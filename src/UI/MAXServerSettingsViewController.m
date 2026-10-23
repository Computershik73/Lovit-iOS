//
//  MAXServerSettingsViewController.m
//

#import "MAXServerSettingsViewController.h"
#import "MAXServerConfig.h"
#import "MAXPacket.h"
#import "MAXApi.h"
#import "MAXTheme.h"

typedef NS_ENUM(NSInteger, MAXServerSection) {
    MAXServerSectionEndpoint = 0,
    MAXServerSectionTls,
    MAXServerSectionProtocol,
    MAXServerSectionActions,
    MAXServerSectionCount
};

@implementation MAXServerSettingsViewController {
    UITextField *_hostField;
    UITextField *_portField;
}

- (id)init {
    return [super initWithStyle:UITableViewStyleGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Сервер";
    [MAXTheme applyToTableView:self.tableView];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return MAXServerSectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case MAXServerSectionEndpoint: return 2;
        case MAXServerSectionTls: return 1;
        case MAXServerSectionProtocol: return 1;
        case MAXServerSectionActions: return 2;
        default: return 0;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case MAXServerSectionEndpoint: return @"Адрес";
        case MAXServerSectionTls: return @"TLS";
        case MAXServerSectionProtocol: return @"Протокол";
        default: return nil;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    switch (section) {
        case MAXServerSectionTls:
            return @"Сертификат api2.oneme.ru выпущен НУЦ Минцифры, которого нет "
                   @"в хранилище iOS. Его корни лежат в связке приложения и "
                   @"подставляются дополнительным якорем — цепочка при этом "
                   @"проверяется полностью.";
        case MAXServerSectionProtocol:
            return @"Сжатие исходящих пакетов LZ4. По умолчанию выключено: "
                   @"протокол допускает флаг 0 на любом размере.";
        default:
            return nil;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc]
                             initWithStyle:UITableViewCellStyleDefault
                             reuseIdentifier:nil];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;

    [MAXTheme applyToCell:cell indexPath:indexPath inTableView:tableView];
    if (indexPath.section == MAXServerSectionEndpoint) {
        UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(12, 0, 70, 44)];
        title.font = [UIFont systemFontOfSize:14.0];
        title.textColor = [MAXTheme secondaryTextColor];
        title.backgroundColor = [UIColor clearColor];
        [cell.contentView addSubview:title];

        UITextField *field = [[UITextField alloc] initWithFrame:
                              CGRectMake(90, 0, tableView.bounds.size.width - 110, 44)];
        field.font = [UIFont systemFontOfSize:15.0];
        field.textColor = [MAXTheme textColor];
        field.keyboardAppearance = [MAXTheme keyboardAppearance];
        field.textAlignment = NSTextAlignmentRight;
        field.autocorrectionType = UITextAutocorrectionTypeNo;
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
        field.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        field.delegate = self;
        field.returnKeyType = UIReturnKeyDone;
        [cell.contentView addSubview:field];

        if (indexPath.row == 0) {
            title.text = @"Хост";
            field.text = [MAXServerConfig host];
            field.keyboardType = UIKeyboardTypeURL;
            _hostField = field;
        } else {
            title.text = @"Порт";
            field.text = [NSString stringWithFormat:@"%lu", (unsigned long)[MAXServerConfig port]];
            field.keyboardType = UIKeyboardTypeNumberPad;
            _portField = field;
        }
        return cell;
    }

    if (indexPath.section == MAXServerSectionTls) {
        cell.textLabel.text = @"Вшитые корни Минцифры";
        cell.textLabel.font = [UIFont systemFontOfSize:15.0];
        cell.accessoryView = [MAXTheme switchWithValue:[MAXServerConfig trustMincifryCa]
                                                target:self
                                                action:@selector(toggleTrustCa:)];
        return cell;
    }

    if (indexPath.section == MAXServerSectionProtocol) {
        cell.textLabel.text = @"Сжимать исходящие (LZ4)";
        cell.textLabel.font = [UIFont systemFontOfSize:15.0];
        cell.accessoryView = [MAXTheme switchWithValue:[MAXPacket compressOutgoing]
                                                target:self
                                                action:@selector(toggleCompression:)];
        return cell;
    }

    cell.selectionStyle = UITableViewCellSelectionStyleBlue;
    cell.textLabel.textAlignment = NSTextAlignmentCenter;
    cell.textLabel.textColor = [MAXTheme accentColor];
    cell.textLabel.text = indexPath.row == 0
        ? @"Сохранить и переподключиться"
        : @"Сбросить к api2.oneme.ru";
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section != MAXServerSectionActions) return;

    if (indexPath.row == 0) {
        [self.view endEditing:YES];
        if (_hostField.text.length > 0) [MAXServerConfig setHost:_hostField.text];

        NSInteger port = [_portField.text integerValue];
        if (port >= 1 && port <= 65535) [MAXServerConfig setPort:(NSUInteger)port];
    } else {
        [MAXServerConfig resetEndpoint];
        [self.tableView reloadData];
    }

    [[MAXApi shared] disconnect];
    [[MAXApi shared] connect];
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)toggleTrustCa:(UISwitch *)sender {
    [MAXServerConfig setTrustMincifryCa:sender.on];
}

- (void)toggleCompression:(UISwitch *)sender {
    [MAXPacket setCompressOutgoing:sender.on];
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
