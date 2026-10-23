//
//  MAXMessagePack.h
//  Max — MessagePack сериализация полезной нагрузки пакетов.
//
//  Порт msgpack_dart, который Komet использует в lib/core/protocol/packet.dart.
//  Соответствие типов:
//    NSDictionary <-> map, NSArray <-> array, NSString <-> str,
//    NSData <-> bin, NSNumber <-> int/uint/float/double/bool, NSNull <-> nil
//

#import <Foundation/Foundation.h>

extern NSString *const MAXMessagePackErrorDomain;

@interface MAXMessagePack : NSObject

+ (NSData *)pack:(id)object;
+ (id)unpack:(NSData *)data error:(NSError **)error;

@end
