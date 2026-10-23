//
//  MAXDeviceIdentity.m
//

#import "MAXDeviceIdentity.h"
#import "MAXSecureStore.h"

static NSString *const MAXInstanceIdKey = @"mt_instance_id";
static NSString *const MAXDeviceIdKey = @"device_id_local";

@implementation MAXDeviceIdentity

+ (NSString *)randomHexWithByteCount:(NSUInteger)byteCount {
    NSMutableString *hex = [NSMutableString stringWithCapacity:byteCount * 2];
    for (NSUInteger i = 0; i < byteCount; i++) {
        [hex appendFormat:@"%02x", (unsigned int)(arc4random_uniform(256))];
    }
    return hex;
}

+ (NSString *)uuidV4 {
    CFUUIDRef uuid = CFUUIDCreate(kCFAllocatorDefault);
    NSString *string = (__bridge_transfer NSString *)CFUUIDCreateString(kCFAllocatorDefault, uuid);
    CFRelease(uuid);
    return [string lowercaseString];
}

+ (long long)randomClientSessionId {
    return (long long)(arc4random_uniform(0x7FFFFFFF) + 1);
}

/**
 * Оба идентификатора живут в MAXSecureStore, а не в настройках, и это не
 * про безопасность, а про то, чтобы вход не слетал.
 *
 * deviceId и instanceId уходят в SESSION_INIT: для сервера это и есть
 * устройство, на котором открыта сессия. Пока они лежали в NSUserDefaults,
 * переустановка стирала их вместе с контейнером, и приложение, даже сохранив
 * токен, представлялось совершенно другим устройством.
 *
 * Значения из прежних сборок подхватываются из настроек и переносятся —
 * поэтому у тех, кто обновляется, устройство остаётся прежним.
 */
+ (NSString *)persistentValueForKey:(NSString *)key generator:(NSString *(^)(void))generator {
    NSString *stored = [MAXSecureStore stringForKey:key];
    if (stored.length > 0) return stored;

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *legacy = [defaults stringForKey:key];
    if (legacy.length > 0) {
        [MAXSecureStore setString:legacy forKey:key];
        [defaults removeObjectForKey:key];
        [defaults synchronize];
        return legacy;
    }

    NSString *generated = generator();
    [MAXSecureStore setString:generated forKey:key];
    return generated;
}

+ (NSString *)deviceId {
    return [self persistentValueForKey:MAXDeviceIdKey generator:^NSString *{
        return [self randomHexWithByteCount:8];
    }];
}

+ (NSString *)instanceId {
    return [self persistentValueForKey:MAXInstanceIdKey generator:^NSString *{
        return [self uuidV4];
    }];
}

+ (long long)clientSessionId {
    static long long sessionId = 0;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        sessionId = [self randomClientSessionId];
    });
    return sessionId;
}

+ (void)regenerate {
    [MAXSecureStore setString:[self randomHexWithByteCount:8] forKey:MAXDeviceIdKey];
    [MAXSecureStore setString:[self uuidV4] forKey:MAXInstanceIdKey];
}

@end
