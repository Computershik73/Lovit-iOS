//
//  MAXKeyboardDismisser.m
//

#import "MAXKeyboardDismisser.h"

/// Насколько надо протянуть палец вниз, чтобы это считалось смахиванием.
/// Меньше — и клавиатура закрывалась бы от промаха по клавише; больше —
/// и жест приходилось бы делать нарочито длинным.
static const CGFloat MAXKeyboardSwipeThreshold = 44.0;

@interface MAXKeyboardDismisser () <UIGestureRecognizerDelegate>
@end

@implementation MAXKeyboardDismisser {
    UIPanGestureRecognizer *_pan;
    BOOL _dismissedInThisGesture;
}

+ (instancetype)shared {
    static MAXKeyboardDismisser *instance = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        instance = [[MAXKeyboardDismisser alloc] init];
    });
    return instance;
}

+ (void)install {
    [[self shared] start];
}

- (void)start {
    // Ловим появление, а не показ: до этого мгновения окна клавиатуры
    // в списке ещё нет, и цеплять распознаватель не к чему.
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardDidShow:)
                                                 name:UIKeyboardDidShowNotification
                                               object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

/**
 * Окно клавиатуры.
 *
 * Своего имени у него в заголовках нет — это внутренний
 * `UITextEffectsWindow`, — но искать по имени класса и не нужно: обычные окна
 * приложения имеют класс ровно `UIWindow`, а всё остальное в списке
 * принадлежит системе. Для наших целей этого признака достаточно, и он
 * не завязан ни на версию, ни на закрытые имена.
 */
- (UIWindow *)keyboardWindow {
    for (UIWindow *window in [UIApplication sharedApplication].windows) {
        if (![window isMemberOfClass:[UIWindow class]]) return window;
    }
    return nil;
}

- (void)keyboardDidShow:(NSNotification *)note {
    UIWindow *window = [self keyboardWindow];
    if (window == nil) return;
    if (_pan != nil && _pan.view == window) return;

    [_pan.view removeGestureRecognizer:_pan];

    _pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panned:)];
    _pan.delegate = self;

    // Распознаватель только наблюдает. Без этого нажатия на клавиши начали бы
    // теряться: система отдала бы их нам и отменила бы у самой клавиатуры.
    _pan.cancelsTouchesInView = NO;
    _pan.delaysTouchesBegan = NO;
    _pan.delaysTouchesEnded = NO;

    [window addGestureRecognizer:_pan];
}

- (void)panned:(UIPanGestureRecognizer *)recognizer {
    if (recognizer.state == UIGestureRecognizerStateBegan) {
        _dismissedInThisGesture = NO;
        return;
    }

    if (recognizer.state != UIGestureRecognizerStateChanged) return;
    if (_dismissedInThisGesture) return;

    CGPoint moved = [recognizer translationInView:recognizer.view];
    CGPoint speed = [recognizer velocityInView:recognizer.view];

    // Вниз и преимущественно вниз: движение вбок — это выбор буквы на
    // всплывающей клавише, и закрывать по нему нельзя.
    if (moved.y < MAXKeyboardSwipeThreshold) return;
    if (fabs(moved.x) > fabs(moved.y)) return;
    if (speed.y <= 0) return;

    _dismissedInThisGesture = YES;

    // Закрывается через окно, а не через конкретное поле: кто именно сейчас
    // первый отвечающий, знать не нужно, и на каждом экране это своё поле.
    [[UIApplication sharedApplication].keyWindow endEditing:YES];
}

#pragma mark - UIGestureRecognizerDelegate

/// Свои распознаватели у клавиатуры тоже есть — например, вытягивание буквы
/// с долгим нажатием. Работаем рядом, а не вместо них.
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer
shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    return YES;
}

@end
