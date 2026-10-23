//
//  MAXSpoofingService.m
//

#import "MAXSpoofingService.h"
#import "MAXSecureStore.h"
#import "MAXSpoofProfile.h"
#import "MAXDevicePresets.h"
#import "MAXDeviceIdentity.h"
#import "MAXTokenStorage.h"

NSString *const MAXSpoofHardcodedAppVersion = @"26.23.2";
const long long MAXSpoofHardcodedBuildNumber = 6779;
NSString *const MAXSpoofPendingScope = @"pending";

@implementation MAXSpoofingService

+ (NSString *)profileKeyForScope:(NSString *)scope {
    return [NSString stringWithFormat:@"spoof_profile_%@", scope];
}

+ (NSString *)activeScope {
    long long accountId = [MAXTokenStorage activeAccountId];
    if (accountId == 0) return MAXSpoofPendingScope;
    return [NSString stringWithFormat:@"%lld", accountId];
}

#pragma mark - Чтение и запись

/// Профиль лежит там же, где токен: он описывает устройство, которым клиент
/// представляется в SESSION_INIT. Потеря профиля при живом токене означает
/// смену устройства посреди сессии — сервер вправе такую сессию оборвать.
/// Профили прежних сборок подхватываются из настроек и переносятся.
+ (MAXSpoofProfile *)profileForScope:(NSString *)scope {
    NSString *key = [self profileKeyForScope:scope];

    NSString *raw = [MAXSecureStore stringForKey:key];
    if (raw.length == 0) {
        NSString *legacy = [[NSUserDefaults standardUserDefaults] stringForKey:key];
        if (legacy.length > 0) {
            [MAXSecureStore setString:legacy forKey:key];
            [[NSUserDefaults standardUserDefaults] removeObjectForKey:key];
            [[NSUserDefaults standardUserDefaults] synchronize];
            raw = legacy;
        }
    }
    if (raw.length == 0) return nil;

    NSData *data = [raw dataUsingEncoding:NSUTF8StringEncoding];
    id decoded = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    if (![decoded isKindOfClass:[NSDictionary class]]) return nil;

    MAXSpoofProfile *profile = [MAXSpoofProfile profileFromDictionary:decoded];
    return [self migrateVersionForProfile:profile scope:scope];
}

+ (void)saveProfile:(MAXSpoofProfile *)profile forScope:(NSString *)scope {
    if (profile == nil) return;
    NSData *data = [NSJSONSerialization dataWithJSONObject:[profile dictionaryRepresentation]
                                                   options:0
                                                     error:NULL];
    if (data == nil) return;

    NSString *json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    [MAXSecureStore setString:json forKey:[self profileKeyForScope:scope]];
}

/// Версия клиента в сохранённом профиле всегда подтягивается до актуальной —
/// сервер отвергает устаревшие сборки.
+ (MAXSpoofProfile *)migrateVersionForProfile:(MAXSpoofProfile *)profile scope:(NSString *)scope {
    if ([profile.appVersion isEqualToString:MAXSpoofHardcodedAppVersion]
        && profile.buildNumber == MAXSpoofHardcodedBuildNumber) {
        return profile;
    }
    profile.appVersion = MAXSpoofHardcodedAppVersion;
    profile.buildNumber = MAXSpoofHardcodedBuildNumber;
    [self saveProfile:profile forScope:scope];
    return profile;
}

#pragma mark - Жизненный цикл аккаунта

+ (void)clearSpoofForAccount:(long long)accountId {
    NSString *scope = [NSString stringWithFormat:@"%lld", accountId];
    [MAXSecureStore removeKey:[self profileKeyForScope:scope]];
}

+ (void)commitPendingSpoofForAccount:(long long)accountId {
    MAXSpoofProfile *pending = [self profileForScope:MAXSpoofPendingScope];
    if (pending == nil) return;

    [self saveProfile:pending forScope:[NSString stringWithFormat:@"%lld", accountId]];
    [MAXSecureStore removeKey:[self profileKeyForScope:MAXSpoofPendingScope]];
}

+ (MAXSpoofProfile *)prepareNewAccountSpoofExcludingAccountIds:(NSArray *)existingAccountIds {
    NSMutableSet *used = [NSMutableSet set];
    for (NSNumber *accountId in existingAccountIds) {
        NSString *scope = [NSString stringWithFormat:@"%lld", [accountId longLongValue]];
        MAXSpoofProfile *existing = [self profileForScope:scope];
        if (existing.deviceName.length > 0) [used addObject:existing.deviceName];
    }

    NSArray *android = MAXDevicePresetsAndroid();
    NSMutableArray *fresh = [NSMutableArray array];
    for (MAXDevicePreset *preset in android) {
        if (![used containsObject:preset.deviceName]) [fresh addObject:preset];
    }
    NSArray *pool = fresh.count > 0 ? fresh : android;
    MAXDevicePreset *preset = pool[arc4random_uniform((u_int32_t)pool.count)];

    NSString *shortLocale = [[preset.locale componentsSeparatedByCharactersInSet:
                              [NSCharacterSet characterSetWithCharactersInString:@"-_"]]
                             objectAtIndex:0];

    MAXSpoofProfile *profile = [[MAXSpoofProfile alloc] init];
    profile.enabled = YES;
    profile.deviceName = preset.deviceName;
    profile.osVersion = preset.osVersion;
    profile.screen = preset.screen;
    profile.timezone = preset.timezone;
    profile.locale = shortLocale;
    profile.deviceLocale = shortLocale;
    profile.deviceId = [MAXDeviceIdentity randomHexWithByteCount:8];
    profile.deviceType = preset.deviceType;
    profile.arch = @"arm64-v8a";
    profile.appVersion = MAXSpoofHardcodedAppVersion;
    profile.buildNumber = MAXSpoofHardcodedBuildNumber;
    profile.pushDeviceType = @"GCM";
    profile.instanceId = [MAXDeviceIdentity uuidV4];
    profile.clientSessionId = [MAXDeviceIdentity randomClientSessionId];
    profile.userAgent = preset.userAgent;

    [self saveProfile:profile forScope:MAXSpoofPendingScope];
    return profile;
}

#pragma mark - Данные для хэндшейка

+ (NSDictionary *)spoofedSessionDataForScope:(NSString *)scope {
    MAXSpoofProfile *profile = [self profileForScope:(scope ?: [self activeScope])];
    if (profile == nil || !profile.enabled) return nil;

    NSString *appVersion = profile.appVersion.length > 0
        ? profile.appVersion
        : MAXSpoofHardcodedAppVersion;
    NSString *arch = profile.arch.length > 0 ? profile.arch : @"arm64-v8a";
    long long buildNumber = profile.buildNumber != 0
        ? profile.buildNumber
        : MAXSpoofHardcodedBuildNumber;

    return @{
        @"device_name": profile.deviceName ?: @"",
        @"os_version": profile.osVersion ?: @"",
        @"screen": profile.screen ?: @"",
        @"timezone": profile.timezone ?: @"",
        @"locale": profile.locale ?: @"",
        @"device_locale": profile.deviceLocale ?: @"",
        @"device_id": profile.deviceId ?: @"",
        @"device_type": profile.deviceType ?: @"ANDROID",
        @"app_version": appVersion,
        @"arch": arch,
        @"build_number": @(buildNumber),
        @"instance_id": profile.instanceId ?: @"",
        @"client_session_id": @(profile.clientSessionId),
        @"push_device_type": profile.pushDeviceType ?: @"GCM",
        @"user_agent": profile.userAgent ?: @""
    };
}

+ (NSString *)webViewUserAgent {
    MAXSpoofProfile *profile = [self profileForScope:[self activeScope]];
    if (profile == nil || !profile.enabled) return nil;
    if (profile.userAgent.length > 0) return profile.userAgent;

    MAXDevicePreset *preset = MAXDevicePresetNamed(profile.deviceName);
    if (preset != nil) return preset.userAgent;

    return [self derivedUserAgentForProfile:profile];
}

+ (NSString *)derivedUserAgentForProfile:(MAXSpoofProfile *)profile {
    NSString *deviceType = profile.deviceType.length > 0 ? profile.deviceType : @"ANDROID";
    NSString *model = profile.deviceName.length > 0 ? profile.deviceName : @"K";

    if ([deviceType isEqualToString:@"IOS"] || [deviceType isEqualToString:@"iOS"]) {
        NSMutableString *digits = [NSMutableString string];
        for (NSUInteger i = 0; i < profile.osVersion.length; i++) {
            unichar c = [profile.osVersion characterAtIndex:i];
            if ((c >= '0' && c <= '9')) [digits appendFormat:@"%C", c];
            else if (c == '.') [digits appendString:@"_"];
        }
        NSString *version = digits.length > 0 ? digits : @"17_0";
        return [NSString stringWithFormat:
                @"Mozilla/5.0 (iPhone; CPU iPhone OS %@ like Mac OS X) "
                @"AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 "
                @"Mobile/15E148 Safari/604.1", version];
    }

    NSString *android = profile.osVersion.length > 0 ? profile.osVersion : @"Android 14";
    return [NSString stringWithFormat:
            @"Mozilla/5.0 (Linux; %@; %@) AppleWebKit/537.36 "
            @"(KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36", android, model];
}

@end
