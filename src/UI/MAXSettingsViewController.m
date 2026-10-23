//
//  MAXSettingsViewController.m
//

#import "MAXSettingsViewController.h"
#import "MAXSpoofViewController.h"
#import "MAXServerSettingsViewController.h"
#import "MAXAboutViewController.h"
#import "MAXSecurityViewController.h"
#import "MAXWallpaperViewController.h"
#import "MAXAppDelegate.h"
#import "MAXTheme.h"
#import "MAXSettings.h"
#import "MAXApi.h"
#import "MAXAccountModule.h"
#import "MAXChatsModule.h"
#import "MAXSpoofingService.h"
#import "MAXSpoofProfile.h"
#import "MAXServerConfig.h"

typedef NS_ENUM(NSInteger, MAXSettingsSection) {
    MAXSettingsSectionAppearance = 0,
    MAXSettingsSectionStyle,
    MAXSettingsSectionWallpaper,
    MAXSettingsSectionPrivacy,
    MAXSettingsSectionSecurity,
    MAXSettingsSectionSpoof,
    MAXSettingsSectionServer,
    MAXSettingsSectionLog,
    MAXSettingsSectionAbout,
    MAXSettingsSectionSession,
    MAXSettingsSectionCount
};

@implementation MAXSettingsViewController

- (id)init {
    return [super initWithStyle:UITableViewStyleGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Настройки";
    [MAXTheme applyToTableView:self.tableView];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.tableView reloadData];
}

#pragma mark - Данные

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return MAXSettingsSectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case MAXSettingsSectionAppearance: return 3;
        case MAXSettingsSectionStyle: return 3;
        case MAXSettingsSectionWallpaper: return 1;
        case MAXSettingsSectionPrivacy: return 3;
        case MAXSettingsSectionSecurity: return 1;
        case MAXSettingsSectionSpoof: return 1;
        case MAXSettingsSectionServer: return 1;
        // Без записи в файл показывать в журнале нечего: в системный лог
        // сообщения уходят всё равно, но забрать их с устройства нельзя.
        case MAXSettingsSectionLog: return MAX_LOG_TO_FILE ? 2 : 0;
        case MAXSettingsSectionAbout: return 1;
        case MAXSettingsSectionSession: return 1;
        default: return 0;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case MAXSettingsSectionAppearance: return @"Оформление";
        case MAXSettingsSectionStyle: return @"Стиль";
        case MAXSettingsSectionWallpaper: return @"Переписка";
        case MAXSettingsSectionPrivacy: return @"Приватность";
        case MAXSettingsSectionSecurity: return @"Безопасность";
        case MAXSettingsSectionSpoof: return @"Подмена устройства";
        case MAXSettingsSectionServer: return @"Сервер";
        case MAXSettingsSectionLog: return MAX_LOG_TO_FILE ? @"Журнал" : nil;
        default: return nil;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    switch (section) {
        case MAXSettingsSectionAppearance:
            return @"«Системная» повторяет оформление iOS. В системах без тёмного "
                   @"режима — до iOS 13 — она всегда светлая: спрашивать там не у кого.";
        case MAXSettingsSectionStyle:
            return @"Скевоморфизм — градиенты, рамки и тени эпохи iOS 6; современная — "
                   @"плоские заливки iOS 7. «Как в системе» выбирает первое до iOS 7 "
                   @"и второе начиная с неё. Со светлой и тёмной темой сочетается любой.";
        case MAXSettingsSectionPrivacy:
            return @"Невидимка: в PING и LOGIN уходит interactive=false — сервер "
                   @"не поднимает статус «в сети». Не отмечать прочитанным: "
                   @"CHAT_MARK не отправляется. Скрыть набор: не отправляется MSG_TYPING.";
        case MAXSettingsSectionSecurity:
            return @"Пароль для входа. Когда у аккаунта уже есть сессия, MAX "
                   @"перестаёт слать код в SMS и требует пароль — без него "
                   @"второе устройство не подключить.";
        case MAXSettingsSectionSpoof:
            return @"Профиль устройства, которым клиент представляется серверу "
                   @"в SESSION_INIT. Изменения применяются при следующем подключении.";
        case MAXSettingsSectionLog:
            if (!MAX_LOG_TO_FILE) return nil;
            return @"Всё, что приложение пишет в системный журнал, попадает ещё "
                   @"и в файл max.log в папке Documents — её видно в iTunes. "
                   @"Туда же пишутся ошибки отправки вложений и приходящие пуши.";
        default:
            return nil;
    }
}

- (id)switchWithValue:(BOOL)value action:(SEL)action {
    return [MAXTheme switchWithValue:value target:self action:action];
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"MAXSettingsCell";

    UITableViewCell *cell = [[UITableViewCell alloc]
                             initWithStyle:UITableViewCellStyleValue1
                             reuseIdentifier:identifier];
    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleBlue;
    cell.textLabel.textColor = [MAXTheme textColor];
    cell.textLabel.textAlignment = NSTextAlignmentLeft;

    [MAXTheme applyToCell:cell indexPath:indexPath inTableView:tableView];
    switch (indexPath.section) {
        case MAXSettingsSectionAppearance: {
            MAXThemeMode mode = (MAXThemeMode)indexPath.row;
            cell.textLabel.text = [MAXTheme nameForMode:mode];
            cell.detailTextLabel.text = @"";
            // Галочка, а не отдельный экран: вариантов три, и видеть их все
            // сразу нагляднее, чем строку со значением и переход в список.
            [MAXTheme setCheckmark:([MAXTheme mode] == mode) onCell:cell];
            break;
        }

        case MAXSettingsSectionStyle: {
            MAXThemeStyle style = (MAXThemeStyle)indexPath.row;
            cell.textLabel.text = [MAXTheme nameForStyle:style];
            cell.detailTextLabel.text = @"";
            [MAXTheme setCheckmark:([MAXTheme style] == style) onCell:cell];
            break;
        }

        case MAXSettingsSectionWallpaper: {
            cell.textLabel.text = @"Фон переписки";
            cell.detailTextLabel.text = @"";
            [MAXTheme setDisclosureOnCell:cell];
            break;
        }

        case MAXSettingsSectionPrivacy: {
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            if (indexPath.row == 0) {
                cell.textLabel.text = @"Режим невидимки";
                cell.accessoryView = [self switchWithValue:[MAXSettings ghostMode]
                                                    action:@selector(toggleGhostMode:)];
            } else if (indexPath.row == 1) {
                cell.textLabel.text = @"Не отмечать прочитанным";
                cell.accessoryView = [self switchWithValue:[MAXSettings antiRead]
                                                    action:@selector(toggleAntiRead:)];
            } else {
                cell.textLabel.text = @"Скрыть набор текста";
                cell.accessoryView = [self switchWithValue:[MAXSettings antiTyping]
                                                    action:@selector(toggleAntiTyping:)];
            }
            break;
        }

        case MAXSettingsSectionSecurity: {
            cell.textLabel.text = @"Пароль для входа";
            cell.detailTextLabel.text = @"";
            [MAXTheme setDisclosureOnCell:cell];
            break;
        }

        case MAXSettingsSectionSpoof: {
            MAXSpoofProfile *profile = [MAXSpoofingService
                                        profileForScope:[MAXSpoofingService activeScope]];
            cell.textLabel.text = @"Профиль подмены";
            cell.detailTextLabel.text = profile.enabled
                ? (profile.deviceName.length > 0 ? profile.deviceName : @"включена")
                : @"выключена";
            [MAXTheme setDisclosureOnCell:cell];
            break;
        }

        case MAXSettingsSectionServer: {
            cell.textLabel.text = @"Адрес сервера";
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%@:%lu",
                                         [MAXServerConfig host],
                                         (unsigned long)[MAXServerConfig port]];
            [MAXTheme setDisclosureOnCell:cell];
            break;
        }

        case MAXSettingsSectionLog: {
            if (indexPath.row == 0) {
                cell.textLabel.text = @"Файл";
                cell.detailTextLabel.text = [MAXLogPath() lastPathComponent];
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
            } else {
                cell.textLabel.text = @"Очистить журнал";
                cell.textLabel.textColor = [MAXTheme accentColor];
                cell.detailTextLabel.text = @"";
            }
            break;
        }

        case MAXSettingsSectionAbout: {
            cell.textLabel.text = @"О приложении";
            cell.detailTextLabel.text = [[NSBundle mainBundle]
                                         objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
            [MAXTheme setDisclosureOnCell:cell];
            break;
        }

        case MAXSettingsSectionSession: {
            cell.textLabel.text = @"Выйти из аккаунта";
            cell.textLabel.textColor = [MAXTheme destructiveColor];
            cell.textLabel.textAlignment = NSTextAlignmentCenter;
            cell.detailTextLabel.text = @"";
            break;
        }
    }

    return cell;
}

#pragma mark - Действия

- (void)toggleGhostMode:(UISwitch *)sender {
    [MAXSettings setGhostMode:sender.on];
    // Сервер узнаёт о смене статуса из ближайшего пинга.
    [[MAXApi shared] refreshPingInteractive];
}

- (void)toggleAntiRead:(UISwitch *)sender {
    [MAXSettings setAntiRead:sender.on];
}

- (void)toggleAntiTyping:(UISwitch *)sender {
    [MAXSettings setAntiTyping:sender.on];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.section == MAXSettingsSectionAppearance) {
        MAXThemeMode mode = (MAXThemeMode)indexPath.row;
        if (mode == [MAXTheme mode]) return;

        // Экраны перестраиваются по уведомлению из setMode:, и этот в том
        // числе — поэтому reloadData здесь не нужен.
        [MAXTheme setMode:mode];
        return;
    }

    if (indexPath.section == MAXSettingsSectionStyle) {
        MAXThemeStyle style = (MAXThemeStyle)indexPath.row;
        if (style == [MAXTheme style]) return;

        [MAXTheme setStyle:style];
        return;
    }

    if (indexPath.section == MAXSettingsSectionWallpaper) {
        [self.navigationController pushViewController:[[MAXWallpaperViewController alloc] init]
                                             animated:YES];
        return;
    }

    if (indexPath.section == MAXSettingsSectionSecurity) {
        [self.navigationController pushViewController:[[MAXSecurityViewController alloc] init]
                                             animated:YES];
        return;
    }

    if (indexPath.section == MAXSettingsSectionSpoof) {
        [self.navigationController pushViewController:[[MAXSpoofViewController alloc] init]
                                             animated:YES];
        return;
    }

    if (indexPath.section == MAXSettingsSectionServer) {
        [self.navigationController
         pushViewController:[[MAXServerSettingsViewController alloc] init]
                   animated:YES];
        return;
    }

    if (indexPath.section == MAXSettingsSectionAbout) {
        [self.navigationController pushViewController:[[MAXAboutViewController alloc] init]
                                             animated:YES];
        return;
    }

    if (indexPath.section == MAXSettingsSectionLog && indexPath.row == 1) {
        MAXLogClear();
        id alert = [MAXTheme alertWithTitle:@"Журнал очищен"
                              message:nil
                             delegate:nil
                    cancelButtonTitle:@"OK"
                     otherButtonTitle:nil];
        [alert show];
        return;
    }

    if (indexPath.section == MAXSettingsSectionSession) {
        id alert = [MAXTheme alertWithTitle:@"Выйти"
                              message:@"Токен и профиль подмены будут удалены с устройства."
                             delegate:self
                    cancelButtonTitle:@"Отмена"
                     otherButtonTitle:@"Выйти"];
        [alert show];
    }
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (buttonIndex == alertView.cancelButtonIndex) return;

    [[MAXAccountModule shared] logoutWithCompletion:^(NSError *error) {
        [[MAXChatsModule shared] reset];
        [[MAXAppDelegate shared] showAuth];
        [[MAXApi shared] connect];
    }];
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
