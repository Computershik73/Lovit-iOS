//
//  MAXVoicePlayer.m
//

#import "MAXVoicePlayer.h"
#import "MAXOpus.h"
#import "MAXHttp.h"
#import <AVFoundation/AVFoundation.h>

NSString *const MAXVoicePlayerDidChangeNotification = @"MAXVoicePlayerDidChangeNotification";

/// Как часто перерисовывается полоска. Десять раз в секунду — движение уже
/// плавное, а перерисовка ячейки на старом телефоне ещё не в тягость.
static const NSTimeInterval MAXVoiceTick = 0.1;

@interface MAXVoicePlayer () <AVAudioPlayerDelegate>
@end

@implementation MAXVoicePlayer {
    AVAudioPlayer *_player;
    NSTimer *_ticker;
    NSString *_messageId;
    BOOL _preparing;
    /// Растёт на каждом запуске: по нему отбрасывается ответ на отменённое.
    NSUInteger _generation;
}

+ (instancetype)shared {
    static MAXVoicePlayer *instance = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [[MAXVoicePlayer alloc] init]; });
    return instance;
}

- (NSString *)messageId { return _messageId; }
- (BOOL)preparing { return _preparing; }
- (BOOL)playing { return _player.isPlaying; }

- (CGFloat)progress {
    if (_player == nil || _player.duration <= 0) return 0;
    CGFloat done = _player.currentTime / _player.duration;
    if (done < 0) return 0;
    return done > 1.0 ? 1.0 : done;
}

- (void)notify {
    NSDictionary *info = _messageId != nil ? @{@"messageId": _messageId} : @{};
    [[NSNotificationCenter defaultCenter] postNotificationName:MAXVoicePlayerDidChangeNotification
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

    // Скачивание и раскодирование — с фоновой очереди: и то и другое на
    // главной означало бы застывший экран на несколько секунд.
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *path = [self wavPathForMessage:wanted];
        NSFileManager *files = [NSFileManager defaultManager];

        if (![files fileExistsAtPath:path]) {
            NSData *ogg = [MAXHttp dataWithContentsOfURLString:address];
            if (ogg.length == 0) {
                [self finishPreparingWithPath:nil generation:generation];
                return;
            }

            NSData *wav = [MAXOpus wavFromOggOpus:ogg];
            if (wav.length == 0) {
                NSLog(@"[Max/Голос] запись не раскодировалась (%lu байт)",
                      (unsigned long)ogg.length);
                [self finishPreparingWithPath:nil generation:generation];
                return;
            }

            [files createDirectoryAtPath:[path stringByDeletingLastPathComponent]
             withIntermediateDirectories:YES
                              attributes:nil
                                   error:NULL];
            [wav writeToFile:path atomically:YES];
        }

        [self finishPreparingWithPath:path generation:generation];
    });
}

- (void)finishPreparingWithPath:(NSString *)path generation:(NSUInteger)generation {
    dispatch_async(dispatch_get_main_queue(), ^{
        // Пока качалось, могли нажать другое голосовое или закрыть чат.
        if (generation != self->_generation) return;

        self->_preparing = NO;

        if (path == nil) {
            self->_messageId = nil;
            [self notify];
            return;
        }
        [self playFile:path];
    });
}

- (void)playFile:(NSString *)path {
    AVAudioSession *session = [AVAudioSession sharedInstance];
    NSError *error = nil;

    // Playback, а не Ambient: иначе голосовое молчит при выключенном звонке —
    // ровно тогда, когда его чаще всего и слушают.
    [session setCategory:AVAudioSessionCategoryPlayback error:&error];
    [session setActive:YES error:&error];

    _player = [[AVAudioPlayer alloc] initWithContentsOfURL:[NSURL fileURLWithPath:path]
                                                     error:&error];
    if (_player == nil) {
        NSLog(@"[Max/Голос] проигрыватель не завёлся: %@", error.localizedDescription);
        _messageId = nil;
        [self notify];
        return;
    }

    _player.delegate = self;
    [_player play];

    [_ticker invalidate];
    _ticker = [NSTimer scheduledTimerWithTimeInterval:MAXVoiceTick
                                               target:self
                                             selector:@selector(tick)
                                             userInfo:nil
                                              repeats:YES];
    [self notify];
}

- (void)tick {
    if (_player.isPlaying) {
        [self notify];
        return;
    }
    // Проигрывание могло кончиться и не через делегата — например, если файл
    // оказался пустым.
    [self stop];
}

- (void)stop {
    [_ticker invalidate];
    _ticker = nil;

    [_player stop];
    _player = nil;

    _preparing = NO;
    _generation++;

    if (_messageId != nil) {
        _messageId = nil;
        [self notify];
    }
}

- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag {
    [self stop];
}

#pragma mark - Диск

/// Раскодированное лежит в Caches: система вправе его стереть, и это не
/// беда — запись раскодируется заново.
- (NSString *)wavPathForMessage:(NSString *)messageId {
    NSArray *dirs = NSSearchPathForDirectoriesInDomains(NSCachesDirectory,
                                                         NSUserDomainMask, YES);
    NSString *folder = [dirs[0] stringByAppendingPathComponent:@"voice"];

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
            [NSString stringWithFormat:@"%@.wav", name]];
}

@end
