//
//  MAXAccountModule.m
//

#import "MAXAccountModule.h"
#import "MAXApi.h"
#import "MAXOpcodes.h"
#import "MAXPacket.h"
#import "MAXSettings.h"
#import "MAXProfile.h"
#import "MAXTokenStorage.h"
#import "MAXSpoofingService.h"
#import "MAXChatCacheFingerprint.h"
#import "MAXContactsCache.h"
#import "MAXStickersModule.h"
#import "MAXTranscripts.h"

NSString *const MAXAccountErrorDomain = @"ru.max.account";
const NSInteger MAXAccountErrorStaleSession = 20;

/// Приметы протухшего входа в тексте отказа. Своего кода у него нет, и
/// узнаётся он ровно так же, как в Komet и в клиенте под Windows Phone.
static BOOL MAXStaleAuthText(NSString *text) {
    NSString *lower = [text lowercaseString];
    return [lower rangeOfString:@"состояние сессии"].location != NSNotFound
        || [lower rangeOfString:@"сессия не найдена"].location != NSNotFound
        || [lower rangeOfString:@"авторизационная сессия"].location != NSNotFound;
}

static BOOL MAXIsStaleAuthPacket(MAXPacket *packet) {
    if (![packet.payload isKindOfClass:[NSDictionary class]]) return NO;
    NSDictionary *map = (NSDictionary *)packet.payload;

    id code = map[@"message"];
    if ([code isEqual:@"FAIL_LOGIN_TOKEN"] || [code isEqual:@"FAIL_WRONG_PASSWORD"]) return YES;

    for (NSString *key in @[@"localizedMessage", @"title", @"message"]) {
        id value = map[key];
        if ([value isKindOfClass:[NSString class]] && MAXStaleAuthText(value)) return YES;
    }
    return NO;
}

/// Отказ шага входа: протухший — своим кодом, всякий другой — как пришёл.
static NSError *MAXAuthError(MAXPacket *packet, NSError *error) {
    if (!MAXIsStaleAuthPacket(packet)) return error;

    NSString *text = error.localizedDescription;
    if (text.length == 0) text = @"Вход устарел";

    return [NSError errorWithDomain:MAXAccountErrorDomain
                               code:MAXAccountErrorStaleSession
                           userInfo:@{NSLocalizedDescriptionKey: text}];
}

static NSString *MAXNormalizeAuthPhone(NSString *phone) {
    NSMutableString *digits = [NSMutableString string];
    for (NSUInteger i = 0; i < phone.length; i++) {
        unichar c = [phone characterAtIndex:i];
        if (c >= '0' && c <= '9') [digits appendFormat:@"%C", c];
    }
    return [NSString stringWithFormat:@"+%@", digits];
}

@interface MAXAccountModule ()
+ (NSError *)wrongPasswordError;
@end

@implementation MAXAccountModule {
    BOOL _loggedIn;
}

+ (instancetype)shared {
    static MAXAccountModule *instance = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        instance = [[MAXAccountModule alloc] init];
    });
    return instance;
}

- (id)init {
    self = [super init];
    if (self) {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(sessionStateChanged:)
                                                     name:MAXApiStateDidChangeNotification
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)sessionStateChanged:(NSNotification *)note {
    if ([MAXApi shared].state != MAXSessionStateOnline) _loggedIn = NO;
}

- (BOOL)isLoggedIn { return _loggedIn; }

#pragma mark - Отпечаток сборки

/// Отпечаток «настоящего» Android-клиента: считается из callsSeed хэндшейка
/// и deviceId. Без него сервер видит неизвестную сборку.
- (NSData *)chatCacheFingerprint {
    MAXApi *api = [MAXApi shared];
    if (!api.hasCallsSeed || api.deviceId.length == 0) return nil;
    return [MAXChatCacheFingerprint computeWithCallsSeed:api.callsSeed deviceId:api.deviceId];
}

#pragma mark - Запрос кода

- (void)requestCodeForPhone:(NSString *)phone completion:(MAXTokenCompletion)completion {
    [self requestCodeForPhone:phone type:@"START_AUTH" completion:completion];
}

- (void)resendCodeForPhone:(NSString *)phone completion:(MAXTokenCompletion)completion {
    [self requestCodeForPhone:phone type:@"RESEND" completion:completion];
}

- (void)requestCodeForPhone:(NSString *)phone
                       type:(NSString *)type
                 completion:(MAXTokenCompletion)completion {
    if (![self ensureOnlineForCompletion:^(NSError *error) { completion(nil, error); }]) return;

    NSMutableDictionary *payload = [NSMutableDictionary dictionary];
    payload[@"phone"] = MAXNormalizeAuthPhone(phone);
    payload[@"type"] = type;
    payload[@"language"] = @"ru";

    NSData *fingerprint = [self chatCacheFingerprint];
    if (fingerprint != nil) payload[@"mode"] = fingerprint;

    [[MAXApi shared] sendRequestWithOpcode:MAXOpcodeAuthRequest
                                   payload:payload
                                completion:^(MAXPacket *packet, NSError *error) {
        if (error != nil) {
            completion(nil, MAXAuthError(packet, error));
            return;
        }

        NSString *token = packet.payloadMap[@"token"];
        if (![token isKindOfClass:[NSString class]] || token.length == 0) {
            completion(nil, [NSError errorWithDomain:MAXAccountErrorDomain
                                                code:10
                                            userInfo:@{NSLocalizedDescriptionKey:
                                                @"Сервер не вернул токен"}]);
            return;
        }
        completion(token, nil);
    }];
}

#pragma mark - Проверка кода

- (void)verifyCode:(NSString *)code
             token:(NSString *)token
        completion:(MAXVerifyCompletion)completion {
    if (![self ensureOnlineForCompletion:^(NSError *error) { completion(nil, error); }]) return;

    NSDictionary *payload = @{
        @"token": token ?: @"",
        @"verifyCode": code ?: @"",
        @"authTokenType": @"CHECK_CODE"
    };

    [[MAXApi shared] sendRequestWithOpcode:MAXOpcodeAuth
                                   payload:payload
                                completion:^(MAXPacket *packet, NSError *error) {
        if (error != nil) {
            completion(nil, MAXAuthError(packet, error));
            return;
        }

        NSDictionary *data = packet.payloadMap;
        NSString *loginToken = [MAXAccountModule nestedTokenFromPayload:data key:@"LOGIN"];
        NSString *registerToken = [MAXAccountModule nestedTokenFromPayload:data key:@"REGISTER"];
        NSString *sessionToken = loginToken ?: registerToken;

        long long accountId = [MAXAccountModule extractAccountId:data];

        if (sessionToken != nil && accountId != 0) {
            [MAXTokenStorage saveToken:sessionToken forAccount:accountId];
            [MAXTokenStorage setActiveAccountId:accountId];
            [MAXSpoofingService commitPendingSpoofForAccount:accountId];
        }

        completion(data, nil);
    }];
}

#pragma mark - Пароль второго фактора

- (void)checkPassword:(NSString *)password
              trackId:(NSString *)trackId
           completion:(MAXPasswordCompletion)completion {
    if (![self ensureOnlineForCompletion:^(NSError *error) { completion(nil, 0, error); }]) return;

    NSDictionary *payload = @{
        @"trackId": trackId ?: @"",
        @"password": password ?: @""
    };

    [[MAXApi shared] sendRequestWithOpcode:MAXOpcodeAuthLoginCheckPassword
                                   payload:payload
                                completion:^(MAXPacket *packet, NSError *error) {
        if (error != nil) {
            // На неверный пароль сервер отвечает пакетом-ошибкой с message =
            // FAIL_WRONG_PASSWORD, а общий разбор превращает его в текст про
            // отвергнутый токен: то же имя ошибки приходит и на негодный токен
            // LOGIN. Здесь опкод известен, значит и смысл однозначен.
            id message = [packet.payload isKindOfClass:[NSDictionary class]]
                         ? ((NSDictionary *)packet.payload)[@"message"] : nil;
            if ([message isEqual:@"FAIL_WRONG_PASSWORD"]) {
                completion(nil, 0, [MAXAccountModule wrongPasswordError]);
                return;
            }
            completion(nil, 0, MAXAuthError(packet, error));
            return;
        }

        NSDictionary *data = packet.payloadMap;

        // Отказ приходит и вторым способом — обычным ответом с полем error.
        if (data[@"error"] != nil) {
            completion(nil, 0, [MAXAccountModule wrongPasswordError]);
            return;
        }

        NSString *loginToken = [MAXAccountModule nestedTokenFromPayload:data key:@"LOGIN"];
        if (loginToken.length == 0) {
            completion(nil, 0, [NSError errorWithDomain:MAXAccountErrorDomain
                                                    code:16
                                                userInfo:@{NSLocalizedDescriptionKey:
                                                    @"Пароль принят, но токен входа не пришёл"}]);
            return;
        }

        long long accountId = [MAXAccountModule extractAccountId:data];
        if (accountId == 0) {
            completion(nil, 0, [NSError errorWithDomain:MAXAccountErrorDomain
                                                    code:17
                                                userInfo:@{NSLocalizedDescriptionKey:
                                                    @"В ответе нет id аккаунта"}]);
            return;
        }

        [MAXTokenStorage saveToken:loginToken forAccount:accountId];
        [MAXTokenStorage setActiveAccountId:accountId];
        [MAXSpoofingService commitPendingSpoofForAccount:accountId];

        completion(loginToken, accountId, nil);
    }];
}

+ (NSError *)wrongPasswordError {
    return [NSError errorWithDomain:MAXAccountErrorDomain
                               code:15
                           userInfo:@{NSLocalizedDescriptionKey: @"Неверный пароль"}];
}

#pragma mark - Регистрация

- (void)completeRegistrationWithToken:(NSString *)token
                            firstName:(NSString *)firstName
                             lastName:(NSString *)lastName
                           completion:(MAXVerifyCompletion)completion {
    if (![self ensureOnlineForCompletion:^(NSError *error) { completion(nil, error); }]) return;

    NSMutableDictionary *payload = [NSMutableDictionary dictionary];
    payload[@"token"] = token ?: @"";
    payload[@"tokenType"] = @"REGISTER";
    payload[@"firstName"] = firstName ?: @"";
    if (lastName.length > 0) payload[@"lastName"] = lastName;

    [[MAXApi shared] sendRequestWithOpcode:MAXOpcodeAuthConfirm
                                   payload:payload
                                completion:^(MAXPacket *packet, NSError *error) {
        if (error != nil) {
            completion(nil, MAXAuthError(packet, error));
            return;
        }

        NSDictionary *data = packet.payloadMap;
        long long accountId = [MAXAccountModule extractAccountId:data];
        if (accountId == 0) {
            completion(nil, [NSError errorWithDomain:MAXAccountErrorDomain
                                                code:11
                                            userInfo:@{NSLocalizedDescriptionKey:
                                                @"В ответе нет id аккаунта"}]);
            return;
        }

        // Профиль создан — сессия продолжается токеном, который сервер
        // выдаёт здесь же либо оставляет прежним, регистрационным. Без этой
        // записи вход сразу после создания профиля упирался в «токен не
        // сохранён»: у номера, которого в MAX ещё не было, id аккаунта на
        // шаге кода неизвестен, и класть токен там было некуда.
        NSString *loginToken = [MAXAccountModule nestedTokenFromPayload:data key:@"LOGIN"];
        if (loginToken.length == 0) loginToken = token;
        if (loginToken.length > 0) [MAXTokenStorage saveToken:loginToken forAccount:accountId];

        [MAXTokenStorage setActiveAccountId:accountId];
        [MAXSpoofingService commitPendingSpoofForAccount:accountId];
        completion(data, nil);
    }];
}

#pragma mark - Вход

/// Порт buildLoginPayload. exp.chatsCountGroups — бинарь, который шлёт
/// оригинальный клиент; отпечаток сборки идёт отдельным полем.
- (NSDictionary *)buildLoginPayloadWithToken:(NSString *)token interactive:(BOOL)interactive {
    uint8_t chatsCountGroups[2] = {0x0b, 0x32};

    NSMutableDictionary *payload = [NSMutableDictionary dictionary];
    payload[@"token"] = token ?: @"";
    payload[@"interactive"] = @(interactive);
    payload[@"exp"] = @{@"chatsCountGroups": [NSData dataWithBytes:chatsCountGroups length:2]};
    payload[@"presenceSync"] = @(-1);
    payload[@"chatsSync"] = @(-1);

    NSData *fingerprint = [self chatCacheFingerprint];
    if (fingerprint != nil) payload[@"chatCacheFingerprint"] = fingerprint;

    return payload;
}

- (void)loginWithCompletion:(MAXLoginCompletion)completion {
    long long accountId = [MAXTokenStorage activeAccountId];
    NSString *token = accountId != 0 ? [MAXTokenStorage tokenForAccount:accountId] : nil;

    if (token == nil) {
        completion(nil, nil, [NSError errorWithDomain:MAXAccountErrorDomain
                                                 code:12
                                             userInfo:@{NSLocalizedDescriptionKey:
                                                 @"Нет сохранённого токена"}]);
        return;
    }
    [self loginWithToken:token accountId:accountId completion:completion];
}

- (void)loginWithToken:(NSString *)token
             accountId:(long long)accountId
            completion:(MAXLoginCompletion)completion {
    if (![self ensureOnlineForCompletion:^(NSError *error) { completion(nil, nil, error); }]) return;

    NSDictionary *payload = [self buildLoginPayloadWithToken:token
                                                 interactive:[MAXSettings interactive]];

    [[MAXApi shared] sendRequestWithOpcode:MAXOpcodeLogin
                                   payload:payload
                                completion:^(MAXPacket *packet, NSError *error) {
        if (error != nil) {
            completion(nil, nil, error);
            return;
        }

        NSDictionary *data = packet.payloadMap;

        long long resolvedId = accountId;
        if (resolvedId == 0) {
            resolvedId = [MAXAccountModule extractAccountId:data];
            if (resolvedId == 0) {
                completion(nil, nil, [NSError errorWithDomain:MAXAccountErrorDomain
                                                         code:13
                                                     userInfo:@{NSLocalizedDescriptionKey:
                                                         @"Не удалось определить аккаунт"}]);
                return;
            }
            [MAXTokenStorage saveToken:token forAccount:resolvedId];
            [MAXTokenStorage setActiveAccountId:resolvedId];
            [MAXSpoofingService commitPendingSpoofForAccount:resolvedId];
        }

        NSString *updatedToken = data[@"token"];
        if ([updatedToken isKindOfClass:[NSString class]] && updatedToken.length > 0) {
            [MAXTokenStorage saveToken:updatedToken forAccount:resolvedId];
        }

        self->_loggedIn = YES;

        MAXProfile *profile = [MAXProfile profileFromServerProfile:data[@"profile"]];
        if (profile == nil) {
            profile = [[MAXProfile alloc] init];
            profile.profileId = resolvedId;
            profile.firstName = @"";
        }

        completion(data, profile, nil);
    }];
}

#pragma mark - Выход

- (void)logoutWithCompletion:(MAXVoidCompletion)completion {
    long long accountId = [MAXTokenStorage activeAccountId];

    void (^finish)(void) = ^{
        self->_loggedIn = NO;
        [[MAXStickersModule shared] reset];
    [[MAXTranscripts shared] reset];
        [[MAXApi shared] disconnect];
        if (accountId != 0) {
            [MAXTokenStorage deleteAccount:accountId];
            [MAXSpoofingService clearSpoofForAccount:accountId];
            [MAXContactsCache clearForAccount:accountId];
        }
        if (completion != nil) completion(nil);
    };

    if ([MAXApi shared].state != MAXSessionStateOnline) {
        finish();
        return;
    }

    [[MAXApi shared] sendRequestWithOpcode:MAXOpcodeLogout
                                   payload:@{}
                                    silent:YES
                                completion:^(MAXPacket *packet, NSError *error) {
        finish();
    }];
}

- (void)beginAddAccount {
    NSMutableArray *existing = [NSMutableArray array];
    long long active = [MAXTokenStorage activeAccountId];
    if (active != 0) [existing addObject:@(active)];

    [MAXSpoofingService prepareNewAccountSpoofExcludingAccountIds:existing];
    [[MAXApi shared] disconnect];
    [MAXTokenStorage clearActiveAccount];
    _loggedIn = NO;
}

#pragma mark - Вспомогательное

- (BOOL)ensureOnlineForCompletion:(void (^)(NSError *error))failure {
    if ([MAXApi shared].state == MAXSessionStateOnline) return YES;
    failure([NSError errorWithDomain:MAXAccountErrorDomain
                                code:14
                            userInfo:@{NSLocalizedDescriptionKey: @"Сессия не онлайн"}]);
    return NO;
}

+ (NSString *)nestedTokenFromPayload:(NSDictionary *)payload key:(NSString *)key {
    id attrs = payload[@"tokenAttrs"];
    if (![attrs isKindOfClass:[NSDictionary class]]) return nil;

    id entry = ((NSDictionary *)attrs)[key];
    if (![entry isKindOfClass:[NSDictionary class]]) return nil;

    id token = ((NSDictionary *)entry)[@"token"];
    return [token isKindOfClass:[NSString class]] ? token : nil;
}

+ (BOOL)isStaleSessionError:(NSError *)error {
    return [error.domain isEqualToString:MAXAccountErrorDomain]
        && error.code == MAXAccountErrorStaleSession;
}

+ (NSDictionary *)passwordChallengeFromPayload:(NSDictionary *)payload {
    if (![payload isKindOfClass:[NSDictionary class]]) return nil;
    id challenge = payload[@"passwordChallenge"];
    return [challenge isKindOfClass:[NSDictionary class]] ? challenge : nil;
}

+ (long long)coerceAccountId:(id)value {
    if ([value isKindOfClass:[NSNumber class]]) return [value longLongValue];
    if ([value isKindOfClass:[NSString class]]) return [value longLongValue];
    return 0;
}

+ (long long)extractAccountId:(NSDictionary *)response {
    if (![response isKindOfClass:[NSDictionary class]]) return 0;

    id profile = response[@"profile"];
    if ([profile isKindOfClass:[NSDictionary class]]) {
        id contact = ((NSDictionary *)profile)[@"contact"];
        if ([contact isKindOfClass:[NSDictionary class]]) {
            for (NSString *key in @[@"id", @"contactId", @"accountId"]) {
                long long value = [self coerceAccountId:((NSDictionary *)contact)[key]];
                if (value != 0) return value;
            }
        }
        for (NSString *key in @[@"id", @"accountId"]) {
            long long value = [self coerceAccountId:((NSDictionary *)profile)[key]];
            if (value != 0) return value;
        }
    }

    id contact = response[@"contact"];
    if ([contact isKindOfClass:[NSDictionary class]]) {
        for (NSString *key in @[@"id", @"contactId"]) {
            long long value = [self coerceAccountId:((NSDictionary *)contact)[key]];
            if (value != 0) return value;
        }
    }

    id account = response[@"account"];
    if ([account isKindOfClass:[NSDictionary class]]) {
        for (NSString *key in @[@"id", @"accountId"]) {
            long long value = [self coerceAccountId:((NSDictionary *)account)[key]];
            if (value != 0) return value;
        }
    }

    long long value = [self coerceAccountId:response[@"accountId"]];
    if (value != 0) return value;
    return [self coerceAccountId:response[@"account_id"]];
}

@end
