//
//  MAXVoiceRecorder.m
//

#import "MAXVoiceRecorder.h"
#import "MAXOpus.h"
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>

/// Столбиков в графике и наибольшая высота столбика. Числа не наши: столько
/// шлёт настоящий клиент, и по ним же рисует их собеседник.
static const NSUInteger MAXWaveBars = 80;
static const CGFloat MAXWaveTop = 120.0;

/// Как часто снимается замер громкости. Десять раз в секунду хватает: график
/// всё равно сжимается до восьмидесяти столбиков.
static const NSTimeInterval MAXWaveTick = 0.1;

/// Сколько отсчётов читается из файла за раз при кодировании — примерно
/// четверть секунды.
static const NSUInteger MAXVoiceChunkSamples = 12000;

@implementation MAXVoiceTake
@end

@implementation MAXVoiceRecorder {
    AVAudioRecorder *_recorder;
    NSString *_path;
    NSTimer *_meter;
    NSMutableArray *_levels;
    NSDate *_startedAt;
    CGFloat _level;
    BOOL _recording;
}

+ (instancetype)shared {
    static MAXVoiceRecorder *instance = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [[MAXVoiceRecorder alloc] init]; });
    return instance;
}

- (BOOL)recording { return _recording; }
- (CGFloat)level { return _level; }

- (NSTimeInterval)elapsed {
    if (_startedAt == nil) return 0;
    return -[_startedAt timeIntervalSinceNow];
}

#pragma mark - Разрешение

/// `recordPermission` появился в iOS 8, `requestRecordPermission:` — в iOS 7,
/// а до того микрофон открывался без спроса. Спрашиваем через
/// respondsToSelector: SDK у нас девятый, а работать приложение должно и на
/// шестом.
+ (BOOL)permissionSettled {
    AVAudioSession *session = [AVAudioSession sharedInstance];
    if (![session respondsToSelector:@selector(recordPermission)]) return YES;

    // Оба метода объявлены в SDK 9.3, поэтому зовём их обычным вызовом, а
    // не performSelector: тот возвращает указатель, и число из него достаётся
    // только приведением, верным по случайности.
    return [session recordPermission] != AVAudioSessionRecordPermissionUndetermined;
}

+ (void)askPermission:(void (^)(BOOL granted))done {
    AVAudioSession *session = [AVAudioSession sharedInstance];
    if (![session respondsToSelector:@selector(requestRecordPermission:)]) {
        done(YES);
        return;
    }

    [session requestRecordPermission:^(BOOL granted) {
        dispatch_async(dispatch_get_main_queue(), ^{ done(granted); });
    }];
}

#pragma mark - Запись

- (NSString *)freshPath {
    NSString *name = [NSString stringWithFormat:@"voice-%.0f.wav",
                      [NSDate timeIntervalSinceReferenceDate] * 1000.0];
    return [NSTemporaryDirectory() stringByAppendingPathComponent:name];
}

- (BOOL)startWithProblem:(NSString **)problem {
    if (_recording) return YES;

    AVAudioSession *session = [AVAudioSession sharedInstance];
    NSError *error = nil;

    // Без PlayAndRecord запись на устройстве идёт вхолостую: категория по
    // умолчанию микрофон вовсе не открывает.
    if (![session setCategory:AVAudioSessionCategoryPlayAndRecord error:&error]) {
        if (problem != NULL) *problem = @"Не удалось занять микрофон";
        NSLog(@"[Max/Голос] категория не встала: %@", error.localizedDescription);
        return NO;
    }
    if (![session setActive:YES error:&error]) {
        if (problem != NULL) *problem = @"Микрофон занят другим приложением";
        NSLog(@"[Max/Голос] сессия не включилась: %@", error.localizedDescription);
        return NO;
    }

    // Просим ровно то, что нужно кодировщику: 48 кГц, один канал, целые
    // шестнадцать разрядов. Расширение .wav выбирает контейнер — из него же
    // потом читаются настоящие частота и число каналов: попросить можно что
    // угодно, а телефон запишет как умеет.
    NSDictionary *settings = @{
        AVFormatIDKey: @(kAudioFormatLinearPCM),
        AVSampleRateKey: @([MAXOpusEncoder recordingRate]),
        AVNumberOfChannelsKey: @(1),
        AVLinearPCMBitDepthKey: @(16),
        AVLinearPCMIsBigEndianKey: @(NO),
        AVLinearPCMIsFloatKey: @(NO)
    };

    _path = [self freshPath];
    _recorder = [[AVAudioRecorder alloc] initWithURL:[NSURL fileURLWithPath:_path]
                                            settings:settings
                                               error:&error];
    if (_recorder == nil) {
        if (problem != NULL) *problem = @"Не удалось начать запись";
        NSLog(@"[Max/Голос] запись не завелась: %@", error.localizedDescription);
        return NO;
    }

    _recorder.meteringEnabled = YES;

    if (![_recorder record]) {
        // Сюда же приходит отказ в доступе к микрофону: своей ошибки у него
        // нет, `record` просто возвращает NO.
        if (problem != NULL) *problem = @"Микрофон недоступен — проверьте разрешения";
        _recorder = nil;
        return NO;
    }

    _levels = [NSMutableArray array];
    _startedAt = [NSDate date];
    _level = 0;
    _recording = YES;

    _meter = [NSTimer scheduledTimerWithTimeInterval:MAXWaveTick
                                              target:self
                                            selector:@selector(tick)
                                            userInfo:nil
                                             repeats:YES];
    return YES;
}

/// Замер громкости приходит в децибелах — от -160 до 0. Ухо слышит громкость
/// не так, как её считает арифметика: без поправки обычная речь дала бы почти
/// незаметные столбики, а разница между шёпотом и криком терялась бы вовсе.
- (void)tick {
    if (!_recording) return;

    [_recorder updateMeters];
    float decibels = [_recorder averagePowerForChannel:0];

    CGFloat loud = powf(10.0f, decibels / 20.0f);
    CGFloat shown = sqrt(loud) * 1.6;
    if (shown > 1.0) shown = 1.0;
    if (shown < 0.0) shown = 0.0;

    _level = shown;
    [_levels addObject:@(shown)];
}

- (void)teardown {
    [_meter invalidate];
    _meter = nil;

    _recorder = nil;
    _recording = NO;
    _level = 0;

    NSError *error = nil;
    [[AVAudioSession sharedInstance] setActive:NO error:&error];
}

- (void)cancel {
    if (!_recording) {
        [self teardown];
        return;
    }

    NSString *path = _path;
    [_recorder stop];
    [self teardown];

    [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
    NSLog(@"[Max/Голос] запись отменена");
}

- (void)stopWithCompletion:(void (^)(MAXVoiceTake *take))completion {
    if (!_recording) {
        MAXVoiceTake *take = [[MAXVoiceTake alloc] init];
        take.error = @"Запись не шла";
        completion(take);
        return;
    }

    NSInteger elapsed = (NSInteger)(self.elapsed * 1000.0);
    NSString *path = _path;
    NSData *wave = [self buildWave];

    [_recorder stop];
    [self teardown];

    // Кодирование пятиминутной записи занимает секунды — на главной очереди
    // это застывший экран.
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        MAXVoiceTake *take = [[MAXVoiceTake alloc] init];
        take.durationMs = elapsed;
        take.wave = wave;
        take.data = [MAXVoiceRecorder encodeWavAtPath:path];

        if (take.data.length == 0) {
            take.error = @"Записать не получилось: звука не поступило";
        }

        [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];

        NSLog(@"[Max/Голос] %ld мс, %lu байт",
              (long)elapsed, (unsigned long)take.data.length);

        dispatch_async(dispatch_get_main_queue(), ^{ completion(take); });
    });
}

/// Собрать график: сколько бы замеров ни набралось, столбиков всегда
/// восемьдесят. В каждом — самый громкий замер своего отрезка, а не средний:
/// усреднение съедает рисунок речи.
- (NSData *)buildWave {
    NSMutableData *wave = [NSMutableData dataWithLength:MAXWaveBars];
    if (_levels.count == 0) return wave;

    uint8_t *bytes = wave.mutableBytes;

    for (NSUInteger bar = 0; bar < MAXWaveBars; bar++) {
        NSUInteger from = _levels.count * bar / MAXWaveBars;
        NSUInteger to = _levels.count * (bar + 1) / MAXWaveBars;
        if (to <= from) to = from + 1;

        CGFloat peak = 0;
        for (NSUInteger at = from; at < to && at < _levels.count; at++) {
            CGFloat value = [_levels[at] doubleValue];
            if (value > peak) peak = value;
        }

        NSInteger height = (NSInteger)lround(peak * MAXWaveTop);
        if (height < 0) height = 0;
        if (height > (NSInteger)MAXWaveTop) height = (NSInteger)MAXWaveTop;

        bytes[bar] = (uint8_t)height;
    }
    return wave;
}

#pragma mark - Кодирование

/// Где в заголовке WAV кончается описание и начинаются отсчёты.
///
/// Заодно оттуда же берутся частота и число каналов: попросить у телефона
/// можно что угодно, а запишет он как умеет, — и кодировщику нужно знать,
/// что именно ему скармливают.
+ (BOOL)findBodyOf:(NSData *)file
                at:(NSUInteger *)offset
            length:(NSUInteger *)length
              rate:(int *)rate
          channels:(int *)channels {
    if (file.length < 44) return NO;

    const uint8_t *bytes = file.bytes;
    if (memcmp(bytes, "RIFF", 4) != 0 || memcmp(bytes + 8, "WAVE", 4) != 0) return NO;

    *rate = [MAXOpusEncoder recordingRate];
    *channels = 1;

    NSUInteger at = 12;
    while (at + 8 <= file.length) {
        uint32_t size = 0;
        for (int i = 0; i < 4; i++) size |= ((uint32_t)bytes[at + 4 + i]) << (i * 8);

        if (memcmp(bytes + at, "data", 4) == 0) {
            *offset = at + 8;
            NSUInteger left = file.length - *offset;
            *length = MIN((NSUInteger)size, left);
            return *length > 0;
        }

        if (memcmp(bytes + at, "fmt ", 4) == 0 && at + 8 + 16 <= file.length) {
            const uint8_t *fmt = bytes + at + 8;
            *channels = fmt[2] | (fmt[3] << 8);
            *rate = fmt[4] | (fmt[5] << 8) | (fmt[6] << 16) | (fmt[7] << 24);

            if (*channels < 1) *channels = 1;
            if (*rate < 8000) *rate = [MAXOpusEncoder recordingRate];
        }

        // Куски выравниваются по чётному числу байтов. Длина берётся из
        // самого файла, поэтому ей нельзя верить на слово: испорченный
        // заголовок с огромным числом увёл бы обход за пределы файла.
        if (size > file.length) break;
        at += 8 + (NSUInteger)size + (size & 1);
    }
    return NO;
}

/// Файл читается отображением в память, а не целиком: система подтягивает
/// страницы по мере надобности и сама их отпускает.
+ (NSData *)encodeWavAtPath:(NSString *)path {
    NSData *file = [NSData dataWithContentsOfFile:path
                                          options:NSDataReadingMappedIfSafe
                                            error:NULL];
    if (file.length == 0) return nil;

    NSUInteger offset = 0;
    NSUInteger length = 0;
    int rate = 0;
    int channels = 1;

    if (![self findBodyOf:file at:&offset length:&length rate:&rate channels:&channels]) {
        NSLog(@"[Max/Голос] в записи не нашлось отсчётов");
        return nil;
    }

    if (rate != [MAXOpusEncoder recordingRate]) {
        // Телефон записал не на той частоте — кодировщик заведён на другую,
        // и звук уехал бы по высоте. Такого пока не встречалось, но молчать
        // об этом нельзя.
        NSLog(@"[Max/Голос] телефон записал на %d Гц вместо %d",
              rate, [MAXOpusEncoder recordingRate]);
        return nil;
    }

    MAXOpusEncoder *encoder = [[MAXOpusEncoder alloc] init];
    if (!encoder.ready) return nil;

    const uint8_t *bytes = (const uint8_t *)file.bytes + offset;
    NSUInteger samples = length / (sizeof(int16_t) * channels);

    // Стерео сводится в моно на лету: кодировщик заведён на один канал.
    int16_t *chunk = malloc(sizeof(int16_t) * MAXVoiceChunkSamples);
    if (chunk == NULL) return nil;

    NSUInteger at = 0;
    while (at < samples) {
        NSUInteger take = MIN(MAXVoiceChunkSamples, samples - at);

        for (NSUInteger i = 0; i < take; i++) {
            const uint8_t *frame = bytes + (at + i) * sizeof(int16_t) * channels;
            int32_t sum = 0;
            for (int c = 0; c < channels; c++) {
                sum += (int16_t)(frame[c * 2] | (frame[c * 2 + 1] << 8));
            }
            chunk[i] = (int16_t)(sum / channels);
        }

        [encoder feed:chunk count:take];
        at += take;
    }

    free(chunk);
    return [encoder finish];
}

@end
