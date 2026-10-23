//
//  MAXChatInfoViewController.h
//  Max — сведения о чате: аватар, название, список участников.
//
//  Открывается нажатием на шапку переписки, как ChatInfoScreen в Komet.
//  Из вкладок оригинала здесь только участники: медиа, ссылки и настройки
//  чата в порт не переносились.
//

#import <UIKit/UIKit.h>
#import "MAXMemberPickerViewController.h"

@class MAXChat;

@interface MAXChatInfoViewController : UIViewController <UITableViewDataSource,
                                                         UITableViewDelegate,
                                                         UIAlertViewDelegate,
                                                         MAXMemberPickerDelegate>

- (id)initWithChat:(MAXChat *)chat;

@end
