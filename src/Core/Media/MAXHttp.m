//
//  MAXHttp.m
//

#import "MAXHttp.h"
#import "MAXTls.h"
#import "MAXServerConfig.h"

static NSString *const MAXHttpErrorDomain = @"ru.max.http";

static const NSTimeInterval MAXHttpTimeout = 30.0;
static const NSUInteger MAXHttpMaxRedirects = 5;
static const NSUInteger MAXHttpMaxBody = 64 * 1024 * 1024;   // страховка от бесконечного ответа

/// Сколько соединение ждёт следующего запроса, прежде чем его закрыть.
/// Больше держать бессмысленно: сервер закрывает раньше нас, и мы получаем
/// только лишнюю попытку с повтором.
static const NSTimeInterval MAXHttpKeepAlive = 20.0;

static NSError *MAXHttpError(NSInteger code, NSString *text) {
    return [NSError errorWithDomain:MAXHttpErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: text}];
}

#pragma mark - Пул соединений

/**
 * Живые соединения между запросами.
 *
 * Каждое рукопожатие — это пара оборотов до сервера и проверка цепочки,
 * то есть сотни миллисекунд на телефоне 2010 года. Список чатов с полусотней
 * аватарок платил эту цену полсотни раз; с пулом остаётся несколько
 * рукопожатий на весь список, дальше идут запросы по готовым соединениям.
 *
 * Соединение возвращается в пул, только если ответ дочитан до конца
 * и обе стороны согласны продолжать: иначе в трубе остаётся хвост чужого
 * ответа, и следующий запрос прочитает мусор вместо заголовков.
 */
@interface MAXHttpIdleConnection : NSObject
@property (nonatomic, strong) MAXTls *tls;
@property (nonatomic, strong) NSDate *since;
@end

@implementation MAXHttpIdleConnection
@end

static NSMutableDictionary *MAXHttpPool(void) {
    static NSMutableDictionary *pool = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ pool = [NSMutableDictionary dictionary]; });
    return pool;
}

static id MAXHttpPoolLock(void) {
    static NSLock *lock = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ lock = [[NSLock alloc] init]; });
    return lock;
}

static MAXTls *MAXHttpTakeConnection(NSString *key) {
    NSLock *lock = MAXHttpPoolLock();
    [lock lock];

    NSMutableArray *waiting = MAXHttpPool()[key];
    MAXTls *found = nil;

    while (waiting.count > 0) {
        MAXHttpIdleConnection *idle = [waiting lastObject];
        [waiting removeLastObject];

        // Просроченные закрываем, не пытаясь использовать: сервер их
        // наверняка уже закрыл со своей стороны.
        if (-[idle.since timeIntervalSinceNow] > MAXHttpKeepAlive) {
            [idle.tls close];
            continue;
        }

        found = idle.tls;
        break;
    }

    [lock unlock];
    return found;
}

static void MAXHttpReturnConnection(NSString *key, MAXTls *tls) {
    MAXHttpIdleConnection *idle = [[MAXHttpIdleConnection alloc] init];
    idle.tls = tls;
    idle.since = [NSDate date];

    NSLock *lock = MAXHttpPoolLock();
    [lock lock];

    NSMutableArray *waiting = MAXHttpPool()[key];
    if (waiting == nil) {
        waiting = [NSMutableArray array];
        MAXHttpPool()[key] = waiting;
    }

    // Больше четырёх на узел не держим: картинки грузятся в несколько
    // потоков, но десятки открытых сокетов не нужны никому.
    if (waiting.count >= 4) {
        [((MAXHttpIdleConnection *)waiting[0]).tls close];
        [waiting removeObjectAtIndex:0];
    }

    [waiting addObject:idle];
    [lock unlock];
}

#pragma mark - Чтение ответа

/// Заголовки: читаем, пока не встретится пустая строка. Всё, что прочлось
/// после неё, — уже начало тела, и его надо не потерять.
/// Сколько ждать молчания, прежде чем считать запрос пропавшим.
///
/// Раньше предела не было вовсе: чтение, встретив тишину, заходило на новый
/// круг — и так без конца. Пока все запросы были обычными GET, это сходило
/// с рук; но стоило спросить у CDN то, на что он не отвечает, как поток
/// вставал навсегда, молча и без следа в журнале. Именно так и пропало
/// потоковое видео в 1.0.60.
///
/// Считается от последних пришедших байтов, а не от начала запроса: большой
/// файл может качаться долго, и обрывать его посреди незачем.
static const NSTimeInterval MAXHttpQuiet = 30.0;

/// Не пора ли сдаться. `since` — когда в последний раз что-то пришло.
static BOOL MAXHttpGaveUp(NSTimeInterval since, NSError **error) {
    if ([NSDate timeIntervalSinceReferenceDate] - since < MAXHttpQuiet) return NO;

    if (error) *error = MAXHttpError(2, @"сервер молчит");
    return YES;
}

static NSString *MAXHttpReadHead(MAXTls *tls, NSMutableData *tail, NSError **error) {
    NSMutableData *head = [NSMutableData data];
    uint8_t buffer[4096];

    NSData *separator = [@"\r\n\r\n" dataUsingEncoding:NSASCIIStringEncoding];
    NSTimeInterval heard = [NSDate timeIntervalSinceReferenceDate];

    while (1) {
        NSInteger got = [tls readBytes:buffer maxLength:sizeof(buffer) error:error];
        if (got == MAXTlsReadTimedOut) {
            if (MAXHttpGaveUp(heard, error)) return nil;
            continue;
        }
        heard = [NSDate timeIntervalSinceReferenceDate];
        if (got < 0) return nil;

        if (got == 0) {
            if (error) *error = MAXHttpError(2, @"соединение закрыто до заголовков");
            return nil;
        }

        [head appendBytes:buffer length:(NSUInteger)got];

        NSRange border = [head rangeOfData:separator
                                   options:0
                                     range:NSMakeRange(0, head.length)];
        if (border.location != NSNotFound) {
            NSUInteger bodyStart = border.location + border.length;
            [tail appendData:[head subdataWithRange:
                              NSMakeRange(bodyStart, head.length - bodyStart)]];

            NSData *headOnly = [head subdataWithRange:NSMakeRange(0, border.location)];
            return [[NSString alloc] initWithData:headOnly encoding:NSISOLatin1StringEncoding];
        }

        if (head.length > 128 * 1024) {
            if (error) *error = MAXHttpError(2, @"заголовки без конца");
            return nil;
        }
    }
}

/// Тело, длина которого объявлена заранее.
static NSData *MAXHttpReadFixed(MAXTls *tls, NSMutableData *already,
                                NSUInteger length, NSError **error) {
    NSMutableData *body = [already mutableCopy];
    uint8_t buffer[32768];

    NSTimeInterval heard = [NSDate timeIntervalSinceReferenceDate];

    while (body.length < length) {
        NSInteger got = [tls readBytes:buffer maxLength:sizeof(buffer) error:error];
        if (got == MAXTlsReadTimedOut) {
            if (MAXHttpGaveUp(heard, error)) return nil;
            continue;
        }
        heard = [NSDate timeIntervalSinceReferenceDate];
        if (got < 0) return nil;
        if (got == 0) break;            // сервер закрыл раньше обещанного — отдаём что есть

        [body appendBytes:buffer length:(NSUInteger)got];

        if (body.length > MAXHttpMaxBody) {
            if (error) *error = MAXHttpError(2, @"ответ длиннее разумного");
            return nil;
        }
    }

    return body;
}

/// Тело «кусками»: перед каждым куском идёт его длина шестнадцатеричным
/// числом, нулевая длина означает конец. Так отвечают, когда размер заранее
/// неизвестен.
static NSData *MAXHttpReadChunked(MAXTls *tls, NSMutableData *already, NSError **error) {
    NSMutableData *buffered = [already mutableCopy];
    NSMutableData *body = [NSMutableData data];
    uint8_t buffer[32768];

    NSData *crlf = [@"\r\n" dataUsingEncoding:NSASCIIStringEncoding];

    while (1) {
        NSRange lineEnd = [buffered rangeOfData:crlf options:0
                                          range:NSMakeRange(0, buffered.length)];

        NSTimeInterval heard = [NSDate timeIntervalSinceReferenceDate];

        while (lineEnd.location == NSNotFound) {
            NSInteger got = [tls readBytes:buffer maxLength:sizeof(buffer) error:error];
            if (got == MAXTlsReadTimedOut) {
                if (MAXHttpGaveUp(heard, error)) return nil;
                continue;
            }
            heard = [NSDate timeIntervalSinceReferenceDate];
            if (got < 0) return nil;
            if (got == 0) return body;      // оборвалось — отдаём собранное

            [buffered appendBytes:buffer length:(NSUInteger)got];
            lineEnd = [buffered rangeOfData:crlf options:0
                                      range:NSMakeRange(0, buffered.length)];
        }

        NSString *sizeLine = [[NSString alloc]
            initWithData:[buffered subdataWithRange:NSMakeRange(0, lineEnd.location)]
                encoding:NSASCIIStringEncoding];

        // После длины через точку с запятой могут идти «расширения» —
        // их никто не использует, но отрезать надо.
        NSRange semicolon = [sizeLine rangeOfString:@";"];
        if (semicolon.location != NSNotFound) {
            sizeLine = [sizeLine substringToIndex:semicolon.location];
        }

        unsigned int chunkSize = 0;
        if (sizeLine.length == 0 ||
            ![[NSScanner scannerWithString:sizeLine] scanHexInt:&chunkSize]) {
            if (error) *error = MAXHttpError(2, @"нечитаемая длина куска");
            return nil;
        }

        [buffered replaceBytesInRange:NSMakeRange(0, lineEnd.location + lineEnd.length)
                            withBytes:NULL length:0];

        if (chunkSize == 0) return body;    // последний кусок

        NSUInteger need = (NSUInteger)chunkSize + 2;   // сам кусок плюс завершающий CRLF
        while (buffered.length < need) {
            NSInteger got = [tls readBytes:buffer maxLength:sizeof(buffer) error:error];
            if (got == MAXTlsReadTimedOut) continue;
            if (got < 0) return nil;
            if (got == 0) return body;

            [buffered appendBytes:buffer length:(NSUInteger)got];
        }

        [body appendData:[buffered subdataWithRange:NSMakeRange(0, chunkSize)]];
        [buffered replaceBytesInRange:NSMakeRange(0, need) withBytes:NULL length:0];

        if (body.length > MAXHttpMaxBody) {
            if (error) *error = MAXHttpError(2, @"ответ длиннее разумного");
            return nil;
        }
    }
}

#pragma mark - Запрос

@implementation MAXHttp

/**
 * Один заход: взять соединение (из пула или новое), отправить, прочитать.
 *
 * `reused` говорит вызывающему, было ли соединение из пула. Это важно для
 * повтора: соединение, взятое из пула, могло быть закрыто сервером, пока
 * лежало без дела, и обрыв на первом же чтении — не ошибка сети, а обычное
 * дело. Новое же соединение, оборвавшееся сразу, — это уже настоящий отказ,
 * и повторять его незачем.
 */
+ (NSData *)attemptRequest:(NSURLRequest *)request
                 redirects:(NSUInteger)redirects
                  response:(NSHTTPURLResponse **)response
                    reused:(BOOL *)reused
                     error:(NSError **)error {
    if (redirects > MAXHttpMaxRedirects) {
        if (error) *error = MAXHttpError(3, @"слишком много переадресаций");
        return nil;
    }

    NSURL *url = request.URL;
    if (url.host.length == 0) {
        if (error) *error = MAXHttpError(1, @"нечитаемый адрес");
        return nil;
    }

    if (![[url.scheme lowercaseString] isEqualToString:@"https"]) {
        // Незашифрованных запросов приложение не делает вовсе: единственное,
        // ради чего писался свой транспорт, — контроль над TLS, и дыра
        // в виде http:// обесценила бы всё остальное.
        if (error) *error = MAXHttpError(1, @"поддерживается только https");
        return nil;
    }

    uint16_t port = url.port != nil ? (uint16_t)url.port.intValue : 443;

    NSString *path = url.path.length > 0 ? url.path : @"/";
    if (url.query.length > 0) path = [path stringByAppendingFormat:@"?%@", url.query];

    NSString *poolKey = [NSString stringWithFormat:@"%@:%u", url.host, (unsigned)port];

    MAXTls *tls = MAXHttpTakeConnection(poolKey);
    if (reused != NULL) *reused = (tls != nil);

    if (tls == nil) {
        tls = [[MAXTls alloc] initWithHost:url.host port:port];
        tls.insecure = [MAXServerConfig insecureTlsAllowed];

        if (![tls connectWithTimeout:MAXHttpTimeout error:error]) return nil;
    }

    // --- запрос ---

    NSString *method = request.HTTPMethod.length > 0 ? request.HTTPMethod : @"GET";
    NSData *body = request.HTTPBody;

    NSMutableString *head = [NSMutableString stringWithFormat:@"%@ %@ HTTP/1.1\r\n", method, path];
    [head appendFormat:@"Host: %@\r\n", url.host];

    NSDictionary *headers = request.allHTTPHeaderFields;
    BOOL hasUserAgent = NO;

    for (NSString *key in headers) {
        if ([[key lowercaseString] isEqualToString:@"host"]) continue;
        if ([[key lowercaseString] isEqualToString:@"user-agent"]) hasUserAgent = YES;
        [head appendFormat:@"%@: %@\r\n", key, headers[key]];
    }

    if (!hasUserAgent) [head appendString:@"User-Agent: okhttp/4.12.0\r\n"];

    // Сжатие не просим: распаковывать его пришлось бы самим, а картинки
    // и файлы и так лежат в сжатых форматах — толку ноль.
    [head appendString:@"Accept-Encoding: identity\r\n"];

    [head appendString:@"Connection: keep-alive\r\n"];

    if (body.length > 0) {
        [head appendFormat:@"Content-Length: %lu\r\n", (unsigned long)body.length];
    }
    [head appendString:@"\r\n"];

    NSData *headData = [head dataUsingEncoding:NSUTF8StringEncoding];
    if ([tls writeBytes:headData.bytes length:headData.length error:error] < 0) {
        [tls close];
        return nil;
    }
    if (body.length > 0 && [tls writeBytes:body.bytes length:body.length error:error] < 0) {
        [tls close];
        return nil;
    }

    // --- ответ ---

    NSMutableData *tail = [NSMutableData data];
    NSString *rawHead = MAXHttpReadHead(tls, tail, error);
    if (rawHead == nil) {
        [tls close];
        return nil;
    }

    NSArray *lines = [rawHead componentsSeparatedByString:@"\r\n"];
    if (lines.count == 0) {
        [tls close];
        if (error) *error = MAXHttpError(2, @"пустой ответ");
        return nil;
    }

    NSArray *statusParts = [lines[0] componentsSeparatedByString:@" "];
    if (statusParts.count < 2) {
        [tls close];
        if (error) *error = MAXHttpError(2, @"нечитаемая строка состояния");
        return nil;
    }

    NSInteger status = [statusParts[1] integerValue];

    NSMutableDictionary *responseHeaders = [NSMutableDictionary dictionary];
    for (NSUInteger i = 1; i < lines.count; i++) {
        NSString *line = lines[i];
        NSRange colon = [line rangeOfString:@":"];
        if (colon.location == NSNotFound) continue;

        NSString *name = [[line substringToIndex:colon.location] lowercaseString];
        NSString *value = [[line substringFromIndex:colon.location + 1]
                           stringByTrimmingCharactersInSet:
                           [NSCharacterSet whitespaceCharacterSet]];
        responseHeaders[name] = value;
    }

    // --- переадресация ---

    if ((status == 301 || status == 302 || status == 303 || status == 307 || status == 308)
        && responseHeaders[@"location"] != nil) {
        NSString *location = responseHeaders[@"location"];
        NSURL *next = [NSURL URLWithString:location relativeToURL:url];

        [tls close];

        if (next == nil) {
            if (error) *error = MAXHttpError(1, @"нечитаемый адрес переадресации");
            return nil;
        }

        NSMutableURLRequest *followed = [request mutableCopy];
        followed.URL = next;

        // 303 и 302 на практике означают «дальше GET», даже если пришли
        // в ответ на POST: так делают все браузеры, и серверы на это
        // рассчитывают.
        if (status == 303 || status == 302) {
            followed.HTTPMethod = @"GET";
            followed.HTTPBody = nil;
        }

        return [self attemptRequest:followed
                          redirects:redirects + 1
                           response:response
                             reused:NULL
                              error:error];
    }

    // --- тело ---

    NSData *data = nil;
    BOOL lengthKnown = YES;
    NSString *encoding = [responseHeaders[@"transfer-encoding"] lowercaseString];

    // Проверка на nil здесь обязательна, и это не перестраховка: сообщение
    // к nil возвращает нулевой NSRange, у которого location == 0, а ноль —
    // это не NSNotFound. Без явной проверки ответ без Transfer-Encoding
    // читался как «кусками», и первые же байты картинки принимались за длину
    // куска — отсюда и брались «нечитаемая длина куска» на каждой аватарке.
    if (encoding != nil && [encoding rangeOfString:@"chunked"].location != NSNotFound) {
        data = MAXHttpReadChunked(tls, tail, error);
    } else if (responseHeaders[@"content-length"] != nil) {
        data = MAXHttpReadFixed(tls, tail, (NSUInteger)[responseHeaders[@"content-length"]
                                                        longLongValue], error);
    } else {
        // Ни длины, ни кусков: конец тела виден только по закрытию
        // соединения, поэтому и оставить его себе нельзя.
        lengthKnown = NO;
        data = MAXHttpReadFixed(tls, tail, NSUIntegerMax, error);
    }

    if (data == nil) {
        [tls close];
        return nil;
    }

    // Соединение возвращается в пул, только если ответ дочитан ровно до конца
    // и сервер не попрощался. Иначе в трубе остался бы хвост, и следующий
    // запрос прочитал бы его вместо своих заголовков.
    // Та же ловушка с nil: без проверки заголовок, которого нет, читался бы
    // как «сервер закрывает», и в пул не возвращалось бы ни одно соединение.
    NSString *connectionHeader = [responseHeaders[@"connection"] lowercaseString];
    BOOL serverClosing = connectionHeader != nil
        && [connectionHeader rangeOfString:@"close"].location != NSNotFound;

    if (lengthKnown && !serverClosing) {
        MAXHttpReturnConnection(poolKey, tls);
    } else {
        [tls close];
    }

    if (response != NULL) {
        *response = [[NSHTTPURLResponse alloc] initWithURL:url
                                                statusCode:status
                                               HTTPVersion:@"HTTP/1.1"
                                              headerFields:responseHeaders];
    }

    return data;
}

+ (NSData *)sendSynchronousRequest:(NSURLRequest *)request
                          response:(NSHTTPURLResponse **)response
                             error:(NSError **)error {
    BOOL reused = NO;
    NSError *attemptError = nil;

    NSData *data = [self attemptRequest:request
                              redirects:0
                               response:response
                                 reused:&reused
                                  error:&attemptError];

    // Соединение из пула могло быть закрыто сервером, пока лежало без дела.
    // Узнаём мы об этом только на обрыве — тогда пробуем ещё раз, уже
    // с новым: для вызывающего это должно выглядеть как один запрос.
    if (data == nil && reused) {
        attemptError = nil;
        data = [self attemptRequest:request
                          redirects:0
                           response:response
                             reused:NULL
                              error:&attemptError];
    }

    if (data == nil && error != NULL) *error = attemptError;
    return data;
}

+ (NSData *)dataWithContentsOfURLString:(NSString *)urlString {
    NSURL *url = [NSURL URLWithString:urlString];
    if (url == nil) return nil;

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.timeoutInterval = MAXHttpTimeout;

    NSHTTPURLResponse *response = nil;
    NSError *error = nil;
    NSData *data = [self sendSynchronousRequest:request response:&response error:&error];

    if (error != nil) {
        NSLog(@"[Max/HTTP] %@ — %@", urlString, error.localizedDescription);
        return nil;
    }
    if (response != nil && (response.statusCode < 200 || response.statusCode >= 300)) {
        NSLog(@"[Max/HTTP] %@ — код %ld", urlString, (long)response.statusCode);
        return nil;
    }
    return data;
}

@end
