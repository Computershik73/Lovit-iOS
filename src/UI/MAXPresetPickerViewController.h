//
//  MAXPresetPickerViewController.h
//  Max — выбор устройства из списка пресетов.
//

#import <UIKit/UIKit.h>

@class MAXDevicePreset, MAXPresetPickerViewController;

@protocol MAXPresetPickerDelegate <NSObject>
- (void)presetPicker:(MAXPresetPickerViewController *)picker
     didSelectPreset:(MAXDevicePreset *)preset;
@end

@interface MAXPresetPickerViewController : UITableViewController

@property (nonatomic, weak) id<MAXPresetPickerDelegate> delegate;

@end
