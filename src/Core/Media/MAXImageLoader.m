//
//  MAXImageLoader.m
//

#import "MAXImageLoader.h"
#import "MAXHttp.h"
#import "MAXWebP.h"

/// Разбор картинки: сначала штатный ImageIO, потом свой WebP.
///
/// Порядок именно такой, а не наоборот: JPEG и PNG система читает быстрее
/// и без лишней копии в памяти, а WebP она до iOS 14 не умеет вовсе —
/// и это не редкий случай, а основной: CDN MAX отдаёт только его.
static UIImage *MAXDecodeImage(NSData *data) {
    if (data.length == 0) return nil;

    UIImage *image = [UIImage imageWithData:data];
    if (image != nil) return image;

    return [MAXWebP imageWithData:data];
}

@implementation MAXImageLoader {
    NSCache *_memory;
    NSMutableDictionary *_masks;   // размер в пикселях -> CGImageRef круга
    NSMutableSet *_inFlight;
    NSMutableDictionary *_waiting;   // ключ -> массив блоков
    dispatch_queue_t _ioQueue;
    NSString *_diskPath;
}

+ (instancetype)shared {
    static MAXImageLoader *instance = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        instance = [[MAXImageLoader alloc] init];
    });
    return instance;
}

- (id)init {
    self = [super init];
    if (self) {
        _memory = [[NSCache alloc] init];
        _memory.countLimit = 200;
        _masks = [NSMutableDictionary dictionary];
        _inFlight = [NSMutableSet set];
        _waiting = [NSMutableDictionary dictionary];
        _ioQueue = dispatch_queue_create("ru.max.images", DISPATCH_QUEUE_CONCURRENT);

        // Application Support, а не Caches: Caches система чистит сама, и после
        // такой уборки список чатов целиком уходил в сеть за аватарками.
        NSString *support = [NSSearchPathForDirectoriesInDomains(
            NSApplicationSupportDirectory, NSUserDomainMask, YES) objectAtIndex:0];
        _diskPath = [support stringByAppendingPathComponent:@"images"];
        [[NSFileManager defaultManager] createDirectoryAtPath:_diskPath
                                 withIntermediateDirectories:YES
                                                  attributes:nil
                                                       error:NULL];

        [self migrateLegacyCache];
        dispatch_async(_ioQueue, ^{ [self pruneDiskCache]; });
    }
    return self;
}

/// Прежний кэш лежал в Caches; аккуратно переносим его один раз, чтобы после
/// обновления не качать заново то, что уже есть.
- (void)migrateLegacyCache {
    NSFileManager *manager = [NSFileManager defaultManager];
    NSString *caches = [NSSearchPathForDirectoriesInDomains(
        NSCachesDirectory, NSUserDomainMask, YES) objectAtIndex:0];
    NSString *legacy = [caches stringByAppendingPathComponent:@"avatars"];

    if (![manager fileExistsAtPath:legacy]) return;

    for (NSString *name in [manager contentsOfDirectoryAtPath:legacy error:NULL]) {
        NSString *from = [legacy stringByAppendingPathComponent:name];
        NSString *to = [_diskPath stringByAppendingPathComponent:name];
        if ([manager fileExistsAtPath:to]) continue;
        [manager moveItemAtPath:from toPath:to error:NULL];
    }
    [manager removeItemAtPath:legacy error:NULL];
}

/// Держит кэш в разумных пределах: первым уходит самое старое по времени
/// записи. Без этого папка растёт всю жизнь установки — фотографии переписки
/// складываются туда же, а они куда тяжелее аватарок.
- (void)pruneDiskCache {
    static const unsigned long long limit = 48ULL * 1024 * 1024;

    NSFileManager *manager = [NSFileManager defaultManager];
    NSArray *names = [manager contentsOfDirectoryAtPath:_diskPath error:NULL];
    if (names.count == 0) return;

    NSMutableArray *files = [NSMutableArray arrayWithCapacity:names.count];
    unsigned long long total = 0;

    for (NSString *name in names) {
        NSString *path = [_diskPath stringByAppendingPathComponent:name];
        NSDictionary *attributes = [manager attributesOfItemAtPath:path error:NULL];
        if (attributes == nil) continue;

        unsigned long long size = [attributes fileSize];
        total += size;
        [files addObject:@{@"path": path,
                           @"date": [attributes fileModificationDate] ?: [NSDate distantPast],
                           @"size": @(size)}];
    }

    if (total <= limit) return;

    [files sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [a[@"date"] compare:b[@"date"]];
    }];

    for (NSDictionary *file in files) {
        if (total <= limit) break;
        if ([manager removeItemAtPath:file[@"path"] error:NULL]) {
            total -= [file[@"size"] unsignedLongLongValue];
        }
    }
    NSLog(@"[Max/Картинки] Кэш подчищен до %llu КБ", total / 1024);
}

#pragma mark - Ключи

/// URL в имя файла превращается хешем: в ссылке бывают и слэши, и вопросы,
/// а размер входит в ключ, потому что кэшируется уже обрезанная картинка.
- (NSString *)keyForURL:(NSString *)url size:(CGFloat)size {
    unsigned long hash = 5381;
    const char *bytes = [url UTF8String];
    for (NSUInteger i = 0; bytes[i] != '\0'; i++) {
        hash = ((hash << 5) + hash) + (unsigned char)bytes[i];
    }
    return [NSString stringWithFormat:@"%lx-%d", hash, (int)size];
}

/// У круглой аватарки прозрачные углы, поэтому только PNG. Фотография из
/// переписки прозрачности не имеет, и JPEG на диске занимает в разы меньше:
/// PNG от снимка на 3 МБ разворачивается в десятки.
- (NSString *)diskPathForKey:(NSString *)key size:(CGFloat)size {
    return [_diskPath stringByAppendingPathComponent:
            [key stringByAppendingPathExtension:(size > 0 ? @"png" : @"jpg")]];
}

- (NSData *)encodedImage:(UIImage *)image size:(CGFloat)size {
    return size > 0 ? UIImagePNGRepresentation(image) : UIImageJPEGRepresentation(image, 0.85);
}

#pragma mark - Чтение

- (UIImage *)cachedImageForURL:(NSString *)url size:(CGFloat)size {
    if (url.length == 0) return nil;

    NSString *key = [self keyForURL:url size:size];
    UIImage *ready = [_memory objectForKey:key];
    if (ready != nil) return ready;

    // Аватарку читаем с диска прямо здесь: файл в несколько килобайт, зато
    // список чатов при запуске не мигает буквами-заглушками, пока асинхронная
    // загрузка дойдёт до тех же байтов. Картинкам переписки (size == 0) так
    // нельзя — они многомегабайтные, и это была бы задержка на прокрутке.
    if (size <= 0) return nil;

    UIImage *stored = [self imageFromDiskForKey:key size:size];
    if (stored != nil) [_memory setObject:stored forKey:key];
    return stored;
}

- (void)loadImageForURL:(NSString *)url
                   size:(CGFloat)size
             completion:(void (^)(UIImage *image))completion {
    if (url.length == 0 || completion == nil) return;

    NSString *key = [self keyForURL:url size:size];

    UIImage *ready = [_memory objectForKey:key];
    if (ready != nil) {
        completion(ready);
        return;
    }

    // Один и тот же аватар просят сразу несколько ячеек: качаем один раз,
    // а колбэки складываем в очередь по ключу.
    @synchronized (self) {
        NSMutableArray *queue = _waiting[key];
        if (queue == nil) {
            queue = [NSMutableArray array];
            _waiting[key] = queue;
        }
        [queue addObject:[completion copy]];

        if ([_inFlight containsObject:key]) return;
        [_inFlight addObject:key];
    }

    dispatch_async(_ioQueue, ^{
        UIImage *image = [self imageFromDiskForKey:key size:size];

        if (image == nil) {
            UIImage *original = [self originalImageForURL:url];
            if (original != nil) {
                image = [self circularImageFrom:original size:size];
                if (image != nil) {
                    [[self encodedImage:image size:size]
                     writeToFile:[self diskPathForKey:key size:size] atomically:YES];
                }
            }
        }

        if (image != nil) [self->_memory setObject:image forKey:key];

        NSArray *blocks = nil;
        @synchronized (self) {
            blocks = [self->_waiting[key] copy];
            [self->_waiting removeObjectForKey:key];
            [self->_inFlight removeObject:key];
        }

        // Колбэк вызывается и при неудаче, с nil. Раньше на неудаче блоки
        // просто выбрасывались — и крутилка в пузыре с фотографией крутилась
        // вечно, потому что остановить её было некому.
        dispatch_async(dispatch_get_main_queue(), ^{
            for (void (^block)(UIImage *) in blocks) block(image);
        });
    });
}

/// Размер 0 в ключе означает «как есть»: обрезка по кругу и уменьшение
/// нужны аватаркам, а картинке в переписке — нет.
- (void)loadOriginalImageForURL:(NSString *)url completion:(void (^)(UIImage *image))completion {
    if (url.length == 0 || completion == nil) return;

    NSString *key = [self keyForURL:url size:0];

    UIImage *ready = [_memory objectForKey:key];
    if (ready != nil) {
        completion(ready);
        return;
    }

    @synchronized (self) {
        NSMutableArray *queue = _waiting[key];
        if (queue == nil) {
            queue = [NSMutableArray array];
            _waiting[key] = queue;
        }
        [queue addObject:[completion copy]];

        if ([_inFlight containsObject:key]) return;
        [_inFlight addObject:key];
    }

    dispatch_async(_ioQueue, ^{
        // На диск кладётся разобранная картинка, а не то, что приехало: читаем
        // мы её потом через imageWithContentsOfFile, а он WebP не понимает —
        // сырые байты под чужим именем просто не прочлись бы. Этим же занят
        // originalImageForURL:, поэтому здесь он и вызывается.
        UIImage *image = [self originalImageForURL:url];

        if (image != nil) [self->_memory setObject:image forKey:key];

        NSArray *blocks = nil;
        @synchronized (self) {
            blocks = [self->_waiting[key] copy];
            [self->_waiting removeObjectForKey:key];
            [self->_inFlight removeObject:key];
        }

        // Колбэк вызывается и при неудаче, с nil. Раньше на неудаче блоки
        // просто выбрасывались — и крутилка в пузыре с фотографией крутилась
        // вечно, потому что остановить её было некому.
        dispatch_async(dispatch_get_main_queue(), ^{
            for (void (^block)(UIImage *) in blocks) block(image);
        });
    });
}

/// Исходник аватарки: сперва с диска, и только если его там нет — из сети.
///
/// Один и тот же человек показывается в трёх размерах — в списке чатов,
/// в шапке пузыря и в списке участников, — и каждый размер хранится обрезанным
/// отдельно. Без этой прослойки каждый из них ходил бы в сеть за одними и теми
/// же байтами: в группе, где половина участников уже знакома по другим чатам,
/// это заметная разница.
- (UIImage *)originalImageForURL:(NSString *)url {
    NSString *originalKey = [self keyForURL:url size:0];

    UIImage *stored = [self imageFromDiskForKey:originalKey size:0];
    if (stored != nil) return stored;

    UIImage *downloaded = MAXDecodeImage([MAXHttp dataWithContentsOfURLString:url]);
    if (downloaded == nil) return nil;

    [[self encodedImage:downloaded size:0]
     writeToFile:[self diskPathForKey:originalKey size:0] atomically:YES];
    return downloaded;
}

- (UIImage *)imageFromDiskForKey:(NSString *)key size:(CGFloat)size {
    NSString *path = [self diskPathForKey:key size:size];
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) return nil;
    return [UIImage imageWithContentsOfFile:path];
}

#pragma mark - Обрезка

/**
 * Маска круга с мягким краем.
 *
 * Обрезка контуром (`addClip`) сглаживания не делает вовсе: край получается
 * ступенчатым, и на экране без ретины — iPad 2, iPhone 4 в режиме 1x — это
 * прекрасно видно, аватарки выглядят пиксельными по кругу.
 *
 * Поэтому круг сначала рисуется в отдельный полутоновый растр, где заливка
 * сглаживается как обычно, а потом им обрезается картинка. Маска зависит
 * только от размера, так что считается один раз на размер и живёт дальше
 * в кэше.
 */
- (CGImageRef)circleMaskForPixels:(size_t)pixels {
    NSNumber *key = @(pixels);
    CGImageRef cached = (__bridge CGImageRef)[_masks objectForKey:key];
    if (cached != NULL) return cached;

    CGColorSpaceRef gray = CGColorSpaceCreateDeviceGray();
    CGContextRef context = CGBitmapContextCreate(NULL, pixels, pixels, 8, pixels,
                                                 gray, (CGBitmapInfo)kCGImageAlphaNone);
    CGColorSpaceRelease(gray);
    if (context == NULL) return NULL;

    CGContextSetGrayFillColor(context, 0.0, 1.0);
    CGContextFillRect(context, CGRectMake(0, 0, pixels, pixels));

    CGContextSetShouldAntialias(context, YES);
    CGContextSetGrayFillColor(context, 1.0, 1.0);
    CGContextFillEllipseInRect(context, CGRectMake(0, 0, pixels, pixels));

    CGImageRef mask = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    if (mask == NULL) return NULL;

    [_masks setObject:(__bridge id)mask forKey:key];
    CGImageRelease(mask);   // словарь держит свою ссылку

    return mask;
}

/// Вписывает картинку в круг заданного размера по правилу «заполнить»:
/// короткая сторона равна диаметру, лишнее по длинной уходит за края.
- (UIImage *)circularImageFrom:(UIImage *)source size:(CGFloat)size {
    if (source.size.width <= 0 || source.size.height <= 0) return nil;

    CGFloat screenScale = [UIScreen mainScreen].scale;
    CGRect bounds = CGRectMake(0, 0, size, size);

    UIGraphicsBeginImageContextWithOptions(bounds.size, NO, screenScale);
    CGContextRef context = UIGraphicsGetCurrentContext();

    CGImageRef mask = [self circleMaskForPixels:(size_t)(size * screenScale)];
    if (mask != NULL) {
        CGContextClipToMask(context, bounds, mask);
    } else {
        [[UIBezierPath bezierPathWithOvalInRect:bounds] addClip];
    }

    CGFloat scale = MAX(size / source.size.width, size / source.size.height);
    CGSize scaled = CGSizeMake(source.size.width * scale, source.size.height * scale);
    CGRect target = CGRectMake((size - scaled.width) / 2.0,
                               (size - scaled.height) / 2.0,
                               scaled.width, scaled.height);
    [source drawInRect:target];

    UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return result;
}

- (void)clearMemoryCache {
    [_memory removeAllObjects];
}

@end
