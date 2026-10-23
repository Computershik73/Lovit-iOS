//
//  MAXMp4Facts.m
//

#import "MAXMp4Facts.h"

#pragma mark - Чтение частей

static uint32_t MAXRead32(const uint8_t *data, NSUInteger length, NSUInteger at) {
    if (at + 4 > length) return 0;
    return ((uint32_t)data[at] << 24) | ((uint32_t)data[at + 1] << 16)
         | ((uint32_t)data[at + 2] << 8) | data[at + 3];
}

static uint64_t MAXRead64(const uint8_t *data, NSUInteger length, NSUInteger at) {
    return ((uint64_t)MAXRead32(data, length, at) << 32) | MAXRead32(data, length, at + 4);
}

static void MAXWrite32(uint8_t *data, NSUInteger at, uint32_t value) {
    data[at] = (uint8_t)(value >> 24);
    data[at + 1] = (uint8_t)(value >> 16);
    data[at + 2] = (uint8_t)(value >> 8);
    data[at + 3] = (uint8_t)value;
}

static NSString *MAXBoxName(const uint8_t *data, NSUInteger length, NSUInteger at) {
    if (at + 4 > length) return @"????";

    unichar made[4];
    for (int i = 0; i < 4; i++) {
        unichar letter = data[at + i];
        made[i] = (letter >= ' ' && letter < 127) ? letter : '?';
    }
    return [NSString stringWithCharacters:made length:4];
}

/// Часть с таким именем среди соседей. Возвращает границы её содержимого.
static BOOL MAXInside(const uint8_t *data, NSUInteger length,
                      NSUInteger at, NSUInteger end, NSString *wanted,
                      NSUInteger *from, NSUInteger *to) {
    if (end > length) end = length;

    while (at + 8 <= end) {
        uint32_t size = MAXRead32(data, length, at);
        if (size < 8 || at + size > end) return NO;

        if ([MAXBoxName(data, length, at + 4) isEqualToString:wanted]) {
            *from = at + 8;
            *to = at + size;
            return YES;
        }
        at += size;
    }
    return NO;
}

/// Все части с таким именем на любой глубине: они вложены друг в друга, и
/// stsd лежит внутри trak/mdia/minf/stbl.
static void MAXFindBoxes(const uint8_t *data, NSUInteger length,
                         NSUInteger at, NSUInteger size, NSString *wanted,
                         NSMutableArray *found) {
    NSUInteger end = at + size;
    if (end > length) end = length;

    while (at + 8 <= end) {
        uint32_t box = MAXRead32(data, length, at);
        NSString *name = MAXBoxName(data, length, at + 4);

        if (box < 8 || at + box > end) break;

        if ([name isEqualToString:wanted]) {
            [found addObject:@(at + 8)];
        } else if ([name isEqualToString:@"trak"] || [name isEqualToString:@"mdia"]
                   || [name isEqualToString:@"minf"] || [name isEqualToString:@"stbl"]) {
            MAXFindBoxes(data, length, at + 8, box - 8, wanted, found);
        }

        at += box;
    }
}

#pragma mark - Биты описания потока

/// Чтение битами подряд. Числа в описании потока записаны не по байтам, а
/// вплотную друг к другу, и иначе до них не добраться.
typedef struct {
    const uint8_t *data;
    NSUInteger length;
    NSUInteger at;
    BOOL broken;
} MAXBits;

static uint64_t MAXBitsRead(MAXBits *bits, int count) {
    uint64_t made = 0;
    for (int step = 0; step < count; step++) {
        NSUInteger which = bits->at >> 3;
        if (which >= bits->length) {
            bits->broken = YES;
            return made;
        }
        made = (made << 1) | ((bits->data[which] >> (7 - (bits->at & 7))) & 1);
        bits->at++;
    }
    return made;
}

/// Число переменной длины: сперва нули, затем единица, затем столько же
/// значащих битов, сколько было нулей.
static uint64_t MAXBitsNumber(MAXBits *bits) {
    int zeros = 0;
    while (MAXBitsRead(bits, 1) == 0) {
        if (bits->broken) return 0;
        zeros++;
        if (zeros > 32) {
            bits->broken = YES;
            return 0;
        }
    }
    if (zeros == 0) return 0;
    return (1ULL << zeros) - 1 + MAXBitsRead(bits, zeros);
}

/// То же, но со знаком: чётные — вправо, нечётные — влево.
static int64_t MAXBitsSigned(MAXBits *bits) {
    uint64_t value = MAXBitsNumber(bits);
    return (value % 2) != 0 ? (int64_t)((value + 1) / 2) : -(int64_t)(value / 2);
}

static uint64_t MAXPeek(const uint8_t *clean, NSUInteger at, int count) {
    uint64_t made = 0;
    for (int step = 0; step < count; step++) {
        NSUInteger which = (at + step) >> 3;
        made = (made << 1) | ((clean[which] >> (7 - ((at + step) & 7))) & 1);
    }
    return made;
}

static void MAXPoke(uint8_t *clean, NSUInteger at, int count, uint64_t value) {
    for (int step = 0; step < count; step++) {
        NSUInteger which = (at + step) >> 3;
        uint8_t mask = (uint8_t)(1 << (7 - ((at + step) & 7)));

        if (((value >> (count - 1 - step)) & 1) != 0) clean[which] |= mask;
        else clean[which] &= (uint8_t)~mask;
    }
}

/// Убрать вставные байты. Их ставят там, где иначе получилось бы начало
/// новой части, и до чтения битов они только мешают.
static NSMutableData *MAXUnstuff(const uint8_t *data, NSUInteger at, NSUInteger length) {
    NSMutableData *made = [NSMutableData dataWithCapacity:length];
    int zeros = 0;

    for (NSUInteger step = 0; step < length; step++) {
        uint8_t value = data[at + step];

        if (zeros == 2 && value == 3) {
            zeros = 0;
            continue;
        }

        [made appendBytes:&value length:1];
        zeros = (value == 0) ? zeros + 1 : 0;
    }
    return made;
}

/// Поставить их обратно.
static NSMutableData *MAXStuff(NSData *source) {
    const uint8_t *data = source.bytes;
    NSMutableData *made = [NSMutableData dataWithCapacity:source.length + 8];
    int zeros = 0;

    for (NSUInteger at = 0; at < source.length; at++) {
        uint8_t value = data[at];

        if (zeros >= 2 && value <= 3) {
            uint8_t three = 3;
            [made appendBytes:&three length:1];
            zeros = 0;
        }

        [made appendBytes:&value length:1];
        zeros = (value == 0) ? zeros + 1 : 0;
    }
    return made;
}

/// Где в описании последовательности лежат форма точки и диапазон яркости.
///
/// Оба записаны битами вплотную, и до них приходится прочесть всё, что лежит
/// впереди, — за один проход находим сразу оба. Место, которого в описании
/// нет, отдаётся как −1: необъявленную форму и необъявленный диапазон и так
/// считают обычными.
///
/// Форма точки бывает записана двояко: номером из готового списка (`aspect`)
/// или, когда в списке такой нет, парой чисел следом за ним (`spelt`).
/// Второе — не редкость: отношения вроде 3:4 в списке отсутствуют.
static BOOL MAXSpsPlaces(NSData *clean, NSInteger *aspect, NSInteger *spelt, NSInteger *range) {
    *aspect = -1;
    *spelt = -1;
    *range = -1;

    MAXBits bits = { clean.bytes, clean.length, 0, NO };

    uint64_t profile = MAXBitsRead(&bits, 8);
    MAXBitsRead(&bits, 8);                      // ограничения
    MAXBitsRead(&bits, 8);                      // уровень
    MAXBitsNumber(&bits);                       // номер набора

    if (profile == 100 || profile == 110 || profile == 122 || profile == 244
            || profile == 44 || profile == 83 || profile == 86 || profile == 118
            || profile == 128 || profile == 138 || profile == 139 || profile == 134) {
        if (MAXBitsNumber(&bits) == 3) MAXBitsRead(&bits, 1);

        MAXBitsNumber(&bits);
        MAXBitsNumber(&bits);
        MAXBitsRead(&bits, 1);

        // Свои таблицы весов разбирать не станем: кодировщики телефона их не
        // пишут, а разбор вышел бы вдвое длиннее всего остального.
        if (MAXBitsRead(&bits, 1) != 0) return NO;
    }

    MAXBitsNumber(&bits);                       // разрядность счётчика кадров
    uint64_t order = MAXBitsNumber(&bits);

    if (order == 0) {
        MAXBitsNumber(&bits);
    } else if (order == 1) {
        MAXBitsRead(&bits, 1);
        MAXBitsSigned(&bits);
        MAXBitsSigned(&bits);

        uint64_t count = MAXBitsNumber(&bits);
        for (uint64_t step = 0; step < count && !bits.broken; step++) MAXBitsSigned(&bits);
    }

    MAXBitsNumber(&bits);                       // сколько кадров помнить
    MAXBitsRead(&bits, 1);
    MAXBitsNumber(&bits);                       // ширина в макроблоках
    MAXBitsNumber(&bits);                       // высота

    if (MAXBitsRead(&bits, 1) == 0) MAXBitsRead(&bits, 1);
    MAXBitsRead(&bits, 1);

    if (MAXBitsRead(&bits, 1) != 0) {           // обрезка по краям
        MAXBitsNumber(&bits);
        MAXBitsNumber(&bits);
        MAXBitsNumber(&bits);
        MAXBitsNumber(&bits);
    }

    if (bits.broken) return NO;
    if (MAXBitsRead(&bits, 1) == 0) return NO;  // дополнительного описания нет

    if (MAXBitsRead(&bits, 1) != 0) {           // форма точки объявлена
        *aspect = (NSInteger)bits.at;

        if (MAXBitsRead(&bits, 8) == 255) {
            *spelt = (NSInteger)bits.at;
            MAXBitsRead(&bits, 16);
            MAXBitsRead(&bits, 16);
        }
    }

    if (MAXBitsRead(&bits, 1) != 0) MAXBitsRead(&bits, 1);   // выход за края
    if (bits.broken) return NO;
    if (MAXBitsRead(&bits, 1) == 0) return YES;              // вид сигнала не объявлен

    MAXBitsRead(&bits, 3);                      // сам вид
    if (bits.broken) return NO;

    *range = (NSInteger)bits.at;                // следующий бит и есть диапазон
    return YES;
}

/// Погасить полный диапазон и объявить квадратную точку в одном описании
/// последовательности.
///
/// Если от правки длина изменилась, всё остаётся как было: за длиной следят
/// ещё и размеры всех частей вокруг, и менять их ради одного бита не стоит.
static void MAXFixSps(uint8_t *moov, NSUInteger at, NSUInteger length) {
    if (length < 2) return;

    NSMutableData *clean = MAXUnstuff(moov, at + 1, length - 1);

    NSInteger aspect = -1;
    NSInteger spelt = -1;
    NSInteger range = -1;

    if (!MAXSpsPlaces(clean, &aspect, &spelt, &range)) return;

    uint8_t *bytes = clean.mutableBytes;
    BOOL changed = NO;

    // Форма точки. Записана либо номером из готового списка, либо, когда в
    // списке такой нет, двумя числами следом — и квадратной делается в обоих
    // случаях одинаково просто, ни на байт не меняя длины.
    if (spelt >= 0) {
        if (MAXPeek(bytes, spelt, 16) != 1 || MAXPeek(bytes, spelt + 16, 16) != 1) {
            MAXPoke(bytes, spelt, 16, 1);
            MAXPoke(bytes, spelt + 16, 16, 1);
            changed = YES;
        }
    } else if (aspect >= 0 && MAXPeek(bytes, aspect, 8) != 1) {
        MAXPoke(bytes, aspect, 8, 1);
        changed = YES;
    }

    if (range >= 0 && MAXPeek(bytes, range, 1) != 0) {
        MAXPoke(bytes, range, 1, 0);
        changed = YES;
    }

    if (!changed) return;

    NSData *made = MAXStuff(clean);
    if (made.length != length - 1) {
        NSLog(@"[Max/Кружок] описание оставлено как было — длина не сходится");
        return;
    }

    memcpy(moov + at + 1, made.bytes, made.length);
    NSLog(@"[Max/Кружок] в описании потока объявлены квадратная точка и обычный диапазон");
}

/// Пройти по описаниям потока внутри avcC и поправить каждое.
///
/// Их там может лежать несколько: сперва по счётчику идут описания
/// последовательности, за ними описания кадра — вторые нам не нужны.
static void MAXWidenAvcC(uint8_t *moov, NSUInteger length, NSUInteger at, NSUInteger end) {
    if (at + 6 > end) return;

    int many = moov[at + 5] & 0x1F;
    NSUInteger cursor = at + 6;

    for (int which = 0; which < many; which++) {
        if (cursor + 2 > end) return;

        NSUInteger size = ((NSUInteger)moov[cursor] << 8) | moov[cursor + 1];
        cursor += 2;

        if (size < 2 || cursor + size > end) return;

        MAXFixSps(moov, cursor, size);
        cursor += size;
    }
}

/// Объявить обычный диапазон яркости вместо полного и снять вытянутую точку.
static void MAXLimitMoov(NSMutableData *moov) {
    uint8_t *data = moov.mutableBytes;
    NSUInteger length = moov.length;
    if (length < 8) return;

    NSMutableArray *tables = [NSMutableArray array];
    MAXFindBoxes(data, length, 8, length - 8, @"stsd", tables);

    for (NSNumber *place in tables) {
        NSUInteger entry = [place unsignedIntegerValue] + 8;
        if (entry + 16 > length) continue;

        uint32_t size = MAXRead32(data, length, entry);
        if (size < 16 || entry + size > length) continue;

        NSString *kind = MAXBoxName(data, length, entry + 4);
        if (![kind isEqualToString:@"avc1"] && ![kind isEqualToString:@"avc3"]) continue;

        NSUInteger from = 0;
        NSUInteger to = 0;

        if (MAXInside(data, length, entry + 86, entry + size, @"avcC", &from, &to)) {
            MAXWidenAvcC(data, length, from, to);
        }

        // Форма точки, объявленная отдельной частью. Сервер её не читает, но
        // и врать в ней незачем.
        if (MAXInside(data, length, entry + 86, entry + size, @"pasp", &from, &to)
                && from + 8 <= to
                && (MAXRead32(data, length, from) != 1
                    || MAXRead32(data, length, from + 4) != 1)) {
            MAXWrite32(data, from, 1);
            MAXWrite32(data, from + 4, 1);
            NSLog(@"[Max/Кружок] вытянутая точка в pasp снята");
        }
    }
}

/// Сдвинуть все расстояния до кусков. Лежат они в частях stco и co64 — той же
/// таблицей, только числа в первой по четыре байта, а во второй по восемь.
static void MAXShiftOffsets(NSMutableData *moov, int64_t delta) {
    uint8_t *data = moov.mutableBytes;
    NSUInteger length = moov.length;
    if (length < 8) return;

    NSMutableArray *tables = [NSMutableArray array];
    MAXFindBoxes(data, length, 8, length - 8, @"stco", tables);

    for (NSNumber *place in tables) {
        NSUInteger table = [place unsignedIntegerValue];
        uint32_t count = MAXRead32(data, length, table + 4);

        for (uint32_t entry = 0; entry < count; entry++) {
            NSUInteger where = table + 8 + (NSUInteger)entry * 4;
            if (where + 4 > length) break;
            MAXWrite32(data, where, (uint32_t)(MAXRead32(data, length, where) + delta));
        }
    }

    tables = [NSMutableArray array];
    MAXFindBoxes(data, length, 8, length - 8, @"co64", tables);

    for (NSNumber *place in tables) {
        NSUInteger table = [place unsignedIntegerValue];
        uint32_t count = MAXRead32(data, length, table + 4);

        for (uint32_t entry = 0; entry < count; entry++) {
            NSUInteger where = table + 8 + (NSUInteger)entry * 8;
            if (where + 8 > length) break;

            uint64_t moved = MAXRead64(data, length, where) + delta;
            MAXWrite32(data, where, (uint32_t)(moved >> 32));
            MAXWrite32(data, where + 4, (uint32_t)(moved & 0xFFFFFFFF));
        }
    }
}

/// Объявление вида файла — своё, вместо написанного телефоном.
///
/// iOS пишет здесь «mp42» или «qt  ». Всё же, что ходит через сервер MAX — и
/// кружок, который он присылает обратно, — объявлено «isom» с набором,
/// обычным для телефонной записи. По этому слову ролик начинают разбирать
/// раньше, чем доберутся до дорожек, и спорить тут не о чем.
static NSData *MAXBrandBox(void) {
    NSMutableData *made = [NSMutableData dataWithLength:32];
    uint8_t *bytes = made.mutableBytes;

    MAXWrite32(bytes, 0, 32);
    memcpy(bytes + 4, "ftyp", 4);
    memcpy(bytes + 8, "isom", 4);
    MAXWrite32(bytes, 12, 512);
    memcpy(bytes + 16, "isom", 4);
    memcpy(bytes + 20, "iso2", 4);
    memcpy(bytes + 24, "avc1", 4);
    memcpy(bytes + 28, "mp41", 4);

    return made;
}

#pragma mark -

@implementation MAXMp4Facts

/// Разложить файл на части верхнего уровня. NO, если он не разбирается.
+ (BOOL)scan:(NSData *)mp4
      starts:(NSMutableArray *)starts
     lengths:(NSMutableArray *)lengths
       names:(NSMutableArray *)names {
    const uint8_t *data = mp4.bytes;
    NSUInteger length = mp4.length;
    NSUInteger at = 0;

    while (at + 8 <= length) {
        uint64_t size = MAXRead32(data, length, at);
        NSString *name = MAXBoxName(data, length, at + 4);

        if (size == 1 && at + 16 <= length) size = MAXRead64(data, length, at + 8);
        else if (size == 0) size = length - at;

        if (size < 8 || at + size > length) return NO;

        [starts addObject:@(at)];
        [lengths addObject:@(size)];
        [names addObject:name];

        at += (NSUInteger)size;
    }
    return starts.count > 0;
}

+ (BOOL)ready:(NSData *)mp4 {
    if (mp4.length < 16) return NO;

    NSMutableArray *starts = [NSMutableArray array];
    NSMutableArray *lengths = [NSMutableArray array];
    NSMutableArray *names = [NSMutableArray array];

    if (![self scan:mp4 starts:starts lengths:lengths names:names]) return NO;

    return [names containsObject:@"moov"] && [names containsObject:@"mdat"];
}

+ (NSString *)describe:(NSData *)mp4 {
    if (mp4.length < 16) return @"пусто";

    NSMutableArray *starts = [NSMutableArray array];
    NSMutableArray *lengths = [NSMutableArray array];
    NSMutableArray *names = [NSMutableArray array];

    if (![self scan:mp4 starts:starts lengths:lengths names:names]) {
        return [NSString stringWithFormat:@"%lu Б, части не разбираются",
                (unsigned long)mp4.length];
    }

    NSMutableString *said = [NSMutableString string];
    [said appendFormat:@"%lu Б, части: %@",
     (unsigned long)mp4.length, [names componentsJoinedByString:@" "]];

    const uint8_t *data = mp4.bytes;
    NSUInteger length = mp4.length;

    NSUInteger ftyp = [names indexOfObject:@"ftyp"];
    if (ftyp != NSNotFound) {
        NSUInteger at = [starts[ftyp] unsignedIntegerValue] + 8;
        [said appendFormat:@"; вид %@", MAXBoxName(data, length, at)];
    }

    NSUInteger moov = [names indexOfObject:@"moov"];
    if (moov == NSNotFound) return said;

    NSUInteger at = [starts[moov] unsignedIntegerValue];
    NSUInteger size = [lengths[moov] unsignedIntegerValue];

    NSMutableArray *tables = [NSMutableArray array];
    MAXFindBoxes(data, length, at + 8, size - 8, @"stsd", tables);

    for (NSNumber *place in tables) {
        NSUInteger entry = [place unsignedIntegerValue] + 8;
        if (entry + 36 > length) continue;

        NSString *kind = MAXBoxName(data, length, entry + 4);
        if (![kind isEqualToString:@"avc1"] && ![kind isEqualToString:@"avc3"]) continue;

        uint32_t box = MAXRead32(data, length, entry);
        int wide = (data[entry + 32] << 8) | data[entry + 33];
        int tall = (data[entry + 34] << 8) | data[entry + 35];

        [said appendFormat:@"; картинка %dx%d", wide, tall];

        NSUInteger from = 0;
        NSUInteger to = 0;
        if (!MAXInside(data, length, entry + 86, entry + box, @"avcC", &from, &to)) continue;
        if (from + 6 > to) continue;

        int many = data[from + 5] & 0x1F;
        NSUInteger cursor = from + 6;
        if (many < 1 || cursor + 2 > to) continue;

        NSUInteger sps = ((NSUInteger)data[cursor] << 8) | data[cursor + 1];
        cursor += 2;
        if (sps < 2 || cursor + sps > to) continue;

        NSData *clean = MAXUnstuff(data, cursor + 1, sps - 1);
        NSInteger aspect = -1;
        NSInteger spelt = -1;
        NSInteger range = -1;

        if (!MAXSpsPlaces(clean, &aspect, &spelt, &range)) {
            [said appendString:@"; описание потока не разобрано"];
            continue;
        }

        const uint8_t *bytes = clean.bytes;
        [said appendFormat:@"; извод %d уровень %d", bytes[0], bytes[2]];

        if (spelt >= 0) {
            [said appendFormat:@"; точка %llu:%llu",
             MAXPeek(bytes, spelt, 16), MAXPeek(bytes, spelt + 16, 16)];
        } else if (aspect >= 0) {
            [said appendFormat:@"; точка №%llu", MAXPeek(bytes, aspect, 8)];
        } else {
            [said appendString:@"; точка не объявлена"];
        }

        [said appendString:(range >= 0
                            ? (MAXPeek(bytes, range, 1) != 0
                               ? @"; диапазон полный"
                               : @"; диапазон обычный")
                            : @"; диапазон не объявлен")];
    }

    return said;
}

+ (NSData *)prepare:(NSData *)mp4 {
    if (mp4.length < 16) return nil;

    NSMutableArray *starts = [NSMutableArray array];
    NSMutableArray *lengths = [NSMutableArray array];
    NSMutableArray *names = [NSMutableArray array];

    if (![self scan:mp4 starts:starts lengths:lengths names:names]) return nil;

    NSUInteger moov = [names indexOfObject:@"moov"];
    NSUInteger mdat = [names indexOfObject:@"mdat"];
    if (moov == NSNotFound || mdat == NSNotFound) return nil;

    // Куски звука и картинки должны лежать одной частью: только тогда все
    // расстояния до них сдвигаются на одну и ту же величину.
    if ([names indexOfObject:@"mdat" inRange:NSMakeRange(mdat + 1, names.count - mdat - 1)]
            != NSNotFound) {
        return nil;
    }

    // Новый порядок: сперва объявление вида файла — своё, — за ним описание,
    // остальное следом. Части, которых стандарт не знает, выбрасываем: их
    // пишет сюда сам телефон, и на той стороне они только мешают разбирать.
    NSData *head = MAXBrandBox();

    NSMutableArray *order = [NSMutableArray arrayWithObject:@(moov)];
    for (NSUInteger box = 0; box < names.count; box++) {
        NSString *name = names[box];
        if ([name isEqualToString:@"ftyp"] || box == moov) continue;
        if ([name isEqualToString:@"uuid"] || [name isEqualToString:@"free"]
                || [name isEqualToString:@"skip"]) continue;
        [order addObject:@(box)];
    }

    NSUInteger total = head.length;
    NSInteger placed = -1;

    for (NSNumber *number in order) {
        NSUInteger box = [number unsignedIntegerValue];
        if (box == mdat) placed = (NSInteger)total;
        total += [lengths[box] unsignedIntegerValue];
    }
    if (placed < 0) return nil;

    // На сколько уехали куски — на столько же надо подвинуть все расстояния
    // до них внутри описания.
    int64_t delta = placed - (int64_t)[starts[mdat] unsignedIntegerValue];

    NSMutableData *described =
        [NSMutableData dataWithData:[mp4 subdataWithRange:
            NSMakeRange([starts[moov] unsignedIntegerValue],
                        [lengths[moov] unsignedIntegerValue])]];

    // Диапазон яркости правится на месте, длины не меняя, — поэтому до
    // сдвига или после, безразлично.
    MAXLimitMoov(described);
    if (delta != 0) MAXShiftOffsets(described, delta);

    NSMutableData *made = [NSMutableData dataWithCapacity:total];
    [made appendData:head];

    for (NSNumber *number in order) {
        NSUInteger box = [number unsignedIntegerValue];

        if (box == moov) {
            [made appendData:described];
            continue;
        }
        [made appendData:[mp4 subdataWithRange:
            NSMakeRange([starts[box] unsignedIntegerValue],
                        [lengths[box] unsignedIntegerValue])]];
    }

    return made;
}

@end
