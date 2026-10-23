//
//  MAXWallpaperViewController.m
//

#import "MAXWallpaperViewController.h"
#import "MAXWallpaper.h"
#import "MAXTheme.h"

typedef NS_ENUM(NSInteger, MAXWallpaperSection) {
    MAXWallpaperSectionPresets = 0,
    MAXWallpaperSectionPhoto,
    MAXWallpaperSectionCount
};

@implementation MAXWallpaperViewController {
    UIPopoverController *_popover;   // на планшете галерея открывается только так
}

- (id)init {
    return [super initWithStyle:UITableViewStyleGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Фон переписки";
    [MAXTheme applyToTableView:self.tableView];
}

#pragma mark - Данные

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return MAXWallpaperSectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == MAXWallpaperSectionPresets) return (NSInteger)[MAXWallpaper presetColors].count;
    return [MAXWallpaper hasImage] ? 2 : 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return section == MAXWallpaperSectionPresets ? @"Оттенок" : @"Своя картинка";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section != MAXWallpaperSectionPhoto) return nil;

    return @"Картинка перекрывает оттенок и хранится только на этом устройстве: "
           @"на сервер фон не уходит.";
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc]
                             initWithStyle:UITableViewCellStyleDefault
                             reuseIdentifier:nil];
    [MAXTheme applyToCell:cell indexPath:indexPath inTableView:tableView];
    cell.textLabel.font = [UIFont systemFontOfSize:15.0];

    if (indexPath.section == MAXWallpaperSectionPresets) {
        NSUInteger index = (NSUInteger)indexPath.row;
        cell.textLabel.text = [MAXWallpaper presetNames][index];

        // Образец цвета — квадратик справа; понятнее любого названия.
        id color = [MAXWallpaper presetColors][index];
        if (color != [NSNull null]) {
            UIView *swatch = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 26, 26)];
            swatch.backgroundColor = color;
            swatch.layer.cornerRadius = 4.0;
            swatch.layer.borderWidth = 1.0;
            swatch.layer.borderColor = [[MAXTheme separatorColor] CGColor];
            cell.accessoryView = swatch;
        } else if ([MAXWallpaper presetIndex] == (NSInteger)index) {
            [MAXTheme setCheckmark:YES onCell:cell];
        }

        if ([MAXWallpaper presetIndex] == (NSInteger)index && color != [NSNull null]) {
            cell.textLabel.textColor = [MAXTheme accentColor];
        }
        return cell;
    }

    cell.textLabel.textAlignment = NSTextAlignmentCenter;
    if (indexPath.row == 0) {
        cell.textLabel.text = [MAXWallpaper hasImage] ? @"Выбрать другую" : @"Выбрать из галереи";
        cell.textLabel.textColor = [MAXTheme accentColor];
    } else {
        cell.textLabel.text = @"Убрать картинку";
        cell.textLabel.textColor = [MAXTheme destructiveColor];
    }
    return cell;
}

#pragma mark - Действия

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.section == MAXWallpaperSectionPresets) {
        [MAXWallpaper setPresetIndex:indexPath.row];
        [tableView reloadData];
        return;
    }

    if (indexPath.row == 1) {
        [MAXWallpaper setImage:nil];
        [tableView reloadData];
        return;
    }

    [self pickPhoto];
}

- (void)pickPhoto {
    if (![UIImagePickerController isSourceTypeAvailable:
          UIImagePickerControllerSourceTypePhotoLibrary]) {
        return;
    }

    UIImagePickerController *picker = [[UIImagePickerController alloc] init];
    picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    picker.delegate = self;

    // На планшете галерею нельзя показывать модально — UIKit бросает
    // исключение и снимает приложение.
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        _popover = [[UIPopoverController alloc] initWithContentViewController:picker];
        [_popover presentPopoverFromRect:self.view.bounds
                                  inView:self.view
                permittedArrowDirections:UIPopoverArrowDirectionAny
                                animated:YES];
        return;
    }

    [self presentViewController:picker animated:YES completion:nil];
}

- (void)dismissPicker {
    if (_popover != nil) {
        [_popover dismissPopoverAnimated:YES];
        _popover = nil;
        return;
    }
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)imagePickerController:(UIImagePickerController *)picker
        didFinishPickingMediaWithInfo:(NSDictionary *)info {
    UIImage *image = info[UIImagePickerControllerOriginalImage];
    [self dismissPicker];

    if (image != nil) [MAXWallpaper setImage:image];
    [self.tableView reloadData];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [self dismissPicker];
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
