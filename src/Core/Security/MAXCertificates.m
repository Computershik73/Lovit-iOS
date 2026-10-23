//
//  MAXCertificates.m
//

#import "MAXCertificates.h"

/**
 * Base64 своей рукой: base64EncodedStringWithOptions появился в iOS 7,
 * а нижняя граница здесь 6.0.
 */
static NSString *MAXBase64(NSData *data) {
    static const char *alphabet =
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

    const uint8_t *bytes = [data bytes];
    NSUInteger length = [data length];

    NSMutableString *result = [NSMutableString stringWithCapacity:((length + 2) / 3) * 4];

    for (NSUInteger i = 0; i < length; i += 3) {
        NSUInteger remaining = length - i;

        uint32_t chunk = (uint32_t)bytes[i] << 16;
        if (remaining > 1) chunk |= (uint32_t)bytes[i + 1] << 8;
        if (remaining > 2) chunk |= (uint32_t)bytes[i + 2];

        [result appendFormat:@"%c%c", alphabet[(chunk >> 18) & 63], alphabet[(chunk >> 12) & 63]];
        [result appendFormat:@"%c", remaining > 1 ? alphabet[(chunk >> 6) & 63] : '='];
        [result appendFormat:@"%c", remaining > 2 ? alphabet[chunk & 63] : '='];
    }

    return result;
}

static NSString *MAXUuidString(void) {
    CFUUIDRef uuid = CFUUIDCreate(NULL);
    CFStringRef text = CFUUIDCreateString(NULL, uuid);

    NSString *value = [NSString stringWithString:(__bridge NSString *)text];

    CFRelease(text);
    CFRelease(uuid);

    return value;
}

@implementation MAXCertificates

/// Корни, которых нет в хранилище старых iOS. Два первых — для протокола
/// (api2.oneme.ru), два последних — для картинок: i.oneme.ru удостоверяется
/// сертификатом Let's Encrypt, а его новый корень ISRG Root YR выпущен
/// в 2026 году и в iOS 7 не мог попасть по определению. Без него фотографии
/// в переписке не загружались вовсе.
+ (NSArray *)fileNames {
    return [NSArray arrayWithObjects:
            @"russian_trusted_root_ca", @"russian_trusted_sub_ca",
            @"isrg_root_yr", @"isrg_root_x1", nil];
}

+ (NSString *)titleForName:(NSString *)name {
    if ([name isEqualToString:@"russian_trusted_root_ca"]) return @"Russian Trusted Root CA";
    if ([name isEqualToString:@"russian_trusted_sub_ca"]) return @"Russian Trusted Sub CA";
    if ([name isEqualToString:@"isrg_root_yr"]) return @"ISRG Root YR";
    if ([name isEqualToString:@"isrg_root_x1"]) return @"ISRG Root X1";
    return name;
}

+ (NSData *)dataForName:(NSString *)name {
    NSString *path = [[NSBundle mainBundle] pathForResource:name
                                                     ofType:@"der"
                                                inDirectory:@"certs"];
    return path != nil ? [NSData dataWithContentsOfFile:path] : nil;
}

/// Якоря создаются один раз: SecCertificateCreateWithData разбирает DER
/// на каждом вызове, а дёргается это на каждом подключении.
+ (NSArray *)anchorCertificates {
    static NSArray *anchors = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableArray *collected = [NSMutableArray array];

        for (NSString *name in [self fileNames]) {
            NSData *data = [self dataForName:name];
            if ([data length] == 0) {
                NSLog(@"[Max/Certs] Корень %@ не найден в связке", name);
                continue;
            }

            SecCertificateRef certificate =
                SecCertificateCreateWithData(NULL, (__bridge CFDataRef)data);
            if (certificate == NULL) {
                NSLog(@"[Max/Certs] Корень %@ не разобрался как DER", name);
                continue;
            }

            [collected addObject:(__bridge_transfer id)certificate];
        }

        anchors = collected;
    });
    return anchors;
}

+ (NSData *)configurationProfile {
    NSMutableString *payloads = [NSMutableString string];

    for (NSString *name in [self fileNames]) {
        NSData *data = [self dataForName:name];
        if ([data length] == 0) continue;

        [payloads appendString:@"\t\t<dict>\n"];
        [payloads appendString:@"\t\t\t<key>PayloadType</key>\n"
                               @"\t\t\t<string>com.apple.security.root</string>\n"];
        [payloads appendString:@"\t\t\t<key>PayloadVersion</key>\n\t\t\t<integer>1</integer>\n"];
        [payloads appendFormat:@"\t\t\t<key>PayloadIdentifier</key>\n"
                               @"\t\t\t<string>ru.computershik.scam.root.%@</string>\n", name];
        [payloads appendFormat:@"\t\t\t<key>PayloadUUID</key>\n\t\t\t<string>%@</string>\n",
                               MAXUuidString()];
        [payloads appendFormat:@"\t\t\t<key>PayloadDisplayName</key>\n\t\t\t<string>%@</string>\n",
                               [self titleForName:name]];
        [payloads appendFormat:@"\t\t\t<key>PayloadCertificateFileName</key>\n"
                               @"\t\t\t<string>%@.cer</string>\n", name];
        [payloads appendFormat:@"\t\t\t<key>PayloadContent</key>\n\t\t\t<data>\n%@\n\t\t\t</data>\n",
                               MAXBase64(data)];
        [payloads appendString:@"\t\t</dict>\n"];
    }

    NSString *profile = [NSString stringWithFormat:
        @"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        @"<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" "
        @"\"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n"
        @"<plist version=\"1.0\">\n"
        @"<dict>\n"
        @"\t<key>PayloadContent</key>\n"
        @"\t<array>\n%@\t</array>\n"
        @"\t<key>PayloadType</key>\n\t<string>Configuration</string>\n"
        @"\t<key>PayloadVersion</key>\n\t<integer>1</integer>\n"
        @"\t<key>PayloadIdentifier</key>\n\t<string>ru.computershik.scam.roots</string>\n"
        @"\t<key>PayloadUUID</key>\n\t<string>%@</string>\n"
        @"\t<key>PayloadOrganization</key>\n\t<string>MAX</string>\n"
        @"\t<key>PayloadDisplayName</key>\n\t<string>Корни НУЦ Минцифры</string>\n"
        @"\t<key>PayloadDescription</key>\n"
        @"\t<string>Корневой и промежуточный сертификаты НУЦ Минцифры России. "
        @"По ним удостоверяется api2.oneme.ru, а в хранилище iOS их нет.</string>\n"
        @"\t<key>PayloadRemovalDisallowed</key>\n\t<false/>\n"
        @"</dict>\n"
        @"</plist>\n", payloads, MAXUuidString()];

    return [profile dataUsingEncoding:NSUTF8StringEncoding];
}

@end
