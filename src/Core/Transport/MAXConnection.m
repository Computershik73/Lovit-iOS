//
//  MAXConnection.m
//

#import "MAXConnection.h"
#import "MAXTls.h"
#import "MAXServerConfig.h"

static NSString *const MAXConnectionErrorDomain = @"ru.max.connection";

/// Сколько ждать данных за один заход. Между заходами поток отправляет
/// накопившееся, так что это же значение — верхняя граница задержки
/// отправки. Десятая доли секунды на глаз незаметна, а просыпаться чаще
/// незачем: в простое чат молчит минутами.
static const NSTimeInterval MAXConnectionReadSlice = 0.1;

/// Тайм-аут подключения и рукопожатия.
static const NSTimeInterval MAXConnectionTimeout = 20.0;

@implementation MAXConnection {
    MAXTls *_tls;
    NSThread *_worker;

    // Очередь на отправку. Пишет в неё кто угодно, разбирает — только поток
    // ввода-вывода: объект OpenSSL не рассчитан на два потока сразу.
    NSMutableArray *_outgoing;
    NSLock *_outgoingLock;

    NSString *_host;
    NSUInteger _port;
    BOOL _insecure;
    BOOL _running;
    MAXSocketState _state;
}

- (id)init {
    self = [super init];
    if (self) {
        _outgoing = [NSMutableArray array];
        _outgoingLock = [[NSLock alloc] init];
        _state = MAXSocketStateDisconnected;
    }
    return self;
}

- (void)dealloc {
    [self disconnect];
}

- (MAXSocketState)state {
    return _state;
}

- (BOOL)isConnected {
    return _state == MAXSocketStateConnected;
}

#pragma mark - Подключение

/**
 * Раньше здесь были NSStream и Secure Transport: поток с run loop, делегат,
 * события. Всё это заменено своим TLS на OpenSSL — и вместе с ним ушла
 * асинхронность, которую давал run loop.
 *
 * Причина смены — iOS 6. Сервер MAX согласовывает TLS 1.3, а на TLS 1.2 из
 * шифров той эпохи принимает ровно один, `ECDHE-RSA-AES128-SHA256`. Secure
 * Transport на iOS 6 его не предлагает, и рукопожатие не состаивается вовсе:
 * приложение просто не соединяется, сколько ни жди. Подробности — в MAXTls.h.
 *
 * Взамен здесь свой поток с простым циклом: отправить накопившееся, попробовать
 * прочитать, повторить. Внешне для MAXApi ничего не изменилось — те же вызовы
 * и те же колбэки делегата на главной очереди.
 */
- (void)connectToHost:(NSString *)host port:(NSUInteger)port allowInsecure:(BOOL)allowInsecure {
    [self disconnect];

    _host = [host copy];
    _port = port;
    _insecure = allowInsecure;
    _state = MAXSocketStateConnecting;
    _running = YES;

    _worker = [[NSThread alloc] initWithTarget:self selector:@selector(workerMain) object:nil];
    _worker.name = @"ru.max.socket";
    [_worker start];
}

- (void)disconnect {
    if (!_running && _tls == nil) return;

    _running = NO;
    _state = MAXSocketStateDisconnected;

    // Сам сокет закрывает поток ввода-вывода, когда увидит снятый флаг:
    // закрывать его отсюда — значит дёргать OpenSSL из чужого потока.
    _worker = nil;

    [_outgoingLock lock];
    [_outgoing removeAllObjects];
    [_outgoingLock unlock];
}

- (void)write:(NSData *)data {
    if (data.length == 0) return;

    [_outgoingLock lock];
    [_outgoing addObject:data];
    [_outgoingLock unlock];
}

#pragma mark - Поток ввода-вывода

- (void)workerMain {
    @autoreleasepool {
        NSLog(@"[Max/Сокет] поток пошёл: %@:%lu", _host, (unsigned long)_port);

        MAXTls *tls = [[MAXTls alloc] initWithHost:_host port:(uint16_t)_port];
        tls.insecure = _insecure;

        NSError *error = nil;
        if (![tls connectWithTimeout:MAXConnectionTimeout error:&error]) {
            NSLog(@"[Max/Сокет] не подключились: %@", error.localizedDescription);
            _state = MAXSocketStateDisconnected;
            _running = NO;
            [self reportFailure:error];
            return;
        }

        // Пока шло рукопожатие (а это до двадцати секунд), нас могли успеть
        // отключить. Без этой проверки делегат получил бы «подключено» уже
        // после того, как MAXApi решил, что соединения нет.
        if (!_running) {
            NSLog(@"[Max/Сокет] подключились, но нас уже отключили — закрываемся");
            [tls close];
            return;
        }

        _tls = tls;
        _state = MAXSocketStateConnected;
        [self reportConnected];

        // Короткий тайм-аут чтения — чтобы между чтениями успевать
        // отправлять накопившееся.
        [tls setReadTimeout:MAXConnectionReadSlice];

        uint8_t buffer[16384];

        while (_running) {
            @autoreleasepool {
                if (![self drainOutgoingThrough:tls]) break;

                NSError *ioError = nil;
                NSInteger got = [tls readBytes:buffer maxLength:sizeof(buffer) error:&ioError];

                if (got == MAXTlsReadTimedOut) continue;

                if (got > 0) {
                    NSData *chunk = [NSData dataWithBytes:buffer length:(NSUInteger)got];
                    [self reportData:chunk];
                    continue;
                }

                if (got == 0) {
                    // Сервер закрыл соединение — это не ошибка, а обычный
                    // конец сессии: реконнектом занимается MAXApi.
                    [self finishWithError:nil];
                    return;
                }

                [self finishWithError:ioError];
                return;
            }
        }

        [tls close];
        _tls = nil;
        _state = MAXSocketStateDisconnected;
    }
}

/// Отправляет всё, что накопилось в очереди. NO — соединение оборвалось.
- (BOOL)drainOutgoingThrough:(MAXTls *)tls {
    while (1) {
        NSData *next = nil;

        [_outgoingLock lock];
        if (_outgoing.count > 0) {
            next = _outgoing[0];
            [_outgoing removeObjectAtIndex:0];
        }
        [_outgoingLock unlock];

        if (next == nil) return YES;

        NSError *error = nil;
        if ([tls writeBytes:next.bytes length:next.length error:&error] < 0) {
            [self finishWithError:error];
            return NO;
        }
    }
}

- (void)finishWithError:(NSError *)error {
    NSLog(@"[Max/Сокет] поток закончился: %@",
          error != nil ? error.localizedDescription : @"сервер закрыл соединение");

    _running = NO;
    _state = MAXSocketStateDisconnected;

    [_tls close];
    _tls = nil;

    if (error != nil) {
        [self reportFailure:error];
    } else {
        [self reportDisconnect];
    }
}

#pragma mark - Колбэки делегата

// Все четыре уходят на главную очередь: делегат — MAXApi, а он трогает
// таймеры и уведомления, которым фоновый поток противопоказан.

- (void)reportConnected {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate connectionDidConnect:self];
    });
}

- (void)reportData:(NSData *)data {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate connection:self didReceiveData:data];
    });
}

- (void)reportDisconnect {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate connectionDidDisconnect:self];
    });
}

- (void)reportFailure:(NSError *)error {
    NSError *reported = error ?: [NSError errorWithDomain:MAXConnectionErrorDomain
                                                     code:1
                                                 userInfo:@{NSLocalizedDescriptionKey:
                                                     @"соединение не установлено"}];

    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate connection:self didFailWithError:reported];
    });
}

@end
