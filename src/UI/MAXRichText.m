//
//  MAXRichText.m
//

#import "MAXRichText.h"

@implementation MAXTextRange
@end

@implementation MAXAppliedMarkup
@end

/// Знаки, которыми кончается предложение, а не адрес.
static NSString *const MAXLinkTail = @".,;:!?)»\"'";

static NSInteger MAXClamp(NSInteger value, NSInteger length) {
    if (value < 0) return 0;
    return value > length ? length : value;
}

@implementation MAXRichText

+ (NSArray *)rangesFromElements:(id)elements {
    if (![elements isKindOfClass:[NSArray class]]) return @[];

    NSMutableArray *result = [NSMutableArray array];
    for (id item in elements) {
        if (![item isKindOfClass:[NSDictionary class]]) continue;
        NSDictionary *map = item;

        id type = map[@"type"];
        if (![type isKindOfClass:[NSString class]] || [type length] == 0) continue;

        id length = map[@"length"];
        if (![length isKindOfClass:[NSNumber class]] || [length integerValue] <= 0) continue;

        MAXTextRange *range = [[MAXTextRange alloc] init];
        range.type = type;
        range.length = [length integerValue];

        id from = map[@"from"];
        range.start = [from isKindOfClass:[NSNumber class]] ? [from integerValue] : 0;

        id attributes = map[@"attributes"];
        if ([attributes isKindOfClass:[NSDictionary class]]) {
            id url = ((NSDictionary *)attributes)[@"url"];
            if ([url isKindOfClass:[NSString class]]) range.url = url;
        }

        [result addObject:range];
    }
    return result;
}

#pragma mark - Показ

/// Шрифт куска по набору признаков. Начертания складываются: жирное внутри
/// наклонного встречается, и терять одно из них незачем.
+ (UIFont *)fontForKinds:(NSSet *)kinds base:(UIFont *)base {
    BOOL bold = [kinds containsObject:@"STRONG"] || [kinds containsObject:@"HEADING"];
    BOOL italic = [kinds containsObject:@"EMPHASIZED"] || [kinds containsObject:@"QUOTE"];

    if ([kinds containsObject:@"MONOSPACED"]) {
        NSString *name = @"Courier";
        if (bold && italic) name = @"Courier-BoldOblique";
        else if (bold) name = @"Courier-Bold";
        else if (italic) name = @"Courier-Oblique";

        UIFont *mono = [UIFont fontWithName:name size:base.pointSize];
        if (mono != nil) return mono;
    }

    if (bold && italic) {
        // Пары «жирное наклонное» у системного шрифта отдельным вызовом нет —
        // берём по имени, а не выйдет, так хотя бы жирным.
        UIFont *both = [UIFont fontWithName:@"HelveticaNeue-BoldItalic" size:base.pointSize];
        if (both != nil) return both;
        return [UIFont boldSystemFontOfSize:base.pointSize];
    }
    if (bold) return [UIFont boldSystemFontOfSize:base.pointSize];
    if (italic) return [UIFont italicSystemFontOfSize:base.pointSize];
    return base;
}

+ (NSAttributedString *)attributedText:(NSString *)text
                                ranges:(NSArray *)ranges
                                  font:(UIFont *)font
                                 color:(UIColor *)color
                             linkColor:(UIColor *)linkColor {
    if (text.length == 0 || ranges.count == 0) return nil;

    NSInteger length = (NSInteger)text.length;

    // Точки реза — границы всех отрезков разом: они накладываются друг на
    // друга, и по-другому набор признаков куска не собрать.
    NSMutableIndexSet *points = [NSMutableIndexSet indexSet];
    [points addIndex:0];
    [points addIndex:(NSUInteger)length];

    BOOL any = NO;
    for (MAXTextRange *range in ranges) {
        NSInteger start = MAXClamp(range.start, length);
        NSInteger end = MAXClamp(range.start + range.length, length);
        if (end <= start) continue;
        [points addIndex:(NSUInteger)start];
        [points addIndex:(NSUInteger)end];
        any = YES;
    }
    if (!any) return nil;

    NSMutableArray *cuts = [NSMutableArray array];
    [points enumerateIndexesUsingBlock:^(NSUInteger index, BOOL *stop) {
        [cuts addObject:@(index)];
    }];

    NSMutableAttributedString *made = [[NSMutableAttributedString alloc] initWithString:text];
    [made addAttribute:NSFontAttributeName value:font range:NSMakeRange(0, text.length)];
    [made addAttribute:NSForegroundColorAttributeName
                 value:color
                 range:NSMakeRange(0, text.length)];

    for (NSUInteger i = 0; i + 1 < cuts.count; i++) {
        NSInteger start = [cuts[i] integerValue];
        NSInteger end = [cuts[i + 1] integerValue];
        if (end <= start) continue;

        NSMutableSet *kinds = [NSMutableSet set];
        for (MAXTextRange *range in ranges) {
            NSInteger rangeStart = MAXClamp(range.start, length);
            NSInteger rangeEnd = MAXClamp(range.start + range.length, length);
            if (rangeStart > start || rangeEnd < end) continue;
            [kinds addObject:range.type];
        }
        if (kinds.count == 0) continue;

        NSRange piece = NSMakeRange((NSUInteger)start, (NSUInteger)(end - start));
        [made addAttribute:NSFontAttributeName
                     value:[self fontForKinds:kinds base:font]
                     range:piece];

        if ([kinds containsObject:@"UNDERLINE"] || [kinds containsObject:@"LINK"]) {
            [made addAttribute:NSUnderlineStyleAttributeName
                         value:@(NSUnderlineStyleSingle)
                         range:piece];
        }
        // Зачёркивание — отдельный признак, а не начертание.
        if ([kinds containsObject:@"STRIKETHROUGH"]) {
            [made addAttribute:NSStrikethroughStyleAttributeName
                         value:@(NSUnderlineStyleSingle)
                         range:piece];
        }
        if ([kinds containsObject:@"LINK"] || [kinds containsObject:@"USER_MENTION"]) {
            [made addAttribute:NSForegroundColorAttributeName value:linkColor range:piece];
        }
    }

    return made;
}

+ (NSArray *)linksInText:(NSString *)text ranges:(NSArray *)ranges {
    NSMutableArray *found = [NSMutableArray array];
    NSInteger length = (NSInteger)text.length;

    for (MAXTextRange *range in ranges) {
        if (![range.type isEqualToString:@"LINK"]) continue;

        NSString *address = range.url;
        if (address.length == 0) {
            NSInteger start = MAXClamp(range.start, length);
            NSInteger end = MAXClamp(range.start + range.length, length);
            if (end <= start) continue;
            address = [text substringWithRange:NSMakeRange((NSUInteger)start,
                                                           (NSUInteger)(end - start))];
        }
        if (address.length > 0 && ![found containsObject:address]) [found addObject:address];
    }
    return found;
}

#pragma mark - Отправка

+ (NSInteger)nextLinkStartInText:(NSString *)text from:(NSInteger)from {
    NSInteger best = -1;
    NSRange rest = NSMakeRange((NSUInteger)from, text.length - (NSUInteger)from);

    for (NSString *prefix in @[@"http://", @"https://", @"www."]) {
        NSRange at = [text rangeOfString:prefix options:NSCaseInsensitiveSearch range:rest];
        if (at.location == NSNotFound) continue;

        // Внутри слова не считается: «xxxwww.» ссылкой не является.
        if (at.location > 0) {
            unichar before = [text characterAtIndex:at.location - 1];
            if (![[NSCharacterSet whitespaceAndNewlineCharacterSet] characterIsMember:before]) {
                continue;
            }
        }

        if (best < 0 || (NSInteger)at.location < best) best = (NSInteger)at.location;
    }
    return best;
}

+ (NSArray *)detectLinksInText:(NSString *)text {
    NSMutableArray *found = [NSMutableArray array];
    if (text.length == 0) return found;

    NSCharacterSet *spaces = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    NSInteger length = (NSInteger)text.length;
    NSInteger at = 0;

    while (at < length) {
        NSInteger start = [self nextLinkStartInText:text from:at];
        if (start < 0) break;

        NSInteger end = start;
        while (end < length && ![spaces characterIsMember:[text characterAtIndex:(NSUInteger)end]]) {
            end++;
        }

        // Точка или скобка в конце — это конец предложения, а не часть адреса.
        while (end > start) {
            unichar last = [text characterAtIndex:(NSUInteger)(end - 1)];
            NSString *tail = [NSString stringWithCharacters:&last length:1];
            if ([MAXLinkTail rangeOfString:tail].location == NSNotFound) break;
            end--;
        }

        if (end - start > 4) {
            NSString *address = [text substringWithRange:NSMakeRange((NSUInteger)start,
                                                                     (NSUInteger)(end - start))];
            MAXTextRange *range = [[MAXTextRange alloc] init];
            range.type = @"LINK";
            range.start = start;
            range.length = end - start;
            range.url = [address rangeOfString:@"://"].location != NSNotFound
                ? address
                : [@"https://" stringByAppendingString:address];
            [found addObject:range];
        }

        at = end > start ? end : start + 1;
    }
    return found;
}

/// Где сейчас кусок, который размечали. Сперва там же, где был, — а если
/// текст правили выше, то поиском.
+ (NSInteger)locate:(MAXAppliedMarkup *)mark inText:(NSString *)text {
    if (mark.covered.length == 0) return -1;

    if (mark.start >= 0
            && mark.start + (NSInteger)mark.covered.length <= (NSInteger)text.length) {
        NSRange where = NSMakeRange((NSUInteger)mark.start, mark.covered.length);
        if ([[text substringWithRange:where] isEqualToString:mark.covered]) return mark.start;
    }

    NSRange found = [text rangeOfString:mark.covered];
    return found.location == NSNotFound ? -1 : (NSInteger)found.location;
}

+ (NSArray *)elementsForText:(NSString *)text {
    return [self elementsForText:text applied:nil];
}

+ (NSArray *)elementsForText:(NSString *)text applied:(NSArray *)applied {
    NSMutableArray *ranges = [NSMutableArray array];

    for (MAXAppliedMarkup *mark in applied) {
        NSInteger start = [self locate:mark inText:text];
        if (start < 0) continue;

        MAXTextRange *range = [[MAXTextRange alloc] init];
        range.type = mark.type;
        range.start = start;
        range.length = (NSInteger)mark.covered.length;
        [ranges addObject:range];
    }

    [ranges addObjectsFromArray:[self detectLinksInText:text]];
    if (ranges.count == 0) return nil;

    NSMutableArray *elements = [NSMutableArray array];
    for (MAXTextRange *range in ranges) {
        NSMutableDictionary *element = [NSMutableDictionary dictionary];
        element[@"type"] = range.type;
        element[@"from"] = @(range.start);
        element[@"length"] = @(range.length);
        if (range.url.length > 0) element[@"attributes"] = @{@"url": range.url};
        [elements addObject:element];
    }
    return elements;
}

+ (NSURL *)absoluteURLFromString:(NSString *)address {
    NSString *text = [address stringByTrimmingCharactersInSet:
                      [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (text.length == 0) return nil;

    if ([text rangeOfString:@"://"].location == NSNotFound) {
        text = [@"https://" stringByAppendingString:text];
    }
    return [NSURL URLWithString:text];
}

@end
