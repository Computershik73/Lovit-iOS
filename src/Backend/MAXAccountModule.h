//
//  MAXAccountModule.h
//  Max — авторизация и вход.
//
//  Порт lib/backend/modules/account.dart.
//

#import <Foundation/Foundation.h>

@class MAXProfile;

extern NSString *const MAXAccountErrorDomain;

/// Незаконченный вход у сервера протух: тот же ключ второй раз не примут,
/// сколько ни повторяй. Единственный выход — начать шаг заново.
extern const NSInteger MAXAccountErrorStaleSession;

typedef void (^MAXTokenCompletion)(NSString *token, NSError *error);
typedef void (^MAXVerifyCompletion)(NSDictionary *payload, NSError *error);
typedef void (^MAXLoginCompletion)(NSDictionary *payload, MAXProfile *profile, NSError *error);
typedef void (^MAXVoidCompletion)(NSError *error);
typedef void (^MAXPasswordCompletion)(NSString *loginToken, long long accountId, NSError *error);

@interface MAXAccountModule : NSObject

+ (instancetype)shared;

/// true после успешного LOGIN (опкод 19), а не просто после хэндшейка.
@property (nonatomic, readonly) BOOL isLoggedIn;

/// AUTH_REQUEST с типом START_AUTH. Возвращает временный токен.
- (void)requestCodeForPhone:(NSString *)phone completion:(MAXTokenCompletion)completion;

/// AUTH_REQUEST с типом RESEND.
- (void)resendCodeForPhone:(NSString *)phone completion:(MAXTokenCompletion)completion;

/// AUTH: проверка кода. В payload приходит tokenAttrs.LOGIN/REGISTER.
- (void)verifyCode:(NSString *)code
             token:(NSString *)token
        completion:(MAXVerifyCompletion)completion;

/// AUTH_LOGIN_CHECK_PASSWORD: второй шаг входа, когда у аккаунта включена
/// двухфакторная аутентификация. Вместо токена AUTH отдаёт passwordChallenge,
/// и токен выдаётся уже в ответ на пароль.
- (void)checkPassword:(NSString *)password
              trackId:(NSString *)trackId
           completion:(MAXPasswordCompletion)completion;

/// AUTH_CONFIRM: завершение регистрации нового профиля.
- (void)completeRegistrationWithToken:(NSString *)token
                            firstName:(NSString *)firstName
                             lastName:(NSString *)lastName
                           completion:(MAXVerifyCompletion)completion;

/// LOGIN по сохранённому токену активного аккаунта.
- (void)loginWithCompletion:(MAXLoginCompletion)completion;

/// LOGIN по конкретному токену.
- (void)loginWithToken:(NSString *)token
             accountId:(long long)accountId
            completion:(MAXLoginCompletion)completion;

/// LOGOUT и локальная очистка.
- (void)logoutWithCompletion:(MAXVoidCompletion)completion;

/// Сбрасывает активный аккаунт и готовит новый профиль подмены.
- (void)beginAddAccount;

/// Извлекает id аккаунта из ответа сервера (несколько возможных мест).
+ (long long)extractAccountId:(NSDictionary *)response;

/// Токены из tokenAttrs: ключи LOGIN и REGISTER.
+ (NSString *)nestedTokenFromPayload:(NSDictionary *)payload key:(NSString *)key;

/// Отказ ли это оттого, что незаконченный вход у сервера протух.
///
/// Своего кода у такого отказа нет. Машинными словами сервер отвечает лишь
/// `FAIL_LOGIN_TOKEN` и `FAIL_WRONG_PASSWORD`, а «недопустимое состояние
/// сессии» приходит текстом — его и Komet узнаёт по словам. Оба машинных
/// слова здесь значат отклонённый ключ: неверный пароль сервер отдаёт не
/// отказом, а обычным ответом с полем `error` внутри.
+ (BOOL)isStaleSessionError:(NSError *)error;

/// passwordChallenge из ответа AUTH: сервер просит пароль вместо выдачи токена.
/// Внутри — trackId для AUTH_LOGIN_CHECK_PASSWORD и необязательная подсказка.
+ (NSDictionary *)passwordChallengeFromPayload:(NSDictionary *)payload;

@end
