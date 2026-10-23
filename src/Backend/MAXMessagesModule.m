//
//  MAXMessagesModule.m
//

#import "MAXMessagesModule.h"
#import "MAXApi.h"
#import "MAXOpcodes.h"
#import "MAXPacket.h"
#import "MAXSettings.h"
#import "MAXMessage.h"
#import "MAXRichText.h"

static long long MAXNowMilliseconds(void) {
    return (long long)([[NSDate date] timeIntervalSince1970] * 1000.0);
}

/// Сколько раз повторять отправку, пока вложение «не готово», и сколько
/// ждать между попытками. Числа из Komet и клиента под Windows Phone.
static const NSUInteger MAXSendAttempts = 30;
static const NSTimeInterval MAXSendPause = 1.0;

@implementation MAXMessagesModule {
    NSMutableDictionary *_lastTypingByChat;
}

- (id)init {
    self = [super init];
    if (self) _lastTypingByChat = [NSMutableDictionary dictionary];
    return self;
}

+ (instancetype)shared {
    static MAXMessagesModule *instance = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        instance = [[MAXMessagesModule alloc] init];
    });
    return instance;
}

- (void)fetchHistoryForChat:(long long)chatId
                   fromTime:(long long)fromTime
                      count:(NSInteger)count
                 completion:(MAXHistoryCompletion)completion {
    [self fetchHistoryForChat:chatId
                     fromTime:fromTime
                      forward:0
                     backward:count
                   completion:completion];
}

- (void)fetchHistoryForChat:(long long)chatId
                   fromTime:(long long)fromTime
                    forward:(NSInteger)forward
                   backward:(NSInteger)backward
                 completion:(MAXHistoryCompletion)completion {
    long long from = fromTime > 0 ? fromTime : (MAXNowMilliseconds() + 86400000);

    NSDictionary *payload = @{
        @"chatId": @(chatId),
        @"from": @(from),
        @"forward": @(forward),
        @"backward": @(backward),
        @"getMessages": @(YES)
    };

    [[MAXApi shared] sendRequestWithOpcode:MAXOpcodeChatHistory
                                   payload:payload
                                completion:^(MAXPacket *packet, NSError *error) {
        if (error != nil) {
            completion(nil, error);
            return;
        }

        id rawMessages = packet.payloadMap[@"messages"];
        if (![rawMessages isKindOfClass:[NSArray class]]) {
            completion(@[], nil);
            return;
        }

        NSMutableArray *messages = [NSMutableArray arrayWithCapacity:[rawMessages count]];
        for (id raw in rawMessages) {
            MAXMessage *message = [MAXMessage messageFromServerMap:raw chatId:chatId];
            if (message != nil) [messages addObject:message];
        }

        [messages sortUsingComparator:^NSComparisonResult(MAXMessage *a, MAXMessage *b) {
            if (a.time == b.time) return NSOrderedSame;
            return a.time < b.time ? NSOrderedAscending : NSOrderedDescending;
        }];

        completion(messages, nil);
    }];
}

- (void)sendText:(NSString *)text
          toChat:(long long)chatId
 replyToMessageId:(long long)replyToMessageId
      completion:(MAXSendCompletion)completion {
    [self sendText:text
            toChat:chatId
  replyToMessageId:replyToMessageId
            markup:nil
        completion:completion];
}

- (void)sendText:(NSString *)text
          toChat:(long long)chatId
 replyToMessageId:(long long)replyToMessageId
          markup:(NSArray *)markup
      completion:(MAXSendCompletion)completion {
    NSMutableDictionary *message = [NSMutableDictionary dictionary];
    message[@"text"] = text ?: @"";
    message[@"cid"] = @(-MAXNowMilliseconds());
    // Наложенное руками и ссылки, найденные сами. Komet ссылок не ищет — там
    // размечают только руками, — но без этого набранная ссылка уходит простым
    // текстом и у собеседника ссылкой не становится.
    message[@"elements"] = [MAXRichText elementsForText:text applied:markup] ?: @[];
    message[@"attaches"] = @[];

    if (replyToMessageId != 0) {
        message[@"link"] = @{@"type": @"REPLY",
                             @"chatId": @(chatId),
                             @"messageId": @(replyToMessageId)};
    }

    NSDictionary *payload = @{@"chatId": @(chatId),
                              @"message": message,
                              @"notify": @(YES)};

    [[MAXApi shared] sendRequestWithOpcode:MAXOpcodeMsgSend
                                   payload:payload
                                completion:^(MAXPacket *packet, NSError *error) {
        if (error != nil) {
            completion(nil, error);
            return;
        }

        id sent = packet.payloadMap[@"message"];
        id messageId = [sent isKindOfClass:[NSDictionary class]] ? ((NSDictionary *)sent)[@"id"] : nil;
        completion(messageId != nil ? [messageId description] : @"", nil);
    }];
}

- (void)sendVoiceToken:(NSString *)token
                toChat:(long long)chatId
            durationMs:(NSInteger)durationMs
                  wave:(NSData *)wave
      replyToMessageId:(long long)replyToMessageId
            completion:(MAXSendCompletion)completion {
    NSMutableDictionary *attach = [NSMutableDictionary dictionary];
    attach[@"_type"] = @"AUDIO";
    attach[@"token"] = token ?: @"";
    attach[@"duration"] = @(durationMs);
    // Пустой график тоже посылается: без поля собеседник рисует пустоту, а
    // с нулями — ровную полоску, что честнее.
    attach[@"wave"] = wave ?: [NSMutableData dataWithLength:80];

    NSMutableDictionary *message = [NSMutableDictionary dictionary];
    message[@"cid"] = @(-MAXNowMilliseconds());
    message[@"text"] = @"";
    message[@"elements"] = @[];
    message[@"attaches"] = @[attach];

    if (replyToMessageId != 0) {
        message[@"link"] = @{@"type": @"REPLY",
                             @"chatId": @(chatId),
                             @"messageId": @(replyToMessageId)};
    }

    NSDictionary *payload = @{@"chatId": @(chatId),
                              @"message": message,
                              @"notify": @(YES)};

    // Через общий путь: у записи, как и у файла, есть вложение, а значит и
    // окно, в котором сервер отвечает «ещё не готово».
    [self sendMessagePayload:payload completion:completion];
}

- (void)sendVideoNoteToken:(NSString *)token
                    toChat:(long long)chatId
                durationMs:(NSInteger)durationMs
          replyToMessageId:(long long)replyToMessageId
                completion:(MAXSendCompletion)completion {
    NSMutableDictionary *attach = [NSMutableDictionary dictionary];
    attach[@"_type"] = @"VIDEO";
    attach[@"token"] = token ?: @"";
    attach[@"duration"] = @(durationMs);
    attach[@"videoType"] = @(1);
    // График громкости кружку не нужен, но поле сервер ждёт у обоих видов
    // записи — шлём пустое, как это делает настоящий клиент.
    attach[@"wave"] = [NSMutableData dataWithLength:80];

    NSMutableDictionary *message = [NSMutableDictionary dictionary];
    message[@"cid"] = @(-MAXNowMilliseconds());
    message[@"text"] = @"";
    message[@"elements"] = @[];
    message[@"attaches"] = @[attach];

    if (replyToMessageId != 0) {
        message[@"link"] = @{@"type": @"REPLY",
                             @"chatId": @(chatId),
                             @"messageId": @(replyToMessageId)};
    }

    NSDictionary *payload = @{@"chatId": @(chatId),
                              @"message": message,
                              @"notify": @(YES)};

    // Через общий путь: у записи, как и у файла, есть вложение, а значит и
    // окно, в котором сервер отвечает «ещё не готово».
    [self sendMessagePayload:payload completion:completion];
}

- (void)sendSticker:(long long)stickerId
             toChat:(long long)chatId
   replyToMessageId:(long long)replyToMessageId
         completion:(MAXSendCompletion)completion {
    NSMutableDictionary *message = [NSMutableDictionary dictionary];
    message[@"cid"] = @(-MAXNowMilliseconds());
    message[@"text"] = @"";
    message[@"elements"] = @[];
    message[@"attaches"] = @[@{@"_type": @"STICKER", @"stickerId": @(stickerId)}];

    if (replyToMessageId != 0) {
        message[@"link"] = @{@"type": @"REPLY",
                             @"chatId": @(chatId),
                             @"messageId": @(replyToMessageId)};
    }

    NSDictionary *payload = @{@"chatId": @(chatId),
                              @"message": message,
                              @"notify": @(YES)};

    // Через общий путь: у записи, как и у файла, есть вложение, а значит и
    // окно, в котором сервер отвечает «ещё не готово».
    [self sendMessagePayload:payload completion:completion];
}

- (void)sendPhotoToken:(NSString *)photoToken
                toChat:(long long)chatId
               caption:(NSString *)caption
            completion:(MAXSendCompletion)completion {
    NSMutableDictionary *message = [NSMutableDictionary dictionary];
    message[@"cid"] = @(-MAXNowMilliseconds());
    message[@"attaches"] = @[@{@"_type": @"PHOTO", @"photoToken": photoToken ?: @""}];
    if (caption.length > 0) message[@"text"] = caption;

    [self sendMessagePayload:@{@"chatId": @(chatId),
                               @"message": message,
                               @"notify": @(YES)}
                  completion:completion];
}

- (void)sendFileToken:(NSString *)token
               fileId:(long long)fileId
                 name:(NSString *)name
               toChat:(long long)chatId
           completion:(MAXSendCompletion)completion {
    // Сервер принимает либо token, либо fileId — шлём то, что дал FILE_UPLOAD.
    NSDictionary *attach = token.length > 0
        ? @{@"_type": @"FILE", @"token": token, @"name": (name ?: @"")}
        : @{@"_type": @"FILE", @"fileId": @(fileId), @"name": (name ?: @"")};

    NSDictionary *message = @{@"cid": @(MAXNowMilliseconds()),
                              @"elements": @[],
                              @"attaches": @[attach]};

    [self sendMessagePayload:@{@"chatId": @(chatId),
                               @"message": message,
                               @"notify": @(YES)}
                  completion:completion];
}

- (void)sendMessagePayload:(NSDictionary *)payload completion:(MAXSendCompletion)completion {
    [self sendMessagePayload:payload attempt:0 completion:completion];
}

/// Отправка сообщения — с повтором, пока вложение не готово.
///
/// Залитое становится пригодным не сразу: CDN его ещё обрабатывает, и до
/// этого сервер отвечает отказом с `not.ready`. Между концом заливки и
/// отправкой проходят миллисекунды, так что попасть в это окно — обычное
/// дело, а не редкость: в журнале видно, что файл дошёл до CDN целиком
/// («0-241442/241443»), и тут же получен отказ.
///
/// Ждём секунду и шлём заново, до тридцати раз, — ровно как Komet
/// (`_sendWithNotReadyRetry`) и клиент под Windows Phone. Остальные отказы
/// повторять незачем: они не про время.
- (void)sendMessagePayload:(NSDictionary *)payload
                   attempt:(NSUInteger)attempt
                completion:(MAXSendCompletion)completion {
    __weak MAXMessagesModule *weakSelf = self;

    // silent: отказ показываем сами, и только окончательный. Иначе каждая
    // попытка всплывала бы окошком поверх переписки.
    [[MAXApi shared] sendRequestWithOpcode:MAXOpcodeMsgSend
                                   payload:payload
                                    silent:YES
                                completion:^(MAXPacket *packet, NSError *error) {
        if (error != nil) {
            NSString *reason = [packet.payloadMap[@"error"] description] ?: @"";
            BOOL notReady = ([reason rangeOfString:@"not.ready"].location != NSNotFound);

            if (notReady && attempt + 1 < MAXSendAttempts) {
                NSLog(@"[Max/Чат] вложение ещё не готово, попытка %lu",
                      (unsigned long)(attempt + 1));

                dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                             (int64_t)(MAXSendPause * NSEC_PER_SEC)),
                               dispatch_get_main_queue(), ^{
                    MAXMessagesModule *strongSelf = weakSelf;
                    if (strongSelf == nil) return;

                    [strongSelf sendMessagePayload:payload
                                           attempt:attempt + 1
                                        completion:completion];
                });
                return;
            }

            if (notReady) {
                NSLog(@"[Max/Чат] вложение так и не подготовилось за %lu попыток",
                      (unsigned long)MAXSendAttempts);
            } else if (reason.length > 0) {
                NSLog(@"[Max/Чат] сообщение отвергнуто: %@", reason);
            }

            if (completion != nil) completion(nil, error);
            return;
        }

        id sent = packet.payloadMap[@"message"];
        id messageId = [sent isKindOfClass:[NSDictionary class]]
            ? ((NSDictionary *)sent)[@"id"] : nil;
        if (completion != nil) completion(messageId != nil ? [messageId description] : @"", nil);
    }];
}

- (void)resolveDownloadURLForBaseURL:(NSString *)baseURL
                               token:(NSString *)token
                          completion:(void (^)(NSString *url, NSError *error))completion {
    if (baseURL.length == 0) {
        completion(nil, [NSError errorWithDomain:@"ru.max.messages"
                                            code:1
                                        userInfo:@{NSLocalizedDescriptionKey:
                            @"У вложения нет адреса"}]);
        return;
    }

    [[MAXApi shared] sendRequestWithOpcode:MAXOpcodeFileDownload
                                   payload:@{@"url": baseURL, @"token": (token ?: @"")}
                                    silent:YES
                                completion:^(MAXPacket *packet, NSError *error) {
        if (error != nil) {
            completion(nil, error);
            return;
        }
        id content = packet.payloadMap[@"content"];
        if ([content isKindOfClass:[NSString class]] && [content length] > 0) {
            completion(content, nil);
            return;
        }
        completion(nil, [NSError errorWithDomain:@"ru.max.messages"
                                            code:2
                                        userInfo:@{NSLocalizedDescriptionKey:
                            @"Сервер не дал ссылку на файл"}]);
    }];
}

#pragma mark - Правка, удаление, пересылка

- (void)editMessage:(NSString *)messageId
             inChat:(long long)chatId
               text:(NSString *)text
         completion:(MAXVoidCompletionBlock)completion {
    [self editMessage:messageId inChat:chatId text:text markup:nil completion:completion];
}

- (void)editMessage:(NSString *)messageId
             inChat:(long long)chatId
               text:(NSString *)text
             markup:(NSArray *)markup
         completion:(MAXVoidCompletionBlock)completion {
    // Разметку сервер заменяет целиком, а не дополняет: не пошли мы её
    // заново — и правленое сообщение осталось бы без ссылок.
    NSDictionary *payload = @{@"messageId": @([messageId longLongValue]),
                              @"chatId": @(chatId),
                              @"elements": ([MAXRichText elementsForText:text
                                                                 applied:markup] ?: @[]),
                              @"text": (text ?: @"")};

    [[MAXApi shared] sendRequestWithOpcode:MAXOpcodeMsgEdit
                                   payload:payload
                                completion:^(MAXPacket *packet, NSError *error) {
        if (completion != nil) completion(error);
    }];
}

- (void)deleteMessages:(NSArray *)messageIds
                inChat:(long long)chatId
           forEveryone:(BOOL)forEveryone
            completion:(MAXVoidCompletionBlock)completion {
    NSMutableArray *ids = [NSMutableArray array];
    for (NSString *messageId in messageIds) {
        long long value = [messageId longLongValue];
        if (value != 0) [ids addObject:@(value)];
    }

    if (ids.count == 0) {
        if (completion != nil) completion(nil);
        return;
    }

    // `forMe` — обратное «удалить у всех»: сервер спрашивает именно так.
    NSDictionary *payload = @{@"messageIds": ids,
                              @"chatId": @(chatId),
                              @"forMe": @(!forEveryone),
                              @"itemType": @"REGULAR"};

    [[MAXApi shared] sendRequestWithOpcode:MAXOpcodeMsgDelete
                                   payload:payload
                                completion:^(MAXPacket *packet, NSError *error) {
        if (completion != nil) completion(error);
    }];
}

- (void)forwardMessage:(NSString *)messageId
              fromChat:(long long)sourceChatId
                toChat:(long long)targetChatId
            completion:(MAXSendCompletion)completion {
    NSDictionary *message = @{@"cid": @(-MAXNowMilliseconds()),
                              @"elements": @[],
                              @"attaches": @[],
                              @"link": @{@"type": @"FORWARD",
                                         @"chatId": @(sourceChatId),
                                         @"messageId": @([messageId longLongValue])}};

    [self sendMessagePayload:@{@"chatId": @(targetChatId),
                               @"message": message,
                               @"notify": @(YES)}
                  completion:completion];
}

- (void)setReaction:(NSString *)emoji
         forMessage:(NSString *)messageId
             inChat:(long long)chatId
         completion:(MAXVoidCompletionBlock)completion {
    BOOL cancelling = emoji.length == 0;

    NSDictionary *payload = cancelling
        ? @{@"chatId": @(chatId), @"messageId": @([messageId longLongValue])}
        : @{@"chatId": @(chatId),
            @"messageId": @([messageId longLongValue]),
            @"reaction": @{@"reactionType": @"EMOJI", @"id": emoji}};

    [[MAXApi shared] sendRequestWithOpcode:(cancelling ? MAXOpcodeMsgCancelReaction
                                                       : MAXOpcodeMsgReaction)
                                   payload:payload
                                completion:^(MAXPacket *packet, NSError *error) {
        if (completion != nil) completion(error);
    }];
}

- (void)fetchMediaForChat:(long long)chatId
          anchorMessageId:(NSString *)anchorMessageId
              attachTypes:(NSArray *)attachTypes
               completion:(MAXHistoryCompletion)completion {
    NSDictionary *payload = @{@"chatId": @(chatId),
                              @"messageId": @([anchorMessageId longLongValue]),
                              @"attachTypes": attachTypes,
                              @"forward": @(0),
                              @"backward": @(60)};

    [[MAXApi shared] sendRequestWithOpcode:MAXOpcodeChatMedia
                                   payload:payload
                                    silent:YES
                                completion:^(MAXPacket *packet, NSError *error) {
        if (error != nil) {
            completion(nil, error);
            return;
        }

        id rawMessages = packet.payloadMap[@"messages"];
        if (![rawMessages isKindOfClass:[NSArray class]]) {
            completion(@[], nil);
            return;
        }

        NSMutableArray *messages = [NSMutableArray array];
        for (id raw in rawMessages) {
            MAXMessage *message = [MAXMessage messageFromServerMap:raw chatId:chatId];
            if (message != nil) [messages addObject:message];
        }

        // Свежее сверху: у ленты вложений порядок обратный истории.
        [messages sortUsingComparator:^NSComparisonResult(MAXMessage *a, MAXMessage *b) {
            if (a.time == b.time) return NSOrderedSame;
            return a.time > b.time ? NSOrderedAscending : NSOrderedDescending;
        }];

        completion(messages, nil);
    }];
}

- (void)resolveVideoURLForVideoId:(long long)videoId
                            token:(NSString *)token
                           chatId:(long long)chatId
                        messageId:(NSString *)messageId
                       completion:(void (^)(NSString *url, NSError *error))completion {
    NSDictionary *payload = @{@"messageId": @([messageId longLongValue]),
                              @"chatId": @(chatId),
                              @"token": token ?: @"",
                              @"videoId": @(videoId)};

    [[MAXApi shared] sendRequestWithOpcode:MAXOpcodeVideoPlay
                                   payload:payload
                                    silent:YES
                                completion:^(MAXPacket *packet, NSError *error) {
        if (error != nil) {
            completion(nil, error);
            return;
        }

        // Среднее качество впереди лучшего нарочно: телефону этих лет и
        // экрана хватает, и 1080p он может не потянуть вовсе.
        NSArray *order = @[@"MP4_480", @"MP4_360", @"MP4_240", @"MP4_144",
                           @"MP4_720", @"MP4_1080"];

        NSDictionary *data = packet.payloadMap;
        for (NSString *key in order) {
            id url = data[key];
            if (![url isKindOfClass:[NSString class]] || [url length] == 0) continue;
            NSLog(@"[Max/Чат] видео: берём %@", key);
            completion(url, nil);
            return;
        }

        completion(nil, [NSError errorWithDomain:@"ru.max.messages"
                                            code:5
                                        userInfo:@{NSLocalizedDescriptionKey:
                            @"Сервер не дал ни одного качества видео"}]);
    }];
}

- (void)resolveFileURLForFileId:(long long)fileId
                         chatId:(long long)chatId
                      messageId:(NSString *)messageId
                     completion:(void (^)(NSString *url, NSError *error))completion {
    if (fileId == 0) {
        completion(nil, [NSError errorWithDomain:@"ru.max.messages"
                                            code:3
                                        userInfo:@{NSLocalizedDescriptionKey:
                            @"У вложения нет идентификатора"}]);
        return;
    }

    NSDictionary *payload = @{@"fileId": @(fileId),
                              @"chatId": @(chatId),
                              @"messageId": @([messageId longLongValue]),
                              @"itemType": @"REGULAR"};

    [[MAXApi shared] sendRequestWithOpcode:MAXOpcodeFileDownload
                                   payload:payload
                                    silent:YES
                                completion:^(MAXPacket *packet, NSError *error) {
        if (error != nil) {
            completion(nil, error);
            return;
        }

        id url = packet.payloadMap[@"url"];
        if ([url isKindOfClass:[NSString class]] && [url length] > 0) {
            completion(url, nil);
            return;
        }
        completion(nil, [NSError errorWithDomain:@"ru.max.messages"
                                            code:4
                                        userInfo:@{NSLocalizedDescriptionKey:
                            @"Сервер не дал ссылку на файл"}]);
    }];
}

/**
 * MSG_TYPING с прореживанием.
 *
 * Вызывается на каждое нажатие клавиши, а слать столько же запросов нельзя:
 * в журнале на одно короткое сообщение уходило семнадцать штук, и каждый —
 * полный круг до сервера и обратно. В Komet индикатор шлётся таймером раз
 * в четыре секунды (sticker_panel_controller.dart), тот же интервал и здесь.
 *
 * В режиме невидимки не отправляется вовсе: показывать набор, скрывая
 * присутствие, — противоречие. Komet поступает так же.
 */
- (void)sendTypingToChat:(long long)chatId {
    if ([MAXSettings antiTyping] || [MAXSettings ghostMode]) return;

    static const NSTimeInterval interval = 4.0;

    NSNumber *key = @(chatId);
    NSDate *last = _lastTypingByChat[key];
    if (last != nil && -[last timeIntervalSinceNow] < interval) return;

    _lastTypingByChat[key] = [NSDate date];
    [[MAXApi shared] sendRequestWithOpcode:MAXOpcodeMsgTyping
                                   payload:@{@"chatId": @(chatId), @"type": @"TEXT"}];
}

@end
