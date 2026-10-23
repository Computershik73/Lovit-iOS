//
//  MAXSpoofingService.h
//  Max — подмена отпечатка сессии.
//
//  Порт lib/core/storage/spoofing_service.dart.
//
//  Профиль хранится по «скоупу»: либо id аккаунта, либо "pending" — профиль,
//  подготовленный до входа и закрепляемый за аккаунтом сразу после успешной
//  авторизации (commitPendingSpoofForAccount:).
//
//  Версия и билд приложения всегда подменяются на версию официального
//  Android-клиента MAX, иначе сервер отвергает старый клиент.
//

#import <Foundation/Foundation.h>

@class MAXSpoofProfile;

extern NSString *const MAXSpoofHardcodedAppVersion;   // 26.23.2
extern const long long MAXSpoofHardcodedBuildNumber;  // 6779
extern NSString *const MAXSpoofPendingScope;          // pending

@interface MAXSpoofingService : NSObject

/// Скоуп активного аккаунта либо "pending".
+ (NSString *)activeScope;

+ (MAXSpoofProfile *)profileForScope:(NSString *)scope;
+ (void)saveProfile:(MAXSpoofProfile *)profile forScope:(NSString *)scope;

+ (void)clearSpoofForAccount:(long long)accountId;
+ (void)commitPendingSpoofForAccount:(long long)accountId;

/// Готовит случайный Android-профиль для нового аккаунта и кладёт его
/// в скоуп "pending". Устройства, уже занятые другими аккаунтами, не берутся.
+ (MAXSpoofProfile *)prepareNewAccountSpoofExcludingAccountIds:(NSArray *)existingAccountIds;

/// Поля для хэндшейка либо nil, если спуф выключен.
+ (NSDictionary *)spoofedSessionDataForScope:(NSString *)scope;

/// User-Agent для веб-вью (WEB_APP_INIT_DATA и внешние ссылки).
+ (NSString *)webViewUserAgent;

@end
