//
//  MAXLZ4.m
//

#import "MAXLZ4.h"

NSString *const MAXLZ4ErrorDomain = @"ru.max.lz4";

static NSError *MAXLZ4MakeError(MAXLZ4Error code, NSString *message) {
    return [NSError errorWithDomain:MAXLZ4ErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

/// Распаковывает один LZ4-блок, дописывая результат в конец `out`.
/// Уже накопленное в `out` содержимое работает как словарь — это нужно для
/// frame-формата со связанными блоками (B.Indep = 0).
static BOOL MAXLZ4DecompressBlockInto(const uint8_t *src,
                                      NSUInteger srcLength,
                                      NSMutableData *out,
                                      NSUInteger maxSize,
                                      NSError **error) {
    NSUInteger pos = 0;

    while (pos < srcLength) {
        uint8_t token = src[pos++];
        NSUInteger literalLength = token >> 4;

        if (literalLength == 15) {
            while (pos < srcLength) {
                uint8_t b = src[pos++];
                literalLength += b;
                if (b != 255) break;
            }
        }

        if (literalLength > 0) {
            if (pos + literalLength > srcLength) {
                if (error) *error = MAXLZ4MakeError(MAXLZ4ErrorMalformed, @"LZ4: обрыв литералов");
                return NO;
            }
            if (out.length + literalLength > maxSize) {
                if (error) *error = MAXLZ4MakeError(MAXLZ4ErrorLimitExceeded, @"LZ4: превышен лимит распаковки");
                return NO;
            }
            [out appendBytes:src + pos length:literalLength];
            pos += literalLength;
        }

        if (pos >= srcLength) break;

        if (pos + 1 >= srcLength) {
            if (error) *error = MAXLZ4MakeError(MAXLZ4ErrorMalformed, @"LZ4: обрыв смещения");
            return NO;
        }
        NSUInteger offset = (NSUInteger)src[pos] | ((NSUInteger)src[pos + 1] << 8);
        pos += 2;
        if (offset == 0 || offset > out.length) {
            if (error) *error = MAXLZ4MakeError(MAXLZ4ErrorMalformed, @"LZ4: некорректное смещение");
            return NO;
        }

        NSUInteger matchLength = (token & 0x0F) + 4;
        if ((token & 0x0F) == 0x0F) {
            while (pos < srcLength) {
                uint8_t b = src[pos++];
                matchLength += b;
                if (b != 255) break;
            }
        }

        if (out.length + matchLength > maxSize) {
            if (error) *error = MAXLZ4MakeError(MAXLZ4ErrorLimitExceeded, @"LZ4: превышен лимит распаковки");
            return NO;
        }

        [out increaseLengthBy:matchLength];
        uint8_t *base = (uint8_t *)out.mutableBytes;
        NSUInteger writeIndex = out.length - matchLength;
        NSUInteger readIndex = writeIndex - offset;
        for (NSUInteger i = 0; i < matchLength; i++) {
            base[writeIndex + i] = base[readIndex + i];
        }
    }

    return YES;
}

@implementation MAXLZ4

+ (NSData *)blockDecompress:(NSData *)source maxSize:(NSUInteger)maxSize error:(NSError **)error {
    if (source.length == 0) return [NSData data];
    NSMutableData *out = [NSMutableData dataWithCapacity:MIN(maxSize, source.length * 4)];
    if (!MAXLZ4DecompressBlockInto((const uint8_t *)source.bytes, source.length, out, maxSize, error)) {
        return nil;
    }
    return out;
}

+ (NSData *)frameDecompress:(NSData *)source maxSize:(NSUInteger)maxSize error:(NSError **)error {
    const uint8_t *bytes = (const uint8_t *)source.bytes;
    NSUInteger length = source.length;

    if (length < 7) {
        if (error) *error = MAXLZ4MakeError(MAXLZ4ErrorMalformed, @"LZ4 frame: слишком короткий заголовок");
        return nil;
    }

    NSUInteger pos = 4; // magic
    uint8_t flg = bytes[pos++];
    pos++; // BD

    BOOL hasContentSize = (flg & 0x08) != 0;
    BOOL hasContentChecksum = (flg & 0x04) != 0;
    BOOL hasBlockChecksum = (flg & 0x10) != 0;
    BOOL hasDictID = (flg & 0x01) != 0;

    if (hasContentSize) pos += 8;
    if (hasDictID) pos += 4;
    pos += 1; // header checksum

    if (pos > length) {
        if (error) *error = MAXLZ4MakeError(MAXLZ4ErrorMalformed, @"LZ4 frame: обрыв заголовка");
        return nil;
    }

    NSMutableData *out = [NSMutableData dataWithCapacity:MIN(maxSize, source.length * 4)];

    while (pos + 4 <= length) {
        uint32_t blockHeader = (uint32_t)bytes[pos]
                             | ((uint32_t)bytes[pos + 1] << 8)
                             | ((uint32_t)bytes[pos + 2] << 16)
                             | ((uint32_t)bytes[pos + 3] << 24);
        pos += 4;

        if (blockHeader == 0) break; // EndMark

        BOOL uncompressed = (blockHeader & 0x80000000u) != 0;
        NSUInteger blockSize = blockHeader & 0x7FFFFFFFu;

        if (pos + blockSize > length) {
            if (error) *error = MAXLZ4MakeError(MAXLZ4ErrorMalformed, @"LZ4 frame: обрыв блока");
            return nil;
        }

        if (uncompressed) {
            if (out.length + blockSize > maxSize) {
                if (error) *error = MAXLZ4MakeError(MAXLZ4ErrorLimitExceeded, @"LZ4 frame: превышен лимит");
                return nil;
            }
            [out appendBytes:bytes + pos length:blockSize];
        } else if (!MAXLZ4DecompressBlockInto(bytes + pos, blockSize, out, maxSize, error)) {
            return nil;
        }

        pos += blockSize;
        if (hasBlockChecksum) pos += 4;
    }

    if (hasContentChecksum) pos += 4;
    return out;
}

+ (NSData *)decompress:(NSData *)source maxSize:(NSUInteger)maxSize error:(NSError **)error {
    if (source.length >= 4) {
        const uint8_t *magic = (const uint8_t *)source.bytes;

        if (magic[0] == 0x28 && magic[1] == 0xB5 && magic[2] == 0x2F && magic[3] == 0xFD) {
            if (error) {
                *error = MAXLZ4MakeError(MAXLZ4ErrorUnsupportedZstd,
                                         @"Сервер прислал Zstandard — формат не поддержан этой сборкой");
            }
            return nil;
        }

        if (magic[0] == 0x04 && magic[1] == 0x22 && magic[2] == 0x4D && magic[3] == 0x18) {
            return [self frameDecompress:source maxSize:maxSize error:error];
        }
    }
    return [self blockDecompress:source maxSize:maxSize error:error];
}

#pragma mark - Compression

#define MAX_LZ4_HASH_LOG 12
#define MAX_LZ4_HASH_SIZE (1 << MAX_LZ4_HASH_LOG)
#define MAX_LZ4_MIN_MATCH 4
#define MAX_LZ4_LAST_LITERALS 5
#define MAX_LZ4_MF_LIMIT (MAX_LZ4_MIN_MATCH + MAX_LZ4_LAST_LITERALS + 1)

static uint32_t MAXLZ4Hash(const uint8_t *p) {
    uint32_t sequence = (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
    return (sequence * 2654435761u) >> (32 - MAX_LZ4_HASH_LOG);
}

static void MAXLZ4WriteLength(NSMutableData *out, NSUInteger length) {
    while (length >= 255) {
        uint8_t byte = 255;
        [out appendBytes:&byte length:1];
        length -= 255;
    }
    uint8_t tail = (uint8_t)length;
    [out appendBytes:&tail length:1];
}

+ (NSData *)blockCompress:(NSData *)source {
    const uint8_t *src = (const uint8_t *)source.bytes;
    NSUInteger srcLength = source.length;
    NSMutableData *out = [NSMutableData dataWithCapacity:srcLength];

    if (srcLength < MAX_LZ4_MF_LIMIT) {
        uint8_t token = (uint8_t)(srcLength < 15 ? (srcLength << 4) : 0xF0);
        [out appendBytes:&token length:1];
        if (srcLength >= 15) MAXLZ4WriteLength(out, srcLength - 15);
        [out appendBytes:src length:srcLength];
        return out;
    }

    NSInteger table[MAX_LZ4_HASH_SIZE];
    for (int i = 0; i < MAX_LZ4_HASH_SIZE; i++) table[i] = -1;

    NSUInteger anchor = 0;
    NSUInteger pos = 0;
    NSUInteger matchLimit = srcLength - MAX_LZ4_LAST_LITERALS;

    while (pos + MAX_LZ4_MF_LIMIT <= srcLength) {
        uint32_t hash = MAXLZ4Hash(src + pos);
        NSInteger candidate = table[hash];
        table[hash] = (NSInteger)pos;

        BOOL matched = candidate >= 0
                    && (pos - (NSUInteger)candidate) <= 0xFFFF
                    && src[candidate] == src[pos]
                    && src[candidate + 1] == src[pos + 1]
                    && src[candidate + 2] == src[pos + 2]
                    && src[candidate + 3] == src[pos + 3];
        if (!matched) {
            pos++;
            continue;
        }

        NSUInteger matchLength = MAX_LZ4_MIN_MATCH;
        while (pos + matchLength < matchLimit
               && src[candidate + matchLength] == src[pos + matchLength]) {
            matchLength++;
        }

        NSUInteger literalLength = pos - anchor;
        uint8_t token = (uint8_t)((literalLength < 15 ? literalLength : 15) << 4);
        NSUInteger encodedMatch = matchLength - MAX_LZ4_MIN_MATCH;
        token |= (uint8_t)(encodedMatch < 15 ? encodedMatch : 15);
        [out appendBytes:&token length:1];

        if (literalLength >= 15) MAXLZ4WriteLength(out, literalLength - 15);
        if (literalLength > 0) [out appendBytes:src + anchor length:literalLength];

        NSUInteger offset = pos - (NSUInteger)candidate;
        uint8_t offsetBytes[2] = {(uint8_t)(offset & 0xFF), (uint8_t)(offset >> 8)};
        [out appendBytes:offsetBytes length:2];

        if (encodedMatch >= 15) MAXLZ4WriteLength(out, encodedMatch - 15);

        pos += matchLength;
        anchor = pos;
    }

    NSUInteger literalLength = srcLength - anchor;
    uint8_t token = (uint8_t)((literalLength < 15 ? literalLength : 15) << 4);
    [out appendBytes:&token length:1];
    if (literalLength >= 15) MAXLZ4WriteLength(out, literalLength - 15);
    if (literalLength > 0) [out appendBytes:src + anchor length:literalLength];

    return out;
}

@end
