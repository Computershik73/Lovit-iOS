//
//  MAXDevicePresets.h
//  Max — набор устройств для подмены отпечатка сессии.
//
//  Порт lib/core/config/device_presets.dart. Файл MAXDevicePresets.m
//  генерируется скриптом из dart-исходника Komet.
//

#import <Foundation/Foundation.h>

@interface MAXDevicePreset : NSObject

@property (nonatomic, copy, readonly) NSString *deviceType;
@property (nonatomic, copy, readonly) NSString *userAgent;
@property (nonatomic, copy, readonly) NSString *deviceName;
@property (nonatomic, copy, readonly) NSString *osVersion;
@property (nonatomic, copy, readonly) NSString *screen;
@property (nonatomic, copy, readonly) NSString *timezone;
@property (nonatomic, copy, readonly) NSString *locale;

+ (instancetype)presetWithDeviceType:(NSString *)deviceType
                           userAgent:(NSString *)userAgent
                          deviceName:(NSString *)deviceName
                           osVersion:(NSString *)osVersion
                              screen:(NSString *)screen
                            timezone:(NSString *)timezone
                              locale:(NSString *)locale;

@end

NSArray *MAXDevicePresetsAll(void);
NSArray *MAXDevicePresetsAndroid(void);
MAXDevicePreset *MAXDevicePresetNamed(NSString *deviceName);
