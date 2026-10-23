//
//  MAXChatViewController.h
//  Max — переписка: история, отправка, приём пушей.
//

#import <UIKit/UIKit.h>

@class MAXChat;

#import "MAXMessageCell.h"
#import "MAXChatPickerViewController.h"
#import "MAXStickerPickerViewController.h"

@interface MAXChatViewController : UIViewController <UITableViewDataSource,
                                                     UITableViewDelegate,
                                                     UITextFieldDelegate,
                                                     UIActionSheetDelegate,
                                                     UIAlertViewDelegate,
                                                     UIImagePickerControllerDelegate,
                                                     UINavigationControllerDelegate,
                                                     MAXChatPickerDelegate,
                                                     MAXStickerPickerDelegate,
                                                     MAXMessageCellDelegate>

- (id)initWithChat:(MAXChat *)chat;

/// Открыть чат не на последних сообщениях, а на этом — так работает переход
/// к источнику пересылки. Задаётся до показа экрана; история грузится окном,
/// которое заканчивается указанным сообщением.
@property (nonatomic, copy) NSString *initialMessageId;
@property (nonatomic, assign) long long initialMessageTime;

@end
