//
//  MAXSecureStore.h
//  Max — хранилище, переживающее переустановку.
//
//  Всё, что привязывает установку к аккаунту, обязано лежать здесь, а не
//  в NSUserDefaults: настройки уезжают вместе с контейнером приложения,
//  Keychain — нет.
//
//  Список того, что сюда переехало, и почему каждое:
//
//    auth_token_<id>       токен сессии;
//    active_account_id     какой из токенов сейчас в деле — без него токен
//                          есть, но найти его некому;
//    device_id_local       deviceId в SESSION_INIT;
//    mt_instance_id        instanceId там же;
//    spoof_profile_<scope> профиль подмены.
//
//  Три последних — это «лицо» устройства для сервера. Если после переустановки
//  они другие, а токен прежний, сессия выглядит угнанной, и её вправе оборвать
//  уже сервер — то есть потеря настроек ломает вход даже при живом токене.
//
//  Если Keychain недоступен (на джейлбрейке это зависит от прав в подписи),
//  запись уходит в NSUserDefaults — приложение продолжает работать, но
//  переустановку такая запись уже не переживёт. Что именно случилось, видно
//  в журнале и в +storageDescription.
//

#import <Foundation/Foundation.h>

@interface MAXSecureStore : NSObject

+ (BOOL)setString:(NSString *)value forKey:(NSString *)key;
+ (NSString *)stringForKey:(NSString *)key;
+ (void)removeKey:(NSString *)key;

/// Все ключи, начинающиеся с префикса. Нужно, чтобы найти уцелевший токен,
/// когда указатель на активный аккаунт потерян.
+ (NSArray *)keysWithPrefix:(NSString *)prefix;

/// Работает ли Keychain на самом деле — проверяется пробной записью.
+ (BOOL)keychainAvailable;

/// Строка для экрана «О приложении»: где на деле лежат токены.
+ (NSString *)storageDescription;

@end
