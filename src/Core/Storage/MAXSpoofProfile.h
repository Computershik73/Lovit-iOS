//
//  MAXSpoofProfile.h
//  Max — профиль подменяемых полей сессии.
//
//  Порт lib/models/spoof_profile.dart. Ключи словаря совпадают с dart-версией,
//  так что профиль читается и пишется в том же формате.
//

#import <Foundation/Foundation.h>

@interface MAXSpoofProfile : NSObject <NSCopying>

@property (nonatomic, assign) BOOL enabled;
@property (nonatomic, copy) NSString *deviceName;
@property (nonatomic, copy) NSString *osVersion;
@property (nonatomic, copy) NSString *screen;
@property (nonatomic, copy) NSString *timezone;
@property (nonatomic, copy) NSString *locale;
@property (nonatomic, copy) NSString *deviceLocale;
@property (nonatomic, copy) NSString *deviceId;
@property (nonatomic, copy) NSString *deviceType;
@property (nonatomic, copy) NSString *arch;
@property (nonatomic, copy) NSString *appVersion;
@property (nonatomic, assign) long long buildNumber;
@property (nonatomic, copy) NSString *pushDeviceType;
@property (nonatomic, copy) NSString *instanceId;
/// 0 — не задан.
@property (nonatomic, assign) long long clientSessionId;
@property (nonatomic, copy) NSString *userAgent;

+ (instancetype)profileFromDictionary:(NSDictionary *)dictionary;
- (NSDictionary *)dictionaryRepresentation;

@end
