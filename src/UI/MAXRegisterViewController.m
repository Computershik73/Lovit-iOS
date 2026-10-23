//
//  MAXRegisterViewController.m
//

#import "MAXRegisterViewController.h"
#import "MAXAppDelegate.h"
#import "MAXTheme.h"
#import "MAXTextField.h"
#import "MAXAccountModule.h"
#import "MAXChatsModule.h"
#import "MAXTokenStorage.h"
#import "MAXProfile.h"

@implementation MAXRegisterViewController {
    UITextField *_firstNameField;
    UITextField *_lastNameField;
    UIButton *_doneButton;
    UILabel *_statusLabel;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"Регистрация";
    self.view.backgroundColor = [MAXTheme backgroundColor];

    _firstNameField = [[MAXTextField alloc] initWithFrame:CGRectZero];
    _firstNameField.placeholder = @"Имя";
    _firstNameField.autocapitalizationType = UITextAutocapitalizationTypeWords;
    _firstNameField.delegate = self;
    [MAXTheme styleTextField:_firstNameField];
    [self.view addSubview:_firstNameField];

    _lastNameField = [[MAXTextField alloc] initWithFrame:CGRectZero];
    _lastNameField.placeholder = @"Фамилия (необязательно)";
    _lastNameField.autocapitalizationType = UITextAutocapitalizationTypeWords;
    _lastNameField.delegate = self;
    [MAXTheme styleTextField:_lastNameField];
    [self.view addSubview:_lastNameField];

    _doneButton = [MAXTheme primaryButtonWithTitle:@"Создать профиль"];
    [_doneButton addTarget:self
                    action:@selector(completeRegistration)
          forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_doneButton];

    _statusLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _statusLabel.numberOfLines = 3;
    _statusLabel.textAlignment = NSTextAlignmentCenter;
    _statusLabel.font = [UIFont systemFontOfSize:13.0];
    _statusLabel.textColor = [MAXTheme secondaryTextColor];
    _statusLabel.backgroundColor = [UIColor clearColor];
    [self.view addSubview:_statusLabel];
}

/// Раскладка — в viewWillLayoutSubviews, как на остальных экранах входа:
/// в viewDidLoad ширина ещё не окончательная и меняется при повороте.
- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];

    CGRect column = [MAXTheme contentColumnInBounds:self.view.bounds];
    CGFloat left = column.origin.x;
    CGFloat width = column.size.width;

    _firstNameField.frame = CGRectMake(left, 30, width, 44);
    _lastNameField.frame = CGRectMake(left, 86, width, 44);
    _doneButton.frame = CGRectMake(left, 146, width, 46);
    _statusLabel.frame = CGRectMake(left, 204, width, 60);
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [_firstNameField becomeFirstResponder];
}

- (void)completeRegistration {
    if (_firstNameField.text.length == 0) {
        _statusLabel.text = @"Введите имя";
        return;
    }

    _doneButton.enabled = NO;
    _statusLabel.text = @"Создаём профиль…";
    [self.view endEditing:YES];

    [[MAXAccountModule shared] completeRegistrationWithToken:_registerToken
                                                   firstName:_firstNameField.text
                                                    lastName:_lastNameField.text
                                                  completion:^(NSDictionary *payload,
                                                               NSError *error) {
        if (error != nil) {
            self->_doneButton.enabled = YES;
            self->_statusLabel.text = error.localizedDescription;

            // Регистрационный ключ у сервера протух — новый берётся только
            // с самого начала, с номера телефона.
            if ([MAXAccountModule isStaleSessionError:error]) {
                [[MAXAppDelegate shared] showAuth];
            }
            return;
        }

        NSString *token = [MAXTokenStorage activeToken];
        long long accountId = [MAXTokenStorage activeAccountId];

        if (token.length == 0) {
            self->_doneButton.enabled = YES;
            self->_statusLabel.text = @"Профиль создан, но токен не сохранён";
            return;
        }

        [[MAXAccountModule shared] loginWithToken:token
                                        accountId:accountId
                                       completion:^(NSDictionary *loginPayload,
                                                    MAXProfile *profile,
                                                    NSError *loginError) {
            if (loginError != nil) {
                self->_doneButton.enabled = YES;
                self->_statusLabel.text = loginError.localizedDescription;
                return;
            }
            [[MAXChatsModule shared] applyLoginPayload:loginPayload
                                         currentUserId:profile.profileId];
            [[MAXAppDelegate shared] showChats];
        }];
    }];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    if (textField == _firstNameField) {
        [_lastNameField becomeFirstResponder];
        return NO;
    }
    [self completeRegistration];
    return NO;
}

@end
