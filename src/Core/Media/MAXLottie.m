//
//  MAXLottie.m
//

#import "MAXLottie.h"
#import "MAXHttp.h"
#import <max_lottie.h>
#import <zlib.h>

/// Предел стороны отрисовки, в точках экрана.
///
/// Считать сторону по месту под стикер — правильно: нарисованное мельче
/// экран растянет, и выйдет мыло. Но на экране с двойной плотностью место
/// в 140 точек разметки — это 280 точек экрана, вчетверо больше работы на
/// каждый кадр, и старое устройство за тридцатью кадрами в секунду уже не
/// поспевает. Предел выбран так, чтобы на обычном экране стикер рисовался
/// точка в точку, а на плотном — чуть мельче места и растягивался самую
/// малость.
static const CGFloat MAXLottieLargestSide = 200.0;

/// Распаковать gzip. MAX присылает описания сжатыми — всегда, а не изредка;
/// узнаём по первым двум байтам.
static NSData *MAXGunzip(NSData *packed) {
    if (packed.length < 3) return nil;

    const uint8_t *bytes = packed.bytes;
    if (bytes[0] != 0x1F || bytes[1] != 0x8B) return packed;   // и не сжато вовсе

    z_stream stream;
    memset(&stream, 0, sizeof(stream));

    // 16 к окну — это и значит «ждём заголовок gzip, а не zlib».
    if (inflateInit2(&stream, 16 + MAX_WBITS) != Z_OK) return nil;

    stream.next_in = (Bytef *)packed.bytes;
    stream.avail_in = (uInt)packed.length;

    NSMutableData *made = [NSMutableData dataWithCapacity:packed.length * 6];
    uint8_t chunk[16384];

    int state = Z_OK;
    while (state != Z_STREAM_END) {
        stream.next_out = chunk;
        stream.avail_out = sizeof(chunk);

        state = inflate(&stream, Z_NO_FLUSH);
        if (state != Z_OK && state != Z_STREAM_END) {
            inflateEnd(&stream);
            return nil;
        }

        [made appendBytes:chunk length:sizeof(chunk) - stream.avail_out];

        // Сжатое, раздувшееся в сотню раз, — это не стикер, а беда.
        if (made.length > 8 * 1024 * 1024) {
            inflateEnd(&stream);
            return nil;
        }
    }

    inflateEnd(&stream);
    return made;
}

/// Очередь одна на всю библиотеку, а не на сцену.
///
/// Это не осторожность, а единственный способ. rlottie собрана без
/// поддержки потоков (LOTTIE_THREAD_SUPPORT), и в таком виде у неё **один
/// на всё** рабочий контур с обводчиком (`RleTaskScheduler::instance()`),
/// а `vthread_local` превращается в пустоту — то есть и временный `VRle`,
/// и вектор пунктира тоже общие. Два стикера, рисуемые разом, рвут друг
/// другу кучу: приложение падает внутри malloc, и не там, где виновато.
///
/// Включить у неё потоки нельзя: `thread_local` требует от системы того,
/// чего до iOS 9 нет вовсе.
static dispatch_queue_t MAXLottieQueue(void) {
    static dispatch_queue_t queue = NULL;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        queue = dispatch_queue_create("ru.max.lottie", DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

@implementation MAXLottie {
    void *_animation;
    uint32_t *_buffer;
    NSInteger _side;
    BOOL _busy;

    NSInteger _drawn;         // сколько кадров нарисовано
    NSTimeInterval _spent;    // и сколько на них ушло — для журнала
}

- (BOOL)busy { return _busy; }
- (NSInteger)side { return _side; }

+ (void)openURL:(NSString *)url
            key:(NSString *)key
           side:(CGFloat)side
     completion:(void (^)(MAXLottie *animation))done {
    if (url.length == 0) {
        done(nil);
        return;
    }

    NSString *address = [url copy];
    NSString *name = [key copy] ?: @"";

    // Точки разметки в точки экрана: на плотном экране их вдвое больше,
    // и рисовать надо по ним, иначе нарисованное будет растянуто.
    CGFloat scale = [UIScreen mainScreen].scale;
    CGFloat wanted = ceilf(side * (scale > 0 ? scale : 1.0));
    if (wanted > MAXLottieLargestSide) wanted = MAXLottieLargestSide;
    if (wanted < 32.0) wanted = 32.0;
    NSInteger pixels = (NSInteger)wanted;

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        // Своими корнями: у CDN их нет в системном хранилище.
        NSData *packed = [MAXHttp dataWithContentsOfURLString:address];
        NSData *json = MAXGunzip(packed);

        NSLog(@"[Max/Стикер] %@: скачано %lu, после распаковки %lu",
              [address lastPathComponent], (unsigned long)packed.length,
              (unsigned long)json.length);

        if (json.length == 0) {
            dispatch_async(dispatch_get_main_queue(), ^{ done(nil); });
            return;
        }

        // Разбор описания — тоже работа библиотеки, и идти он должен там
        // же, где отрисовка: общее у неё не только рисование.
        dispatch_async(MAXLottieQueue(), ^{
            MAXLottie *made = [[MAXLottie alloc] initWithJson:json
                                                          key:name
                                                         side:pixels];
            dispatch_async(dispatch_get_main_queue(), ^{ done(made); });
        });
    });
}

- (id)initWithJson:(NSData *)json key:(NSString *)key side:(NSInteger)side {
    self = [super init];
    if (self == nil) return nil;

    _side = side;

    // Библиотека ждёт строку, оканчивающуюся нулём.
    NSMutableData *text = [NSMutableData dataWithData:json];
    [text appendBytes:"\0" length:1];

    _animation = max_lottie_open((const char *)text.bytes, [key UTF8String] ?: "");
    if (_animation == NULL) {
        NSLog(@"[Max/Стикер] описание не разобралось (%lu знаков)",
              (unsigned long)json.length);
        return nil;
    }

    _buffer = calloc((size_t)(_side * _side), sizeof(uint32_t));
    if (_buffer == NULL) {
        max_lottie_close(_animation);
        _animation = NULL;
        return nil;
    }

    NSLog(@"[Max/Стикер] кадров %ld, по %.0f мс, рисуем %ldx%ld",
          (long)self.frames, self.frameDuration * 1000.0, (long)_side, (long)_side);
    return self;
}

- (void)dealloc {
    // Освобождаем на очереди отрисовки: там мог остаться недорисованный
    // кадр, да и закрывать сцену, пока библиотека занята другой, нельзя —
    // общего в ней достаточно.
    void *animation = _animation;
    uint32_t *buffer = _buffer;

    if (animation != NULL) {
        dispatch_async(MAXLottieQueue(), ^{
            max_lottie_close(animation);
            free(buffer);
        });
        return;
    }

    free(buffer);
}

- (NSInteger)frames {
    if (_animation == NULL) return 0;
    return (NSInteger)max_lottie_frames(_animation);
}

- (NSTimeInterval)frameDuration {
    if (_animation == NULL) return 0;

    double rate = max_lottie_rate(_animation);
    if (rate <= 0) return 1.0 / 30.0;
    return 1.0 / rate;
}

/// Кадр в картинку. Точки rlottie отдаёт уже помноженными на прозрачность и
/// в том порядке, в каком их читает CoreGraphics на этой архитектуре, —
/// переставлять ничего не приходится.
///
/// А вот копировать приходится: картинка читает точки не тогда, когда её
/// делают, а когда рисуют, — и к тому мигу общий буфер был бы уже занят
/// следующим кадром. Стоит копия 64 КБ на кадр.
- (UIImage *)imageFromBuffer {
    size_t bytes = (size_t)(_side * _side) * sizeof(uint32_t);

    NSData *frame = [NSData dataWithBytes:_buffer length:bytes];
    CGDataProviderRef source = CGDataProviderCreateWithCFData((__bridge CFDataRef)frame);
    if (source == NULL) return nil;

    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();

    CGImageRef made = CGImageCreate((size_t)_side, (size_t)_side, 8, 32,
                                    (size_t)_side * sizeof(uint32_t), space,
                                    kCGImageAlphaPremultipliedFirst
                                        | kCGBitmapByteOrder32Little,
                                    source, NULL, NO, kCGRenderingIntentDefault);

    CGColorSpaceRelease(space);
    CGDataProviderRelease(source);

    if (made == NULL) return nil;

    // Со своей плотностью, а не «точка разметки = точка экрана»: иначе
    // UIKit посчитает кадр вдвое большим, чем он есть, и на плотном экране
    // стикер выйдет вдвое крупнее места под него.
    CGFloat scale = [UIScreen mainScreen].scale;
    UIImage *image = [UIImage imageWithCGImage:made
                                         scale:(scale > 0 ? scale : 1.0)
                                   orientation:UIImageOrientationUp];
    CGImageRelease(made);
    return image;
}

- (void)renderFrame:(NSInteger)frame completion:(void (^)(UIImage *image))done {
    if (_animation == NULL || _busy) {
        done(nil);
        return;
    }

    _busy = YES;

    __weak MAXLottie *weakSelf = self;
    dispatch_async(MAXLottieQueue(), ^{
        MAXLottie *strongSelf = weakSelf;
        if (strongSelf == nil) return;

        NSTimeInterval began = [NSDate timeIntervalSinceReferenceDate];

        max_lottie_render(strongSelf->_animation, (int)frame, strongSelf->_buffer,
                          (int)strongSelf->_side, (int)strongSelf->_side,
                          (int)(strongSelf->_side * sizeof(uint32_t)));

        // Сколько стоит кадр — главный вопрос к этой затее на старом
        // устройстве, поэтому счёт ведётся и попадает в журнал. Не каждый
        // кадр: их тридцать в секунду, журнал бы захлебнулся.
        strongSelf->_spent += [NSDate timeIntervalSinceReferenceDate] - began;
        strongSelf->_drawn += 1;

        if (strongSelf->_drawn == 1 || strongSelf->_drawn % 100 == 0) {
            NSLog(@"[Max/Стикер] кадр %ld, в среднем %.0f мс на кадр",
                  (long)strongSelf->_drawn,
                  strongSelf->_spent / (double)strongSelf->_drawn * 1000.0);
        }

        // Картинка строится здесь же, на этой очереди: буфер общий, и к
        // следующему кадру он будет занят.
        UIImage *image = [strongSelf imageFromBuffer];

        dispatch_async(dispatch_get_main_queue(), ^{
            strongSelf->_busy = NO;
            done(image);
        });
    });
}

@end
