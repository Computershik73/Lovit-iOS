//
//  MAXStickerSetViewController.m
//

#import "MAXStickerSetViewController.h"
#import "MAXStickersModule.h"
#import "MAXSticker.h"
#import "MAXTheme.h"
#import "MAXImageLoader.h"

/// Промежуток между плитками и высота нижней кнопки.
static const CGFloat MAXSetTileGap = 6.0;
static const CGFloat MAXSetButtonHeight = 46.0;
static const CGFloat MAXSetButtonMargin = 10.0;
static const CGFloat MAXSetCountHeight = 26.0;

/// «3 стикера», «5 стикеров» — окончание зависит от числа.
static NSString *MAXCountOfStickers(NSUInteger count) {
    NSUInteger tail = count % 100;
    NSString *word = @"стикеров";

    if (tail < 11 || tail > 14) {
        switch (count % 10) {
            case 1: word = @"стикер"; break;
            case 2:
            case 3:
            case 4: word = @"стикера"; break;
            default: break;
        }
    }
    return [NSString stringWithFormat:@"%lu %@", (unsigned long)count, word];
}

@implementation MAXStickerSetViewController {
    long long _stickerId;       // с чего начали, если набор ещё неизвестен
    long long _setId;
    MAXStickerSet *_set;
    NSArray *_stickers;         // MAXSticker
    BOOL _busy;                 // идёт добавление или удаление

    UILabel *_countLabel;
    UIScrollView *_grid;
    UIActivityIndicatorView *_spinner;
    UILabel *_notice;
    UIButton *_action;
}

- (id)initWithStickerId:(long long)stickerId {
    self = [super init];
    if (self != nil) _stickerId = stickerId;
    return self;
}

- (id)initWithSetId:(long long)setId {
    self = [super init];
    if (self != nil) _setId = setId;
    return self;
}

#pragma mark - Устройство экрана

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"Набор";
    self.view.backgroundColor = [MAXTheme backgroundColor];

    // Чтобы содержимое не уезжало под панель навигации на iOS 7 и новее.
    if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)]) {
        self.edgesForExtendedLayout = UIRectEdgeNone;
    }

    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"Закрыть"
                                         style:[MAXTheme barButtonStyle]
                                        target:self
                                        action:@selector(close)];

    _countLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _countLabel.textAlignment = NSTextAlignmentCenter;
    _countLabel.font = [UIFont systemFontOfSize:14.0];
    _countLabel.textColor = [MAXTheme secondaryTextColor];
    _countLabel.backgroundColor = [UIColor clearColor];
    _countLabel.hidden = YES;
    [self.view addSubview:_countLabel];

    _grid = [[UIScrollView alloc] initWithFrame:CGRectZero];
    _grid.backgroundColor = [UIColor clearColor];
    [self.view addSubview:_grid];

    _spinner = [[UIActivityIndicatorView alloc]
                initWithActivityIndicatorStyle:[MAXTheme activityIndicatorStyle]];
    _spinner.hidesWhenStopped = YES;
    [self.view addSubview:_spinner];

    _notice = [[UILabel alloc] initWithFrame:CGRectZero];
    _notice.textAlignment = NSTextAlignmentCenter;
    _notice.font = [UIFont systemFontOfSize:15.0];
    _notice.textColor = [MAXTheme secondaryTextColor];
    _notice.backgroundColor = [UIColor clearColor];
    _notice.numberOfLines = 2;
    _notice.hidden = YES;
    [self.view addSubview:_notice];

    _action = [MAXTheme primaryButtonWithTitle:@"Добавить к себе"];
    _action.hidden = YES;
    [_action addTarget:self
                action:@selector(toggleFavorite)
      forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_action];

    [_spinner startAnimating];
    [self load];
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];

    CGRect bounds = self.view.bounds;
    CGFloat bottom = bounds.size.height;

    if (!_action.hidden) {
        CGRect column = [MAXTheme contentColumnInBounds:bounds];
        _action.frame = CGRectMake(column.origin.x,
                                   bottom - MAXSetButtonHeight - MAXSetButtonMargin,
                                   column.size.width, MAXSetButtonHeight);
        bottom = _action.frame.origin.y - MAXSetButtonMargin;
    }

    CGFloat top = 0;
    if (!_countLabel.hidden) {
        _countLabel.frame = CGRectMake(0, 6.0, bounds.size.width, MAXSetCountHeight);
        top = MAXSetCountHeight + 8.0;
    }

    _grid.frame = CGRectMake(0, top, bounds.size.width, MAX(0, bottom - top));
    _spinner.center = CGPointMake(bounds.size.width / 2.0, bounds.size.height / 2.0);
    _notice.frame = CGRectMake(20.0, bounds.size.height / 2.0 - 20.0,
                               bounds.size.width - 40.0, 40.0);

    [self layoutTiles];
}

- (void)close {
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Загрузка

/// Три шага, и каждый следующий нужен только после предыдущего: сначала по
/// номеру стикера находится набор, потом сам набор с именем и составом,
/// потом стикеры этого состава. Заодно спрашивается список своих наборов —
/// без него неизвестно, что писать на кнопке.
- (void)load {
    __weak MAXStickerSetViewController *weakSelf = self;

    if (_setId == 0) {
        [[MAXStickersModule shared] setIdForSticker:_stickerId
                                         completion:^(long long setId) {
            MAXStickerSetViewController *strongSelf = weakSelf;
            if (strongSelf == nil) return;

            if (setId == 0) {
                [strongSelf failWith:@"Не удалось узнать, из какого набора этот стикер"];
                return;
            }
            strongSelf->_setId = setId;
            [strongSelf loadSet];
        }];
        return;
    }

    [self loadSet];
}

- (void)loadSet {
    __weak MAXStickerSetViewController *weakSelf = self;

    [[MAXStickersModule shared] setWithId:_setId completion:^(MAXStickerSet *set) {
        MAXStickerSetViewController *strongSelf = weakSelf;
        if (strongSelf == nil) return;

        if (set == nil) {
            [strongSelf failWith:@"Набор недоступен"];
            return;
        }
        strongSelf->_set = set;

        [[MAXStickersModule shared] stickersOfSet:set completion:^(NSArray *stickers) {
            MAXStickerSetViewController *inner = weakSelf;
            if (inner == nil) return;
            inner->_stickers = stickers;

            [[MAXStickersModule shared] loadFavoritesWithCompletion:^(NSError *error) {
                MAXStickerSetViewController *done = weakSelf;
                if (done == nil) return;
                [done show];
            }];
        }];
    }];
}

- (void)failWith:(NSString *)text {
    [_spinner stopAnimating];
    _notice.text = text;
    _notice.hidden = NO;
    [self.view setNeedsLayout];
}

- (void)show {
    [_spinner stopAnimating];
    _notice.hidden = YES;

    self.title = _set.name.length > 0 ? _set.name : @"Набор";

    // Считаем по составу набора, а не по тому, сколько стикеров доехало:
    // не доехавшие в наборе всё равно есть.
    _countLabel.text = MAXCountOfStickers(_set.stickerIds.count);
    _countLabel.hidden = NO;

    // Кнопка нужна и тогда, когда ни один стикер не показался: набор от
    // этого не перестаёт быть набором, и добавить его к себе можно.
    if (_stickers.count == 0) {
        _notice.text = @"Стикеры не загрузились";
        _notice.hidden = NO;
    }

    [self refreshAction];
    [self fillGrid];
    [self.view setNeedsLayout];
}

/// Надпись на кнопке — по тому, свой уже набор или нет.
- (void)refreshAction {
    BOOL mine = [[MAXStickersModule shared] isFavorite:_setId];

    [_action setTitle:(mine ? @"Убрать из моих" : @"Добавить к себе")
             forState:UIControlStateNormal];
    _action.enabled = !_busy;
    _action.hidden = NO;
}

#pragma mark - Сетка

- (void)fillGrid {
    for (UIView *old in [_grid.subviews copy]) [old removeFromSuperview];

    NSUInteger position = 0;
    for (MAXSticker *sticker in _stickers) {
        UIImageView *tile = [[UIImageView alloc] initWithFrame:CGRectZero];
        tile.contentMode = UIViewContentModeScaleAspectFit;
        tile.backgroundColor = [UIColor clearColor];
        tile.tag = (NSInteger)position;
        [_grid addSubview:tile];

        [self fillTile:tile withSticker:sticker];
        position++;
    }

    [self layoutTiles];
}

/// Стикеры показываются неподвижными — даже те, что умеют двигаться.
/// В наборе их бывает под сотню, и сотня заведённых сцен разом съела бы и
/// память, и всё время устройства; в переписке, где стикер один, они
/// двигаются.
- (void)fillTile:(UIImageView *)tile withSticker:(MAXSticker *)sticker {
    if (sticker.url.length == 0) return;

    UIImage *cached = [[MAXImageLoader shared] cachedImageForURL:sticker.url size:0];
    if (cached != nil) {
        tile.image = cached;
        return;
    }

    NSInteger position = tile.tag;
    long long wanted = sticker.stickerId;
    __weak MAXStickerSetViewController *weakSelf = self;

    [[MAXImageLoader shared] loadOriginalImageForURL:sticker.url
                                         completion:^(UIImage *image) {
        MAXStickerSetViewController *strongSelf = weakSelf;
        if (strongSelf == nil || image == nil) return;

        // Пока качалось, сетку могли заполнить заново.
        if (position >= (NSInteger)strongSelf->_stickers.count) return;
        MAXSticker *now = strongSelf->_stickers[(NSUInteger)position];
        if (now.stickerId != wanted) return;

        tile.image = image;
    }];
}

- (void)layoutTiles {
    CGFloat width = _grid.bounds.size.width;
    if (width <= 0) return;

    // Столбцов столько же, сколько в панели выбора: плитка около 76 pt.
    NSUInteger columns = (NSUInteger)floorf((width - MAXSetTileGap) / 82.0);
    if (columns < 3) columns = 3;

    CGFloat side = (width - MAXSetTileGap * (columns + 1)) / columns;
    NSUInteger index = 0;

    for (UIView *tile in _grid.subviews) {
        if (![tile isKindOfClass:[UIImageView class]]) continue;

        NSUInteger column = index % columns;
        NSUInteger row = index / columns;

        tile.frame = CGRectMake(MAXSetTileGap + column * (side + MAXSetTileGap),
                                MAXSetTileGap + row * (side + MAXSetTileGap),
                                side, side);
        index++;
    }

    NSUInteger rows = (index + columns - 1) / columns;
    _grid.contentSize = CGSizeMake(width,
                                   MAXSetTileGap + rows * (side + MAXSetTileGap));
}

#pragma mark - Добавить и убрать

- (void)toggleFavorite {
    if (_busy || _setId == 0) return;

    BOOL mine = [[MAXStickersModule shared] isFavorite:_setId];
    _busy = YES;
    [self refreshAction];

    __weak MAXStickerSetViewController *weakSelf = self;
    void (^done)(BOOL) = ^(BOOL ok) {
        MAXStickerSetViewController *strongSelf = weakSelf;
        if (strongSelf == nil) return;

        strongSelf->_busy = NO;
        [strongSelf refreshAction];

        if (!ok) {
            id alert = [MAXTheme alertWithTitle:(mine ? @"Не убралось" : @"Не добавилось")
                                        message:@"Сервер не согласился. Попробуйте ещё раз."
                                       delegate:nil
                              cancelButtonTitle:@"OK"
                               otherButtonTitle:nil];
            [alert show];
        }
    };

    if (mine) [[MAXStickersModule shared] unfavoriteSet:_setId completion:done];
    else [[MAXStickersModule shared] favoriteSet:_setId completion:done];
}

@end
