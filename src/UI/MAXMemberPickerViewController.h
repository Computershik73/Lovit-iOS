//
//  MAXMemberPickerViewController.h
//  Max — выбор людей из адресного списка для добавления в чат.
//

#import <UIKit/UIKit.h>

@class MAXMemberPickerViewController;

@protocol MAXMemberPickerDelegate <NSObject>
/// Идентификаторы выбранных (NSNumber). Пустой массив — ничего не выбрали.
- (void)memberPicker:(MAXMemberPickerViewController *)picker didPickIds:(NSArray *)ids;
@end

@interface MAXMemberPickerViewController : UITableViewController

@property (nonatomic, weak) id<MAXMemberPickerDelegate> delegate;

/// `excludedIds` — кто уже в чате: показывать их незачем.
- (id)initWithExcludedIds:(NSSet *)excludedIds;

@end
