//
//  MAXPasswordViewController.m
//

#import "MAXPasswordViewController.h"
#import "MAXAppDelegate.h"
#import "MAXTheme.h"
#import "MAXTextField.h"
#import "MAXAccountModule.h"
#import "MAXChatsModule.h"
#import "MAXProfile.h"
#import "MAXApi.h"

@implementation MAXPasswordViewController {
    UILabel *_introLabel;
    UILabel *_hintLabel;
    UITextField *_passwordField;
    UIButton *_revealButton;
    UIButton *_confirmButton;
    UILabel *_statusLabel;
    UIActivityIndicatorView *_spinner;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"Пароль";
    self.view.backgroundColor = [MAXTheme backgroundColor];

    // Назад с этого экрана вести некуда: код из SMS уже потрачен, и повторная
    // проверка того же кода серверу не понравится. Возврат — только через
    // «Начать заново», то есть к вводу телефона.
    self.navigationItem.hidesBackButton = YES;
    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"Заново"
                                         style:[MAXTheme barButtonStyle]
                                        target:self
                                        action:@selector(startOver)];

    _introLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _introLabel.text = @"У аккаунта включена двухфакторная аутентификация. "
                       @"Введите пароль, чтобы завершить вход.";
    _introLabel.numberOfLines = 3;
    _introLabel.textAlignment = NSTextAlignmentCenter;
    _introLabel.font = [UIFont systemFontOfSize:15.0];
    _introLabel.textColor = [MAXTheme secondaryTextColor];
    _introLabel.backgroundColor = [UIColor clearColor];
    [self.view addSubview:_introLabel];

    if (_hint.length > 0) {
        _hintLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _hintLabel.text = [NSString stringWithFormat:@"Подсказка: %@", _hint];
        _hintLabel.numberOfLines = 2;
        _hintLabel.textAlignment = NSTextAlignmentCenter;
        _hintLabel.font = [UIFont systemFontOfSize:14.0];
        _hintLabel.textColor = [MAXTheme accentColor];
        _hintLabel.backgroundColor = [UIColor clearColor];
        [self.view addSubview:_hintLabel];
    }

    _passwordField = [[MAXTextField alloc] initWithFrame:CGRectZero];
    _passwordField.placeholder = @"Пароль";
    _passwordField.secureTextEntry = YES;
    _passwordField.returnKeyType = UIReturnKeyDone;
    _passwordField.delegate = self;
    [MAXTheme styleTextField:_passwordField];
    [self.view addSubview:_passwordField];

    _revealButton = [MAXTheme plainButtonWithTitle:@""];
    [_revealButton setTitle:@"Показать пароль" forState:UIControlStateNormal];
    [_revealButton addTarget:self
                      action:@selector(toggleReveal)
            forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_revealButton];

    _confirmButton = [MAXTheme primaryButtonWithTitle:@"Войти"];
    [_confirmButton addTarget:self
                       action:@selector(submitPassword)
             forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_confirmButton];

    _statusLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _statusLabel.numberOfLines = 3;
    _statusLabel.textAlignment = NSTextAlignmentCenter;
    _statusLabel.font = [UIFont systemFontOfSize:13.0];
    _statusLabel.textColor = [MAXTheme secondaryTextColor];
    _statusLabel.backgroundColor = [UIColor clearColor];
    [self.view addSubview:_statusLabel];

    _spinner = [[UIActivityIndicatorView alloc]
                initWithActivityIndicatorStyle:[MAXTheme activityIndicatorStyle]];
    [self.view addSubview:_spinner];
}

/// Раскладка сверху вниз с накоплением: подсказка есть не всегда, и всё,
/// что ниже, сдвигается на её высоту. Считается при каждом проходе — ширина
/// в viewDidLoad ещё не окончательная и меняется при повороте.
- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];

    CGRect column = [MAXTheme contentColumnInBounds:self.view.bounds];
    CGFloat left = column.origin.x;
    CGFloat width = column.size.width;
    CGFloat y = 30.0;

    _introLabel.frame = CGRectMake(left, y, width, 60);
    y += 70.0;

    if (_hintLabel != nil) {
        _hintLabel.frame = CGRectMake(left, y, width, 40);
        y += 48.0;
    }

    _passwordField.frame = CGRectMake(left, y, width, 44);
    y += 52.0;

    _revealButton.frame = CGRectMake(left, y, width, 30);
    y += 40.0;

    _confirmButton.frame = CGRectMake(left, y, width, 46);
    y += 58.0;

    _statusLabel.frame = CGRectMake(left, y, width, 60);
    y += 66.0;

    _spinner.center = CGPointMake(CGRectGetMidX(self.view.bounds), y + 10.0);
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [_passwordField becomeFirstResponder];
}

- (void)setBusy:(BOOL)busy status:(NSString *)status {
    _confirmButton.enabled = !busy;
    _revealButton.enabled = !busy;
    _passwordField.enabled = !busy;
    _statusLabel.text = status ?: @"";
    if (busy) [_spinner startAnimating]; else [_spinner stopAnimating];
}

/// Поле с секретным вводом теряет набранное при первом же нажатии после
/// переключения — текст возвращается на место перезаписью.
- (void)toggleReveal {
    BOOL secure = !_passwordField.secureTextEntry;
    NSString *text = _passwordField.text;

    _passwordField.secureTextEntry = secure;
    _passwordField.text = @"";
    _passwordField.text = text;

    [_revealButton setTitle:(secure ? @"Показать пароль" : @"Скрыть пароль")
                   forState:UIControlStateNormal];
}

- (void)startOver {
    [[MAXAppDelegate shared] showAuth];
}

/// Вернуться к вводу номера, сказав почему.
///
/// Без такого выхода застрять можно намертво: сервер отвергает пароль не
/// из-за пароля, а потому что незаконченный вход у него протух, — и
/// повторное «Войти» будет раз за разом посылать тот же негодный ключ.
- (void)startOverBecause:(NSString *)why {
    if (why.length > 0) {
        id alert = [MAXTheme alertWithTitle:@"Вход"
                                    message:why
                                   delegate:nil
                          cancelButtonTitle:@"OK"
                           otherButtonTitle:nil];
        [alert show];
    }
    [self startOver];
}

- (void)submitPassword {
    NSString *password = _passwordField.text;
    if (password.length == 0) {
        _statusLabel.text = @"Введите пароль";
        return;
    }
    if (_trackId.length == 0) {
        _statusLabel.text = @"Сервер не прислал trackId — начните вход заново";
        return;
    }

    // Связь могла оборваться и подняться заново, пока набирали пароль.
    // Незаконченный вход при этом остался в прошлой сессии, и посылать туда
    // пароль бессмысленно: ответом будет отказ, одинаковый на любой пароль.
    if (_authSession != 0 && [MAXApi shared].session != _authSession) {
        [self startOverBecause:@"Связь прерывалась — вход придётся начать заново."];
        return;
    }

    [_passwordField resignFirstResponder];
    [self setBusy:YES status:@"Проверяем пароль…"];

    [[MAXAccountModule shared] checkPassword:password
                                     trackId:_trackId
                                  completion:^(NSString *loginToken,
                                               long long accountId,
                                               NSError *error) {
        if (error != nil) {
            [self setBusy:NO status:error.localizedDescription];

            // Сервер держит незаконченный вход недолго. Протух — тот же ключ
            // не оживёт, сколько «Войти» ни нажимай.
            if ([MAXAccountModule isStaleSessionError:error]) {
                [self startOverBecause:@"Вход устарел — начните заново."];
            }
            return;
        }
        [self performLoginWithToken:loginToken accountId:accountId];
    }];
}

- (void)performLoginWithToken:(NSString *)token accountId:(long long)accountId {
    [self setBusy:YES status:@"Входим…"];

    [[MAXAccountModule shared] loginWithToken:token
                                    accountId:accountId
                                   completion:^(NSDictionary *payload,
                                                MAXProfile *profile,
                                                NSError *error) {
        if (error != nil) {
            [self setBusy:NO status:error.localizedDescription];
            return;
        }

        [[MAXChatsModule shared] applyLoginPayload:payload currentUserId:profile.profileId];
        [[MAXChatsModule shared] paginateChatsFromLoginPayload:payload];
        [self setBusy:NO status:nil];
        [[MAXAppDelegate shared] showChats];
    }];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [self submitPassword];
    return NO;
}

@end
