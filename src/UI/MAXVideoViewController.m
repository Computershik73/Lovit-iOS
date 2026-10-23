//
//  MAXVideoViewController.m
//

#import "MAXVideoViewController.h"
#import "MAXTheme.h"
#import <AVFoundation/AVFoundation.h>

/// Через сколько бездействия оверлей прячется.
static const NSTimeInterval MAXVideoIdle = 4.0;

/// Перемотка: назад меньше, чем вперёд. Назад отматывают, чтобы переслушать
/// пропущенное слово, вперёд — чтобы проскочить паузу.
static const NSTimeInterval MAXVideoBack = 5.0;
static const NSTimeInterval MAXVideoForward = 10.0;

static const CGFloat MAXVideoBarHeight = 44.0;

@implementation MAXVideoViewController {
    NSURL *_source;
    NSString *_title;

    AVPlayer *_player;
    AVPlayerItem *_item;
    AVPlayerLayer *_layer;
    id _timeWatcher;

    UIView *_overlay;
    UILabel *_titleLabel;
    UIButton *_closeButton;
    UIButton *_playButton;
    UIButton *_backButton;
    UIButton *_forwardButton;
    UISlider *_slider;
    UILabel *_clock;
    UIActivityIndicatorView *_spinner;

    NSTimer *_hider;
    BOOL _dragging;
}

- (id)initWithFilePath:(NSString *)path title:(NSString *)title {
    self = [super init];
    if (self) {
        _source = [NSURL fileURLWithPath:path];
        _title = [title copy];
    }
    return self;
}

- (id)initWithURL:(NSURL *)url title:(NSString *)title {
    self = [super init];
    if (self) {
        _source = url;
        _title = [title copy];
    }
    return self;
}

- (void)dealloc {
    [_hider invalidate];
    if (_timeWatcher != nil) [_player removeTimeObserver:_timeWatcher];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Постройка

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor blackColor];

    [self buildPlayer];
    [self buildOverlay];

    [self.view addGestureRecognizer:
        [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggleOverlay)]];

    [self showOverlay];
}

- (void)buildPlayer {
    NSError *error = nil;
    AVAudioSession *session = [AVAudioSession sharedInstance];
    [session setCategory:AVAudioSessionCategoryPlayback error:&error];
    [session setActive:YES error:&error];

    // Под перехватом нарочно: именно здесь AVFoundation и бросала исключение,
    // когда её звала MediaPlayer. Своё хотя бы окажется в журнале.
    @try {
        _item = [AVPlayerItem playerItemWithURL:_source];
        _player = [AVPlayer playerWithPlayerItem:_item];

        _layer = [AVPlayerLayer playerLayerWithPlayer:_player];
        _layer.videoGravity = AVLayerVideoGravityResizeAspect;
        _layer.frame = self.view.bounds;
        [self.view.layer addSublayer:_layer];
    }
    @catch (NSException *trouble) {
        NSLog(@"[Max/Видео] проигрыватель не завёлся: %@: %@", trouble.name, trouble.reason);
        return;
    }

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(playedToEnd)
                                                 name:AVPlayerItemDidPlayToEndTimeNotification
                                               object:_item];

    __weak MAXVideoViewController *weakSelf = self;
    _timeWatcher = [_player addPeriodicTimeObserverForInterval:CMTimeMake(1, 4)
                                                         queue:dispatch_get_main_queue()
                                                    usingBlock:^(CMTime time) {
        [weakSelf refreshTime];
    }];

    [_player play];
}

- (UIButton *)barButton:(NSString *)title {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.titleLabel.font = [UIFont systemFontOfSize:15.0];
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [_overlay addSubview:button];
    return button;
}

- (void)buildOverlay {
    _overlay = [[UIView alloc] initWithFrame:self.view.bounds];
    _overlay.backgroundColor = [UIColor clearColor];
    [self.view addSubview:_overlay];

    // Нажатие по оверлею прячет кнопки, нажатие по экрану из-под спрятанного
    // оверлея — показывает. Второй распознаватель нужен именно затем: пока
    // оверлей виден, он и ловит касания, а спрятанный (alpha 0) их
    // пропускает — UIKit не отдаёт касаний почти прозрачным видам.
    [_overlay addGestureRecognizer:
        [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggleOverlay)]];

    UIView *top = [[UIView alloc] initWithFrame:CGRectZero];
    top.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.55];
    top.tag = 1;
    // Затемнение — только вид: касание должно доходить до оверлея под ним.
    top.userInteractionEnabled = NO;
    [_overlay addSubview:top];

    UIView *bottom = [[UIView alloc] initWithFrame:CGRectZero];
    bottom.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.55];
    bottom.tag = 2;
    bottom.userInteractionEnabled = NO;
    [_overlay addSubview:bottom];

    _titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _titleLabel.text = _title.length > 0 ? _title : @"Видео";
    _titleLabel.font = [UIFont systemFontOfSize:15.0];
    _titleLabel.textColor = [UIColor whiteColor];
    _titleLabel.backgroundColor = [UIColor clearColor];
    [_overlay addSubview:_titleLabel];

    _closeButton = [self barButton:@"Закрыть"];
    _backButton = [self barButton:@"↺ 5"];
    _playButton = [self barButton:@"Пауза"];
    _forwardButton = [self barButton:@"10 ↻"];

    [_closeButton addTarget:self action:@selector(close)
           forControlEvents:UIControlEventTouchUpInside];
    [_backButton addTarget:self action:@selector(skipBack)
          forControlEvents:UIControlEventTouchUpInside];
    [_playButton addTarget:self action:@selector(togglePlay)
          forControlEvents:UIControlEventTouchUpInside];
    [_forwardButton addTarget:self action:@selector(skipForward)
             forControlEvents:UIControlEventTouchUpInside];

    _slider = [[UISlider alloc] initWithFrame:CGRectZero];
    _slider.minimumValue = 0.0;
    _slider.maximumValue = 1.0;
    _slider.userInteractionEnabled = YES;
    [_slider addTarget:self action:@selector(sliderTouched)
      forControlEvents:UIControlEventTouchDown];
    [_slider addTarget:self action:@selector(sliderReleased)
      forControlEvents:(UIControlEventTouchUpInside | UIControlEventTouchUpOutside)];
    [_overlay addSubview:_slider];

    _clock = [[UILabel alloc] initWithFrame:CGRectZero];
    _clock.font = [UIFont systemFontOfSize:12.0];
    _clock.textColor = [UIColor whiteColor];
    _clock.textAlignment = NSTextAlignmentRight;
    _clock.backgroundColor = [UIColor clearColor];
    [_overlay addSubview:_clock];

    _spinner = [[UIActivityIndicatorView alloc]
                initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
    [self.view addSubview:_spinner];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    CGRect bounds = self.view.bounds;
    _layer.frame = bounds;
    _overlay.frame = bounds;
    _spinner.center = CGPointMake(CGRectGetMidX(bounds), CGRectGetMidY(bounds));

    for (UIView *shade in _overlay.subviews) {
        if (shade.tag == 1) {
            shade.frame = CGRectMake(0, 0, bounds.size.width, MAXVideoBarHeight);
        } else if (shade.tag == 2) {
            shade.frame = CGRectMake(0, bounds.size.height - MAXVideoBarHeight * 2,
                                     bounds.size.width, MAXVideoBarHeight * 2);
        }
    }

    _closeButton.frame = CGRectMake(8.0, 0, 90.0, MAXVideoBarHeight);
    _titleLabel.frame = CGRectMake(106.0, 0, bounds.size.width - 116.0, MAXVideoBarHeight);

    CGFloat row = bounds.size.height - MAXVideoBarHeight;
    CGFloat third = bounds.size.width / 3.0;

    _backButton.frame = CGRectMake(0, row, third, MAXVideoBarHeight);
    _playButton.frame = CGRectMake(third, row, third, MAXVideoBarHeight);
    _forwardButton.frame = CGRectMake(third * 2.0, row, third, MAXVideoBarHeight);

    CGFloat clockWidth = 92.0;
    _slider.frame = CGRectMake(10.0, row - MAXVideoBarHeight + 8.0,
                               bounds.size.width - clockWidth - 24.0,
                               MAXVideoBarHeight - 16.0);
    _clock.frame = CGRectMake(bounds.size.width - clockWidth - 10.0,
                              row - MAXVideoBarHeight, clockWidth, MAXVideoBarHeight);
}

#pragma mark - Оверлей

- (void)showOverlay {
    _overlay.alpha = 1.0;

    [_hider invalidate];
    _hider = [NSTimer scheduledTimerWithTimeInterval:MAXVideoIdle
                                              target:self
                                            selector:@selector(hideOverlay)
                                            userInfo:nil
                                             repeats:NO];
}

- (void)hideOverlay {
    _hider = nil;

    // Пока тянут полоску, прятать нельзя: она уедет из-под пальца.
    if (_dragging) {
        [self showOverlay];
        return;
    }

    [UIView animateWithDuration:0.25 animations:^{ _overlay.alpha = 0.0; }];
}

- (void)toggleOverlay {
    if (_overlay.alpha > 0.5) [self hideOverlay];
    else [self showOverlay];
}

#pragma mark - Управление

- (void)close {
    [_player pause];
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)togglePlay {
    if (_player.rate != 0.0) {
        [_player pause];
        [_playButton setTitle:@"Играть" forState:UIControlStateNormal];
    } else {
        [_player play];
        [_playButton setTitle:@"Пауза" forState:UIControlStateNormal];
    }
    [self showOverlay];
}

- (void)seekBy:(NSTimeInterval)delta {
    CMTime whole = _item.duration;
    if (!CMTIME_IS_NUMERIC(whole)) return;

    NSTimeInterval at = CMTimeGetSeconds(_item.currentTime) + delta;
    NSTimeInterval last = CMTimeGetSeconds(whole);

    if (at < 0) at = 0;
    if (at > last) at = last;

    [_player seekToTime:CMTimeMakeWithSeconds(at, NSEC_PER_SEC)];
    [self showOverlay];
}

- (void)skipBack { [self seekBy:-MAXVideoBack]; }
- (void)skipForward { [self seekBy:MAXVideoForward]; }

- (void)sliderTouched {
    _dragging = YES;
    [self showOverlay];
}

- (void)sliderReleased {
    _dragging = NO;

    CMTime whole = _item.duration;
    if (CMTIME_IS_NUMERIC(whole)) {
        NSTimeInterval last = CMTimeGetSeconds(whole);
        [_player seekToTime:CMTimeMakeWithSeconds(last * _slider.value, NSEC_PER_SEC)];
    }
    [self showOverlay];
}

- (void)playedToEnd {
    [_player seekToTime:kCMTimeZero];
    [_player pause];
    [_playButton setTitle:@"Играть" forState:UIControlStateNormal];
    [self showOverlay];
}

static NSString *MAXVideoClock(NSTimeInterval seconds) {
    if (seconds < 0 || seconds != seconds) seconds = 0;
    long whole = (long)seconds;
    return [NSString stringWithFormat:@"%ld:%02ld", whole / 60, whole % 60];
}

- (void)refreshTime {
    if (_item.status == AVPlayerItemStatusFailed) {
        [_spinner stopAnimating];
        // Целиком, а не одной подписью: подпись у AVFoundation невнятная
        // («не удалось открыть видео»), а разбираться надо по коду и по
        // вложенной ошибке — там и бывает причина.
        NSError *why = _item.error;
        NSLog(@"[Max/Видео] не проигрывается: %@ (%@ %ld); внутри: %@; %@",
              why.localizedDescription, why.domain, (long)why.code,
              [why.userInfo[NSUnderlyingErrorKey] description],
              why.userInfo[NSLocalizedFailureReasonErrorKey] ?: @"причины нет");

        id alert = [MAXTheme alertWithTitle:@"Видео"
                                    message:(_item.error.localizedDescription
                                             ?: @"Не удалось проиграть")
                                   delegate:nil
                          cancelButtonTitle:@"OK"
                           otherButtonTitle:nil];
        [alert show];
        [self close];
        return;
    }

    if (_item.status != AVPlayerItemStatusReadyToPlay) {
        [_spinner startAnimating];
        return;
    }
    [_spinner stopAnimating];

    CMTime whole = _item.duration;
    if (!CMTIME_IS_NUMERIC(whole)) return;

    NSTimeInterval last = CMTimeGetSeconds(whole);
    NSTimeInterval at = CMTimeGetSeconds(_item.currentTime);

    if (!_dragging && last > 0) _slider.value = at / last;

    _clock.text = [NSString stringWithFormat:@"%@ / %@",
                   MAXVideoClock(at), MAXVideoClock(last)];
}

#pragma mark - Поворот

- (BOOL)shouldAutorotate { return YES; }

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskAll;
}

- (BOOL)prefersStatusBarHidden { return YES; }

@end
