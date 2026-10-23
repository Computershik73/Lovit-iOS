//
//  MAXConnection.h
//  Max — TCP + TLS сокет на NSStream.
//
//  Порт lib/core/transport/connection.dart. Отдаёт сырые байты делегату,
//  сборкой пакетов занимается MAXPacketReceiver.
//
//  Потоки живут на выделенном треде с собственным run loop; все колбэки
//  делегата приходят на главную очередь.
//

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, MAXSocketState) {
    MAXSocketStateDisconnected = 0,
    MAXSocketStateConnecting,
    MAXSocketStateConnected
};

@class MAXConnection;

@protocol MAXConnectionDelegate <NSObject>
- (void)connection:(MAXConnection *)connection didReceiveData:(NSData *)data;
- (void)connectionDidConnect:(MAXConnection *)connection;
- (void)connection:(MAXConnection *)connection didFailWithError:(NSError *)error;
- (void)connectionDidDisconnect:(MAXConnection *)connection;
@end

@interface MAXConnection : NSObject

@property (nonatomic, weak) id<MAXConnectionDelegate> delegate;
@property (nonatomic, readonly) MAXSocketState state;
@property (nonatomic, readonly) BOOL isConnected;

/// `allowInsecure` отключает проверку цепочки сертификатов. Нужен для сервера
/// с CA Минцифры, которого нет в системном хранилище iOS 6 —
/// аналог ServerConfig.trustMincifryCa в Komet.
- (void)connectToHost:(NSString *)host port:(NSUInteger)port allowInsecure:(BOOL)allowInsecure;

- (void)write:(NSData *)data;
- (void)disconnect;

@end
