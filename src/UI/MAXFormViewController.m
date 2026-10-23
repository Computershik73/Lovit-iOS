//
//  MAXFormViewController.m
//

#import "MAXFormViewController.h"
#import "MAXTheme.h"

/// Зазор между полем и клавиатурой: впритык поле выглядит прижатым.
static const CGFloat MAXFormGap = 12.0;

@implementation MAXFormViewController {
    CGFloat _offset;
}

@synthesize keyboardHeight = _keyboardHeight;

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [MAXTheme backgroundColor];

    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(keyboardWillShow:)
                   name:UIKeyboardWillShowNotification object:nil];
    [center addObserver:self selector:@selector(keyboardWillHide:)
                   name:UIKeyboardWillHideNotification object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Клавиатура

- (void)keyboardWillShow:(NSNotification *)note {
    CGRect frame = [note.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];

    // Переводим в свои координаты: в системных клавиатура при повороте
    // описывается уже другой стороной прямоугольника.
    CGRect converted = [self.view convertRect:frame fromView:nil];
    _keyboardHeight = self.view.bounds.size.height - converted.origin.y;
    if (_keyboardHeight < 0) _keyboardHeight = 0;

    NSTimeInterval duration = [note.userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    [UIView animateWithDuration:duration animations:^{ [self updateKeyboardOffset]; }];
}

- (void)keyboardWillHide:(NSNotification *)note {
    _keyboardHeight = 0;

    NSTimeInterval duration = [note.userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    [UIView animateWithDuration:duration animations:^{ [self updateKeyboardOffset]; }];
}

/**
 * Сдвигает содержимое вверх ровно настолько, чтобы нижний край активного поля
 * оказался над клавиатурой.
 *
 * Сдвигается `bounds.origin`, а не `frame`: у вида контроллера свои границы
 * задаёт система, и менять их — значит спорить с ней при каждом повороте.
 * Смещение начала координат ту же работу делает, ничего не ломая, и снимается
 * одним присваиванием.
 */
- (void)updateKeyboardOffset {
    CGFloat needed = 0;

    if (_keyboardHeight > 0 && self.activeField != nil) {
        CGRect field = [self.view convertRect:self.activeField.bounds
                                     fromView:self.activeField];
        CGFloat visible = self.view.bounds.size.height - _keyboardHeight;
        CGFloat overlap = CGRectGetMaxY(field) + MAXFormGap - visible - _offset;
        if (overlap > 0) needed = _offset + overlap;
    }

    if (needed == _offset) return;
    _offset = needed;

    CGRect bounds = self.view.bounds;
    bounds.origin.y = needed;
    self.view.bounds = bounds;
}

#pragma mark - UITextFieldDelegate

- (void)textFieldDidBeginEditing:(UITextField *)textField {
    self.activeField = textField;
    [self updateKeyboardOffset];
}

- (void)textFieldDidEndEditing:(UITextField *)textField {
    if (self.activeField == textField) self.activeField = nil;
}

@end
