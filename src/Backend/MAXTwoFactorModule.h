//
//  MAXTwoFactorModule.h
//  Max — пароль для входа (двухфакторная аутентификация).
//
//  Порт lib/backend/modules/account/two_factor_module.dart.
//
//  Зачем он понадобился: сервер MAX перестаёт слать код в SMS, когда у
//  аккаунта уже есть сессия, и вместо этого присылает в переписку «Установите
//  пароль, чтобы войти в MAX на новом устройстве». Без пароля второе
//  устройство подключить нельзя вовсе, а поставить его можно только там,
//  где есть действующая сессия, — то есть в самом клиенте.
//
//  Все шаги идут внутри одного «трека» (`trackId`): сервер выдаёт его на
//  AUTH_CREATE_TRACK и по нему связывает проверку пароля, подсказки и почты
//  с итоговым AUTH_SET_2FA. Трек живёт недолго, поэтому получать его надо
//  в начале каждой операции, а не хранить.
//

#import <Foundation/Foundation.h>

typedef void (^MAXTrackCompletion)(NSString *trackId, NSError *error);
typedef void (^MAXTwoFactorCompletion)(NSError *error);

/// Состояние пароля на сервере: включён ли, к какой почте привязан и какая
/// у него подсказка. Почта и подсказка необязательны и часто пусты.
typedef void (^MAXTwoFactorStatusCompletion)(BOOL enabled,
                                             NSString *email,
                                             NSString *hint,
                                             NSError *error);

@interface MAXTwoFactorModule : NSObject

+ (instancetype)shared;

/// AUTH_CREATE_TRACK. С него начинается любая операция ниже.
- (void)createTrackWithCompletion:(MAXTrackCompletion)completion;

/// AUTH_CREATE_TRACK + AUTH_2FA_DETAILS: есть ли пароль и что о нём известно.
- (void)fetchStatusWithCompletion:(MAXTwoFactorStatusCompletion)completion;

/// AUTH_VALIDATE_PASSWORD — сервер проверяет пароль на пригодность (длину
/// и словарные варианты), но ещё не устанавливает его.
- (void)validatePassword:(NSString *)password
                 trackId:(NSString *)trackId
              completion:(MAXTwoFactorCompletion)completion;

/// AUTH_VALIDATE_HINT.
- (void)validateHint:(NSString *)hint
             trackId:(NSString *)trackId
          completion:(MAXTwoFactorCompletion)completion;

/// AUTH_VERIFY_EMAIL — на почту уходит код подтверждения.
- (void)verifyEmail:(NSString *)email
            trackId:(NSString *)trackId
         completion:(MAXTwoFactorCompletion)completion;

/// AUTH_CHECK_EMAIL — код с почты.
- (void)checkEmailCode:(NSString *)code
               trackId:(NSString *)trackId
            completion:(MAXTwoFactorCompletion)completion;

/// AUTH_SET_2FA: пароль устанавливается только этим вызовом, после всех
/// проверок. `hint` и `email` необязательны, но если почта подтверждалась,
/// `withEmail` обязан быть YES — иначе сервер отвергнет набор возможностей.
- (void)confirmWithTrackId:(NSString *)trackId
                  password:(NSString *)password
                      hint:(NSString *)hint
                 withEmail:(BOOL)withEmail
                completion:(MAXTwoFactorCompletion)completion;

/// AUTH_CHECK_PASSWORD — подтверждение текущего пароля перед его сменой
/// или снятием.
- (void)checkCurrentPassword:(NSString *)password
                     trackId:(NSString *)trackId
                  completion:(MAXTwoFactorCompletion)completion;

/// Смена пароля: проверка нового, необязательная подсказка и AUTH_SET_2FA
/// с другим набором возможностей.
- (void)updatePassword:(NSString *)newPassword
                  hint:(NSString *)hint
               trackId:(NSString *)trackId
            completion:(MAXTwoFactorCompletion)completion;

/// AUTH_SET_2FA с `remove2fa` — пароль снимается.
- (void)removePasswordWithTrackId:(NSString *)trackId
                       completion:(MAXTwoFactorCompletion)completion;

@end
