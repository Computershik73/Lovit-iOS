//
//  MAXAvatarView.m
//

#import "MAXAvatarView.h"
#import "MAXImageLoader.h"

@implementation MAXAvatarView {
    UIImageView *_imageView;
    UILabel *_letterLabel;
    long long _identifier;
    NSString *_shownUrl;
}

/// Палитра заглушек. Оттенки взяты приглушённые: поверх них лежит белая буква,
/// и на светлых фонах она бы терялась.
+ (NSArray *)placeholderColors {
    static NSArray *colors = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        colors = @[
            [UIColor colorWithRed:0.36 green:0.55 blue:0.90 alpha:1.0],
            [UIColor colorWithRed:0.42 green:0.31 blue:0.85 alpha:1.0],
            [UIColor colorWithRed:0.20 green:0.68 blue:0.55 alpha:1.0],
            [UIColor colorWithRed:0.91 green:0.45 blue:0.32 alpha:1.0],
            [UIColor colorWithRed:0.85 green:0.35 blue:0.56 alpha:1.0],
            [UIColor colorWithRed:0.95 green:0.63 blue:0.22 alpha:1.0],
            [UIColor colorWithRed:0.30 green:0.60 blue:0.75 alpha:1.0]
        ];
    });
    return colors;
}

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.opaque = NO;

        _letterLabel = [[UILabel alloc] initWithFrame:self.bounds];
        _letterLabel.textAlignment = NSTextAlignmentCenter;
        _letterLabel.textColor = [UIColor whiteColor];
        _letterLabel.backgroundColor = [UIColor clearColor];
        _letterLabel.font = [UIFont systemFontOfSize:frame.size.width * 0.42];
        _letterLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth
                                      | UIViewAutoresizingFlexibleHeight;
        [self addSubview:_letterLabel];

        _imageView = [[UIImageView alloc] initWithFrame:self.bounds];
        _imageView.autoresizingMask = UIViewAutoresizingFlexibleWidth
                                    | UIViewAutoresizingFlexibleHeight;
        _imageView.hidden = YES;
        [self addSubview:_imageView];
    }
    return self;
}

/// Круг рисуется сам, а не слоем с cornerRadius: маска слоя на iOS 6 —
/// это отрисовка за кадром для каждой ячейки на каждом кадре прокрутки.
- (void)drawRect:(CGRect)rect {
    if (!_imageView.hidden) return;

    NSArray *colors = [MAXAvatarView placeholderColors];
    NSUInteger index = (NSUInteger)(llabs(_identifier) % (long long)colors.count);

    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextSetFillColorWithColor(context, [colors[index] CGColor]);
    CGContextFillEllipseInRect(context, self.bounds);
}

- (void)setTitle:(NSString *)title
       avatarURL:(NSString *)avatarURL
      identifier:(long long)identifier {
    _identifier = identifier;

    NSString *letter = @"?";
    NSString *trimmed = [title stringByTrimmingCharactersInSet:
                         [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length > 0) {
        letter = [[trimmed substringToIndex:1] uppercaseString];
    }
    _letterLabel.text = letter;

    _shownUrl = [avatarURL copy];

    _imageView.image = nil;
    _imageView.hidden = YES;
    [self setNeedsDisplay];

    if (avatarURL.length == 0) return;

    CGFloat size = self.bounds.size.width;

    UIImage *ready = [[MAXImageLoader shared] cachedImageForURL:avatarURL size:size];
    if (ready != nil) {
        _imageView.image = ready;
        _imageView.hidden = NO;
        return;
    }

    // Ячейку могли переиспользовать, пока картинка ехала: сверяем, что на
    // месте всё тот же собеседник, иначе аватарка встанет не в тот ряд.
    //
    // Одного номера мало. Строку списка переиспользуют и под тот же чат —
    // а адрес значка у него мог за это время смениться (или, наоборот,
    // пропасть). Приехавшая с опозданием старая картинка тогда ложилась
    // поверх новой и держалась до перезапуска приложения. Поэтому сверяем
    // ещё и адрес: он и есть то, что заказывали.
    long long requested = identifier;
    NSString *requestedUrl = [avatarURL copy];
    __weak MAXAvatarView *weakSelf = self;
    [[MAXImageLoader shared] loadImageForURL:avatarURL size:size completion:^(UIImage *image) {
        MAXAvatarView *strongSelf = weakSelf;
        if (strongSelf == nil || image == nil) return;
        if (strongSelf->_identifier != requested) return;
        if (![strongSelf->_shownUrl isEqualToString:requestedUrl]) return;
        strongSelf->_imageView.image = image;
        strongSelf->_imageView.hidden = NO;
    }];
}

@end
