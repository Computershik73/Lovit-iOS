//
//  MAXAttachment.m
//

#import "MAXAttachment.h"

static NSString *MAXStringValue(NSDictionary *map, NSString *key) {
    id value = map[key];
    return [value isKindOfClass:[NSString class]] ? value : nil;
}

static long long MAXLongValue(NSDictionary *map, NSString *key) {
    id value = map[key];
    if ([value isKindOfClass:[NSNumber class]]) return [value longLongValue];
    if ([value isKindOfClass:[NSString class]]) return [value longLongValue];
    return 0;
}

/// Есть ли в имени хоть один знак вне латиницы. Обычные имена из латиницы
/// и цифр проверять незачем — портиться в них нечему.
static BOOL MAXHasHighLetters(NSString *name) {
    for (NSUInteger i = 0; i < name.length; i++) {
        if ([name characterAtIndex:i] > 0x007F) return YES;
    }
    return NO;
}

/// Явный след порчи: знаки «латинской добавки» (À-ÿ). В настоящем имени они
/// наперечёт, у испорченного из них состоит почти всё.
static BOOL MAXLooksLatinBroken(NSString *name) {
    for (NSUInteger i = 0; i < name.length; i++) {
        unichar letter = [name characterAtIndex:i];
        if (letter >= 0x00C0 && letter <= 0x00FF) return YES;
    }
    return NO;
}

/// Похоже ли починенное на человеческое имя файла.
///
/// Нужна эта проверка вот зачем: изредка байты целого имени случайно
/// оказываются верным UTF-8 и «чинятся» в бессмыслицу. Скажем, «Цё» в
/// CP1251 — это D6 B8, а как UTF-8 те же два байта читаются как знак
/// огласовки иврита. Поэтому починку принимаем, только если вышло то, из
/// чего имена и состоят: латиница, кириллица, цифры, знаки препинания.
static BOOL MAXSaneName(NSString *name) {
    for (NSUInteger i = 0; i < name.length; i++) {
        unichar letter = [name characterAtIndex:i];

        if (letter >= 0x0020 && letter <= 0x007E) continue;      // латиница и цифры
        if (letter >= 0x0400 && letter <= 0x04FF) continue;      // кириллица
        if (letter >= 0x00C0 && letter <= 0x00FF
            && letter != 0x00D7 && letter != 0x00F7) continue;   // é, ö, ß и родня
        if (letter == 0x2116) continue;                          // №
        if (letter == 0x00AB || letter == 0x00BB) continue;      // « »
        if (letter == 0x2013 || letter == 0x2014) continue;      // тире

        return NO;
    }
    return YES;
}

/// Чинит имя, испорченное двойной перекодировкой.
///
/// Беда не наша: к нам имя приезжает строкой MessagePack и раскодируется
/// строго как UTF-8 — неверные байты дали бы пустое имя, а не мусор. Значит,
/// мусор был мусором уже на той стороне: кто-то прочитал байты UTF-8 как
/// однобайтовую кодировку и в таком виде сохранил. «Отчёт.pdf» превращается
/// в «ÐžÑ‚Ñ‡Ñ‘Ñ‚.pdf» (прочли как Latin-1) или в «РћС‚С‡С‘С‚.pdf» (прочли
/// как CP1251).
///
/// Обратный ход однозначен: записать знаки той самой однобайтовой кодировкой
/// и прочитать получившиеся байты как UTF-8. Вышло — имя было сломано именно
/// так; не вышло — оставляем как есть. Лучше показать непонятное, чем
/// испортить понятное.
///
/// Целое русское имя под починку не попадёт. В Latin-1 кириллица не
/// записывается вовсе. В CP1251 записывается, но получившиеся байты почти
/// никогда не оказываются верным UTF-8: русские буквы там лежат в C0-FF, а
/// UTF-8 после такого начала ждёт продолжения из 80-BF — то есть не буквы.
/// Плюс требование стать короче: испорченное всегда длиннее исходного, —
/// и требование к виду починенного (MAXSaneName).
///
/// Проверено перебором: из двадцати тысяч случайных русских имён починка
/// трогает одно, и то такое, которое само выглядит сломанным («8Рё25» — это
/// ровно то, во что превращается «8и25»); сорок тысяч испорченных чинятся
/// все до одного.
/// Одно и то же имя разбирается при каждой прокрутке и каждом обновлении
/// списка; в журнал о нём хватит одной строки.
static BOOL MAXFirstTimeFor(NSString *name) {
    static NSMutableSet *seen = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ seen = [NSMutableSet set]; });

    @synchronized (seen) {
        if ([seen containsObject:name]) return NO;
        [seen addObject:name];
        return YES;
    }
}

NSString *MAXRepairedFileName(NSString *name) {
    if (name.length == 0 || !MAXHasHighLetters(name)) return name;

    const NSStringEncoding guesses[] = {NSISOLatin1StringEncoding,
                                        NSWindowsCP1251StringEncoding};

    for (NSUInteger i = 0; i < sizeof(guesses) / sizeof(guesses[0]); i++) {
        NSData *bytes = [name dataUsingEncoding:guesses[i] allowLossyConversion:NO];
        if (bytes.length == 0) continue;

        NSString *fixed = [[NSString alloc] initWithData:bytes encoding:NSUTF8StringEncoding];
        if (fixed.length == 0 || fixed.length >= name.length) continue;
        if (!MAXSaneName(fixed)) continue;

        if (MAXFirstTimeFor(name)) NSLog(@"[Max/Имя] починено: «%@» -> «%@»", name, fixed);
        return fixed;
    }

    // Следы порчи есть, а починка не вышла: такое стоит увидеть в журнале
    // целиком — вдруг сломано как-то ещё.
    if (MAXLooksLatinBroken(name) && MAXFirstTimeFor(name)) {
        NSLog(@"[Max/Имя] непонятное имя «%@», байты %@", name,
              [name dataUsingEncoding:NSUTF8StringEncoding]);
    }
    return name;
}

@implementation MAXAttachment

+ (MAXAttachmentType)typeFromString:(NSString *)raw {
    NSString *type = [raw uppercaseString];
    if ([type isEqualToString:@"PHOTO"]) return MAXAttachmentTypePhoto;
    if ([type isEqualToString:@"VIDEO"]) return MAXAttachmentTypeVideo;
    if ([type isEqualToString:@"AUDIO"]) return MAXAttachmentTypeAudio;
    if ([type isEqualToString:@"FILE"]) return MAXAttachmentTypeFile;
    if ([type isEqualToString:@"STICKER"]) return MAXAttachmentTypeSticker;
    if ([type isEqualToString:@"CONTROL"]) return MAXAttachmentTypeControl;
    return MAXAttachmentTypeOther;
}

+ (instancetype)attachmentFromMap:(NSDictionary *)map {
    if (![map isKindOfClass:[NSDictionary class]]) return nil;

    MAXAttachment *attachment = [[MAXAttachment alloc] init];
    attachment.type = [self typeFromString:[map[@"_type"] description]];

    // Имена полей у разных типов разные, поэтому проверяем по очереди:
    // у фото это baseUrl, у файла — url, у стикера — иногда сразу готовый.
    attachment.previewUrl = MAXStringValue(map, @"previewUrl")
                         ?: MAXStringValue(map, @"url")
                         ?: MAXStringValue(map, @"baseUrl");
    attachment.baseUrl = MAXStringValue(map, @"baseUrl") ?: MAXStringValue(map, @"url");

    // Кадр ролика — своим полем. У кружка ни previewUrl, ни baseUrl нет
    // вовсе, и без этого он оставался чёрным кругом до самого запуска.
    // Запасным берётся то же, что и у фотографии, а не один baseUrl: у
    // ролика без `thumbnail` иначе пропал бы и тот кадр, что показывался
    // раньше.
    attachment.thumbnailUrl = MAXStringValue(map, @"thumbnail") ?: attachment.previewUrl;

    attachment.lottieUrl = MAXStringValue(map, @"lottieUrl");
    attachment.stickerId = MAXLongValue(map, @"stickerId");

    id preview = map[@"previewData"];
    if ([preview isKindOfClass:[NSData class]] && [preview length] > 0) {
        attachment.previewBytes = preview;
    }
    // У каждого типа вложения токен зовётся по-своему, и общего `token` может
    // не быть вовсе: файл присылают с `fileToken`, и без него FILE_DOWNLOAD
    // уходил с пустым токеном — скачивание молча не работало.
    attachment.token = MAXStringValue(map, @"photoToken")
                    ?: MAXStringValue(map, @"fileToken")
                    ?: MAXStringValue(map, @"videoToken")
                    ?: MAXStringValue(map, @"token");
    // Номер вложения у каждого вида свой: у файла fileId, у видео videoId,
    // у голосового audioId. Пока читался один только fileId, видео оставалось
    // без номера вовсе — а без него сервер ссылки на него не даёт.
    attachment.fileId = MAXLongValue(map, @"fileId");
    if (attachment.fileId == 0) attachment.fileId = MAXLongValue(map, @"videoId");
    if (attachment.fileId == 0) attachment.fileId = MAXLongValue(map, @"audioId");

    attachment.name = MAXRepairedFileName(MAXStringValue(map, @"name"));
    attachment.size = MAXLongValue(map, @"size");
    attachment.duration = MAXLongValue(map, @"duration");
    attachment.isVideoNote = (attachment.type == MAXAttachmentTypeVideo
                              && MAXLongValue(map, @"videoType") == 1);

    // Имя поля у графика громкости мы знаем из Komet, но сервер мог назвать
    // его и иначе — пробуем известные написания.
    id wave = map[@"wave"] ?: map[@"waveform"] ?: map[@"waves"];
    if ([wave isKindOfClass:[NSData class]]) {
        attachment.wave = wave;
    } else if ([wave isKindOfClass:[NSArray class]]) {
        // Бывает и списком чисел, а не двоичным полем.
        NSMutableData *made = [NSMutableData dataWithLength:[wave count]];
        uint8_t *bytes = made.mutableBytes;
        NSUInteger at = 0;
        for (id item in wave) {
            long long value = [item isKindOfClass:[NSNumber class]] ? [item longLongValue] : 0;
            if (value < 0) value = 0;
            if (value > 255) value = 255;
            bytes[at++] = (uint8_t)value;
        }
        attachment.wave = made;
    }
    attachment.width = (CGFloat)MAXLongValue(map, @"width");
    attachment.height = (CGFloat)MAXLongValue(map, @"height");

    return attachment;
}

+ (NSArray *)attachmentsFromMessagePayload:(NSDictionary *)payload {
    id raw = payload[@"attaches"];
    if (![raw isKindOfClass:[NSArray class]] || [raw count] == 0) return nil;

    NSMutableArray *result = [NSMutableArray array];
    for (id item in raw) {
        MAXAttachment *attachment = [self attachmentFromMap:item];
        if (attachment != nil) [result addObject:attachment];
    }
    return result.count > 0 ? result : nil;
}

- (CGFloat)displayHeightForWidth:(CGFloat)width {
    // Кружок круглый, значит и место под него квадратное. Без этого он
    // становился бы линзой, когда сервер не прислал размеров: обрезка по
    // половине ширины на невысокой плитке даёт именно её.
    if (_isVideoNote) return width;

    // Сервер не всегда присылает размеры; без них берём 4:3, а очень длинные
    // картинки подрезаем по высоте, чтобы одна не занимала весь экран.
    if (_width <= 0 || _height <= 0) return width * 0.75;

    CGFloat height = width * (_height / _width);
    CGFloat limit = width * 1.4;
    return MIN(height, limit);
}

- (NSString *)humanReadableDuration {
    long long seconds = (_duration + 500) / 1000;
    if (seconds < 0) seconds = 0;
    return [NSString stringWithFormat:@"%lld:%02lld", seconds / 60, seconds % 60];
}

/// Столбиков у сервера восемьдесят, на экране помещается меньше — берём из
/// каждого отрезка самый громкий, а не средний: усреднение съедает рисунок
/// речи.
- (NSArray *)waveBarsCount:(NSUInteger)count {
    if (_wave.length == 0 || count == 0) return @[];

    const uint8_t *bytes = _wave.bytes;
    NSUInteger length = _wave.length;

    // Сервер меряет высоту столбика в долях от 120; выше не бывает.
    static const CGFloat top = 120.0;

    NSMutableArray *bars = [NSMutableArray arrayWithCapacity:count];
    for (NSUInteger bar = 0; bar < count; bar++) {
        NSUInteger from = length * bar / count;
        NSUInteger to = length * (bar + 1) / count;
        if (to <= from) to = from + 1;

        uint8_t peak = 0;
        for (NSUInteger at = from; at < to && at < length; at++) {
            if (bytes[at] > peak) peak = bytes[at];
        }

        CGFloat value = peak / top;
        [bars addObject:@(value > 1.0 ? 1.0 : value)];
    }
    return bars;
}

- (NSString *)humanReadableSize {
    if (_size <= 0) return @"";
    if (_size < 1024) return [NSString stringWithFormat:@"%lld Б", _size];
    if (_size < 1024 * 1024) {
        return [NSString stringWithFormat:@"%.0f КБ", _size / 1024.0];
    }
    return [NSString stringWithFormat:@"%.1f МБ", _size / (1024.0 * 1024.0)];
}

@end
