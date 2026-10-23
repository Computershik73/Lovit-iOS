//
//  MAXServerConfig.h
//  Max — адрес сервера и таймауты.
//
//  Порт lib/core/config/config.dart.
//

#import <Foundation/Foundation.h>

extern NSString *const MAXServerDefaultHost;    // api2.oneme.ru
extern const NSUInteger MAXServerDefaultPort;   // 443

@interface MAXServerConfig : NSObject

+ (NSString *)host;
+ (void)setHost:(NSString *)host;

+ (NSUInteger)port;
+ (void)setPort:(NSUInteger)port;

/// Подставлять вшитые корни НУЦ Минцифры дополнительным якорем при проверке
/// цепочки. По умолчанию включено: `api2.oneme.ru` удостоверяется именно ими,
/// а в хранилище iOS их нет. Цепочка при этом проверяется полностью —
/// в отличие от Komet, где тот же флаг снимал проверку целиком.
+ (BOOL)trustMincifryCa;
+ (void)setTrustMincifryCa:(BOOL)value;

/// Отладочный режим «принимать любой сертификат» (dev_tls_insecure в Komet).
///
/// Всегда NO, и переключателя к нему нет. Проверка цепочки — единственное,
/// что стоит между перепиской и любым, кто окажется на пути пакетов; флажок
/// в настройках, снимающий её целиком, слишком легко включить и невозможно
/// заметить потом. Соединение с подставным сертификатом должно не работать,
/// а не «работать с предупреждением».
+ (BOOL)insecureTlsAllowed;

+ (void)resetEndpoint;

+ (NSTimeInterval)pingInterval;      // 10 c
+ (NSTimeInterval)requestTimeout;    // 30 c

@end
