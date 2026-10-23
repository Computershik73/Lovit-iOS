//
//  MAXIcons.m
//

#import "MAXIcons.h"

#pragma mark - Разбор пути

/// Курсор по строке пути. Числа в сокращённой записи разделяются не только
/// пробелом и запятой: «1-1.414» — это два числа, а «.5.5» — тоже два.
typedef struct {
    const char *bytes;
    NSUInteger length;
    NSUInteger offset;
} MAXPathCursor;

/// Свой поиск символа в наборе вместо strchr.
///
/// В общем наборе SDK (github.com/theos/sdks) из libsystem_c.tbd потеряна
/// часть символов libc — ровно та беда, что описана в tools/patch-sdk.sh про
/// memset. strchr из этой же компании: на armv7 линковка встаёт на
/// «Undefined symbols: _strchr». Дописывать его в .tbd можно, но тогда сборка
/// начнёт требовать пропатченный SDK там, где без этого легко обойтись.
static BOOL MAXIsOneOf(char value, const char *set) {
    for (NSUInteger i = 0; set[i] != '\0'; i++) {
        if (set[i] == value) return YES;
    }
    return NO;
}

static void MAXSkipSeparators(MAXPathCursor *cursor) {
    while (cursor->offset < cursor->length) {
        char c = cursor->bytes[cursor->offset];
        if (c == ' ' || c == ',' || c == '\t' || c == '\n' || c == '\r') cursor->offset++;
        else break;
    }
}

static BOOL MAXReadNumber(MAXPathCursor *cursor, CGFloat *value) {
    MAXSkipSeparators(cursor);
    if (cursor->offset >= cursor->length) return NO;

    NSUInteger start = cursor->offset;
    char c = cursor->bytes[cursor->offset];
    if (c == '+' || c == '-') cursor->offset++;

    BOOL digits = NO;
    while (cursor->offset < cursor->length) {
        c = cursor->bytes[cursor->offset];
        if (c >= '0' && c <= '9') { digits = YES; cursor->offset++; continue; }
        if (c == '.') {
            // Вторая точка принадлежит уже следующему числу: «.5.5».
            BOOL seen = NO;
            for (NSUInteger i = start; i < cursor->offset; i++) {
                if (cursor->bytes[i] == '.') { seen = YES; break; }
            }
            if (seen) break;
            cursor->offset++;
            continue;
        }
        if ((c == 'e' || c == 'E') && digits) { cursor->offset++; continue; }
        if ((c == '-' || c == '+') && cursor->offset > start
            && (cursor->bytes[cursor->offset - 1] == 'e'
                || cursor->bytes[cursor->offset - 1] == 'E')) {
            cursor->offset++;
            continue;
        }
        break;
    }

    if (!digits) return NO;

    char buffer[64];
    NSUInteger count = MIN(cursor->offset - start, (NSUInteger)63);
    memcpy(buffer, cursor->bytes + start, count);
    buffer[count] = '\0';

    *value = (CGFloat)atof(buffer);
    return YES;
}

/// Дуга SVG задана конечной точкой, а CGPath умеет только центральную форму.
/// Пересчёт — по приложению F.6.5 спецификации SVG, дальше дуга разбивается
/// на кубические куски не длиннее 90°.
static void MAXAddArc(CGMutablePathRef path,
                      CGPoint from, CGPoint to,
                      CGFloat rx, CGFloat ry, CGFloat rotation,
                      BOOL largeArc, BOOL sweep) {
    if (rx == 0 || ry == 0) {
        CGPathAddLineToPoint(path, NULL, to.x, to.y);
        return;
    }

    rx = fabs(rx);
    ry = fabs(ry);

    CGFloat angle = rotation * (CGFloat)M_PI / 180.0;
    CGFloat cosA = cos(angle), sinA = sin(angle);

    CGFloat dx2 = (from.x - to.x) / 2.0, dy2 = (from.y - to.y) / 2.0;
    CGFloat x1 = cosA * dx2 + sinA * dy2;
    CGFloat y1 = -sinA * dx2 + cosA * dy2;

    CGFloat rxSq = rx * rx, rySq = ry * ry;
    CGFloat x1Sq = x1 * x1, y1Sq = y1 * y1;

    CGFloat radiiCheck = x1Sq / rxSq + y1Sq / rySq;
    if (radiiCheck > 1.0) {
        rx *= sqrt(radiiCheck);
        ry *= sqrt(radiiCheck);
        rxSq = rx * rx;
        rySq = ry * ry;
    }

    CGFloat numerator = rxSq * rySq - rxSq * y1Sq - rySq * x1Sq;
    if (numerator < 0) numerator = 0;
    CGFloat denominator = rxSq * y1Sq + rySq * x1Sq;
    CGFloat coefficient = denominator == 0 ? 0 : sqrt(numerator / denominator);
    if (largeArc == sweep) coefficient = -coefficient;

    CGFloat cx1 = coefficient * rx * y1 / ry;
    CGFloat cy1 = -coefficient * ry * x1 / rx;

    CGFloat cx = cosA * cx1 - sinA * cy1 + (from.x + to.x) / 2.0;
    CGFloat cy = sinA * cx1 + cosA * cy1 + (from.y + to.y) / 2.0;

    CGFloat startAngle = atan2((y1 - cy1) / ry, (x1 - cx1) / rx);
    CGFloat endAngle = atan2((-y1 - cy1) / ry, (-x1 - cx1) / rx);
    CGFloat delta = endAngle - startAngle;

    if (!sweep && delta > 0) delta -= 2 * (CGFloat)M_PI;
    else if (sweep && delta < 0) delta += 2 * (CGFloat)M_PI;

    NSInteger segments = (NSInteger)ceil(fabs(delta / (CGFloat)(M_PI_2)));
    if (segments < 1) segments = 1;

    CGFloat step = delta / segments;
    CGFloat control = 4.0 / 3.0 * tan(step / 4.0);

    CGFloat theta = startAngle;
    for (NSInteger i = 0; i < segments; i++) {
        CGFloat next = theta + step;

        CGFloat cosT = cos(theta), sinT = sin(theta);
        CGFloat cosN = cos(next), sinN = sin(next);

        CGPoint p1 = CGPointMake(rx * (cosT - control * sinT), ry * (sinT + control * cosT));
        CGPoint p2 = CGPointMake(rx * (cosN + control * sinN), ry * (sinN - control * cosN));
        CGPoint p3 = CGPointMake(rx * cosN, ry * sinN);

        CGPoint c1 = CGPointMake(cx + cosA * p1.x - sinA * p1.y,
                                 cy + sinA * p1.x + cosA * p1.y);
        CGPoint c2 = CGPointMake(cx + cosA * p2.x - sinA * p2.y,
                                 cy + sinA * p2.x + cosA * p2.y);
        CGPoint end = CGPointMake(cx + cosA * p3.x - sinA * p3.y,
                                  cy + sinA * p3.x + cosA * p3.y);

        CGPathAddCurveToPoint(path, NULL, c1.x, c1.y, c2.x, c2.y, end.x, end.y);
        theta = next;
    }
}

static CGMutablePathRef MAXCreatePathFromString(NSString *source) {
    CGMutablePathRef path = CGPathCreateMutable();

    const char *bytes = [source UTF8String];
    MAXPathCursor cursor = {bytes, strlen(bytes), 0};

    CGPoint current = CGPointZero;
    CGPoint start = CGPointZero;
    CGPoint lastControl = CGPointZero;
    char previous = 0;
    char command = 0;

    while (cursor.offset < cursor.length) {
        MAXSkipSeparators(&cursor);
        if (cursor.offset >= cursor.length) break;

        char c = cursor.bytes[cursor.offset];
        if (MAXIsOneOf(c, "MmLlHhVvCcSsQqTtAaZz")) {
            command = c;
            cursor.offset++;
        } else if (command == 0) {
            break;
        } else if (command == 'M') {
            command = 'L';   // повтор параметров после M — это линии
        } else if (command == 'm') {
            command = 'l';
        }

        BOOL relative = (command >= 'a' && command <= 'z');
        CGFloat a, b, c1x, c1y, c2x, c2y;

        switch (command) {
            case 'M': case 'm': {
                if (!MAXReadNumber(&cursor, &a) || !MAXReadNumber(&cursor, &b)) goto done;
                current = relative ? CGPointMake(current.x + a, current.y + b)
                                   : CGPointMake(a, b);
                start = current;
                CGPathMoveToPoint(path, NULL, current.x, current.y);
                break;
            }
            case 'L': case 'l': {
                if (!MAXReadNumber(&cursor, &a) || !MAXReadNumber(&cursor, &b)) goto done;
                current = relative ? CGPointMake(current.x + a, current.y + b)
                                   : CGPointMake(a, b);
                CGPathAddLineToPoint(path, NULL, current.x, current.y);
                break;
            }
            case 'H': case 'h': {
                if (!MAXReadNumber(&cursor, &a)) goto done;
                current.x = relative ? current.x + a : a;
                CGPathAddLineToPoint(path, NULL, current.x, current.y);
                break;
            }
            case 'V': case 'v': {
                if (!MAXReadNumber(&cursor, &a)) goto done;
                current.y = relative ? current.y + a : a;
                CGPathAddLineToPoint(path, NULL, current.x, current.y);
                break;
            }
            case 'C': case 'c': {
                CGFloat x1, y1, x2, y2, x, y;
                if (!MAXReadNumber(&cursor, &x1) || !MAXReadNumber(&cursor, &y1)
                    || !MAXReadNumber(&cursor, &x2) || !MAXReadNumber(&cursor, &y2)
                    || !MAXReadNumber(&cursor, &x) || !MAXReadNumber(&cursor, &y)) goto done;
                c1x = relative ? current.x + x1 : x1;
                c1y = relative ? current.y + y1 : y1;
                c2x = relative ? current.x + x2 : x2;
                c2y = relative ? current.y + y2 : y2;
                CGPoint end = relative ? CGPointMake(current.x + x, current.y + y)
                                       : CGPointMake(x, y);
                CGPathAddCurveToPoint(path, NULL, c1x, c1y, c2x, c2y, end.x, end.y);
                lastControl = CGPointMake(c2x, c2y);
                current = end;
                break;
            }
            case 'S': case 's': {
                CGFloat x2, y2, x, y;
                if (!MAXReadNumber(&cursor, &x2) || !MAXReadNumber(&cursor, &y2)
                    || !MAXReadNumber(&cursor, &x) || !MAXReadNumber(&cursor, &y)) goto done;
                BOOL smooth = MAXIsOneOf(previous, "CcSs");
                c1x = smooth ? 2 * current.x - lastControl.x : current.x;
                c1y = smooth ? 2 * current.y - lastControl.y : current.y;
                c2x = relative ? current.x + x2 : x2;
                c2y = relative ? current.y + y2 : y2;
                CGPoint end = relative ? CGPointMake(current.x + x, current.y + y)
                                       : CGPointMake(x, y);
                CGPathAddCurveToPoint(path, NULL, c1x, c1y, c2x, c2y, end.x, end.y);
                lastControl = CGPointMake(c2x, c2y);
                current = end;
                break;
            }
            case 'Q': case 'q': {
                CGFloat x1, y1, x, y;
                if (!MAXReadNumber(&cursor, &x1) || !MAXReadNumber(&cursor, &y1)
                    || !MAXReadNumber(&cursor, &x) || !MAXReadNumber(&cursor, &y)) goto done;
                c1x = relative ? current.x + x1 : x1;
                c1y = relative ? current.y + y1 : y1;
                CGPoint end = relative ? CGPointMake(current.x + x, current.y + y)
                                       : CGPointMake(x, y);
                CGPathAddQuadCurveToPoint(path, NULL, c1x, c1y, end.x, end.y);
                lastControl = CGPointMake(c1x, c1y);
                current = end;
                break;
            }
            case 'T': case 't': {
                CGFloat x, y;
                if (!MAXReadNumber(&cursor, &x) || !MAXReadNumber(&cursor, &y)) goto done;
                BOOL smooth = MAXIsOneOf(previous, "QqTt");
                c1x = smooth ? 2 * current.x - lastControl.x : current.x;
                c1y = smooth ? 2 * current.y - lastControl.y : current.y;
                CGPoint end = relative ? CGPointMake(current.x + x, current.y + y)
                                       : CGPointMake(x, y);
                CGPathAddQuadCurveToPoint(path, NULL, c1x, c1y, end.x, end.y);
                lastControl = CGPointMake(c1x, c1y);
                current = end;
                break;
            }
            case 'A': case 'a': {
                CGFloat rx, ry, rotation, largeArc, sweep, x, y;
                if (!MAXReadNumber(&cursor, &rx) || !MAXReadNumber(&cursor, &ry)
                    || !MAXReadNumber(&cursor, &rotation)
                    || !MAXReadNumber(&cursor, &largeArc) || !MAXReadNumber(&cursor, &sweep)
                    || !MAXReadNumber(&cursor, &x) || !MAXReadNumber(&cursor, &y)) goto done;
                CGPoint end = relative ? CGPointMake(current.x + x, current.y + y)
                                       : CGPointMake(x, y);
                MAXAddArc(path, current, end, rx, ry, rotation,
                          largeArc != 0, sweep != 0);
                current = end;
                break;
            }
            case 'Z': case 'z': {
                CGPathCloseSubpath(path);
                current = start;
                break;
            }
            default:
                goto done;
        }

        previous = command;
    }

done:
    return path;
}

#pragma mark - Отрисовка

@implementation MAXIcons

+ (NSCache *)cache {
    static NSCache *cache = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        cache = [[NSCache alloc] init];
        cache.countLimit = 120;
    });
    return cache;
}

+ (BOOL)hasIconNamed:(NSString *)name {
    return MAXIconDefinitions()[name] != nil;
}

/// Контур иконки, вписанный в квадрат со стороной `size`. Вызывающий
/// освобождает результат.
+ (CGPathRef)createFittedPathForName:(NSString *)name size:(CGFloat)size {
    NSArray *paths = MAXIconDefinitions()[name];
    if (paths.count == 0) return NULL;

    // Все контуры складываются в один, чтобы вписывать их общей рамкой:
    // иначе части иконки разъехались бы по разным масштабам.
    CGMutablePathRef combined = CGPathCreateMutable();
    for (NSString *source in paths) {
        CGMutablePathRef piece = MAXCreatePathFromString(source);
        CGPathAddPath(combined, NULL, piece);
        CGPathRelease(piece);
    }

    CGRect box = CGPathGetBoundingBox(combined);
    if (CGRectIsEmpty(box) || CGRectIsNull(box)) {
        CGPathRelease(combined);
        return NULL;
    }

    CGFloat scale = MIN(size / CGRectGetWidth(box), size / CGRectGetHeight(box));
    CGAffineTransform transform = CGAffineTransformMakeTranslation(
        (size - CGRectGetWidth(box) * scale) / 2.0 - CGRectGetMinX(box) * scale,
        (size - CGRectGetHeight(box) * scale) / 2.0 - CGRectGetMinY(box) * scale);
    transform = CGAffineTransformScale(transform, scale, scale);

    CGPathRef fitted = CGPathCreateCopyByTransformingPath(combined, &transform);
    CGPathRelease(combined);
    return fitted;
}

+ (UIImage *)imageNamed:(NSString *)name size:(CGFloat)size color:(UIColor *)color {
    if (name.length == 0 || size <= 0) return nil;

    const CGFloat *components = CGColorGetComponents([color CGColor]);
    NSString *key = [NSString stringWithFormat:@"%@-%d-%p", name, (int)size, components];

    UIImage *cached = [[self cache] objectForKey:key];
    if (cached != nil) return cached;

    CGPathRef fitted = [self createFittedPathForName:name size:size];
    if (fitted == NULL) return nil;

    UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), NO,
                                           [UIScreen mainScreen].scale);
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextSetFillColorWithColor(context, [(color ?: [UIColor blackColor]) CGColor]);
    CGContextAddPath(context, fitted);
    // Чётно-нечётное правило, а не ненулевое: кольца вроде шестерёнки в
    // исходнике нарисованы двумя подконтурами одного направления, и при
    // ненулевом правиле отверстие в них залилось бы.
    CGContextEOFillPath(context);

    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    CGPathRelease(fitted);

    if (image != nil) [[self cache] setObject:image forKey:key];
    return image;
}

/**
 * Тиснёная иконка эпохи iOS 6: заливка градиентом и белый отблеск снизу.
 *
 * Плоский силуэт в скевоморфной теме выдаёт себя сразу — рядом с выпуклыми
 * кнопками и панелями он выглядит вставленным из другого приложения. Объём
 * здесь дают три вещи, и все три видны на любом снимке той поры: светлый верх
 * и тёмный низ у самой фигуры, тонкая тёмная кромка по её краю и белая тень,
 * сдвинутая на точку вниз, — будто фигура выдавлена в поверхности.
 */
+ (UIImage *)embossedImageNamed:(NSString *)name size:(CGFloat)size color:(UIColor *)color {
    if (name.length == 0 || size <= 0) return nil;

    const CGFloat *components = CGColorGetComponents([color CGColor]);
    NSString *key = [NSString stringWithFormat:@"%@-%d-%p-emboss", name, (int)size, components];

    UIImage *cached = [[self cache] objectForKey:key];
    if (cached != nil) return cached;

    CGPathRef fitted = [self createFittedPathForName:name size:size - 1.0];
    if (fitted == NULL) return nil;

    CGFloat red = 0, green = 0, blue = 0, alpha = 1;
    if (![(color ?: [UIColor blackColor]) getRed:&red green:&green blue:&blue alpha:&alpha]) {
        CGFloat white = 0;
        [(color ?: [UIColor blackColor]) getWhite:&white alpha:&alpha];
        red = green = blue = white;
    }

    UIColor *light = [UIColor colorWithRed:MIN(1.0, red + 0.22)
                                     green:MIN(1.0, green + 0.22)
                                      blue:MIN(1.0, blue + 0.22)
                                     alpha:alpha];
    UIColor *dark = [UIColor colorWithRed:MAX(0.0, red - 0.16)
                                    green:MAX(0.0, green - 0.16)
                                     blue:MAX(0.0, blue - 0.16)
                                    alpha:alpha];

    UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), NO,
                                           [UIScreen mainScreen].scale);
    CGContextRef context = UIGraphicsGetCurrentContext();

    // Отблеск: та же фигура на точку ниже.
    CGContextSaveGState(context);
    CGContextTranslateCTM(context, 0.5, 1.5);
    CGContextAddPath(context, fitted);
    CGContextSetFillColorWithColor(context, [[UIColor colorWithWhite:1.0 alpha:0.75] CGColor]);
    CGContextEOFillPath(context);
    CGContextRestoreGState(context);

    // Сама фигура — градиентом сверху вниз.
    CGContextSaveGState(context);
    CGContextTranslateCTM(context, 0.5, 0.5);
    CGContextAddPath(context, fitted);
    CGContextEOClip(context);

    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    NSArray *colors = @[(id)[light CGColor], (id)[dark CGColor]];
    CGGradientRef gradient = CGGradientCreateWithColors(space, (__bridge CFArrayRef)colors, NULL);
    CGContextDrawLinearGradient(context, gradient, CGPointZero, CGPointMake(0, size), 0);
    CGGradientRelease(gradient);
    CGColorSpaceRelease(space);
    CGContextRestoreGState(context);

    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    CGPathRelease(fitted);

    if (image != nil) [[self cache] setObject:image forKey:key];
    return image;
}

+ (UIImage *)templateImageNamed:(NSString *)name size:(CGFloat)size {
    return [self imageNamed:name size:size color:[UIColor blackColor]];
}

@end
