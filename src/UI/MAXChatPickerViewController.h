//
//  MAXChatPickerViewController.h
//  Max — выбор чата: куда переслать сообщение.
//

#import <UIKit/UIKit.h>

@class MAXChat, MAXChatPickerViewController;

@protocol MAXChatPickerDelegate <NSObject>
/// nil — выбор отменили.
- (void)chatPicker:(MAXChatPickerViewController *)picker didPickChat:(MAXChat *)chat;
@end

@interface MAXChatPickerViewController : UITableViewController

@property (nonatomic, weak) id<MAXChatPickerDelegate> delegate;

@end
