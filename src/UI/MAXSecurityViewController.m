//
//  MAXSecurityViewController.m
//

#import "MAXSecurityViewController.h"
#import "MAXPasswordSetupViewController.h"
#import "MAXTheme.h"
#import "MAXTwoFactorModule.h"

typedef NS_ENUM(NSInteger, MAXSecuritySection) {
    MAXSecuritySectionStatus = 0,
    MAXSecuritySectionActions,
    MAXSecuritySectionCount
};

@implementation MAXSecurityViewController {
    BOOL _loading;
    BOOL _known;        // ответ от сервера получен
    BOOL _enabled;
    NSString *_email;
    NSString *_hint;
    NSString *_error;

    UIActivityIndicatorView *_spinner;
}

- (id)init {
    return [super initWithStyle:UITableViewStyleGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"Безопасность";
    [MAXTheme applyToTableView:self.tableView];

    _spinner = [[UIActivityIndicatorView alloc]
                initWithActivityIndicatorStyle:[MAXTheme activityIndicatorStyle]];
    _spinner.center = CGPointMake(CGRectGetMidX(self.view.bounds), 120.0);
    _spinner.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin
                              | UIViewAutoresizingFlexibleRightMargin;
    [self.view addSubview:_spinner];

    [self reload];
}

- (void)reload {
    if (_loading) return;
    _loading = YES;
    _error = nil;
    [_spinner startAnimating];
    [self.tableView reloadData];

    __weak MAXSecurityViewController *weakSelf = self;
    [[MAXTwoFactorModule shared] fetchStatusWithCompletion:^(BOOL enabled,
                                                             NSString *email,
                                                             NSString *hint,
                                                             NSError *error) {
        MAXSecurityViewController *strongSelf = weakSelf;
        if (strongSelf == nil) return;

        strongSelf->_loading = NO;
        [strongSelf->_spinner stopAnimating];

        if (error != nil) {
            strongSelf->_error = error.localizedDescription;
        } else {
            strongSelf->_known = YES;
            strongSelf->_enabled = enabled;
            strongSelf->_email = email;
            strongSelf->_hint = hint;
        }
        [strongSelf.tableView reloadData];
    }];
}

#pragma mark - Данные

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return MAXSecuritySectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (_loading || !_known) return section == MAXSecuritySectionStatus ? 1 : 0;

    if (section == MAXSecuritySectionStatus) {
        // Состояние, а под ним почта и подсказка — если сервер их знает.
        return 1 + (_email.length > 0 ? 1 : 0) + (_hint.length > 0 ? 1 : 0);
    }

    // Без пароля — только «Установить»; с паролем — сменить и удалить.
    return _enabled ? 2 : 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return section == MAXSecuritySectionStatus ? @"Пароль для входа" : nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section != MAXSecuritySectionStatus) return nil;

    return @"Когда у аккаунта уже есть сессия, MAX перестаёт слать код в SMS "
           @"и требует пароль. Без него войти на другом устройстве нельзя, "
           @"а задать его можно только там, где вход уже выполнен.";
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc]
                             initWithStyle:UITableViewCellStyleValue1
                             reuseIdentifier:nil];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    [MAXTheme applyToCell:cell indexPath:indexPath inTableView:tableView];
    cell.textLabel.font = [UIFont systemFontOfSize:15.0];

    if (indexPath.section == MAXSecuritySectionStatus) {
        if (_loading) {
            cell.textLabel.text = @"Проверяем…";
            return cell;
        }
        if (!_known) {
            cell.textLabel.text = _error ?: @"Состояние неизвестно";
            cell.textLabel.textColor = [MAXTheme destructiveColor];
            cell.textLabel.numberOfLines = 0;
            return cell;
        }

        NSInteger row = indexPath.row;
        if (row == 0) {
            cell.textLabel.text = @"Состояние";
            cell.detailTextLabel.text = _enabled ? @"задан" : @"не задан";
            return cell;
        }
        if (row == 1 && _email.length > 0) {
            cell.textLabel.text = @"Почта";
            cell.detailTextLabel.text = _email;
            return cell;
        }

        cell.textLabel.text = @"Подсказка";
        cell.detailTextLabel.text = _hint;
        return cell;
    }

    cell.selectionStyle = UITableViewCellSelectionStyleBlue;
    cell.textLabel.textAlignment = NSTextAlignmentCenter;

    if (!_enabled) {
        cell.textLabel.text = @"Установить пароль";
        cell.textLabel.textColor = [MAXTheme accentColor];
        return cell;
    }

    if (indexPath.row == 0) {
        cell.textLabel.text = @"Изменить пароль";
        cell.textLabel.textColor = [MAXTheme accentColor];
    } else {
        cell.textLabel.text = @"Удалить пароль";
        cell.textLabel.textColor = [MAXTheme destructiveColor];
    }
    return cell;
}

#pragma mark - Действия

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section != MAXSecuritySectionActions) return;

    if (_enabled && indexPath.row == 1) {
        [self askPasswordForRemoval];
        return;
    }

    MAXPasswordSetupViewController *setup = [[MAXPasswordSetupViewController alloc] init];
    setup.changingExisting = _enabled;

    __weak MAXSecurityViewController *weakSelf = self;
    setup.completion = ^{ [weakSelf reload]; };

    [self.navigationController pushViewController:setup animated:YES];
}

/// Снятие пароля сервер разрешает только после его подтверждения, поэтому
/// спрашиваем текущий прямо в диалоге — заводить ради одного поля целый
/// экран незачем.
- (void)askPasswordForRemoval {
    id alert = [MAXTheme alertWithTitle:@"Удалить пароль"
                                message:@"Введите текущий пароль. После удаления вход "
                                        @"на новых устройствах снова потребует код из SMS."
                               delegate:self
                      cancelButtonTitle:@"Отмена"
                       otherButtonTitle:@"Удалить"];
    [alert setAlertViewStyle:UIAlertViewStylePlainTextInput];
    [[alert textFieldAtIndex:0] setSecureTextEntry:YES];
    [alert show];
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (buttonIndex == alertView.cancelButtonIndex) return;

    NSString *password = [alertView textFieldAtIndex:0].text;
    if (password.length == 0) return;

    _loading = YES;
    [_spinner startAnimating];
    [self.tableView reloadData];

    __weak MAXSecurityViewController *weakSelf = self;
    [[MAXTwoFactorModule shared] createTrackWithCompletion:^(NSString *trackId, NSError *error) {
        MAXSecurityViewController *strongSelf = weakSelf;
        if (strongSelf == nil) return;
        if (error != nil) {
            [strongSelf finishRemovalWithError:error];
            return;
        }

        [[MAXTwoFactorModule shared] checkCurrentPassword:password
                                                  trackId:trackId
                                               completion:^(NSError *checkError) {
            if (checkError != nil) {
                [strongSelf finishRemovalWithError:checkError];
                return;
            }

            [[MAXTwoFactorModule shared] removePasswordWithTrackId:trackId
                                                        completion:^(NSError *removeError) {
                [strongSelf finishRemovalWithError:removeError];
            }];
        }];
    }];
}

- (void)finishRemovalWithError:(NSError *)error {
    _loading = NO;
    [_spinner stopAnimating];

    if (error != nil) {
        id alert = [MAXTheme alertWithTitle:@"Не удалось"
                                    message:error.localizedDescription
                                   delegate:nil
                          cancelButtonTitle:@"OK"
                           otherButtonTitle:nil];
        [alert show];
        [self.tableView reloadData];
        return;
    }

    [self reload];
}

#pragma mark - Оформление секций

- (void)tableView:(UITableView *)tableView
  willDisplayHeaderView:(UIView *)view
         forSection:(NSInteger)section {
    [MAXTheme applyToHeaderFooterView:view];
}

- (void)tableView:(UITableView *)tableView
  willDisplayFooterView:(UIView *)view
         forSection:(NSInteger)section {
    [MAXTheme applyToHeaderFooterView:view];
}

@end
