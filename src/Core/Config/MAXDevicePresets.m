//
//  MAXDevicePresets.m
//
//  Перенесено один в один из Komet lib/core/config/device_presets.dart.
//

#import "MAXDevicePresets.h"

@implementation MAXDevicePreset

+ (instancetype)presetWithDeviceType:(NSString *)deviceType
                           userAgent:(NSString *)userAgent
                          deviceName:(NSString *)deviceName
                           osVersion:(NSString *)osVersion
                              screen:(NSString *)screen
                            timezone:(NSString *)timezone
                              locale:(NSString *)locale {
    MAXDevicePreset *preset = [[MAXDevicePreset alloc] init];
    preset->_deviceType = [deviceType copy];
    preset->_userAgent = [userAgent copy];
    preset->_deviceName = [deviceName copy];
    preset->_osVersion = [osVersion copy];
    preset->_screen = [screen copy];
    preset->_timezone = [timezone copy];
    preset->_locale = [locale copy];
    return preset;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<MAXDevicePreset %@ (%@)>", _deviceName, _deviceType];
}

@end

static MAXDevicePreset *P(NSString *type, NSString *ua, NSString *name,
                          NSString *os, NSString *screen, NSString *tz, NSString *locale) {
    return [MAXDevicePreset presetWithDeviceType:type
                                       userAgent:ua
                                      deviceName:name
                                       osVersion:os
                                          screen:screen
                                        timezone:tz
                                          locale:locale];
}

NSArray *MAXDevicePresetsAll(void) {
    static NSArray *presets = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        presets = @[
            P(@"ANDROID", @"Mozilla/5.0 (Linux; Android 14; SM-S928B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36", @"Samsung Galaxy S24 Ultra", @"Android 14", @"xxhdpi 450dpi 1440x3120", @"Europe/Berlin", @"de-DE"),
            P(@"ANDROID", @"Mozilla/5.0 (Linux; Android 14; Pixel 8 Pro) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Mobile Safari/537.36", @"Google Pixel 8 Pro", @"Android 14", @"xxhdpi 430dpi 1344x2992", @"America/New_York", @"en-US"),
            P(@"ANDROID", @"Mozilla/5.0 (Linux; Android 13; 23021RAA2Y) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Mobile Safari/537.36", @"Xiaomi 13 Pro", @"Android 13", @"xxhdpi 460dpi 1440x3200", @"Asia/Shanghai", @"zh-CN"),
            P(@"ANDROID", @"Mozilla/5.0 (Linux; Android 14; CPH2521) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36", @"OnePlus 12", @"Android 14", @"xxhdpi 450dpi 1440x3168", @"Asia/Kolkata", @"en-IN"),
            P(@"ANDROID", @"Mozilla/5.0 (Linux; Android 13; SM-G998B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Mobile Safari/537.36", @"Samsung Galaxy S21 Ultra", @"Android 13", @"xxhdpi 460dpi 1440x3200", @"Europe/London", @"en-GB"),
            P(@"ANDROID", @"Mozilla/5.0 (Linux; Android 12; Pixel 6) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36", @"Google Pixel 6", @"Android 12", @"xxhdpi 420dpi 1080x2400", @"America/Chicago", @"en-US"),
            P(@"ANDROID", @"Mozilla/5.0 (Linux; Android 13; RMX3371) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Mobile Safari/537.36", @"Realme GT Master Edition", @"Android 13", @"xxhdpi 400dpi 1080x2400", @"Asia/Dubai", @"ar-AE"),
            P(@"ANDROID", @"Mozilla/5.0 (Linux; Android 11; M2101K6G) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/118.0.0.0 Mobile Safari/537.36", @"Poco F3", @"Android 11", @"xxhdpi 420dpi 1080x2400", @"Europe/Madrid", @"es-ES"),
            P(@"ANDROID", @"Mozilla/5.0 (Linux; Android 14; SO-51D) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Mobile Safari/537.36", @"Sony Xperia 1 V", @"Android 14", @"xxxhdpi 560dpi 1644x3840", @"Asia/Tokyo", @"ja-JP"),
            P(@"ANDROID", @"Mozilla/5.0 (Linux; Android 13; XT2201-2) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Mobile Safari/537.36", @"Motorola Edge 30 Pro", @"Android 13", @"xxhdpi 400dpi 1080x2400", @"America/Sao_Paulo", @"pt-BR"),
            P(@"ANDROID", @"Mozilla/5.0 (Linux; Android 14; SM-A546E) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36", @"Samsung Galaxy A54", @"Android 14", @"xxhdpi 400dpi 1080x2340", @"Australia/Sydney", @"en-AU"),
            P(@"ANDROID", @"Mozilla/5.0 (Linux; Android 12; 2201116SG) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36", @"Redmi Note 11 Pro", @"Android 12", @"xxhdpi 420dpi 1080x2400", @"Europe/Rome", @"it-IT"),
            P(@"ANDROID", @"Mozilla/5.0 (Linux; Android 13; ZS676KS) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Mobile Safari/537.36", @"Asus ROG Phone 6", @"Android 13", @"xxhdpi 420dpi 1080x2448", @"Asia/Taipei", @"zh-TW"),
            P(@"ANDROID", @"Mozilla/5.0 (Linux; Android 10; TA-1021) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/115.0.0.0 Mobile Safari/537.36", @"Nokia 8", @"Android 10", @"xxhdpi 380dpi 1440x2560", @"Europe/Helsinki", @"fi-FI"),
            P(@"ANDROID", @"Mozilla/5.0 (Linux; Android 13; PGT-N19) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Mobile Safari/537.36", @"Huawei P60 Pro", @"Android 13 (EMUI)", @"xxhdpi 430dpi 1220x2700", @"Europe/Paris", @"fr-FR"),
            P(@"ANDROID", @"Mozilla/5.0 (Linux; Android 9; LM-G710) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/110.0.0.0 Mobile Safari/537.36", @"LG G7 ThinQ", @"Android 9", @"xxhdpi 450dpi 1440x3120", @"Asia/Seoul", @"ko-KR"),
            P(@"ANDROID", @"Mozilla/5.0 (Linux; Android 14; Nothing Phone (2)) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36", @"Nothing Phone (2)", @"Android 14", @"xxhdpi 400dpi 1080x2412", @"America/Toronto", @"en-CA"),
            P(@"ANDROID", @"Mozilla/5.0 (Linux; Android 13; SM-F936U) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Mobile Safari/537.36", @"Samsung Galaxy Z Fold 4", @"Android 13", @"xhdpi 350dpi 1812x2176", @"America/Denver", @"en-US"),
            P(@"ANDROID", @"Mozilla/5.0 (Linux; Android 12; LE2113) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Mobile Safari/537.36", @"OnePlus 9", @"Android 12", @"xxhdpi 420dpi 1080x2400", @"Europe/Stockholm", @"sv-SE"),
            P(@"ANDROID", @"Mozilla/5.0 (Linux; Android 14; Pixel 7a) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Mobile Safari/537.36", @"Google Pixel 7a", @"Android 14", @"xxhdpi 400dpi 1080x2400", @"Europe/Amsterdam", @"nl-NL"),
            P(@"ANDROID", @"Mozilla/5.0 (Linux; Android 14; SM-S911B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36", @"Samsung Galaxy S24", @"Android 14", @"xxhdpi 450dpi 1440x3120", @"America/Vancouver", @"en-CA"),
            P(@"ANDROID", @"Mozilla/5.0 (Linux; Android 13; M2101K6C) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Mobile Safari/537.36", @"Poco F3 GT", @"Android 13", @"xxhdpi 420dpi 1080x2400", @"Asia/Kolkata", @"en-IN"),
            P(@"ANDROID", @"Mozilla/5.0 (Linux; Android 14; V29) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36", @"Vivo V29", @"Android 14", @"xxhdpi 460dpi 1440x3200", @"Asia/Bangkok", @"th-TH"),
            P(@"ANDROID", @"Mozilla/5.0 (Linux; Android 13; K30 Ultra) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Mobile Safari/537.36", @"Xiaomi K30 Ultra", @"Android 13", @"xxhdpi 450dpi 1440x3200", @"Asia/Shanghai", @"zh-CN"),
            P(@"ANDROID", @"Mozilla/5.0 (Linux; Android 14; P80) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36", @"Oppo Find N3", @"Android 14", @"xxhdpi 430dpi 1440x3168", @"Europe/Paris", @"fr-FR"),
            P(@"ANDROID", @"Mozilla/5.0 (Linux; Android 13; SM-G916B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Mobile Safari/537.36", @"Samsung Galaxy S20 FE", @"Android 13", @"xxhdpi 400dpi 1080x2400", @"Europe/Berlin", @"de-DE"),
            P(@"ANDROID", @"Mozilla/5.0 (Linux; Android 12; CPH2135) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36", @"OnePlus 8 Pro", @"Android 12", @"xxhdpi 450dpi 1440x3168", @"America/New_York", @"en-US"),
            P(@"ANDROID", @"Mozilla/5.0 (Linux; Android 14; S24E) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36", @"Samsung Galaxy S24 Edge", @"Android 14", @"xxhdpi 460dpi 1440x3200", @"Asia/Tokyo", @"ja-JP"),
            P(@"ANDROID", @"Mozilla/5.0 (Linux; Android 13; LE2120) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Mobile Safari/537.36", @"OnePlus 9 Pro", @"Android 13", @"xxhdpi 460dpi 1440x3216", @"America/Toronto", @"en-CA"),
            P(@"ANDROID", @"Mozilla/5.0 (Linux; Android 14; A14 Pro) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36", @"Google Pixel 9 Pro", @"Android 14", @"xxhdpi 430dpi 1344x2992", @"Europe/London", @"en-GB"),
            P(@"ANDROID", @"Mozilla/5.0 (Linux; Android 13; 21091116AC) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Mobile Safari/537.36", @"Xiaomi 12T", @"Android 13", @"xxhdpi 460dpi 1440x3200", @"Europe/Rome", @"it-IT"),
            P(@"ANDROID", @"Mozilla/5.0 (Linux; Android 12; SM-F711B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36", @"Samsung Galaxy Z Flip 3", @"Android 12", @"xhdpi 370dpi 1080x2640", @"America/Mexico_City", @"es-MX"),
            P(@"ANDROID", @"Mozilla/5.0 (Linux; Android 13; XT2201-3) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Mobile Safari/537.36", @"Motorola Edge 40", @"Android 13", @"xxhdpi 400dpi 1080x2400", @"Asia/Dubai", @"ar-AE"),
            P(@"ANDROID", @"Mozilla/5.0 (Linux; Android 14; 23088RA9AC) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36", @"Xiaomi 14 Ultra", @"Android 14", @"xxhdpi 450dpi 1440x3200", @"Europe/Moscow", @"ru-RU"),
            P(@"ANDROID", @"Mozilla/5.0 (Linux; Android 13; CPH2487) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Mobile Safari/537.36", @"OnePlus 11", @"Android 13", @"xxhdpi 450dpi 1440x3216", @"Australia/Sydney", @"en-AU"),
            P(@"ANDROID", @"Mozilla/5.0 (Linux; Android 12; M2004J19C) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Mobile Safari/537.36", @"Xiaomi Mi 10T Pro", @"Android 12", @"xxhdpi 460dpi 1440x3200", @"America/Sao_Paulo", @"pt-BR"),
            P(@"ANDROID", @"Mozilla/5.0 (Linux; Android 14; SM-A546B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36", @"Samsung Galaxy A55", @"Android 14", @"xxhdpi 460dpi 1440x3200", @"Europe/Madrid", @"es-ES"),
            P(@"ANDROID", @"Mozilla/5.0 (Linux; Android 13; RMX3761) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Mobile Safari/537.36", @"Realme GT Neo 3", @"Android 13", @"xxhdpi 460dpi 1440x3200", @"Asia/Hong_Kong", @"zh-HK"),

            P(@"IOS", @"Mozilla/5.0 (iPhone; CPU iPhone OS 17_5_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1", @"iPhone 15 Pro Max", @"iOS 17.5.1", @"1290x2796 3.0x", @"America/Los_Angeles", @"en-US"),
            P(@"IOS", @"Mozilla/5.0 (iPhone; CPU iPhone OS 16_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1", @"iPhone 13", @"iOS 16.7", @"1170x2532 3.0x", @"Europe/London", @"en-GB"),
            P(@"IOS", @"Mozilla/5.0 (iPad; CPU OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) CriOS/124.0.6367.88 Mobile/15E148 Safari/604.1", @"iPad Pro 11-inch", @"iPadOS 17.5", @"1668x2388 2.0x", @"Europe/Paris", @"fr-FR"),
            P(@"IOS", @"Mozilla/5.0 (iPhone; CPU iPhone OS 17_4_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) FxiOS/125.0 Mobile/15E148", @"iPhone 14 Pro", @"iOS 17.4.1", @"1179x2556 3.0x", @"Europe/Berlin", @"de-DE"),
            P(@"IOS", @"Mozilla/5.0 (iPhone; CPU iPhone OS 15_8 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.6.3 Mobile/15E148 Safari/604.1", @"iPhone SE (2020)", @"iOS 15.8", @"750x1334 2.0x", @"Australia/Melbourne", @"en-AU"),
            P(@"IOS", @"Mozilla/5.0 (iPhone; CPU iPhone OS 17_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) OPR/55.0.2519.144889 Mobile/15E148", @"iPhone 15", @"iOS 17.1", @"1179x2556 3.0x", @"Asia/Tokyo", @"ja-JP"),
            P(@"IOS", @"Mozilla/5.0 (iPad; CPU OS 16_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.5 Mobile/15E148 Safari/604.1", @"iPad Air 5th Gen", @"iPadOS 16.5", @"1640x2360 2.0x", @"America/Toronto", @"en-CA"),
            P(@"IOS", @"Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1", @"iPhone 15 Pro", @"iOS 17.5", @"1179x2556 3.0x", @"Asia/Singapore", @"en-SG"),
            P(@"IOS", @"Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Mobile/15E148 Safari/604.1", @"iPhone 14", @"iOS 17.4", @"1170x2532 3.0x", @"Europe/Stockholm", @"sv-SE"),
            P(@"IOS", @"Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1", @"iPhone 12 Pro Max", @"iOS 16.6", @"1284x2778 3.0x", @"Asia/Bangkok", @"th-TH"),
            P(@"IOS", @"Mozilla/5.0 (iPhone; CPU iPhone OS 15_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.6 Mobile/15E148 Safari/604.1", @"iPhone 11 Pro", @"iOS 15.7", @"1125x2436 3.0x", @"Europe/Istanbul", @"tr-TR"),
            P(@"IOS", @"Mozilla/5.0 (iPad; CPU OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1", @"iPad Mini 6th Gen", @"iPadOS 17.5", @"1488x2266 2.0x", @"America/Mexico_City", @"es-MX"),
            P(@"IOS", @"Mozilla/5.0 (iPad; CPU OS 16_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.7 Mobile/15E148 Safari/604.1", @"iPad 10th Gen", @"iPadOS 16.7", @"1620x2160 2.0x", @"Asia/Hong_Kong", @"zh-HK"),
            P(@"IOS", @"Mozilla/5.0 (iPhone; CPU iPhone OS 17_3 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.3 Mobile/15E148 Safari/604.1", @"iPhone 13 Pro", @"iOS 17.3", @"1170x2532 3.0x", @"Europe/Dublin", @"en-IE"),
            P(@"IOS", @"Mozilla/5.0 (iPhone; CPU iPhone OS 16_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.5 Mobile/15E148 Safari/604.1", @"iPhone 12", @"iOS 16.5", @"1125x2436 3.0x", @"Asia/Mumbai", @"en-IN"),
            P(@"IOS", @"Mozilla/5.0 (iPad; CPU OS 15_8 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.6 Mobile/15E148 Safari/604.1", @"iPad Pro 12.9-inch", @"iPadOS 15.8", @"2048x2732 2.0x", @"Europe/Vienna", @"de-AT"),
            P(@"IOS", @"Mozilla/5.0 (iPhone; CPU iPhone OS 14_8 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/14.1.1 Mobile/15E148 Safari/604.1", @"iPhone XS Max", @"iOS 14.8", @"1125x2436 3.0x", @"America/Los_Angeles", @"en-US"),
            P(@"IOS", @"Mozilla/5.0 (iPhone; CPU iPhone OS 17_2 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.2 Mobile/15E148 Safari/604.1", @"iPhone 13 mini", @"iOS 17.2", @"1080x2340 3.0x", @"America/Miami", @"en-US"),
            P(@"IOS", @"Mozilla/5.0 (iPad; CPU OS 14_8 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/14.1 Mobile/15E148 Safari/604.1", @"iPad Air 4th Gen", @"iPadOS 14.8", @"1640x2360 2.0x", @"Europe/Zurich", @"de-CH"),
            P(@"IOS", @"Mozilla/5.0 (iPhone; CPU iPhone OS 16_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.4 Mobile/15E148 Safari/604.1", @"iPhone 11", @"iOS 16.4", @"828x1792 2.0x", @"America/Argentina/Buenos_Aires", @"es-AR"),
            P(@"IOS", @"Mozilla/5.0 (iPhone; CPU iPhone OS 17_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.1 Mobile/15E148 Safari/604.1", @"iPhone 12 mini", @"iOS 17.1", @"1080x2340 3.0x", @"Europe/Brussels", @"nl-BE"),
            P(@"IOS", @"Mozilla/5.0 (iPad; CPU OS 17_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Mobile/15E148 Safari/604.1", @"iPad Air Pro 11-inch", @"iPadOS 17.4", @"2388x1668 2.0x", @"Asia/Bangkok", @"en-TH"),
            P(@"IOS", @"Mozilla/5.0 (iPhone; CPU iPhone OS 13_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/13.1.3 Mobile/15E148 Safari/604.1", @"iPhone XR", @"iOS 13.7", @"828x1792 2.0x", @"Europe/Lisbon", @"pt-PT"),
            P(@"IOS", @"Mozilla/5.0 (iPad; CPU OS 17_3 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.3 Mobile/15E148 Safari/604.1", @"iPad (9th generation)", @"iPadOS 17.3", @"1620x2160 2.0x", @"Europe/Prague", @"cs-CZ"),

            P(@"DESKTOP", @"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36", @"Windows PC", @"Windows 11", @"1920x1080 1.25x", @"Europe/Moscow", @"ru-RU"),
            P(@"DESKTOP", @"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36", @"MacBook Pro", @"macOS 14.5 Sonoma", @"1728x1117 2.0x", @"America/New_York", @"en-US"),
            P(@"DESKTOP", @"Mozilla/5.0 (X11; Linux x86_64; rv:125.0) Gecko/20100101 Firefox/125.0", @"Linux PC", @"Ubuntu 24.04 LTS", @"2560x1440 1.0x", @"UTC", @"en-GB"),
            P(@"DESKTOP", @"Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:125.0) Gecko/20100101 Firefox/125.0", @"Windows PC (Firefox)", @"Windows 10", @"1536x864 1.0x", @"Europe/Paris", @"fr-FR"),
            P(@"DESKTOP", @"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4.1 Safari/605.1.15", @"iMac (Safari)", @"macOS 13.6 Ventura", @"3840x2160 1.5x", @"America/Los_Angeles", @"en-US"),

            P(@"WEB", @"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36", @"Chrome", @"Windows ", @"1920x1080", @"Europe/Berlin", @"de-DE"),
            P(@"WEB", @"Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36", @"Chrome", @"Windows", @"2560x1440", @"America/New_York", @"en-US"),
            P(@"WEB", @"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36 Edg/123.0.2420.97", @"Edge", @"Windows", @"1536x864", @"Europe/London", @"en-GB"),
            P(@"WEB", @"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36", @"Chrome", @"Windows", @"1920x1200", @"Europe/Paris", @"fr-FR"),
            P(@"WEB", @"Mozilla/5.0 (Windows NT 6.1; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36", @"Chrome", @"Windows", @"1366x768", @"Europe/Madrid", @"es-ES"),
            P(@"WEB", @"Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:126.0) Gecko/20100101 Firefox/126.0", @"Firefox", @"Windows", @"1920x1080", @"Europe/Rome", @"it-IT"),
            P(@"WEB", @"Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:125.0) Gecko/20100101 Firefox/125.0", @"Firefox", @"Windows", @"1440x900", @"Europe/Amsterdam", @"nl-NL"),
            P(@"WEB", @"Mozilla/5.0 (Windows NT 6.3; Win64; x64; rv:124.0) Gecko/20100101 Firefox/124.0", @"Firefox", @"Windows", @"1600x900", @"Europe/Warsaw", @"pl-PL"),
            P(@"WEB", @"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36 Edg/125.0.2535.51", @"Edge", @"Windows", @"1920x1080", @"America/Chicago", @"en-US"),
            P(@"WEB", @"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36 Edg/124.0.2478.109", @"Edge", @"Windows", @"1366x768", @"America/Sao_Paulo", @"pt-BR"),
            P(@"WEB", @"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36", @"Chrome", @"macOS 14.5", @"2560x1440", @"America/Los_Angeles", @"en-US"),
            P(@"WEB", @"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36", @"Chrome", @"macOS 13.6", @"1440x900", @"America/Toronto", @"en-CA"),
            P(@"WEB", @"Mozilla/5.0 (Macintosh; Intel Mac OS X 11_7_10) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36", @"Chrome", @"macOS 11.7", @"1728x1117", @"Australia/Sydney", @"en-AU"),
            P(@"WEB", @"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36", @"Chrome", @"macOS 12.5", @"2048x1152", @"Europe/London", @"en-GB"),
            P(@"WEB", @"Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:126.0) Gecko/20100101 Firefox/126.0", @"Firefox", @"macOS 14.5", @"1920x1080", @"America/New_York", @"en-US"),
            P(@"WEB", @"Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:125.0) Gecko/20100101 Firefox/125.0", @"Firefox", @"macOS 13.0", @"1680x1050", @"Europe/Berlin", @"de-DE"),
            P(@"WEB", @"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15", @"Safari", @"macOS 14.5", @"1440x900", @"America/New_York", @"en-US"),
            P(@"WEB", @"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Safari/605.1.15", @"Safari", @"macOS 13.6", @"2560x1600", @"Europe/Paris", @"fr-FR"),
            P(@"WEB", @"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_14_6) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.6.1 Safari/605.1.15", @"Safari", @"macOS 10.14", @"1280x800", @"Asia/Tokyo", @"ja-JP"),
            P(@"WEB", @"Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36", @"Chrome", @"Linux", @"1920x1080", @"Europe/Moscow", @"ru-RU"),
            P(@"WEB", @"Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36", @"Chrome", @"Linux", @"1366x768", @"Asia/Kolkata", @"en-IN"),
            P(@"WEB", @"Mozilla/5.0 (X11; CrOS x86_64 14541.0.0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36", @"Chrome", @"Chrome OS", @"1920x1080", @"America/Mexico_City", @"es-MX"),
            P(@"WEB", @"Mozilla/5.0 (X11; Linux i686) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36", @"Chrome", @"Linux", @"1600x900", @"Asia/Shanghai", @"zh-CN"),
            P(@"WEB", @"Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:126.0) Gecko/20100101 Firefox/126.0", @"Firefox", @"Linux", @"1920x1080", @"UTC", @"en-GB"),
            P(@"WEB", @"Mozilla/5.0 (X11; Fedora; Linux x86_64; rv:125.0) Gecko/20100101 Firefox/125.0", @"Firefox", @"Linux", @"2560x1440", @"America/Denver", @"en-US"),
            P(@"WEB", @"Mozilla/5.0 (X11; Linux x86_64; rv:109.0) Gecko/20100101 Firefox/115.0", @"Firefox", @"Linux", @"1366x768", @"Asia/Dubai", @"ar-AE"),
            P(@"WEB", @"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36 OPR/110.0.0.0", @"Opera", @"Windows", @"1920x1080", @"Europe/Oslo", @"no-NO"),
            P(@"WEB", @"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36 Vivaldi/6.5.3206.63", @"Vivaldi", @"macOS 14.0", @"1440x900", @"Europe/Stockholm", @"sv-SE"),
            P(@"WEB", @"Mozilla/5.0 (Windows NT 10.0; rv:102.0) Gecko/20100101 Firefox/102.0", @"Firefox", @"Windows", @"1280x720", @"Asia/Seoul", @"ko-KR"),
            P(@"WEB", @"Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/108.0.0.0 Safari/537.36", @"Chrome", @"Linux", @"1920x1080", @"Europe/Helsinki", @"fi-FI"),
            P(@"WEB", @"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_13_6) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/13.1.2 Safari/605.1.15", @"Safari", @"macOS 10.13", @"1280x800", @"America/Vancouver", @"en-CA")
        ];
    });
    return presets;
}

NSArray *MAXDevicePresetsAndroid(void) {
    static NSArray *androidPresets = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableArray *filtered = [NSMutableArray array];
        for (MAXDevicePreset *preset in MAXDevicePresetsAll()) {
            if ([preset.deviceType isEqualToString:@"ANDROID"]) [filtered addObject:preset];
        }
        androidPresets = filtered;
    });
    return androidPresets;
}

MAXDevicePreset *MAXDevicePresetNamed(NSString *deviceName) {
    if (deviceName.length == 0) return nil;
    for (MAXDevicePreset *preset in MAXDevicePresetsAll()) {
        if ([preset.deviceName isEqualToString:deviceName]) return preset;
    }
    return nil;
}
