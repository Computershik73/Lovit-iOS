//
//  MAXAlertView.m
//

#import "MAXAlertView.h"
#import "MAXTheme.h"
#import "MAXTextField.h"
#import <QuartzCore/QuartzCore.h>

static const CGFloat MAXAlertWidth = 270.0;
static const CGFloat MAXAlertSideMargin = 16.0;
static const CGFloat MAXAlertTopMargin = 19.0;
static const CGFloat MAXAlertButtonHeight = 44.0;
static const CGFloat MAXAlertFieldHeight = 30.0;
static const CGFloat MAXAlertCornerRadius = 7.0;

@implementation MAXAlertView {
    UIView *_box;
    UILabel *_titleLabel;
    UILabel *_messageLabel;
    MAXTextField *_textField;

    NSMutableArray *_titles;    // подписи кнопок по индексам
    NSMutableArray *_buttons;
    NSString *_message;

    CGFloat _keyboardHeight;
}

@synthesize alertViewStyle = _alertViewStyle;
@synthesize delegate = _delegate;
@synthesize cancelButtonIndex = _cancelButtonIndex;

- (id)initWithTitle:(NSString *)title
            message:(NSString *)message
           delegate:(id)delegate
  cancelButtonTitle:(NSString *)cancelButtonTitle
   otherButtonTitle:(NSString *)otherButtonTitle {
    self = [super initWithFrame:CGRectZero];
    if (self == nil) return nil;

    _delegate = delegate;
    _message = [message copy];
    _titles = [NSMutableArray array];
    _buttons = [NSMutableArray array];
    _cancelButtonIndex = -1;

    // Порядок тот же, что у системного: кнопка отмены получает нулевой индекс,
    // остальные идут за ней в порядке добавления.
    if (cancelButtonTitle.length > 0) {
        [_titles addObject:cancelButtonTitle];
        _cancelButtonIndex = 0;
    }
    if (otherButtonTitle.length > 0) [_titles addObject:otherButtonTitle];

    self.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.4];
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

    _box = [[UIView alloc] initWithFrame:CGRectZero];
    _box.backgroundColor = [MAXTheme isDark]
        ? [UIColor colorWithWhite:0.16 alpha:1.0]
        : [UIColor colorWithWhite:0.98 alpha:1.0];
    _box.layer.cornerRadius = MAXAlertCornerRadius;
    _box.clipsToBounds = YES;
    [self addSubview:_box];

    if (title.length > 0) {
        _titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _titleLabel.text = title;
        _titleLabel.font = [UIFont boldSystemFontOfSize:17.0];
        _titleLabel.textColor = [MAXTheme textColor];
        _titleLabel.textAlignment = NSTextAlignmentCenter;
        _titleLabel.numberOfLines = 0;
        _titleLabel.backgroundColor = [UIColor clearColor];
        [_box addSubview:_titleLabel];
    }

    if (message.length > 0) {
        _messageLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _messageLabel.text = message;
        _messageLabel.font = [UIFont systemFontOfSize:14.0];
        _messageLabel.textColor = [MAXTheme textColor];
        _messageLabel.textAlignment = NSTextAlignmentCenter;
        _messageLabel.numberOfLines = 0;
        _messageLabel.backgroundColor = [UIColor clearColor];
        [_box addSubview:_messageLabel];
    }

    return self;
}

/**
 * Поле ввода заводится сразу при выборе стиля, а не при показе.
 *
 * Так же ведёт себя системный `UIAlertView`: место вызова вправе взять поле
 * через `textFieldAtIndex:` до `show` — например, чтобы включить скрытый
 * ввод. Создавай мы его позже, такая настройка молча уходила бы в никуда,
 * и пароль набирался бы открытым текстом.
 */
- (void)setAlertViewStyle:(UIAlertViewStyle)alertViewStyle {
    _alertViewStyle = alertViewStyle;
    if (alertViewStyle != UIAlertViewStylePlainTextInput || _textField != nil) return;

    _textField = [[MAXTextField alloc] initWithFrame:CGRectZero];
    _textField.borderStyle = UITextBorderStyleNone;
    _textField.backgroundColor = [MAXTheme isDark]
        ? [UIColor colorWithWhite:0.24 alpha:1.0]
        : [UIColor whiteColor];
    _textField.textColor = [MAXTheme textColor];
    _textField.font = [UIFont systemFontOfSize:14.0];
    _textField.keyboardAppearance = [MAXTheme keyboardAppearance];
    _textField.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
    _textField.layer.cornerRadius = 4.0;
    _textField.layer.borderWidth = 1.0;
    _textField.layer.borderColor = [[MAXTheme separatorColor] CGColor];
    [_box addSubview:_textField];
}

- (NSInteger)addButtonWithTitle:(NSString *)title {
    [_titles addObject:title];
    return (NSInteger)_titles.count - 1;
}

- (UITextField *)textFieldAtIndex:(NSInteger)index {
    return _textField;
}

#pragma mark - Показ

- (void)show {
    UIWindow *window = [UIApplication sharedApplication].keyWindow;
    if (window == nil) window = [[UIApplication sharedApplication].windows lastObject];
    if (window == nil) return;

    [self buildButtons];

    self.frame = window.bounds;
    [window addSubview:self];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillShow:)
                                                 name:UIKeyboardWillShowNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillHide:)
                                                 name:UIKeyboardWillHideNotification
                                               object:nil];

    [self setNeedsLayout];
    [self layoutIfNeeded];

    // Короб появляется с лёгким уменьшением — так же, как это делает система
    // начиная с iOS 7.
    self.alpha = 0.0;
    _box.transform = CGAffineTransformMakeScale(1.15, 1.15);
    [UIView animateWithDuration:0.2 animations:^{
        self.alpha = 1.0;
        _box.transform = CGAffineTransformIdentity;
    }];

    [_textField becomeFirstResponder];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)buildButtons {
    // Кнопок может не быть вовсе только по недосмотру вызывающего — тогда
    // диалог нечем закрыть, и лучше это заметить сразу.
    if (_titles.count == 0) [_titles addObject:@"OK"];

    for (NSUInteger i = 0; i < _titles.count; i++) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
        button.tag = (NSInteger)i;
        button.titleLabel.font = ((NSInteger)i == _cancelButtonIndex && _titles.count > 1)
            ? [UIFont systemFontOfSize:17.0]
            : [UIFont boldSystemFontOfSize:17.0];
        [button setTitle:_titles[i] forState:UIControlStateNormal];
        [button setTitleColor:[MAXTheme accentColor] forState:UIControlStateNormal];
        [button setTitleColor:[[MAXTheme accentColor] colorWithAlphaComponent:0.4]
                     forState:UIControlStateHighlighted];
        [button addTarget:self action:@selector(buttonTapped:)
         forControlEvents:UIControlEventTouchUpInside];
        [_box addSubview:button];
        [_buttons addObject:button];
    }
}

- (void)buttonTapped:(UIButton *)sender {
    NSInteger index = sender.tag;
    id delegate = _delegate;

    [_textField resignFirstResponder];
    [[NSNotificationCenter defaultCenter] removeObserver:self];

    [UIView animateWithDuration:0.15 animations:^{
        self.alpha = 0.0;
    } completion:^(BOOL finished) {
        [self removeFromSuperview];
    }];

    // Приведение к чужому классу намеренное: у делегата метод объявлен
    // с `UIAlertView *`, а пользуется он только теми именами, которые здесь
    // и реализованы. Менять подпись у всех делегатов ради этого не стоит.
    if ([delegate respondsToSelector:@selector(alertView:clickedButtonAtIndex:)]) {
        [delegate alertView:(UIAlertView *)self clickedButtonAtIndex:index];
    }
}

#pragma mark - Клавиатура

- (void)keyboardWillShow:(NSNotification *)note {
    CGRect frame = [note.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGRect converted = [self convertRect:frame fromView:nil];
    _keyboardHeight = self.bounds.size.height - converted.origin.y;

    [UIView animateWithDuration:[note.userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue]
                     animations:^{ [self layoutSubviews]; }];
}

- (void)keyboardWillHide:(NSNotification *)note {
    _keyboardHeight = 0;
    [UIView animateWithDuration:[note.userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue]
                     animations:^{ [self layoutSubviews]; }];
}

#pragma mark - Раскладка

/// Высота текста при заданной ширине. `sizeWithFont:constrainedToSize:` —
/// то, что есть и на iOS 6, и на 9: `boundingRectWithSize:` появился в iOS 7.
- (CGFloat)heightOfText:(NSString *)text font:(UIFont *)font width:(CGFloat)width {
    if (text.length == 0) return 0;
    CGSize size = [text sizeWithFont:font
                    constrainedToSize:CGSizeMake(width, 10000.0)
                        lineBreakMode:NSLineBreakByWordWrapping];
    return ceilf((float)size.height);
}

- (void)layoutSubviews {
    [super layoutSubviews];

    CGFloat contentWidth = MAXAlertWidth - MAXAlertSideMargin * 2.0;
    CGFloat y = MAXAlertTopMargin;

    if (_titleLabel != nil) {
        CGFloat height = [self heightOfText:_titleLabel.text
                                       font:_titleLabel.font
                                      width:contentWidth];
        _titleLabel.frame = CGRectMake(MAXAlertSideMargin, y, contentWidth, height);
        y += height + 4.0;
    }

    if (_messageLabel != nil) {
        CGFloat height = [self heightOfText:_messageLabel.text
                                       font:_messageLabel.font
                                      width:contentWidth];
        _messageLabel.frame = CGRectMake(MAXAlertSideMargin, y, contentWidth, height);
        y += height;
    }

    if (_textField != nil) {
        y += 12.0;
        _textField.frame = CGRectMake(MAXAlertSideMargin, y, contentWidth, MAXAlertFieldHeight);
        y += MAXAlertFieldHeight;
    }

    y += MAXAlertTopMargin;

    // Две кнопки помещаются в ряд, больше — только столбиком: иначе подписи
    // обрезаются, и «Отмена» становится неотличима от согласия.
    BOOL sideBySide = (_buttons.count == 2);
    CGFloat hairline = 1.0 / [UIScreen mainScreen].scale;

    if (sideBySide) {
        CGFloat half = MAXAlertWidth / 2.0;
        [_buttons[0] setFrame:CGRectMake(0, y, half, MAXAlertButtonHeight)];
        [_buttons[1] setFrame:CGRectMake(half, y, MAXAlertWidth - half, MAXAlertButtonHeight)];
        y += MAXAlertButtonHeight;
    } else {
        for (UIButton *button in _buttons) {
            button.frame = CGRectMake(0, y, MAXAlertWidth, MAXAlertButtonHeight);
            y += MAXAlertButtonHeight;
        }
    }

    _box.bounds = CGRectMake(0, 0, MAXAlertWidth, y);

    // Разделители рисуются поверх, поэтому пересобираются на каждой раскладке:
    // старые убираем, новые кладём по нынешним рамкам кнопок.
    for (UIView *line in [_box subviews]) {
        if (line.tag == 999) [line removeFromSuperview];
    }

    UIView *top = [[UIView alloc] initWithFrame:
                   CGRectMake(0, y - MAXAlertButtonHeight * (sideBySide ? 1 : _buttons.count)
                                 - hairline,
                              MAXAlertWidth, hairline)];
    top.backgroundColor = [MAXTheme separatorColor];
    top.tag = 999;
    [_box addSubview:top];

    for (NSUInteger i = 1; i < _buttons.count; i++) {
        UIButton *button = _buttons[i];
        CGRect frame = sideBySide
            ? CGRectMake(button.frame.origin.x, button.frame.origin.y, hairline,
                         MAXAlertButtonHeight)
            : CGRectMake(0, button.frame.origin.y, MAXAlertWidth, hairline);

        UIView *line = [[UIView alloc] initWithFrame:frame];
        line.backgroundColor = [MAXTheme separatorColor];
        line.tag = 999;
        [_box addSubview:line];
    }

    // Короб держится по центру свободной части экрана: с открытой клавиатурой
    // это верхняя половина, иначе — весь экран.
    CGFloat available = self.bounds.size.height - _keyboardHeight;
    CGFloat centerY = available / 2.0;
    if (centerY < y / 2.0 + 10.0) centerY = y / 2.0 + 10.0;

    _box.center = CGPointMake(self.bounds.size.width / 2.0, centerY);
}

@end
