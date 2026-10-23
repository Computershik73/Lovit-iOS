//
//  MAXApi.m
//

#import "MAXApi.h"
#import <UIKit/UIKit.h>
#import "MAXConnection.h"
#import "MAXPacketReceiver.h"
#import "MAXOpcodes.h"
#import "MAXServerConfig.h"
#import "MAXSettings.h"
#import "MAXDeviceIdentity.h"
#import "MAXSpoofingService.h"
#import <sys/utsname.h>

NSString *const MAXApiStateDidChangeNotification = @"MAXApiStateDidChangeNotification";
NSString *const MAXApiDidReceivePushNotification = @"MAXApiDidReceivePushNotification";
NSString *const MAXApiSessionExpiredNotification = @"MAXApiSessionExpiredNotification";
NSString *const MAXApiErrorNotification = @"MAXApiErrorNotification";
NSString *const MAXApiErrorDomain = @"ru.max.api";

/// Экран по умолчанию — как у Komet, когда подмена выключена.
static NSString *const MAXDefaultScreen = @"420dpi 420dpi 1080x2340";

/// Шаги многошагового входа. Отказ на них разбирают экраны входа, а не
/// общий разбор ответов: аккаунта на этом месте ещё нет.
static BOOL MAXIsAuthFlowOpcode(NSUInteger opcode) {
    return opcode == MAXOpcodeAuthRequest
        || opcode == MAXOpcodeAuth
        || opcode == MAXOpcodeAuthConfirm
        || opcode == MAXOpcodeAuthLoginCheckPassword;
}

/// Общий предел ожидания ответа. Дальше ждать бессмысленно: за экраном
/// стоит человек, и он уже решил, что приложение сломалось.
static const NSTimeInterval MAXLongestWait = 180.0;

@interface MAXPendingRequest : NSObject
@property (nonatomic, copy) MAXPacketCompletion completion;
@property (nonatomic, strong) NSTimer *timeoutTimer;
@property (nonatomic, assign) NSUInteger opcode;
@property (nonatomic, assign) BOOL silent;
/// Когда запрос ушёл и сколько байт было прочитано к этому мигу: по второму
/// числу видно, отвечает ли сервер вообще или просто отвечает долго.
@property (nonatomic, assign) NSTimeInterval startedAt;
@property (nonatomic, assign) unsigned long long seenBytes;
@end

@implementation MAXPendingRequest
@end

@interface MAXApi () <MAXConnectionDelegate>
@end

@implementation MAXApi {
    MAXConnection *_connection;
    MAXPacketReceiver *_receiver;
    NSMutableDictionary *_pending;      // @(seq) -> MAXPendingRequest
    NSUInteger _seq;
    MAXSessionState _state;
    NSTimer *_pingTimer;
    NSTimer *_reconnectTimer;
    NSTimer *_connectWatchdog;
    NSUInteger _connectGeneration;
    NSUInteger _session;
    NSUInteger _reconnectAttempts;
    BOOL _autoReconnect;
    BOOL _waking;
    long long _callsSeed;
    BOOL _hasCallsSeed;
    /// Сколько байт пришло из сокета за всё время сессии.
    unsigned long long _bytesRead;
}

+ (instancetype)shared {
    static MAXApi *instance = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        instance = [[MAXApi alloc] init];
    });
    return instance;
}

- (id)init {
    self = [super init];
    if (self) {
        _pending = [NSMutableDictionary dictionary];
        _receiver = [[MAXPacketReceiver alloc] init];
        _state = MAXSessionStateDisconnected;
        _seq = 0;
    }
    return self;
}

- (MAXSessionState)state { return _state; }
- (NSUInteger)session { return _session; }
- (long long)callsSeed { return _callsSeed; }
- (BOOL)hasCallsSeed { return _hasCallsSeed; }

#pragma mark - Подключение

- (void)connect {
    if (_state != MAXSessionStateDisconnected) return;

    _autoReconnect = YES;
    _connectGeneration++;
    [self setState:MAXSessionStateConnecting];
    [self armConnectWatchdog];

    [_receiver reset];
    _connection = [[MAXConnection alloc] init];
    _connection.delegate = self;
    [_connection connectToHost:[MAXServerConfig host]
                          port:[MAXServerConfig port]
                 allowInsecure:[MAXServerConfig insecureTlsAllowed]];
}

- (void)disconnect {
    _autoReconnect = NO;
    _connectGeneration++;
    [_reconnectTimer invalidate];
    _reconnectTimer = nil;
    [self cleanup];
    [self setState:MAXSessionStateDisconnected];
    [self failAllPendingWithMessage:@"Соединение разорвано"];
}

/// Приложение вернулось на экран.
///
/// Спящий телефон рвёт сокет молча — со стороны клиента соединение выглядит
/// живым, пока в него не напишут, — поэтому здесь либо сразу подключаемся,
/// либо проверяем живость пингом.
///
/// `_waking` — от повторного захода: пробуждение может прийти второй раз,
/// пока первое ещё не довело подключение до конца, и второму делать здесь
/// нечего. След в журнале нарочно подробный: до сих пор о пробуждении была
/// одна строка, и оборвись всё сразу после неё — по журналу не понять, на
/// каком шаге.
- (void)wakeUp {
    if (!_autoReconnect) return;
    if (_waking) return;
    _waking = YES;

    NSLog(@"[MAXApi] пробуждение: состояние %ld", (long)_state);

    switch (_state) {
        case MAXSessionStateDisconnected:
            _reconnectAttempts = 0;
            [_reconnectTimer invalidate];
            _reconnectTimer = nil;
            [self connect];
            NSLog(@"[MAXApi] пробуждение: соединялись заново, вышло %ld", (long)_state);
            break;
        case MAXSessionStateConnecting:
        case MAXSessionStateConnected:
            _reconnectAttempts = 0;
            break;
        case MAXSessionStateOnline:
            [self probeLiveness];
            break;
    }

    _waking = NO;
}

- (void)armConnectWatchdog {
    [_connectWatchdog invalidate];
    _connectWatchdog = [NSTimer scheduledTimerWithTimeInterval:75.0
                                                        target:self
                                                      selector:@selector(connectWatchdogFired)
                                                      userInfo:nil
                                                       repeats:NO];
}

- (void)connectWatchdogFired {
    _connectWatchdog = nil;
    if (_state == MAXSessionStateOnline || _state == MAXSessionStateDisconnected) return;
    NSLog(@"[MAXApi] watchdog: застряли в подключении, сброс");
    [self handleDisconnect];
}

- (void)cleanup {
    [_connectWatchdog invalidate];
    _connectWatchdog = nil;
    [_pingTimer invalidate];
    _pingTimer = nil;

    _connection.delegate = nil;
    [_connection disconnect];
    _connection = nil;
    [_receiver reset];
}

/// Обрыв не по своей воле: разбудить всех, кто ждал ответа, и вернуться в сеть.
///
/// Сюда попадают по нескольку раз подряд, и это не случайность. Ожидающего
/// его completion продолжает прямо здесь же, на этом самом месте: тот видит
/// пустой ответ, считает связь оборванной и зовёт нас снова — поверх
/// незаконченной уборки. Отсюда и двойной реконнект, и лишний счёт поколений.
///
/// Поэтому порядок такой: сперва состояние — по нему второй заход
/// разворачивается на первой же строке; потом транспорт; и только после
/// этого раздаются ответы, когда трогать больше нечего.
- (void)handleDisconnect {
    if (_state == MAXSessionStateDisconnected) return;

    _connectGeneration++;
    [self setState:MAXSessionStateDisconnected];
    [self cleanup];
    [self failAllPendingWithMessage:@"Соединение разорвано"];

    if (_autoReconnect) [self scheduleReconnect];
}

- (void)scheduleReconnect {
    NSUInteger shift = _reconnectAttempts < 3 ? _reconnectAttempts : 3;
    NSTimeInterval delay = (NSTimeInterval)(2 << shift);
    if (delay > 15.0) delay = 15.0;
    _reconnectAttempts++;

    [_reconnectTimer invalidate];
    _reconnectTimer = [NSTimer scheduledTimerWithTimeInterval:delay
                                                       target:self
                                                     selector:@selector(reconnectTimerFired)
                                                     userInfo:nil
                                                      repeats:NO];
}

- (void)reconnectTimerFired {
    _reconnectTimer = nil;
    [self connect];
}

- (void)setState:(MAXSessionState)state {
    if (_state == state) return;
    _state = state;

    // Через %s кириллица уходила в журнал кракозябрами: C-строка там
    // трактуется в системной кодировке, а не в UTF-8.
    NSArray *names = @[@"отключено", @"подключение", @"подключено", @"онлайн"];
    NSLog(@"[Max/Сессия] %@", names[state]);

    [[NSNotificationCenter defaultCenter] postNotificationName:MAXApiStateDidChangeNotification
                                                        object:self];
}

#pragma mark - Хэндшейк

/// Собирает поля устройства с наложенной подменой и отправляет SESSION_INIT.
- (void)sendHandshake {
    NSString *deviceType = @"ANDROID";
    NSString *osVersion = [self systemOsVersion];
    NSString *deviceName = [self hardwareModel];
    NSString *architecture = @"arm64-v8a";
    NSString *appVersion = MAXSpoofHardcodedAppVersion;
    long long buildNumber = MAXSpoofHardcodedBuildNumber;
    NSString *screen = MAXDefaultScreen;
    NSString *timezone = [[NSTimeZone systemTimeZone] name];
    // Оба поля русские, и это не забывчивость. Часть строк сервер отдаёт уже
    // переведёнными — названия системных папок, например, — и переводит он их
    // по языку устройства, а не по `locale`. Интерфейс порта на одном языке,
    // так что испанский телефон приносил в русское окно папку «Canales».
    // Профиль подмены оба поля при желании перекроет.
    NSString *locale = @"ru";
    NSString *deviceLocale = @"ru";
    NSString *deviceId = [MAXDeviceIdentity deviceId];
    NSString *pushDeviceType = @"GCM";
    NSString *instanceId = [MAXDeviceIdentity instanceId];
    long long clientSessionId = [MAXDeviceIdentity clientSessionId];

    NSDictionary *spoofed = [MAXSpoofingService spoofedSessionDataForScope:self.spoofScope];
    if (spoofed != nil) {
        NSString *value;

        value = spoofed[@"device_type"];
        // Пресеты IOS не меняют тип: клиент всегда представляется Android'ом.
        if (value.length > 0 && ![value isEqualToString:@"IOS"]) deviceType = value;

        value = spoofed[@"device_name"];
        if (value.length > 0) deviceName = value;

        value = spoofed[@"os_version"];
        if (value.length > 0) osVersion = value;

        value = spoofed[@"screen"];
        if (value.length > 0) screen = value;

        value = spoofed[@"timezone"];
        if (value.length > 0) timezone = value;

        value = spoofed[@"locale"];
        if (value.length > 0) {
            locale = value;
            deviceLocale = [[value componentsSeparatedByCharactersInSet:
                             [NSCharacterSet characterSetWithCharactersInString:@"-_"]]
                            objectAtIndex:0];
        }

        value = spoofed[@"device_locale"];
        if (value.length > 0) deviceLocale = value;

        value = spoofed[@"device_id"];
        if (value.length > 0) deviceId = value;

        value = spoofed[@"app_version"];
        if (value.length > 0) appVersion = value;

        value = spoofed[@"arch"];
        if (value.length > 0) architecture = value;

        NSNumber *build = spoofed[@"build_number"];
        if ([build isKindOfClass:[NSNumber class]] && [build longLongValue] != 0) {
            buildNumber = [build longLongValue];
        }

        value = spoofed[@"push_device_type"];
        if (value.length > 0) pushDeviceType = value;

        value = spoofed[@"instance_id"];
        if (value.length > 0) instanceId = value;

        NSNumber *session = spoofed[@"client_session_id"];
        if ([session isKindOfClass:[NSNumber class]] && [session longLongValue] != 0) {
            clientSessionId = [session longLongValue];
        }
    }

    _userAgent = @{
        @"deviceType": deviceType,
        @"appVersion": appVersion,
        @"osVersion": osVersion,
        @"timezone": timezone,
        @"screen": screen,
        @"pushDeviceType": pushDeviceType,
        @"arch": architecture,
        @"locale": locale,
        @"buildNumber": @(buildNumber),
        @"deviceName": deviceName,
        @"deviceLocale": deviceLocale
    };
    _deviceId = deviceId;

    NSDictionary *payload = @{
        @"mt_instanceid": instanceId,
        @"userAgent": _userAgent,
        @"clientSessionId": @(clientSessionId),
        @"deviceId": deviceId
    };

    NSUInteger generation = _connectGeneration;
    __weak MAXApi *weakSelf = self;
    [self sendRequestWithOpcode:MAXOpcodeSessionInit payload:payload completion:^(MAXPacket *packet, NSError *error) {
        MAXApi *strongSelf = weakSelf;
        if (strongSelf == nil || generation != strongSelf->_connectGeneration) return;

        if (error != nil || packet == nil) {
            NSLog(@"[MAXApi] хэндшейк не прошёл: %@", error.localizedDescription);
            [strongSelf handleDisconnect];
            return;
        }

        NSNumber *callsSeed = packet.payloadMap[@"callsSeed"];
        if ([callsSeed isKindOfClass:[NSNumber class]]) {
            strongSelf->_callsSeed = [callsSeed longLongValue];
            strongSelf->_hasCallsSeed = YES;
        }

        [strongSelf->_connectWatchdog invalidate];
        strongSelf->_connectWatchdog = nil;
        strongSelf->_reconnectAttempts = 0;
        strongSelf->_session++;
        [strongSelf setState:MAXSessionStateOnline];
        [strongSelf startPingTimer];

        if (strongSelf.reconnectHandler != nil) strongSelf.reconnectHandler();
    }];
}

- (NSString *)systemOsVersion {
    return [NSString stringWithFormat:@"iOS %@", [[UIDevice currentDevice] systemVersion]];
}

- (NSString *)hardwareModel {
    struct utsname info;
    uname(&info);
    return [NSString stringWithCString:info.machine encoding:NSUTF8StringEncoding];
}

- (NSString *)systemLanguageCode {
    NSString *identifier = [[NSLocale currentLocale] localeIdentifier];
    if (identifier.length >= 2) return [identifier substringToIndex:2];
    return @"ru";
}

#pragma mark - Пинг

- (void)startPingTimer {
    [_pingTimer invalidate];
    _pingTimer = [NSTimer scheduledTimerWithTimeInterval:[MAXServerConfig pingInterval]
                                                  target:self
                                                selector:@selector(pingTimerFired)
                                                userInfo:nil
                                                 repeats:YES];
}

- (void)pingTimerFired {
    if (_state != MAXSessionStateOnline) return;
    [self sendRequestWithOpcode:MAXOpcodePing
                        payload:@{@"interactive": @([MAXSettings interactive])}];
}

- (void)refreshPingInteractive {
    if (_state != MAXSessionStateOnline) return;
    [self sendRequestWithOpcode:MAXOpcodePing
                        payload:@{@"interactive": @([MAXSettings interactive])}];
}

/// Пробный пинг с коротким таймаутом: не ответил — принудительный реконнект.
- (void)probeLiveness {
    if (_state != MAXSessionStateOnline) return;
    NSUInteger generation = _connectGeneration;
    __weak MAXApi *weakSelf = self;
    [self sendRequestWithOpcode:MAXOpcodePing
                        payload:@{@"interactive": @([MAXSettings interactive])}
                         silent:YES
                     completion:^(MAXPacket *packet, NSError *error) {
        MAXApi *strongSelf = weakSelf;
        if (strongSelf == nil || error == nil) return;
        if (generation != strongSelf->_connectGeneration) return;
        if (strongSelf->_state != MAXSessionStateOnline) return;
        NSLog(@"[MAXApi] пробный пинг не прошёл — реконнект");
        [strongSelf handleDisconnect];
    }];
}

#pragma mark - Запросы

- (NSUInteger)nextSeq {
    _seq = (_seq + 1) % 65536;
    return _seq;
}

- (void)sendRequestWithOpcode:(NSUInteger)opcode payload:(NSDictionary *)payload {
    [self sendRequestWithOpcode:opcode payload:payload silent:YES completion:nil];
}

- (void)sendRequestWithOpcode:(NSUInteger)opcode
                      payload:(NSDictionary *)payload
                   completion:(MAXPacketCompletion)completion {
    [self sendRequestWithOpcode:opcode payload:payload silent:NO completion:completion];
}

- (void)sendRequestWithOpcode:(NSUInteger)opcode
                      payload:(NSDictionary *)payload
                       silent:(BOOL)silent
                   completion:(MAXPacketCompletion)completion {
    if (_connection == nil || !_connection.isConnected) {
        if (completion != nil) {
            completion(nil, [NSError errorWithDomain:MAXApiErrorDomain
                                                code:1
                                            userInfo:@{NSLocalizedDescriptionKey:
                                [NSString stringWithFormat:@"Нет соединения (%@)",
                                 MAXOpcodeName(opcode)]}]);
        }
        return;
    }

    NSUInteger seq = [self nextSeq];
    NSData *frame = [MAXPacket packOpcode:opcode payload:payload seq:seq];
    [_connection write:frame];

    NSLog(@"[Max/=>] %@ seq=%lu (%lu Б)",
          MAXOpcodeName(opcode), (unsigned long)seq, (unsigned long)frame.length);

    if (completion == nil) return;

    MAXPendingRequest *request = [[MAXPendingRequest alloc] init];
    request.completion = completion;
    request.opcode = opcode;
    request.silent = silent;
    request.startedAt = [NSDate timeIntervalSinceReferenceDate];
    request.seenBytes = _bytesRead;
    request.timeoutTimer = [NSTimer scheduledTimerWithTimeInterval:[MAXServerConfig requestTimeout]
                                                            target:self
                                                          selector:@selector(requestTimedOut:)
                                                          userInfo:@(seq)
                                                           repeats:NO];
    _pending[@(seq)] = request;
}

/// Ответа может не быть вовсе — сервер молчит, соединение висит. Тогда ждать
/// вечно нельзя: экран так и останется с крутилкой.
///
/// Но молчание и медленный ответ — разные вещи, и отличать их надо. Ответ на
/// вход у большого аккаунта идёт мегабайтами, и на неспешной сети он не
/// успевает за отведённые полминуты: клиент считал это тишиной и объявлял
/// «сервер не ответил», хотя данные всё это время шли.
///
/// Поэтому счётчик прочитанного сверяется с тем, каким он был: вырос —
/// значит сервер отвечает, просто ответ длинный, и ожидание продлевается.
/// Стоит на месте — значит тишина, и ждать больше нечего.
- (void)requestTimedOut:(NSTimer *)timer {
    NSNumber *seq = timer.userInfo;
    MAXPendingRequest *request = _pending[seq];
    if (request == nil) return;

    NSTimeInterval waited = [NSDate timeIntervalSinceReferenceDate] - request.startedAt;

    if (_bytesRead != request.seenBytes && waited < MAXLongestWait) {
        NSLog(@"[Max/Сессия] %@ ждёт дальше: пришло %llu Б, всего ждём %.0f с",
              MAXOpcodeName(request.opcode),
              _bytesRead - request.seenBytes, waited);

        request.seenBytes = _bytesRead;
        request.timeoutTimer =
            [NSTimer scheduledTimerWithTimeInterval:[MAXServerConfig requestTimeout]
                                             target:self
                                           selector:@selector(requestTimedOut:)
                                           userInfo:seq
                                            repeats:NO];
        return;
    }

    [_pending removeObjectForKey:seq];

    NSString *message = [NSString stringWithFormat:@"%@ таймаут", MAXOpcodeName(request.opcode)];
    request.completion(nil, [NSError errorWithDomain:MAXApiErrorDomain
                                                code:2
                                            userInfo:@{NSLocalizedDescriptionKey: message}]);
}

- (void)failAllPendingWithMessage:(NSString *)message {
    NSDictionary *snapshot = [_pending copy];
    [_pending removeAllObjects];

    for (MAXPendingRequest *request in snapshot.allValues) {
        [request.timeoutTimer invalidate];
        request.completion(nil, [NSError errorWithDomain:MAXApiErrorDomain
                                                    code:3
                                                userInfo:@{NSLocalizedDescriptionKey: message}]);
    }
}

- (void)deliverPacket:(MAXPacket *)packet {
    // Логируем всё входящее без разбора: пуш это или ответ, видно только
    // по cmd, и когда «ничего не приходит», важно отличить «пусто на проводе»
    // от «пришло, но не туда».
    NSLog(@"[Max/<=] %@ cmd=%lu seq=%lu",
          MAXOpcodeName(packet.opcode), (unsigned long)packet.cmd, (unsigned long)packet.seq);

    if (packet.isPush) {
        [[NSNotificationCenter defaultCenter] postNotificationName:MAXApiDidReceivePushNotification
                                                            object:self
                                                          userInfo:@{@"packet": packet}];
        return;
    }

    MAXPendingRequest *request = _pending[@(packet.seq)];
    if (request == nil) return;
    [_pending removeObjectForKey:@(packet.seq)];
    [request.timeoutTimer invalidate];

    if (packet.isError) {
        NSString *message = MAXMessageFromErrorPayload(packet.payload);

        // FAIL_WRONG_PASSWORD сервер шлёт и на отвергнутый токен LOGIN, и на
        // неверный пароль второго фактора. Второе — обычная опечатка, из-за
        // которой нельзя стирать аккаунт и выкидывать на экран телефона:
        // экран пароля покажет ошибку сам и даст ввести ещё раз.
        //
        // По той же причине молчим на всех шагах входа: там ещё нечему
        // истекать — аккаунта нет, — а протухший незаконченный вход экраны
        // разбирают сами и выводят из него кнопкой, вместо того чтобы
        // сбрасывать человека к номеру телефона окриком «Сессия истекла».
        BOOL sessionExpired = MAXIsSessionExpiredPayload(packet.payload) &&
                              !MAXIsAuthFlowOpcode(request.opcode);

        if (sessionExpired) {
            [[NSNotificationCenter defaultCenter]
             postNotificationName:MAXApiSessionExpiredNotification
                           object:self
                         userInfo:@{@"message": message}];
        } else if (!request.silent) {
            NSString *serverText = [self serverErrorTextFromPayload:packet.payload];
            if (serverText != nil) {
                [[NSNotificationCenter defaultCenter]
                 postNotificationName:MAXApiErrorNotification
                               object:self
                             userInfo:@{@"message": serverText}];
            }
        }

        request.completion(packet, [NSError errorWithDomain:MAXApiErrorDomain
                                                       code:4
                                                   userInfo:@{NSLocalizedDescriptionKey: message}]);
        return;
    }

    request.completion(packet, nil);
}

- (NSString *)serverErrorTextFromPayload:(id)payload {
    if (![payload isKindOfClass:[NSDictionary class]]) return nil;
    for (NSString *key in @[@"localizedMessage", @"title"]) {
        id value = ((NSDictionary *)payload)[key];
        if (![value isKindOfClass:[NSString class]]) continue;
        NSString *text = [value stringByTrimmingCharactersInSet:
                          [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (text.length > 0) return text;
    }
    return nil;
}

#pragma mark - MAXConnectionDelegate

- (void)connectionDidConnect:(MAXConnection *)connection {
    if (connection != _connection) return;
    [self setState:MAXSessionStateConnected];
    [self sendHandshake];
}

- (void)connection:(MAXConnection *)connection didReceiveData:(NSData *)data {
    if (connection != _connection) return;

    // Счётчик нужен не для статистики: по нему ожидание ответа отличает
    // молчание сервера от длинного ответа — см. requestTimedOut:.
    _bytesRead += data.length;

    NSArray *frames = [_receiver feed:data];
    if (frames == nil) {
        NSLog(@"[MAXApi] переполнение буфера приёма — реконнект");
        [self handleDisconnect];
        return;
    }

    for (NSData *frame in frames) {
        NSError *error = nil;
        MAXPacket *packet = [MAXPacket unpack:frame error:&error];
        if (packet == nil) {
            NSLog(@"[MAXApi] пакет не разобран: %@", error.localizedDescription);
            continue;
        }
        [self deliverPacket:packet];
    }
}

- (void)connection:(MAXConnection *)connection didFailWithError:(NSError *)error {
    if (connection != _connection) return;
    NSLog(@"[MAXApi] ошибка сокета: %@", error.localizedDescription);
    [self handleDisconnect];
}

- (void)connectionDidDisconnect:(MAXConnection *)connection {
    if (connection != _connection) return;
    [self handleDisconnect];
}

@end
