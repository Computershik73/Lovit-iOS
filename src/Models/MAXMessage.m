//
//  MAXMessage.m
//

#import "MAXMessage.h"
#import "MAXAttachment.h"
#import "MAXRichText.h"

static NSDictionary *MAXFirstPreviewAttach(id attaches) {
    if (![attaches isKindOfClass:[NSArray class]] || [attaches count] == 0) return nil;
    for (id attach in attaches) {
        if (![attach isKindOfClass:[NSDictionary class]]) continue;
        NSString *type = [((NSDictionary *)attach)[@"_type"] description];
        if ([[type uppercaseString] isEqualToString:@"INLINE_KEYBOARD"]) continue;
        return attach;
    }
    return nil;
}

/// Вложенное сообщение из `link`, когда это пересылка.
///
/// Пересланное сообщение приходит пустым: `attaches` пуст, `text` пуст, а всё
/// содержимое — текст, вложения, отправитель, время — лежит внутри
/// `link.message`. Komet разбирает его так же, см. `ForwardedMessageAttachment
/// .fromMap` в lib/models/attachment.dart. Ответ (`link.type == REPLY`) сюда
/// не попадает намеренно: у него своё содержимое на месте, а в `link` лежит
/// лишь то, на что отвечают.
NSDictionary *MAXForwardedMessageFromPayload(NSDictionary *message) {
    if (![message isKindOfClass:[NSDictionary class]]) return nil;

    id link = message[@"link"];
    if (![link isKindOfClass:[NSDictionary class]]) return nil;

    NSString *type = [[((NSDictionary *)link)[@"type"] description] uppercaseString];
    if (![type isEqualToString:@"FORWARD"]) return nil;

    id nested = ((NSDictionary *)link)[@"message"];
    return [nested isKindOfClass:[NSDictionary class]] ? nested : nil;
}

/// Цитируемое сообщение из `link`, когда это ответ.
///
/// Разница с пересылкой принципиальная: у ответа своё содержимое на месте,
/// а в `link.message` лежит то, на что отвечают. Порт `ReplyInfo.fromPayload`
/// из lib/backend/modules/messages.dart.
static NSDictionary *MAXRepliedMessageFromPayload(NSDictionary *message) {
    id link = message[@"link"];
    if (![link isKindOfClass:[NSDictionary class]]) return nil;

    NSString *type = [[((NSDictionary *)link)[@"type"] description] uppercaseString];
    if (![type isEqualToString:@"REPLY"]) return nil;

    id nested = ((NSDictionary *)link)[@"message"];
    return [nested isKindOfClass:[NSDictionary class]] ? nested : nil;
}

static NSString *MAXControlPreviewLabel(NSDictionary *control) {
    NSString *title = control[@"title"];
    if ([title isKindOfClass:[NSString class]] && title.length > 0) return title;

    NSString *shortMessage = control[@"shortMessage"];
    if ([shortMessage isKindOfClass:[NSString class]] && shortMessage.length > 0) {
        return shortMessage;
    }

    NSString *event = [control[@"event"] description];
    if ([event isEqualToString:@"new"]) return @"Чат создан";
    if ([event isEqualToString:@"add"] || [event isEqualToString:@"joinByLink"]) {
        return @"Участник добавлен";
    }
    if ([event isEqualToString:@"remove"] || [event isEqualToString:@"leave"]) {
        return @"Участник вышел";
    }
    if ([event isEqualToString:@"title"]) return @"Название изменено";
    if ([event isEqualToString:@"icon"]) return @"Аватар изменён";
    if ([event isEqualToString:@"pin"]) return @"Сообщение закреплено";
    return @"Системное сообщение";
}

NSString *MAXAttachmentPreviewLabel(id attaches) {
    NSDictionary *first = MAXFirstPreviewAttach(attaches);
    if (first == nil) return nil;

    NSString *type = [[first[@"_type"] description] uppercaseString];

    if ([type isEqualToString:@"PHOTO"]) return @"Фото";
    if ([type isEqualToString:@"VIDEO"]) {
        id videoType = first[@"videoType"];
        BOOL isNote = [[videoType description] isEqualToString:@"1"];
        return isNote ? @"Видео-сообщение" : @"Видео";
    }
    if ([type isEqualToString:@"AUDIO"]) return @"Голосовое сообщение";
    if ([type isEqualToString:@"VIDEO"]) {
        id kind = first[@"videoType"];
        if ([kind isKindOfClass:[NSNumber class]] && [kind longLongValue] == 1) {
            return @"Видеосообщение";
        }
    }
    if ([type isEqualToString:@"FILE"]) {
        // Та же починка, что в самой переписке: иначе в чате имя уже
        // читаемое, а в списке чатов — всё ещё кракозябры.
        NSString *name = MAXRepairedFileName([first[@"name"] description]);
        return name.length > 0 ? [NSString stringWithFormat:@"Файл: %@", name] : @"Файл";
    }
    if ([type isEqualToString:@"STICKER"]) return @"Стикер";
    if ([type isEqualToString:@"SHARE"]) {
        NSString *title = [first[@"title"] description];
        return title.length > 0 ? [NSString stringWithFormat:@"Ссылка: %@", title] : @"Ссылка";
    }
    if ([type isEqualToString:@"POLL"]) {
        NSString *title = [first[@"title"] description];
        return title.length > 0 ? [NSString stringWithFormat:@"Опрос: %@", title] : @"Опрос";
    }
    if ([type isEqualToString:@"LOCATION"]) return @"Геопозиция";
    if ([type isEqualToString:@"CONTACT"]) return @"Контакт";
    if ([type isEqualToString:@"CONTROL"]) return MAXControlPreviewLabel(first);
    if ([type isEqualToString:@"INLINE_KEYBOARD"]) return nil;
    if ([type isEqualToString:@"CALL"]) {
        BOOL video = [[[first[@"callType"] description] uppercaseString] isEqualToString:@"VIDEO"];
        long long duration = [first[@"duration"] isKindOfClass:[NSNumber class]]
            ? [first[@"duration"] longLongValue] : 0;
        NSString *hangup = [first[@"hangupType"] description];
        BOOL failed = duration == 0
            || [hangup isEqualToString:@"CANCELED"]
            || [hangup isEqualToString:@"REJECTED"]
            || [hangup isEqualToString:@"MISSED"];

        if (first[@"joinLink"] != nil && first[@"joinLink"] != [NSNull null]) {
            return video ? @"Групповой видеозвонок" : @"Групповой звонок";
        }
        if (failed) return video ? @"Пропущенный видеозвонок" : @"Пропущенный звонок";
        return video ? @"Видеозвонок" : @"Звонок";
    }
    return @"Вложение";
}

NSString *MAXMessagePreviewText(NSDictionary *message) {
    if (![message isKindOfClass:[NSDictionary class]]) return nil;

    id text = message[@"text"];
    if ([text isKindOfClass:[NSString class]] && [text length] > 0) return text;

    NSString *label = MAXAttachmentPreviewLabel(message[@"attaches"]);
    if (label != nil) return label;

    // У пересылки собственного содержимого нет: без этого в списке чатов
    // последним сообщением была пустая строка.
    NSDictionary *forwarded = MAXForwardedMessageFromPayload(message);
    if (forwarded != nil) {
        id forwardedText = forwarded[@"text"];
        if ([forwardedText isKindOfClass:[NSString class]] && [forwardedText length] > 0) {
            return forwardedText;
        }
        return MAXAttachmentPreviewLabel(forwarded[@"attaches"]) ?: @"Пересланное сообщение";
    }

    return nil;
}

@implementation MAXMessage {
    NSArray *_parsedMarkup;
    NSArray *_parsedAttachments;
    BOOL _attachmentsParsed;
}

@synthesize myReaction = _myReaction;

+ (instancetype)messageFromServerMap:(NSDictionary *)map chatId:(long long)chatId {
    if (![map isKindOfClass:[NSDictionary class]]) return nil;
    id rawId = map[@"id"];
    if (rawId == nil || rawId == [NSNull null]) return nil;

    MAXMessage *message = [[MAXMessage alloc] init];
    message.messageId = [rawId description];
    message.chatId = chatId;
    message.payload = map;

    id sender = map[@"sender"];
    message.senderId = [sender isKindOfClass:[NSNumber class]]
        ? [sender longLongValue] : [[sender description] longLongValue];

    id text = map[@"text"];
    message.text = [text isKindOfClass:[NSString class]] ? text : nil;

    // Пересылка: содержимое берётся из вложенного сообщения, если своего нет.
    // Своё бывает — когда пересылают с припиской, — и тогда оно главнее.
    NSDictionary *forwarded = MAXForwardedMessageFromPayload(map);
    if (forwarded != nil) {
        message.forwardedPayload = forwarded;

        if (message.text.length == 0) {
            id forwardedText = forwarded[@"text"];
            message.text = [forwardedText isKindOfClass:[NSString class]] ? forwardedText : nil;
        }

        id forwardedSender = forwarded[@"sender"];
        message.forwardedSenderId = [forwardedSender isKindOfClass:[NSNumber class]]
            ? [forwardedSender longLongValue] : [[forwardedSender description] longLongValue];

        id forwardedId = forwarded[@"id"];
        if (forwardedId != nil && forwardedId != [NSNull null]) {
            message.forwardedMessageId = [forwardedId description];
        }

        id forwardedTime = forwarded[@"time"];
        message.forwardedTime = [forwardedTime isKindOfClass:[NSNumber class]]
            ? [forwardedTime longLongValue] : [[forwardedTime description] longLongValue];

        message.forwardedIsChannel =
            [[[forwarded[@"type"] description] uppercaseString] isEqualToString:@"CHANNEL"];

        id link = map[@"link"];
        if ([link isKindOfClass:[NSDictionary class]]) {
            id chatName = ((NSDictionary *)link)[@"chatName"];
            if ([chatName isKindOfClass:[NSString class]] && [chatName length] > 0) {
                message.forwardedFrom = chatName;
            }

            id sourceChatId = ((NSDictionary *)link)[@"chatId"];
            message.forwardedChatId = [sourceChatId isKindOfClass:[NSNumber class]]
                ? [sourceChatId longLongValue] : [[sourceChatId description] longLongValue];
        }
    }

    NSDictionary *replied = MAXRepliedMessageFromPayload(map);
    if (replied != nil) {
        message.replyPayload = replied;

        id replySender = replied[@"sender"];
        message.replySenderId = [replySender isKindOfClass:[NSNumber class]]
            ? [replySender longLongValue] : [[replySender description] longLongValue];

        id replyId = replied[@"id"];
        if (replyId != nil && replyId != [NSNull null]) {
            message.replyMessageId = [replyId description];
        }

        id replyTime = replied[@"time"];
        message.replyTime = [replyTime isKindOfClass:[NSNumber class]]
            ? [replyTime longLongValue] : [[replyTime description] longLongValue];
    }

    id time = map[@"time"];
    message.time = [time isKindOfClass:[NSNumber class]]
        ? [time longLongValue] : [[time description] longLongValue];

    id status = map[@"status"];
    message.status = [status isKindOfClass:[NSString class]] ? status : nil;

    id attaches = map[@"attaches"];
    if (MAXFirstPreviewAttach(attaches) == nil && forwarded != nil) {
        attaches = forwarded[@"attaches"];
    }
    NSDictionary *first = MAXFirstPreviewAttach(attaches);
    message.isControl = [[[first[@"_type"] description] uppercaseString] isEqualToString:@"CONTROL"];

    return message;
}

- (NSDate *)date {
    return [NSDate dateWithTimeIntervalSince1970:(_time / 1000.0)];
}

/// Разбор откладывается до первого обращения: разметка есть у меньшинства
/// сообщений, а список прокручивается часто.
- (NSArray *)markupRanges {
    if (_parsedMarkup != nil) return _parsedMarkup;

    id elements = _payload[@"elements"];
    if (![elements isKindOfClass:[NSArray class]] && _forwardedPayload != nil) {
        elements = _forwardedPayload[@"elements"];
    }

    _parsedMarkup = [MAXRichText rangesFromElements:elements];
    return _parsedMarkup;
}

/// Разбор откладывается до первого обращения: у большинства сообщений
/// вложений нет вовсе, а список прокручивается часто.
- (NSArray *)attachments {
    if (_parsedAttachments == nil && !_attachmentsParsed) {
        _attachmentsParsed = YES;
        _parsedAttachments = [MAXAttachment attachmentsFromMessagePayload:_payload];
        if (_parsedAttachments == nil && _forwardedPayload != nil) {
            _parsedAttachments = [MAXAttachment attachmentsFromMessagePayload:_forwardedPayload];
        }
    }
    return _parsedAttachments;
}

- (id)attachmentOfType:(MAXAttachmentType)type {
    for (MAXAttachment *attachment in self.attachments) {
        if (attachment.type == type) return attachment;
    }
    return nil;
}

- (id)photoAttachment {
    return [self attachmentOfType:MAXAttachmentTypePhoto];
}

/// Картинки пузыря — фотографии, стикеры и видео.
///
/// Стикер здесь не для полноты: он приходит такой же картинкой с адресом
/// и размерами, и без него сообщение со стикером рисовалось пустым пузырём —
/// ровно как когда-то пересланные фотографии.
///
/// Видео — тоже плитка: сервер даёт к нему кадр тем же полем, что и адрес
/// фотографии. Раньше оно не попадало сюда вовсе, и от ролика в переписке
/// оставалась одна подпись «Видео», которую даже нажать было нельзя.
- (NSArray *)photoAttachments {
    NSMutableArray *photos = [NSMutableArray array];
    for (MAXAttachment *attachment in self.attachments) {
        if (attachment.type == MAXAttachmentTypePhoto
                || attachment.type == MAXAttachmentTypeSticker
                || attachment.type == MAXAttachmentTypeVideo) {
            [photos addObject:attachment];
        }
    }
    return photos;
}

- (id)fileAttachment {
    return [self attachmentOfType:MAXAttachmentTypeFile];
}

- (id)voiceAttachment {
    return [self attachmentOfType:MAXAttachmentTypeAudio];
}

- (NSString *)replyPreview {
    if (_replyPayload == nil) return nil;

    NSString *preview = MAXMessagePreviewText(_replyPayload);
    if (preview.length > 0) {
        return [preview stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
    }
    // Сервер прислал ссылку без самого сообщения — бывает, когда отвечают
    // на что-то удалённое.
    return @"Сообщение";
}

/// Реакции лежат в `reactionInfo.counters` — список пар «эмодзи, счётчик»,
/// плюс `yourReaction`. Порт ReactionInfo.fromMap: показываем их одной
/// строкой, отдельной панели с лицами в порте нет.
- (NSString *)reactionsSummary {
    id info = _payload[@"reactionInfo"];
    if (![info isKindOfClass:[NSDictionary class]]) return nil;

    id counters = ((NSDictionary *)info)[@"counters"];
    if (![counters isKindOfClass:[NSArray class]] || [counters count] == 0) return nil;

    NSMutableArray *parts = [NSMutableArray array];
    for (id entry in counters) {
        if (![entry isKindOfClass:[NSDictionary class]]) continue;

        id emoji = ((NSDictionary *)entry)[@"reaction"];
        if (![emoji isKindOfClass:[NSString class]] || [emoji length] == 0) continue;

        id count = ((NSDictionary *)entry)[@"count"];
        long long value = [count isKindOfClass:[NSNumber class]] ? [count longLongValue] : 0;

        [parts addObject:(value > 1
                          ? [NSString stringWithFormat:@"%@ %lld", emoji, value]
                          : emoji)];
    }

    return parts.count > 0 ? [parts componentsJoinedByString:@"  "] : nil;
}

- (void)applyReactionCounters:(NSArray *)counters {
    NSMutableDictionary *payload = [_payload mutableCopy] ?: [NSMutableDictionary dictionary];

    NSMutableDictionary *info = [payload[@"reactionInfo"] isKindOfClass:[NSDictionary class]]
        ? [payload[@"reactionInfo"] mutableCopy]
        : [NSMutableDictionary dictionary];

    info[@"counters"] = counters ?: @[];
    payload[@"reactionInfo"] = info;
    _payload = payload;
}

- (void)applyMyReaction:(NSString *)emoji instead:(NSString *)previous {
    NSMutableArray *counters = [NSMutableArray array];

    id info = _payload[@"reactionInfo"];
    id existing = [info isKindOfClass:[NSDictionary class]] ? ((NSDictionary *)info)[@"counters"] : nil;
    if ([existing isKindOfClass:[NSArray class]]) {
        for (id entry in existing) {
            if ([entry isKindOfClass:[NSDictionary class]]) [counters addObject:[entry mutableCopy]];
        }
    }

    // Снятая уходит из счёта, поставленная прибавляется; новой строки может
    // и не быть вовсе — тогда она заводится.
    if (previous.length > 0) [self shiftCount:-1 forReaction:previous in:counters];
    if (emoji.length > 0) [self shiftCount:+1 forReaction:emoji in:counters];

    [self applyReactionCounters:counters];
}

- (void)shiftCount:(NSInteger)delta
       forReaction:(NSString *)emoji
                in:(NSMutableArray *)counters {
    for (NSUInteger i = 0; i < counters.count; i++) {
        NSMutableDictionary *entry = counters[i];
        if (![entry[@"reaction"] isEqual:emoji]) continue;

        long long count = [entry[@"count"] isKindOfClass:[NSNumber class]]
            ? [entry[@"count"] longLongValue] : 0;
        count += delta;

        if (count <= 0) [counters removeObjectAtIndex:i];
        else entry[@"count"] = @(count);
        return;
    }

    if (delta > 0) {
        [counters addObject:[@{@"reaction": emoji, @"count": @(delta)} mutableCopy]];
    }
}

- (NSString *)myReaction {
    if (_myReaction != nil) return _myReaction;

    id info = _payload[@"reactionInfo"];
    if (![info isKindOfClass:[NSDictionary class]]) return nil;

    id mine = ((NSDictionary *)info)[@"yourReaction"];
    return [mine isKindOfClass:[NSString class]] ? mine : nil;
}

- (NSString *)displayText {
    if (_text.length > 0) return _text;

    NSString *label = MAXAttachmentPreviewLabel(_payload[@"attaches"]);
    if (label == nil && _forwardedPayload != nil) {
        label = MAXAttachmentPreviewLabel(_forwardedPayload[@"attaches"])
             ?: @"Пересланное сообщение";
    }
    return label ?: @"";
}

@end
