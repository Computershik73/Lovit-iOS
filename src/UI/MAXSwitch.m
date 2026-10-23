//
//  MAXSwitch.m
//

#import "MAXSwitch.h"
#import "MAXTheme.h"
#import <QuartzCore/QuartzCore.h>

static const CGFloat MAXSwitchWidth = 51.0;
static const CGFloat MAXSwitchHeight = 31.0;
static const CGFloat MAXSwitchBorder = 1.5;
static const CGFloat MAXSwitchKnobInset = 2.0;

@implementation MAXSwitch {
    UIView *_track;      // дорожка: она же рамка в выключенном состоянии
    UIView *_fill;       // зелёная заливка, проявляется при включении
    UIView *_knob;
}

@synthesize on = _on;

+ (CGSize)standardSize {
    return CGSizeMake(MAXSwitchWidth, MAXSwitchHeight);
}

- (id)initWithFrame:(CGRect)frame {
    // Размер системный и не обсуждается: переключатель лежит в accessoryView
    // ячейки, где его никто не растягивает, а пропорции у него узнаваемые.
    frame.size = [MAXSwitch standardSize];

    self = [super initWithFrame:frame];
    if (self == nil) return nil;

    CGRect bounds = CGRectMake(0, 0, MAXSwitchWidth, MAXSwitchHeight);
    CGFloat radius = MAXSwitchHeight / 2.0;

    _track = [[UIView alloc] initWithFrame:bounds];
    _track.layer.cornerRadius = radius;
    _track.layer.borderWidth = MAXSwitchBorder;
    _track.userInteractionEnabled = NO;
    [self addSubview:_track];

    // Заливка отдельным видом, а не сменой цвета дорожки: так включение
    // можно показать ростом из середины, как это делает система.
    _fill = [[UIView alloc] initWithFrame:bounds];
    _fill.layer.cornerRadius = radius;
    _fill.userInteractionEnabled = NO;
    [self addSubview:_fill];

    CGFloat knobSize = MAXSwitchHeight - MAXSwitchKnobInset * 2.0;
    _knob = [[UIView alloc] initWithFrame:
             CGRectMake(MAXSwitchKnobInset, MAXSwitchKnobInset, knobSize, knobSize)];
    _knob.backgroundColor = [UIColor whiteColor];
    _knob.layer.cornerRadius = knobSize / 2.0;
    _knob.layer.shadowColor = [[UIColor blackColor] CGColor];
    _knob.layer.shadowOffset = CGSizeMake(0, 1.0);
    _knob.layer.shadowRadius = 1.5;
    _knob.layer.shadowOpacity = 0.25;
    _knob.layer.shadowPath = [[UIBezierPath bezierPathWithOvalInRect:
                               CGRectMake(0, 0, knobSize, knobSize)] CGPath];
    _knob.userInteractionEnabled = NO;
    [self addSubview:_knob];

    [self addTarget:self action:@selector(toggle) forControlEvents:UIControlEventTouchUpInside];

    [self applyColors];
    [self layoutForState:NO];

    return self;
}

- (CGSize)sizeThatFits:(CGSize)size {
    return [MAXSwitch standardSize];
}

/**
 * Цвета и объём под выбранный стиль.
 *
 * Своя отрисовка включается там, где системного вида не добиться, — и рисовать
 * она обязана именно выбранный стиль, а не всегда плоский. Иначе на iOS 7
 * со скевоморфизмом получается ровно то, ради чего всё и затевалось наоборот:
 * вокруг объём, а переключатель плоский.
 */
- (void)applyColors {
    BOOL dark = [MAXTheme isDark];
    BOOL skeuomorphic = [MAXTheme isSkeuomorphic];

    _track.backgroundColor = dark ? [UIColor colorWithWhite:0.22 alpha:1.0]
                                  : [UIColor whiteColor];
    _track.layer.borderColor = [(dark ? [UIColor colorWithWhite:0.32 alpha:1.0]
                                      : [UIColor colorWithRed:0.898 green:0.898
                                                          blue:0.918 alpha:1.0]) CGColor];

    // Зелёный тумблер — черта iOS 7; до неё включённое состояние было синим
    // и глянцевым.
    _fill.backgroundColor = skeuomorphic
        ? [UIColor colorWithRed:0.153 green:0.451 blue:0.804 alpha:1.0]
        : [UIColor colorWithRed:0.298 green:0.851 blue:0.392 alpha:1.0];

    [self applyDepth:skeuomorphic];
}

/// Объём: утопленная дорожка, блик на заливке и выпуклая ручка. Слои
/// добавляются один раз — размер у переключателя постоянный.
- (void)applyDepth:(BOOL)skeuomorphic {
    if (!skeuomorphic) {
        _track.layer.borderWidth = MAXSwitchBorder;
        _knob.layer.borderWidth = 0.0;
        [self removeGlossLayers];
        return;
    }

    _track.layer.borderWidth = 1.0;
    _track.layer.borderColor = [[UIColor colorWithWhite:0.55 alpha:1.0] CGColor];

    _knob.layer.borderWidth = 1.0;
    _knob.layer.borderColor = [[UIColor colorWithWhite:0.62 alpha:1.0] CGColor];
    _knob.layer.shadowOpacity = 0.4;

    [self addGlossTo:_track
                from:[UIColor colorWithWhite:0.78 alpha:1.0]
                  to:[UIColor colorWithWhite:1.00 alpha:1.0]];
    [self addGlossTo:_fill
                from:[UIColor colorWithWhite:1.0 alpha:0.45]
                  to:[UIColor colorWithWhite:1.0 alpha:0.0]];
    [self addGlossTo:_knob
                from:[UIColor colorWithWhite:1.00 alpha:1.0]
                  to:[UIColor colorWithWhite:0.86 alpha:1.0]];
}

- (void)addGlossTo:(UIView *)view from:(UIColor *)top to:(UIColor *)bottom {
    for (CALayer *layer in [view.layer.sublayers copy]) {
        if ([layer.name isEqualToString:@"MAXSwitchGloss"]) [layer removeFromSuperlayer];
    }

    CAGradientLayer *gloss = [CAGradientLayer layer];
    gloss.name = @"MAXSwitchGloss";
    gloss.frame = view.bounds;
    gloss.cornerRadius = view.layer.cornerRadius;
    gloss.colors = @[(id)[top CGColor], (id)[bottom CGColor]];
    [view.layer insertSublayer:gloss atIndex:0];
}

- (void)removeGlossLayers {
    for (UIView *view in @[_track, _fill, _knob]) {
        for (CALayer *layer in [view.layer.sublayers copy]) {
            if ([layer.name isEqualToString:@"MAXSwitchGloss"]) [layer removeFromSuperlayer];
        }
    }
}

/// Положение ручки и вид заливки под текущее состояние.
- (void)layoutForState:(BOOL)animated {
    CGFloat knobSize = MAXSwitchHeight - MAXSwitchKnobInset * 2.0;
    CGFloat x = _on ? MAXSwitchWidth - knobSize - MAXSwitchKnobInset : MAXSwitchKnobInset;

    void (^apply)(void) = ^{
        CGRect knobFrame = _knob.frame;
        knobFrame.origin.x = x;
        _knob.frame = knobFrame;

        // Выключенное состояние — заливка, схлопнутая в точку под ручкой:
        // так включение выглядит как разлив цвета, а не как подмена картинки.
        _fill.alpha = _on ? 1.0 : 0.0;
        _fill.transform = _on ? CGAffineTransformIdentity
                              : CGAffineTransformMakeScale(0.01, 0.01);
    };

    if (animated) {
        [UIView animateWithDuration:0.22
                              delay:0
                            options:UIViewAnimationOptionCurveEaseOut
                         animations:apply
                         completion:nil];
    } else {
        apply();
    }
}

- (void)toggle {
    [self setOn:!_on animated:YES];
    [self sendActionsForControlEvents:UIControlEventValueChanged];
}

- (void)setOn:(BOOL)on {
    [self setOn:on animated:NO];
}

- (void)setOn:(BOOL)on animated:(BOOL)animated {
    if (_on == on) return;
    _on = on;
    [self layoutForState:animated];
}

@end
