//
//  MAXDeviceIdentity.h
//  Max — постоянные идентификаторы устройства для хэндшейка.
//
//  Порт lib/core/storage/device_identity.dart.
//
//  deviceId        — 8 случайных байт в hex, живёт между запусками
//  instanceId      — UUID v4, живёт между запусками (поле mt_instanceid)
//  clientSessionId — случайное положительное 31-битное число на запуск
//

#import <Foundation/Foundation.h>

@interface MAXDeviceIdentity : NSObject

+ (NSString *)deviceId;
+ (NSString *)instanceId;
+ (long long)clientSessionId;

/// Новые значения deviceId/instanceId — используется при добавлении аккаунта.
+ (void)regenerate;

+ (NSString *)randomHexWithByteCount:(NSUInteger)byteCount;
+ (NSString *)uuidV4;
+ (long long)randomClientSessionId;

@end
