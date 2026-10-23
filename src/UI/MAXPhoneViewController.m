//
//  MAXPhoneViewController.m
//

#import "MAXPhoneViewController.h"
#import "MAXCodeViewController.h"
#import "MAXServerSettingsViewController.h"
#import "MAXTheme.h"
#import "MAXTextField.h"
#import "MAXApi.h"
#import "MAXAccountModule.h"
#import "MAXSpoofingService.h"
#import "MAXSpoofProfile.h"
#import "MAXTokenStorage.h"

@implementation MAXPhoneViewController {
    UILabel *_hintLabel;
    UITextField *_phoneField;
    UIButton *_continueButton;
    UILabel *_statusLabel;
    UIActivityIndicatorView *_spinner;
    BOOL _requesting;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"Вход в MAX";
    self.view.backgroundColor = [MAXTheme backgroundColor];

    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"Сервер"
                                         style:[MAXTheme barButtonStyle]
                                        target:self
                                        action:@selector(openServerSettings)];

    _hintLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _hintLabel.text = @"Введите номер телефона";
    _hintLabel.textAlignment = NSTextAlignmentCenter;
    _hintLabel.font = [UIFont systemFontOfSize:16.0];
    _hintLabel.textColor = [MAXTheme secondaryTextColor];
    _hintLabel.backgroundColor = [UIColor clearColor];
    [self.view addSubview:_hintLabel];

    _phoneField = [[MAXTextField alloc] initWithFrame:CGRectZero];
    _phoneField.placeholder = @"+7 900 000 00 00";
    _phoneField.keyboardType = UIKeyboardTypePhonePad;
    _phoneField.delegate = self;
    [MAXTheme styleTextField:_phoneField];
    [self.view addSubview:_phoneField];

    _continueButton = [MAXTheme primaryButtonWithTitle:@"Получить код"];
    [_continueButton addTarget:self
                        action:@selector(requestCode)
              forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_continueButton];

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

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(sessionStateChanged)
                                                 name:MAXApiStateDidChangeNotification
                                               object:nil];
    [self sessionStateChanged];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

/// Раскладка считается здесь, а не в viewDidLoad: там ширина ещё не
/// окончательная (её правят панели), и она меняется при повороте. На планшете
/// это было особенно заметно — экран, свёрстанный по портретной ширине,
/// в альбомной висел прижатым влево.
- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];

    CGRect column = [MAXTheme contentColumnInBounds:self.view.bounds];
    CGFloat left = column.origin.x;
    CGFloat width = column.size.width;

    _hintLabel.frame = CGRectMake(left, 30, width, 40);
    _phoneField.frame = CGRectMake(left, 80, width, 44);
    _continueButton.frame = CGRectMake(left, 140, width, 46);
    _statusLabel.frame = CGRectMake(left, 200, width, 60);
    _spinner.center = CGPointMake(CGRectGetMidX(self.view.bounds), 270);
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [_phoneField becomeFirstResponder];

    // Профиль подмены готовится до входа и закрепляется за аккаунтом
    // сразу после успешной авторизации.
    if ([MAXSpoofingService profileForScope:MAXSpoofPendingScope] == nil
        && [MAXTokenStorage activeAccountId] == 0) {
        [MAXSpoofingService prepareNewAccountSpoofExcludingAccountIds:@[]];
    }
}

- (void)openServerSettings {
    [self.navigationController pushViewController:[[MAXServerSettingsViewController alloc] init]
                                         animated:YES];
}

- (void)sessionStateChanged {
    MAXSessionState state = [MAXApi shared].state;
    BOOL online = state == MAXSessionStateOnline;

    _continueButton.enabled = online && !_requesting;

    if (_requesting) return;

    switch (state) {
        case MAXSessionStateDisconnected:
            _statusLabel.text = @"Нет соединения с сервером";
            break;
        case MAXSessionStateConnecting:
            _statusLabel.text = @"Подключение…";
            break;
        case MAXSessionStateConnected:
            _statusLabel.text = @"Рукопожатие…";
            break;
        case MAXSessionStateOnline: {
            MAXSpoofProfile *profile = [MAXSpoofingService profileForScope:MAXSpoofPendingScope];
            _statusLabel.text = profile.enabled
                ? [NSString stringWithFormat:@"Сессия готова\nУстройство: %@", profile.deviceName]
                : @"Сессия готова";
            break;
        }
    }
}

- (void)requestCode {
    NSString *phone = _phoneField.text;
    if (phone.length < 5) {
        _statusLabel.text = @"Введите номер полностью";
        return;
    }

    _requesting = YES;
    _continueButton.enabled = NO;
    _statusLabel.text = @"Запрашиваем код…";
    [_spinner startAnimating];
    [_phoneField resignFirstResponder];

    [[MAXAccountModule shared] requestCodeForPhone:phone
                                        completion:^(NSString *token, NSError *error) {
        self->_requesting = NO;
        [self->_spinner stopAnimating];
        [self sessionStateChanged];

        if (error != nil) {
            self->_statusLabel.text = error.localizedDescription;
            return;
        }

        MAXCodeViewController *codeScreen = [[MAXCodeViewController alloc] init];
        codeScreen.authToken = token;
        codeScreen.phone = phone;
        [self.navigationController pushViewController:codeScreen animated:YES];
    }];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [self requestCode];
    return NO;
}

@end
