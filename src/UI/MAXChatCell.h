//
//  MAXChatCell.h
//  Max — строка списка чатов.
//
//  Раскладка повторяет клиент MAX: круглая аватарка слева, имя жирным,
//  под ним превью последнего сообщения, справа сверху время, справа снизу
//  синий счётчик непрочитанных. У официальных чатов рядом с именем галочка.
//

#import <UIKit/UIKit.h>

@class MAXChat;

@interface MAXChatCell : UITableViewCell

+ (CGFloat)rowHeight;

/// `title` и `avatarURL` приходят снаружи, а не берутся из чата: у диалога
/// и то, и другое лежит в карточке контакта, которая приезжает отдельно
/// и позже самого чата. Разрешает их MAXChatsModule.
- (void)configureWithChat:(MAXChat *)chat
                    title:(NSString *)title
                avatarURL:(NSString *)avatarURL;

@end
