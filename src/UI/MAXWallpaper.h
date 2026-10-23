//
//  MAXWallpaper.h
//  Фон переписки.
//
//  Порт chat_background_screen.dart и ChatWallpaperStore: набор готовых
//  оттенков плюс своя картинка из галереи. Хранится только у нас — на сервер
//  фон не уходит, и на другом устройстве он свой.
//

#import <UIKit/UIKit.h>

/// Фон сменился — открытые переписки перекрашиваются.
extern NSString *const MAXWallpaperDidChangeNotification;

@interface MAXWallpaper : NSObject

/// Готовые оттенки. 0 — «по теме», дальше по списку.
+ (NSArray *)presetColors;
+ (NSArray *)presetNames;

+ (NSInteger)presetIndex;
+ (void)setPresetIndex:(NSInteger)index;

/// Цвет фона переписки с учётом выбора: свой оттенок либо тот, что даёт тема.
+ (UIColor *)backgroundColor;

/// Своя картинка. nil — не выбрана.
+ (UIImage *)image;
+ (void)setImage:(UIImage *)image;
+ (BOOL)hasImage;

@end
