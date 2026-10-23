//
//  MAXVideoNoteRecorder.m
//

#import "MAXVideoNoteRecorder.h"
#import "MAXMp4Facts.h"

/// Сторона кадра. Ровно 480 и ни точкой больше: проверено дважды — 640×480 и
/// 640×640 сервер отверг, причём у второго всё прочее было в порядке.
static const NSInteger MAXNoteSide = 480;

/// Кадров в секунду — столько же, сколько у настоящего клиента.
static const NSInteger MAXNoteFrameRate = 30;

/// Поток картинки. Настоящий клиент пишет примерно мегабитом, но на движении
/// картинка начинает сыпаться квадратами; полтора сервер берёт — среди
/// принятых им записей была и такая.
static const NSInteger MAXNoteBitrate = 1600000;

/// Звук — как у настоящего: один канал, сорок восемь тысяч, 96 кбит.
static const NSInteger MAXNoteAudioRate = 48000;
static const NSInteger MAXNoteAudioBitrate = 96000;

static const NSTimeInterval MAXNoteLongest = 60.0;

@implementation MAXNoteTake
@end

@interface MAXVideoNoteRecorder () <AVCaptureVideoDataOutputSampleBufferDelegate,
                                    AVCaptureAudioDataOutputSampleBufferDelegate>
@end

@implementation MAXVideoNoteRecorder {
    AVCaptureSession *_session;
    AVCaptureVideoDataOutput *_videoOut;
    AVCaptureAudioDataOutput *_audioOut;
    AVCaptureVideoPreviewLayer *_preview;

    AVAssetWriter *_writer;
    AVAssetWriterInput *_videoIn;
    AVAssetWriterInput *_audioIn;

    /// Кадры и звук — на ней же заканчивается запись: `AVAssetWriter` не
    /// терпит, чтобы в него писали с двух сторон разом, а дописать его,
    /// пока с другого потока в него кладут кадр, — это уже исключение и
    /// мгновенная гибель приложения.
    dispatch_queue_t _queue;

    /// Включение и выключение самой съёмки. Своя, потому что `startRunning`
    /// занимает до секунды, а звать его и `stopRunning` вперемешку с разных
    /// потоков нельзя.
    dispatch_queue_t _sessionQueue;

    NSString *_path;
    NSDate *_startedAt;

    BOOL _recording;
    BOOL _writing;          // первый кадр уже пришёл, сессия записи начата
    BOOL _closing;          // идёт завершение: новых кадров не берём
}

+ (instancetype)shared {
    static MAXVideoNoteRecorder *instance = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [[MAXVideoNoteRecorder alloc] init]; });
    return instance;
}

+ (NSTimeInterval)longest { return MAXNoteLongest; }

- (id)init {
    self = [super init];
    if (self) {
        _queue = dispatch_queue_create("ru.max.note", DISPATCH_QUEUE_SERIAL);
        _sessionQueue = dispatch_queue_create("ru.max.note.session", DISPATCH_QUEUE_SERIAL);
        _front = YES;
    }
    return self;
}

- (BOOL)recording { return _recording; }
- (AVCaptureVideoPreviewLayer *)previewLayer { return _preview; }

- (NSTimeInterval)elapsed {
    if (_startedAt == nil) return 0;
    return -[_startedAt timeIntervalSinceNow];
}

#pragma mark - Разрешение

+ (BOOL)permissionSettled {
    if (![AVCaptureDevice respondsToSelector:@selector(authorizationStatusForMediaType:)]) {
        return YES;
    }
    return [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo]
           != AVAuthorizationStatusNotDetermined;
}

+ (void)askPermission:(void (^)(BOOL granted))done {
    if (![AVCaptureDevice respondsToSelector:@selector(requestAccessForMediaType:completionHandler:)]) {
        done(YES);
        return;
    }

    [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo
                             completionHandler:^(BOOL granted) {
        dispatch_async(dispatch_get_main_queue(), ^{ done(granted); });
    }];
}

#pragma mark - Начало

- (AVCaptureDevice *)cameraFacing:(BOOL)front {
    AVCaptureDevicePosition wanted = front
        ? AVCaptureDevicePositionFront : AVCaptureDevicePositionBack;

    for (AVCaptureDevice *device in [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo]) {
        if (device.position == wanted) return device;
    }
    return [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
}

- (NSString *)freshPath {
    NSString *name = [NSString stringWithFormat:@"note-%.0f.mp4",
                      [NSDate timeIntervalSinceReferenceDate] * 1000.0];
    return [NSTemporaryDirectory() stringByAppendingPathComponent:name];
}

- (void)startWithCompletion:(void (^)(BOOL ready, NSString *problem))done {
    if (_recording) {
        done(YES, nil);
        return;
    }

    NSString *problem = [self buildSession];
    if (problem != nil) {
        [self teardown];
        done(NO, problem);
        return;
    }

    problem = [self buildWriter];
    if (problem != nil) {
        [self teardown];
        done(NO, problem);
        return;
    }

    _recording = YES;
    _writing = NO;
    _closing = NO;
    _startedAt = [NSDate date];

    // Запуск занимает до секунды и на главной очереди виден подвисанием
    // экрана.
    AVCaptureSession *session = _session;
    __weak MAXVideoNoteRecorder *weakSelf = self;

    dispatch_async(_sessionQueue, ^{
        [session startRunning];

        dispatch_async(dispatch_get_main_queue(), ^{
            MAXVideoNoteRecorder *strongSelf = weakSelf;
            if (strongSelf == nil) return;

            // Пока камера включалась, запись могли уже бросить.
            if (!strongSelf->_recording) {
                done(NO, nil);
                return;
            }
            strongSelf->_startedAt = [NSDate date];
            done(YES, nil);
        });
    });
}

- (NSString *)buildSession {
    NSError *error = nil;

    _session = [[AVCaptureSession alloc] init];

    // 640×480 — самый мелкий набор, из которого квадрат в 480 точек вырезается
    // без растягивания. Брать крупнее незачем: всё лишнее всё равно уйдёт в
    // обрезку, а телефону тех лет лишние точки дороги.
    if ([_session canSetSessionPreset:AVCaptureSessionPreset640x480]) {
        _session.sessionPreset = AVCaptureSessionPreset640x480;
    } else {
        _session.sessionPreset = AVCaptureSessionPresetMedium;
    }

    AVCaptureDevice *camera = [self cameraFacing:_front];
    if (camera == nil) return @"Камера недоступна";

    AVCaptureDeviceInput *videoInput = [AVCaptureDeviceInput deviceInputWithDevice:camera
                                                                             error:&error];
    if (videoInput == nil || ![_session canAddInput:videoInput]) {
        NSLog(@"[Max/Кружок] камера не подключилась: %@", error.localizedDescription);
        return @"Камера недоступна";
    }
    [_session addInput:videoInput];

    AVCaptureDevice *mic = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio];
    AVCaptureDeviceInput *audioInput = mic != nil
        ? [AVCaptureDeviceInput deviceInputWithDevice:mic error:&error] : nil;

    // Без звука кружок всё же снимем: беззвучный лучше, чем никакой.
    if (audioInput != nil && [_session canAddInput:audioInput]) {
        [_session addInput:audioInput];
    } else {
        NSLog(@"[Max/Кружок] микрофон не подключился: %@", error.localizedDescription);
    }

    _videoOut = [[AVCaptureVideoDataOutput alloc] init];
    // Полный диапазон яркости сервер бракует. Просим ограниченный прямо у
    // камеры — а верен ли он на самом деле, всё равно проверяется потом по
    // биту в SPS: на Windows Phone именно этот бит и был главной бедой.
    _videoOut.videoSettings = @{(id)kCVPixelBufferPixelFormatTypeKey:
                                    @(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)};
    _videoOut.alwaysDiscardsLateVideoFrames = YES;
    [_videoOut setSampleBufferDelegate:self queue:_queue];

    if (![_session canAddOutput:_videoOut]) return @"Камера недоступна";
    [_session addOutput:_videoOut];

    _audioOut = [[AVCaptureAudioDataOutput alloc] init];
    [_audioOut setSampleBufferDelegate:self queue:_queue];
    if ([_session canAddOutput:_audioOut]) [_session addOutput:_audioOut];

    AVCaptureConnection *link = [_videoOut connectionWithMediaType:AVMediaTypeVideo];

    if ([link isVideoOrientationSupported]) {
        link.videoOrientation = AVCaptureVideoOrientationPortrait;
    }
    // Передняя камера без отражения выглядит чужим лицом: люди привыкли
    // видеть себя как в зеркале.
    if (_front && [link isVideoMirroringSupported]) link.videoMirrored = YES;

    // Частоту задаём через соединение: свойства самого устройства для этого
    // появились только в iOS 7, а работать надо и на шестой.
    if ([link respondsToSelector:@selector(setVideoMinFrameDuration:)]) {
        link.videoMinFrameDuration = CMTimeMake(1, (int32_t)MAXNoteFrameRate);
    }
    if ([link respondsToSelector:@selector(setVideoMaxFrameDuration:)]) {
        link.videoMaxFrameDuration = CMTimeMake(1, (int32_t)MAXNoteFrameRate);
    }

    _preview = [AVCaptureVideoPreviewLayer layerWithSession:_session];
    _preview.videoGravity = AVLayerVideoGravityResizeAspectFill;
    if ([_preview.connection isVideoOrientationSupported]) {
        _preview.connection.videoOrientation = AVCaptureVideoOrientationPortrait;
    }

    return nil;
}

- (NSString *)buildWriter {
    NSError *error = nil;

    _path = [self freshPath];
    _writer = [[AVAssetWriter alloc] initWithURL:[NSURL fileURLWithPath:_path]
                                        fileType:AVFileTypeMPEG4
                                           error:&error];
    if (_writer == nil) {
        NSLog(@"[Max/Кружок] писать некуда: %@", error.localizedDescription);
        return @"Не удалось начать съёмку";
    }

    // Вот ради чего всё это и написано вручную: сторона ровно 480, обрезка
    // до квадрата вместо вписывания с полями, извод и уровень как у
    // настоящего клиента.
    NSDictionary *video = @{
        AVVideoCodecKey: AVVideoCodecH264,
        AVVideoWidthKey: @(MAXNoteSide),
        AVVideoHeightKey: @(MAXNoteSide),
        AVVideoScalingModeKey: AVVideoScalingModeResizeAspectFill,
        AVVideoCompressionPropertiesKey: @{
            AVVideoAverageBitRateKey: @(MAXNoteBitrate),
            AVVideoMaxKeyFrameIntervalKey: @(MAXNoteFrameRate),
            AVVideoProfileLevelKey: AVVideoProfileLevelH264Main30
        }
    };

    _videoIn = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo
                                                  outputSettings:video];
    _videoIn.expectsMediaDataInRealTime = YES;
    if (![_writer canAddInput:_videoIn]) return @"Не удалось начать съёмку";
    [_writer addInput:_videoIn];

    NSDictionary *audio = @{
        AVFormatIDKey: @(kAudioFormatMPEG4AAC),
        AVSampleRateKey: @(MAXNoteAudioRate),
        AVNumberOfChannelsKey: @(1),
        AVEncoderBitRateKey: @(MAXNoteAudioBitrate)
    };

    _audioIn = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeAudio
                                                  outputSettings:audio];
    _audioIn.expectsMediaDataInRealTime = YES;
    if ([_writer canAddInput:_audioIn]) [_writer addInput:_audioIn];

    return nil;
}

#pragma mark - Кадры

- (void)captureOutput:(AVCaptureOutput *)output
didOutputSampleBuffer:(CMSampleBufferRef)sample
       fromConnection:(AVCaptureConnection *)connection {
    if (_closing || !_recording) return;
    if (!CMSampleBufferDataIsReady(sample)) return;

    BOOL isVideo = (output == _videoOut);

    // Сессию записи начинаем с первого кадра картинки: начни её со звука —
    // и в начале ролика окажется чёрное место длиной в один кадр.
    if (!_writing) {
        if (!isVideo) return;

        if (![_writer startWriting]) {
            NSLog(@"[Max/Кружок] запись не пошла: %@", _writer.error.localizedDescription);
            return;
        }

        [_writer startSessionAtSourceTime:CMSampleBufferGetPresentationTimeStamp(sample)];
        _writing = YES;
    }

    AVAssetWriterInput *input = isVideo ? _videoIn : _audioIn;
    if (input == nil || _closing) return;
    if (!input.isReadyForMoreMediaData) return;

    [input appendSampleBuffer:sample];
}

#pragma mark - Конец

/// Погасить съёмку и отпустить всё, что она держала.
///
/// `stopRunning` уходит на ту же очередь, что и `startRunning`: звать их
/// вперемешку с разных потоков нельзя, а бросить запись успевают ровно
/// в тот миг, когда камера ещё включается.
- (void)teardown {
    AVCaptureSession *session = _session;
    AVCaptureVideoDataOutput *videoOut = _videoOut;
    AVCaptureAudioDataOutput *audioOut = _audioOut;

    if (session != nil) {
        dispatch_async(_sessionQueue, ^{
            [videoOut setSampleBufferDelegate:nil queue:NULL];
            [audioOut setSampleBufferDelegate:nil queue:NULL];
            if (session.isRunning) [session stopRunning];
        });
    }

    _videoOut = nil;
    _audioOut = nil;
    _session = nil;
    _preview = nil;

    _writer = nil;
    _videoIn = nil;
    _audioIn = nil;

    _recording = NO;
    _writing = NO;
}

/// Закончить писать файл — обязательно на очереди кадров.
///
/// Дописать писателя, пока с очереди кадров в него кладут очередной кусок, —
/// это исключение и мгновенная гибель приложения. Поэтому и признак
/// «закрываемся», и само закрытие ставятся в ту же очередь: она одна,
/// и порядок в ней соблюдается сам собой.
- (void)closeWriter:(AVAssetWriter *)writer
            writing:(BOOL)writing
               then:(void (^)(BOOL saved))done {
    dispatch_async(_queue, ^{
        _closing = YES;

        if (!writing || writer.status != AVAssetWriterStatusWriting) {
            done(NO);
            return;
        }

        [writer finishWritingWithCompletionHandler:^{
            done(writer.status == AVAssetWriterStatusCompleted);
        }];
    });
}

- (void)cancel {
    if (!_recording) {
        [self teardown];
        return;
    }

    NSString *path = _path;
    AVAssetWriter *writer = _writer;
    BOOL writing = _writing;

    _recording = NO;

    // Дописывать незачем, но и бросить на полуслове нельзя: писатель держит
    // файл, пока не закончит.
    [self closeWriter:writer writing:writing then:^(BOOL saved) {
        [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
    }];

    [self teardown];
    NSLog(@"[Max/Кружок] съёмка отменена");
}

- (void)stopWithCompletion:(void (^)(MAXNoteTake *take))done {
    if (!_recording) {
        MAXNoteTake *take = [[MAXNoteTake alloc] init];
        take.error = @"Съёмка не шла";
        done(take);
        return;
    }

    NSInteger elapsed = (NSInteger)(self.elapsed * 1000.0);
    NSString *path = _path;
    AVAssetWriter *writer = _writer;
    BOOL writing = _writing;

    _recording = NO;

    __weak MAXVideoNoteRecorder *weakSelf = self;

    [self closeWriter:writer writing:writing then:^(BOOL saved) {
        // Описание дорожек оказывается на диске позже, чем возвращается
        // остановка, — а прочитанное в этот миг обрывается на полуслове.
        // Поэтому читаем уже здесь, когда писатель сам сказал, что закончил.
        MAXNoteTake *take = [[MAXNoteTake alloc] init];
        take.durationMs = elapsed;

        if (saved) take.data = [MAXVideoNoteRecorder readyDataAtPath:path];
        if (take.data.length == 0) take.error = @"Кружок не записался";

        [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];

        dispatch_async(dispatch_get_main_queue(), ^{
            MAXVideoNoteRecorder *strongSelf = weakSelf;
            if (strongSelf != nil) [strongSelf teardown];
            done(take);
        });
    }];
}

/// Прочитать снятое и привести к виду, который берёт сервер.
+ (NSData *)readyDataAtPath:(NSString *)path {
    NSData *shot = [NSData dataWithContentsOfFile:path];
    if (shot.length == 0) return nil;

    // Из чего вышел ролик — в журнал. Сервер о негодном кружке говорит одно
    // слово без подробностей, и разбирать снятое приходится самим.
    NSLog(@"[Max/Кружок] снято: %@", [MAXMp4Facts describe:shot]);

    // Недописанное на сервер не отправляем: он ответит отказом, а человек
    // увидит невнятную ругань вместо простого «не вышло».
    if (![MAXMp4Facts ready:shot]) {
        NSLog(@"[Max/Кружок] файл не дописан — не отправляем");
        return nil;
    }

    NSData *ready = [MAXMp4Facts prepare:shot];
    if (ready == nil) return shot;

    NSLog(@"[Max/Кружок] после правки: %@", [MAXMp4Facts describe:ready]);
    return ready;
}

@end
