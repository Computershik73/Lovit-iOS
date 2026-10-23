//
//  MAXPasswordSetupViewController.m
//

#import "MAXPasswordSetupViewController.h"
#import "MAXTheme.h"
#import "MAXTextField.h"
#import "MAXTwoFactorModule.h"

/// Короче шести знаков сервер пароль не примет — проверяем на месте, чтобы
/// не гонять заведомо негодное и не ловить сухое «FAIL».
static const NSUInteger MAXPasswordMinimumLength = 6;

@implementation MAXPasswordSetupViewController {
    UILabel *_introLabel;
    UITextField *_currentField;
    UITextField *_passwordField;
    UITextField *_confirmField;
    UITextField *_hintField;
    UITextField *_emailField;
    UITextField *_codeField;
    UIButton *_submitButton;
    UILabel *_statusLabel;
    UIActivityIndicatorView *_spinner;

    NSString *_trackId;
    BOOL _awaitingEmailCode;   // код с почты уже запрошен
    BOOL _busy;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = _changingExisting ? @"Смена пароля" : @"Пароль для входа";
    self.view.backgroundColor = [MAXTheme backgroundColor];

    _introLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _introLabel.text = _changingExisting
        ? @"Введите текущий пароль и новый — дважды."
        : @"Пароль нужен, чтобы входить в MAX на других устройствах: "
          @"вместо кода в SMS сервер спросит его.";
    _introLabel.numberOfLines = 4;
    _introLabel.textAlignment = NSTextAlignmentCenter;
    _introLabel.font = [UIFont systemFontOfSize:14.0];
    _introLabel.textColor = [MAXTheme secondaryTextColor];
    _introLabel.backgroundColor = [UIColor clearColor];
    [self.view addSubview:_introLabel];

    if (_changingExisting) {
        _currentField = [self addFieldWithPlaceholder:@"Текущий пароль" secure:YES];
    }

    _passwordField = [self addFieldWithPlaceholder:@"Новый пароль" secure:YES];
    _confirmField = [self addFieldWithPlaceholder:@"Повторите пароль" secure:YES];
    _hintField = [self addFieldWithPlaceholder:@"Подсказка (необязательно)" secure:NO];

    // Почта нужна только при первой установке: сменой пароля её привязку
    // не трогают, а отвязывать её отдельным экраном порт пока не умеет.
    if (!_changingExisting) {
        _emailField = [self addFieldWithPlaceholder:@"Почта для восстановления (необязательно)"
                                             secure:NO];
        _emailField.keyboardType = UIKeyboardTypeEmailAddress;

        _codeField = [self addFieldWithPlaceholder:@"Код из письма" secure:NO];
        _codeField.keyboardType = UIKeyboardTypeNumberPad;
        _codeField.hidden = YES;
    }

    _submitButton = [MAXTheme primaryButtonWithTitle:@"Установить пароль"];
    [_submitButton addTarget:self action:@selector(submit)
            forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_submitButton];

    _statusLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _statusLabel.numberOfLines = 4;
    _statusLabel.textAlignment = NSTextAlignmentCenter;
    _statusLabel.font = [UIFont systemFontOfSize:13.0];
    _statusLabel.textColor = [MAXTheme secondaryTextColor];
    _statusLabel.backgroundColor = [UIColor clearColor];
    [self.view addSubview:_statusLabel];

    _spinner = [[UIActivityIndicatorView alloc]
                initWithActivityIndicatorStyle:[MAXTheme activityIndicatorStyle]];
    [self.view addSubview:_spinner];
}

- (UITextField *)addFieldWithPlaceholder:(NSString *)placeholder secure:(BOOL)secure {
    MAXTextField *field = [[MAXTextField alloc] initWithFrame:CGRectZero];
    field.placeholder = placeholder;
    field.secureTextEntry = secure;
    field.returnKeyType = UIReturnKeyNext;
    field.delegate = self;
    [MAXTheme styleTextField:field];
    [self.view addSubview:field];
    return field;
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];

    CGRect column = [MAXTheme contentColumnInBounds:self.view.bounds];
    CGFloat left = column.origin.x;
    CGFloat width = column.size.width;
    CGFloat y = 20.0;

    _introLabel.frame = CGRectMake(left, y, width, 62);
    y += 72.0;

    NSArray *fields = @[_currentField ?: [NSNull null],
                        _passwordField,
                        _confirmField,
                        _hintField,
                        _emailField ?: [NSNull null],
                        _codeField ?: [NSNull null]];

    for (id item in fields) {
        if (item == [NSNull null]) continue;
        UITextField *field = item;
        if (field.hidden) continue;

        field.frame = CGRectMake(left, y, width, 44);
        y += 52.0;
    }

    y += 8.0;
    _submitButton.frame = CGRectMake(left, y, width, 46);
    y += 58.0;

    _statusLabel.frame = CGRectMake(left, y, width, 70);
    _spinner.center = CGPointMake(CGRectGetMidX(self.view.bounds), y + 90.0);
}

#pragma mark - Состояние

- (void)setBusy:(BOOL)busy status:(NSString *)status {
    _busy = busy;
    _submitButton.enabled = !busy;
    _statusLabel.text = status;

    if (busy) {
        [_spinner startAnimating];
    } else {
        [_spinner stopAnimating];
    }
}

- (void)failWithError:(NSError *)error {
    [self setBusy:NO status:error.localizedDescription ?: @"Не удалось"];
}

#pragma mark - Отправка

- (void)submit {
    if (_busy) return;
    [self.view endEditing:YES];

    if (_awaitingEmailCode) {
        [self submitEmailCode];
        return;
    }

    NSString *password = _passwordField.text;
    if (password.length < MAXPasswordMinimumLength) {
        [self setBusy:NO status:[NSString stringWithFormat:
                                 @"Пароль короче %lu знаков сервер не примет.",
                                 (unsigned long)MAXPasswordMinimumLength]];
        return;
    }
    if (![password isEqualToString:_confirmField.text]) {
        [self setBusy:NO status:@"Пароли не совпадают."];
        return;
    }

    [self setBusy:YES status:@"Проверяем…"];

    __weak MAXPasswordSetupViewController *weakSelf = self;
    [[MAXTwoFactorModule shared] createTrackWithCompletion:^(NSString *trackId, NSError *error) {
        MAXPasswordSetupViewController *strongSelf = weakSelf;
        if (strongSelf == nil) return;
        if (error != nil) {
            [strongSelf failWithError:error];
            return;
        }

        strongSelf->_trackId = trackId;
        if (strongSelf->_changingExisting) {
            [strongSelf confirmCurrentPassword];
        } else {
            [strongSelf validateNewPassword];
        }
    }];
}

/// Смена пароля начинается с подтверждения нынешнего — сервер иначе
/// не выдаст новую возможность в этом треке.
- (void)confirmCurrentPassword {
    __weak MAXPasswordSetupViewController *weakSelf = self;
    [[MAXTwoFactorModule shared] checkCurrentPassword:_currentField.text
                                              trackId:_trackId
                                           completion:^(NSError *error) {
        MAXPasswordSetupViewController *strongSelf = weakSelf;
        if (strongSelf == nil) return;
        if (error != nil) {
            [strongSelf failWithError:error];
            return;
        }
        [strongSelf applyNewPassword];
    }];
}

- (void)applyNewPassword {
    __weak MAXPasswordSetupViewController *weakSelf = self;
    [[MAXTwoFactorModule shared] updatePassword:_passwordField.text
                                           hint:_hintField.text
                                        trackId:_trackId
                                     completion:^(NSError *error) {
        MAXPasswordSetupViewController *strongSelf = weakSelf;
        if (strongSelf == nil) return;
        if (error != nil) {
            [strongSelf failWithError:error];
            return;
        }
        [strongSelf finishWithMessage:@"Пароль изменён."];
    }];
}

- (void)validateNewPassword {
    __weak MAXPasswordSetupViewController *weakSelf = self;
    [[MAXTwoFactorModule shared] validatePassword:_passwordField.text
                                          trackId:_trackId
                                       completion:^(NSError *error) {
        MAXPasswordSetupViewController *strongSelf = weakSelf;
        if (strongSelf == nil) return;
        if (error != nil) {
            [strongSelf failWithError:error];
            return;
        }
        [strongSelf validateHintIfNeeded];
    }];
}

- (void)validateHintIfNeeded {
    if (_hintField.text.length == 0) {
        [self requestEmailIfNeeded];
        return;
    }

    __weak MAXPasswordSetupViewController *weakSelf = self;
    [[MAXTwoFactorModule shared] validateHint:_hintField.text
                                      trackId:_trackId
                                   completion:^(NSError *error) {
        MAXPasswordSetupViewController *strongSelf = weakSelf;
        if (strongSelf == nil) return;
        if (error != nil) {
            [strongSelf failWithError:error];
            return;
        }
        [strongSelf requestEmailIfNeeded];
    }];
}

/// Почта необязательна. Если её не указали — пароль ставится сразу; если
/// указали, экран переходит во второй шаг и ждёт код из письма.
- (void)requestEmailIfNeeded {
    NSString *email = _emailField.text;
    if (email.length == 0) {
        [self confirmWithEmail:NO];
        return;
    }

    if ([email rangeOfString:@"@"].location == NSNotFound) {
        [self setBusy:NO status:@"Проверьте адрес почты."];
        return;
    }

    __weak MAXPasswordSetupViewController *weakSelf = self;
    [[MAXTwoFactorModule shared] verifyEmail:email
                                     trackId:_trackId
                                  completion:^(NSError *error) {
        MAXPasswordSetupViewController *strongSelf = weakSelf;
        if (strongSelf == nil) return;
        if (error != nil) {
            [strongSelf failWithError:error];
            return;
        }

        strongSelf->_awaitingEmailCode = YES;
        strongSelf->_codeField.hidden = NO;
        strongSelf->_emailField.enabled = NO;
        [strongSelf->_submitButton setTitle:@"Подтвердить код"
                                    forState:UIControlStateNormal];
        [strongSelf setBusy:NO status:@"Код отправлен на почту."];
        [strongSelf.view setNeedsLayout];
        [strongSelf->_codeField becomeFirstResponder];
    }];
}

- (void)submitEmailCode {
    if (_codeField.text.length == 0) {
        [self setBusy:NO status:@"Введите код из письма."];
        return;
    }

    [self setBusy:YES status:@"Проверяем код…"];

    __weak MAXPasswordSetupViewController *weakSelf = self;
    [[MAXTwoFactorModule shared] checkEmailCode:_codeField.text
                                        trackId:_trackId
                                     completion:^(NSError *error) {
        MAXPasswordSetupViewController *strongSelf = weakSelf;
        if (strongSelf == nil) return;
        if (error != nil) {
            [strongSelf failWithError:error];
            return;
        }
        [strongSelf confirmWithEmail:YES];
    }];
}

- (void)confirmWithEmail:(BOOL)withEmail {
    [self setBusy:YES status:@"Устанавливаем пароль…"];

    __weak MAXPasswordSetupViewController *weakSelf = self;
    [[MAXTwoFactorModule shared] confirmWithTrackId:_trackId
                                            password:_passwordField.text
                                                hint:_hintField.text
                                           withEmail:withEmail
                                          completion:^(NSError *error) {
        MAXPasswordSetupViewController *strongSelf = weakSelf;
        if (strongSelf == nil) return;
        if (error != nil) {
            [strongSelf failWithError:error];
            return;
        }
        [strongSelf finishWithMessage:@"Пароль установлен."];
    }];
}

- (void)finishWithMessage:(NSString *)message {
    [self setBusy:NO status:message];
    if (_completion != nil) _completion();

    id alert = [MAXTheme alertWithTitle:message
                                message:@"Теперь вход на новом устройстве спросит его "
                                        @"вместо кода из SMS."
                               delegate:nil
                      cancelButtonTitle:@"OK"
                       otherButtonTitle:nil];
    [alert show];

    [self.navigationController popViewControllerAnimated:YES];
}

#pragma mark - UITextFieldDelegate

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return NO;
}

@end
