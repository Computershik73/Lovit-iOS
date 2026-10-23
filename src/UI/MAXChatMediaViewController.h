//
//  MAXChatMediaViewController.h
//  Max — вложения чата: медиа, файлы, ссылки.
//
//  Порт вкладок ChatInfoScreen из Komet (`shared_content_tabs.dart`), собранный
//  на одном переключателе: три отдельных экрана на iOS 6 стоили бы больше,
//  чем дают.
//

#import <UIKit/UIKit.h>

@class MAXChat;

@interface MAXChatMediaViewController : UIViewController <UITableViewDataSource,
                                                          UITableViewDelegate>

- (id)initWithChat:(MAXChat *)chat;

@end
