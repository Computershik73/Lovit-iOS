//
//  MAXWaveView.m
//

#import "MAXWaveView.h"

/// Ширина столбика и промежуток между ними.
static const CGFloat MAXWaveBarWidth = 2.0;
static const CGFloat MAXWaveBarGap = 1.0;

/// Ниже этого столбик не опускается: у тишины посреди речи должна остаться
/// хоть какая-то отметка, иначе в графике появляются провалы до пустоты.
static const CGFloat MAXWaveLeast = 0.12;

@implementation MAXWaveView

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.opaque = NO;
        self.contentMode = UIViewContentModeRedraw;
    }
    return self;
}

- (void)setBars:(NSArray *)bars {
    _bars = bars;
    [self setNeedsDisplay];
}

- (void)setProgress:(CGFloat)progress {
    // Перерисовываем не на каждую долю: полоска двигается десять раз в
    // секунду, а лишняя отрисовка ячейки на старом телефоне заметна.
    if (fabs(progress - _progress) < 0.005) return;
    _progress = progress;
    [self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect {
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGFloat width = self.bounds.size.width;
    CGFloat height = self.bounds.size.height;
    if (width <= 0 || height <= 0) return;

    NSUInteger count = (NSUInteger)floorf((width + MAXWaveBarGap)
                                          / (MAXWaveBarWidth + MAXWaveBarGap));
    if (count == 0) return;

    CGFloat edge = width * _progress;

    for (NSUInteger i = 0; i < count; i++) {
        CGFloat value = MAXWaveLeast;
        if (i < _bars.count) {
            value = [_bars[i] doubleValue];
            if (value < MAXWaveLeast) value = MAXWaveLeast;
            if (value > 1.0) value = 1.0;
        }

        CGFloat bar = height * value;
        CGFloat x = i * (MAXWaveBarWidth + MAXWaveBarGap);
        CGRect frame = CGRectMake(x, (height - bar) / 2.0, MAXWaveBarWidth, bar);

        // Столбик на границе делится: без этого полоска движется рывками по
        // целому столбику, а это заметно.
        if (x + MAXWaveBarWidth <= edge) {
            CGContextSetFillColorWithColor(context, [_playedColor CGColor]);
            CGContextFillRect(context, frame);
            continue;
        }

        if (x >= edge) {
            CGContextSetFillColorWithColor(context, [_restColor CGColor]);
            CGContextFillRect(context, frame);
            continue;
        }

        CGRect played = frame;
        played.size.width = edge - x;
        CGContextSetFillColorWithColor(context, [_playedColor CGColor]);
        CGContextFillRect(context, played);

        CGRect rest = frame;
        rest.origin.x = edge;
        rest.size.width = x + MAXWaveBarWidth - edge;
        CGContextSetFillColorWithColor(context, [_restColor CGColor]);
        CGContextFillRect(context, rest);
    }
}

@end
