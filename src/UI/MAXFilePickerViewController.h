//
//  MAXFilePickerViewController.h
//  Max — выбор файла из папки Documents.
//
//  Системного выбора файлов на iOS 6 нет: UIDocumentPickerViewController
//  появился только в iOS 8. Зато в Info.plist включён UIFileSharingEnabled,
//  то есть в Documents можно положить что угодно через iTunes — эту папку
//  экран и показывает.
//

#import <UIKit/UIKit.h>

@interface MAXFilePickerViewController : UITableViewController

/// Вызывается с полным путём к файлу либо с nil, если выбор отменили.
@property (nonatomic, copy) void (^completion)(NSString *path);

@end
