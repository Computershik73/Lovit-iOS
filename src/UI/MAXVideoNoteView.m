//
//  MAXVideoNoteView.m
//

#import "MAXVideoNoteView.h"

/// Толщина полоски воспроизведения.
static const CGFloat MAXNoteRingWidth = 3.0;

@implementation MAXVideoNoteView {
    CAShapeLayer *_ring;
    UIActivityIndicatorView *_spinner;
}

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor blackColor];
        self.layer.masksToBounds = YES;

        _ring = [CAShapeLayer layer];
        _ring.fillColor = NULL;
        _ring.strokeColor = [[UIColor whiteColor] CGColor];
        _ring.lineWidth = MAXNoteRingWidth;
        _ring.lineCap = kCALineCapRound;
        // Кольцо поверх кадра, но внутри той же обрезки: полоска идёт по
        // самому краю круга, и срезать её нечему.
        [self.layer addSublayer:_ring];

        _spinner = [[UIActivityIndicatorView alloc]
                    initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
        _spinner.hidesWhenStopped = YES;
        [self addSubview:_spinner];
    }
    return self;
}

- (void)setPlayerLayer:(AVPlayerLayer *)layer {
    if (_playerLayer == layer) return;

    [_playerLayer removeFromSuperlayer];
    _playerLayer = layer;

    if (layer != nil) {
        layer.frame = self.bounds;
        // Под кольцо: иначе кадр закрыл бы полоску.
        [self.layer insertSublayer:layer below:_ring];
    }
}

- (void)setPreparing:(BOOL)preparing {
    _preparing = preparing;
    if (preparing) [_spinner startAnimating];
    else [_spinner stopAnimating];
}

- (void)setProgress:(CGFloat)progress {
    // Перерисовываем не на каждую долю: кольцо двигается десять раз в секунду,
    // а лишняя отрисовка на старом телефоне заметна.
    if (fabs(progress - _progress) < 0.004) return;
    _progress = progress;
    [self refreshRing];
}

- (void)layoutSubviews {
    [super layoutSubviews];

    CGFloat side = MIN(self.bounds.size.width, self.bounds.size.height);
    self.layer.cornerRadius = side / 2.0;

    _playerLayer.frame = self.bounds;
    _ring.frame = self.bounds;
    _spinner.center = CGPointMake(self.bounds.size.width / 2.0,
                                  self.bounds.size.height / 2.0);

    [self refreshRing];
}

- (void)refreshRing {
    CGFloat side = MIN(self.bounds.size.width, self.bounds.size.height);
    if (side <= 0) return;

    // Полоска идёт по краю, отступив на половину своей толщины, — иначе
    // половина её ушла бы за обрезку.
    CGFloat radius = side / 2.0 - MAXNoteRingWidth / 2.0;

    UIBezierPath *path =
        [UIBezierPath bezierPathWithArcCenter:CGPointMake(self.bounds.size.width / 2.0,
                                                          self.bounds.size.height / 2.0)
                                       radius:radius
                                   startAngle:-M_PI_2
                                     endAngle:-M_PI_2 + 2.0 * M_PI * _progress
                                    clockwise:YES];
    _ring.path = [path CGPath];
}

@end
