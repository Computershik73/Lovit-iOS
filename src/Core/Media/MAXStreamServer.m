//
//  MAXStreamServer.m
//

#import "MAXStreamServer.h"
#import "MAXHttp.h"

#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <unistd.h>
#import <errno.h>

/// Сколько тянуть с CDN за один заход. Меньше — чаще ходим, больше — дольше
/// ждём первого кадра и больше держим в памяти. Полмегабайта на глаз: этого
/// хватает на несколько секунд обычного ролика.
static const NSUInteger MAXStreamSlice = 512 * 1024;

/// Предел на заголовок запроса от проигрывателя. Он короткий; всё, что
/// длиннее, — не он.
static const NSUInteger MAXStreamHeadLimit = 8 * 1024;

@interface MAXStreamServer ()
+ (instancetype)shared;
- (BOOL)start;
- (void)acceptLoop;
- (void)serve:(int)client;
- (void)pour:(id)record from:(long long)from to:(long long)to into:(int)client;
- (long long)totalFor:(id)record;
- (NSData *)fetch:(NSString *)remote from:(long long)from to:(long long)to;
- (NSString *)readHead:(int)client;
- (BOOL)readRange:(NSArray *)lines from:(long long *)from to:(long long *)to total:(long long)total;
- (NSString *)typeForPath:(NSString *)path;
- (BOOL)writeString:(NSString *)text to:(int)client;
- (BOOL)write:(const void *)bytes length:(NSUInteger)length to:(int)client;
@end

/// Заголовок ответа по имени: в разных местах они попадаются и строчными,
/// и как их написал сервер.
static NSString *MAXStreamHeader(NSHTTPURLResponse *response, NSString *name) {
    for (NSString *key in response.allHeaderFields) {
        if ([[key lowercaseString] isEqualToString:name]) {
            return [response.allHeaderFields[key] description];
        }
    }
    return nil;
}

@interface MAXStreamRecord : NSObject
@property (nonatomic, copy) NSString *remote;
@property (nonatomic, assign) long long total;    // 0 — ещё не спрашивали
@end

@implementation MAXStreamRecord
@end

@implementation MAXStreamServer {
    int _listener;
    uint16_t _port;
    NSMutableDictionary *_records;   // имя ссылки -> MAXStreamRecord
    NSLock *_lock;
}

+ (instancetype)shared {
    static MAXStreamServer *instance = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [[MAXStreamServer alloc] init]; });
    return instance;
}

- (id)init {
    self = [super init];
    if (self != nil) {
        _listener = -1;
        _records = [NSMutableDictionary dictionary];
        _lock = [[NSLock alloc] init];
    }
    return self;
}

#pragma mark - Наружу

+ (NSURL *)localURLForRemoteURL:(NSString *)remote name:(NSString *)name {
    if (remote.length == 0) return nil;

    MAXStreamServer *server = [self shared];
    if (![server start]) return nil;

    MAXStreamRecord *record = [[MAXStreamRecord alloc] init];
    record.remote = remote;

    // Имя случайное: местный адрес всё-таки адрес, и угадывать его не
    // должно быть можно.
    NSString *token = [NSString stringWithFormat:@"%08x%08x", arc4random(), arc4random()];
    NSString *tail = [name.pathExtension length] > 0 ? name.pathExtension : @"mp4";

    [server->_lock lock];
    // Больше десятка ссылок разом не нужно: открывают ролики по одному,
    // а старые записи держат только адрес.
    if (server->_records.count > 12) [server->_records removeAllObjects];
    server->_records[token] = record;
    [server->_lock unlock];

    return [NSURL URLWithString:
            [NSString stringWithFormat:@"http://127.0.0.1:%u/%@.%@",
             (unsigned)server->_port, token, tail]];
}

#pragma mark - Сам сервер

- (BOOL)start {
    [_lock lock];
    BOOL alive = (_listener >= 0);
    [_lock unlock];
    if (alive) return YES;

    int sock = socket(AF_INET, SOCK_STREAM, 0);
    if (sock < 0) return NO;

    int yes = 1;
    setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));
    // Без этого запись в закрытый сокет уносит приложение сигналом, а
    // проигрыватель закрывает соединения постоянно — на каждой перемотке.
    setsockopt(sock, SOL_SOCKET, SO_NOSIGPIPE, &yes, sizeof(yes));

    struct sockaddr_in address;
    memset(&address, 0, sizeof(address));
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);   // только петля
    address.sin_port = 0;                               // порт любой свободный

    if (bind(sock, (struct sockaddr *)&address, sizeof(address)) < 0
        || listen(sock, 8) < 0) {
        close(sock);
        return NO;
    }

    socklen_t length = sizeof(address);
    if (getsockname(sock, (struct sockaddr *)&address, &length) < 0) {
        close(sock);
        return NO;
    }

    [_lock lock];
    _listener = sock;
    _port = ntohs(address.sin_port);
    [_lock unlock];

    NSLog(@"[Max/Поток] сервер на 127.0.0.1:%u", (unsigned)_port);

    [NSThread detachNewThreadSelector:@selector(acceptLoop) toTarget:self withObject:nil];
    return YES;
}

- (void)acceptLoop {
    while (YES) {
        int client = accept(_listener, NULL, NULL);
        if (client < 0) {
            if (errno == EINTR) continue;
            NSLog(@"[Max/Поток] приём оборвался: %d", errno);
            return;
        }

        int yes = 1;
        setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &yes, sizeof(yes));

        NSLog(@"[Max/Поток] проигрыватель подключился");

        // Каждое соединение — своей очередью: проигрыватель держит их
        // несколько разом (звук и картинка читаются порознь).
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            @autoreleasepool {
                [self serve:client];
                close(client);
            }
        });
    }
}

#pragma mark - Один запрос

- (void)serve:(int)client {
    NSString *head = [self readHead:client];
    if (head.length == 0) return;

    NSArray *lines = [head componentsSeparatedByString:@"\r\n"];
    NSArray *first = [lines[0] componentsSeparatedByString:@" "];
    if (first.count < 2) return;

    NSString *method = first[0];
    NSString *path = first[1];

    NSLog(@"[Max/Поток] просят: %@", lines[0]);

    // Имя ссылки — то, что между «/» и точкой.
    NSString *token = [[path lastPathComponent] stringByDeletingPathExtension];

    [_lock lock];
    MAXStreamRecord *record = _records[token];
    [_lock unlock];

    if (record == nil) {
        [self writeString:@"HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n\r\n" to:client];
        return;
    }

    long long total = [self totalFor:record];
    if (total <= 0) {
        [self writeString:@"HTTP/1.1 502 Bad Gateway\r\nContent-Length: 0\r\n\r\n" to:client];
        return;
    }

    long long from = 0;
    long long to = total - 1;
    BOOL partial = [self readRange:lines from:&from to:&to total:total];

    if (from > to || from >= total) {
        [self writeString:[NSString stringWithFormat:
                           @"HTTP/1.1 416 Requested Range Not Satisfiable\r\n"
                           @"Content-Range: bytes */%lld\r\nContent-Length: 0\r\n\r\n", total]
                       to:client];
        return;
    }

    NSMutableString *answer = [NSMutableString string];
    [answer appendFormat:@"HTTP/1.1 %@\r\n", partial ? @"206 Partial Content" : @"200 OK"];
    [answer appendString:@"Accept-Ranges: bytes\r\n"];
    [answer appendFormat:@"Content-Type: %@\r\n", [self typeForPath:path]];
    [answer appendFormat:@"Content-Length: %lld\r\n", to - from + 1];
    if (partial) {
        [answer appendFormat:@"Content-Range: bytes %lld-%lld/%lld\r\n", from, to, total];
    }
    [answer appendString:@"Connection: close\r\n\r\n"];

    if (![self writeString:answer to:client]) return;

    // На HEAD тело не полагается: проигрыватель иногда начинает с него.
    if ([method isEqualToString:@"HEAD"]) return;

    [self pour:record from:from to:to into:client];
}

/// Тело ответа: тянем с CDN кусками и сразу отдаём проигрывателю.
///
/// Следующий кусок заказывается **до** того, как отдан нынешний: пока
/// проигрыватель принимает эти полмегабайта, следующие уже едут. Иначе на
/// каждом куске выходила бы пауза в целый обмен с сервером, и на неспешной
/// сети ролик дёргался бы раз в несколько секунд.
- (void)pour:(MAXStreamRecord *)record from:(long long)from to:(long long)to into:(int)client {
    long long at = from;
    NSData *slice = [self fetch:record.remote from:at to:MIN(to, at + (long long)MAXStreamSlice - 1)];

    while (slice.length > 0) {
        NSUInteger wanted = (NSUInteger)MIN(to - at + 1, (long long)MAXStreamSlice);

        // Сервер мог не понять диапазона и прислать больше, чем просили, —
        // лишнее отрезаем: проигрывателю обещана ровно та длина, что стоит
        // в заголовке.
        if (slice.length > wanted) slice = [slice subdataWithRange:NSMakeRange(0, wanted)];

        // Начало файла — в журнал: по этим байтам видно марку ролика, а
        // значит и то, возьмётся ли за него старая прошивка.
        if (at == 0 && slice.length >= 16) {
            NSLog(@"[Max/Поток] начало ролика: %@",
                  [slice subdataWithRange:NSMakeRange(0, 16)]);
        }

        long long following = at + (long long)slice.length;

        // Заказ следующего куска — в сторону, отдача нынешнего — здесь.
        __block NSData *ahead = nil;
        dispatch_semaphore_t ready = NULL;

        if (following <= to) {
            long long last = MIN(to, following + (long long)MAXStreamSlice - 1);
            ready = dispatch_semaphore_create(0);

            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                ahead = [self fetch:record.remote from:following to:last];
                dispatch_semaphore_signal(ready);
            });
        }

        BOOL sent = [self write:slice.bytes length:slice.length to:client];

        // Дождаться подкачки нужно в любом случае, даже если отдавать уже
        // некому: иначе блок останется писать в отпущенную переменную.
        if (ready != NULL) dispatch_semaphore_wait(ready, DISPATCH_TIME_FOREVER);

        if (!sent) {
            // Обычное дело: перемотали — проигрыватель бросил это соединение
            // и открыл другое.
            return;
        }

        at = following;
        slice = ahead;
    }

    if (at <= to) NSLog(@"[Max/Поток] кусок с %lld не пришёл", at);
}

#pragma mark - Наружу, за роликом

/// Длина ролика целиком. Спрашивается одним байтом: в ответе на диапазон
/// сервер называет и полный размер.
- (long long)totalFor:(MAXStreamRecord *)record {
    [_lock lock];
    long long known = record.total;
    [_lock unlock];
    if (known > 0) return known;

    // Спрашиваем одним байтом, а не HEAD. HEAD выглядел аккуратнее — и
    // именно он подвесил потоковое видео в 1.0.60: CDN на него не ответил
    // вовсе, а предела ожидания в нашем HTTP тогда не было, и поток встал
    // навсегда. На запрос куска CDN отвечает всегда, и в ответе называет
    // полный размер.
    NSMutableURLRequest *probe =
        [NSMutableURLRequest requestWithURL:[NSURL URLWithString:record.remote]];
    [probe setValue:@"bytes=0-0" forHTTPHeaderField:@"Range"];

    NSHTTPURLResponse *probed = nil;
    NSError *trouble = nil;
    NSData *answer = [MAXHttp sendSynchronousRequest:probe response:&probed error:&trouble];

    NSString *range = MAXStreamHeader(probed, @"content-range");
    long long total = 0;

    NSRange slash = [range rangeOfString:@"/" options:NSBackwardsSearch];
    if (slash.location != NSNotFound) {
        total = [[range substringFromIndex:slash.location + 1] longLongValue];
    }

    if (total <= 0) {
        NSLog(@"[Max/Поток] длина не выяснилась: пришло %lu Б, ответ %ld, %@",
              (unsigned long)answer.length, (long)probed.statusCode,
              trouble.localizedDescription ?: @"без ошибки");
        return 0;
    }

    [_lock lock];
    record.total = total;
    [_lock unlock];

    NSLog(@"[Max/Поток] ролик целиком %lld Б", total);
    return total;
}

- (NSData *)fetch:(NSString *)remote from:(long long)from to:(long long)to {
    NSMutableURLRequest *request =
        [NSMutableURLRequest requestWithURL:[NSURL URLWithString:remote]];
    [request setValue:[NSString stringWithFormat:@"bytes=%lld-%lld", from, to]
   forHTTPHeaderField:@"Range"];

    return [MAXHttp sendSynchronousRequest:request response:NULL error:NULL];
}

#pragma mark - Мелочи разбора

- (NSString *)readHead:(int)client {
    NSMutableData *head = [NSMutableData data];
    uint8_t buffer[1024];

    while (head.length < MAXStreamHeadLimit) {
        ssize_t got = recv(client, buffer, sizeof(buffer), 0);
        if (got <= 0) return nil;

        [head appendBytes:buffer length:(NSUInteger)got];

        NSData *border = [@"\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding];
        NSRange found = [head rangeOfData:border
                                  options:0
                                    range:NSMakeRange(0, head.length)];
        if (found.location != NSNotFound) {
            return [[NSString alloc] initWithData:
                    [head subdataWithRange:NSMakeRange(0, found.location)]
                                         encoding:NSUTF8StringEncoding];
        }
    }
    return nil;
}

/// `Range: bytes=от-до`. Обе стороны необязательны: бывает и «с такого-то
/// байта до конца», и «последние столько-то байт» — последним проигрыватель
/// и добирает `moov`, если тот лежит в хвосте.
- (BOOL)readRange:(NSArray *)lines from:(long long *)from to:(long long *)to total:(long long)total {
    for (NSString *line in lines) {
        if (![[line lowercaseString] hasPrefix:@"range:"]) continue;

        NSString *value = [[line substringFromIndex:6]
                           stringByTrimmingCharactersInSet:
                           [NSCharacterSet whitespaceCharacterSet]];
        if (![[value lowercaseString] hasPrefix:@"bytes="]) return NO;

        NSString *pair = [value substringFromIndex:6];
        NSRange dash = [pair rangeOfString:@"-"];
        if (dash.location == NSNotFound) return NO;

        NSString *left = [pair substringToIndex:dash.location];
        NSString *right = [pair substringFromIndex:dash.location + 1];

        if (left.length == 0) {
            long long tail = [right longLongValue];
            if (tail <= 0) return NO;
            *from = MAX(0LL, total - tail);
            *to = total - 1;
            return YES;
        }

        *from = [left longLongValue];
        *to = right.length > 0 ? MIN([right longLongValue], total - 1) : total - 1;
        return YES;
    }
    return NO;
}

- (NSString *)typeForPath:(NSString *)path {
    NSString *extension = [[path pathExtension] lowercaseString];

    if ([extension isEqualToString:@"mov"]) return @"video/quicktime";
    if ([extension isEqualToString:@"m4v"]) return @"video/x-m4v";
    if ([extension isEqualToString:@"m4a"]) return @"audio/mp4";
    return @"video/mp4";
}

#pragma mark - Запись в сокет

- (BOOL)writeString:(NSString *)text to:(int)client {
    NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding];
    return [self write:data.bytes length:data.length to:client];
}

/// Сокет берёт сколько может, а не сколько дали, — отсюда цикл.
- (BOOL)write:(const void *)bytes length:(NSUInteger)length to:(int)client {
    const uint8_t *at = bytes;
    NSUInteger left = length;

    while (left > 0) {
        ssize_t sent = send(client, at, left, 0);
        if (sent > 0) {
            at += sent;
            left -= (NSUInteger)sent;
            continue;
        }
        if (sent < 0 && errno == EINTR) continue;
        return NO;
    }
    return YES;
}

@end
