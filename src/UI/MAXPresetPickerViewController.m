//
//  MAXPresetPickerViewController.m
//

#import "MAXPresetPickerViewController.h"
#import "MAXDevicePresets.h"
#import "MAXTheme.h"

@implementation MAXPresetPickerViewController {
    NSArray *_types;          // порядок секций
    NSDictionary *_byType;    // тип -> массив пресетов
}

- (id)init {
    return [super initWithStyle:UITableViewStylePlain];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Устройства";
    [MAXTheme applyToTableView:self.tableView];

    _types = @[@"ANDROID", @"IOS", @"DESKTOP", @"WEB"];

    NSMutableDictionary *grouped = [NSMutableDictionary dictionary];
    for (NSString *type in _types) grouped[type] = [NSMutableArray array];

    for (MAXDevicePreset *preset in MAXDevicePresetsAll()) {
        NSMutableArray *bucket = grouped[preset.deviceType];
        if (bucket != nil) [bucket addObject:preset];
    }
    _byType = grouped;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return (NSInteger)_types.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return _types[(NSUInteger)section];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)[_byType[_types[(NSUInteger)section]] count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"MAXPresetCell";

    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                      reuseIdentifier:identifier];
        cell.detailTextLabel.textColor = [MAXTheme secondaryTextColor];
        cell.detailTextLabel.font = [UIFont systemFontOfSize:12.0];
    }

    [MAXTheme applyToCell:cell indexPath:indexPath inTableView:tableView];
    MAXDevicePreset *preset = _byType[_types[(NSUInteger)indexPath.section]][(NSUInteger)indexPath.row];
    cell.textLabel.text = preset.deviceName;
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@ · %@",
                                 preset.osVersion, preset.screen, preset.locale];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    MAXDevicePreset *preset = _byType[_types[(NSUInteger)indexPath.section]][(NSUInteger)indexPath.row];
    [self.delegate presetPicker:self didSelectPreset:preset];
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
