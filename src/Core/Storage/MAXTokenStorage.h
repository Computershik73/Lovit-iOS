//
//  MAXTokenStorage.h
//  Max — токены сессий в Keychain плюс активный аккаунт в NSUserDefaults.
//
//  Порт lib/core/storage/token_storage.dart (flutter_secure_storage → Keychain).
//

#import <Foundation/Foundation.h>

@interface MAXTokenStorage : NSObject

+ (void)saveToken:(NSString *)token forAccount:(long long)accountId;
+ (NSString *)tokenForAccount:(long long)accountId;
+ (void)deleteTokenForAccount:(long long)accountId;

+ (void)setActiveAccountId:(long long)accountId;
+ (void)clearActiveAccount;
/// 0, если активного аккаунта нет.
+ (long long)activeAccountId;
+ (NSString *)activeToken;

+ (void)deleteAccount:(long long)accountId;

@end
