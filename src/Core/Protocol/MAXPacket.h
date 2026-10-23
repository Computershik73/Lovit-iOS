//
//  MAXPacket.h
//  Max — распакованный бинарный пакет и (де)сериализация провода.
//
//  Порт lib/core/protocol/packet.dart.
//
//  Формат заголовка (10 байт):
//    [0]      ver       — версия протокола (uint8), всегда 10
//    [1]      cmd       — тип команды (uint8), у клиента всегда 0
//    [2..3]   seq       — порядковый номер (uint16 BE)
//    [4..5]   opcode    — код операции (uint16 BE)
//    [6..9]   packedLen — флаг сжатия [6] + длина payload [7..9] (uint32 BE)
//    [10..]   payload   — MessagePack, опционально сжатый LZ4
//
//  Старший байт packedLen — не идентификатор формата, а множитель размера:
//  0 — без сжатия, иначе (rawLen / compLen) + 1, по нему получатель выделяет
//  буфер под распаковку.
//

#import <Foundation/Foundation.h>

extern const NSUInteger MAXPacketHeaderSize;   // 10
extern const NSUInteger MAXPacketMaxDecompressedSize; // 32 MB
extern NSString *const MAXPacketErrorDomain;

typedef NS_ENUM(NSUInteger, MAXCmdType) {
    MAXCmdTypeRequest = 0,  // запрос клиента / пуш от сервера
    MAXCmdTypePush = 0,
    MAXCmdTypeOk = 1,
    MAXCmdTypeNotFound = 2,
    MAXCmdTypeError = 3
};

@interface MAXPacket : NSObject

@property (nonatomic, assign) NSUInteger api;
@property (nonatomic, assign) NSUInteger cmd;
@property (nonatomic, assign) NSUInteger seq;
@property (nonatomic, assign) NSUInteger opcode;
@property (nonatomic, strong) id payload;

@property (nonatomic, readonly) BOOL isOk;
@property (nonatomic, readonly) BOOL isError;
@property (nonatomic, readonly) BOOL isPush;

/// Payload как словарь либо nil.
@property (nonatomic, readonly) NSDictionary *payloadMap;

+ (instancetype)packetWithCmd:(NSUInteger)cmd
                          seq:(NSUInteger)seq
                       opcode:(NSUInteger)opcode
                      payload:(id)payload;

/// Собирает байты пакета для отправки серверу.
+ (NSData *)packOpcode:(NSUInteger)opcode payload:(NSDictionary *)payload seq:(NSUInteger)seq;

/// Разбирает один целиком принятый пакет.
+ (MAXPacket *)unpack:(NSData *)data error:(NSError **)error;

/// LZ4-сжатие исходящих пакетов. По умолчанию выключено.
+ (void)setCompressOutgoing:(BOOL)enabled;
+ (BOOL)compressOutgoing;

@end

/// Текст ошибки из payload ответа с cmd = error.
NSString *MAXMessageFromErrorPayload(id payload);

/// Сервер отверг токен — сессия истекла.
BOOL MAXIsSessionExpiredPayload(id payload);
