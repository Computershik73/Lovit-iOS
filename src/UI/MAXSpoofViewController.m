//
//  MAXSpoofViewController.m
//

#import "MAXSpoofViewController.h"
#import "MAXPresetPickerViewController.h"
#import "MAXTheme.h"
#import "MAXSpoofingService.h"
#import "MAXSpoofProfile.h"
#import "MAXDevicePresets.h"
#import "MAXDeviceIdentity.h"
#import "MAXApi.h"

typedef NS_ENUM(NSInteger, MAXSpoofSection) {
    MAXSpoofSectionEnable = 0,
    MAXSpoofSectionMethod,
    MAXSpoofSectionActions,
    MAXSpoofSectionFields,
    MAXSpoofSectionApply,
    MAXSpoofSectionCount
};

/// Ключи полей в порядке отображения.
static NSString *const MAXSpoofFieldKeys[] = {
    @"deviceName", @"osVersion", @"screen", @"timezone", @"locale", @"deviceLocale",
    @"deviceId", @"deviceType", @"arch", @"appVersion", @"buildNumber",
    @"pushDeviceType", @"instanceId", @"clientSessionId", @"userAgent"
};
static const NSUInteger MAXSpoofFieldCount = 15;

@interface MAXSpoofViewController () <MAXPresetPickerDelegate>
@end

@implementation MAXSpoofViewController {
    MAXSpoofProfile *_profile;
    NSString *_scope;
    BOOL _fullMethod;
    NSMutableDictionary *_fieldValues;
}

- (id)init {
    return [super initWithStyle:UITableViewStyleGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"Подмена";
    [MAXTheme applyToTableView:self.tableView];
    _scope = [MAXSpoofingService activeScope];

    _profile = [MAXSpoofingService profileForScope:_scope];
    if (_profile == nil) {
        _profile = [[MAXSpoofProfile alloc] init];
        _profile.appVersion = MAXSpoofHardcodedAppVersion;
        _profile.buildNumber = MAXSpoofHardcodedBuildNumber;
    }

    _fullMethod = YES;
    [self loadFieldValuesFromProfile];
}

#pragma mark - Модель полей

- (void)loadFieldValuesFromProfile {
    _fieldValues = [NSMutableDictionary dictionary];
    _fieldValues[@"deviceName"] = _profile.deviceName ?: @"";
    _fieldValues[@"osVersion"] = _profile.osVersion ?: @"";
    _fieldValues[@"screen"] = _profile.screen ?: @"";
    _fieldValues[@"timezone"] = _profile.timezone ?: @"";
    _fieldValues[@"locale"] = _profile.locale ?: @"";
    _fieldValues[@"deviceLocale"] = _profile.deviceLocale ?: @"";
    _fieldValues[@"deviceId"] = _profile.deviceId ?: @"";
    _fieldValues[@"deviceType"] = _profile.deviceType ?: @"ANDROID";
    _fieldValues[@"arch"] = _profile.arch ?: @"arm64-v8a";
    _fieldValues[@"appVersion"] = _profile.appVersion ?: @"";
    _fieldValues[@"buildNumber"] = [NSString stringWithFormat:@"%lld", _profile.buildNumber];
    _fieldValues[@"pushDeviceType"] = _profile.pushDeviceType ?: @"GCM";
    _fieldValues[@"instanceId"] = _profile.instanceId ?: @"";
    _fieldValues[@"clientSessionId"] = [NSString stringWithFormat:@"%lld", _profile.clientSessionId];
    _fieldValues[@"userAgent"] = _profile.userAgent ?: @"";
}

- (void)storeFieldValuesToProfile {
    _profile.deviceName = _fieldValues[@"deviceName"];
    _profile.osVersion = _fieldValues[@"osVersion"];
    _profile.screen = _fieldValues[@"screen"];
    _profile.timezone = _fieldValues[@"timezone"];
    _profile.locale = _fieldValues[@"locale"];
    _profile.deviceLocale = _fieldValues[@"deviceLocale"];
    _profile.deviceId = _fieldValues[@"deviceId"];
    _profile.deviceType = _fieldValues[@"deviceType"];
    _profile.arch = _fieldValues[@"arch"];
    _profile.appVersion = _fieldValues[@"appVersion"];
    _profile.buildNumber = [_fieldValues[@"buildNumber"] longLongValue];
    _profile.pushDeviceType = _fieldValues[@"pushDeviceType"];
    _profile.instanceId = _fieldValues[@"instanceId"];
    _profile.clientSessionId = [_fieldValues[@"clientSessionId"] longLongValue];
    _profile.userAgent = _fieldValues[@"userAgent"];
}

- (NSString *)titleForFieldKey:(NSString *)key {
    static NSDictionary *titles = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        titles = @{
            @"deviceName": @"Устройство",
            @"osVersion": @"ОС",
            @"screen": @"Экран",
            @"timezone": @"Часовой пояс",
            @"locale": @"Язык",
            @"deviceLocale": @"Язык устройства",
            @"deviceId": @"deviceId",
            @"deviceType": @"Тип",
            @"arch": @"Архитектура",
            @"appVersion": @"Версия",
            @"buildNumber": @"Сборка",
            @"pushDeviceType": @"Пуши",
            @"instanceId": @"instanceId",
            @"clientSessionId": @"clientSessionId",
            @"userAgent": @"User-Agent"
        };
    });
    return titles[key] ?: key;
}

#pragma mark - Применение пресета

/// Порт _applyPreset: частичный режим оставляет реальные часовой пояс и язык.
- (void)applyPreset:(MAXDevicePreset *)preset {
    _fieldValues[@"deviceName"] = preset.deviceName;
    _fieldValues[@"osVersion"] = preset.osVersion;
    _fieldValues[@"screen"] = preset.screen;
    _fieldValues[@"deviceType"] = preset.deviceType;
    _fieldValues[@"userAgent"] = preset.userAgent;
    _fieldValues[@"arch"] = @"arm64-v8a";
    _fieldValues[@"appVersion"] = MAXSpoofHardcodedAppVersion;
    _fieldValues[@"buildNumber"] = [NSString stringWithFormat:@"%lld",
                                    MAXSpoofHardcodedBuildNumber];
    _fieldValues[@"deviceId"] = [MAXDeviceIdentity randomHexWithByteCount:8];

    NSString *shortLocale = [[preset.locale componentsSeparatedByCharactersInSet:
                              [NSCharacterSet characterSetWithCharactersInString:@"-_"]]
                             objectAtIndex:0];

    if (_fullMethod) {
        _fieldValues[@"timezone"] = preset.timezone;
        _fieldValues[@"locale"] = shortLocale;
        _fieldValues[@"deviceLocale"] = shortLocale;
    } else {
        _fieldValues[@"timezone"] = [[NSTimeZone systemTimeZone] name];
        NSString *identifier = [[NSLocale currentLocale] localeIdentifier];
        NSString *systemLocale = identifier.length >= 2 ? [identifier substringToIndex:2] : @"ru";
        _fieldValues[@"locale"] = systemLocale;
        _fieldValues[@"deviceLocale"] = systemLocale;
    }

    if (_fieldValues[@"instanceId"] == nil || [_fieldValues[@"instanceId"] length] == 0) {
        _fieldValues[@"instanceId"] = [MAXDeviceIdentity uuidV4];
    }
    if ([_fieldValues[@"clientSessionId"] longLongValue] == 0) {
        _fieldValues[@"clientSessionId"] = [NSString stringWithFormat:@"%lld",
                                            [MAXDeviceIdentity randomClientSessionId]];
    }

    _profile.enabled = YES;
    [self.tableView reloadData];
}

- (void)generateRandomDevice {
    // Частичный режим всегда берёт Android-пресет, как в оригинале.
    NSString *type = _fullMethod ? _fieldValues[@"deviceType"] : @"ANDROID";

    NSMutableArray *filtered = [NSMutableArray array];
    for (MAXDevicePreset *preset in MAXDevicePresetsAll()) {
        if ([preset.deviceType isEqualToString:type]) [filtered addObject:preset];
    }
    if (filtered.count == 0) filtered = [MAXDevicePresetsAndroid() mutableCopy];
    if (filtered.count == 0) return;

    [self applyPreset:filtered[arc4random_uniform((u_int32_t)filtered.count)]];
}

- (void)regenerateIdentifiers {
    _fieldValues[@"deviceId"] = [MAXDeviceIdentity randomHexWithByteCount:8];
    _fieldValues[@"instanceId"] = [MAXDeviceIdentity uuidV4];
    _fieldValues[@"clientSessionId"] = [NSString stringWithFormat:@"%lld",
                                        [MAXDeviceIdentity randomClientSessionId]];
    [self.tableView reloadData];
}

- (void)applyAndReconnect {
    [self.view endEditing:YES];
    [self storeFieldValuesToProfile];
    [MAXSpoofingService saveProfile:_profile forScope:_scope];

    // Поля устройства уходят только в SESSION_INIT, поэтому нужен реконнект.
    [[MAXApi shared] disconnect];
    [[MAXApi shared] connect];

    id alert = [MAXTheme alertWithTitle:@"Сохранено"
                              message:@"Профиль применён, сессия переподключается."
                             delegate:nil
                    cancelButtonTitle:@"OK"
                     otherButtonTitle:nil];
    [alert show];
}

#pragma mark - Таблица

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return MAXSpoofSectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case MAXSpoofSectionEnable: return 1;
        case MAXSpoofSectionMethod: return 1;
        case MAXSpoofSectionActions: return 3;
        case MAXSpoofSectionFields: return (NSInteger)MAXSpoofFieldCount;
        case MAXSpoofSectionApply: return 1;
        default: return 0;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == MAXSpoofSectionFields) return @"Поля SESSION_INIT";
    return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    switch (section) {
        case MAXSpoofSectionEnable:
            return @"Версия и сборка всегда подменяются на версию официального "
                   @"клиента MAX — иначе сервер откажет старой сборке.";
        case MAXSpoofSectionMethod:
            return @"Полная: подменяются также часовой пояс и язык. "
                   @"Частичная: только устройство, время и язык остаются настоящими.";
        default:
            return nil;
    }
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 44.0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc]
                             initWithStyle:UITableViewCellStyleDefault
                             reuseIdentifier:nil];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;

    [MAXTheme applyToCell:cell indexPath:indexPath inTableView:tableView];
    switch (indexPath.section) {
        case MAXSpoofSectionEnable: {
            cell.textLabel.text = @"Подмена включена";
            id toggle = [MAXTheme switchWithValue:_profile.enabled
                                            target:self
                                            action:@selector(toggleEnabled:)];
            cell.accessoryView = toggle;
            break;
        }

        case MAXSpoofSectionMethod: {
            UISegmentedControl *segmented = [[UISegmentedControl alloc]
                                             initWithItems:@[@"Полная", @"Частичная"]];
            segmented.selectedSegmentIndex = _fullMethod ? 0 : 1;
            segmented.frame = CGRectMake(10, 6, tableView.bounds.size.width - 40, 32);
            segmented.autoresizingMask = UIViewAutoresizingFlexibleWidth;
            [segmented addTarget:self action:@selector(methodChanged:)
                forControlEvents:UIControlEventValueChanged];
            [cell.contentView addSubview:segmented];
            break;
        }

        case MAXSpoofSectionActions: {
            cell.selectionStyle = UITableViewCellSelectionStyleBlue;
            cell.textLabel.textColor = [MAXTheme accentColor];
            if (indexPath.row == 0) cell.textLabel.text = @"Случайное устройство";
            else if (indexPath.row == 1) cell.textLabel.text = @"Выбрать из списка…";
            else cell.textLabel.text = @"Новые deviceId / instanceId / сессия";
            break;
        }

        case MAXSpoofSectionFields: {
            NSString *key = MAXSpoofFieldKeys[indexPath.row];

            UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(12, 0, 130, 44)];
            title.text = [self titleForFieldKey:key];
            title.font = [UIFont systemFontOfSize:14.0];
            title.textColor = [MAXTheme secondaryTextColor];
            title.backgroundColor = [UIColor clearColor];
            [cell.contentView addSubview:title];

            UITextField *field = [[UITextField alloc] initWithFrame:
                                  CGRectMake(146, 0, tableView.bounds.size.width - 166, 44)];
            field.text = _fieldValues[key];
            field.font = [UIFont systemFontOfSize:14.0];
            field.textColor = [MAXTheme textColor];
            field.keyboardAppearance = [MAXTheme keyboardAppearance];
            field.textAlignment = NSTextAlignmentRight;
            field.autocorrectionType = UITextAutocorrectionTypeNo;
            field.autocapitalizationType = UITextAutocapitalizationTypeNone;
            field.autoresizingMask = UIViewAutoresizingFlexibleWidth;
            field.delegate = self;
            field.tag = indexPath.row;
            field.returnKeyType = UIReturnKeyDone;
            [cell.contentView addSubview:field];
            break;
        }

        case MAXSpoofSectionApply: {
            cell.selectionStyle = UITableViewCellSelectionStyleBlue;
            cell.textLabel.text = @"Применить и переподключиться";
            cell.textLabel.textAlignment = NSTextAlignmentCenter;
            cell.textLabel.textColor = [MAXTheme accentColor];
            break;
        }
    }

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.section == MAXSpoofSectionActions) {
        if (indexPath.row == 0) {
            [self generateRandomDevice];
        } else if (indexPath.row == 1) {
            MAXPresetPickerViewController *picker = [[MAXPresetPickerViewController alloc] init];
            picker.delegate = self;
            [self.navigationController pushViewController:picker animated:YES];
        } else {
            [self regenerateIdentifiers];
        }
        return;
    }

    if (indexPath.section == MAXSpoofSectionApply) {
        [self applyAndReconnect];
    }
}

#pragma mark - Обработчики

- (void)toggleEnabled:(UISwitch *)sender {
    _profile.enabled = sender.on;
    // Включение с пустым профилем сразу подставляет случайное устройство.
    if (sender.on && [_fieldValues[@"deviceName"] length] == 0) [self generateRandomDevice];
}

- (void)methodChanged:(UISegmentedControl *)sender {
    _fullMethod = sender.selectedSegmentIndex == 0;
}

#pragma mark - MAXPresetPickerDelegate

- (void)presetPicker:(MAXPresetPickerViewController *)picker didSelectPreset:(MAXDevicePreset *)preset {
    [self applyPreset:preset];
    [self.navigationController popViewControllerAnimated:YES];
}

#pragma mark - UITextFieldDelegate

- (void)textFieldDidEndEditing:(UITextField *)textField {
    if (textField.tag >= 0 && (NSUInteger)textField.tag < MAXSpoofFieldCount) {
        _fieldValues[MAXSpoofFieldKeys[textField.tag]] = textField.text ?: @"";
    }
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return NO;
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
