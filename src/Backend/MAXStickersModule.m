//
//  MAXStickersModule.m
//

#import "MAXStickersModule.h"
#import "MAXApi.h"
#import "MAXOpcodes.h"
#import "MAXPacket.h"
#import "MAXSticker.h"

/// Просить всё разом нельзя: у иных наборов сотни стикеров, а сервер на
/// слишком длинный список отвечает отказом.
static const NSUInteger MAXStickersPage = 100;

@implementation MAXStickersModule {
    NSMutableDictionary *_setsById;       // @(setId) -> MAXStickerSet
    NSMutableDictionary *_stickersById;   // @(stickerId) -> MAXSticker
    NSMutableArray *_mine;                // номера своих наборов, по порядку
    NSMutableArray *_recentIds;           // номера недавних, по порядку
    NSMutableArray *_waiting;             // те, кто просил, пока шла загрузка
    BOOL _loaded;
    BOOL _loading;
}

+ (instancetype)shared {
    static MAXStickersModule *instance = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [[MAXStickersModule alloc] init]; });
    return instance;
}

- (id)init {
    self = [super init];
    if (self) {
        _setsById = [NSMutableDictionary dictionary];
        _stickersById = [NSMutableDictionary dictionary];
        _mine = [NSMutableArray array];
        _recentIds = [NSMutableArray array];
        _waiting = [NSMutableArray array];
    }
    return self;
}

- (void)reset {
    [_setsById removeAllObjects];
    [_stickersById removeAllObjects];
    [_mine removeAllObjects];
    [_recentIds removeAllObjects];
    [_waiting removeAllObjects];
    _loaded = NO;
    _loading = NO;
}

#pragma mark - Доступ

- (NSArray *)pick:(NSArray *)ids {
    NSMutableArray *found = [NSMutableArray array];
    for (NSNumber *identifier in ids) {
        MAXSticker *sticker = _stickersById[identifier];
        if (sticker != nil) [found addObject:sticker];
    }
    return found;
}

- (NSArray *)recent { return [self pick:_recentIds]; }

- (NSArray *)sets {
    NSMutableArray *found = [NSMutableArray array];
    for (NSNumber *identifier in _mine) {
        MAXStickerSet *set = _setsById[identifier];
        if (set != nil) [found addObject:set];
    }
    return found;
}

- (void)noteSent:(long long)stickerId {
    if (stickerId == 0) return;
    NSNumber *key = @(stickerId);
    [_recentIds removeObject:key];
    [_recentIds insertObject:key atIndex:0];
}

#pragma mark - Загрузка

- (void)loadWithCompletion:(void (^)(NSError *error))completion {
    if (_loaded) {
        if (completion != nil) completion(nil);
        return;
    }

    // Загрузка уже идёт — становимся в очередь. Позвать обратно сразу было бы
    // враньём: наборов в этот миг ещё нет, и панель показала бы «наборов
    // пока нет» тому, кто просто открыл её второй раз подряд.
    if (_loading) {
        if (completion != nil) [_waiting addObject:[completion copy]];
        return;
    }
    if ([MAXApi shared].state != MAXSessionStateOnline) {
        if (completion != nil) {
            completion([NSError errorWithDomain:@"ru.max.stickers"
                                           code:1
                                       userInfo:@{NSLocalizedDescriptionKey:
                                           @"Сессия не онлайн"}]);
        }
        return;
    }

    _loading = YES;
    __weak MAXStickersModule *weakSelf = self;

    // Недавние и разделы приходят одним ответом; свои наборы лежат отдельным
    // видом со своим разделом — отсюда два запроса подряд.
    [self updateType:@"STICKER" completion:^(NSDictionary *common) {
        MAXStickersModule *strongSelf = weakSelf;
        if (strongSelf == nil) return;
        [strongSelf readRecents:common];

        [strongSelf updateType:@"FAVORITE_STICKER" completion:^(NSDictionary *mine) {
            MAXStickersModule *inner = weakSelf;
            if (inner == nil) return;
            [inner readMine:mine];

            [inner fetchSets:^{
                MAXStickersModule *done = weakSelf;
                if (done == nil) return;
                done->_loading = NO;
                done->_loaded = YES;
                NSLog(@"[Max/Стикеры] наборов %lu, недавних %lu",
                      (unsigned long)done->_setsById.count,
                      (unsigned long)done->_recentIds.count);

                if (completion != nil) completion(nil);

                NSArray *waiting = [done->_waiting copy];
                [done->_waiting removeAllObjects];
                for (void (^pending)(NSError *) in waiting) pending(nil);
            }];
        }];
    }];
}

- (void)updateType:(NSString *)type completion:(void (^)(NSDictionary *payload))completion {
    [[MAXApi shared] sendRequestWithOpcode:MAXOpcodeAssetsUpdate
                                   payload:@{@"type": type, @"sync": @(0)}
                                    silent:YES
                                completion:^(MAXPacket *packet, NSError *error) {
        completion(error == nil ? packet.payloadMap : nil);
    }];
}

- (void)readRecents:(NSDictionary *)payload {
    id sections = payload[@"sections"];
    if (![sections isKindOfClass:[NSArray class]]) return;

    for (id raw in sections) {
        if (![raw isKindOfClass:[NSDictionary class]]) continue;
        NSDictionary *section = raw;
        if (![section[@"type"] isEqual:@"RECENTS"]) continue;

        // Недавние приезжают целыми стикерами, а не номерами: их и складываем
        // сразу, лишний запрос за ними не нужен.
        id list = section[@"recentsList"];
        if (![list isKindOfClass:[NSArray class]]) continue;

        for (id item in list) {
            MAXSticker *sticker = [MAXSticker stickerFromMap:item];
            if (sticker == nil) continue;
            _stickersById[@(sticker.stickerId)] = sticker;
            if (![_recentIds containsObject:@(sticker.stickerId)]) {
                [_recentIds addObject:@(sticker.stickerId)];
            }
        }
    }
}

- (void)readMine:(NSDictionary *)payload {
    id sections = payload[@"sections"];
    if (![sections isKindOfClass:[NSArray class]]) return;

    for (id raw in sections) {
        if (![raw isKindOfClass:[NSDictionary class]]) continue;
        NSDictionary *section = raw;
        if (![section[@"id"] isEqual:@"FAVORITE_STICKER_SETS"]) continue;

        id ids = section[@"stickerSets"];
        if (![ids isKindOfClass:[NSArray class]]) continue;

        for (id item in ids) {
            long long identifier = [item isKindOfClass:[NSNumber class]]
                ? [item longLongValue] : [[item description] longLongValue];
            if (identifier != 0 && ![_mine containsObject:@(identifier)]) {
                [_mine addObject:@(identifier)];
            }
        }
    }
}

- (void)fetchSets:(void (^)(void))done {
    if (_mine.count == 0) {
        done();
        return;
    }

    __weak MAXStickersModule *weakSelf = self;
    [self fetchByIds:_mine
                type:@"STICKER_SET"
                 key:@"stickerSets"
          completion:^(NSArray *found) {
        MAXStickersModule *strongSelf = weakSelf;
        if (strongSelf != nil) {
            for (id raw in found) {
                MAXStickerSet *set = [MAXStickerSet setFromMap:raw];
                if (set != nil) strongSelf->_setsById[@(set.setId)] = set;
            }
        }
        done();
    }];
}

- (void)stickersOfSet:(MAXStickerSet *)set completion:(void (^)(NSArray *stickers))completion {
    if (set == nil) {
        completion(@[]);
        return;
    }

    NSMutableArray *missing = [NSMutableArray array];
    for (NSNumber *identifier in set.stickerIds) {
        if (_stickersById[identifier] == nil) [missing addObject:identifier];
    }

    if (missing.count == 0) {
        completion([self pick:set.stickerIds]);
        return;
    }

    __weak MAXStickersModule *weakSelf = self;
    [self fetchByIds:missing
                type:@"STICKER"
                 key:@"stickers"
          completion:^(NSArray *found) {
        MAXStickersModule *strongSelf = weakSelf;
        if (strongSelf == nil) {
            completion(@[]);
            return;
        }
        for (id raw in found) {
            MAXSticker *sticker = [MAXSticker stickerFromMap:raw];
            if (sticker != nil) strongSelf->_stickersById[@(sticker.stickerId)] = sticker;
        }
        completion([strongSelf pick:set.stickerIds]);
    }];
}

#pragma mark - Набор по нажатию на стикер

- (void)setIdForSticker:(long long)stickerId
             completion:(void (^)(long long setId))completion {
    if (stickerId == 0) {
        completion(0);
        return;
    }

    MAXSticker *known = _stickersById[@(stickerId)];
    if (known != nil && known.setId != 0) {
        completion(known.setId);
        return;
    }

    __weak MAXStickersModule *weakSelf = self;
    [self fetchByIds:@[@(stickerId)]
                type:@"STICKER"
                 key:@"stickers"
          completion:^(NSArray *found) {
        MAXStickersModule *strongSelf = weakSelf;
        if (strongSelf == nil) {
            completion(0);
            return;
        }

        long long setId = 0;
        for (id raw in found) {
            MAXSticker *sticker = [MAXSticker stickerFromMap:raw];
            if (sticker == nil) continue;
            strongSelf->_stickersById[@(sticker.stickerId)] = sticker;
            if (sticker.stickerId == stickerId) setId = sticker.setId;
        }
        completion(setId);
    }];
}

- (void)setWithId:(long long)setId completion:(void (^)(MAXStickerSet *set))completion {
    if (setId == 0) {
        completion(nil);
        return;
    }

    MAXStickerSet *known = _setsById[@(setId)];
    if (known != nil) {
        completion(known);
        return;
    }

    __weak MAXStickersModule *weakSelf = self;
    [self fetchByIds:@[@(setId)]
                type:@"STICKER_SET"
                 key:@"stickerSets"
          completion:^(NSArray *found) {
        MAXStickersModule *strongSelf = weakSelf;
        if (strongSelf == nil) {
            completion(nil);
            return;
        }

        MAXStickerSet *made = nil;
        for (id raw in found) {
            MAXStickerSet *set = [MAXStickerSet setFromMap:raw];
            if (set == nil) continue;
            strongSelf->_setsById[@(set.setId)] = set;
            if (set.setId == setId) made = set;
        }
        completion(made);
    }];
}

#pragma mark - Свои наборы

- (void)loadFavoritesWithCompletion:(void (^)(NSError *error))completion {
    if ([MAXApi shared].state != MAXSessionStateOnline) {
        if (completion != nil) {
            completion([NSError errorWithDomain:@"ru.max.stickers"
                                           code:1
                                       userInfo:@{NSLocalizedDescriptionKey:
                                           @"Сессия не онлайн"}]);
        }
        return;
    }

    __weak MAXStickersModule *weakSelf = self;
    [self updateType:@"FAVORITE_STICKER" completion:^(NSDictionary *mine) {
        MAXStickersModule *strongSelf = weakSelf;
        if (strongSelf == nil) return;

        // Список приходит целиком, поэтому старый отбрасывается: набор мог
        // быть убран с другого устройства.
        [strongSelf->_mine removeAllObjects];
        [strongSelf readMine:mine];

        NSError *error = (mine == nil)
            ? [NSError errorWithDomain:@"ru.max.stickers"
                                  code:2
                              userInfo:@{NSLocalizedDescriptionKey:
                                  @"Сервер не ответил"}]
            : nil;

        // Среди своих мог оказаться набор, добавленный с другого устройства,
        // — о нём здесь известен только номер. Панель выбора показывает
        // наборы по их описаниям и такой просто потеряла бы, поэтому
        // недостающие описания добираем сразу же.
        NSMutableArray *unknown = [NSMutableArray array];
        for (NSNumber *identifier in strongSelf->_mine) {
            if (strongSelf->_setsById[identifier] == nil) [unknown addObject:identifier];
        }

        if (unknown.count == 0) {
            if (completion != nil) completion(error);
            return;
        }

        [strongSelf fetchByIds:unknown
                          type:@"STICKER_SET"
                           key:@"stickerSets"
                    completion:^(NSArray *found) {
            MAXStickersModule *inner = weakSelf;
            if (inner != nil) {
                for (id raw in found) {
                    MAXStickerSet *set = [MAXStickerSet setFromMap:raw];
                    if (set != nil) inner->_setsById[@(set.setId)] = set;
                }
            }
            if (completion != nil) completion(error);
        }];
    }];
}

- (BOOL)isFavorite:(long long)setId {
    return setId != 0 && [_mine containsObject:@(setId)];
}

- (void)favoriteSet:(long long)setId completion:(void (^)(BOOL ok))completion {
    if (setId == 0) {
        completion(NO);
        return;
    }

    __weak MAXStickersModule *weakSelf = self;
    [[MAXApi shared] sendRequestWithOpcode:MAXOpcodeAssetsAdd
                                   payload:@{@"type": @"FAVORITE_STICKER_SET",
                                             @"id": @(setId)}
                                    silent:YES
                                completion:^(MAXPacket *packet, NSError *error) {
        MAXStickersModule *strongSelf = weakSelf;
        BOOL ok = (error == nil && [packet.payloadMap[@"success"] boolValue]);

        if (ok && strongSelf != nil && ![strongSelf->_mine containsObject:@(setId)]) {
            [strongSelf->_mine insertObject:@(setId) atIndex:0];
        }
        completion(ok);
    }];
}

- (void)unfavoriteSet:(long long)setId completion:(void (^)(BOOL ok))completion {
    if (setId == 0) {
        completion(NO);
        return;
    }

    // Убирают списком, а добавляют по одному — так устроен сервер.
    __weak MAXStickersModule *weakSelf = self;
    [[MAXApi shared] sendRequestWithOpcode:MAXOpcodeAssetsRemove
                                   payload:@{@"type": @"FAVORITE_STICKER_SET",
                                             @"ids": @[@(setId)]}
                                    silent:YES
                                completion:^(MAXPacket *packet, NSError *error) {
        MAXStickersModule *strongSelf = weakSelf;
        BOOL ok = (error == nil && [packet.payloadMap[@"success"] boolValue]);

        if (ok && strongSelf != nil) [strongSelf->_mine removeObject:@(setId)];
        completion(ok);
    }];
}

/// Страница за страницей, потому что разом сервер длинный список не берёт.
/// Собранное отдаётся одним куском, когда кончились страницы.
- (void)fetchByIds:(NSArray *)ids
              type:(NSString *)type
               key:(NSString *)key
        completion:(void (^)(NSArray *found))completion {
    NSMutableArray *all = [NSMutableArray array];
    [self fetchPageFrom:0 ids:ids type:type key:key into:all completion:completion];
}

- (void)fetchPageFrom:(NSUInteger)at
                  ids:(NSArray *)ids
                 type:(NSString *)type
                  key:(NSString *)key
                 into:(NSMutableArray *)all
           completion:(void (^)(NSArray *found))completion {
    if (at >= ids.count) {
        completion(all);
        return;
    }

    NSUInteger length = MIN(MAXStickersPage, ids.count - at);
    NSArray *page = [ids subarrayWithRange:NSMakeRange(at, length)];

    __weak MAXStickersModule *weakSelf = self;
    [[MAXApi shared] sendRequestWithOpcode:MAXOpcodeAssetsGetByIds
                                   payload:@{@"type": type, @"ids": page}
                                    silent:YES
                                completion:^(MAXPacket *packet, NSError *error) {
        MAXStickersModule *strongSelf = weakSelf;
        if (strongSelf == nil) {
            completion(all);
            return;
        }

        if (error == nil) {
            id found = packet.payloadMap[key];
            if ([found isKindOfClass:[NSArray class]]) [all addObjectsFromArray:found];
        }

        [strongSelf fetchPageFrom:at + length
                              ids:ids
                             type:type
                              key:key
                             into:all
                       completion:completion];
    }];
}

@end
