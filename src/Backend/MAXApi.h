//
//  MAXApi.h
//  Max — жизненный цикл сессии: подключение, хэндшейк, пинг, реконнект.
//
//  Порт lib/backend/api.dart.
//

#import <Foundation/Foundation.h>
#import "MAXPacket.h"

typedef NS_ENUM(NSInteger, MAXSessionState) {
    MAXSessionStateDisconnected = 0,
    MAXSessionStateConnecting,
    MAXSessionStateConnected,
    MAXSessionStateOnline
};

extern NSString *const MAXApiStateDidChangeNotification;
extern NSString *const MAXApiDidReceivePushNotification;   // userInfo[@"packet"]
extern NSString *const MAXApiSessionExpiredNotification;   // userInfo[@"message"]
extern NSString *const MAXApiErrorNotification;            // userInfo[@"message"]

extern NSString *const MAXApiErrorDomain;

typedef void (^MAXPacketCompletion)(MAXPacket *packet, NSError *error);

@interface MAXApi : NSObject

+ (instancetype)shared;

@property (nonatomic, readonly) MAXSessionState state;

/// Счёт сессий: растёт с каждым удачным рукопожатием.
///
/// Сервер держит незаконченный разговор — многошаговый вход, например —
/// при своей сессии. Оборвись связь и поднимись заново, и всё выданное в
/// прошлой сессии становится негодным, хотя со стороны клиента связь всё
/// это время выглядит целой. По этому числу и видно, та ли она.
@property (nonatomic, readonly) NSUInteger session;

/// Поля userAgent, ушедшие в SESSION_INIT (после подмены).
@property (nonatomic, readonly) NSDictionary *userAgent;
@property (nonatomic, readonly) NSString *deviceId;
/// Из ответа на SESSION_INIT; вместе с deviceId даёт chatCacheFingerprint.
@property (nonatomic, readonly) long long callsSeed;
@property (nonatomic, readonly) BOOL hasCallsSeed;

/// Скоуп профиля подмены. nil — активный аккаунт.
@property (nonatomic, copy) NSString *spoofScope;

/// Вызывается после успешного хэндшейка — сюда вешается авто-логин.
@property (nonatomic, copy) void (^reconnectHandler)(void);

- (void)connect;
- (void)disconnect;
/// Пробуждение из фона: реконнект либо проверка живости.
- (void)wakeUp;

- (void)sendRequestWithOpcode:(NSUInteger)opcode
                      payload:(NSDictionary *)payload
                   completion:(MAXPacketCompletion)completion;

/// То же, но ошибки сервера не показываются пользователю.
- (void)sendRequestWithOpcode:(NSUInteger)opcode
                      payload:(NSDictionary *)payload
                       silent:(BOOL)silent
                   completion:(MAXPacketCompletion)completion;

/// Отправка без ожидания ответа.
- (void)sendRequestWithOpcode:(NSUInteger)opcode payload:(NSDictionary *)payload;

/// Синхронизирует поле `interactive` в пинге с режимом невидимки.
- (void)refreshPingInteractive;

@end
