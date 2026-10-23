//
//  MAXChatCacheFingerprint.m
//

#import "MAXChatCacheFingerprint.h"
#import <CommonCrypto/CommonDigest.h>

static NSData *MAXDataFromHex(NSString *hex) {
    NSUInteger length = hex.length / 2;
    NSMutableData *data = [NSMutableData dataWithLength:length];
    uint8_t *bytes = (uint8_t *)data.mutableBytes;
    for (NSUInteger i = 0; i < length; i++) {
        NSString *pair = [hex substringWithRange:NSMakeRange(i * 2, 2)];
        unsigned int value = 0;
        [[NSScanner scannerWithString:pair] scanHexInt:&value];
        bytes[i] = (uint8_t)value;
    }
    return data;
}

@implementation MAXChatCacheFingerprint

+ (NSData *)signatureDigest {
    static NSData *digest = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        digest = MAXDataFromHex(@"1684414033eb263e2c615f8b7df5ed8793850a07656304997fbf07e9e21e1e93");
    });
    return digest;
}

+ (NSData *)soDigest {
    static NSData *digest = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        digest = MAXDataFromHex(@"634ecc42b246784d975f180b4fecf903df235cdf0476da47163a85630eb1a6a8");
    });
    return digest;
}

+ (NSData *)dexDigest {
    static NSData *digest = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        digest = MAXDataFromHex(@"38cff46f392dc1734c308be011c2f0d8da152a390b41063dbb2c913e3032f4b3");
    });
    return digest;
}

+ (NSData *)sha256OfA:(NSData *)a b:(NSData *)b c:(NSData *)c {
    CC_SHA256_CTX context;
    CC_SHA256_Init(&context);
    CC_SHA256_Update(&context, a.bytes, (CC_LONG)a.length);
    CC_SHA256_Update(&context, b.bytes, (CC_LONG)b.length);
    CC_SHA256_Update(&context, c.bytes, (CC_LONG)c.length);
    uint8_t digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256_Final(digest, &context);
    return [NSData dataWithBytes:digest length:CC_SHA256_DIGEST_LENGTH];
}

+ (NSData *)computeWithCallsSeed:(long long)callsSeed deviceId:(NSString *)deviceId {
    uint8_t seedBytes[8];
    for (int i = 0; i < 8; i++) {
        seedBytes[i] = (uint8_t)((uint64_t)callsSeed >> (56 - 8 * i));
    }
    NSData *seed = [NSData dataWithBytes:seedBytes length:8];
    NSData *device = [(deviceId ?: @"") dataUsingEncoding:NSUTF8StringEncoding];

    NSMutableData *result = [NSMutableData dataWithCapacity:96];
    [result appendData:[self sha256OfA:[self signatureDigest] b:seed c:device]];
    [result appendData:[self sha256OfA:[self dexDigest] b:seed c:device]];
    [result appendData:[self sha256OfA:[self soDigest] b:seed c:device]];
    return result;
}

@end
