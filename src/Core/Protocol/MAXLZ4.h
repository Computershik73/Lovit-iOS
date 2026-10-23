//
//  MAXLZ4.h
//  Max — распаковка полезной нагрузки пакетов.
//
//  Порт lib/core/protocol/lz4_block.dart и _decompressPayload из packet.dart.
//  Сервер шлёт LZ4 block (без magic), реже LZ4 frame; Zstd встречается
//  в отдельных ответах и здесь не поддержан (см. README).
//

#import <Foundation/Foundation.h>

extern NSString *const MAXLZ4ErrorDomain;

typedef NS_ENUM(NSInteger, MAXLZ4Error) {
    MAXLZ4ErrorMalformed = 1,
    MAXLZ4ErrorLimitExceeded = 2,
    MAXLZ4ErrorUnsupportedZstd = 3
};

@interface MAXLZ4 : NSObject

/// LZ4 block без заголовка.
+ (NSData *)blockDecompress:(NSData *)source maxSize:(NSUInteger)maxSize error:(NSError **)error;

/// LZ4 frame (magic 04 22 4D 18).
+ (NSData *)frameDecompress:(NSData *)source maxSize:(NSUInteger)maxSize error:(NSError **)error;

/// Определяет формат по magic-number и распаковывает.
+ (NSData *)decompress:(NSData *)source maxSize:(NSUInteger)maxSize error:(NSError **)error;

/// LZ4 block сжатие. Используется, только когда включено сжатие исходящих
/// пакетов (см. MAXServerConfig.compressOutgoing).
+ (NSData *)blockCompress:(NSData *)source;

@end
