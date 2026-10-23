//
//  MAXTwoFactorModule.m
//

#import "MAXTwoFactorModule.h"
#import "MAXApi.h"
#import "MAXOpcodes.h"
#import "MAXPacket.h"

static NSString *const MAXTwoFactorErrorDomain = @"ru.max.twofactor";

@implementation MAXTwoFactorModule

+ (instancetype)shared {
    static MAXTwoFactorModule *instance = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        instance = [[MAXTwoFactorModule alloc] init];
    });
    return instance;
}

#pragma mark - Вспомогательное

- (BOOL)ensureOnlineForCompletion:(MAXTwoFactorCompletion)failure {
    if ([MAXApi shared].state == MAXSessionStateOnline) return YES;
    failure([NSError errorWithDomain:MAXTwoFactorErrorDomain
                                code:1
                            userInfo:@{NSLocalizedDescriptionKey: @"Нет связи с сервером"}]);
    return NO;
}

+ (NSError *)errorWithMessage:(NSString *)message {
    return [NSError errorWithDomain:MAXTwoFactorErrorDomain
                                code:2
                            userInfo:@{NSLocalizedDescriptionKey: message}];
}

/// Ответ сервера на шагах проверки: пустой или словарь. Ошибка приезжает
/// либо отдельным пакетом (её разбирает MAXApi), либо полем `error` внутри
/// словаря — второе как раз и означает «пароль не годится».
+ (NSError *)errorInPayload:(id)payload {
    if (![payload isKindOfClass:[NSDictionary class]]) return nil;

    NSDictionary *data = payload;
    id error = data[@"error"];
    if (error == nil || error == [NSNull null]) return nil;

    id text = data[@"localizedMessage"] ?: data[@"message"] ?: error;
    return [self errorWithMessage:[text description]];
}

/// Общий вид шага: отправить, разобрать ошибку, доложить.
- (void)sendStep:(NSUInteger)opcode
         payload:(NSDictionary *)payload
      completion:(MAXTwoFactorCompletion)completion {
    if (![self ensureOnlineForCompletion:completion]) return;

    [[MAXApi shared] sendRequestWithOpcode:opcode
                                   payload:payload
                                completion:^(MAXPacket *packet, NSError *error) {
        if (error != nil) {
            completion(error);
            return;
        }
        completion([MAXTwoFactorModule errorInPayload:packet.payload]);
    }];
}

#pragma mark - Трек

- (void)createTrackWithCompletion:(MAXTrackCompletion)completion {
    if (![self ensureOnlineForCompletion:^(NSError *error) { completion(nil, error); }]) return;

    // type: 0 — тот же тип трека, что заводит официальный клиент при входе
    // в раздел пароля.
    [[MAXApi shared] sendRequestWithOpcode:MAXOpcodeAuthCreateTrack
                                   payload:@{@"type": @0}
                                completion:^(MAXPacket *packet, NSError *error) {
        if (error != nil) {
            completion(nil, error);
            return;
        }

        NSDictionary *data = [packet.payload isKindOfClass:[NSDictionary class]]
                             ? packet.payload : nil;
        NSString *trackId = data[@"trackId"];
        if (trackId.length == 0) {
            completion(nil, [MAXTwoFactorModule errorWithMessage:
                             @"Сервер не выдал идентификатор операции"]);
            return;
        }
        completion(trackId, nil);
    }];
}

- (void)fetchStatusWithCompletion:(MAXTwoFactorStatusCompletion)completion {
    [self createTrackWithCompletion:^(NSString *trackId, NSError *error) {
        if (error != nil) {
            completion(NO, nil, nil, error);
            return;
        }

        [[MAXApi shared] sendRequestWithOpcode:MAXOpcodeAuth2faDetails
                                       payload:@{@"trackId": trackId}
                                    completion:^(MAXPacket *packet, NSError *innerError) {
            if (innerError != nil) {
                completion(NO, nil, nil, innerError);
                return;
            }

            NSDictionary *data = [packet.payload isKindOfClass:[NSDictionary class]]
                                 ? packet.payload : nil;
            NSDictionary *password = [data[@"password"] isKindOfClass:[NSDictionary class]]
                                     ? data[@"password"] : nil;

            completion([password[@"enabled"] boolValue],
                       password[@"email"],
                       password[@"hint"],
                       nil);
        }];
    }];
}

#pragma mark - Проверки

- (void)validatePassword:(NSString *)password
                 trackId:(NSString *)trackId
              completion:(MAXTwoFactorCompletion)completion {
    [self sendStep:MAXOpcodeAuthValidatePassword
           payload:@{@"trackId": trackId ?: @"", @"password": password ?: @""}
        completion:completion];
}

- (void)validateHint:(NSString *)hint
             trackId:(NSString *)trackId
          completion:(MAXTwoFactorCompletion)completion {
    [self sendStep:MAXOpcodeAuthValidateHint
           payload:@{@"trackId": trackId ?: @"", @"hint": hint ?: @""}
        completion:completion];
}

- (void)verifyEmail:(NSString *)email
            trackId:(NSString *)trackId
         completion:(MAXTwoFactorCompletion)completion {
    [self sendStep:MAXOpcodeAuthVerifyEmail
           payload:@{@"trackId": trackId ?: @"", @"email": email ?: @""}
        completion:completion];
}

- (void)checkEmailCode:(NSString *)code
               trackId:(NSString *)trackId
            completion:(MAXTwoFactorCompletion)completion {
    [self sendStep:MAXOpcodeAuthCheckEmail
           payload:@{@"trackId": trackId ?: @"", @"verifyCode": code ?: @""}
        completion:completion];
}

- (void)checkCurrentPassword:(NSString *)password
                     trackId:(NSString *)trackId
                  completion:(MAXTwoFactorCompletion)completion {
    [self sendStep:MAXOpcodeAuthCheckPassword
           payload:@{@"trackId": trackId ?: @"", @"password": password ?: @""}
        completion:completion];
}

#pragma mark - Установка

/**
 * Набор возможностей — то, что сервер ждёт в `expectedCapabilities`.
 *
 * Числа взяты из Komet один в один и означают, что именно меняет этот вызов:
 * 0 — пароль ставится впервые, 1 — меняется существующий, 3 — задаётся
 * подсказка, 4 — привязывается почта, 5 — пароль снимается. Список должен
 * совпадать с тем, что на самом деле проверялось в этом треке, иначе сервер
 * отвечает отказом.
 */
- (void)confirmWithTrackId:(NSString *)trackId
                  password:(NSString *)password
                      hint:(NSString *)hint
                 withEmail:(BOOL)withEmail
                completion:(MAXTwoFactorCompletion)completion {
    NSMutableArray *capabilities = [NSMutableArray arrayWithObject:@0];
    if (hint.length > 0) [capabilities addObject:@3];
    if (withEmail) [capabilities addObject:@4];

    NSMutableDictionary *payload = [NSMutableDictionary dictionary];
    payload[@"expectedCapabilities"] = capabilities;
    payload[@"trackId"] = trackId ?: @"";
    payload[@"password"] = password ?: @"";
    if (hint.length > 0) payload[@"hint"] = hint;

    [self sendStep:MAXOpcodeAuthSet2fa payload:payload completion:completion];
}

- (void)updatePassword:(NSString *)newPassword
                  hint:(NSString *)hint
               trackId:(NSString *)trackId
            completion:(MAXTwoFactorCompletion)completion {
    __weak MAXTwoFactorModule *weakSelf = self;

    [self validatePassword:newPassword trackId:trackId completion:^(NSError *error) {
        MAXTwoFactorModule *strongSelf = weakSelf;
        if (strongSelf == nil) return;
        if (error != nil) {
            completion(error);
            return;
        }

        void (^finish)(void) = ^{
            NSMutableArray *capabilities = [NSMutableArray arrayWithObject:@1];
            if (hint.length > 0) [capabilities addObject:@3];

            NSMutableDictionary *payload = [NSMutableDictionary dictionary];
            payload[@"expectedCapabilities"] = capabilities;
            payload[@"trackId"] = trackId ?: @"";
            payload[@"password"] = newPassword ?: @"";
            if (hint.length > 0) payload[@"hint"] = hint;

            [strongSelf sendStep:MAXOpcodeAuthSet2fa payload:payload completion:completion];
        };

        if (hint.length == 0) {
            finish();
            return;
        }

        [strongSelf validateHint:hint trackId:trackId completion:^(NSError *hintError) {
            if (hintError != nil) {
                completion(hintError);
                return;
            }
            finish();
        }];
    }];
}

- (void)removePasswordWithTrackId:(NSString *)trackId
                       completion:(MAXTwoFactorCompletion)completion {
    [self sendStep:MAXOpcodeAuthSet2fa
           payload:@{@"expectedCapabilities": @[@5],
                     @"trackId": trackId ?: @"",
                     @"remove2fa": @YES}
        completion:completion];
}

@end
