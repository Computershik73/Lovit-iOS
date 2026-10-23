//
//  MAXSearchModule.m
//

#import "MAXSearchModule.h"
#import "MAXApi.h"
#import "MAXOpcodes.h"
#import "MAXPacket.h"
#import "MAXChatsModule.h"
#import "MAXChat.h"
#import "MAXContact.h"

/// Сколько просить у сервера. Значения из Komet: сообщений больше, потому что
/// они короткие и часто повторяются по одному чату.
static const NSUInteger MAXSearchMessageCount = 50;
static const NSUInteger MAXSearchPublicCount = 20;

@implementation MAXMessageHit
@end

@implementation MAXPublicHit

- (MAXChat *)chatStub {
    MAXChat *chat = [[MAXChat alloc] init];
    chat.chatId = _chatId;
    chat.type = _type.length > 0 ? _type : @"CHAT";
    chat.title = _title;
    chat.iconUrl = _avatarUrl;
    return chat;
}

@end

@implementation MAXSearchModule

+ (instancetype)shared {
    static MAXSearchModule *instance = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        instance = [[MAXSearchModule alloc] init];
    });
    return instance;
}

#pragma mark - По кэшу

/// Сравнение без учёта регистра и в любом месте строки: искать по началу
/// слова недостаточно — фамилию в списке контактов набирают чаще имени.
static BOOL MAXSearchMatches(NSString *text, NSString *query) {
    if (text.length == 0) return NO;
    return [text rangeOfString:query options:NSCaseInsensitiveSearch].location != NSNotFound;
}

- (NSArray *)localContactsMatching:(NSString *)query {
    NSString *term = [query stringByTrimmingCharactersInSet:
                      [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (term.length == 0) return @[];

    NSMutableArray *found = [NSMutableArray array];
    for (MAXContact *contact in [MAXChatsModule shared].contacts) {
        NSString *phone = contact.phone > 0
            ? [NSString stringWithFormat:@"%lld", contact.phone] : nil;

        if (MAXSearchMatches(contact.name, term) || MAXSearchMatches(phone, term)) {
            [found addObject:contact];
        }
    }
    return found;
}

- (NSArray *)localChatsMatching:(NSString *)query {
    NSString *term = [query stringByTrimmingCharactersInSet:
                      [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (term.length == 0) return @[];

    MAXChatsModule *module = [MAXChatsModule shared];

    NSMutableArray *found = [NSMutableArray array];
    for (MAXChat *chat in module.chats) {
        // Своего названия у диалога нет — берётся то же имя, что и в списке.
        if (MAXSearchMatches([module displayTitleForChat:chat], term)) {
            [found addObject:chat];
        }
    }
    return found;
}

#pragma mark - На сервере

- (void)searchMessages:(NSString *)query
            completion:(void (^)(NSArray *hits, NSError *error))completion {
    NSString *term = [query stringByTrimmingCharactersInSet:
                      [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (term.length == 0) {
        completion(@[], nil);
        return;
    }

    [[MAXApi shared] sendRequestWithOpcode:MAXOpcodeChatSearch
                                   payload:@{@"count": @(MAXSearchMessageCount),
                                             @"query": term}
                                    silent:YES
                                completion:^(MAXPacket *packet, NSError *error) {
        if (error != nil) {
            completion(nil, error);
            return;
        }

        NSMutableArray *hits = [NSMutableArray array];
        id result = packet.payloadMap[@"result"];

        if ([result isKindOfClass:[NSArray class]]) {
            for (id item in result) {
                if (![item isKindOfClass:[NSDictionary class]]) continue;

                id message = ((NSDictionary *)item)[@"message"];
                if (![message isKindOfClass:[NSDictionary class]]) continue;

                // Чат с нулевым номером — сохранённые сообщения, их сервер
                // отдаёт отдельно и открывать по этому пути нечего.
                long long chatId = [((NSDictionary *)item)[@"chatId"] longLongValue];
                if (chatId == 0) continue;

                MAXMessageHit *hit = [[MAXMessageHit alloc] init];
                hit.chatId = chatId;
                hit.messageId = [((NSDictionary *)message)[@"id"] description];
                hit.text = ((NSDictionary *)message)[@"text"];
                hit.time = [((NSDictionary *)message)[@"time"] longLongValue];
                hit.senderId = [((NSDictionary *)message)[@"sender"] longLongValue];
                [hits addObject:hit];
            }
        }

        completion(hits, nil);
    }];
}

- (void)searchPublic:(NSString *)query
          completion:(void (^)(NSArray *hits, NSError *error))completion {
    NSString *term = [query stringByTrimmingCharactersInSet:
                      [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (term.length == 0) {
        completion(@[], nil);
        return;
    }

    [[MAXApi shared] sendRequestWithOpcode:MAXOpcodePublicSearch
                                   payload:@{@"type": @"ALL",
                                             @"count": @(MAXSearchPublicCount),
                                             @"query": term}
                                    silent:YES
                                completion:^(MAXPacket *packet, NSError *error) {
        if (error != nil) {
            completion(nil, error);
            return;
        }

        NSMutableArray *hits = [NSMutableArray array];
        id result = packet.payloadMap[@"result"];

        if ([result isKindOfClass:[NSArray class]]) {
            for (id item in result) {
                if (![item isKindOfClass:[NSDictionary class]]) continue;

                id chat = ((NSDictionary *)item)[@"chat"];
                if (![chat isKindOfClass:[NSDictionary class]]) continue;

                NSDictionary *map = chat;
                long long chatId = [map[@"id"] longLongValue];
                if (chatId == 0) continue;

                MAXPublicHit *hit = [[MAXPublicHit alloc] init];
                hit.chatId = chatId;
                hit.type = map[@"type"] ?: @"CHAT";
                hit.title = map[@"title"];
                hit.avatarUrl = map[@"baseIconUrl"];

                // Подпись: ссылка вида @name, если она есть, иначе последнее
                // сообщение — так канал отличают от одноимённого.
                NSString *link = map[@"link"];
                if ([link isKindOfClass:[NSString class]] && link.length > 0) {
                    hit.subtitle = [NSString stringWithFormat:@"@%@", link];
                } else {
                    id last = map[@"lastMessage"];
                    if ([last isKindOfClass:[NSDictionary class]]) {
                        hit.subtitle = ((NSDictionary *)last)[@"text"];
                    }
                }

                [hits addObject:hit];
            }
        }

        completion(hits, nil);
    }];
}

@end
