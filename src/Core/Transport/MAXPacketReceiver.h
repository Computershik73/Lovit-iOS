//
//  MAXPacketReceiver.h
//  Max — сборка целых пакетов из потока байтов сокета.
//
//  Порт lib/core/transport/receiver.dart.
//

#import <Foundation/Foundation.h>

extern const NSUInteger MAXReceiverMaxBufferSize; // 16 MB

@interface MAXPacketReceiver : NSObject

/// Возвращает массив NSData — по элементу на каждый целиком собранный пакет
/// (заголовок + payload). Хвост остаётся в буфере до следующего вызова.
/// Если буфер переполнен, возвращает nil и сбрасывает состояние.
- (NSArray *)feed:(NSData *)data;

- (void)reset;

@end
