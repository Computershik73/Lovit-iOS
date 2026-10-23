//
//  MAXMessagePack.m
//

#import "MAXMessagePack.h"

NSString *const MAXMessagePackErrorDomain = @"ru.max.msgpack";

#pragma mark - Writer

static void MAXAppendByte(NSMutableData *out, uint8_t byte) {
    [out appendBytes:&byte length:1];
}

static void MAXAppendU8(NSMutableData *out, uint8_t prefix, uint8_t value) {
    uint8_t buf[2] = {prefix, value};
    [out appendBytes:buf length:2];
}

static void MAXAppendU16(NSMutableData *out, uint8_t prefix, uint16_t value) {
    uint8_t buf[3];
    buf[0] = prefix;
    buf[1] = (uint8_t)(value >> 8);
    buf[2] = (uint8_t)(value & 0xFF);
    [out appendBytes:buf length:3];
}

static void MAXAppendU32(NSMutableData *out, uint8_t prefix, uint32_t value) {
    uint8_t buf[5];
    buf[0] = prefix;
    buf[1] = (uint8_t)(value >> 24);
    buf[2] = (uint8_t)(value >> 16);
    buf[3] = (uint8_t)(value >> 8);
    buf[4] = (uint8_t)(value);
    [out appendBytes:buf length:5];
}

static void MAXAppendU64(NSMutableData *out, uint8_t prefix, uint64_t value) {
    uint8_t buf[9];
    buf[0] = prefix;
    for (int i = 0; i < 8; i++) {
        buf[1 + i] = (uint8_t)(value >> (56 - 8 * i));
    }
    [out appendBytes:buf length:9];
}

static void MAXPackObject(NSMutableData *out, id object);

static void MAXPackInteger(NSMutableData *out, long long value) {
    if (value >= 0) {
        unsigned long long u = (unsigned long long)value;
        if (u < 0x80ULL) {
            MAXAppendByte(out, (uint8_t)u);
        } else if (u <= UINT8_MAX) {
            MAXAppendU8(out, 0xCC, (uint8_t)u);
        } else if (u <= UINT16_MAX) {
            MAXAppendU16(out, 0xCD, (uint16_t)u);
        } else if (u <= UINT32_MAX) {
            MAXAppendU32(out, 0xCE, (uint32_t)u);
        } else {
            MAXAppendU64(out, 0xCF, u);
        }
        return;
    }
    if (value >= -32) {
        MAXAppendByte(out, (uint8_t)(0xE0 | (value + 32)));
    } else if (value >= INT8_MIN) {
        MAXAppendU8(out, 0xD0, (uint8_t)(int8_t)value);
    } else if (value >= INT16_MIN) {
        MAXAppendU16(out, 0xD1, (uint16_t)(int16_t)value);
    } else if (value >= INT32_MIN) {
        MAXAppendU32(out, 0xD2, (uint32_t)(int32_t)value);
    } else {
        MAXAppendU64(out, 0xD3, (uint64_t)value);
    }
}

static void MAXPackDouble(NSMutableData *out, double value) {
    union { double d; uint64_t u; } bits;
    bits.d = value;
    MAXAppendU64(out, 0xCB, bits.u);
}

static void MAXPackString(NSMutableData *out, NSString *string) {
    NSData *utf8 = [string dataUsingEncoding:NSUTF8StringEncoding];
    NSUInteger length = utf8.length;
    if (length < 32) {
        MAXAppendByte(out, (uint8_t)(0xA0 | length));
    } else if (length <= UINT8_MAX) {
        MAXAppendU8(out, 0xD9, (uint8_t)length);
    } else if (length <= UINT16_MAX) {
        MAXAppendU16(out, 0xDA, (uint16_t)length);
    } else {
        MAXAppendU32(out, 0xDB, (uint32_t)length);
    }
    [out appendData:utf8];
}

static void MAXPackData(NSMutableData *out, NSData *data) {
    NSUInteger length = data.length;
    if (length <= UINT8_MAX) {
        MAXAppendU8(out, 0xC4, (uint8_t)length);
    } else if (length <= UINT16_MAX) {
        MAXAppendU16(out, 0xC5, (uint16_t)length);
    } else {
        MAXAppendU32(out, 0xC6, (uint32_t)length);
    }
    [out appendData:data];
}

static void MAXPackArray(NSMutableData *out, NSArray *array) {
    NSUInteger count = array.count;
    if (count < 16) {
        MAXAppendByte(out, (uint8_t)(0x90 | count));
    } else if (count <= UINT16_MAX) {
        MAXAppendU16(out, 0xDC, (uint16_t)count);
    } else {
        MAXAppendU32(out, 0xDD, (uint32_t)count);
    }
    for (id item in array) {
        MAXPackObject(out, item);
    }
}

static void MAXPackDictionary(NSMutableData *out, NSDictionary *dictionary) {
    NSUInteger count = dictionary.count;
    if (count < 16) {
        MAXAppendByte(out, (uint8_t)(0x80 | count));
    } else if (count <= UINT16_MAX) {
        MAXAppendU16(out, 0xDE, (uint16_t)count);
    } else {
        MAXAppendU32(out, 0xDF, (uint32_t)count);
    }
    for (id key in dictionary) {
        MAXPackObject(out, key);
        MAXPackObject(out, dictionary[key]);
    }
}

static void MAXPackNumber(NSMutableData *out, NSNumber *number) {
    if (number == (id)kCFBooleanTrue) {
        MAXAppendByte(out, 0xC3);
        return;
    }
    if (number == (id)kCFBooleanFalse) {
        MAXAppendByte(out, 0xC2);
        return;
    }
    const char *type = [number objCType];
    if (type != NULL && (type[0] == 'f' || type[0] == 'd')) {
        MAXPackDouble(out, [number doubleValue]);
        return;
    }
    MAXPackInteger(out, [number longLongValue]);
}

static void MAXPackObject(NSMutableData *out, id object) {
    if (object == nil || object == [NSNull null]) {
        MAXAppendByte(out, 0xC0);
    } else if ([object isKindOfClass:[NSString class]]) {
        MAXPackString(out, object);
    } else if ([object isKindOfClass:[NSNumber class]]) {
        MAXPackNumber(out, object);
    } else if ([object isKindOfClass:[NSDictionary class]]) {
        MAXPackDictionary(out, object);
    } else if ([object isKindOfClass:[NSArray class]]) {
        MAXPackArray(out, object);
    } else if ([object isKindOfClass:[NSData class]]) {
        MAXPackData(out, object);
    } else {
        MAXPackString(out, [object description]);
    }
}

#pragma mark - Reader

typedef struct {
    const uint8_t *bytes;
    NSUInteger length;
    NSUInteger offset;
    BOOL failed;
} MAXUnpackCursor;

static BOOL MAXRequire(MAXUnpackCursor *cursor, NSUInteger count) {
    if (cursor->failed || cursor->offset + count > cursor->length) {
        cursor->failed = YES;
        return NO;
    }
    return YES;
}

static uint64_t MAXReadUInt(MAXUnpackCursor *cursor, NSUInteger width) {
    if (!MAXRequire(cursor, width)) return 0;
    uint64_t value = 0;
    for (NSUInteger i = 0; i < width; i++) {
        value = (value << 8) | cursor->bytes[cursor->offset + i];
    }
    cursor->offset += width;
    return value;
}

static id MAXReadObject(MAXUnpackCursor *cursor);

static id MAXReadString(MAXUnpackCursor *cursor, NSUInteger length) {
    if (!MAXRequire(cursor, length)) return nil;
    NSString *string = [[NSString alloc] initWithBytes:cursor->bytes + cursor->offset
                                                length:length
                                              encoding:NSUTF8StringEncoding];
    cursor->offset += length;
    if (string == nil) return @"";
    return string;
}

static id MAXReadData(MAXUnpackCursor *cursor, NSUInteger length) {
    if (!MAXRequire(cursor, length)) return nil;
    NSData *data = [NSData dataWithBytes:cursor->bytes + cursor->offset length:length];
    cursor->offset += length;
    return data;
}

static id MAXReadArray(MAXUnpackCursor *cursor, NSUInteger count) {
    NSMutableArray *array = [NSMutableArray arrayWithCapacity:count];
    for (NSUInteger i = 0; i < count; i++) {
        id item = MAXReadObject(cursor);
        if (cursor->failed) return nil;
        [array addObject:(item ?: [NSNull null])];
    }
    return array;
}

static id MAXReadMap(MAXUnpackCursor *cursor, NSUInteger count) {
    NSMutableDictionary *map = [NSMutableDictionary dictionaryWithCapacity:count];
    for (NSUInteger i = 0; i < count; i++) {
        id key = MAXReadObject(cursor);
        id value = MAXReadObject(cursor);
        if (cursor->failed) return nil;
        if (key == nil) continue;
        if (![key conformsToProtocol:@protocol(NSCopying)]) continue;
        [map setObject:(value ?: [NSNull null]) forKey:key];
    }
    return map;
}

static id MAXReadObject(MAXUnpackCursor *cursor) {
    if (!MAXRequire(cursor, 1)) return nil;
    uint8_t prefix = cursor->bytes[cursor->offset++];

    if (prefix <= 0x7F) return @(prefix);
    if (prefix >= 0xE0) return @((int8_t)prefix);
    if ((prefix & 0xF0) == 0x80) return MAXReadMap(cursor, prefix & 0x0F);
    if ((prefix & 0xF0) == 0x90) return MAXReadArray(cursor, prefix & 0x0F);
    if ((prefix & 0xE0) == 0xA0) return MAXReadString(cursor, prefix & 0x1F);

    switch (prefix) {
        case 0xC0: return [NSNull null];
        case 0xC2: return (id)kCFBooleanFalse;
        case 0xC3: return (id)kCFBooleanTrue;
        case 0xC4: return MAXReadData(cursor, (NSUInteger)MAXReadUInt(cursor, 1));
        case 0xC5: return MAXReadData(cursor, (NSUInteger)MAXReadUInt(cursor, 2));
        case 0xC6: return MAXReadData(cursor, (NSUInteger)MAXReadUInt(cursor, 4));
        case 0xC7: { NSUInteger n = (NSUInteger)MAXReadUInt(cursor, 1); MAXReadUInt(cursor, 1); return MAXReadData(cursor, n); }
        case 0xC8: { NSUInteger n = (NSUInteger)MAXReadUInt(cursor, 2); MAXReadUInt(cursor, 1); return MAXReadData(cursor, n); }
        case 0xC9: { NSUInteger n = (NSUInteger)MAXReadUInt(cursor, 4); MAXReadUInt(cursor, 1); return MAXReadData(cursor, n); }
        case 0xCA: {
            uint32_t raw = (uint32_t)MAXReadUInt(cursor, 4);
            union { uint32_t u; float f; } bits;
            bits.u = raw;
            return @(bits.f);
        }
        case 0xCB: {
            uint64_t raw = MAXReadUInt(cursor, 8);
            union { uint64_t u; double d; } bits;
            bits.u = raw;
            return @(bits.d);
        }
        case 0xCC: return @((uint8_t)MAXReadUInt(cursor, 1));
        case 0xCD: return @((uint16_t)MAXReadUInt(cursor, 2));
        case 0xCE: return @((uint32_t)MAXReadUInt(cursor, 4));
        case 0xCF: return @((unsigned long long)MAXReadUInt(cursor, 8));
        case 0xD0: return @((int8_t)MAXReadUInt(cursor, 1));
        case 0xD1: return @((int16_t)MAXReadUInt(cursor, 2));
        case 0xD2: return @((int32_t)MAXReadUInt(cursor, 4));
        case 0xD3: return @((long long)MAXReadUInt(cursor, 8));
        case 0xD4: { MAXReadUInt(cursor, 1); return MAXReadData(cursor, 1); }
        case 0xD5: { MAXReadUInt(cursor, 1); return MAXReadData(cursor, 2); }
        case 0xD6: { MAXReadUInt(cursor, 1); return MAXReadData(cursor, 4); }
        case 0xD7: { MAXReadUInt(cursor, 1); return MAXReadData(cursor, 8); }
        case 0xD8: { MAXReadUInt(cursor, 1); return MAXReadData(cursor, 16); }
        case 0xD9: return MAXReadString(cursor, (NSUInteger)MAXReadUInt(cursor, 1));
        case 0xDA: return MAXReadString(cursor, (NSUInteger)MAXReadUInt(cursor, 2));
        case 0xDB: return MAXReadString(cursor, (NSUInteger)MAXReadUInt(cursor, 4));
        case 0xDC: return MAXReadArray(cursor, (NSUInteger)MAXReadUInt(cursor, 2));
        case 0xDD: return MAXReadArray(cursor, (NSUInteger)MAXReadUInt(cursor, 4));
        case 0xDE: return MAXReadMap(cursor, (NSUInteger)MAXReadUInt(cursor, 2));
        case 0xDF: return MAXReadMap(cursor, (NSUInteger)MAXReadUInt(cursor, 4));
        default:
            cursor->failed = YES;
            return nil;
    }
}

#pragma mark -

@implementation MAXMessagePack

+ (NSData *)pack:(id)object {
    NSMutableData *out = [NSMutableData dataWithCapacity:256];
    MAXPackObject(out, object);
    return out;
}

+ (id)unpack:(NSData *)data error:(NSError **)error {
    if (data.length == 0) return nil;
    MAXUnpackCursor cursor;
    cursor.bytes = (const uint8_t *)data.bytes;
    cursor.length = data.length;
    cursor.offset = 0;
    cursor.failed = NO;

    id result = MAXReadObject(&cursor);
    if (cursor.failed) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:MAXMessagePackErrorDomain
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Повреждённый MessagePack"}];
        }
        return nil;
    }
    return result;
}

@end
