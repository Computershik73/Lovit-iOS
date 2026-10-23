//
//  MAXChat.h
//  Max — чат из CHATS_LIST / payload логина / пушей.
//
//  Порт CachedChat и parseChatRow из lib/backend/modules/chat_parsing.dart.
//

#import <Foundation/Foundation.h>

@class MAXContact;

@interface MAXChat : NSObject

@property (nonatomic, assign) long long chatId;
@property (nonatomic, copy) NSString *type;          // DIALOG / CHAT / CHANNEL
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *iconUrl;

@property (nonatomic, assign) long long lastMessageId;
@property (nonatomic, assign) long long lastMessageTime;
@property (nonatomic, copy) NSString *lastMessageText;
@property (nonatomic, assign) long long lastMessageSenderId;

@property (nonatomic, assign) NSInteger unreadCount;
@property (nonatomic, assign) long long lastEventTime;
@property (nonatomic, strong) NSDictionary *participants;  // @(userId) -> @(time)
/// Сколько народу в чате на самом деле. В `participants` сервер кладёт лишь
/// горстку записей, и считать по ним — то же, что считать по первой странице.
@property (nonatomic, assign) NSInteger participantsCount;
@property (nonatomic, strong) NSSet *options;
@property (nonatomic, assign) long long ownerId;
/// Идентификаторы администраторов (NSNumber). Сервер шлёт их либо списком
/// `admins`, либо словарём `adminParticipants`.
@property (nonatomic, strong) NSSet *adminIds;

/// До какого момента чат «молчит»: 0 — уведомления включены, отрицательное —
/// выключены навсегда. Приходит не в самом чате, а в `config.chats` логина.
@property (nonatomic, assign) long long dontDisturbUntil;

/// Закреплённое сообщение чата. Приходит в самом чате, отдельного запроса
/// не требует; `pinnedMessageId` == 0 — закрепа нет.
@property (nonatomic, assign) long long pinnedMessageId;
@property (nonatomic, copy) NSString *pinnedMessageText;
@property (nonatomic, assign) long long pinnedMessageTime;

@property (nonatomic, readonly) BOOL isDialog;
@property (nonatomic, readonly) BOOL isMuted;
@property (nonatomic, readonly) BOOL isOfficial;
/// Однострочный превью последнего сообщения для списка чатов.
@property (nonatomic, readonly) NSString *lastMessagePreview;

/// `contactsById` — @(id) -> MAXContact, нужен для заголовка диалога.
+ (instancetype)chatFromServerMap:(NSDictionary *)map
                    currentUserId:(long long)currentUserId
                     contactsById:(NSDictionary *)contactsById;

/// Второй участник диалога.
- (long long)otherParticipantIdForCurrentUser:(long long)currentUserId;

/// Владелец или администратор. Порт `iAmAdmin` из Komet.
- (BOOL)isAdmin:(long long)userId;

/// Можно ли писать в этот чат. В канале — только администраторам: у Komet
/// строка ввода в каналах заменяется кнопкой уведомлений, писать оттуда нельзя.
- (BOOL)canWriteAsUser:(long long)userId;

@end
