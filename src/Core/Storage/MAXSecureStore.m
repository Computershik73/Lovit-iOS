//
//  MAXSecureStore.m
//

#import "MAXSecureStore.h"
#import <Security/Security.h>

static NSString *const MAXKeychainService = @"ru.computershik.scam";

/// Префикс запасного хранения в NSUserDefaults — чтобы эти записи не путались
/// с обычными настройками и чтобы их можно было опознать при разборе.
static NSString *const MAXFallbackPrefix = @"secure_";

@implementation MAXSecureStore

+ (NSMutableDictionary *)queryForKey:(NSString *)key {
    NSMutableDictionary *query = [NSMutableDictionary dictionary];
    query[(__bridge id)kSecClass] = (__bridge id)kSecClassGenericPassword;
    query[(__bridge id)kSecAttrService] = MAXKeychainService;
    query[(__bridge id)kSecAttrAccount] = key;
    return query;
}

#pragma mark - Запись

+ (BOOL)setString:(NSString *)value forKey:(NSString *)key {
    if (key.length == 0) return NO;

    if (value == nil) {
        [self removeKey:key];
        return YES;
    }

    NSMutableDictionary *query = [self queryForKey:key];
    SecItemDelete((__bridge CFDictionaryRef)query);

    query[(__bridge id)kSecValueData] = [value dataUsingEncoding:NSUTF8StringEncoding];
    // AfterFirstUnlock, а не WhenUnlocked: сессия поднимается и в фоне,
    // когда экран заблокирован.
    query[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleAfterFirstUnlock;

    OSStatus status = SecItemAdd((__bridge CFDictionaryRef)query, NULL);

    if (status == errSecSuccess) {
        // Запись могла раньше уйти в запасное хранилище — убираем дубль,
        // чтобы не осталось двух источников правды.
        [[NSUserDefaults standardUserDefaults]
         removeObjectForKey:[MAXFallbackPrefix stringByAppendingString:key]];
        [[NSUserDefaults standardUserDefaults] synchronize];
        return YES;
    }

    NSLog(@"[Max/Store] Keychain отказал для «%@» (status=%d) — пишу в настройки, "
          @"переустановку такая запись не переживёт", key, (int)status);

    [[NSUserDefaults standardUserDefaults]
     setObject:value forKey:[MAXFallbackPrefix stringByAppendingString:key]];
    [[NSUserDefaults standardUserDefaults] synchronize];
    return NO;
}

#pragma mark - Чтение

+ (NSString *)stringForKey:(NSString *)key {
    if (key.length == 0) return nil;

    NSMutableDictionary *query = [self queryForKey:key];
    query[(__bridge id)kSecReturnData] = (id)kCFBooleanTrue;
    query[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;

    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);

    if (status == errSecSuccess && result != NULL) {
        NSData *data = (__bridge_transfer NSData *)result;
        NSString *value = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (value != nil) return value;
    }

    return [[NSUserDefaults standardUserDefaults]
            stringForKey:[MAXFallbackPrefix stringByAppendingString:key]];
}

+ (void)removeKey:(NSString *)key {
    if (key.length == 0) return;

    SecItemDelete((__bridge CFDictionaryRef)[self queryForKey:key]);
    [[NSUserDefaults standardUserDefaults]
     removeObjectForKey:[MAXFallbackPrefix stringByAppendingString:key]];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

+ (NSArray *)keysWithPrefix:(NSString *)prefix {
    NSMutableSet *keys = [NSMutableSet set];

    NSMutableDictionary *query = [NSMutableDictionary dictionary];
    query[(__bridge id)kSecClass] = (__bridge id)kSecClassGenericPassword;
    query[(__bridge id)kSecAttrService] = MAXKeychainService;
    query[(__bridge id)kSecReturnAttributes] = (id)kCFBooleanTrue;
    query[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitAll;

    CFTypeRef result = NULL;
    if (SecItemCopyMatching((__bridge CFDictionaryRef)query, &result) == errSecSuccess
        && result != NULL) {
        NSArray *items = (__bridge_transfer NSArray *)result;
        for (NSDictionary *item in items) {
            NSString *account = item[(__bridge id)kSecAttrAccount];
            if ([account isKindOfClass:[NSString class]] && [account hasPrefix:prefix]) {
                [keys addObject:account];
            }
        }
    }

    NSString *fallbackPrefix = [MAXFallbackPrefix stringByAppendingString:prefix];
    NSDictionary *defaults = [[NSUserDefaults standardUserDefaults] dictionaryRepresentation];
    for (NSString *key in defaults) {
        if ([key hasPrefix:fallbackPrefix]) {
            [keys addObject:[key substringFromIndex:MAXFallbackPrefix.length]];
        }
    }

    return [keys allObjects];
}

#pragma mark - Диагностика

+ (BOOL)keychainAvailable {
    static BOOL available = NO;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *probe = @"__probe__";

        NSMutableDictionary *query = [self queryForKey:probe];
        SecItemDelete((__bridge CFDictionaryRef)query);
        query[(__bridge id)kSecValueData] = [@"1" dataUsingEncoding:NSUTF8StringEncoding];
        query[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleAfterFirstUnlock;

        available = SecItemAdd((__bridge CFDictionaryRef)query, NULL) == errSecSuccess;
        SecItemDelete((__bridge CFDictionaryRef)[self queryForKey:probe]);
    });
    return available;
}

+ (NSString *)storageDescription {
    return [self keychainAvailable]
        ? @"Keychain — переустановку переживёт"
        : @"Настройки приложения — переустановка сбросит вход";
}

@end
