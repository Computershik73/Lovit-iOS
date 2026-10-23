//
//  MAXStickerPickerViewController.m
//

#import "MAXStickerPickerViewController.h"
#import "MAXStickersModule.h"
#import "MAXSticker.h"
#import "MAXTheme.h"
#import "MAXImageLoader.h"

/// Сторона плитки и промежуток между ними. Четыре в ряд на телефоне тех лет
/// это примерно 70 pt — палец попадает, и стикер ещё узнаваем.
static const CGFloat MAXStickerTileGap = 6.0;
static const CGFloat MAXStickerTabHeight = 44.0;

@implementation MAXStickerPickerViewController {
    UIScrollView *_tabs;
    NSMutableArray *_tabButtons;
    NSInteger _selectedTab;
    UIScrollView *_grid;
    UIActivityIndicatorView *_spinner;
    UILabel *_emptyLabel;

    NSArray *_sets;         // MAXStickerSet, вкладки со второй
    NSArray *_shown;        // MAXSticker текущей вкладки
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"Стикеры";
    self.view.backgroundColor = [MAXTheme backgroundColor];

    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"Отмена"
                                         style:[MAXTheme barButtonStyle]
                                        target:self
                                        action:@selector(cancel)];

    // Вкладки лентой, а не переключателем: наборов у человека бывает
    // полтора десятка, и в переключателе они превращаются в неразличимые
    // полоски по паре точек шириной.
    _tabs = [[UIScrollView alloc] initWithFrame:CGRectZero];
    _tabs.showsHorizontalScrollIndicator = NO;
    _tabs.backgroundColor = [UIColor clearColor];
    [self.view addSubview:_tabs];

    _tabButtons = [NSMutableArray array];
    _selectedTab = -1;

    _grid = [[UIScrollView alloc] initWithFrame:CGRectZero];
    _grid.delegate = self;
    _grid.backgroundColor = [UIColor clearColor];
    [self.view addSubview:_grid];

    _emptyLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _emptyLabel.text = @"Наборов стикеров пока нет";
    _emptyLabel.textAlignment = NSTextAlignmentCenter;
    _emptyLabel.font = [UIFont systemFontOfSize:15.0];
    _emptyLabel.textColor = [MAXTheme secondaryTextColor];
    _emptyLabel.backgroundColor = [UIColor clearColor];
    _emptyLabel.hidden = YES;
    [self.view addSubview:_emptyLabel];

    _spinner = [[UIActivityIndicatorView alloc]
                initWithActivityIndicatorStyle:[MAXTheme activityIndicatorStyle]];
    [self.view addSubview:_spinner];

    [self load];
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];

    CGRect bounds = self.view.bounds;
    _tabs.frame = CGRectMake(0, 4.0, bounds.size.width, MAXStickerTabHeight - 8.0);
    [self layoutTabs];

    CGFloat top = MAXStickerTabHeight + 4.0;
    _grid.frame = CGRectMake(0, top, bounds.size.width, bounds.size.height - top);
    _emptyLabel.frame = CGRectMake(0, top + 40.0, bounds.size.width, 20.0);
    _spinner.center = CGPointMake(bounds.size.width / 2.0, top + 40.0);

    [self layoutTiles];
}

- (void)cancel {
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Загрузка

- (void)load {
    [_spinner startAnimating];

    __weak MAXStickerPickerViewController *weakSelf = self;
    [[MAXStickersModule shared] loadWithCompletion:^(NSError *error) {
        MAXStickerPickerViewController *strongSelf = weakSelf;
        if (strongSelf == nil) return;

        [strongSelf->_spinner stopAnimating];

        if (error != nil) {
            strongSelf->_emptyLabel.text = error.localizedDescription;
            strongSelf->_emptyLabel.hidden = NO;
            return;
        }
        [strongSelf buildTabs];
    }];
}

- (void)buildTabs {
    _sets = [MAXStickersModule shared].sets;

    for (UIButton *button in _tabButtons) [button removeFromSuperview];
    [_tabButtons removeAllObjects];

    NSMutableArray *names = [NSMutableArray arrayWithObject:@"Недавние"];
    for (MAXStickerSet *set in _sets) {
        [names addObject:set.name.length > 0 ? set.name : @"Набор"];
    }

    for (NSUInteger i = 0; i < names.count; i++) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
        button.tag = (NSInteger)i;
        button.titleLabel.font = [UIFont systemFontOfSize:14.0];
        [button setTitle:names[i] forState:UIControlStateNormal];
        [button addTarget:self
                   action:@selector(tabPicked:)
         forControlEvents:UIControlEventTouchUpInside];
        [_tabs addSubview:button];
        [_tabButtons addObject:button];
    }

    [self layoutTabs];
    [self selectTab:0];
}

- (void)layoutTabs {
    CGFloat x = 8.0;
    CGFloat height = _tabs.bounds.size.height;

    for (UIButton *button in _tabButtons) {
        CGFloat width = [button sizeThatFits:CGSizeZero].width + 16.0;
        button.frame = CGRectMake(x, 0, width, height);
        x += width + 4.0;
    }
    _tabs.contentSize = CGSizeMake(x + 4.0, height);
}

- (void)tabPicked:(UIButton *)button {
    [self selectTab:button.tag];
}

- (void)selectTab:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)_tabButtons.count) return;
    _selectedTab = index;

    for (UIButton *button in _tabButtons) {
        BOOL chosen = (button.tag == index);
        [button setTitleColor:(chosen ? [MAXTheme accentColor] : [MAXTheme secondaryTextColor])
                     forState:UIControlStateNormal];
        button.titleLabel.font = chosen ? [UIFont boldSystemFontOfSize:14.0]
                                        : [UIFont systemFontOfSize:14.0];
    }

    if (index == 0) {
        [self showStickers:[MAXStickersModule shared].recent
                     empty:@"Недавних стикеров пока нет"];
        return;
    }

    NSUInteger position = (NSUInteger)index - 1;
    if (position >= _sets.count) return;

    [_spinner startAnimating];
    MAXStickerSet *set = _sets[position];

    __weak MAXStickerPickerViewController *weakSelf = self;
    [[MAXStickersModule shared] stickersOfSet:set completion:^(NSArray *stickers) {
        MAXStickerPickerViewController *strongSelf = weakSelf;
        if (strongSelf == nil) return;

        // Пока набор ехал, вкладку могли переключить — тогда показывать
        // приехавшее нельзя: под пальцем уже другой набор.
        if (strongSelf->_selectedTab != index) return;

        [strongSelf->_spinner stopAnimating];
        [strongSelf showStickers:stickers empty:@"В этом наборе пусто"];
    }];
}

- (void)showStickers:(NSArray *)stickers empty:(NSString *)empty {
    _shown = stickers;

    _emptyLabel.text = empty;
    _emptyLabel.hidden = (stickers.count > 0);

    for (UIView *view in [_grid.subviews copy]) [view removeFromSuperview];

    for (NSUInteger i = 0; i < stickers.count; i++) {
        MAXSticker *sticker = stickers[i];

        UIButton *tile = [UIButton buttonWithType:UIButtonTypeCustom];
        tile.tag = (NSInteger)i;
        tile.backgroundColor = [UIColor clearColor];
        tile.imageView.contentMode = UIViewContentModeScaleAspectFit;
        // Без этого UIKit рисует картинку в её собственном размере по центру
        // кнопки: крупный стикер вылезал за плитку и наезжал на соседние.
        tile.contentHorizontalAlignment = UIControlContentHorizontalAlignmentFill;
        tile.contentVerticalAlignment = UIControlContentVerticalAlignmentFill;
        [tile addTarget:self
                 action:@selector(tilePicked:)
       forControlEvents:UIControlEventTouchUpInside];
        [_grid addSubview:tile];

        [self loadImageForSticker:sticker into:tile];
    }

    [self layoutTiles];
    _grid.contentOffset = CGPointZero;
}

/// Стикеры приходят в WebP — своим разбором занимается загрузчик картинок,
/// тот же, что тянет фотографии в переписке.
- (void)loadImageForSticker:(MAXSticker *)sticker into:(UIButton *)tile {
    if (sticker.url.length == 0) return;

    UIImage *cached = [[MAXImageLoader shared] cachedImageForURL:sticker.url size:0];
    if (cached != nil) {
        [tile setImage:cached forState:UIControlStateNormal];
        return;
    }

    NSInteger position = tile.tag;
    __weak MAXStickerPickerViewController *weakSelf = self;
    [[MAXImageLoader shared] loadOriginalImageForURL:sticker.url completion:^(UIImage *image) {
        MAXStickerPickerViewController *strongSelf = weakSelf;
        if (strongSelf == nil || image == nil) return;

        // Плитки переиспользуются при смене вкладки: сверяем, что на этом
        // месте всё ещё тот самый стикер.
        if (position >= (NSInteger)strongSelf->_shown.count) return;
        MAXSticker *now = strongSelf->_shown[(NSUInteger)position];
        if (now.stickerId != sticker.stickerId) return;

        [tile setImage:image forState:UIControlStateNormal];
    }];
}

- (void)layoutTiles {
    CGFloat width = _grid.bounds.size.width;
    if (width <= 0) return;

    // Столбцов столько, чтобы плитка была около 76 pt: на узком экране их
    // выходит четыре, на планшете — заметно больше.
    NSUInteger columns = (NSUInteger)floorf((width - MAXStickerTileGap) / 82.0);
    if (columns < 3) columns = 3;

    CGFloat side = (width - MAXStickerTileGap * (columns + 1)) / columns;
    NSUInteger index = 0;

    for (UIView *tile in _grid.subviews) {
        if (![tile isKindOfClass:[UIButton class]]) continue;

        NSUInteger column = index % columns;
        NSUInteger row = index / columns;

        tile.frame = CGRectMake(MAXStickerTileGap + column * (side + MAXStickerTileGap),
                                MAXStickerTileGap + row * (side + MAXStickerTileGap),
                                side, side);
        index++;
    }

    NSUInteger rows = (index + columns - 1) / columns;
    _grid.contentSize = CGSizeMake(width,
                                   MAXStickerTileGap + rows * (side + MAXStickerTileGap));
}

- (void)tilePicked:(UIButton *)tile {
    NSUInteger index = (NSUInteger)tile.tag;
    if (index >= _shown.count) return;

    MAXSticker *sticker = _shown[index];
    [[MAXStickersModule shared] noteSent:sticker.stickerId];
    [self.delegate stickerPicker:self didPickSticker:sticker];
}

@end
