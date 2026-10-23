//
//  MAXSearchModule.h
//  Поиск: по своему и по всему MAX.
//
//  Порт searchMessages/searchPublic из lib/backend/modules/chats.dart и
//  экрана lib/frontend/screens/chats/search_screen.dart.
//
//  Ищется в четырёх местах сразу, и три из них разные по природе:
//
//    * контакты и свои чаты — на месте, по кэшу в памяти. Ответ мгновенный
//      и не зависит от связи;
//    * сообщения — на сервере, CHAT_SEARCH: по всей переписке, а не по одному
//      чату, и локально этого не повторить — история хранится не целиком;
//    * каналы и группы — на сервере, PUBLIC_SEARCH: то, чего у нас нет вовсе.
//

#import <Foundation/Foundation.h>

@class MAXChat;

/// Найденное сообщение. Открывается вместе с чатом и подводит историю
/// к нужному месту.
@interface MAXMessageHit : NSObject
@property (nonatomic, assign) long long chatId;
@property (nonatomic, copy) NSString *messageId;
@property (nonatomic, copy) NSString *text;
@property (nonatomic, assign) long long time;
@property (nonatomic, assign) long long senderId;
@end

/// Найденный чужой чат: канал или открытая группа.
@interface MAXPublicHit : NSObject
@property (nonatomic, assign) long long chatId;
@property (nonatomic, copy) NSString *type;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *avatarUrl;
/// Ссылка вида `@name` либо последнее сообщение — что нашлось.
@property (nonatomic, copy) NSString *subtitle;

/// Заготовка чата, чтобы открыть найденное. Настоящий приедет с историей.
- (MAXChat *)chatStub;
@end

@interface MAXSearchModule : NSObject

+ (instancetype)shared;

/// Контакты по имени и номеру — по кэшу, без запроса.
- (NSArray *)localContactsMatching:(NSString *)query;

/// Свои чаты по названию — тоже по кэшу. Диалоги ищутся по имени собеседника:
/// своего названия у них нет.
- (NSArray *)localChatsMatching:(NSString *)query;

/// CHAT_SEARCH: сообщения по всей переписке.
- (void)searchMessages:(NSString *)query
            completion:(void (^)(NSArray *hits, NSError *error))completion;

/// PUBLIC_SEARCH: каналы и группы по всему MAX.
- (void)searchPublic:(NSString *)query
          completion:(void (^)(NSArray *hits, NSError *error))completion;

@end
