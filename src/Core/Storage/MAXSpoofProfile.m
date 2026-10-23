//
//  MAXSpoofProfile.m
//

#import "MAXSpoofProfile.h"

static NSString *MAXStringValue(NSDictionary *dictionary, NSString *key, NSString *fallback) {
    id value = dictionary[key];
    return [value isKindOfClass:[NSString class]] ? value : fallback;
}

static long long MAXLongValue(NSDictionary *dictionary, NSString *key, long long fallback) {
    id value = dictionary[key];
    return [value isKindOfClass:[NSNumber class]] ? [value longLongValue] : fallback;
}

@implementation MAXSpoofProfile

- (id)init {
    self = [super init];
    if (self) {
        _enabled = NO;
        _deviceName = @"";
        _osVersion = @"";
        _screen = @"";
        _timezone = @"";
        _locale = @"";
        _deviceLocale = @"";
        _deviceId = @"";
        _deviceType = @"ANDROID";
        _arch = @"arm64-v8a";
        _appVersion = @"";
        _buildNumber = 0;
        _pushDeviceType = @"GCM";
        _instanceId = @"";
        _clientSessionId = 0;
        _userAgent = @"";
    }
    return self;
}

+ (instancetype)profileFromDictionary:(NSDictionary *)dictionary {
    MAXSpoofProfile *profile = [[MAXSpoofProfile alloc] init];
    if (![dictionary isKindOfClass:[NSDictionary class]]) return profile;

    id enabled = dictionary[@"enabled"];
    profile.enabled = [enabled isKindOfClass:[NSNumber class]] ? [enabled boolValue] : NO;
    profile.deviceName = MAXStringValue(dictionary, @"device_name", @"");
    profile.osVersion = MAXStringValue(dictionary, @"os_version", @"");
    profile.screen = MAXStringValue(dictionary, @"screen", @"");
    profile.timezone = MAXStringValue(dictionary, @"timezone", @"");
    profile.locale = MAXStringValue(dictionary, @"locale", @"");
    profile.deviceLocale = MAXStringValue(dictionary, @"device_locale", @"");
    profile.deviceId = MAXStringValue(dictionary, @"device_id", @"");
    profile.deviceType = MAXStringValue(dictionary, @"device_type", @"ANDROID");
    profile.arch = MAXStringValue(dictionary, @"arch", @"arm64-v8a");
    profile.appVersion = MAXStringValue(dictionary, @"app_version", @"");
    profile.buildNumber = MAXLongValue(dictionary, @"build_number", 0);
    profile.pushDeviceType = MAXStringValue(dictionary, @"push_device_type", @"GCM");
    profile.instanceId = MAXStringValue(dictionary, @"instance_id", @"");
    profile.clientSessionId = MAXLongValue(dictionary, @"client_session_id", 0);
    profile.userAgent = MAXStringValue(dictionary, @"user_agent", @"");
    return profile;
}

- (NSDictionary *)dictionaryRepresentation {
    return @{
        @"enabled": @(_enabled),
        @"device_name": _deviceName ?: @"",
        @"os_version": _osVersion ?: @"",
        @"screen": _screen ?: @"",
        @"timezone": _timezone ?: @"",
        @"locale": _locale ?: @"",
        @"device_locale": _deviceLocale ?: @"",
        @"device_id": _deviceId ?: @"",
        @"device_type": _deviceType ?: @"ANDROID",
        @"arch": _arch ?: @"arm64-v8a",
        @"app_version": _appVersion ?: @"",
        @"build_number": @(_buildNumber),
        @"push_device_type": _pushDeviceType ?: @"GCM",
        @"instance_id": _instanceId ?: @"",
        @"client_session_id": @(_clientSessionId),
        @"user_agent": _userAgent ?: @""
    };
}

- (id)copyWithZone:(NSZone *)zone {
    return [MAXSpoofProfile profileFromDictionary:[self dictionaryRepresentation]];
}

@end
