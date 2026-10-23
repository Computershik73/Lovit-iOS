//
//  MAXSticker.m
//

#import "MAXSticker.h"

static long long MAXStickerLong(id value) {
    if ([value isKindOfClass:[NSNumber class]]) return [value longLongValue];
    if ([value isKindOfClass:[NSString class]]) return [value longLongValue];
    return 0;
}

static NSString *MAXStickerString(NSDictionary *map, NSString *key) {
    id value = map[key];
    return [value isKindOfClass:[NSString class]] ? value : nil;
}

@implementation MAXSticker

+ (instancetype)stickerFromMap:(NSDictionary *)map {
    if (![map isKindOfClass:[NSDictionary class]]) return nil;

    MAXSticker *sticker = [[MAXSticker alloc] init];
    sticker.stickerId = MAXStickerLong(map[@"id"]);
    if (sticker.stickerId == 0) return nil;

    sticker.url = MAXStickerString(map, @"url");
    sticker.setId = MAXStickerLong(map[@"setId"]);
    sticker.width = (CGFloat)MAXStickerLong(map[@"width"]);
    sticker.height = (CGFloat)MAXStickerLong(map[@"height"]);
    sticker.isAnimated = (MAXStickerString(map, @"lottieUrl").length > 0);

    id tags = map[@"tags"];
    if ([tags isKindOfClass:[NSArray class]]) {
        NSMutableArray *found = [NSMutableArray array];
        for (id tag in tags) {
            if (tag != nil && tag != [NSNull null]) [found addObject:[tag description]];
        }
        sticker.tags = found;
    }

    return sticker;
}

@end

@implementation MAXStickerSet

+ (instancetype)setFromMap:(NSDictionary *)map {
    if (![map isKindOfClass:[NSDictionary class]]) return nil;

    MAXStickerSet *set = [[MAXStickerSet alloc] init];
    set.setId = MAXStickerLong(map[@"id"]);
    if (set.setId == 0) return nil;

    set.name = MAXStickerString(map, @"name") ?: @"";
    set.iconUrl = MAXStickerString(map, @"iconUrl");

    NSMutableArray *ids = [NSMutableArray array];
    id list = map[@"stickers"];
    if ([list isKindOfClass:[NSArray class]]) {
        for (id item in list) {
            long long number = MAXStickerLong(item);
            if (number != 0) [ids addObject:@(number)];
        }
    }
    set.stickerIds = ids;

    return set;
}

@end
