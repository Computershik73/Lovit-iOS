//
//  MAXPhotoViewController.m
//

#import "MAXPhotoViewController.h"
#import "MAXImageLoader.h"
#import "MAXTheme.h"

@implementation MAXPhotoViewController {
    NSArray *_imageURLs;
    NSUInteger _index;

    UIScrollView *_pager;
    NSMutableArray *_pages;        // область прокрутки на страницу — она же масштабирует
    NSMutableArray *_imageViews;
    NSMutableArray *_spinners;
    NSMutableSet *_loading;        // индексы страниц, которые сейчас едут

    CGSize _laidOutSize;
}

- (id)initWithImageURL:(NSString *)imageURL {
    return [self initWithImageURLs:(imageURL.length > 0 ? @[imageURL] : @[]) startIndex:0];
}

- (id)initWithImageURLs:(NSArray *)imageURLs startIndex:(NSUInteger)startIndex {
    self = [super init];
    if (self) {
        _imageURLs = [imageURLs copy];
        _index = startIndex < _imageURLs.count ? startIndex : 0;
        _loading = [NSMutableSet set];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor blackColor];

    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"Закрыть"
                                         style:[MAXTheme barButtonStyle]
                                        target:self
                                        action:@selector(close)];
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"Сохранить"
                                         style:[MAXTheme barButtonStyle]
                                        target:self
                                        action:@selector(save)];
    self.navigationItem.rightBarButtonItem.enabled = NO;

    _pager = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    _pager.autoresizingMask = UIViewAutoresizingFlexibleWidth
                            | UIViewAutoresizingFlexibleHeight;
    _pager.pagingEnabled = YES;
    _pager.showsHorizontalScrollIndicator = NO;
    _pager.showsVerticalScrollIndicator = NO;
    _pager.backgroundColor = [UIColor blackColor];
    _pager.delegate = self;
    [self.view addSubview:_pager];

    _pages = [NSMutableArray arrayWithCapacity:_imageURLs.count];
    _imageViews = [NSMutableArray arrayWithCapacity:_imageURLs.count];
    _spinners = [NSMutableArray arrayWithCapacity:_imageURLs.count];

    for (NSUInteger i = 0; i < _imageURLs.count; i++) {
        // Масштабирование живёт на странице, а не снаружи: иначе увеличенная
        // картинка и листание боролись бы за одно и то же движение пальцем.
        UIScrollView *page = [[UIScrollView alloc] initWithFrame:CGRectZero];
        page.delegate = self;
        page.minimumZoomScale = 1.0;
        page.maximumZoomScale = 4.0;
        page.showsHorizontalScrollIndicator = NO;
        page.showsVerticalScrollIndicator = NO;
        page.backgroundColor = [UIColor blackColor];
        page.tag = (NSInteger)i;
        [_pager addSubview:page];
        [_pages addObject:page];

        UIImageView *imageView = [[UIImageView alloc] initWithFrame:CGRectZero];
        imageView.contentMode = UIViewContentModeScaleAspectFit;
        [page addSubview:imageView];
        [_imageViews addObject:imageView];

        UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc]
            initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
        spinner.hidesWhenStopped = YES;
        [page addSubview:spinner];
        [_spinners addObject:spinner];
    }

    [self updateTitle];
}

/// Раскладка пересчитывается только при смене размера — на повороте. Делать
/// это на каждом проходе нельзя: возврат contentOffset посреди свайпа выглядел
/// бы как залипание страницы.
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    CGSize size = self.view.bounds.size;
    if (CGSizeEqualToSize(size, _laidOutSize)) return;
    _laidOutSize = size;

    _pager.contentSize = CGSizeMake(size.width * _imageURLs.count, size.height);

    for (NSUInteger i = 0; i < _pages.count; i++) {
        UIScrollView *page = _pages[i];
        page.zoomScale = 1.0;
        page.frame = CGRectMake(size.width * i, 0, size.width, size.height);

        [(UIImageView *)_imageViews[i] setFrame:CGRectMake(0, 0, size.width, size.height)];
        [(UIActivityIndicatorView *)_spinners[i]
            setCenter:CGPointMake(size.width / 2.0, size.height / 2.0)];
    }

    _pager.contentOffset = CGPointMake(size.width * _index, 0);
    [self loadImagesAroundCurrent];
}

#pragma mark - Загрузка

/// Держим в памяти текущую страницу и по соседу с каждой стороны: снимки
/// полноразмерные, и четыре сразу — это уже десятки мегабайт.
- (void)loadImagesAroundCurrent {
    NSUInteger first = _index > 0 ? _index - 1 : 0;
    NSUInteger last = _index + 1;

    for (NSUInteger i = 0; i < _imageURLs.count; i++) {
        if (i >= first && i <= last) {
            [self loadImageAtIndex:i];
            continue;
        }
        [(UIImageView *)_imageViews[i] setImage:nil];
    }
    [self updateSaveButton];
}

- (void)loadImageAtIndex:(NSUInteger)index {
    if (index >= _imageURLs.count) return;

    UIImageView *imageView = _imageViews[index];
    if (imageView.image != nil) return;
    if ([_loading containsObject:@(index)]) return;

    NSString *url = _imageURLs[index];
    if (url.length == 0) return;

    [_loading addObject:@(index)];
    [(UIActivityIndicatorView *)_spinners[index] startAnimating];

    __weak MAXPhotoViewController *weakSelf = self;
    [[MAXImageLoader shared] loadOriginalImageForURL:url completion:^(UIImage *image) {
        MAXPhotoViewController *strongSelf = weakSelf;
        if (strongSelf == nil) return;

        [strongSelf->_loading removeObject:@(index)];
        [(UIActivityIndicatorView *)strongSelf->_spinners[index] stopAnimating];
        [(UIImageView *)strongSelf->_imageViews[index] setImage:image];
        [strongSelf updateSaveButton];
    }];
}

- (UIImage *)currentImage {
    if (_index >= _imageViews.count) return nil;
    return [(UIImageView *)_imageViews[_index] image];
}

- (void)updateSaveButton {
    self.navigationItem.rightBarButtonItem.enabled = [self currentImage] != nil;
}

- (void)updateTitle {
    self.title = _imageURLs.count > 1
        ? [NSString stringWithFormat:@"%lu из %lu",
           (unsigned long)(_index + 1), (unsigned long)_imageURLs.count]
        : @"Фото";
}

#pragma mark - Листание

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if (scrollView != _pager) return;

    CGFloat width = scrollView.bounds.size.width;
    if (width <= 0) return;

    NSUInteger page = (NSUInteger)((scrollView.contentOffset.x + width / 2.0) / width);
    if (page >= _imageURLs.count) page = _imageURLs.count > 0 ? _imageURLs.count - 1 : 0;
    if (page == _index) return;

    // Увеличенная страница, оставленная позади, вернулась бы к нам в том же
    // масштабе — сбрасываем, чтобы соседняя открывалась целиком.
    [(UIScrollView *)_pages[_index] setZoomScale:1.0 animated:NO];

    _index = page;
    [self updateTitle];
    [self loadImagesAroundCurrent];
}

#pragma mark - Действия

- (void)close {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)save {
    UIImage *image = [self currentImage];
    if (image == nil) return;

    UIImageWriteToSavedPhotosAlbum(image, self,
                                   @selector(image:didFinishSavingWithError:contextInfo:), NULL);
}

- (void)image:(UIImage *)image
    didFinishSavingWithError:(NSError *)error
                 contextInfo:(void *)contextInfo {
    id alert = [MAXTheme alertWithTitle:(error == nil ? @"Сохранено" : @"Не сохранилось")
                              message:(error == nil ? @"Фото в плёнке" : error.localizedDescription)
                             delegate:nil
                    cancelButtonTitle:@"OK"
                     otherButtonTitle:nil];
    [alert show];
}

/// Масштабируется страница, но не общая прокрутка: у той своя работа.
- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView {
    if (scrollView == _pager) return nil;

    NSUInteger index = (NSUInteger)scrollView.tag;
    return index < _imageViews.count ? _imageViews[index] : nil;
}

/// Экран показывается и лёжа: смысл полноэкранного просмотра в том и есть.
- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskAll;
}

- (BOOL)shouldAutorotate {
    return YES;
}

@end
