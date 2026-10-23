//
//  MAXChatsModule.m
//

#import "MAXChatsModule.h"
#import "MAXApi.h"
#import "MAXOpcodes.h"
#import "MAXPacket.h"
#import "MAXSettings.h"
#import "MAXChat.h"
#import "MAXContact.h"
#import "MAXMessage.h"
#import "MAXFoldersModule.h"
#import "MAXContactsCache.h"
#import "MAXTokenStorage.h"
#import "MAXStickersModule.h"
#import "MAXTranscripts.h"

NSString *const MAXChatsDidChangeNotification = @"MAXChatsDidChangeNotification";
NSString *const MAXChatDidReceiveMessageNotification = @"MAXChatDidReceiveMessageNotification";
NSString *const MAXChatMessagesDeletedNotification = @"MAXChatMessagesDeletedNotification";
NSString *const MAXChatReactionsChangedNotification = @"MAXChatReactionsChangedNotification";
NSString *const MAXChatTypingNotification = @"MAXChatTypingNotification";

/// Числа сервер шлёт то числом, то строкой — и в номерах чатов, и в номерах
/// сообщений. Раньше на этом обработчики молча выходили.
static long long MAXLongFromValue(id value) {
    if ([value isKindOfClass:[NSNumber class]]) return [value longLongValue];
    if ([value isKindOfClass:[NSString class]]) return [value longLongValue];
    return 0;
}

static const NSInteger MAXChatsPageSize = 50;
static const NSInteger MAXChatsMaxPages = 200;

@implementation MAXChatsModule {
    NSMutableDictionary *_chatsById;
    NSMutableDictionary *_contactsById;
    NSMutableSet *_requestedContactIds;
    NSMutableDictionary *_presenceById;

    // Сообщения в чаты, которых ещё нет в списке: ждут, пока приедет сам
    // чат (CHAT_INFO). Хранится последнее — по нему чат и встанет в списке.
    NSMutableDictionary *_waitingMessages;   // @(chatId) -> @{message, unread}
    NSMutableSet *_chatsBeingFetched;        // за какими чатами уже пошли
    BOOL _paginating;
    BOOL _contactsSynced;
}

+ (instancetype)shared {
    static MAXChatsModule *instance = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        instance = [[MAXChatsModule alloc] init];
    });
    return instance;
}

- (id)init {
    self = [super init];
    if (self) {
        _chatsById = [NSMutableDictionary dictionary];
        _contactsById = [NSMutableDictionary dictionary];
        _requestedContactIds = [NSMutableSet set];
        _presenceById = [NSMutableDictionary dictionary];
        _waitingMessages = [NSMutableDictionary dictionary];
        _chatsBeingFetched = [NSMutableSet set];
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

#pragma mark - Карточки на диске

- (void)loadCachedContacts {
    long long accountId = [MAXTokenStorage activeAccountId];
    if (accountId == 0) return;

    NSArray *saved = [MAXContactsCache loadForAccount:accountId];
    if (saved.count == 0) return;

    for (MAXContact *contact in saved) {
        if (_contactsById[@(contact.contactId)] != nil) continue;
        _contactsById[@(contact.contactId)] = contact;
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:MAXChatsDidChangeNotification
                                                        object:self];
}

/// Карточки приезжают пачками, и на каждую приходит уведомление об
/// изменении списка. Сам кэш пропускает лишние записи по времени — здесь
/// достаточно просто позвать его.
- (void)persistContacts {
    long long accountId = [MAXTokenStorage activeAccountId];
    if (accountId == 0) return;
    [MAXContactsCache save:[_contactsById allValues] forAccount:accountId];
}

- (void)persistContactsNow {
    long long accountId = [MAXTokenStorage activeAccountId];
    if (accountId == 0) return;
    [MAXContactsCache forceSave:[_contactsById allValues] forAccount:accountId];
}

- (void)reset {
    long long accountId = [MAXTokenStorage activeAccountId];
    if (accountId != 0) [MAXContactsCache clearForAccount:accountId];

    [_chatsById removeAllObjects];
    [_contactsById removeAllObjects];
    [_requestedContactIds removeAllObjects];
    [_waitingMessages removeAllObjects];
    [_chatsBeingFetched removeAllObjects];
    [[MAXStickersModule shared] reset];
    [[MAXTranscripts shared] reset];
    _paginating = NO;
    _contactsSynced = NO;
    [self notifyChanged];
}

#pragma mark - Доступ

- (NSArray *)chats {
    NSArray *all = [_chatsById allValues];
    return [all sortedArrayUsingComparator:^NSComparisonResult(MAXChat *a, MAXChat *b) {
        long long left = a.lastEventTime > 0 ? a.lastEventTime : a.lastMessageTime;
        long long right = b.lastEventTime > 0 ? b.lastEventTime : b.lastMessageTime;
        if (left == right) return NSOrderedSame;
        return left > right ? NSOrderedAscending : NSOrderedDescending;
    }];
}

- (MAXChat *)chatWithId:(long long)chatId {
    return _chatsById[@(chatId)];
}

- (MAXContact *)contactWithId:(long long)contactId {
    return _contactsById[@(contactId)];
}

- (NSArray *)contacts {
    return [[_contactsById allValues] sortedArrayUsingComparator:^NSComparisonResult(MAXContact *a,
                                                                                     MAXContact *b) {
        NSString *left = a.name.length > 0 ? a.name : @"";
        NSString *right = b.name.length > 0 ? b.name : @"";
        return [left localizedCaseInsensitiveCompare:right];
    }];
}

- (NSString *)displayTitleForChat:(MAXChat *)chat {
    if (chat.title.length > 0) return chat.title;

    if (chat.isDialog) {
        long long otherId = [chat otherParticipantIdForCurrentUser:_currentUserId];

        // Диалог с самим собой: у него нет ни названия, ни второго участника,
        // и общий запасной вариант выдавал «Чат 0». В MAX это «Избранное» —
        // место, куда пересылают себе.
        if (chat.chatId == 0 || otherId == 0 || otherId == _currentUserId) {
            return @"Избранное";
        }
        MAXContact *contact = [self contactWithId:otherId];
        if (contact.name.length > 0) return contact.name;

        // Имени ещё нет — номер собеседника всё же понятнее «чата 12345».
        if (contact.phone > 0) return [NSString stringWithFormat:@"+%lld", contact.phone];
        if (otherId != 0) return [NSString stringWithFormat:@"ID %lld", otherId];
    }

    return [NSString stringWithFormat:@"Чат %lld", chat.chatId];
}

- (NSString *)avatarURLForChat:(MAXChat *)chat {
    if (chat.iconUrl.length > 0) return chat.iconUrl;
    if (!chat.isDialog) return nil;

    // У диалога своей картинки нет — она лежит в карточке собеседника,
    // а та приезжает отдельно от чата и обычно позже. Поэтому адрес
    // разрешается при показе, а не запоминается при разборе чата.
    long long otherId = [chat otherParticipantIdForCurrentUser:_currentUserId];

    // «Избранное» — диалог с самим собой: другого участника в нём нет,
    // и аватарка берётся своя.
    if (otherId == 0) otherId = _currentUserId;

    return [self contactWithId:otherId].avatarUrl;
}

/// Русский счёт: 1 участник, 2 участника, 5 участников.
static NSString *MAXPluralForm(NSUInteger count,
                               NSString *one,
                               NSString *few,
                               NSString *many) {
    NSUInteger tens = count % 100;
    if (tens >= 11 && tens <= 14) return many;

    switch (count % 10) {
        case 1: return one;
        case 2:
        case 3:
        case 4: return few;
        default: return many;
    }
}

- (NSString *)subtitleForChat:(MAXChat *)chat {
    if (chat == nil) return @"";

    if (chat.isDialog) {
        long long otherId = [chat otherParticipantIdForCurrentUser:_currentUserId];
        MAXContact *contact = [self contactWithId:otherId];
        return contact.phone > 0 ? [NSString stringWithFormat:@"+%lld", contact.phone] : @"";
    }

    // Настоящее число — в participantsCount; `participants` для этого не
    // годится, там лежит горстка записей независимо от размера чата.
    NSUInteger count = chat.participantsCount > 0
        ? (NSUInteger)chat.participantsCount
        : chat.participants.count;
    if (count == 0) return @"";

    BOOL channel = [chat.type isEqualToString:@"CHANNEL"];
    NSString *word = channel
        ? MAXPluralForm(count, @"подписчик", @"подписчика", @"подписчиков")
        : MAXPluralForm(count, @"участник", @"участника", @"участников");

    return [NSString stringWithFormat:@"%lu %@", (unsigned long)count, word];
}

- (void)notifyChanged {
    [self persistContacts];
    NSLog(@"[Max/Чаты] Список обновлён (%lu шт.)", (unsigned long)_chatsById.count);
    [[NSNotificationCenter defaultCenter] postNotificationName:MAXChatsDidChangeNotification
                                                        object:self];
}

#pragma mark - Синхронизация из LOGIN

- (void)applyLoginPayload:(NSDictionary *)payload currentUserId:(long long)currentUserId {
    _currentUserId = currentUserId;

    [self storeContacts:payload[@"contacts"]];
    [self storeChatMaps:payload[@"chats"]];
    [self applyChatsConfig:payload[@"config"]];
    [self notifyChanged];
    [self resolveMissingContacts];
    [self syncAllContacts];

    // Папки — отсюда, а не с экрана списка чатов. Экран строится при запуске,
    // когда соединения ещё нет: запрос уходил в никуда, а повторять его было
    // некому, и вкладки папок появлялись лишь тогда, когда сервер сам присылал
    // NOTIF_FOLDERS. LOGIN — первый момент, когда сессией уже можно
    // пользоваться.
    [[MAXFoldersModule shared] fetchFolders];
}

/**
 * Весь адресный список разом — порт `ContactsModule.syncFromServer` из Komet:
 * тот же опкод `CONTACTS_GET` с `contactsSync: 0`, и ответ разбирается как
 * `contacts` из LOGIN.
 *
 * До него в кэше оказывались только собеседники диалогов: обход
 * `resolveMissingContacts` идёт по чатам, а человек, с которым переписки нет,
 * в него не попадает никак. Из-за этого номерами вместо имён выглядели авторы
 * пересылок и участники групп.
 *
 * Раз за сессию: LOGIN повторяется на каждом переподключении, а список за это
 * время не меняется.
 */
- (void)syncAllContacts {
    if (_contactsSynced) return;
    _contactsSynced = YES;

    __weak MAXChatsModule *weakSelf = self;
    [[MAXApi shared] sendRequestWithOpcode:MAXOpcodeContactsGet
                                   payload:@{@"contactsSync": @(0)}
                                    silent:YES
                                completion:^(MAXPacket *packet, NSError *error) {
        MAXChatsModule *strongSelf = weakSelf;
        if (strongSelf == nil) return;

        if (error != nil) {
            // Следующий вход попробует снова: без списка имена остаются
            // номерами, и мириться с этим до перезапуска незачем.
            strongSelf->_contactsSynced = NO;
            NSLog(@"[Max/Контакты] Список не получен: %@", error.localizedDescription);
            return;
        }

        id contacts = packet.payloadMap[@"contacts"];
        if (![contacts isKindOfClass:[NSArray class]]) return;

        NSLog(@"[Max/Контакты] Получено %lu", (unsigned long)[contacts count]);
        if ([strongSelf storeContacts:contacts]) [strongSelf notifyChanged];
    }];
}

- (BOOL)storeContacts:(id)contacts {
    if (![contacts isKindOfClass:[NSArray class]]) return NO;

    BOOL added = NO;
    for (id raw in contacts) {
        MAXContact *contact = [MAXContact contactFromServerMap:raw];
        if (contact == nil) continue;
        _contactsById[@(contact.contactId)] = contact;
        added = YES;
    }
    return added;
}

/// Состояние уведомлений лежит не в чате, а в `config.chats.<id>` логина —
/// там же, куда его пишет CONFIG при переключении.
- (void)applyChatsConfig:(id)config {
    if (![config isKindOfClass:[NSDictionary class]]) return;

    id chatsConfig = ((NSDictionary *)config)[@"chats"];
    if (![chatsConfig isKindOfClass:[NSDictionary class]]) return;

    for (id key in (NSDictionary *)chatsConfig) {
        long long chatId = [[key description] longLongValue];
        MAXChat *chat = _chatsById[@(chatId)];
        if (chat == nil) continue;

        id entry = ((NSDictionary *)chatsConfig)[key];
        if (![entry isKindOfClass:[NSDictionary class]]) continue;

        id until = ((NSDictionary *)entry)[@"dontDisturbUntil"];
        if ([until isKindOfClass:[NSNumber class]]) chat.dontDisturbUntil = [until longLongValue];
    }
}

- (NSInteger)storeChatMaps:(id)chats {
    if (![chats isKindOfClass:[NSArray class]]) return 0;

    NSInteger stored = 0;
    for (id raw in chats) {
        MAXChat *chat = [MAXChat chatFromServerMap:raw
                                     currentUserId:_currentUserId
                                      contactsById:_contactsById];
        if (chat == nil) continue;

        // У диалогов заголовок приходит только из контактов; если контакт
        // ещё не загружен, сохраняем прежнее имя вместо пустого.
        MAXChat *existing = _chatsById[@(chat.chatId)];
        if (chat.title.length == 0 && existing.title.length > 0) {
            chat.title = existing.title;
            chat.iconUrl = existing.iconUrl;
        }

        _chatsById[@(chat.chatId)] = chat;
        stored++;
    }
    return stored;
}

/**
 * Догружает контакты, которых нет в кэше.
 *
 * Заголовок диалога — это имя собеседника, а оно приходит не в самом чате,
 * а отдельным списком `contacts`. В ответе на LOGIN он есть не всегда (и уж
 * точно его нет в постраничном CHATS_LIST), поэтому часть диалогов остаётся
 * без имени — именно так в списке и появлялись «Чат 1234567».
 *
 * CONTACT_INFO принимает пачку идентификаторов, так что одного запроса
 * обычно хватает на весь список.
 */
- (void)resolveMissingContacts {
    NSMutableArray *missing = [NSMutableArray array];

    for (MAXChat *chat in [_chatsById allValues]) {
        if (!chat.isDialog) continue;

        long long otherId = [chat otherParticipantIdForCurrentUser:_currentUserId];
        if (otherId == 0 || otherId == _currentUserId) continue;
        if (_contactsById[@(otherId)] != nil) continue;
        if ([_requestedContactIds containsObject:@(otherId)]) continue;

        [_requestedContactIds addObject:@(otherId)];
        [missing addObject:@(otherId)];
    }

    if (missing.count == 0) return;

    // Пачками: список контактов у активного пользователя бывает длинным,
    // а сервер на слишком большой запрос отвечает ошибкой целиком.
    const NSUInteger batchSize = 100;
    for (NSUInteger offset = 0; offset < missing.count; offset += batchSize) {
        NSRange range = NSMakeRange(offset, MIN(batchSize, missing.count - offset));
        [self requestContactInfoForIds:[missing subarrayWithRange:range]];
    }
}

- (void)fetchMembersForChat:(long long)chatId
                     marker:(long long)marker
                 completion:(void (^)(NSArray *memberIds,
                                      long long nextMarker,
                                      NSError *error))completion {
    NSDictionary *payload = @{@"chatId": @(chatId),
                              @"type": @"MEMBER",
                              @"marker": @(marker),
                              @"count": @(50)};

    __weak MAXChatsModule *weakSelf = self;
    [[MAXApi shared] sendRequestWithOpcode:MAXOpcodeChatMembers
                                   payload:payload
                                    silent:YES
                                completion:^(MAXPacket *packet, NSError *error) {
        MAXChatsModule *strongSelf = weakSelf;
        if (strongSelf == nil) return;

        if (error != nil) {
            completion(nil, 0, error);
            return;
        }

        NSDictionary *data = packet.payloadMap;
        id rawMembers = data[@"members"];

        NSMutableArray *ids = [NSMutableArray array];
        BOOL added = NO;

        if ([rawMembers isKindOfClass:[NSArray class]]) {
            for (id member in rawMembers) {
                if (![member isKindOfClass:[NSDictionary class]]) continue;

                // Карточка лежит внутри записи об участии — рядом с ней
                // сервер шлёт ещё и присутствие, но его порт не показывает.
                id rawContact = ((NSDictionary *)member)[@"contact"];
                MAXContact *contact = [MAXContact contactFromServerMap:rawContact];
                if (contact == nil || contact.contactId == 0) continue;

                strongSelf->_contactsById[@(contact.contactId)] = contact;
                [strongSelf->_requestedContactIds addObject:@(contact.contactId)];
                [ids addObject:@(contact.contactId)];
                added = YES;
            }
        }

        id nextMarker = data[@"marker"];
        long long next = [nextMarker isKindOfClass:[NSNumber class]]
            ? [nextMarker longLongValue] : 0;

        if (added) [strongSelf notifyChanged];
        completion(ids, next, nil);
    }];
}

#pragma mark - Действия над чатом

/// Общий хвост для действий, которым от ответа нужен только успех или ошибка.
- (void)sendAction:(NSUInteger)opcode
           payload:(NSDictionary *)payload
        completion:(void (^)(NSError *error))completion {
    [[MAXApi shared] sendRequestWithOpcode:opcode
                                   payload:payload
                                    silent:YES
                                completion:^(MAXPacket *packet, NSError *error) {
        if (completion != nil) completion(error);
    }];
}

- (void)leaveChat:(long long)chatId completion:(void (^)(NSError *error))completion {
    __weak MAXChatsModule *weakSelf = self;
    [self sendAction:MAXOpcodeChatLeave
             payload:@{@"chatId": @(chatId)}
          completion:^(NSError *error) {
        MAXChatsModule *strongSelf = weakSelf;
        if (strongSelf != nil && error == nil) {
            [strongSelf->_chatsById removeObjectForKey:@(chatId)];
            [strongSelf notifyChanged];
        }
        if (completion != nil) completion(error);
    }];
}

- (void)clearHistoryForChat:(long long)chatId
                     forAll:(BOOL)forAll
                 completion:(void (^)(NSError *error))completion {
    MAXChat *chat = [self chatWithId:chatId];
    long long lastEventTime = chat.lastEventTime > 0 ? chat.lastEventTime : chat.lastMessageTime;

    [self sendAction:MAXOpcodeChatClear
             payload:@{@"chatId": @(chatId),
                       @"lastEventTime": @(lastEventTime),
                       @"forAll": @(forAll)}
          completion:completion];
}

- (void)setMuteUntil:(long long)until
             forChat:(long long)chatId
          completion:(void (^)(NSError *error))completion {
    // Ключ чата в настройках — строка: MessagePack различает числовые
    // и строковые ключи, а сервер ждёт именно строку.
    NSDictionary *payload = @{@"settings":
        @{@"chats": @{[NSString stringWithFormat:@"%lld", chatId]:
                          @{@"dontDisturbUntil": @(until)}}}};

    __weak MAXChatsModule *weakSelf = self;
    [self sendAction:MAXOpcodeConfig payload:payload completion:^(NSError *error) {
        MAXChatsModule *strongSelf = weakSelf;
        if (strongSelf != nil && error == nil) {
            [strongSelf chatWithId:chatId].dontDisturbUntil = until;
            [strongSelf notifyChanged];
        }
        if (completion != nil) completion(error);
    }];
}

- (void)updateMembers:(NSArray *)userIds
              forChat:(long long)chatId
            operation:(NSString *)operation
           completion:(void (^)(NSError *error))completion {
    if (userIds.count == 0) {
        if (completion != nil) completion(nil);
        return;
    }

    [self sendAction:MAXOpcodeChatMembersUpdate
             payload:@{@"chatId": @(chatId),
                       @"userIds": userIds,
                       @"showHistory": @(YES),
                       @"operation": operation}
          completion:completion];
}

- (void)createGroupWithTitle:(NSString *)title
                     userIds:(NSArray *)userIds
                  completion:(void (^)(MAXChat *chat, NSError *error))completion {
    NSDictionary *control = @{@"_type": @"CONTROL",
                              @"event": @"new",
                              @"chatType": @"CHAT",
                              @"title": (title ?: @""),
                              @"userIds": (userIds ?: @[])};

    NSDictionary *payload = @{@"message": @{@"cid": @((long long)([[NSDate date]
                                                timeIntervalSince1970] * 1000.0)),
                                            @"attaches": @[control]},
                              @"notify": @(YES)};

    __weak MAXChatsModule *weakSelf = self;
    [[MAXApi shared] sendRequestWithOpcode:MAXOpcodeMsgSend
                                   payload:payload
                                completion:^(MAXPacket *packet, NSError *error) {
        MAXChatsModule *strongSelf = weakSelf;
        if (strongSelf == nil) return;

        if (error != nil) {
            completion(nil, error);
            return;
        }

        id rawChat = packet.payloadMap[@"chat"];
        if (![rawChat isKindOfClass:[NSDictionary class]]) {
            completion(nil, [NSError errorWithDomain:@"ru.max.chats"
                                                code:1
                                            userInfo:@{NSLocalizedDescriptionKey:
                                @"Сервер не вернул созданный чат"}]);
            return;
        }

        [strongSelf storeChatMaps:@[rawChat]];
        [strongSelf notifyChanged];
        completion([strongSelf chatWithId:[rawChat[@"id"] longLongValue]], nil);
    }];
}

#pragma mark - Действия над контактом

- (void)updateContact:(long long)contactId
               action:(NSString *)action
            firstName:(NSString *)firstName
           completion:(void (^)(NSError *error))completion {
    NSMutableDictionary *payload = [NSMutableDictionary dictionary];
    payload[@"contactId"] = @(contactId);
    payload[@"action"] = action;
    if (firstName.length > 0) payload[@"firstName"] = firstName;

    __weak MAXChatsModule *weakSelf = self;
    [[MAXApi shared] sendRequestWithOpcode:MAXOpcodeContactUpdate
                                   payload:payload
                                    silent:YES
                                completion:^(MAXPacket *packet, NSError *error) {
        MAXChatsModule *strongSelf = weakSelf;

        // В ответе приезжает свежая карточка — кладём её в кэш, чтобы имя
        // и признак «в контактах» обновились без отдельного запроса.
        if (strongSelf != nil && error == nil) {
            MAXContact *contact = [MAXContact contactFromServerMap:packet.payloadMap[@"contact"]];
            if (contact != nil && contact.contactId != 0) {
                strongSelf->_contactsById[@(contact.contactId)] = contact;
                [strongSelf notifyChanged];
            }
        }
        if (completion != nil) completion(error);
    }];
}

- (void)fetchBlockedContactsWithCompletion:(void (^)(NSSet *blockedIds, NSError *error))completion {
    [[MAXApi shared] sendRequestWithOpcode:MAXOpcodeContactList
                                   payload:@{@"status": @"BLOCKED",
                                             @"count": @(100),
                                             @"from": @(0)}
                                    silent:YES
                                completion:^(MAXPacket *packet, NSError *error) {
        if (error != nil) {
            completion(nil, error);
            return;
        }

        NSMutableSet *ids = [NSMutableSet set];
        id contacts = packet.payloadMap[@"contacts"];
        if ([contacts isKindOfClass:[NSArray class]]) {
            for (id raw in contacts) {
                if (![raw isKindOfClass:[NSDictionary class]]) continue;
                id contactId = ((NSDictionary *)raw)[@"id"];
                if ([contactId isKindOfClass:[NSNumber class]]) [ids addObject:contactId];
            }
        }
        completion(ids, nil);
    }];
}

NSString *MAXPresenceText(NSDictionary *presence) {
    if (![presence isKindOfClass:[NSDictionary class]]) return @"";

    id rawStatus = presence[@"status"];
    long long status = [rawStatus isKindOfClass:[NSNumber class]] ? [rawStatus longLongValue] : 0;

    if (status == 1) return @"В сети";
    if (status == 2 || status == 3) return @"Был(-а) недавно";

    id rawSeen = presence[@"seen"];
    long long seen = [rawSeen isKindOfClass:[NSNumber class]] ? [rawSeen longLongValue] : 0;
    if (seen <= 0) return @"";

    // `seen` приходит в секундах, а не в миллисекундах, как время сообщений.
    NSTimeInterval elapsed = [[NSDate date] timeIntervalSince1970] - (NSTimeInterval)seen;
    if (elapsed < 120) return @"Был(-а) только что";

    long long minutes = (long long)(elapsed / 60);
    if (minutes < 60) return [NSString stringWithFormat:@"Был(-а) %lld мин назад", minutes];

    long long hours = minutes / 60;
    if (hours < 24) return [NSString stringWithFormat:@"Был(-а) %lld ч назад", hours];

    long long days = hours / 24;
    if (days < 7) return [NSString stringWithFormat:@"Был(-а) %lld дн назад", days];

    NSDate *date = [NSDate dateWithTimeIntervalSince1970:(NSTimeInterval)seen];
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"d MMMM";
    formatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"ru_RU"];
    return [NSString stringWithFormat:@"Был(-а) %@", [formatter stringFromDate:date]];
}

- (void)fetchPresenceForIds:(NSArray *)contactIds
                 completion:(void (^)(NSDictionary *presence, NSError *error))completion {
    if (contactIds.count == 0) {
        completion(@{}, nil);
        return;
    }

    [[MAXApi shared] sendRequestWithOpcode:MAXOpcodeContactPresence
                                   payload:@{@"contactIds": contactIds}
                                    silent:YES
                                completion:^(MAXPacket *packet, NSError *error) {
        if (error != nil) {
            completion(nil, error);
            return;
        }

        id presence = packet.payloadMap[@"presence"];
        if (![presence isKindOfClass:[NSDictionary class]]) {
            completion(@{}, nil);
            return;
        }

        // Ключи приходят строками, а спрашивали мы числами — приводим к числам,
        // чтобы вызывающему не пришлось знать об этой мелочи.
        NSMutableDictionary *result = [NSMutableDictionary dictionary];
        for (NSNumber *contactId in contactIds) {
            id entry = ((NSDictionary *)presence)[[contactId description]]
                    ?: ((NSDictionary *)presence)[contactId];
            if (![entry isKindOfClass:[NSDictionary class]]) continue;

            result[contactId] = entry;
            self->_presenceById[contactId] = entry;
        }
        completion(result, nil);
    }];
}

- (long long)dialogChatIdForContact:(long long)contactId {
    for (MAXChat *chat in [_chatsById allValues]) {
        if (!chat.isDialog) continue;
        if ([chat otherParticipantIdForCurrentUser:_currentUserId] != contactId) continue;
        return chat.chatId;
    }
    // Переписки ещё нет. Идентификатор диалога в MAX выводится из двух
    // участников, и Komet считает его так же, — по нему чат можно открыть
    // заранее, а заведётся он на сервере при первой отправке.
    return _currentUserId ^ contactId;
}

- (MAXChat *)dialogChatForContact:(long long)contactId {
    long long chatId = [self dialogChatIdForContact:contactId];

    MAXChat *existing = [self chatWithId:chatId];
    if (existing != nil) return existing;

    // Заготовка: сервер о таком чате ещё не знает, и спрашивать его о нём
    // бесполезно — он появится там с первым сообщением. Всё, что нужно экрану
    // переписки, берётся из карточки контакта.
    MAXContact *contact = [self contactWithId:contactId];

    MAXChat *dialog = [[MAXChat alloc] init];
    dialog.chatId = chatId;
    dialog.type = @"DIALOG";
    dialog.title = contact.name;
    dialog.iconUrl = contact.avatarUrl;
    dialog.participants = @{@(contactId): @(0), @(_currentUserId): @(0)};
    return dialog;
}

- (void)setPinnedMessage:(long long)messageId
                  inChat:(long long)chatId
                  notify:(BOOL)notify
              completion:(void (^)(NSError *error))completion {
    [[MAXApi shared] sendRequestWithOpcode:MAXOpcodeChatUpdate
                                   payload:@{@"chatId": @(chatId),
                                             @"notifyPin": @(notify),
                                             @"pinMessageId": @(messageId)}
                                completion:^(MAXPacket *packet, NSError *error) {
        if (error != nil) {
            if (completion != nil) completion(error);
            return;
        }

        // В ответе приезжает обновлённый чат — им и обновляем свой, чтобы
        // полоска закрепа сменилась сразу, не дожидаясь уведомления.
        id chat = packet.payloadMap[@"chat"];
        if ([chat isKindOfClass:[NSDictionary class]]) {
            [self storeChatMaps:@[chat]];
            [self notifyChanged];
        }

        if (completion != nil) completion(nil);
    }];
}

- (void)fetchInfoForChat:(long long)chatId
              completion:(void (^)(NSDictionary *info, NSError *error))completion {
    [[MAXApi shared] sendRequestWithOpcode:MAXOpcodeChatInfo
                                   payload:@{@"chatIds": @[@(chatId)]}
                                    silent:YES
                                completion:^(MAXPacket *packet, NSError *error) {
        if (error != nil) {
            completion(nil, error);
            return;
        }

        id chats = packet.payloadMap[@"chats"];
        if (![chats isKindOfClass:[NSArray class]] || [chats count] == 0) {
            completion(nil, nil);
            return;
        }

        id first = [chats objectAtIndex:0];
        completion([first isKindOfClass:[NSDictionary class]] ? first : nil, nil);
    }];
}

- (void)fetchDescriptionForChat:(long long)chatId
                     completion:(void (^)(NSString *text, NSError *error))completion {
    [self fetchInfoForChat:chatId completion:^(NSDictionary *info, NSError *error) {
        id text = info[@"description"];
        completion([text isKindOfClass:[NSString class]] ? text : nil, error);
    }];
}

- (void)joinChannelWithLink:(NSString *)link
                 completion:(void (^)(MAXChat *chat, NSError *error))completion {
    if (link.length == 0) {
        completion(nil, [NSError errorWithDomain:@"ru.max.chats"
                                            code:1
                                        userInfo:@{NSLocalizedDescriptionKey:
                                                       @"У канала нет ссылки"}]);
        return;
    }

    [[MAXApi shared] sendRequestWithOpcode:MAXOpcodeChatJoin
                                   payload:@{@"link": link}
                                    silent:YES
                                completion:^(MAXPacket *packet, NSError *error) {
        if (error != nil) {
            completion(nil, error);
            return;
        }

        id chat = packet.payloadMap[@"chat"];
        if (![chat isKindOfClass:[NSDictionary class]]) {
            completion(nil, [NSError errorWithDomain:@"ru.max.chats"
                                                code:2
                                            userInfo:@{NSLocalizedDescriptionKey:
                                                           @"Не удалось подписаться"}]);
            return;
        }

        // Канал приезжает в ответе целиком — он же и попадает в список чатов:
        // с этой минуты подписка есть, и отдельного обновления не нужно.
        [self storeChatMaps:@[chat]];
        [self notifyChanged];

        completion([self chatWithId:[chat[@"id"] longLongValue]], nil);
    }];
}

- (void)subscribeToChannel:(long long)chatId
                completion:(void (^)(MAXChat *chat, NSError *error))completion {
    [self fetchInfoForChat:chatId completion:^(NSDictionary *info, NSError *error) {
        if (error != nil) {
            completion(nil, error);
            return;
        }

        id link = info[@"link"];
        [self joinChannelWithLink:([link isKindOfClass:[NSString class]] ? link : nil)
                       completion:completion];
    }];
}

- (void)ensureContactWithId:(long long)contactId {
    [self ensureContactsWithIds:@[@(contactId)]];
}

- (void)ensureContactsWithIds:(NSArray *)contactIds {
    NSMutableArray *missing = [NSMutableArray array];

    for (NSNumber *raw in contactIds) {
        long long contactId = [raw longLongValue];
        if (contactId == 0 || contactId == _currentUserId) continue;
        if (_contactsById[@(contactId)] != nil) continue;
        if ([_requestedContactIds containsObject:@(contactId)]) continue;

        [_requestedContactIds addObject:@(contactId)];
        [missing addObject:@(contactId)];
    }

    if (missing.count == 0) return;
    [self requestContactInfoForIds:missing];
}

- (void)requestContactInfoForIds:(NSArray *)contactIds {
    __weak MAXChatsModule *weakSelf = self;
    [[MAXApi shared] sendRequestWithOpcode:MAXOpcodeContactInfo
                                   payload:@{@"contactIds": contactIds}
                                    silent:YES
                                completion:^(MAXPacket *packet, NSError *error) {
        MAXChatsModule *strongSelf = weakSelf;
        if (strongSelf == nil) return;

        if (error != nil) {
            // Дадим следующему заходу шанс: иначе имена не появятся до
            // перезапуска приложения.
            for (NSNumber *contactId in contactIds) {
                [strongSelf->_requestedContactIds removeObject:contactId];
            }
            return;
        }

        id contacts = packet.payloadMap[@"contacts"];
        if (![contacts isKindOfClass:[NSArray class]]) return;

        BOOL added = NO;
        for (id raw in contacts) {
            MAXContact *contact = [MAXContact contactFromServerMap:raw];
            if (contact == nil) continue;
            strongSelf->_contactsById[@(contact.contactId)] = contact;
            added = YES;
        }

        if (added) [strongSelf notifyChanged];
    }];
}

- (void)paginateChatsFromLoginPayload:(NSDictionary *)payload {
    if (_paginating) return;

    id marker = payload[@"chatMarker"];
    if (![marker isKindOfClass:[NSNumber class]] || [marker longLongValue] <= 0) return;

    _paginating = YES;
    [self loadChatsPageWithMarker:[marker longLongValue] page:0];
}

- (void)loadChatsPageWithMarker:(long long)marker page:(NSInteger)page {
    if (page >= MAXChatsMaxPages) {
        _paginating = NO;
        return;
    }

    __weak MAXChatsModule *weakSelf = self;
    [[MAXApi shared] sendRequestWithOpcode:MAXOpcodeChatsList
                                   payload:@{@"marker": @(marker), @"count": @(MAXChatsPageSize)}
                                    silent:YES
                                completion:^(MAXPacket *packet, NSError *error) {
        MAXChatsModule *strongSelf = weakSelf;
        if (strongSelf == nil) return;

        if (error != nil) {
            strongSelf->_paginating = NO;
            return;
        }

        NSDictionary *data = packet.payloadMap;
        id chats = data[@"chats"];
        if (![chats isKindOfClass:[NSArray class]] || [chats count] == 0) {
            strongSelf->_paginating = NO;
            return;
        }

        [strongSelf storeContacts:data[@"contacts"]];
        [strongSelf storeChatMaps:chats];
        [strongSelf notifyChanged];
        [strongSelf resolveMissingContacts];

        id next = data[@"marker"];
        BOOL lastPage = ![next isKindOfClass:[NSNumber class]]
            || [next longLongValue] == marker
            || [chats count] < MAXChatsPageSize;

        if (lastPage) {
            strongSelf->_paginating = NO;
            return;
        }
        [strongSelf loadChatsPageWithMarker:[next longLongValue] page:page + 1];
    }];
}

#pragma mark - Действия

- (void)subscribeToChat:(long long)chatId subscribe:(BOOL)subscribe {
    [[MAXApi shared] sendRequestWithOpcode:MAXOpcodeChatSubscribe
                                   payload:@{@"chatId": @(chatId), @"subscribe": @(subscribe)}];
}

- (void)noteMessage:(id)message inChat:(long long)chatId {
    MAXMessage *seen = message;
    MAXChat *chat = [self chatWithId:chatId];
    if (chat == nil || seen == nil) return;

    // Свежее того, что уже показано, — иначе открытие старой переписки
    // выдёргивало бы её наверх списка.
    if (seen.time <= chat.lastMessageTime) return;

    chat.lastMessageId = [seen.messageId longLongValue];
    chat.lastMessageTime = seen.time;
    chat.lastMessageSenderId = seen.senderId;
    chat.lastMessageText = seen.displayText;
    chat.lastEventTime = seen.time;

    [self notifyChanged];
}

- (void)markChatRead:(long long)chatId messageId:(NSString *)messageId time:(long long)time {
    MAXChat *chat = [self chatWithId:chatId];
    if (chat == nil) return;

    // Режим «не отмечать прочитанным»: локально обнуляем счётчик, но
    // CHAT_MARK на сервер не уходит — отправитель не увидит галочку.
    if (![MAXSettings antiRead] && messageId.length > 0) {
        long long numericId = [messageId longLongValue];
        if (numericId != 0) {
            [[MAXApi shared] sendRequestWithOpcode:MAXOpcodeChatMark
                                           payload:@{@"type": @"READ_MESSAGE",
                                                     @"chatId": @(chatId),
                                                     @"messageId": @(numericId),
                                                     @"mark": @(time)}];
        }
    }

    if (chat.unreadCount != 0) {
        chat.unreadCount = 0;
        [self notifyChanged];
    }
}

#pragma mark - Пуши

- (void)handlePush:(NSNotification *)note {
    MAXPacket *packet = note.userInfo[@"packet"];
    if (packet == nil) return;

    switch (packet.opcode) {
        case MAXOpcodeNotifMessage:
            [self handleNotifMessage:packet];
            break;
        case MAXOpcodeNotifChat:
            [self handleNotifChat:packet];
            break;
        case MAXOpcodeNotifContact:
            [self handleNotifContact:packet];
            break;
        case MAXOpcodeNotifPresence:
            [self handleNotifPresence:packet];
            break;
        case MAXOpcodeNotifMsgDelete:
            [self handleNotifMessageDelete:packet];
            break;
        case MAXOpcodeNotifMsgReactionsChanged:
        case MAXOpcodeNotifMsgYouReacted:
            [self handleNotifReactions:packet];
            break;
        case MAXOpcodeNotifMark:
            [self handleNotifMark:packet];
            break;
        case MAXOpcodeNotifTyping:
            [self handleNotifTyping:packet];
            break;
        default:
            break;
    }
}

/// Присутствие приходит и пушем — без него строка «в сети» обновлялась бы
/// только при повторном открытии чата. Запись кладётся в кэш, а экраны
/// перечитывают её по тому же уведомлению, что и остальной кэш.
- (void)handleNotifPresence:(MAXPacket *)packet {
    id presence = packet.payloadMap[@"presence"];
    if (![presence isKindOfClass:[NSDictionary class]]) return;

    BOOL changed = NO;
    for (id key in (NSDictionary *)presence) {
        long long contactId = [[key description] longLongValue];
        if (contactId == 0) continue;

        id entry = ((NSDictionary *)presence)[key];
        if (![entry isKindOfClass:[NSDictionary class]]) continue;

        _presenceById[@(contactId)] = entry;
        changed = YES;
    }

    if (changed) [self notifyChanged];
}

- (NSDictionary *)presenceForContact:(long long)contactId {
    return _presenceById[@(contactId)];
}

- (void)handleNotifMessage:(MAXPacket *)packet {
    NSDictionary *payload = packet.payloadMap;

    // chatId сервер шлёт числом, но бывает и строкой — раньше на этом
    // обработчик молча выходил, и список чатов не обновлялся вовсе.
    id rawChatId = payload[@"chatId"];
    long long chatIdValue = 0;
    if ([rawChatId isKindOfClass:[NSNumber class]]) {
        chatIdValue = [rawChatId longLongValue];
    } else if ([rawChatId isKindOfClass:[NSString class]]) {
        chatIdValue = [rawChatId longLongValue];
    }

    if (chatIdValue == 0) {
        NSLog(@"[Max/Push] NOTIF_MESSAGE без chatId, ключи: %@", [payload allKeys]);
        return;
    }

    id message = payload[@"message"];
    if (![message isKindOfClass:[NSDictionary class]]) {
        NSLog(@"[Max/Push] NOTIF_MESSAGE без message, ключи: %@", [payload allKeys]);
        return;
    }

    // Комментарии к постам каналов приходят тем же опкодом — пропускаем.
    id postId = payload[@"postId"] ?: ((NSDictionary *)message)[@"postId"];
    if ([postId isKindOfClass:[NSString class]]) return;

    NSNumber *chatId = @(chatIdValue);
    MAXChat *chat = [self chatWithId:chatIdValue];

    if (chat == nil) {
        // Сообщение в чат, которого ещё нет в списке, — первое от нового
        // собеседника. Чат надо сперва запросить (CHAT_INFO), и только когда
        // он приедет, приложить к нему это сообщение: иначе чат встанет в
        // список со временем, которое сказал сервер, а то и без него — то есть
        // в самый низ, под сотни прочих, где его никто не увидит.
        //
        // Так делает Komet (notifMessage в chats.dart): дождаться чата и
        // разобрать сообщение как обычно.
        NSMutableDictionary *waiting = [NSMutableDictionary dictionary];
        waiting[@"message"] = message;
        if (payload[@"unread"] != nil) waiting[@"unread"] = payload[@"unread"];
        _waitingMessages[chatId] = waiting;

        if (![_chatsBeingFetched containsObject:chatId]) {
            NSLog(@"[Max/Push] сообщение в неизвестный чат %lld — запрашиваю его",
                  chatIdValue);
            [_chatsBeingFetched addObject:chatId];
            [self fetchChatInfo:chatIdValue];
        }
    } else {
        [self applyMessage:message unread:payload[@"unread"] toChat:chat];
        [self notifyChanged];
    }

    [[NSNotificationCenter defaultCenter]
     postNotificationName:MAXChatDidReceiveMessageNotification
                   object:self
                 userInfo:@{@"chatId": chatId, @"message": message}];
}

/// Приложить пришедшее сообщение к чату: последнее сообщение, время,
/// непрочитанное. По времени чат и встаёт в списке наверх.
///
/// `unread` — число от сервера, если он его прислал. Если нет — своё
/// сообщение счётчик не трогает, чужое прибавляет единицу.
- (void)applyMessage:(NSDictionary *)last unread:(id)unread toChat:(MAXChat *)chat {
    chat.lastMessageId = [last[@"id"] isKindOfClass:[NSNumber class]]
        ? [last[@"id"] longLongValue] : [[last[@"id"] description] longLongValue];
    chat.lastMessageTime = [last[@"time"] isKindOfClass:[NSNumber class]]
        ? [last[@"time"] longLongValue] : 0;
    chat.lastMessageSenderId = [last[@"sender"] isKindOfClass:[NSNumber class]]
        ? [last[@"sender"] longLongValue] : 0;
    chat.lastMessageText = MAXMessagePreviewText(last);
    chat.lastEventTime = chat.lastMessageTime;

    if ([unread isKindOfClass:[NSNumber class]]) chat.unreadCount = [unread integerValue];
    else if (chat.lastMessageSenderId != _currentUserId) chat.unreadCount += 1;
}

/// Сообщение удалили — у себя или у всех.
///
/// Номер чата приходит двумя способами: целым чатом в `chat` — тогда заодно
/// обновились и его сведения — либо просто числом в `chatId`.
- (void)handleNotifMessageDelete:(MAXPacket *)packet {
    NSDictionary *payload = packet.payloadMap;
    long long chatId = 0;

    id chatMap = payload[@"chat"];
    if ([chatMap isKindOfClass:[NSDictionary class]]) {
        chatId = MAXLongFromValue(((NSDictionary *)chatMap)[@"id"]);
        [self storeChatMaps:@[chatMap]];
    } else {
        // Ноль — это «Избранное», а не отсутствие номера: отличаем по ключу.
        if (payload[@"chatId"] == nil) return;
        chatId = MAXLongFromValue(payload[@"chatId"]);
    }

    id raw = payload[@"messageIds"];
    if (![raw isKindOfClass:[NSArray class]]) return;

    NSMutableArray *ids = [NSMutableArray array];
    for (id item in raw) {
        // Номера сообщений ходят и строкой, и числом.
        if (item == nil || item == [NSNull null]) continue;
        NSString *identifier = [item description];
        if (identifier.length > 0) [ids addObject:identifier];
    }
    if (ids.count == 0) return;

    [[NSNotificationCenter defaultCenter]
     postNotificationName:MAXChatMessagesDeletedNotification
                   object:self
                 userInfo:@{@"chatId": @(chatId), @"messageIds": ids}];

    [self notifyChanged];
}

- (void)handleNotifReactions:(MAXPacket *)packet {
    NSDictionary *payload = packet.payloadMap;

    id raw = payload[@"messageId"];
    if (raw == nil || raw == [NSNull null]) return;

    NSString *messageId = [raw description];
    if (messageId.length == 0) return;

    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    info[@"chatId"] = @(MAXLongFromValue(payload[@"chatId"]));
    info[@"messageId"] = messageId;

    id counters = payload[@"counters"];
    if ([counters isKindOfClass:[NSArray class]]) info[@"counters"] = counters;

    [[NSNotificationCenter defaultCenter]
     postNotificationName:MAXChatReactionsChangedNotification
                   object:self
                 userInfo:info];
}

/// Чат отметили прочитанным — с этого же аккаунта на другом устройстве или
/// собеседником. Без этого счётчик непрочитанного держался до перезапуска.
- (void)handleNotifMark:(MAXPacket *)packet {
    NSDictionary *payload = packet.payloadMap;

    long long chatId = MAXLongFromValue(payload[@"chatId"]);
    MAXChat *chat = [self chatWithId:chatId];
    if (chat == nil) return;

    // Только READ_MESSAGE: этой же отметкой сервер сообщает и о прочтении
    // собеседником, но она приходит под другим именем и нашего счётчика
    // не касается.
    if (![payload[@"type"] isEqual:@"READ_MESSAGE"]) return;

    if (chat.unreadCount == 0) return;
    chat.unreadCount = 0;
    [self notifyChanged];
}

/// Собеседник набирает сообщение. Своё же собственное «печатает» с другого
/// устройства пропускаем: показывать его себе незачем.
- (void)handleNotifTyping:(MAXPacket *)packet {
    NSDictionary *payload = packet.payloadMap;

    long long chatId = MAXLongFromValue(payload[@"chatId"]);
    long long userId = MAXLongFromValue(payload[@"userId"]);
    if (chatId == 0 || userId == _currentUserId) return;

    MAXContact *contact = [self contactWithId:userId];
    NSString *name = contact.name.length > 0 ? contact.name : @"Собеседник";

    [[NSNotificationCenter defaultCenter]
     postNotificationName:MAXChatTypingNotification
                   object:self
                 userInfo:@{@"chatId": @(chatId), @"name": name}];
}

/// CHAT_INFO для чата, который пришёл в пуше, но которого нет в списке.
- (void)fetchChatInfo:(long long)chatId {
    __weak MAXChatsModule *weakSelf = self;
    [[MAXApi shared] sendRequestWithOpcode:MAXOpcodeChatInfo
                                   payload:@{@"chatIds": @[@(chatId)]}
                                    silent:YES
                                completion:^(MAXPacket *packet, NSError *error) {
        MAXChatsModule *strongSelf = weakSelf;
        if (strongSelf == nil) return;

        // Что бы ни вышло, запрос закончен: следующее сообщение в этот чат
        // вправе спросить его заново.
        [strongSelf->_chatsBeingFetched removeObject:@(chatId)];

        id chats = packet.payloadMap[@"chats"];
        if (error != nil || ![chats isKindOfClass:[NSArray class]] || [chats count] == 0) {
            NSLog(@"[Max/Push] чат %lld не выдали: %@", chatId,
                  error.localizedDescription ?: @"пустой ответ");
            return;
        }

        // В список — только если чат наш. Присутствие в списке здесь и
        // значит членство (по нему решается, предлагать ли «выйти»), а
        // сообщение может прийти и из чужого канала, открытого из поиска:
        // пока он открыт, сервер шлёт его новые посты. На WP ровно так чужой
        // канал однажды и попадал в список.
        NSMutableArray *ours = [NSMutableArray array];
        for (id raw in chats) {
            MAXChat *probe = [MAXChat chatFromServerMap:raw
                                          currentUserId:strongSelf->_currentUserId
                                           contactsById:strongSelf->_contactsById];
            if ([strongSelf chatIsOurs:probe]) [ours addObject:raw];
            else NSLog(@"[Max/Push] чат %lld не наш (%@) — в список не кладём",
                       probe.chatId, probe.type);
        }

        if (ours.count == 0) {
            [strongSelf->_waitingMessages removeObjectForKey:@(chatId)];
            return;
        }

        [strongSelf storeChatMaps:ours];
        [strongSelf applyWaitingMessageToChat:chatId];
        [strongSelf notifyChanged];
        [strongSelf resolveMissingContacts];
    }];
}

/// Наш ли чат, пришедший на CHAT_INFO.
///
/// Диалог — всегда наш: кто-то пишет нам лично, ради этого всё и затевалось.
/// Группа — если мы среди участников; когда сервер участников не прислал,
/// верим самому сообщению — чужие группы из поиска открывают редко. Канал —
/// никогда: подписки приходят списком чатов и NOTIF_CHAT, а сообщение из
/// канала почти наверняка значит «открыли из поиска и читают».
- (BOOL)chatIsOurs:(MAXChat *)chat {
    if (chat == nil) return NO;
    if (chat.isDialog) return YES;
    if ([chat.type isEqualToString:@"CHANNEL"]) return NO;

    if (chat.participants.count == 0) return YES;
    return chat.participants[@(_currentUserId)] != nil;
}

/// Чат приехал — приложить к нему сообщение, из-за которого за ним ходили.
///
/// Непрочитанное берётся из самого чата, если сервер не прислал числа вместе
/// с сообщением: чат запрошен уже после сообщения, и его счётчик это
/// сообщение учитывает. Прибавить единицу сверху значило бы посчитать его
/// дважды.
- (void)applyWaitingMessageToChat:(long long)chatId {
    NSDictionary *waiting = _waitingMessages[@(chatId)];
    [_waitingMessages removeObjectForKey:@(chatId)];

    MAXChat *chat = _chatsById[@(chatId)];
    if (waiting == nil || chat == nil) return;

    NSDictionary *message = waiting[@"message"];
    long long time = [message[@"time"] isKindOfClass:[NSNumber class]]
        ? [message[@"time"] longLongValue] : 0;

    // Сервер мог отдать чат уже с более свежим сообщением — тогда наше
    // старше, и откатывать чат назад незачем.
    if (time < chat.lastMessageTime) return;

    NSInteger keptUnread = chat.unreadCount;
    [self applyMessage:message unread:waiting[@"unread"] toChat:chat];

    if (waiting[@"unread"] == nil) {
        // Ноль у чата при чужом сообщении — значит, счётчик сервер отдал
        // старый; хотя бы одно непрочитанное там точно есть.
        BOOL mine = (chat.lastMessageSenderId == _currentUserId);
        chat.unreadCount = (keptUnread == 0 && !mine) ? 1 : keptUnread;
    }

    NSLog(@"[Max/Push] чат %lld добавлен в список", chatId);
}

- (void)handleNotifChat:(MAXPacket *)packet {
    NSDictionary *payload = packet.payloadMap;

    // Чат приходит то одиночным `chat`, то списком `chats` — как и на WP.
    NSMutableArray *maps = [NSMutableArray array];
    id single = payload[@"chat"];
    if ([single isKindOfClass:[NSDictionary class]]) [maps addObject:single];
    id many = payload[@"chats"];
    if ([many isKindOfClass:[NSArray class]]) [maps addObjectsFromArray:many];
    if (maps.count == 0) return;

    [self storeChatMaps:maps];

    // Сервер мог прислать новый чат сам, раньше нашего ответа на CHAT_INFO, —
    // тогда ждущее сообщение прикладываем сейчас.
    for (id map in maps) {
        if (![map isKindOfClass:[NSDictionary class]]) continue;
        [self applyWaitingMessageToChat:MAXLongFromValue(((NSDictionary *)map)[@"id"])];
    }

    [self notifyChanged];
}

- (void)handleNotifContact:(MAXPacket *)packet {
    NSDictionary *payload = packet.payloadMap;
    id contact = payload[@"contact"];
    MAXContact *parsed = [MAXContact contactFromServerMap:contact];
    if (parsed == nil) return;

    _contactsById[@(parsed.contactId)] = parsed;

    // Заголовок диалога берётся из контакта — обновляем открытые чаты.
    for (MAXChat *chat in [_chatsById allValues]) {
        if (!chat.isDialog) continue;
        if ([chat otherParticipantIdForCurrentUser:_currentUserId] != parsed.contactId) continue;
        chat.title = parsed.name;
        chat.iconUrl = parsed.avatarUrl;
    }
    [self notifyChanged];
}

@end
