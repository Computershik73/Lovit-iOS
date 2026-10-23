//
//  MAXServerConfig.m
//

#import "MAXServerConfig.h"

NSString *const MAXServerDefaultHost = @"api2.oneme.ru";
const NSUInteger MAXServerDefaultPort = 443;

static NSString *const MAXPrefHostKey = @"server_host_override";
static NSString *const MAXPrefPortKey = @"server_port_override";
static NSString *const MAXPrefTrustMincifryKey = @"server_trust_mincifry_ca";

@implementation MAXServerConfig

+ (NSString *)host {
    NSString *stored = [[NSUserDefaults standardUserDefaults] stringForKey:MAXPrefHostKey];
    NSString *trimmed = [stored stringByTrimmingCharactersInSet:
                         [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return trimmed.length > 0 ? trimmed : MAXServerDefaultHost;
}

+ (void)setHost:(NSString *)host {
    [[NSUserDefaults standardUserDefaults] setObject:(host ?: @"") forKey:MAXPrefHostKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

+ (NSUInteger)port {
    NSInteger stored = [[NSUserDefaults standardUserDefaults] integerForKey:MAXPrefPortKey];
    if (stored >= 1 && stored <= 65535) return (NSUInteger)stored;
    return MAXServerDefaultPort;
}

+ (void)setPort:(NSUInteger)port {
    [[NSUserDefaults standardUserDefaults] setInteger:(NSInteger)port forKey:MAXPrefPortKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

+ (BOOL)trustMincifryCa {
    NSNumber *stored = [[NSUserDefaults standardUserDefaults] objectForKey:MAXPrefTrustMincifryKey];
    return stored != nil ? [stored boolValue] : YES;
}

+ (void)setTrustMincifryCa:(BOOL)value {
    [[NSUserDefaults standardUserDefaults] setBool:value forKey:MAXPrefTrustMincifryKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

+ (BOOL)insecureTlsAllowed {
    // Сохранённое значение намеренно не читается: у прежних установок флаг
    // мог остаться включённым, и тогда обновление тихо оставило бы соединение
    // без проверки.
    return NO;
}

+ (void)resetEndpoint {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults removeObjectForKey:MAXPrefHostKey];
    [defaults removeObjectForKey:MAXPrefPortKey];
    [defaults removeObjectForKey:MAXPrefTrustMincifryKey];
    [defaults synchronize];
}

+ (NSTimeInterval)pingInterval { return 10.0; }
+ (NSTimeInterval)requestTimeout { return 30.0; }

@end
