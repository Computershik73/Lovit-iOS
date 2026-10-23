//
//  MAXTheme.m
//

#import "MAXTheme.h"
#import "MAXIcons.h"
#import "MAXSwitch.h"
#import "MAXAlertView.h"
#import <QuartzCore/QuartzCore.h>

NSString *const MAXThemeDidChangeNotification = @"MAXThemeDidChangeNotification";

static NSString *const MAXThemeModeKey = @"ru.max.theme";
static NSString *const MAXThemeStyleKey = @"ru.max.themeStyle";

/// Имя слоя с градиентом пузыря: по нему он находится при повторном
/// использовании ячейки, чтобы не наслаивать копии.
static NSString *const MAXThemeGradientLayerName = @"MAXThemeGradient";

@implementation MAXTheme

#pragma mark - Режим и стиль

+ (MAXThemeMode)mode {
    return (MAXThemeMode)[[NSUserDefaults standardUserDefaults] integerForKey:MAXThemeModeKey];
}

+ (void)setMode:(MAXThemeMode)mode {
    [[NSUserDefaults standardUserDefaults] setInteger:mode forKey:MAXThemeModeKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [[NSNotificationCenter defaultCenter] postNotificationName:MAXThemeDidChangeNotification
                                                        object:nil];
}

+ (MAXThemeStyle)style {
    return (MAXThemeStyle)[[NSUserDefaults standardUserDefaults] integerForKey:MAXThemeStyleKey];
}

+ (void)setStyle:(MAXThemeStyle)style {
    [[NSUserDefaults standardUserDefaults] setInteger:style forKey:MAXThemeStyleKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [[NSNotificationCenter defaultCenter] postNotificationName:MAXThemeDidChangeNotification
                                                        object:nil];
}

+ (NSString *)nameForMode:(MAXThemeMode)mode {
    switch (mode) {
        case MAXThemeModeLight: return @"Светлая";
        case MAXThemeModeDark: return @"Тёмная";
        default: return @"Системная";
    }
}

+ (NSString *)nameForStyle:(MAXThemeStyle)style {
    switch (style) {
        case MAXThemeStyleSkeuomorphic: return @"Скевоморфизм";
        case MAXThemeStyleModern: return @"Современная";
        default: return @"Как в системе";
    }
}

/**
 * Тёмная ли тема сейчас.
 *
 * «Системная» до iOS 13 означает светлую, и это не упрощение: тёмного режима
 * в тех системах нет вовсе, спрашивать не у кого. С iOS 13 ответ берётся
 * у `UITraitCollection`, но через `NSSelectorFromString` и `respondsToSelector:`
 * — заголовков SDK 9.3 для него нет, а компилировать надо им.
 */
+ (BOOL)isDark {
    MAXThemeMode mode = [self mode];
    if (mode == MAXThemeModeDark) return YES;
    if (mode == MAXThemeModeLight) return NO;

    SEL currentTraits = NSSelectorFromString(@"currentTraitCollection");
    if (![UITraitCollection respondsToSelector:currentTraits]) return NO;

    id traits = [UITraitCollection performSelector:currentTraits];
    if (![traits respondsToSelector:NSSelectorFromString(@"userInterfaceStyle")]) return NO;

    // Значение числовое, и `performSelector:` его не отдаст — тот возвращает
    // объект. Через KVC число приезжает завёрнутым в NSNumber.
    NSNumber *style = [traits valueForKey:@"userInterfaceStyle"];
    return [style integerValue] == 2;   // UIUserInterfaceStyleDark
}

/// До iOS 7: у панелей нет ни `barTintColor`, ни плоского вида по умолчанию.
/// Проверяется наличие ключа, а не номер системы, — от него же зависит,
/// каким способом вообще задавать цвет.
+ (BOOL)isLegacySystem {
    return ![UINavigationBar instancesRespondToSelector:@selector(setBarTintColor:)];
}

+ (BOOL)isSkeuomorphic {
    MAXThemeStyle style = [self style];
    if (style == MAXThemeStyleSkeuomorphic) return YES;
    if (style == MAXThemeStyleModern) return NO;
    return [self isLegacySystem];
}

/**
 * Совпадает ли выбранный стиль с тем, что система рисует сама.
 *
 * Скевоморфизм родной до iOS 7, современный — начиная с неё. Там, где стиль
 * родной, ничего перерисовывать не надо и не нужно: система делает это лучше
 * и без швов. Своя отрисовка включается только в двух неродных сочетаниях —
 * плоский вид на iOS 6 и объёмный на iOS 7, — и вот там она обязательна,
 * потому что взять его больше неоткуда.
 *
 * Правило появилось не сразу: сначала своё рисовалось всегда, и на iOS 7
 * скевоморфный градиент панели шёл полосами, а кнопка возврата оставалась
 * плоской — ровно те места, где система и без нас справлялась.
 */
+ (BOOL)isNativeStyle {
    return [self isSkeuomorphic] == [self isLegacySystem];
}

/// Нужна ли своя отрисовка вместо системной. Тёмная тема считается неродной
/// всегда: до iOS 13 системе о ней ничего не известно.
+ (BOOL)needsOwnDrawing {
    return ![self isNativeStyle] || [self isDark];
}

/// Нужен плоский вид там, где система его не умеет, — то есть современный
/// стиль до iOS 7.
+ (BOOL)needsFlatRedraw {
    return ![self isSkeuomorphic] && [self isLegacySystem];
}

#pragma mark - Цвета

/// Системный синий: #007AFF в светлой теме, #0A84FF в тёмной. Значения
/// сверены с набором Teehan+Lax по iOS 7 — там же взяты и остальные.
+ (UIColor *)accentColor {
    return [self isDark]
        ? [UIColor colorWithRed:0.039 green:0.518 blue:1.000 alpha:1.0]   // #0A84FF
        : [UIColor colorWithRed:0.000 green:0.478 blue:1.000 alpha:1.0];  // #007AFF
}

+ (UIColor *)badgeColor {
    return [self accentColor];
}

+ (UIColor *)destructiveColor {
    return [self isDark]
        ? [UIColor colorWithRed:1.000 green:0.271 blue:0.227 alpha:1.0]   // #FF453A
        : [UIColor colorWithRed:1.000 green:0.231 blue:0.188 alpha:1.0];  // #FF3B30
}

+ (UIColor *)backgroundColor {
    return [self isDark] ? [UIColor colorWithWhite:0.11 alpha:1.0] : [UIColor whiteColor];
}

+ (UIColor *)groupedBackgroundColor {
    if ([self isDark]) return [UIColor colorWithWhite:0.07 alpha:1.0];

    // У скевоморфной группировки фон заметно темнее — на нём и держались
    // «выпуклые» блоки ячеек.
    return [self isSkeuomorphic]
        ? [UIColor colorWithRed:0.780 green:0.800 blue:0.830 alpha:1.0]
        : [UIColor colorWithRed:0.937 green:0.937 blue:0.957 alpha:1.0];  // #EFEFF4
}

+ (UIColor *)fieldBackgroundColor {
    if ([self isDark]) return [UIColor colorWithWhite:0.20 alpha:1.0];

    // Скевоморфное поле — белое с рамкой, как утопленный бланк; современное —
    // серая плашка без рамки.
    return [self isSkeuomorphic]
        ? [UIColor whiteColor]
        : [UIColor colorWithRed:0.898 green:0.898 blue:0.918 alpha:1.0];  // #E5E5EA
}

+ (UIColor *)barBackgroundColor {
    if ([self isDark]) {
        return [self isSkeuomorphic]
            ? [UIColor colorWithWhite:0.17 alpha:1.0]
            : [UIColor colorWithWhite:0.14 alpha:1.0];
    }
    return [self isSkeuomorphic]
        ? [UIColor colorWithRed:0.850 green:0.870 blue:0.900 alpha:1.0]
        : [UIColor colorWithWhite:0.973 alpha:1.0];   // #F8F8F8 — панель iOS 7
}

+ (UIColor *)textColor {
    return [self isDark] ? [UIColor colorWithWhite:0.96 alpha:1.0] : [UIColor blackColor];
}

/// #8E8E93 — тот самый серый подписей из iOS 7. Он одинаково читается и на
/// белом, и на почти чёрном, поэтому по темам не разводится.
+ (UIColor *)secondaryTextColor {
    return [UIColor colorWithRed:0.557 green:0.557 blue:0.576 alpha:1.0];
}

+ (UIColor *)placeholderColor {
    return [self isDark]
        ? [UIColor colorWithWhite:0.52 alpha:1.0]
        : [UIColor colorWithRed:0.780 green:0.780 blue:0.804 alpha:1.0];  // #C7C7CD
}

+ (UIColor *)separatorColor {
    return [self isDark]
        ? [UIColor colorWithRed:0.220 green:0.220 blue:0.229 alpha:1.0]   // #38383A
        : [UIColor colorWithRed:0.784 green:0.780 blue:0.800 alpha:1.0];  // #C8C7CC
}

+ (UIColor *)outgoingBubbleColor {
    return [self isDark]
        ? [UIColor colorWithRed:0.16 green:0.30 blue:0.47 alpha:1.0]
        : [UIColor colorWithRed:0.84 green:0.92 blue:0.99 alpha:1.0];
}

+ (UIColor *)incomingBubbleColor {
    return [self isDark] ? [UIColor colorWithWhite:0.20 alpha:1.0] : [UIColor whiteColor];
}

+ (UIColor *)outgoingTextColor {
    return [self textColor];
}

+ (UIColor *)incomingTextColor {
    return [self textColor];
}

+ (UIColor *)chatBackgroundColor {
    return [self isDark]
        ? [UIColor colorWithWhite:0.09 alpha:1.0]
        : [UIColor colorWithRed:0.79 green:0.90 blue:0.97 alpha:1.0];
}

+ (UIColor *)placeholderTileColor {
    return [self isDark]
        ? [UIColor colorWithWhite:0.26 alpha:1.0]
        : [UIColor colorWithWhite:0.85 alpha:1.0];
}

/**
 * Подписи на панелях.
 *
 * Отдельно от `textColor` не для красоты. У скевоморфной панели свой фон,
 * и в светлой теме она серо-голубая, а не белая: чёрный текст на ней выглядит
 * грубо, тёмно-серый — как в системе. А в тёмной теме панель почти чёрная,
 * и подпись обязана быть светлой независимо от того, какой фон у экрана.
 */
+ (UIColor *)barTextColor {
    if ([self isDark]) return [UIColor colorWithWhite:0.94 alpha:1.0];
    return [self isSkeuomorphic]
        ? [UIColor colorWithWhite:0.20 alpha:1.0]
        : [UIColor blackColor];
}

+ (UIColor *)barTintColorForButtons {
    return [self accentColor];
}

+ (UIKeyboardAppearance)keyboardAppearance {
    return [self isDark] ? UIKeyboardAppearanceAlert : UIKeyboardAppearanceDefault;
}

#pragma mark - Рисование подложек

/// Тот же цвет, но светлее или темнее на `delta`. Нужен для градиентов:
/// держать в коде по три оттенка на каждый фон — верный способ развести их
/// при первой же правке.
+ (UIColor *)color:(UIColor *)color shiftedBy:(CGFloat)delta {
    CGFloat r = 0, g = 0, b = 0, a = 1;
    if (![color getRed:&r green:&g blue:&b alpha:&a]) {
        CGFloat white = 0;
        if ([color getWhite:&white alpha:&a]) r = g = b = white;
    }

    r = MIN(1.0, MAX(0.0, r + delta));
    g = MIN(1.0, MAX(0.0, g + delta));
    b = MIN(1.0, MAX(0.0, b + delta));
    return [UIColor colorWithRed:r green:g blue:b alpha:a];
}

/**
 * Подложка панели: вертикальный градиент с волосяной линией по краю.
 *
 * Картинкой, а не цветом, и в обеих темах. Так вид панели перестаёт зависеть
 * от системы: на iOS 6 картинка убирает глянец, которого в современной теме
 * быть не должно, а на iOS 7 — рисует градиент, которого там сама система
 * уже не делает. Один способ на обе системы вместо двух наборов ключей.
 *
 * Растягивается за середину: крайние строки остаются нетронутыми, иначе
 * линия по краю размазалась бы на альбомной панели в 32 pt.
 */
+ (UIImage *)barBackgroundImageWithColor:(UIColor *)base
                                edgeLine:(UIColor *)edge
                                atBottom:(BOOL)atBottom
                                  height:(CGFloat)height {
    CGFloat scale = [UIScreen mainScreen].scale;
    CGFloat hairline = 1.0 / scale;

    UIGraphicsBeginImageContextWithOptions(CGSizeMake(1.0, height), YES, scale);
    CGContextRef context = UIGraphicsGetCurrentContext();

    if ([self isSkeuomorphic]) {
        CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
        // Переход плавный, без излома посередине. Излом был точнее по духу,
        // но растяжение картинки под панель другой высоты (на iOS 7 она 64 pt
        // вместо 44) размазывало его в отчётливую полосу поперёк панели.
        NSArray *colors = @[(id)[[self color:base shiftedBy:0.09] CGColor],
                            (id)[[self color:base shiftedBy:0.01] CGColor],
                            (id)[[self color:base shiftedBy:-0.08] CGColor]];
        CGFloat stops[] = {0.0, 0.55, 1.0};
        CGGradientRef gradient = CGGradientCreateWithColors(space,
                                                            (__bridge CFArrayRef)colors, stops);
        CGContextDrawLinearGradient(context, gradient, CGPointZero, CGPointMake(0, height), 0);
        CGGradientRelease(gradient);
        CGColorSpaceRelease(space);
    } else {
        CGContextSetFillColorWithColor(context, [base CGColor]);
        CGContextFillRect(context, CGRectMake(0, 0, 1.0, height));
    }

    CGContextSetFillColorWithColor(context, [edge CGColor]);
    CGContextFillRect(context, CGRectMake(0, atBottom ? height - hairline : 0, 1.0, hairline));

    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();

    // Тянется только середина: крайние строки с волосяной линией остаются
    // нетронутыми, иначе линия по краю размазалась бы на панели другой высоты.
    if ([image respondsToSelector:@selector(resizableImageWithCapInsets:)]) {
        return [image resizableImageWithCapInsets:UIEdgeInsetsMake(3.0, 0, 3.0, 0)];
    }
    return [image stretchableImageWithLeftCapWidth:0 topCapHeight:3];
}

/**
 * Высота подложки панели навигации.
 *
 * С iOS 7 панель прилегает к строке состояния и занимает 64 pt вместе с ней,
 * и картинку надо давать такой же высоты. Картинку в 44 pt система кладёт
 * только в нижние 44 pt, а строку состояния заливает `barTintColor` — отсюда
 * ступенька поперёк панели на высоте 20 pt, которую ни один градиент
 * не сгладит.
 */
+ (CGFloat)navigationBarImageHeight {
    return [self isLegacySystem] ? 44.0 : 64.0;
}

/**
 * Капсула под кнопкой панели — только для скевоморфной темы.
 *
 * Высота у картинки не декоративная: кнопка панели принимает размер своей
 * подложки. Квадратик 12×12 давал кнопку в 12 pt высотой — надпись в ней
 * не помещалась и кнопка выглядела раздавленной. 30 pt — штатная высота
 * кнопки на панели в 44 pt.
 */
+ (UIImage *)barButtonBackgroundImagePressed:(BOOL)pressed {
    CGFloat radius = 5.0;
    CGFloat width = radius * 2.0 + 2.0;
    CGFloat height = 30.0;

    UIColor *base = [self barBackgroundColor];
    UIColor *top = [self color:base shiftedBy:pressed ? -0.10 : 0.06];
    UIColor *bottom = [self color:base shiftedBy:pressed ? -0.02 : -0.10];
    UIColor *border = [self color:base shiftedBy:[self isDark] ? 0.16 : -0.28];

    UIGraphicsBeginImageContextWithOptions(CGSizeMake(width, height), NO,
                                           [UIScreen mainScreen].scale);
    CGContextRef context = UIGraphicsGetCurrentContext();

    CGRect rect = CGRectInset(CGRectMake(0, 0, width, height), 0.5, 0.5);
    UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:rect cornerRadius:radius];

    CGContextSaveGState(context);
    [path addClip];

    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    NSArray *colors = @[(id)[top CGColor], (id)[bottom CGColor]];
    CGGradientRef gradient = CGGradientCreateWithColors(space, (__bridge CFArrayRef)colors, NULL);
    CGContextDrawLinearGradient(context, gradient, CGPointZero, CGPointMake(0, height), 0);
    CGGradientRelease(gradient);
    CGColorSpaceRelease(space);

    CGContextRestoreGState(context);

    [border setStroke];
    path.lineWidth = 1.0;
    [path stroke];

    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();

    UIEdgeInsets caps = UIEdgeInsetsMake(radius, radius, radius, radius);
    if ([image respondsToSelector:@selector(resizableImageWithCapInsets:)]) {
        return [image resizableImageWithCapInsets:caps];
    }
    return [image stretchableImageWithLeftCapWidth:(NSInteger)radius
                                       topCapHeight:(NSInteger)radius];
}

#pragma mark - Общее оформление

/// Атрибуты подписи: на iOS 6 свои ключи, с iOS 7 — общие с NSAttributedString.
/// Тень гасится всегда: по умолчанию система рисует подписи панели белыми
/// с тёмной тенью, в расчёте на тёмную панель. Поменять один только цвет —
/// значит получить тёмную подпись с тёмным же ореолом.
+ (NSDictionary *)barTextAttributesWithColor:(UIColor *)color {
    // nil означает «не вмешиваться»: пустой словарь снял бы с подписи и
    // системный цвет тоже, и та стала бы чёрной там, где должна быть синей.
    if (color == nil) return nil;

    if ([self isLegacySystem]) {
        return @{UITextAttributeTextColor: color,
                 UITextAttributeTextShadowColor: [UIColor clearColor],
                 UITextAttributeTextShadowOffset: [NSValue valueWithUIOffset:UIOffsetZero]};
    }

    // С iOS 7 тени у подписей панели нет по умолчанию, гасить нечего — а вот
    // NSShadow трогать нельзя: в SDK 9.3 класс числится за UIKit, на старых
    // системах живёт в Foundation, и dyld снимет процесс ещё до main.
    return @{NSForegroundColorAttributeName: color};
}

/// Цвет невыбранной вкладки. Скевоморфная панель тёмная в обеих темах —
/// такой её и рисовала iOS 6, — поэтому подпись на ней всегда светло-серая.
+ (UIColor *)tabBarItemColor {
    if ([self isSkeuomorphic]) return [UIColor colorWithWhite:0.62 alpha:1.0];
    return [self isDark] ? [UIColor colorWithWhite:0.55 alpha:1.0]
                         : [UIColor colorWithWhite:0.50 alpha:1.0];
}

/// Фон нижней панели. У скевоморфной он тёмный при любой теме: светлая панель
/// вкладок появилась только в iOS 7, и в паре с градиентом смотрелась бы
/// ряженой.
+ (UIColor *)tabBarBaseColor {
    if ([self isSkeuomorphic]) {
        return [self isDark] ? [UIColor colorWithWhite:0.09 alpha:1.0]
                             : [UIColor colorWithWhite:0.16 alpha:1.0];
    }
    return [self barBackgroundColor];
}

/**
 * Оформление, которое задаётся один раз на всё приложение.
 *
 * Ради подписей на кнопках панели навигации и вкладок. Своего цвета у них
 * нет: система рисует их белыми с тёмной тенью, считая, что панель тёмная.
 * У нас она бывает почти белой — и «Группа», «Сервер» выходили светло-серыми
 * по светлому.
 *
 * Лечится только прокси `UIAppearance`: ни у `UIBarButtonItem`, ни у
 * `UITabBarItem` нет общего места создания, по которому можно было бы
 * пройтись. Прокси действует на то, что создано после него, поэтому вызывать
 * это надо до постройки экранов — и заново при смене темы, перед пересборкой.
 *
 * Спрашивать `respondsToSelector:` у самого прокси бесполезно: это подставной
 * объект, он отвечает «нет» почти на всё и переправляет вызовы дальше сам.
 * Спрашивать надо класс — `instancesRespondToSelector:`. На этом и сорвалась
 * первая попытка починить подписи: код исправно вызывался и столь же исправно
 * выходил на первой же проверке.
 */
+ (void)applyAppearance {
    // Цвет подписи с iOS 7 берётся у `tintColor` панели — там прокси только
    // мешал бы. На iOS 6 своего цвета у кнопок нет вовсе, и задать его больше
    // нечем, поэтому там он ставится при любом стиле.
    NSDictionary *button = [self barTextAttributesWithColor:
                            [self isLegacySystem] ? [self barTintColorForButtons] : nil];
    NSDictionary *disabled = [self barTextAttributesWithColor:
                              [self isLegacySystem] ? [self placeholderColor] : nil];

    if ([UIBarButtonItem instancesRespondToSelector:@selector(setTitleTextAttributes:forState:)]) {
        id proxy = [UIBarButtonItem appearance];
        [proxy setTitleTextAttributes:button forState:UIControlStateNormal];
        [proxy setTitleTextAttributes:button forState:UIControlStateHighlighted];
        [proxy setTitleTextAttributes:disabled forState:UIControlStateDisabled];

        // Подложка кнопки. В современной теме она снимается прозрачной
        // картинкой, а не nil: nil означает «вернуть как было», то есть
        // ровно ту глянцевую капсулу iOS 6, от которой и уходим.
        if ([UIBarButtonItem instancesRespondToSelector:
                 @selector(setBackgroundImage:forState:barMetrics:)]) {
            // Родной стиль — родные подложки: nil означает «как было», и на
            // iOS 6 это готовая капсула, а на iOS 7 её отсутствие. Своё
            // рисуется только в двух неродных сочетаниях: капсула на iOS 7
            // и её снятие на iOS 6.
            BOOL skeuomorphic = [self isSkeuomorphic];
            BOOL native = [self isNativeStyle];

            UIImage *normal = native ? nil
                            : (skeuomorphic ? [self barButtonBackgroundImagePressed:NO]
                                            : [self clearStretchableImage]);
            UIImage *pressed = native ? nil
                             : (skeuomorphic ? [self barButtonBackgroundImagePressed:YES]
                                             : [self clearStretchableImage]);

            [proxy setBackgroundImage:normal
                              forState:UIControlStateNormal
                            barMetrics:UIBarMetricsDefault];
            [proxy setBackgroundImage:pressed
                              forState:UIControlStateHighlighted
                            barMetrics:UIBarMetricsDefault];

            // Кнопка возврата — случай особый, и общая подложка ей не годится:
            // у неё своя форма со стрелкой слева, и надпись система ставит
            // с оглядкой на эту стрелку. Прямоугольная капсула съедала стрелку
            // и сбивала надпись с места — «Чаты» уезжали от центра.
            //
            // В родном сочетании она системная, в неродных — своя: остроносая
            // капсула для скевоморфизма на iOS 7 и плоский шеврон для
            // современного вида на iOS 6.
            UIImage *back = nil, *backPressed = nil;
            if (!native) {
                back = skeuomorphic ? [self skeuomorphicBackImagePressed:NO] : normal;
                backPressed = skeuomorphic ? [self skeuomorphicBackImagePressed:YES] : pressed;
            }

            [proxy setBackButtonBackgroundImage:back
                                       forState:UIControlStateNormal
                                     barMetrics:UIBarMetricsDefault];
            [proxy setBackButtonBackgroundImage:backPressed
                                       forState:UIControlStateHighlighted
                                     barMetrics:UIBarMetricsDefault];

        }
    }

    // Подписи вкладок трогаются только в неродном сочетании: на iOS 6 система
    // сама рисует их светло-серыми на тёмной панели, на iOS 7 их красит
    // `tintColor`. И там, и там нам вмешиваться незачем.
    if ([UITabBarItem instancesRespondToSelector:@selector(setTitleTextAttributes:forState:)]) {
        BOOL own = [self needsOwnDrawing];
        id proxy = [UITabBarItem appearance];
        [proxy setTitleTextAttributes:(own ? [self barTextAttributesWithColor:
                                              [self tabBarItemColor]] : nil)
                              forState:UIControlStateNormal];
        [proxy setTitleTextAttributes:(own ? [self barTextAttributesWithColor:
                                              [self accentColor]] : nil)
                              forState:UIControlStateSelected];
    }
}

+ (void)applyToNavigationBar:(UINavigationBar *)navigationBar {
    navigationBar.titleTextAttributes = [self barTextAttributesWithColor:[self barTextColor]];

    if ([navigationBar respondsToSelector:@selector(setBarTintColor:)]) {
        navigationBar.barTintColor = [self barBackgroundColor];
        navigationBar.tintColor = [self barTintColorForButtons];
        navigationBar.translucent = NO;
    } else {
        // На iOS 6 tintColor красит саму панель, а не её содержимое.
        navigationBar.tintColor = [self barBackgroundColor];
    }

    if ([navigationBar respondsToSelector:@selector(setBarStyle:)]) {
        navigationBar.barStyle = [self isDark] ? UIBarStyleBlack : UIBarStyleDefault;
    }

    // Картинка фона — только там, где системного вида недостаточно. В родном
    // сочетании она снимается (nil), и панель рисуется системой: свой градиент
    // на iOS 7 шёл полосами, потому что картинку в 44 pt та растягивает на 64.
    if ([navigationBar respondsToSelector:@selector(setBackgroundImage:forBarMetrics:)]) {
        UIColor *base = [self barBackgroundColor];
        UIImage *background = [self needsOwnDrawing]
            ? [self barBackgroundImageWithColor:base
                                       edgeLine:[self color:base
                                                  shiftedBy:[self isDark] ? 0.10 : -0.22]
                                       atBottom:YES
                                         height:[self navigationBarImageHeight]]
            : nil;
        [navigationBar setBackgroundImage:background forBarMetrics:UIBarMetricsDefault];

        // На случай, если система всё же зальёт часть панели своим цветом:
        // берём верхний тон градиента, и шва тогда не видно.
        if ([navigationBar respondsToSelector:@selector(setBarTintColor:)]
                && [self needsOwnDrawing]) {
            navigationBar.barTintColor = [self color:base shiftedBy:0.09];
        }
    }
}

/**
 * Нижняя панель.
 *
 * На iOS 7 `tintColor` красит значки и подписи, а фон задаётся `barTintColor`.
 * На iOS 6 всё иначе: `barTintColor` не существует вовсе, а `tintColor` красит
 * **саму панель**, а не её содержимое. Прежний код ставил его вслепую
 * по `respondsToSelector:` — и на планшете панель заливалась синим, поверх
 * которого лежали тёмные значки почти того же тона.
 *
 * Фон в итоге всё равно задаётся картинкой — она работает в обеих системах
 * одинаково, — а версии различаются лишь тем, чем красить выделение.
 */
+ (void)applyToTabBar:(UITabBar *)tabBar {
    if ([tabBar respondsToSelector:@selector(setBarTintColor:)]) {
        tabBar.barTintColor = [self tabBarBaseColor];
        tabBar.tintColor = [self accentColor];
        tabBar.translucent = NO;
        if ([tabBar respondsToSelector:@selector(setBarStyle:)]) {
            tabBar.barStyle = [self isDark] ? UIBarStyleBlack : UIBarStyleDefault;
        }
    } else if ([tabBar respondsToSelector:@selector(setSelectedImageTintColor:)]) {
        tabBar.selectedImageTintColor = [self accentColor];
    }

    if ([tabBar respondsToSelector:@selector(setBackgroundImage:)]) {
        UIColor *base = [self tabBarBaseColor];
        tabBar.backgroundImage = [self needsOwnDrawing]
            ? [self barBackgroundImageWithColor:base
                                       edgeLine:[self color:base shiftedBy:0.14]
                                       atBottom:NO
                                         height:49.0]
            : nil;
    }

    // Подсветка выбранной вкладки: до iOS 7 это выпуклая плашка под значком.
    // Гасится она только там, где плоский вид приходится делать самим.
    if ([tabBar respondsToSelector:@selector(setSelectionIndicatorImage:)]) {
        tabBar.selectionIndicatorImage = (![self isSkeuomorphic] && [self isLegacySystem])
            ? [self clearStretchableImage]
            : nil;
    }
}

/**
 * Таблица.
 *
 * В светлой скевоморфной теме не трогается ничего, кроме разделителей.
 * Это не лень: сгруппированную таблицу на iOS 6 система рисует сама —
 * скруглённые блоки на голубовато-сером фоне, — и любой заданный нами фон
 * эту отрисовку отменяет. Именно так профиль контакта и превратился
 * в плоские прямоугольные полосы посреди скевоморфного оформления.
 */
+ (void)applyToTableView:(UITableView *)tableView {
    tableView.separatorColor = [self separatorColor];

    // Разделители в скевоморфной группировке нарисованы в самих блоках:
    // системный шёл бы поперёк блока и вылезал за его края.
    if ([self isSkeuomorphic] && ![self isLegacySystem]
            && tableView.style == UITableViewStyleGrouped) {
        tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    }

    if (![self needsOwnDrawing]) return;

    tableView.backgroundColor = tableView.style == UITableViewStyleGrouped
        ? [self groupedBackgroundColor]
        : [self backgroundColor];

    // У сгруппированной таблицы фон задаётся ещё и подложкой: на iOS 6 она
    // рисует поверх backgroundColor свою текстуру, и без этого группы
    // остаются светлыми в тёмной теме.
    tableView.backgroundView = nil;
}

+ (void)applyToCell:(UITableViewCell *)cell {
    cell.textLabel.textColor = [self textColor];
    cell.detailTextLabel.textColor = [self secondaryTextColor];

    // Фон ячейки — то самое место, где заданный цвет отменяет скруглённые
    // блоки сгруппированной таблицы. В светлой скевоморфной теме он и не
    // нужен: системный белый и есть наш.
    if ([self needsOwnDrawing]) {
        cell.backgroundColor = [self backgroundColor];
        cell.contentView.backgroundColor = [self backgroundColor];

        // Одного цвета мало. Сгруппированную таблицу до iOS 7 система рисует
        // подложкой ячейки — скруглённым блоком со светлой рамкой, — и рамка
        // остаётся видна поверх любой заливки: в тёмной теме она выглядела
        // белыми полосами между строками. Своя подложка её заменяет целиком.
        UIView *background = [[UIView alloc] init];
        background.backgroundColor = [self backgroundColor];
        cell.backgroundView = background;
    }

    // Подсветка нажатия. Системная до iOS 7 — синий градиент во всю ячейку,
    // в тёмной теме она же белёсая. Плоская заливка нужна и там, и там.
    if ([self needsOwnDrawing]) {
        UIView *selected = [[UIView alloc] init];
        selected.backgroundColor = [self isDark]
            ? [UIColor colorWithWhite:0.22 alpha:1.0]
            : [UIColor colorWithRed:0.820 green:0.820 blue:0.839 alpha:1.0];  // #D1D1D6
        cell.selectedBackgroundView = selected;
    }
}

/**
 * Заголовок и подпись секции.
 *
 * Своего цвета у них нет: система рисует заголовок тёмно-серым со светлым
 * ореолом снизу — расчёт на светлый фон группы. В тёмной теме от такой
 * надписи остаётся только ореол.
 *
 * Метка достаётся через `respondsToSelector:`, а не приведением типа:
 * на iOS 6 сюда приезжает `UITableViewHeaderFooterView`, а вот что именно
 * подставит система следующей версии — вопрос открытый, и падать из-за
 * оформления не за что.
 */
+ (void)applyToHeaderFooterView:(UIView *)view {
    if (![view respondsToSelector:@selector(textLabel)]) return;

    // Тиснёный серо-синий заголовок — родная черта iOS 6, и в скевоморфной
    // теме он на своём месте. Перекрашивать его надо только там, где фон
    // перестал быть светлым или плоским.
    if (![self needsOwnDrawing]) return;

    UILabel *label = [view valueForKey:@"textLabel"];
    label.textColor = [self secondaryTextColor];
    label.shadowColor = [UIColor clearColor];
    label.shadowOffset = CGSizeZero;

    // Подложка заголовка до iOS 7 — градиент с тиснением, и рисуется он
    // светлым: в тёмной теме планка секции оставалась светлой полосой поперёк
    // тёмного списка. Заменяется целиком — перекрасить её нечем.
    if ([view respondsToSelector:@selector(setBackgroundView:)]) {
        UIView *background = [[UIView alloc] init];
        background.backgroundColor = [self isDark]
            ? [UIColor colorWithWhite:0.17 alpha:1.0]
            : [UIColor clearColor];
        [view setValue:background forKey:@"backgroundView"];
    }

    if ([view respondsToSelector:@selector(detailTextLabel)]) {
        UILabel *detail = [view valueForKey:@"detailTextLabel"];
        detail.textColor = [self secondaryTextColor];
        detail.shadowColor = [UIColor clearColor];
    }
}

+ (UIActivityIndicatorViewStyle)activityIndicatorStyle {
    return [self isDark] ? UIActivityIndicatorViewStyleWhite
                         : UIActivityIndicatorViewStyleGray;
}

/**
 * Отступ блока группы от краёв экрана.
 *
 * Меньше, чем было у iOS 6 (там 10 pt), и это расчёт, а не приблизительность.
 * Поля внутри блока задаёт не он, а сама ячейка: она ставит текст в 15 pt
 * от своего края и с той же стороны держит значение и значок. Значит, поле
 * внутри блока равно 15 минус этот отступ — и одинаково слева и справа
 * ровно до тех пор, пока мы не трогаем ни ту, ни другую сторону.
 */
static const CGFloat MAXGroupedInset = 6.0;

/**
 * Подложка блока сгруппированной таблицы.
 *
 * Скругляются только те углы, что смотрят наружу секции: у первой строки
 * верхние, у последней нижние, у единственной — все четыре. Разделитель между
 * строками нарисован здесь же, у нижнего края: у таблицы он на это время
 * выключен, иначе шёл бы поперёк блока и за его края.
 */
+ (UIImage *)groupedBlockImageTop:(BOOL)top bottom:(BOOL)bottom pressed:(BOOL)pressed {
    CGFloat radius = 8.0;
    CGFloat topCap = top ? radius + 1.0 : 2.0;
    CGFloat bottomCap = bottom ? radius + 1.0 : 2.0;
    CGFloat width = radius * 2.0 + 2.0;
    CGFloat height = topCap + 1.0 + bottomCap;
    CGFloat hairline = 1.0 / [UIScreen mainScreen].scale;

    BOOL dark = [self isDark];
    UIColor *fill = pressed
        ? (dark ? [UIColor colorWithWhite:0.22 alpha:1.0]
                : [UIColor colorWithRed:0.820 green:0.820 blue:0.839 alpha:1.0])
        : [self backgroundColor];
    UIColor *border = dark ? [UIColor colorWithWhite:0.30 alpha:1.0]
                           : [UIColor colorWithWhite:0.65 alpha:1.0];

    UIGraphicsBeginImageContextWithOptions(CGSizeMake(width, height), NO,
                                           [UIScreen mainScreen].scale);

    UIRectCorner corners = 0;
    if (top) corners |= UIRectCornerTopLeft | UIRectCornerTopRight;
    if (bottom) corners |= UIRectCornerBottomLeft | UIRectCornerBottomRight;

    CGRect rect = CGRectMake(0.5, top ? 0.5 : -radius,
                             width - 1.0,
                             height - (top ? 0.5 : -radius) - (bottom ? 0.5 : -radius));
    UIBezierPath *path = corners
        ? [UIBezierPath bezierPathWithRoundedRect:rect
                                 byRoundingCorners:corners
                                       cornerRadii:CGSizeMake(radius, radius)]
        : [UIBezierPath bezierPathWithRect:rect];

    [fill setFill];
    [path fill];

    [border setStroke];
    path.lineWidth = 1.0;
    [path stroke];

    // Блик по верхнему краю — та самая выпуклость.
    if (top && !dark) {
        [[UIColor colorWithWhite:1.0 alpha:0.9] setStroke];
        UIBezierPath *gloss = [UIBezierPath bezierPath];
        [gloss moveToPoint:CGPointMake(radius, 1.5)];
        [gloss addLineToPoint:CGPointMake(width - radius, 1.5)];
        gloss.lineWidth = 1.0;
        [gloss stroke];
    }

    if (!bottom) {
        [[self separatorColor] setFill];
        UIRectFill(CGRectMake(1.0, height - hairline, width - 2.0, hairline));
    }

    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();

    UIEdgeInsets caps = UIEdgeInsetsMake(topCap, radius, bottomCap, radius);
    if ([image respondsToSelector:@selector(resizableImageWithCapInsets:)]) {
        return [image resizableImageWithCapInsets:caps];
    }
    return [image stretchableImageWithLeftCapWidth:(NSInteger)radius
                                       topCapHeight:(NSInteger)topCap];
}

/// Подложка, вставленная от краёв: сама она растягивается системой во всю
/// ячейку, поэтому блок кладётся внутрь неё отдельным видом с полями.
+ (UIView *)groupedBackgroundViewTop:(BOOL)top bottom:(BOOL)bottom pressed:(BOOL)pressed {
    UIView *wrapper = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320.0, 44.0)];
    wrapper.backgroundColor = [UIColor clearColor];

    UIImageView *block = [[UIImageView alloc] initWithImage:
                          [self groupedBlockImageTop:top bottom:bottom pressed:pressed]];
    block.frame = CGRectInset(wrapper.bounds, MAXGroupedInset, 0);
    block.autoresizingMask = UIViewAutoresizingFlexibleWidth
                           | UIViewAutoresizingFlexibleHeight;
    [wrapper addSubview:block];

    return wrapper;
}

+ (void)applyToCell:(UITableViewCell *)cell
          indexPath:(NSIndexPath *)indexPath
        inTableView:(UITableView *)tableView {
    [self applyToCell:cell];

    if (![self isSkeuomorphic] || [self isLegacySystem]) return;
    if (tableView.style != UITableViewStyleGrouped) return;

    NSInteger count = [tableView numberOfRowsInSection:indexPath.section];
    BOOL top = (indexPath.row == 0);
    BOOL bottom = (indexPath.row == count - 1);

    cell.backgroundColor = [UIColor clearColor];
    cell.contentView.backgroundColor = [UIColor clearColor];
    cell.backgroundView = [self groupedBackgroundViewTop:top bottom:bottom pressed:NO];

    if (cell.selectionStyle != UITableViewCellSelectionStyleNone) {
        cell.selectedBackgroundView = [self groupedBackgroundViewTop:top
                                                              bottom:bottom
                                                             pressed:YES];
    }

    // Содержимое не сдвигается. Отступ слева ячейка держит сама, а вот справа
    // сдвинуть значение и значок нечем — и всякая добавка слева тут же ломает
    // симметрию: от края блока до текста получалось 15 pt, а до значения 5.
}

+ (UIBarButtonItemStyle)barButtonStyle {
    // На iOS 7 стили слились в один, и Bordered там ничем не отличается
    // от Plain; на iOS 6 он даёт ту самую капсулу.
    return [self isSkeuomorphic] ? UIBarButtonItemStyleBordered : UIBarButtonItemStylePlain;
}

/**
 * Кнопка возврата.
 *
 * Пустое имя годится только там, где кнопка — стрелка, то есть с iOS 7.
 * До неё это капсула с надписью, и пустая надпись давала пустую капсулу:
 * из переписки, открытой из карточки контакта, и из карточки, открытой
 * из группового чата, вернуться было нечем.
 */
+ (UIBarButtonItem *)backBarButtonItem {
    NSString *title;

    if ([self isSkeuomorphic]) {
        // Капсула с надписью — и системная на iOS 6, и своя на iOS 7.
        title = @"Назад";
    } else if ([self isLegacySystem]) {
        // Современный вид на iOS 6: стрелки у кнопки там нет вовсе, и рисуется
        // она знаком прямо в надписи. Картинкой со стрелкой это делать нельзя:
        // надпись пришлось бы двигать `backButtonTitlePositionAdjustment`,
        // а он на iOS 6 сбивает собственный отступ системы — «Чаты» уезжали
        // к правому краю кнопки.
        title = @"\u2039 Назад";
    } else {
        // С iOS 7 шеврон рисует сама система.
        title = @"";
    }

    return [[UIBarButtonItem alloc] initWithTitle:title
                                            style:[self barButtonStyle]
                                           target:nil
                                           action:nil];
}

/// Прозрачная растягивающаяся картинка. Ею снимаются системные подложки:
/// `nil` для этого не годится — он означает «вернуть как было», то есть
/// как раз ту самую системную.
+ (UIImage *)clearStretchableImage {
    // 30 pt по высоте — по той же причине, что и у капсулы: кнопка панели
    // принимает размер подложки, и картинка в 1 pt делала её невидимой.
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(1.0, 30.0), NO,
                                           [UIScreen mainScreen].scale);
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();

    if ([image respondsToSelector:@selector(resizableImageWithCapInsets:)]) {
        return [image resizableImageWithCapInsets:UIEdgeInsetsZero];
    }
    return [image stretchableImageWithLeftCapWidth:0 topCapHeight:0];
}

/**
 * Остроносая подложка кнопки возврата — та самая форма, что была у iOS 6.
 *
 * Нужна только на iOS 7 и новее: там своей такой формы нет, а без неё
 * скевоморфная тема выдаёт себя первой же кнопкой — всё вокруг выпуклое,
 * а «назад» плоская.
 *
 * Растягивается узкой полоской между носом и правым скруглением, поэтому
 * ни остриё, ни углы при длинной надписи не расплываются.
 */
+ (UIImage *)skeuomorphicBackImagePressed:(BOOL)pressed {
    CGFloat height = 30.0, arrow = 10.0, radius = 5.0;
    CGFloat width = arrow + radius + 1.0 + radius + 1.0;

    UIColor *base = [self barBackgroundColor];
    UIColor *top = [self color:base shiftedBy:pressed ? -0.10 : 0.06];
    UIColor *bottom = [self color:base shiftedBy:pressed ? -0.02 : -0.10];
    UIColor *border = [self color:base shiftedBy:[self isDark] ? 0.16 : -0.28];

    UIGraphicsBeginImageContextWithOptions(CGSizeMake(width, height), NO,
                                           [UIScreen mainScreen].scale);
    CGContextRef context = UIGraphicsGetCurrentContext();

    CGFloat right = width - 0.5, topY = 0.5, bottomY = height - 0.5;
    CGFloat middle = height / 2.0;

    UIBezierPath *path = [UIBezierPath bezierPath];
    [path moveToPoint:CGPointMake(arrow, topY)];
    [path addLineToPoint:CGPointMake(right - radius, topY)];
    [path addQuadCurveToPoint:CGPointMake(right, topY + radius)
                 controlPoint:CGPointMake(right, topY)];
    [path addLineToPoint:CGPointMake(right, bottomY - radius)];
    [path addQuadCurveToPoint:CGPointMake(right - radius, bottomY)
                 controlPoint:CGPointMake(right, bottomY)];
    [path addLineToPoint:CGPointMake(arrow, bottomY)];
    [path addLineToPoint:CGPointMake(0.5, middle)];
    [path closePath];

    CGContextSaveGState(context);
    [path addClip];

    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    NSArray *colors = @[(id)[top CGColor], (id)[bottom CGColor]];
    CGGradientRef gradient = CGGradientCreateWithColors(space, (__bridge CFArrayRef)colors, NULL);
    CGContextDrawLinearGradient(context, gradient, CGPointZero, CGPointMake(0, height), 0);
    CGGradientRelease(gradient);
    CGColorSpaceRelease(space);

    CGContextRestoreGState(context);

    [border setStroke];
    path.lineWidth = 1.0;
    [path stroke];

    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();

    UIEdgeInsets caps = UIEdgeInsetsMake(0, arrow + radius, 0, radius + 1.0);
    if ([image respondsToSelector:@selector(resizableImageWithCapInsets:)]) {
        return [image resizableImageWithCapInsets:caps];
    }
    return [image stretchableImageWithLeftCapWidth:(NSInteger)(arrow + radius) topCapHeight:0];
}

+ (UIImage *)iconNamed:(NSString *)name size:(CGFloat)size color:(UIColor *)color {
    return [self isSkeuomorphic]
        ? [MAXIcons embossedImageNamed:name size:size color:color]
        : [MAXIcons imageNamed:name size:size color:color];
}

/**
 * Вкладка нижней панели.
 *
 * На iOS 6 система берёт у значка только альфу и рисует его сама: тиснение,
 * градиент, подсветка выбранного. В современной теме это ровно то, чего быть
 * не должно, а отменить перерисовку можно единственным способом —
 * `setFinishedSelectedImage:withFinishedUnselectedImage:`: «вот готовые
 * картинки, больше ничего не делай». С iOS 7 метод убран, но там он и не
 * нужен — значок красится `tintColor`.
 */
+ (UITabBarItem *)tabBarItemWithTitle:(NSString *)title
                             iconName:(NSString *)iconName
                                  tag:(NSInteger)tag {
    CGFloat size = 26.0;

    if (![self isSkeuomorphic] && [self isLegacySystem]) {
        UITabBarItem *item = [[UITabBarItem alloc] initWithTitle:title image:nil tag:tag];
        [item setFinishedSelectedImage:[MAXIcons imageNamed:iconName
                                                       size:size
                                                      color:[self accentColor]]
           withFinishedUnselectedImage:[MAXIcons imageNamed:iconName
                                                       size:size
                                                      color:[self tabBarItemColor]]];
        return item;
    }

    // Скевоморфизм на iOS 7: там панель красит значок сама, плоской заливкой
    // по альфе, и тиснения из неё не выжать. Поэтому картинки отдаются
    // готовыми, а перекраску снимает режим `AlwaysOriginal`.
    if ([self isSkeuomorphic] && ![self isLegacySystem]) {
        UIImage *normal = [[MAXIcons embossedImageNamed:iconName
                                                   size:size
                                                  color:[self tabBarItemColor]]
                           imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
        UIImage *selected = [[MAXIcons embossedImageNamed:iconName
                                                     size:size
                                                    color:[self accentColor]]
                             imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];

        UITabBarItem *item = [[UITabBarItem alloc] initWithTitle:title image:normal tag:tag];
        if ([item respondsToSelector:@selector(setSelectedImage:)]) {
            item.selectedImage = selected;
        }
        return item;
    }

    // Панель вкладок красит картинку сама, по её альфе, — поэтому сюда
    // отдаётся сплошная чёрная маска, а не готовый цветной значок.
    return [[UITabBarItem alloc] initWithTitle:title
                                          image:[MAXIcons templateImageNamed:iconName size:size]
                                            tag:tag];
}

/**
 * Стрелка «дальше».
 *
 * В современной теме — тонкий шеврон iOS 7. В скевоморфной — толще, серо-синяя
 * и с белым тиснением снизу: так её рисовала iOS 6, и своя отрисовка обязана
 * повторять выбранный стиль, а не всегда плоский.
 */
+ (UIImage *)disclosureImage {
    BOOL skeuomorphic = [self isSkeuomorphic];
    CGFloat width = skeuomorphic ? 10.0 : 8.0;
    CGFloat height = skeuomorphic ? 15.0 : 13.0;

    UIGraphicsBeginImageContextWithOptions(CGSizeMake(width, height + 1.0), NO,
                                           [UIScreen mainScreen].scale);
    CGContextRef context = UIGraphicsGetCurrentContext();

    CGContextSetLineWidth(context, skeuomorphic ? 2.5 : 2.0);
    CGContextSetLineCap(context, kCGLineCapRound);
    CGContextSetLineJoin(context, kCGLineJoinRound);

    // Тиснение рисуется первым — той же фигурой, сдвинутой на точку вниз.
    NSUInteger passes = skeuomorphic ? 2 : 1;
    for (NSUInteger pass = 0; pass < passes; pass++) {
        BOOL emboss = (skeuomorphic && pass == 0);
        CGFloat shift = emboss ? 1.0 : 0.0;

        UIColor *color = emboss
            ? [UIColor colorWithWhite:1.0 alpha:0.9]
            : (skeuomorphic ? [UIColor colorWithRed:0.53 green:0.56 blue:0.60 alpha:1.0]
                            : [self placeholderColor]);

        CGContextSetStrokeColorWithColor(context, [color CGColor]);
        CGContextMoveToPoint(context, 1.5, 1.5 + shift);
        CGContextAddLineToPoint(context, width - 1.5, height / 2.0 + shift);
        CGContextAddLineToPoint(context, 1.5, height - 1.5 + shift);
        CGContextStrokePath(context);
    }

    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

/// Галочка выбора. В современной теме берётся готовый значок, в скевоморфной
/// рисуется толще и с тем же тиснением, что и стрелка.
+ (UIImage *)checkmarkImage {
    if (![self isSkeuomorphic]) {
        return [MAXIcons imageNamed:@"check" size:18.0 color:[self accentColor]];
    }

    CGFloat size = 18.0;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size + 1.0), NO,
                                           [UIScreen mainScreen].scale);
    CGContextRef context = UIGraphicsGetCurrentContext();

    CGContextSetLineWidth(context, 2.6);
    CGContextSetLineCap(context, kCGLineCapRound);
    CGContextSetLineJoin(context, kCGLineJoinRound);

    for (NSUInteger pass = 0; pass < 2; pass++) {
        BOOL emboss = (pass == 0);
        CGFloat shift = emboss ? 1.0 : 0.0;

        CGContextSetStrokeColorWithColor(context, [(emboss
            ? [UIColor colorWithWhite:1.0 alpha:0.9]
            : [self color:[self accentColor] shiftedBy:-0.12]) CGColor]);

        CGContextMoveToPoint(context, size * 0.16, size * 0.52 + shift);
        CGContextAddLineToPoint(context, size * 0.40, size * 0.76 + shift);
        CGContextAddLineToPoint(context, size * 0.86, size * 0.22 + shift);
        CGContextStrokePath(context);
    }

    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

+ (void)setDisclosureOnCell:(UITableViewCell *)cell {
    if ([self isNativeStyle]) {
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.accessoryView = nil;
        return;
    }

    // Системная стрелка до iOS 7 нарисована объёмной, серо-голубой и заметно
    // крупнее; своя рисуется по нынешним цветам темы.
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.accessoryView = [[UIImageView alloc] initWithImage:[self disclosureImage]];
}

+ (void)setCheckmark:(BOOL)checked onCell:(UITableViewCell *)cell {
    if (!checked) {
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.accessoryView = nil;
        return;
    }

    if ([self isNativeStyle]) {
        cell.accessoryType = UITableViewCellAccessoryCheckmark;
        cell.accessoryView = nil;
        return;
    }

    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.accessoryView = [[UIImageView alloc] initWithImage:[self checkmarkImage]];
}

+ (id)switchWithValue:(BOOL)value target:(id)target action:(SEL)action {
    id toggle;

    if ([self isNativeStyle]) {
        UISwitch *system = [[UISwitch alloc] initWithFrame:CGRectZero];
        [self applyToSwitch:system];
        toggle = system;
    } else {
        toggle = [[MAXSwitch alloc] initWithFrame:CGRectZero];
    }

    [toggle setOn:value animated:NO];
    [toggle addTarget:target action:action forControlEvents:UIControlEventValueChanged];
    return toggle;
}

+ (id)alertWithTitle:(NSString *)title
             message:(NSString *)message
            delegate:(id)delegate
   cancelButtonTitle:(NSString *)cancelButtonTitle
    otherButtonTitle:(NSString *)otherButtonTitle {
    // Свой диалог плоский, и объёмным он не станет: рисовать второй его
    // вариант ради одного неродного сочетания не стоит того. Поэтому он
    // выходит только там, где системный заведомо не тот, — на iOS 6
    // с современным стилем.
    if (![self needsFlatRedraw]) {
        return [[UIAlertView alloc] initWithTitle:title
                                           message:message
                                          delegate:delegate
                                 cancelButtonTitle:cancelButtonTitle
                                 otherButtonTitles:otherButtonTitle, nil];
    }

    return [[MAXAlertView alloc] initWithTitle:title
                                        message:message
                                       delegate:delegate
                              cancelButtonTitle:cancelButtonTitle
                               otherButtonTitle:otherButtonTitle];
}

+ (void)applyToSwitch:(UISwitch *)toggle {
    // Форма переключателя системная и никакими ключами не меняется — цвет
    // включённого состояния единственное, что тут вообще можно задать.
    if ([toggle respondsToSelector:@selector(setOnTintColor:)]) {
        toggle.onTintColor = [self isSkeuomorphic]
            ? nil
            : [UIColor colorWithRed:0.298 green:0.851 blue:0.392 alpha:1.0];  // #4CD964
    }
}

#pragma mark - Пузыри

+ (void)applyBubbleStyleTo:(UIView *)view outgoing:(BOOL)outgoing {
    UIColor *base = outgoing ? [self outgoingBubbleColor] : [self incomingBubbleColor];

    CAGradientLayer *gradient = nil;
    for (CALayer *layer in view.layer.sublayers) {
        if ([layer.name isEqualToString:MAXThemeGradientLayerName]) {
            gradient = (CAGradientLayer *)layer;
            break;
        }
    }

    view.backgroundColor = base;

    if (![self isSkeuomorphic]) {
        [gradient removeFromSuperlayer];
        view.layer.cornerRadius = 16.0;
        view.layer.borderWidth = 0.0;
        view.layer.shadowOpacity = 0.0;
        return;
    }

    view.layer.cornerRadius = 13.0;
    view.layer.borderWidth = 1.0;
    view.layer.borderColor = [[self color:base shiftedBy:[self isDark] ? 0.10 : -0.18] CGColor];

    view.layer.shadowColor = [[UIColor blackColor] CGColor];
    view.layer.shadowOffset = CGSizeMake(0, 1.0);
    view.layer.shadowRadius = 1.0;
    view.layer.shadowOpacity = [self isDark] ? 0.5 : 0.18;

    // Без явного пути тень считается по содержимому слоя — отрисовкой мимо
    // экрана на каждый пузырь. На iPad 2 это видно по прокрутке, а форма
    // тени нам известна заранее.
    view.layer.shadowPath = [[UIBezierPath bezierPathWithRoundedRect:view.bounds
                                                       cornerRadius:view.layer.cornerRadius]
                             CGPath];

    if (gradient == nil) {
        gradient = [CAGradientLayer layer];
        gradient.name = MAXThemeGradientLayerName;
        [view.layer insertSublayer:gradient atIndex:0];
    }

    // Слой не тянется за видом сам — размер задаётся здесь, поэтому вызывать
    // это надо после того, как выставлен frame пузыря.
    gradient.frame = view.bounds;
    gradient.cornerRadius = view.layer.cornerRadius;
    gradient.colors = @[(id)[[self color:base shiftedBy:0.07] CGColor],
                        (id)[[self color:base shiftedBy:-0.04] CGColor]];
}

+ (UIImage *)microphoneIconOfSize:(CGFloat)size color:(UIColor *)color {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), NO, 0.0);
    CGContextRef context = UIGraphicsGetCurrentContext();

    CGContextSetFillColorWithColor(context, [color CGColor]);
    CGContextSetStrokeColorWithColor(context, [color CGColor]);

    CGFloat line = size / 12.0;
    CGContextSetLineWidth(context, line);
    CGContextSetLineCap(context, kCGLineCapRound);

    // Капсула самого микрофона.
    CGFloat capsuleWidth = size * 0.30;
    CGRect capsule = CGRectMake((size - capsuleWidth) / 2.0, size * 0.12,
                                capsuleWidth, size * 0.46);
    UIBezierPath *body = [UIBezierPath bezierPathWithRoundedRect:capsule
                                                    cornerRadius:capsuleWidth / 2.0];
    [body fill];

    // Дужка под ней и ножка.
    CGRect arc = CGRectMake(size * 0.24, size * 0.34, size * 0.52, size * 0.42);
    CGContextAddArc(context, CGRectGetMidX(arc), CGRectGetMidY(arc),
                    arc.size.width / 2.0, 0, M_PI, NO);
    CGContextStrokePath(context);

    CGContextMoveToPoint(context, size / 2.0, CGRectGetMidY(arc) + arc.size.width / 2.0);
    CGContextAddLineToPoint(context, size / 2.0, size * 0.88);
    CGContextStrokePath(context);

    UIImage *made = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return made;
}

+ (void)clearBubbleStyleOf:(UIView *)view {
    for (CALayer *layer in [view.layer.sublayers copy]) {
        if ([layer.name isEqualToString:MAXThemeGradientLayerName]) [layer removeFromSuperlayer];
    }

    view.backgroundColor = [UIColor clearColor];
    view.layer.cornerRadius = 0.0;
    view.layer.borderWidth = 0.0;
    view.layer.shadowOpacity = 0.0;
    view.layer.shadowPath = NULL;
}

#pragma mark - Кнопки и поля

+ (CGRect)contentColumnInBounds:(CGRect)bounds {
    static const CGFloat margin = 20.0;
    static const CGFloat widest = 420.0;

    CGFloat width = bounds.size.width - margin * 2.0;
    if (width > widest) width = widest;
    if (width < 100.0) width = 100.0;

    return CGRectMake((bounds.size.width - width) / 2.0, 0, width, bounds.size.height);
}

/// Подложка кнопки: градиент с рамкой в скевоморфной теме, ровная заливка
/// в современной. Растягивающейся картинкой, а не слоем, — иначе пришлось бы
/// следить за её размером при каждой перекладке.
+ (UIImage *)primaryButtonImagePressed:(BOOL)pressed {
    UIColor *accent = [self accentColor];
    CGFloat radius = [self isSkeuomorphic] ? 8.0 : 10.0;
    CGFloat size = radius * 2.0 + 2.0;

    UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), NO,
                                           [UIScreen mainScreen].scale);
    CGContextRef context = UIGraphicsGetCurrentContext();

    CGRect rect = CGRectInset(CGRectMake(0, 0, size, size), 0.5, 0.5);
    UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:rect cornerRadius:radius];

    if ([self isSkeuomorphic]) {
        CGContextSaveGState(context);
        [path addClip];

        CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
        NSArray *colors = @[(id)[[self color:accent shiftedBy:pressed ? -0.12 : 0.12] CGColor],
                            (id)[[self color:accent shiftedBy:pressed ? -0.20 : -0.10] CGColor]];
        CGGradientRef gradient = CGGradientCreateWithColors(space,
                                                            (__bridge CFArrayRef)colors, NULL);
        CGContextDrawLinearGradient(context, gradient, CGPointZero, CGPointMake(0, size), 0);
        CGGradientRelease(gradient);
        CGColorSpaceRelease(space);

        CGContextRestoreGState(context);

        [[self color:accent shiftedBy:-0.24] setStroke];
        path.lineWidth = 1.0;
        [path stroke];
    } else {
        [(pressed ? [self color:accent shiftedBy:-0.10] : accent) setFill];
        [path fill];
    }

    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();

    UIEdgeInsets caps = UIEdgeInsetsMake(radius, radius, radius, radius);
    if ([image respondsToSelector:@selector(resizableImageWithCapInsets:)]) {
        return [image resizableImageWithCapInsets:caps];
    }
    return [image stretchableImageWithLeftCapWidth:(NSInteger)radius
                                       topCapHeight:(NSInteger)radius];
}

+ (UIButton *)primaryButtonWithTitle:(NSString *)title {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.backgroundColor = [UIColor clearColor];
    button.titleLabel.font = [UIFont boldSystemFontOfSize:17.0];
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [button setTitleColor:[UIColor colorWithWhite:1.0 alpha:0.5] forState:UIControlStateDisabled];

    [button setBackgroundImage:[self primaryButtonImagePressed:NO] forState:UIControlStateNormal];
    [button setBackgroundImage:[self primaryButtonImagePressed:YES]
                       forState:UIControlStateHighlighted];

    if ([self isSkeuomorphic]) {
        // Вдавленная подпись — половина скевоморфного облика кнопки.
        button.titleLabel.shadowOffset = CGSizeMake(0, -1.0);
        [button setTitleShadowColor:[UIColor colorWithWhite:0.0 alpha:0.4]
                            forState:UIControlStateNormal];
    }

    return button;
}

/**
 * Кнопка отправки.
 *
 * В скевоморфной теме — та же капсула с градиентом, что и на экранах входа:
 * так выглядела кнопка отправки в «Сообщениях» на iOS 6. В современной —
 * просто синяя подпись: с iOS 7 кнопка это текст, и подложка у неё бывает
 * только там, где без неё непонятно, куда нажимать.
 */
+ (UIButton *)composerSendButton {
    if ([self isSkeuomorphic]) {
        UIButton *button = [self primaryButtonWithTitle:@"Отправить"];
        button.titleLabel.font = [UIFont boldSystemFontOfSize:15.0];
        return button;
    }

    UIButton *button = [self plainButtonWithTitle:@"Отправить"];
    button.titleLabel.font = [UIFont boldSystemFontOfSize:16.0];
    return button;
}

/**
 * Кнопка без подложки — синяя надпись.
 *
 * Замена `UIButtonTypeSystem`, которого на iOS 6 нет вовсе: там та же
 * константа (1) означает `UIButtonTypeRoundedRect` и рисует глянцевый белый
 * прямоугольник — не то что задумано, да ещё и белым по светлому в паре мест.
 */
+ (UIButton *)plainButtonWithTitle:(NSString *)title {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.backgroundColor = [UIColor clearColor];
    button.titleLabel.font = [UIFont systemFontOfSize:15.0];
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:[self accentColor] forState:UIControlStateNormal];
    [button setTitleColor:[self color:[self accentColor] shiftedBy:-0.2]
                  forState:UIControlStateHighlighted];
    [button setTitleColor:[self placeholderColor] forState:UIControlStateDisabled];
    return button;
}

+ (void)styleTextField:(UITextField *)textField {
    textField.borderStyle = UITextBorderStyleNone;
    textField.backgroundColor = [self fieldBackgroundColor];
    textField.font = [UIFont systemFontOfSize:17.0];
    textField.clipsToBounds = YES;
    textField.autocorrectionType = UITextAutocorrectionTypeNo;
    textField.autocapitalizationType = UITextAutocapitalizationTypeNone;

    if ([self isSkeuomorphic]) {
        // Утопленный бланк: рамка по краю и небольшое скругление.
        textField.layer.cornerRadius = 6.0;
        textField.layer.borderWidth = 1.0;
        textField.layer.borderColor =
            [[self color:[self fieldBackgroundColor]
               shiftedBy:[self isDark] ? 0.14 : -0.22] CGColor];
    } else {
        textField.layer.cornerRadius = 10.0;
        textField.layer.borderWidth = 0.0;
    }

    // Подсказка своим цветом: системная серая на тёмном фоне почти не
    // читается. `attributedPlaceholder` есть с iOS 6, но только если подсказка
    // уже задана — поэтому вызывать это надо после установки placeholder.
    //
    // И строго ДО цвета текста. На iOS 6 присвоение `attributedPlaceholder`
    // перетягивает на себя атрибуты набора: всё, что вводят, становится того
    // же цвета, что подсказка. На белом поле светло-серый набор попросту
    // невидим — именно так и пропал вводимый номер телефона.
    if (textField.placeholder.length > 0) {
        textField.attributedPlaceholder =
            [[NSAttributedString alloc] initWithString:textField.placeholder
                                            attributes:@{NSForegroundColorAttributeName:
                                                             [self placeholderColor]}];
    }

    // Цвет текста задаётся явно: по умолчанию он чёрный, и в тёмной теме
    // набранное сливалось бы с подложкой ровно в тот момент, когда его
    // и надо видеть.
    textField.textColor = [self textColor];
    textField.font = [UIFont systemFontOfSize:17.0];
    textField.keyboardAppearance = [self keyboardAppearance];

    // Строка по центру поля. Раньше это считал сам MAXTextField, отдавая
    // прямоугольник высотой в строку, — и на нулевой ширине поля тот
    // вырождался, унося набранное за пределы экрана. Штатный ключ делает
    // то же самое и не зависит от порядка раскладки.
    textField.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;

    // Отступы внутри поля даёт сам MAXTextField; подставной leftView, который
    // стоял здесь раньше, ломал вертикальное выравнивание — текст обрезался
    // верхней границей.
    textField.leftView = nil;
}

#pragma mark - Даты

+ (NSDateFormatter *)timeFormatter {
    static NSDateFormatter *formatter = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        formatter = [[NSDateFormatter alloc] init];
        formatter.dateFormat = @"HH:mm";
    });
    return formatter;
}

+ (NSDateFormatter *)dateFormatter {
    static NSDateFormatter *formatter = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        formatter = [[NSDateFormatter alloc] init];
        formatter.dateFormat = @"dd.MM.yy";
    });
    return formatter;
}

/// Разбор даты на год, месяц и день — сравнивать метки времени напрямую
/// нельзя: сутки не всегда длятся 86 400 секунд, а часовой пояс у устройства
/// свой.
static NSDateComponents *MAXDayComponents(NSDate *date) {
    NSUInteger units = NSYearCalendarUnit | NSMonthCalendarUnit | NSDayCalendarUnit;
    return [[NSCalendar currentCalendar] components:units fromDate:date];
}

+ (BOOL)isSameDayMilliseconds:(long long)first and:(long long)second {
    if (first <= 0 || second <= 0) return NO;

    NSDateComponents *a = MAXDayComponents([NSDate dateWithTimeIntervalSince1970:first / 1000.0]);
    NSDateComponents *b = MAXDayComponents([NSDate dateWithTimeIntervalSince1970:second / 1000.0]);

    return a.year == b.year && a.month == b.month && a.day == b.day;
}

+ (NSString *)daySeparatorFromMilliseconds:(long long)milliseconds {
    if (milliseconds <= 0) return nil;

    NSDate *date = [NSDate dateWithTimeIntervalSince1970:milliseconds / 1000.0];
    NSDate *now = [NSDate date];

    if ([self isSameDayMilliseconds:milliseconds
                                and:(long long)([now timeIntervalSince1970] * 1000.0)]) {
        return @"Сегодня";
    }

    NSTimeInterval yesterday = [now timeIntervalSince1970] - 86400.0;
    if ([self isSameDayMilliseconds:milliseconds and:(long long)(yesterday * 1000.0)]) {
        return @"Вчера";
    }

    static NSDateFormatter *sameYear = nil;
    static NSDateFormatter *otherYear = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        sameYear = [[NSDateFormatter alloc] init];
        sameYear.dateFormat = @"d MMMM";
        otherYear = [[NSDateFormatter alloc] init];
        otherYear.dateFormat = @"d MMMM yyyy";
    });

    BOOL thisYear = MAXDayComponents(date).year == MAXDayComponents(now).year;
    return [(thisYear ? sameYear : otherYear) stringFromDate:date];
}

+ (NSString *)shortTimeFromMilliseconds:(long long)milliseconds {
    if (milliseconds <= 0) return @"";
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:(milliseconds / 1000.0)];
    return [[self timeFormatter] stringFromDate:date];
}

+ (NSString *)relativeDateFromMilliseconds:(long long)milliseconds {
    if (milliseconds <= 0) return @"";

    NSDate *date = [NSDate dateWithTimeIntervalSince1970:(milliseconds / 1000.0)];
    NSCalendar *calendar = [NSCalendar currentCalendar];
    NSUInteger units = NSYearCalendarUnit | NSMonthCalendarUnit | NSDayCalendarUnit;

    NSDateComponents *messageParts = [calendar components:units fromDate:date];
    NSDateComponents *todayParts = [calendar components:units fromDate:[NSDate date]];

    BOOL sameDay = messageParts.year == todayParts.year
                && messageParts.month == todayParts.month
                && messageParts.day == todayParts.day;

    return sameDay ? [[self timeFormatter] stringFromDate:date]
                   : [[self dateFormatter] stringFromDate:date];
}

@end
