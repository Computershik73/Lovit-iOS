//
//  MAXChatPickerViewController.m
//

#import "MAXChatPickerViewController.h"
#import "MAXAvatarView.h"
#import "MAXTheme.h"
#import "MAXChatsModule.h"
#import "MAXChat.h"

static const CGFloat MAXPickerRowHeight = 52.0;

@implementation MAXChatPickerViewController {
    NSArray *_chats;
}

- (id)init {
    self = [super initWithStyle:UITableViewStylePlain];
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"Куда переслать";
    self.tableView.rowHeight = MAXPickerRowHeight;
    [MAXTheme applyToTableView:self.tableView];

    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"Отмена"
                                         style:[MAXTheme barButtonStyle]
                                        target:self
                                        action:@selector(cancel)];

    // Каналы, которые мы не ведём, отсеиваем сразу: туда писать всё равно
    // нельзя, и предлагать их в списке значило бы обещать невозможное.
    MAXChatsModule *module = [MAXChatsModule shared];
    NSMutableArray *chats = [NSMutableArray array];
    for (MAXChat *chat in module.chats) {
        if (![chat canWriteAsUser:module.currentUserId]) continue;
        [chats addObject:chat];
    }
    _chats = chats;
}

- (void)cancel {
    [self.delegate chatPicker:self didPickChat:nil];
}

#pragma mark - UITableView

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)_chats.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"MAXChatPickerCell";

    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    MAXAvatarView *avatar = nil;

    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                      reuseIdentifier:identifier];
        avatar = [[MAXAvatarView alloc] initWithFrame:CGRectMake(12, 8, 36, 36)];
        avatar.tag = 100;
        [cell.contentView addSubview:avatar];
        cell.indentationLevel = 4;
        cell.indentationWidth = 10.0;
    } else {
        avatar = (MAXAvatarView *)[cell.contentView viewWithTag:100];
    }

    [MAXTheme applyToCell:cell];
    MAXChatsModule *module = [MAXChatsModule shared];
    MAXChat *chat = _chats[(NSUInteger)indexPath.row];
    NSString *title = [module displayTitleForChat:chat];

    cell.textLabel.text = title;
    cell.textLabel.font = [UIFont systemFontOfSize:16.0];

    [avatar setTitle:title
           avatarURL:[module avatarURLForChat:chat]
          identifier:chat.chatId];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    [self.delegate chatPicker:self didPickChat:_chats[(NSUInteger)indexPath.row]];
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
