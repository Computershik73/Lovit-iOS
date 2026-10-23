//
//  MAXTls.h
//  Max — защищённое соединение поверх сокета, на своей криптографии.
//
//  Перенесено из «АльтерВито», где тот же слой решает ту же беду.
//
//  Зачем. Всё, что здесь есть, система умеет и сама — но по-своему в каждой
//  версии. От iOS 5 до нынешней в Secure Transport сменились и набор шифров,
//  и поддерживаемые версии протокола, и хранилище корней. Для MAX это
//  оказалось смертельно: сервер согласовывает TLS 1.3, а на TLS 1.2 из шифров
//  эпохи iOS 6 принимает ровно один — `ECDHE-RSA-AES128-SHA256`. Всё, что на
//  SHA-1, он отбрасывает, и рукопожатие на iOS 6 не состаивается вовсе.
//  Своя библиотека ведёт себя одинаково везде: разговор с сервером выглядит
//  так, как задали мы, а не так, как решил телефон 2011 года.
//
//  Работает синхронно и блокирующе, и это сделано нарочно. Асинхронность
//  здесь была бы третьей по счёту — у сокета своя, у OpenSSL своя,
//  у вызывающего своя, — а нужна ровно одна. Поэтому MAXConnection держит
//  свой поток ввода-вывода и зовёт нас оттуда, а MAXHttp — из фоновой очереди.
//

#import <Foundation/Foundation.h>

extern NSString *const MAXTlsErrorDomain;

typedef NS_ENUM(NSInteger, MAXTlsErrorCode) {
    MAXTlsErrorResolve = 1,      // имя не разрешилось
    MAXTlsErrorConnect,          // сокет не подключился
    MAXTlsErrorHandshake,        // рукопожатие не состоялось
    MAXTlsErrorCertificate,      // сертификат не принят
    MAXTlsErrorIO                // обрыв или тайм-аут при обмене
};

/// Возврат из чтения, когда данных пока нет, а соединение живо.
extern const NSInteger MAXTlsReadTimedOut;

@interface MAXTls : NSObject

/// Один раз за запуск: инициализация библиотеки и загрузка вшитых корней.
/// Звать можно сколько угодно, сработает первый раз.
+ (void)prepare;

- (id)initWithHost:(NSString *)host port:(uint16_t)port;

/// Отладочный режим «любой сертификат» из настроек сервера. Цепочка не
/// проверяется вовсе — соединение остаётся шифрованным, но беззащитным
/// к перехвату.
@property (nonatomic, assign) BOOL insecure;

/// Подключается и проводит рукопожатие. Тайм-аут общий на обе операции.
- (BOOL)connectWithTimeout:(NSTimeInterval)timeout error:(NSError **)error;

/// Тайм-аут ожидания данных при чтении. Ноль — ждать сколько придётся.
/// Ставится после подключения; цикл чтения выставляет доли секунды, чтобы
/// успевать между чтениями отправлять накопившееся.
- (void)setReadTimeout:(NSTimeInterval)timeout;

- (NSInteger)writeBytes:(const void *)bytes length:(NSUInteger)length error:(NSError **)error;

/// Больше нуля — прочитано; ноль — сервер закрыл соединение;
/// `MAXTlsReadTimedOut` — данных пока нет; минус один — ошибка.
- (NSInteger)readBytes:(void *)buffer maxLength:(NSUInteger)length error:(NSError **)error;

- (void)close;

/// Заполняются после успешного рукопожатия — по ним видно, о чём именно
/// договорились, и это первое, что нужно смотреть при разборе отказов.
@property (nonatomic, readonly) NSString *protocolName;   // TLSv1.3
@property (nonatomic, readonly) NSString *cipherName;     // TLS_AES_128_GCM_SHA256
@property (nonatomic, readonly) NSString *peerSubject;    // CN=*.oneme.ru
@property (nonatomic, readonly) NSString *peerIssuer;

@end
