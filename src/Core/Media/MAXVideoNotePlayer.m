//
//  MAXVideoNotePlayer.m
//

#import "MAXVideoNotePlayer.h"
#import "MAXHttp.h"
#import "MAXMp4Facts.h"

NSString *const MAXVideoNotePlayerDidChangeNotification =
    @"MAXVideoNotePlayerDidChangeNotification";

/// Как часто двигается кольцо. Десять раз в секунду — движение уже плавное,
/// а перерисовка на телефоне тех лет ещё не в тягость.
static const NSTimeInterval MAXNoteTick = 0.1;

@implementation MAXVideoNotePlayer {
    AVPlayer *_player;
    AVPlayerItem *_item;
    AVPlayerLayer *_layer;
    NSTimer *_ticker;
    NSString *_messageId;
    BOOL _preparing;
    /// Растёт на каждом запуске: по нему отбрасывается ответ на отменённое.
    NSUInteger _generation;
}

+ (instancetype)shared {
    static MAXVideoNotePlayer *instance = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [[MAXVideoNotePlayer alloc] init]; });
    return instance;
}

- (NSString *)messageId { return _messageId; }
- (BOOL)preparing { return _preparing; }
- (AVPlayerLayer *)playerLayer { return _layer; }

- (CGFloat)progress {
    if (_item == nil) return 0;

    CMTime whole = _item.duration;
    if (!CMTIME_IS_NUMERIC(whole) || CMTimeGetSeconds(whole) <= 0) return 0;

    CGFloat done = CMTimeGetSeconds(_item.currentTime) / CMTimeGetSeconds(whole);
    if (done < 0) return 0;
    return done > 1.0 ? 1.0 : done;
}

- (void)notify {
    NSDictionary *info = _messageId != nil ? @{@"messageId": _messageId} : @{};
    [[NSNotificationCenter defaultCenter]
     postNotificationName:MAXVideoNotePlayerDidChangeNotification
                   object:self
                 userInfo:info];
}

#pragma mark - Управление

- (void)toggleMessage:(NSString *)messageId url:(NSString *)url {
    if (messageId.length == 0) return;

    if ([messageId isEqualToString:_messageId]) {
        [self stop];
        return;
    }

    [self stop];

    _messageId = [messageId copy];
    _preparing = YES;
    _generation++;

    NSUInteger generation = _generation;
    NSString *wanted = [messageId copy];
    NSString *address = [url copy];

    [self notify];

    __weak MAXVideoNotePlayer *weakSelf = self;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *path = [MAXVideoNotePlayer pathForMessage:wanted];
        NSFileManager *files = [NSFileManager defaultManager];

        if (![files fileExistsAtPath:path]) {
            // Своими руками и своими корнями: у AVFoundation на iOS 6 их
            // не спросишь.
            NSData *video = [MAXHttp dataWithContentsOfURLString:address];

            if (video.length == 0) {
                NSLog(@"[Max/Кружок] запись не скачалась");
                [weakSelf finishPreparing:nil generation:generation];
                return;
            }

            // Из чего состоит скачанное — в журнал, до того как файл попадёт
            // в AVFoundation. Она умеет падать на негодном файле так, что
            // исключение уносит приложение с чужой очереди и поймать его
            // нечем; тогда эта строка окажется последней, и по ней будет
            // видно, чем именно запись не угодила. Сервер кружки не
            // перекодирует — то есть отдаёт обратно ровно то, что мы прислали.
            NSLog(@"[Max/Кружок] скачано: %@", [MAXMp4Facts describe:video]);

            [files createDirectoryAtPath:[path stringByDeletingLastPathComponent]
             withIntermediateDirectories:YES
                              attributes:nil
                                   error:NULL];

            if (![video writeToFile:path atomically:YES]) {
                NSLog(@"[Max/Кружок] запись не легла на диск");
                [weakSelf finishPreparing:nil generation:generation];
                return;
            }
        }

        [weakSelf finishPreparing:path generation:generation];
    });
}

- (void)finishPreparing:(NSString *)path generation:(NSUInteger)generation {
    dispatch_async(dispatch_get_main_queue(), ^{
        // Пока качалось, могли нажать другой кружок или закрыть чат.
        if (generation != _generation) return;

        _preparing = NO;

        if (path == nil) {
            _messageId = nil;
            [self notify];
            return;
        }
        [self playFile:path];
    });
}

- (void)playFile:(NSString *)path {
    NSError *error = nil;

    // Playback, а не Ambient: иначе кружок молчит при выключенном звонке —
    // ровно тогда, когда его чаще всего и смотрят.
    AVAudioSession *session = [AVAudioSession sharedInstance];
    [session setCategory:AVAudioSessionCategoryPlayback error:&error];
    [session setActive:YES error:&error];

    // Под перехватом нарочно: именно здесь AVFoundation и бросала исключение,
    // когда её звала MediaPlayer. Своё исключение хотя бы окажется в журнале,
    // а не унесёт приложение молча.
    @try {
        _item = [AVPlayerItem playerItemWithURL:[NSURL fileURLWithPath:path]];
        _player = [AVPlayer playerWithPlayerItem:_item];

        _layer = [AVPlayerLayer playerLayerWithPlayer:_player];
        _layer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    }
    @catch (NSException *trouble) {
        NSLog(@"[Max/Кружок] проигрыватель не завёлся: %@: %@", trouble.name, trouble.reason);
        [self stop];
        return;
    }

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(itemEnded:)
                                                 name:AVPlayerItemDidPlayToEndTimeNotification
                                               object:_item];

    [_player play];

    [_ticker invalidate];
    _ticker = [NSTimer scheduledTimerWithTimeInterval:MAXNoteTick
                                               target:self
                                             selector:@selector(tick)
                                             userInfo:nil
                                              repeats:YES];
    [self notify];
}

- (void)tick {
    // Сорвалось — в журнал и остановиться: без этого кольцо стояло бы на
    // месте, а человек ждал бы неизвестно чего.
    if (_item.status == AVPlayerItemStatusFailed) {
        NSLog(@"[Max/Кружок] не проигрывается: %@", _item.error.localizedDescription);
        [self stop];
        return;
    }
    [self notify];
}

- (void)itemEnded:(NSNotification *)note {
    [self stop];
}

- (void)stop {
    [_ticker invalidate];
    _ticker = nil;

    if (_item != nil) {
        [[NSNotificationCenter defaultCenter]
         removeObserver:self
                   name:AVPlayerItemDidPlayToEndTimeNotification
                 object:_item];
    }

    [_player pause];
    _player = nil;
    _item = nil;

    [_layer removeFromSuperlayer];
    _layer = nil;

    _preparing = NO;
    _generation++;

    if (_messageId != nil) {
        _messageId = nil;
        [self notify];
    }
}

#pragma mark - Диск

/// Скачанное лежит в Caches: система вправе его стереть, и это не беда —
/// запись скачается заново.
+ (NSString *)pathForMessage:(NSString *)messageId {
    NSArray *dirs = NSSearchPathForDirectoriesInDomains(NSCachesDirectory,
                                                         NSUserDomainMask, YES);
    NSString *folder = [dirs[0] stringByAppendingPathComponent:@"notes"];

    // Номер сообщения приходит с сервера и в имени файла безопасен не всегда.
    NSCharacterSet *allowed = [NSCharacterSet alphanumericCharacterSet];
    NSMutableString *name = [NSMutableString string];
    for (NSUInteger i = 0; i < messageId.length && name.length < 40; i++) {
        unichar c = [messageId characterAtIndex:i];
        [name appendString:([allowed characterIsMember:c]
                            ? [NSString stringWithCharacters:&c length:1]
                            : @"_")];
    }

    return [folder stringByAppendingPathComponent:
            [NSString stringWithFormat:@"%@.mp4", name]];
}

@end
