//
//  MAXIcons.h
//  Max — иконки, нарисованные вектором в рантайме.
//
//  Контуры взяты из ресурсов Android-клиента MAX (см. tools/extract-icons.py)
//  и хранятся строками в синтаксисе путей SVG. Растр из них получается
//  на месте и под нужный размер, поэтому не нужны ни @2x/@3x, ни отдельные
//  файлы под каждый оттенок: цвет задаётся при отрисовке.
//
//  Холст не хранится: контур вписывается по своим границам
//  (CGPathGetBoundingBox), см. пояснение в генераторе.
//

#import <UIKit/UIKit.h>

/// Имя иконки -> массив строк-контуров. Определён в MAXIconData.m.
NSDictionary *MAXIconDefinitions(void);

@interface MAXIcons : NSObject

/// Квадратная картинка со стороной `size`, залитая цветом `color`.
/// Результат кэшируется: на панели вкладок и в ячейках одно и то же
/// перерисовывалось бы на каждом кадре.
+ (UIImage *)imageNamed:(NSString *)name size:(CGFloat)size color:(UIColor *)color;

/// Та же иконка, но тиснёная: заливка градиентом и белый отблеск снизу.
/// Нужна скевоморфной теме — плоский силуэт рядом с выпуклыми кнопками
/// выглядит вставленным из другого приложения.
+ (UIImage *)embossedImageNamed:(NSString *)name size:(CGFloat)size color:(UIColor *)color;

/// Непрозрачная чёрная маска — для UITabBarItem, который красит сам.
+ (UIImage *)templateImageNamed:(NSString *)name size:(CGFloat)size;

+ (BOOL)hasIconNamed:(NSString *)name;

@end
