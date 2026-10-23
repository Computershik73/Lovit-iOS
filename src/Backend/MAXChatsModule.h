//
//  MAXChatsModule.h
//  Max — список чатов, контакты и обработка пушей.
//
//  Порт lib/backend/modules/chats.dart и contacts.dart (кэш в памяти
//  вместо SQLite — на iOS 6 хватает).
//

#import <Foundation/Foundation.h>

@class MAXChat, MAXContact;

extern NSString *const MAXChatsDidChangeNotification;
/// userInfo[@"chatId"] — чат, в котором появилось сообщение.
extern NSString *const MAXChatDidReceiveMessageNotification;

/// Сообщения удалили — у себя или у всех.
/// userInfo: @"chatId" и @"messageIds" (строками).
///
/// Без этого пуша удалённое оставалось на экране до перезахода в чат.
extern NSString *const MAXChatMessagesDeletedNotification;

/// Реакции на сообщение изменились. Пересчитывать нечего: сервер присылает
/// готовые счётчики. userInfo: @"chatId", @"messageId", @"counters".
extern NSString *const MAXChatReactionsChangedNotification;

/// Собеседник набирает сообщение. userInfo: @"chatId" и @"name".
extern NSString *const MAXChatTypingNotification;

@interface MAXChatsModule : NSObject

+ (instancetype)shared;

@property (nonatomic, assign) long long currentUserId;
/// Чаты, отсортированные по времени последнего события (свежие сверху).
@property (nonatomic, readonly) NSArray *chats;

/// Контакты, отсортированные по имени.
@property (nonatomic, readonly) NSArray *contacts;

- (MAXChat *)chatWithId:(long long)chatId;
- (MAXContact *)contactWithId:(long long)contactId;

/// Диалог с человеком — существующий или ещё не начатый.
///
/// Возвращает всегда: если переписки нет, собирается заготовка с тем же
/// идентификатором, какой чат получит на сервере. Заводится он там при первой
/// отправке, а до тех пор существует только у нас. Так открывается переписка
/// с тем, кому ещё ни разу не писали.
- (MAXChat *)dialogChatForContact:(long long)contactId;

/// CHAT_UPDATE с `pinMessageId`. Ноль снимает закреп.
///
/// `notify` — предупреждать ли участников: официальный клиент спрашивает,
/// и от этого зависит, придёт ли всем уведомление о новом закрепе.
- (void)setPinnedMessage:(long long)messageId
                  inChat:(long long)chatId
                  notify:(BOOL)notify
              completion:(void (^)(NSError *error))completion;

/// Догружает карточку человека, о котором клиент узнал не из списка чатов, —
/// например, автора пересланного сообщения. Сам обход ищет только собеседников
/// диалогов, а такой автор может не иметь с нами переписки вовсе. Уже
/// известные и уже запрошенные пропускаются, так что звать можно из отрисовки.
- (void)ensureContactWithId:(long long)contactId;

/// То же пачкой — для отправителей в групповом чате: их в списке контактов
/// может не быть вовсе, а запрашивать по одному на каждое сообщение истории
/// значило бы полсотни запросов на открытие чата.
- (void)ensureContactsWithIds:(NSArray *)contactIds;

/// Заголовок чата для показа. У диалога это имя собеседника из контактов;
/// пока контакт не догрузился — телефон или, в крайнем случае, номер чата.
- (NSString *)displayTitleForChat:(MAXChat *)chat;

/// Аватарка собеседника для диалога, иконка чата — для остальных.
- (NSString *)avatarURLForChat:(MAXChat *)chat;

/// Вторая строка шапки: «12 участников» у группы, «300 подписчиков» у канала,
/// телефон — у диалога. Komet в диалоге пишет «В сети» или «был(-а) недавно»,
/// но присутствие (`NOTIF_PRESENCE`) в порт не переносилось, а номер — то
/// немногое полезное, что о собеседнике известно наверняка.
- (NSString *)subtitleForChat:(MAXChat *)chat;

/// Разбирает `chats` и `contacts` из ответа LOGIN.
- (void)applyLoginPayload:(NSDictionary *)payload currentUserId:(long long)currentUserId;

/// Догружает оставшиеся чаты по маркеру из ответа LOGIN.
- (void)paginateChatsFromLoginPayload:(NSDictionary *)payload;

/// CHAT_MEMBERS — состав группы или канала постранично.
///
/// Список участников иначе не собрать: в `participants` у чата лежит горстка
/// записей, а карточки этих людей в адресном списке обычно отсутствуют.
/// В ответе приходят готовые карточки — они же пополняют кэш контактов.
/// `marker` — 0 для первой страницы, дальше берётся из ответа; в completion
/// приходят идентификаторы участников страницы и маркер следующей (0 — конец).
- (void)fetchMembersForChat:(long long)chatId
                     marker:(long long)marker
                 completion:(void (^)(NSArray *memberIds,
                                      long long nextMarker,
                                      NSError *error))completion;

/// CHAT_INFO — то, чего нет в списке чатов: описание, ссылка канала и число
/// подписчиков. В completion приезжает карточка чата с сервера как есть.
- (void)fetchInfoForChat:(long long)chatId
              completion:(void (^)(NSDictionary *info, NSError *error))completion;

/// То же, но только описание.
- (void)fetchDescriptionForChat:(long long)chatId
                     completion:(void (^)(NSString *text, NSError *error))completion;

/// CHAT_JOIN — подписка на канал по его ссылке.
///
/// Отдельного «подписаться по номеру чата» в MAX нет: вступают по ссылке,
/// а её отдаёт CHAT_INFO. Отписка — это CHAT_LEAVE, тот же вызов, что и выход
/// из группы.
- (void)joinChannelWithLink:(NSString *)link
                 completion:(void (^)(MAXChat *chat, NSError *error))completion;

/// Подписаться на канал, зная только его номер: сведения, из них ссылка,
/// и уже по ней вступление.
- (void)subscribeToChannel:(long long)chatId
                completion:(void (^)(MAXChat *chat, NSError *error))completion;

#pragma mark - Действия над чатом

/// CHAT_LEAVE — выйти из группы или отписаться от канала. Чат уходит из списка.
- (void)leaveChat:(long long)chatId completion:(void (^)(NSError *error))completion;

/// CHAT_CLEAR — очистить историю. `forAll` — у всех участников, а не у себя.
- (void)clearHistoryForChat:(long long)chatId
                     forAll:(BOOL)forAll
                 completion:(void (^)(NSError *error))completion;

/// Уведомления чата. Порт `setChatMute`: это не CHAT_UPDATE, а CONFIG —
/// `settings.chats.<id>.dontDisturbUntil`. 0 — включить, -1 — выключить
/// навсегда.
- (void)setMuteUntil:(long long)until
             forChat:(long long)chatId
          completion:(void (^)(NSError *error))completion;

/// CHAT_MEMBERS_UPDATE — `operation` это `add` или `remove`.
- (void)updateMembers:(NSArray *)userIds
              forChat:(long long)chatId
            operation:(NSString *)operation
           completion:(void (^)(NSError *error))completion;

/// Создание группы. Это не отдельный опкод, а MSG_SEND с вложением CONTROL
/// и событием `new` — так же, как у Komet (`_createChat`).
- (void)createGroupWithTitle:(NSString *)title
                     userIds:(NSArray *)userIds
                  completion:(void (^)(MAXChat *chat, NSError *error))completion;

#pragma mark - Действия над контактом

/// CONTACT_UPDATE с действием ADD / REMOVE / BLOCK / UNBLOCK.
- (void)updateContact:(long long)contactId
               action:(NSString *)action
            firstName:(NSString *)firstName
           completion:(void (^)(NSError *error))completion;

/// Список заблокированных (CONTACT_LIST со `status: BLOCKED`), одной страницей.
- (void)fetchBlockedContactsWithCompletion:(void (^)(NSSet *blockedIds, NSError *error))completion;

/// «В сети», «был(-а) 5 мин назад» — из записи присутствия. Порт `_headerStatus`
/// и `formatLastSeen` из Komet: `status` 1 — в сети, 2 и 3 — недавно, иначе
/// считаем по `seen` (он в секундах). Пустая строка, если сказать нечего.
NSString *MAXPresenceText(NSDictionary *presence);

/// Последнее известное присутствие человека — из ответа `CONTACT_PRESENCE`
/// или из пуша `NOTIF_PRESENCE`. nil, если о нём ещё ничего не известно.
- (NSDictionary *)presenceForContact:(long long)contactId;

/// CONTACT_PRESENCE. В ответ — @(id) -> @{@"status": …, @"seen": …}.
- (void)fetchPresenceForIds:(NSArray *)contactIds
                 completion:(void (^)(NSDictionary *presence, NSError *error))completion;

/// Идентификатор диалога с человеком: существующий, либо тот, который получится
/// при первой отправке. Komet считает его так же — `accountId ^ contactId`,
/// поэтому переписку можно открыть до того, как она заведена.
- (long long)dialogChatIdForContact:(long long)contactId;

/// CHAT_SUBSCRIBE — подписка на обновления открытого чата.
- (void)subscribeToChat:(long long)chatId subscribe:(BOOL)subscribe;

/// Обновляет строку списка по сообщению, которое клиент увидел сам —
/// отправил или получил в истории при открытии чата.
///
/// Обычно это делают пуши NOTIF_MESSAGE, но полагаться только на них нельзя:
/// пока их нет, список показывал бы то, что приехало при входе. Метод берёт
/// на себя ровно то, что клиенту и так известно, и от пушей не зависит.
- (void)noteMessage:(id)message inChat:(long long)chatId;

/// CHAT_MARK. Не отправляется, если включён режим «не отмечать прочитанным».
- (void)markChatRead:(long long)chatId messageId:(NSString *)messageId time:(long long)time;

/// Поднимает карточки прошлого запуска с диска.
///
/// Зовётся до соединения: список чатов приезжает за доли секунды, а карточки
/// собеседников — несколько, и всё это время у диалогов вместо имён стоят
/// номера. Уже известные не трогаются: с сервера приезжает свежее.
- (void)loadCachedContacts;

/// Кладёт карточки на диск немедленно — при уходе приложения в фон.
- (void)persistContactsNow;

/// Сбрасывает кэш при смене аккаунта.
- (void)reset;

@end
