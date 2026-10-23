//
//  MAXContactsViewController.m
//

#import "MAXContactsViewController.h"
#import "MAXChatViewController.h"
#import "MAXAvatarView.h"
#import "MAXTheme.h"
#import "MAXChatsModule.h"
#import "MAXChat.h"
#import "MAXContact.h"

static const CGFloat MAXContactRowHeight = 60.0;
static const CGFloat MAXContactAvatarSize = 44.0;

@implementation MAXContactsViewController {
    NSArray *_contacts;
    UILabel *_emptyLabel;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"Контакты";
    // Отсюда открывается переписка: со словом «Контакты» на кнопке возврата
    // её заголовок переставал стоять по центру.
    self.navigationItem.backBarButtonItem = [MAXTheme backBarButtonItem];

    self.tableView.rowHeight = MAXContactRowHeight;
    [MAXTheme applyToTableView:self.tableView];
    if ([self.tableView respondsToSelector:@selector(setSeparatorInset:)]) {
        self.tableView.separatorInset = UIEdgeInsetsMake(0, 68, 0, 0);
    }

    _emptyLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _emptyLabel.text = @"Контактов пока нет";
    _emptyLabel.textAlignment = NSTextAlignmentCenter;
    _emptyLabel.textColor = [MAXTheme secondaryTextColor];
    _emptyLabel.font = [UIFont systemFontOfSize:15.0];
    _emptyLabel.backgroundColor = [UIColor clearColor];
    [self.view addSubview:_emptyLabel];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(contactsChanged:)
                                                 name:MAXChatsDidChangeNotification
                                               object:nil];
    [self reload];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reload];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    _emptyLabel.frame = CGRectMake(0, 40, self.view.bounds.size.width, 20);
}

- (void)contactsChanged:(NSNotification *)note {
    [self reload];
}

- (void)reload {
    _contacts = [MAXChatsModule shared].contacts;
    _emptyLabel.hidden = _contacts.count > 0;
    [self.tableView reloadData];
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)_contacts.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"MAXContactCell";
    static const NSInteger avatarTag = 100;

    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                      reuseIdentifier:identifier];
        cell.detailTextLabel.font = [UIFont systemFontOfSize:13.0];
        cell.detailTextLabel.textColor = [MAXTheme secondaryTextColor];
        cell.textLabel.font = [UIFont systemFontOfSize:16.0];

        MAXAvatarView *avatar = [[MAXAvatarView alloc] initWithFrame:
                                 CGRectMake(12.0, (MAXContactRowHeight - MAXContactAvatarSize) / 2.0,
                                            MAXContactAvatarSize, MAXContactAvatarSize)];
        avatar.tag = avatarTag;
        [cell.contentView addSubview:avatar];

        // Стандартные метки ячейки начинаются от края, а слева теперь аватарка.
        cell.indentationLevel = 1;
        cell.indentationWidth = 56.0;
    }

    [MAXTheme applyToCell:cell];
    MAXContact *contact = _contacts[(NSUInteger)indexPath.row];
    NSString *name = contact.name.length > 0
        ? contact.name
        : [NSString stringWithFormat:@"ID %lld", contact.contactId];

    cell.textLabel.text = name;
    cell.detailTextLabel.text = contact.phone > 0
        ? [NSString stringWithFormat:@"+%lld", contact.phone]
        : @"";

    MAXAvatarView *avatar = (MAXAvatarView *)[cell.contentView viewWithTag:avatarTag];
    [avatar setTitle:name avatarURL:contact.avatarUrl identifier:contact.contactId];

    return cell;
}

#pragma mark - UITableViewDelegate

/// Открываем существующий диалог, если он уже есть в списке чатов. Создание
/// нового диалога — это отдельный запрос к серверу, его здесь пока нет.
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    MAXContact *contact = _contacts[(NSUInteger)indexPath.row];

    // Переписка открывается и с тем, кому ещё ни разу не писали: раньше здесь
    // искался готовый чат, и без него нажатие не делало ровно ничего.
    MAXChat *dialog = [[MAXChatsModule shared] dialogChatForContact:contact.contactId];

    MAXChatViewController *screen = [[MAXChatViewController alloc] initWithChat:dialog];
    [self.navigationController pushViewController:screen animated:YES];
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
