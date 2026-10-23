//
//  MAXTls.m
//

#import "MAXTls.h"

#include <sys/socket.h>
#include <sys/time.h>
#include <netdb.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>

#include <openssl/ssl.h>
#include <openssl/err.h>
#include <openssl/x509v3.h>

NSString *const MAXTlsErrorDomain = @"ru.max.tls";
const NSInteger MAXTlsReadTimedOut = -2;

static SSL_CTX *gContext = NULL;

@implementation MAXTls {
    NSString *_host;
    uint16_t  _port;
    int       _socket;
    SSL      *_ssl;
}

@synthesize protocolName = _protocolName;
@synthesize cipherName = _cipherName;
@synthesize peerSubject = _peerSubject;
@synthesize peerIssuer = _peerIssuer;

#pragma mark - Подготовка библиотеки

/**
 * Корни доверия — свои, из связки.
 *
 * MAX удостоверяется двумя разными центрами, и ни одного из них нет
 * в хранилище старых iOS:
 *
 *   api2.oneme.ru  ← Russian Trusted Sub CA ← Russian Trusted Root CA
 *   i.oneme.ru     ← Let's Encrypt YR2      ← ISRG Root YR (выпущен в 2026)
 *
 * Системное хранилище остаётся в стороне намеренно. На iOS 6 оно застыло
 * в 2012 году: часть корней оттуда отозвана, часть протухла по сроку,
 * а новых там не появится никогда.
 *
 * Обратная сторона: когда MAX сменит удостоверяющий центр, приложение
 * перестанет ходить в сеть, пока не обновят связку. Это видно сразу и
 * написано в журнале открытым текстом — в отличие от «доверяем всему, что
 * скажет система», где однажды отваливается половина запросов и непонятно,
 * почему.
 */
static int MAXTlsLoadRoots(SSL_CTX *ctx) {
    X509_STORE *store = SSL_CTX_get_cert_store(ctx);
    if (store == NULL) return 0;

    NSArray *files = [[NSBundle mainBundle] pathsForResourcesOfType:@"der"
                                                        inDirectory:@"certs"];
    int loaded = 0;

    for (NSString *path in files) {
        NSData *data = [NSData dataWithContentsOfFile:path];
        if (data.length == 0) continue;

        const unsigned char *bytes = (const unsigned char *)data.bytes;
        X509 *cert = d2i_X509(NULL, &bytes, (long)data.length);
        if (cert == NULL) {
            NSLog(@"[Max/TLS] не разобрался корень %@", path.lastPathComponent);
            continue;
        }

        if (X509_STORE_add_cert(store, cert)) loaded++;
        X509_free(cert);
    }

    return loaded;
}

+ (void)prepare {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        SSL_library_init();
        SSL_load_error_strings();

        // TLS_client_method — «любая версия, договоримся по ходу».
        // Нижняя граница задаётся отдельно: TLS 1.2. Ниже сервер MAX
        // и сам не пойдёт, а клиент, предлагающий 2026 году протокол
        // из девяностых, сам себя объявляет подозрительным.
        gContext = SSL_CTX_new(TLS_client_method());
        if (gContext == NULL) {
            NSLog(@"[Max/TLS] не создался контекст");
            return;
        }

        SSL_CTX_set_min_proto_version(gContext, TLS1_2_VERSION);

        SSL_CTX_set_verify(gContext, SSL_VERIFY_PEER, NULL);
        SSL_CTX_set_verify_depth(gContext, 6);

        // Сжатие TLS выключено: оно давно признано опасным (CRIME),
        // и современные клиенты его не предлагают — а мы хотим выглядеть
        // современным клиентом.
        SSL_CTX_set_options(gContext, SSL_OP_NO_COMPRESSION);

        // Набор шифров — как у нынешних мобильных приложений. Порядок здесь
        // такая же примета клиента, как и User-Agent.
        //
        // `ECDHE-RSA-AES128-SHA256` в конце списка не для красоты: это
        // единственный шифр эпохи iOS 6, который сервер MAX принимает
        // на TLS 1.2. Обычно до него не доходит — договариваемся по 1.3, —
        // но если сервер однажды снимет поддержку новых версий, соединение
        // не пропадёт.
        SSL_CTX_set_cipher_list(gContext,
            "ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:"
            "ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:"
            "ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:"
            "ECDHE-RSA-AES128-SHA256:ECDHE-RSA-AES128-SHA:AES128-GCM-SHA256");

        SSL_CTX_set_ciphersuites(gContext,
            "TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256");

        int roots = MAXTlsLoadRoots(gContext);
        NSLog(@"[Max/TLS] OpenSSL %s, корней загружено: %d",
              OpenSSL_version(OPENSSL_VERSION), roots);

        if (roots == 0) {
            NSLog(@"[Max/TLS] ВНИМАНИЕ: ни одного корня — проверки сертификатов провалятся");
        }
    });
}

#pragma mark - Жизненный цикл

- (id)initWithHost:(NSString *)host port:(uint16_t)port {
    self = [super init];
    if (self) {
        _host = [host copy];
        _port = port;
        _socket = -1;
    }
    return self;
}

- (void)dealloc {
    [self close];
}

- (void)close {
    if (_ssl != NULL) {
        // Одного вызова достаточно: дожидаться ответного «до свидания»
        // незачем — соединение мы и так закрываем.
        SSL_shutdown(_ssl);
        SSL_free(_ssl);
        _ssl = NULL;
    }
    if (_socket >= 0) {
        close(_socket);
        _socket = -1;
    }
}

#pragma mark - Ошибки

static NSError *MAXTlsMakeError(MAXTlsErrorCode code, NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *text = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    return [NSError errorWithDomain:MAXTlsErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: text}];
}

/// Последняя ошибка OpenSSL человеческими словами. Очередь надо разгребать
/// до конца: иначе следующая операция увидит чужую запись и объяснит
/// происходящее совершенно неверно.
static NSString *MAXTlsOpenSSLError(void) {
    NSMutableArray *lines = [NSMutableArray array];
    unsigned long code;

    while ((code = ERR_get_error()) != 0) {
        char buffer[256];
        ERR_error_string_n(code, buffer, sizeof(buffer));
        [lines addObject:[NSString stringWithUTF8String:buffer]];
    }

    return lines.count > 0 ? [lines componentsJoinedByString:@"; "] : @"нет подробностей";
}

#pragma mark - Соединение

/**
 * Подключение с тайм-аутом: сокет переводится в неблокирующий режим,
 * connect возвращает управление сразу, а ждём мы на select.
 *
 * Без этого приложение на плохой связи замирает до системного тайм-аута,
 * а он на iOS около минуты с четвертью — за это время человек успевает
 * решить, что всё сломалось.
 */
static int MAXTlsConnectWithTimeout(struct addrinfo *address, NSTimeInterval timeout) {
    int fd = socket(address->ai_family, address->ai_socktype, address->ai_protocol);
    if (fd < 0) return -1;

    int flags = fcntl(fd, F_GETFL, 0);
    fcntl(fd, F_SETFL, flags | O_NONBLOCK);

    // Мелкие пакеты отправляем сразу, не дожидаясь попутчиков: у протокола
    // MAX они короткие, и задержка Нейгла добавила бы к каждому до двухсот
    // миллисекунд на ровном месте.
    int one = 1;
    setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof(one));

    // Обрыв соединения не должен убивать процесс сигналом.
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof(one));

    if (connect(fd, address->ai_addr, address->ai_addrlen) == 0) {
        fcntl(fd, F_SETFL, flags);
        return fd;
    }

    if (errno != EINPROGRESS) {
        close(fd);
        return -1;
    }

    fd_set writable;
    FD_ZERO(&writable);
    FD_SET(fd, &writable);

    struct timeval tv;
    tv.tv_sec = (time_t)timeout;
    tv.tv_usec = (suseconds_t)((timeout - (NSTimeInterval)tv.tv_sec) * 1000000);

    if (select(fd + 1, NULL, &writable, NULL, &tv) <= 0) {
        close(fd);
        return -1;
    }

    // select сказал «можно писать», но это ещё не значит «подключено»:
    // так же он ведёт себя и при отказе. Настоящий ответ лежит в SO_ERROR.
    int soError = 0;
    socklen_t length = sizeof(soError);
    if (getsockopt(fd, SOL_SOCKET, SO_ERROR, &soError, &length) < 0 || soError != 0) {
        close(fd);
        return -1;
    }

    fcntl(fd, F_SETFL, flags);
    return fd;
}

- (BOOL)connectWithTimeout:(NSTimeInterval)timeout error:(NSError **)error {
    [MAXTls prepare];

    if (gContext == NULL) {
        if (error) *error = MAXTlsMakeError(MAXTlsErrorHandshake, @"криптография не поднялась");
        return NO;
    }

    // --- разрешение имени ---

    // Каждая стадия отмечается в журнале со временем. Без этого отказ
    // выглядит как пауза в двадцать секунд и одна строка «не подключился»,
    // по которой не отличить медленный DNS от молчащего сервера.
    NSDate *started = [NSDate date];

    struct addrinfo hints;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_UNSPEC;          // и IPv4, и IPv6
    hints.ai_socktype = SOCK_STREAM;

    // AI_ADDRCONFIG — не спрашивать адреса того семейства, которого на
    // устройстве нет. Без него резолвер в сети без IPv6 всё равно ходит
    // за AAAA и ждёт своего тайм-аута: на старых iOS это лишние секунды
    // молчания перед каждым подключением.
    hints.ai_flags = AI_ADDRCONFIG;

    struct addrinfo *list = NULL;
    NSString *portText = [NSString stringWithFormat:@"%u", (unsigned)_port];

    int rc = getaddrinfo(_host.UTF8String, portText.UTF8String, &hints, &list);
    if (rc != 0 || list == NULL) {
        NSLog(@"[Max/TLS] %@: имя не разрешилось за %.1f с — %s",
              _host, -[started timeIntervalSinceNow], gai_strerror(rc));
        if (error) *error = MAXTlsMakeError(MAXTlsErrorResolve, @"не разрешилось имя %@: %s",
                                            _host, gai_strerror(rc));
        return NO;
    }

    NSLog(@"[Max/TLS] %@: имя разрешилось за %.1f с", _host, -[started timeIntervalSinceNow]);

    // --- сокет ---

    NSDate *connecting = [NSDate date];

    for (struct addrinfo *a = list; a != NULL; a = a->ai_next) {
        _socket = MAXTlsConnectWithTimeout(a, timeout);
        if (_socket >= 0) break;
        NSLog(@"[Max/TLS] %@: адрес не подошёл (errno %d)", _host, errno);
    }
    freeaddrinfo(list);

    if (_socket < 0) {
        NSLog(@"[Max/TLS] %@:%u: сокет не открылся за %.1f с",
              _host, (unsigned)_port, -[connecting timeIntervalSinceNow]);
        if (error) *error = MAXTlsMakeError(MAXTlsErrorConnect, @"не подключился к %@:%u",
                                            _host, (unsigned)_port);
        return NO;
    }

    NSLog(@"[Max/TLS] %@:%u: сокет открыт за %.1f с, рукопожатие…",
          _host, (unsigned)_port, -[connecting timeIntervalSinceNow]);

    // Дальше работаем блокирующе, но с тайм-аутом на каждой операции —
    // иначе молчащий сервер держал бы поток вечно.
    [self setReadTimeout:timeout];

    struct timeval tv;
    tv.tv_sec = (time_t)timeout;
    tv.tv_usec = 0;
    setsockopt(_socket, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));

    // --- рукопожатие ---

    _ssl = SSL_new(gContext);
    if (_ssl == NULL) {
        if (error) *error = MAXTlsMakeError(MAXTlsErrorHandshake, @"SSL_new: %@",
                                            MAXTlsOpenSSLError());
        return NO;
    }

    SSL_set_fd(_ssl, _socket);

    // Имя узла в расширении SNI. Без него сервер, держащий на одном адресе
    // сотни имён, не поймёт, чей сертификат показывать, и покажет чужой —
    // а мы его не примем.
    SSL_set_tlsext_host_name(_ssl, _host.UTF8String);

    if (_insecure) {
        // Отладочный тумблер из настроек: шифруем, но не удостоверяем.
        SSL_set_verify(_ssl, SSL_VERIFY_NONE, NULL);
    } else {
        // Имя узла для проверки сертификата — это отдельная работа: цепочка
        // может быть безупречной, но выписанной на другой домен.
        X509_VERIFY_PARAM *param = SSL_get0_param(_ssl);
        X509_VERIFY_PARAM_set_hostflags(param, X509_CHECK_FLAG_NO_PARTIAL_WILDCARDS);
        if (!X509_VERIFY_PARAM_set1_host(param, _host.UTF8String, 0)) {
            if (error) *error = MAXTlsMakeError(MAXTlsErrorHandshake,
                                                @"не задалось имя для проверки");
            return NO;
        }
    }

    // ALPN: говорим, что умеем HTTP/1.1. Современные клиенты это расширение
    // шлют всегда, и его отсутствие — заметная примета. Просить h2 не станем:
    // своей реализации HTTP/2 у нас нет, а протокол MAX поверх ALPN
    // не согласовывается вовсе.
    static const unsigned char alpn[] = { 8, 'h','t','t','p','/','1','.','1' };
    SSL_set_alpn_protos(_ssl, alpn, sizeof(alpn));

    NSDate *shaking = [NSDate date];

    if (SSL_connect(_ssl) != 1) {
        long verify = SSL_get_verify_result(_ssl);
        NSString *details = MAXTlsOpenSSLError();

        NSLog(@"[Max/TLS] %@: рукопожатие не вышло за %.1f с (errno %d, проверка %ld)",
              _host, -[shaking timeIntervalSinceNow], errno, verify);

        if (verify != X509_V_OK) {
            if (error) *error = MAXTlsMakeError(MAXTlsErrorCertificate,
                                                @"сертификат не принят: %s (%ld)",
                                                X509_verify_cert_error_string(verify), verify);
        } else {
            if (error) *error = MAXTlsMakeError(MAXTlsErrorHandshake,
                                                @"рукопожатие не состоялось: %@", details);
        }
        return NO;
    }

    _protocolName = [NSString stringWithUTF8String:SSL_get_version(_ssl)];
    _cipherName = [NSString stringWithUTF8String:SSL_CIPHER_get_name(SSL_get_current_cipher(_ssl))];

    NSLog(@"[Max/TLS] %@:%u — %@, %@ (всего %.1f с)", _host, (unsigned)_port,
          _protocolName, _cipherName, -[started timeIntervalSinceNow]);

    X509 *peer = SSL_get_peer_certificate(_ssl);
    if (peer != NULL) {
        char line[512];

        X509_NAME_oneline(X509_get_subject_name(peer), line, sizeof(line));
        _peerSubject = [NSString stringWithUTF8String:line];

        X509_NAME_oneline(X509_get_issuer_name(peer), line, sizeof(line));
        _peerIssuer = [NSString stringWithUTF8String:line];

        X509_free(peer);
    }

    return YES;
}

- (void)setReadTimeout:(NSTimeInterval)timeout {
    if (_socket < 0) return;

    struct timeval tv;
    tv.tv_sec = (time_t)timeout;
    tv.tv_usec = (suseconds_t)((timeout - (NSTimeInterval)tv.tv_sec) * 1000000);
    setsockopt(_socket, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
}

#pragma mark - Обмен

- (NSInteger)writeBytes:(const void *)bytes length:(NSUInteger)length error:(NSError **)error {
    if (_ssl == NULL) {
        if (error) *error = MAXTlsMakeError(MAXTlsErrorIO, @"соединение закрыто");
        return -1;
    }

    NSUInteger sent = 0;

    while (sent < length) {
        int written = SSL_write(_ssl, (const char *)bytes + sent, (int)(length - sent));
        if (written <= 0) {
            int reason = SSL_get_error(_ssl, written);

            // WANT_READ при записи — не ошибка, а пересогласование ключей:
            // библиотеке нужно прочитать ответ сервера, прежде чем
            // продолжить. Сокет блокирующий, так что просто пробуем снова.
            if (reason == SSL_ERROR_WANT_READ || reason == SSL_ERROR_WANT_WRITE) continue;

            if (error) *error = MAXTlsMakeError(MAXTlsErrorIO, @"обрыв при отправке: %@",
                                                MAXTlsOpenSSLError());
            return -1;
        }
        sent += (NSUInteger)written;
    }

    return (NSInteger)sent;
}

- (NSInteger)readBytes:(void *)buffer maxLength:(NSUInteger)length error:(NSError **)error {
    if (_ssl == NULL) {
        if (error) *error = MAXTlsMakeError(MAXTlsErrorIO, @"соединение закрыто");
        return -1;
    }

    while (1) {
        errno = 0;
        int got = SSL_read(_ssl, buffer, (int)length);
        if (got > 0) return got;

        int reason = SSL_get_error(_ssl, got);

        // Тайм-аут на сокете: данных пока нет, но соединение живо. Цикл
        // чтения на этом месте отправляет накопившееся и приходит снова.
        if ((reason == SSL_ERROR_SYSCALL || reason == SSL_ERROR_WANT_READ)
            && (errno == EAGAIN || errno == EWOULDBLOCK)) {
            return MAXTlsReadTimedOut;
        }

        // Ноль означает конец: либо сервер попрощался по правилам
        // (ZERO_RETURN), либо просто закрыл соединение (SYSCALL без ошибки).
        if (reason == SSL_ERROR_ZERO_RETURN) return 0;
        if (reason == SSL_ERROR_SYSCALL && errno == 0) return 0;

        if (reason == SSL_ERROR_WANT_READ || reason == SSL_ERROR_WANT_WRITE) continue;

        if (error) *error = MAXTlsMakeError(MAXTlsErrorIO, @"обрыв при чтении: %@",
                                            MAXTlsOpenSSLError());
        return -1;
    }
}

@end
