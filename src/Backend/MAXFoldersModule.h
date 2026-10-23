//
//  MAXFoldersModule.h
//  Папки чатов.
//
//  Порт lib/backend/modules/folders.dart и модели chat_folder.dart.
//
//  Папка — это не список чатов, а правило отбора: набор признаков (непрочитанные,
//  каналы, группы, контакты, боты) плюс поимённый список тех, кого включили
//  вручную. Поэтому состав папки считается на месте, по тем же чатам, что уже
//  лежат в памяти, а с сервера приходит только само правило.
//

#import <Foundation/Foundation.h>

@class MAXChat;

/// Папки обновились — список чатов пересобирает полоску вкладок.
extern NSString *const MAXFoldersDidChangeNotification;

@interface MAXFolder : NSObject

@property (nonatomic, copy) NSString *folderId;
@property (nonatomic, copy) NSString *title;
/// Чаты, включённые поимённо, — @(chatId).
@property (nonatomic, strong) NSSet *include;
/// Признаки отбора, числами протокола.
@property (nonatomic, strong) NSArray *filters;

+ (instancetype)folderFromServerMap:(NSDictionary *)map;

/// Папка «Все чаты» — её сервер присылает наравне с остальными, а показывать
/// второй раз незачем: она у нас и так первая вкладка.
- (BOOL)isAllChats;

/// Папка «только непрочитанные» — то же самое, что наша вкладка «Новые».
- (BOOL)isUnreadOnly;

- (BOOL)matchesChat:(MAXChat *)chat
      currentUserId:(long long)currentUserId
         contactIds:(NSSet *)contactIds;

@end

@interface MAXFoldersModule : NSObject

+ (instancetype)shared;

/// Папки в порядке, заданном сервером. Пока не загрузились — пусто.
@property (nonatomic, readonly) NSArray *folders;

/// FOLDERS_GET. Ошибки не показываются: папок у аккаунта может не быть вовсе,
/// и это не повод тревожить пользователя.
- (void)fetchFolders;

/// Разбирает `folders` и `foldersOrder` — и из ответа, и из уведомления
/// NOTIF_FOLDERS.
- (void)applyPayload:(NSDictionary *)payload;

- (void)reset;

@end
