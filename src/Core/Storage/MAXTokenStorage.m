//
//  MAXTokenStorage.m
//

#import "MAXTokenStorage.h"
#import "MAXSecureStore.h"

static NSString *const MAXTokenPrefix = @"auth_token_";
static NSString *const MAXActiveAccountKey = @"active_account_id";

/// Ключ, под которым активный аккаунт лежал раньше — в NSUserDefaults.
/// Оставлен ради тех установок, что заводились до переезда в Keychain.
static NSString *const MAXLegacyActiveAccountKey = @"active_account_id";

@implementation MAXTokenStorage

+ (NSString *)accountKeyFor:(long long)accountId {
    return [NSString stringWithFormat:@"%@%lld", MAXTokenPrefix, accountId];
}

#pragma mark - Токены

+ (void)saveToken:(NSString *)token forAccount:(long long)accountId {
    if (token.length == 0) return;
    [MAXSecureStore setString:token forKey:[self accountKeyFor:accountId]];
}

+ (NSString *)tokenForAccount:(long long)accountId {
    return [MAXSecureStore stringForKey:[self accountKeyFor:accountId]];
}

+ (void)deleteTokenForAccount:(long long)accountId {
    [MAXSecureStore removeKey:[self accountKeyFor:accountId]];
}

#pragma mark - Активный аккаунт

+ (void)setActiveAccountId:(long long)accountId {
    [MAXSecureStore setString:[NSString stringWithFormat:@"%lld", accountId]
                       forKey:MAXActiveAccountKey];
}

+ (void)clearActiveAccount {
    [MAXSecureStore removeKey:MAXActiveAccountKey];
}

/**
 * Кто сейчас в деле.
 *
 * Три источника по убыванию надёжности, и второй с третьим — это ровно те
 * случаи, когда раньше вход слетал на пустом месте:
 *
 *   1. Keychain — переустановку переживает;
 *   2. NSUserDefaults — там указатель лежал в прежних сборках; если он ещё
 *      цел, поднимаем его в Keychain и больше туда не возвращаемся;
 *   3. поиск по самому Keychain — контейнер снесли вместе с настройками,
 *      но токен-то остался. Раньше на этом месте приложение просто
 *      показывало экран входа, хотя сессия была живой.
 */
+ (long long)activeAccountId {
    NSString *stored = [MAXSecureStore stringForKey:MAXActiveAccountKey];
    if (stored.length > 0) return [stored longLongValue];

    NSString *legacy = [[NSUserDefaults standardUserDefaults]
                        stringForKey:MAXLegacyActiveAccountKey];
    if (legacy.length > 0) {
        long long accountId = [legacy longLongValue];
        if (accountId != 0 && [self tokenForAccount:accountId].length > 0) {
            [self setActiveAccountId:accountId];
            [[NSUserDefaults standardUserDefaults]
             removeObjectForKey:MAXLegacyActiveAccountKey];
            [[NSUserDefaults standardUserDefaults] synchronize];
            return accountId;
        }
    }

    return [self recoverAccountIdFromStore];
}

/// Ищет уцелевший токен, когда указателя на него не осталось.
/// Если токенов несколько, берётся наибольший id — то есть заведённый позже.
+ (long long)recoverAccountIdFromStore {
    NSArray *keys = [MAXSecureStore keysWithPrefix:MAXTokenPrefix];

    long long recovered = 0;
    for (NSString *key in keys) {
        long long accountId = [[key substringFromIndex:MAXTokenPrefix.length] longLongValue];
        if (accountId > recovered) recovered = accountId;
    }

    if (recovered == 0) return 0;

    NSLog(@"[Max/Token] Указатель на аккаунт потерян, но токен %lld уцелел — "
          @"восстанавливаю сессию", recovered);
    [self setActiveAccountId:recovered];
    return recovered;
}

+ (NSString *)activeToken {
    long long accountId = [self activeAccountId];
    if (accountId == 0) return nil;
    return [self tokenForAccount:accountId];
}

+ (void)deleteAccount:(long long)accountId {
    // Указатель читается до удаления токена: иначе восстановление в
    // activeAccountId подхватило бы соседний аккаунт прямо посреди выхода.
    BOOL wasActive = [self activeAccountId] == accountId;

    [self deleteTokenForAccount:accountId];
    if (wasActive) [self clearActiveAccount];
}

@end
