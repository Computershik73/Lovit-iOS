//
//  MAXChat.m
//

#import "MAXChat.h"
#import "MAXContact.h"
#import "MAXMessage.h"

@implementation MAXChat

+ (NSDictionary *)parseParticipants:(id)raw {
    if (![raw isKindOfClass:[NSDictionary class]]) return @{};

    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    for (id key in raw) {
        long long userId = 0;
        if ([key isKindOfClass:[NSNumber class]]) {
            userId = [key longLongValue];
        } else if ([key isKindOfClass:[NSString class]]) {
            userId = [key longLongValue];
        }
        if (userId == 0) continue;

        id value = ((NSDictionary *)raw)[key];
        long long time = [value isKindOfClass:[NSNumber class]] ? [value longLongValue] : 0;
        result[@(userId)] = @(time);
    }
    return result;
}

/// Администраторы приходят двумя способами: списком `admins` либо словарём
/// `adminParticipants`, где идентификаторы лежат ключами. Komet разбирает
/// оба, и по одному чату не угадать, какой пришлёт сервер.
+ (NSSet *)parseAdmins:(NSDictionary *)map {
    NSMutableSet *admins = [NSMutableSet set];

    id list = map[@"admins"];
    if ([list isKindOfClass:[NSArray class]]) {
        for (id entry in list) {
            long long value = [entry isKindOfClass:[NSNumber class]]
                ? [entry longLongValue] : [[entry description] longLongValue];
            if (value != 0) [admins addObject:@(value)];
        }
        return admins;
    }

    id participants = map[@"adminParticipants"];
    if ([participants isKindOfClass:[NSDictionary class]]) {
        for (id key in (NSDictionary *)participants) {
            long long value = [key isKindOfClass:[NSNumber class]]
                ? [key longLongValue] : [[key description] longLongValue];
            if (value != 0) [admins addObject:@(value)];
        }
    }
    return admins;
}

+ (instancetype)chatFromServerMap:(NSDictionary *)map
                    currentUserId:(long long)currentUserId
                     contactsById:(NSDictionary *)contactsById {
    if (![map isKindOfClass:[NSDictionary class]]) return nil;
    id chatId = map[@"id"];
    if (![chatId isKindOfClass:[NSNumber class]]) return nil;

    MAXChat *chat = [[MAXChat alloc] init];
    chat.chatId = [chatId longLongValue];

    id type = map[@"type"];
    chat.type = [type isKindOfClass:[NSString class]] ? type : @"DIALOG";
    chat.participants = [self parseParticipants:map[@"participants"]];

    id participantsCount = map[@"participantsCount"];
    chat.participantsCount = [participantsCount isKindOfClass:[NSNumber class]]
        ? [participantsCount integerValue] : 0;

    if (chat.isDialog) {
        long long otherId = [chat otherParticipantIdForCurrentUser:currentUserId];
        MAXContact *contact = contactsById[@(otherId)];
        chat.title = contact.name;
        chat.iconUrl = contact.avatarUrl;
        chat.options = contact.options ?: [NSSet set];
    } else {
        id title = map[@"title"];
        chat.title = [title isKindOfClass:[NSString class]] ? title : nil;

        id icon = map[@"baseIconUrl"];
        chat.iconUrl = [icon isKindOfClass:[NSString class]] ? icon : nil;

        // У групп options — это словарь флагов, а не список.
        id options = map[@"options"];
        NSMutableSet *set = [NSMutableSet set];
        if ([options isKindOfClass:[NSDictionary class]]) {
            for (id key in options) {
                if (![key isKindOfClass:[NSString class]]) continue;
                if ([((NSDictionary *)options)[key] boolValue]) [set addObject:key];
            }
        }
        chat.options = set;
    }

    // Закреп лежит рядом с последним сообщением и устроен так же: тот же
    // разбор превью годится и здесь.
    id pinned = map[@"pinnedMessage"];
    if ([pinned isKindOfClass:[NSDictionary class]]) {
        NSDictionary *message = pinned;
        chat.pinnedMessageId = [message[@"id"] longLongValue];
        chat.pinnedMessageTime = [message[@"time"] longLongValue];
        chat.pinnedMessageText = MAXMessagePreviewText(message);
    }

    id lastMessage = map[@"lastMessage"];
    if ([lastMessage isKindOfClass:[NSDictionary class]]) {
        NSDictionary *last = lastMessage;
        chat.lastMessageId = [last[@"id"] isKindOfClass:[NSNumber class]]
            ? [last[@"id"] longLongValue] : 0;
        chat.lastMessageTime = [last[@"time"] isKindOfClass:[NSNumber class]]
            ? [last[@"time"] longLongValue] : 0;
        chat.lastMessageSenderId = [last[@"sender"] isKindOfClass:[NSNumber class]]
            ? [last[@"sender"] longLongValue] : 0;
        chat.lastMessageText = MAXMessagePreviewText(last);
    }

    id unread = map[@"newMessages"];
    chat.unreadCount = [unread isKindOfClass:[NSNumber class]] ? [unread integerValue] : 0;

    id lastEvent = map[@"lastEventTime"];
    chat.lastEventTime = [lastEvent isKindOfClass:[NSNumber class]] ? [lastEvent longLongValue] : 0;

    id owner = map[@"owner"];
    chat.ownerId = [owner isKindOfClass:[NSNumber class]] ? [owner longLongValue] : 0;
    chat.adminIds = [self parseAdmins:map];

    return chat;
}

- (long long)otherParticipantIdForCurrentUser:(long long)currentUserId {
    for (NSNumber *key in _participants) {
        if ([key longLongValue] != currentUserId) return [key longLongValue];
    }
    return 0;
}

- (BOOL)isDialog {
    return [_type isEqualToString:@"DIALOG"];
}

- (BOOL)isAdmin:(long long)userId {
    if (userId == 0) return NO;
    if (_ownerId == userId) return YES;
    return [_adminIds containsObject:@(userId)];
}

/// В каналах Komet строку ввода не показывает вовсе — вместо неё кнопка
/// уведомлений (`composer_input.dart`). Права писать там у обычного читателя
/// и нет: сервер отвергнет отправку. Исключение — администраторы: канал ведут
/// они, и для них поле осмысленно.
- (BOOL)canWriteAsUser:(long long)userId {
    if (![_type isEqualToString:@"CHANNEL"]) return YES;
    return [self isAdmin:userId];
}

/// Ноль — уведомления включены, отрицательное — выключены навсегда,
/// положительное — до указанного момента. Порядок проверок как в Komet.
- (BOOL)isMuted {
    if (_dontDisturbUntil == 0) return NO;
    if (_dontDisturbUntil < 0) return YES;
    return _dontDisturbUntil > (long long)([[NSDate date] timeIntervalSince1970] * 1000.0);
}

- (BOOL)isOfficial {
    return [_options containsObject:@"OFFICIAL"];
}

- (NSString *)lastMessagePreview {
    if (_lastMessageText.length == 0) return @"";
    return [_lastMessageText stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
}

@end
