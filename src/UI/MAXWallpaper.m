//
//  MAXWallpaper.m
//

#import "MAXWallpaper.h"
#import "MAXTheme.h"

NSString *const MAXWallpaperDidChangeNotification = @"MAXWallpaperDidChangeNotification";

static NSString *const MAXWallpaperPresetKey = @"ru.max.wallpaper";

/// Картинка лежит в Application Support, а не в Documents: её не должно быть
/// видно в iTunes рядом с журналом и файлами, которые кладёт пользователь.
static NSString *MAXWallpaperImagePath(void) {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory,
                                                         NSUserDomainMask, YES);
    NSString *directory = [paths firstObject];
    if (directory.length == 0) return nil;

    [[NSFileManager defaultManager] createDirectoryAtPath:directory
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:NULL];
    return [directory stringByAppendingPathComponent:@"wallpaper.jpg"];
}

@implementation MAXWallpaper {
    UIImage *_cachedImage;
}

+ (instancetype)shared {
    static MAXWallpaper *instance = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        instance = [[MAXWallpaper alloc] init];
    });
    return instance;
}

+ (NSArray *)presetColors {
    return @[[NSNull null],   // «по теме» — цвет берётся у неё
             [UIColor colorWithRed:0.79 green:0.90 blue:0.97 alpha:1.0],
             [UIColor colorWithRed:0.90 green:0.93 blue:0.86 alpha:1.0],
             [UIColor colorWithRed:0.96 green:0.91 blue:0.85 alpha:1.0],
             [UIColor colorWithRed:0.93 green:0.89 blue:0.95 alpha:1.0],
             [UIColor colorWithWhite:0.93 alpha:1.0],
             [UIColor colorWithWhite:0.13 alpha:1.0]];
}

+ (NSArray *)presetNames {
    return @[@"По теме", @"Голубой", @"Оливковый", @"Песочный",
             @"Сиреневый", @"Светло-серый", @"Тёмный"];
}

+ (NSInteger)presetIndex {
    return [[NSUserDefaults standardUserDefaults] integerForKey:MAXWallpaperPresetKey];
}

+ (void)setPresetIndex:(NSInteger)index {
    [[NSUserDefaults standardUserDefaults] setInteger:index forKey:MAXWallpaperPresetKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [[NSNotificationCenter defaultCenter] postNotificationName:MAXWallpaperDidChangeNotification
                                                        object:nil];
}

+ (UIColor *)backgroundColor {
    NSInteger index = [self presetIndex];
    NSArray *colors = [self presetColors];

    if (index <= 0 || index >= (NSInteger)colors.count) return [MAXTheme chatBackgroundColor];

    id color = colors[(NSUInteger)index];
    return color == [NSNull null] ? [MAXTheme chatBackgroundColor] : color;
}

+ (UIImage *)image {
    MAXWallpaper *shared = [self shared];
    if (shared->_cachedImage != nil) return shared->_cachedImage;

    NSString *path = MAXWallpaperImagePath();
    if (path == nil) return nil;

    shared->_cachedImage = [UIImage imageWithContentsOfFile:path];
    return shared->_cachedImage;
}

+ (BOOL)hasImage {
    return [self image] != nil;
}

+ (void)setImage:(UIImage *)image {
    NSString *path = MAXWallpaperImagePath();
    if (path == nil) return;

    MAXWallpaper *shared = [self shared];
    shared->_cachedImage = image;

    if (image == nil) {
        [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
    } else {
        // JPEG, а не PNG: обои — это фотография, и разница в размере файла
        // на телефоне тех лет заметна.
        [UIImageJPEGRepresentation(image, 0.8) writeToFile:path atomically:YES];
    }

    [[NSNotificationCenter defaultCenter] postNotificationName:MAXWallpaperDidChangeNotification
                                                        object:nil];
}

@end
