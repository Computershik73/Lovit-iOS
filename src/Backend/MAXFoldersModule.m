//
//  MAXFoldersModule.m
//

#import "MAXFoldersModule.h"
#import "MAXApi.h"
#import "MAXOpcodes.h"
#import "MAXPacket.h"
#import "MAXChat.h"

NSString *const MAXFoldersDidChangeNotification = @"MAXFoldersDidChangeNotification";

/// Признаки отбора. Числа взяты из Komet один в один; сервер шлёт их числами,
/// но в старых записях попадаются и словами — разбор ниже понимает оба вида.
typedef NS_ENUM(NSInteger, MAXFolderFilter) {
    MAXFolderFilterUnread = 0,
    MAXFolderFilterChannel = 2,
    MAXFolderFilterGroup = 3,
    MAXFolderFilterContact = 8,
    MAXFolderFilterNotContact = 9,
    MAXFolderFilterBot = 10
};

/// Признак числом, каким бы его ни прислали.
static NSInteger MAXFilterCode(id raw);

@implementation MAXFolder

+ (instancetype)folderFromServerMap:(NSDictionary *)map {
    if (![map isKindOfClass:[NSDictionary class]]) return nil;

    MAXFolder *folder = [[MAXFolder alloc] init];
    folder.folderId = [map[@"id"] description];
    folder.title = [map[@"title"] description];

    id include = map[@"include"];
    if ([include isKindOfClass:[NSArray class]]) {
        NSMutableSet *ids = [NSMutableSet set];
        for (id item in include) [ids addObject:@([item longLongValue])];
        folder.include = ids;
    }

    id filters = map[@"filters"];
    folder.filters = [filters isKindOfClass:[NSArray class]] ? filters : @[];

    return folder;
}

/**
 * Папка «Все чаты».
 *
 * Определяется по идентификатору и по устройству самой папки, но не по
 * названию. Komet сверяет ещё и название — со списком «все», «все чаты»,
 * «all», «all chats», — и на этом ловится: заголовки папок приходят с сервера
 * переведёнными под язык устройства, и на испанском телефоне «Todos» мимо
 * такого списка проходит. Папка без единого признака отбора и так означает
 * «всё подряд» — этот признак не зависит от языка.
 */
- (BOOL)isAllChats {
    if ([_folderId isEqualToString:@"all.chat.folder"]) return YES;
    return _filters.count == 0 && _include.count == 0;
}

/// Ровно один признак — непрочитанные, и никого вручную. Такая папка
/// повторяет нашу вкладку «Новые», и показывать обе незачем.
- (BOOL)isUnreadOnly {
    if (_include.count > 0 || _filters.count != 1) return NO;
    return MAXFilterCode([_filters firstObject]) == MAXFolderFilterUnread;
}

/// Признак числом, каким бы его ни прислали.
static NSInteger MAXFilterCode(id raw) {
    if ([raw isKindOfClass:[NSNumber class]]) return [raw integerValue];
    if (![raw isKindOfClass:[NSString class]]) return -1;

    NSString *name = raw;
    if ([name isEqualToString:@"UNREAD"]) return MAXFolderFilterUnread;
    if ([name isEqualToString:@"CHANNEL"]) return MAXFolderFilterChannel;
    if ([name isEqualToString:@"GROUP"] || [name isEqualToString:@"CHAT"]) {
        return MAXFolderFilterGroup;
    }
    if ([name isEqualToString:@"CONTACT"]) return MAXFolderFilterContact;
    if ([name isEqualToString:@"NOT_CONTACT"]) return MAXFolderFilterNotContact;
    if ([name isEqualToString:@"BOT"]) return MAXFolderFilterBot;

    return [name integerValue];
}

- (BOOL)matchesChat:(MAXChat *)chat
      currentUserId:(long long)currentUserId
         contactIds:(NSSet *)contactIds {
    // Включённые вручную попадают в папку независимо от признаков.
    if ([_include containsObject:@(chat.chatId)]) return YES;
    if (_filters.count == 0) return NO;

    BOOL isDialog = chat.isDialog;
    BOOL isBot = isDialog && [chat.options containsObject:@"BOT"];

    // Собеседник диалога выводится из его номера — тем же способом, каким
    // номер и складывался.
    long long peerId = isDialog ? (chat.chatId ^ currentUserId) : 0;
    BOOL isSelf = isDialog && peerId == currentUserId;
    BOOL isContact = isDialog && !isSelf && [contactIds containsObject:@(peerId)];

    for (id raw in _filters) {
        switch (MAXFilterCode(raw)) {
            case MAXFolderFilterUnread:
                if (chat.unreadCount > 0) return YES;
                break;
            case MAXFolderFilterChannel:
                if ([chat.type isEqualToString:@"CHANNEL"]) return YES;
                break;
            case MAXFolderFilterGroup:
                if ([chat.type isEqualToString:@"CHAT"]
                        || [chat.type isEqualToString:@"GROUP"]) return YES;
                break;
            case MAXFolderFilterContact:
                if (isDialog && !isBot && isContact) return YES;
                break;
            case MAXFolderFilterNotContact:
                if (isDialog && !isBot && !isSelf && !isContact) return YES;
                break;
            case MAXFolderFilterBot:
                if (isBot) return YES;
                break;
            default:
                break;
        }
    }

    return NO;
}

@end

@implementation MAXFoldersModule {
    NSArray *_folders;
}

+ (instancetype)shared {
    static MAXFoldersModule *instance = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        instance = [[MAXFoldersModule alloc] init];
    });
    return instance;
}

- (id)init {
    self = [super init];
    if (self) {
        _folders = @[];

        // Сервер шлёт изменения сам — например, когда папки правят с телефона.
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(foldersNotification:)
                                                     name:MAXApiDidReceivePushNotification
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (NSArray *)folders {
    return _folders;
}

- (void)reset {
    _folders = @[];
}

- (void)foldersNotification:(NSNotification *)note {
    MAXPacket *packet = note.userInfo[@"packet"];
    if (packet == nil || packet.opcode != MAXOpcodeNotifFolders) return;

    [self applyPayload:packet.payloadMap];
}

- (void)fetchFolders {
    [[MAXApi shared] sendRequestWithOpcode:MAXOpcodeFoldersGet
                                   payload:@{@"folderSync": @0}
                                    silent:YES
                                completion:^(MAXPacket *packet, NSError *error) {
        if (error != nil) return;
        [self applyPayload:packet.payloadMap];
    }];
}

- (void)applyPayload:(NSDictionary *)payload {
    id raw = payload[@"folders"];
    if (![raw isKindOfClass:[NSArray class]]) return;

    NSMutableArray *folders = [NSMutableArray array];
    for (id item in raw) {
        MAXFolder *folder = [MAXFolder folderFromServerMap:item];
        if (folder.folderId.length > 0) [folders addObject:folder];
    }

    // Порядок задаётся отдельным списком идентификаторов: в самих папках его
    // нет, а показывать их надо так же, как в официальном клиенте.
    id order = payload[@"foldersOrder"];
    if ([order isKindOfClass:[NSArray class]] && [order count] > 0) {
        NSMutableDictionary *positions = [NSMutableDictionary dictionary];
        NSUInteger index = 0;
        for (id identifier in order) {
            NSString *key = [identifier description];
            if (positions[key] == nil) positions[key] = @(index);
            index++;
        }

        [folders sortUsingComparator:^NSComparisonResult(MAXFolder *a, MAXFolder *b) {
            NSNumber *first = positions[a.folderId];
            NSNumber *second = positions[b.folderId];

            // Неупомянутые уходят в конец, сохраняя относительный порядок.
            if (first == nil && second == nil) return NSOrderedSame;
            if (first == nil) return NSOrderedDescending;
            if (second == nil) return NSOrderedAscending;
            return [first compare:second];
        }];
    }

    _folders = folders;
    [[NSNotificationCenter defaultCenter] postNotificationName:MAXFoldersDidChangeNotification
                                                        object:nil];
}

@end
