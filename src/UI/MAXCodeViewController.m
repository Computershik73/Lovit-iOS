//
//  MAXCodeViewController.m
//

#import "MAXCodeViewController.h"
#import "MAXRegisterViewController.h"
#import "MAXPasswordViewController.h"
#import "MAXAppDelegate.h"
#import "MAXTheme.h"
#import "MAXTextField.h"
#import "MAXAccountModule.h"
#import "MAXChatsModule.h"
#import "MAXProfile.h"
#import "MAXApi.h"

@implementation MAXCodeViewController {
    UILabel *_hintLabel;
    UITextField *_codeField;
    UIButton *_confirmButton;
    UIButton *_resendButton;
    UILabel *_statusLabel;
    UIActivityIndicatorView *_spinner;
}

/// Раскладка — в viewWillLayoutSubviews: ширина вида в viewDidLoad ещё
/// не окончательная и меняется при повороте (см. MAXPhoneViewController).
- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];

    CGRect column = [MAXTheme contentColumnInBounds:self.view.bounds];
    CGFloat left = column.origin.x;
    CGFloat width = column.size.width;

    _hintLabel.frame = CGRectMake(left, 30, width, 40);
    _codeField.frame = CGRectMake(left, 80, width, 44);
    _confirmButton.frame = CGRectMake(left, 140, width, 46);
    _resendButton.frame = CGRectMake(left, 196, width, 34);
    _statusLabel.frame = CGRectMake(left, 240, width, 60);
    _spinner.center = CGPointMake(CGRectGetMidX(self.view.bounds), 310);
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"Код из SMS";
    self.view.backgroundColor = [MAXTheme backgroundColor];

    _hintLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _hintLabel.text = [NSString stringWithFormat:@"Код отправлен на %@", _phone ?: @""];
    _hintLabel.textAlignment = NSTextAlignmentCenter;
    _hintLabel.font = [UIFont systemFontOfSize:15.0];
    _hintLabel.textColor = [MAXTheme secondaryTextColor];
    _hintLabel.backgroundColor = [UIColor clearColor];
    [self.view addSubview:_hintLabel];

    _codeField = [[MAXTextField alloc] initWithFrame:CGRectZero];
    _codeField.placeholder = @"------";
    _codeField.keyboardType = UIKeyboardTypeNumberPad;
    _codeField.textAlignment = NSTextAlignmentCenter;
    _codeField.delegate = self;
    [MAXTheme styleTextField:_codeField];
    [self.view addSubview:_codeField];

    _confirmButton = [MAXTheme primaryButtonWithTitle:@"Подтвердить"];
    [_confirmButton addTarget:self
                       action:@selector(confirmCode)
             forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_confirmButton];

    _resendButton = [MAXTheme plainButtonWithTitle:@""];
    [_resendButton setTitle:@"Отправить код повторно" forState:UIControlStateNormal];
    [_resendButton addTarget:self
                      action:@selector(resendCode)
            forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_resendButton];

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

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [_codeField becomeFirstResponder];
}

- (void)setBusy:(BOOL)busy status:(NSString *)status {
    _confirmButton.enabled = !busy;
    _resendButton.enabled = !busy;
    _statusLabel.text = status ?: @"";
    if (busy) [_spinner startAnimating]; else [_spinner stopAnimating];
}

- (void)resendCode {
    [self resendCodeWithStatus:@"Отправляем код повторно…" done:@"Код отправлен повторно"];
}

- (void)resendCodeWithStatus:(NSString *)status done:(NSString *)done {
    [self setBusy:YES status:status];

    [[MAXAccountModule shared] resendCodeForPhone:_phone
                                       completion:^(NSString *token, NSError *error) {
        if (error != nil) {
            [self setBusy:NO status:error.localizedDescription];

            // Просить код заново уже некуда: у сервера протух и сам разговор.
            // Остаётся вернуться к номеру — иначе экран станет тупиком.
            if ([MAXAccountModule isStaleSessionError:error]) {
                [[MAXAppDelegate shared] showAuth];
            }
            return;
        }
        self.authToken = token;
        [self setBusy:NO status:done];
    }];
}

- (void)confirmCode {
    NSString *code = _codeField.text;
    if (code.length == 0) {
        _statusLabel.text = @"Введите код";
        return;
    }

    [_codeField resignFirstResponder];
    [self setBusy:YES status:@"Проверяем код…"];

    [[MAXAccountModule shared] verifyCode:code
                                    token:_authToken
                               completion:^(NSDictionary *payload, NSError *error) {
        if (error != nil) {
            // Протухший вход на этом шаге чинится сам: номер мы помним,
            // значит просто просим новый код. Так же поступает Komet —
            // сбрасывать человека к вводу номера из-за того, что связь
            // моргнула, незачем.
            if ([MAXAccountModule isStaleSessionError:error]) {
                [self resendCodeWithStatus:@"Вход устарел — высылаем код заново…"
                                      done:@"Код выслан заново — введите его"];
                return;
            }

            [self setBusy:NO status:error.localizedDescription];
            return;
        }

        // Двухфакторная: вместо токена приходит passwordChallenge, и вход
        // продолжается на экране пароля. Проверять его надо первым — токена
        // в таком ответе нет вовсе.
        NSDictionary *challenge = [MAXAccountModule passwordChallengeFromPayload:payload];
        if (challenge != nil) {
            id trackId = challenge[@"trackId"];
            if (![trackId isKindOfClass:[NSString class]] || [trackId length] == 0) {
                [self setBusy:NO status:@"Нужен пароль, но сервер не прислал trackId"];
                return;
            }

            [self setBusy:NO status:nil];

            MAXPasswordViewController *passwordScreen =
                [[MAXPasswordViewController alloc] init];
            passwordScreen.trackId = trackId;
            passwordScreen.authSession = [MAXApi shared].session;

            id hint = challenge[@"hint"];
            if ([hint isKindOfClass:[NSString class]]) passwordScreen.hint = hint;

            [self.navigationController pushViewController:passwordScreen animated:YES];
            return;
        }

        NSString *loginToken = [MAXAccountModule nestedTokenFromPayload:payload key:@"LOGIN"];
        NSString *registerToken = [MAXAccountModule nestedTokenFromPayload:payload key:@"REGISTER"];

        if (loginToken != nil) {
            [self performLoginWithToken:loginToken
                              accountId:[MAXAccountModule extractAccountId:payload]];
            return;
        }

        if (registerToken != nil) {
            [self setBusy:NO status:nil];
            MAXRegisterViewController *registerScreen = [[MAXRegisterViewController alloc] init];
            registerScreen.registerToken = registerToken;
            [self.navigationController pushViewController:registerScreen animated:YES];
            return;
        }

        [self setBusy:NO status:@"Сервер не вернул токен сессии"];
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
    [self confirmCode];
    return NO;
}

@end
