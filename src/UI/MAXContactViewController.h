//
//  MAXContactViewController.h
//  Max — карточка человека: имя, телефон, переход в переписку.
//
//  Открывается по нажатию на автора пересылки. У Komet в этом месте
//  `openContactDialogProfile` из chat_screen.dart.
//

#import <UIKit/UIKit.h>

@interface MAXContactViewController : UIViewController <UITableViewDataSource,
                                                        UITableViewDelegate>

/// Карточка ищется в кэше контактов; если человека там нет, она запрашивается
/// у сервера и экран обновляется сам.
- (id)initWithContactId:(long long)contactId;

@end
