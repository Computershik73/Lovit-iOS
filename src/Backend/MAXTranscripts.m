//
//  MAXTranscripts.m
//

#import "MAXTranscripts.h"
#import "MAXApi.h"
#import "MAXOpcodes.h"
#import "MAXPacket.h"

NSString *const MAXTranscriptsDidChangeNotification = @"MAXTranscriptsDidChangeNotification";

/// Сколько раз переспросить и с какой передышкой, если сервер ответил
/// «ещё считаю». Пятнадцати секунд хватает на запись любой разумной длины;
/// дальше молчание значит, что не сложилось, и ждать без конца незачем.
static const NSUInteger MAXTranscriptTries = 5;
static const NSTimeInterval MAXTranscriptPause = 3.0;

@implementation MAXTranscript
@end

@implementation MAXTranscripts {
    NSMutableDictionary *_byMessageId;   // messageId -> MAXTranscript
    NSMutableDictionary *_triesLeft;     // messageId -> @(сколько попыток ещё)
}

+ (instancetype)shared {
    static MAXTranscripts *instance = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [[MAXTranscripts alloc] init]; });
    return instance;
}

- (id)init {
    self = [super init];
    if (self != nil) {
        _byMessageId = [NSMutableDictionary dictionary];
        _triesLeft = [NSMutableDictionary dictionary];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(handlePush:)
                                                     name:MAXApiDidReceivePushNotification
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)reset {
    [_byMessageId removeAllObjects];
    [_triesLeft removeAllObjects];
}

- (MAXTranscript *)transcriptForMessageId:(NSString *)messageId {
    if (messageId.length == 0) return nil;
    return _byMessageId[messageId];
}

#pragma mark - Нажатие на «Т»

- (void)toggleForMessageId:(NSString *)messageId
                    chatId:(long long)chatId
                   mediaId:(long long)mediaId {
    if (messageId.length == 0) return;

    MAXTranscript *known = _byMessageId[messageId];

    // Уже спрашивали: нажатие просто сворачивает и разворачивает. Заново
    // тревожить сервер незачем — кроме случая, когда в прошлый раз не вышло.
    if (known != nil && known.state != MAXTranscriptFailed) {
        known.shown = !known.shown;
        [self changed:messageId];
        return;
    }

    MAXTranscript *made = [[MAXTranscript alloc] init];
    made.state = MAXTranscriptWaiting;
    made.text = @"Расшифровываю…";
    made.shown = YES;
    _byMessageId[messageId] = made;
    _triesLeft[messageId] = @(MAXTranscriptTries);

    [self changed:messageId];
    [self askForMessageId:messageId chatId:chatId mediaId:mediaId];
}

/// Сам вопрос серверу. Ответ бывает трёх видов: готовый текст, «ещё считаю»
/// и отказ.
- (void)askForMessageId:(NSString *)messageId
                 chatId:(long long)chatId
                mediaId:(long long)mediaId {
    NSDictionary *payload = @{@"chatId": @(chatId),
                              @"messageId": @([messageId longLongValue]),
                              @"mediaId": @(mediaId)};

    __weak MAXTranscripts *weakSelf = self;
    [[MAXApi shared] sendRequestWithOpcode:MAXOpcodeAudioTranscription
                                   payload:payload
                                    silent:YES
                                completion:^(MAXPacket *packet, NSError *error) {
        MAXTranscripts *strongSelf = weakSelf;
        if (strongSelf == nil) return;

        if (error != nil) {
            [strongSelf failMessageId:messageId
                                 with:@"Не удалось расшифровать"];
            return;
        }

        NSDictionary *map = packet.payloadMap;
        NSInteger status = [map[@"transcriptionStatus"] integerValue];

        if (status == 1) {
            [strongSelf readyMessageId:messageId text:map[@"transcription"]];
            return;
        }

        if (status != 0) {
            [strongSelf failMessageId:messageId with:@"Не удалось расшифровать"];
            return;
        }

        // Ещё считает — переспросим попозже, если попытки не кончились.
        NSInteger left = [strongSelf->_triesLeft[messageId] integerValue] - 1;
        strongSelf->_triesLeft[messageId] = @(left);

        if (left <= 0) {
            [strongSelf failMessageId:messageId
                                 with:@"Расшифровка не готова — попробуйте позже"];
            return;
        }

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                     (int64_t)(MAXTranscriptPause * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            MAXTranscripts *again = weakSelf;
            if (again == nil) return;

            // За время передышки текст мог приехать сам — сервер присылает
            // его и без вопроса. Тогда переспрашивать нечего.
            MAXTranscript *now = again->_byMessageId[messageId];
            if (now == nil || now.state != MAXTranscriptWaiting) return;

            [again askForMessageId:messageId chatId:chatId mediaId:mediaId];
        });
    }];
}

#pragma mark - Ответ сервера сам по себе

/// Сервер присылает готовую расшифровку и без вопроса — когда досчитает.
/// Разбираем осторожно: поля здесь названы так же, как в ответе, но точного
/// вида этой посылки я не видел.
- (void)handlePush:(NSNotification *)note {
    MAXPacket *packet = note.userInfo[@"packet"];
    if (packet == nil || packet.opcode != MAXOpcodeTranscriptionResult) return;

    NSDictionary *map = packet.payloadMap;
    if (![map isKindOfClass:[NSDictionary class]]) return;

    id raw = map[@"messageId"];
    NSString *messageId = [raw isKindOfClass:[NSString class]]
        ? raw
        : ([raw respondsToSelector:@selector(stringValue)] ? [raw stringValue] : nil);
    if (messageId.length == 0) return;

    // Не про то сообщение, о котором спрашивали, — значит, и показывать
    // некому: расшифровку заводит только нажатие.
    if (_byMessageId[messageId] == nil) return;

    NSInteger status = map[@"transcriptionStatus"] != nil
        ? [map[@"transcriptionStatus"] integerValue]
        : 1;

    NSString *text = [map[@"transcription"] isKindOfClass:[NSString class]]
        ? map[@"transcription"]
        : nil;

    if (status == 1 || text.length > 0) {
        [self readyMessageId:messageId text:text];
        return;
    }
    if (status != 0) [self failMessageId:messageId with:@"Не удалось расшифровать"];
}

#pragma mark - Итоги

- (void)readyMessageId:(NSString *)messageId text:(id)raw {
    MAXTranscript *transcript = _byMessageId[messageId];
    if (transcript == nil) return;

    NSString *text = [raw isKindOfClass:[NSString class]] ? raw : nil;

    transcript.state = MAXTranscriptReady;
    transcript.text = text.length > 0 ? text : @"Речи не разобрать";
    [_triesLeft removeObjectForKey:messageId];

    NSLog(@"[Max/Расшифровка] %@: %lu знаков",
          messageId, (unsigned long)transcript.text.length);
    [self changed:messageId];
}

- (void)failMessageId:(NSString *)messageId with:(NSString *)reason {
    MAXTranscript *transcript = _byMessageId[messageId];
    if (transcript == nil) return;

    transcript.state = MAXTranscriptFailed;
    transcript.text = reason;
    [_triesLeft removeObjectForKey:messageId];

    NSLog(@"[Max/Расшифровка] %@: %@", messageId, reason);
    [self changed:messageId];
}

- (void)changed:(NSString *)messageId {
    [[NSNotificationCenter defaultCenter]
        postNotificationName:MAXTranscriptsDidChangeNotification
                      object:self
                    userInfo:@{@"messageId": messageId}];
}

@end
