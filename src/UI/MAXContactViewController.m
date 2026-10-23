//
//  MAXContactViewController.m
//

#import "MAXContactViewController.h"
#import "MAXChatViewController.h"
#import "MAXPhotoViewController.h"
#import "MAXAvatarView.h"
#import "MAXTheme.h"
#import "MAXChatsModule.h"
#import "MAXChat.h"
#import "MAXContact.h"

static const CGFloat MAXProfileAvatarSize = 96.0;
static const CGFloat MAXProfileHeaderHeight = 216.0;

/// Строки собираются заранее: так и таблица, и нажатия работают по одному
/// списку, и не приходится держать в голове, какой индекс чему соответствует.
static NSString *const MAXProfileRowPhone = @"phone";
static NSString *const MAXProfileRowAbout = @"about";
static NSString *const MAXProfileRowId = @"id";
static NSString *const MAXProfileRowWrite = @"write";
static NSString *const MAXProfileRowContact = @"contact";
static NSString *const MAXProfileRowBlock = @"block";

@implementation MAXContactViewController {
    long long _contactId;

    UITableView *_tableView;
    MAXAvatarView *_avatarView;
    UILabel *_nameLabel;
    UILabel *_presenceLabel;

    NSArray *_infoRows;
    NSArray *_actionRows;

    NSString *_avatarURL;
    NSString *_presenceText;
    BOOL _blocked;
    BOOL _blockedKnown;
}

- (id)initWithContactId:(long long)contactId {
    self = [super init];
    if (self) {
        _contactId = contactId;
        self.hidesBottomBarWhenPushed = YES;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"Профиль";
    self.view.backgroundColor = [MAXTheme backgroundColor];

    // Отсюда открывается переписка, а её заголовок — имя собеседника. Пусть
    // кнопка возврата будет стрелкой: со словом «Профиль» она отъедала место
    // у заголовка, и тот переставал стоять по центру.
    self.navigationItem.backBarButtonItem = [MAXTheme backBarButtonItem];

    // Таблица, а не набор фреймов: строк ровно столько, сколько сервер дал
    // сведений, а на четырёхдюймовом экране они иначе уезжали за нижний край.
    _tableView = [[UITableView alloc] initWithFrame:self.view.bounds
                                              style:UITableViewStyleGrouped];
    _tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth
                                | UIViewAutoresizingFlexibleHeight;
    _tableView.dataSource = self;
    _tableView.delegate = self;
    [self.view addSubview:_tableView];
    [MAXTheme applyToTableView:_tableView];

    _tableView.tableHeaderView = [self buildHeader];

    [[MAXChatsModule shared] ensureContactWithId:_contactId];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(contactsChanged:)
                                                 name:MAXChatsDidChangeNotification
                                               object:nil];

    // Кто заблокирован — отдельный список: в карточке контакта этого признака
    // нет. Пока ответа нет, строку блокировки не показываем: предлагать
    // действие, не зная текущего состояния, хуже, чем подождать.
    __weak MAXContactViewController *weakSelf = self;
    [[MAXChatsModule shared] fetchBlockedContactsWithCompletion:^(NSSet *blocked, NSError *error) {
        MAXContactViewController *strongSelf = weakSelf;
        if (strongSelf == nil || error != nil) return;

        strongSelf->_blocked = [blocked containsObject:@(strongSelf->_contactId)];
        strongSelf->_blockedKnown = YES;
        [strongSelf refresh];
    }];

    [self refreshPresence];
    [self refresh];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)contactsChanged:(NSNotification *)note {
    [self refresh];
}

#pragma mark - Шапка

- (UIView *)buildHeader {
    CGFloat width = self.view.bounds.size.width;
    UIView *header = [[UIView alloc] initWithFrame:
                      CGRectMake(0, 0, width, MAXProfileHeaderHeight)];
    header.backgroundColor = [UIColor clearColor];

    _avatarView = [[MAXAvatarView alloc] initWithFrame:
                   CGRectMake((width - MAXProfileAvatarSize) / 2.0, 24,
                              MAXProfileAvatarSize, MAXProfileAvatarSize)];
    _avatarView.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin
                                 | UIViewAutoresizingFlexibleRightMargin;
    _avatarView.userInteractionEnabled = YES;
    [header addSubview:_avatarView];

    UITapGestureRecognizer *avatarTap =
        [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(openAvatar)];
    [_avatarView addGestureRecognizer:avatarTap];

    _nameLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 134, width - 40, 52)];
    _nameLabel.font = [UIFont boldSystemFontOfSize:21.0];
    _nameLabel.textColor = [MAXTheme textColor];
    _nameLabel.textAlignment = NSTextAlignmentCenter;
    _nameLabel.numberOfLines = 2;
    _nameLabel.backgroundColor = [UIColor clearColor];
    _nameLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [header addSubview:_nameLabel];

    _presenceLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 188, width - 40, 18)];
    _presenceLabel.font = [UIFont systemFontOfSize:14.0];
    _presenceLabel.textAlignment = NSTextAlignmentCenter;
    _presenceLabel.textColor = [MAXTheme secondaryTextColor];
    _presenceLabel.backgroundColor = [UIColor clearColor];
    _presenceLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [header addSubview:_presenceLabel];

    return header;
}

#pragma mark - Состояние

- (void)refresh {
    MAXContact *contact = [[MAXChatsModule shared] contactWithId:_contactId];

    NSString *name = contact.name.length > 0
        ? contact.name
        : [NSString stringWithFormat:@"ID %lld", _contactId];

    _nameLabel.text = name;
    _presenceLabel.text = _presenceText;

    _avatarURL = contact.avatarUrl;
    [_avatarView setTitle:name avatarURL:contact.avatarUrl identifier:_contactId];

    NSMutableArray *info = [NSMutableArray array];
    if (contact.phone > 0) [info addObject:MAXProfileRowPhone];
    if (contact.about.length > 0) [info addObject:MAXProfileRowAbout];
    [info addObject:MAXProfileRowId];
    _infoRows = info;

    NSMutableArray *actions = [NSMutableArray array];
    if (_contactId != [MAXChatsModule shared].currentUserId) {
        [actions addObject:MAXProfileRowWrite];
        [actions addObject:MAXProfileRowContact];
        if (_blockedKnown) [actions addObject:MAXProfileRowBlock];
    }
    _actionRows = actions;

    [_tableView reloadData];
}

/// «В сети» / «был(-а) недавно» — то, что Komet пишет в шапке диалога.
/// Присутствие приходит отдельным запросом: в карточке контакта его нет.
- (void)refreshPresence {
    __weak MAXContactViewController *weakSelf = self;
    [[MAXChatsModule shared] fetchPresenceForIds:@[@(_contactId)]
                                      completion:^(NSDictionary *presence, NSError *error) {
        MAXContactViewController *strongSelf = weakSelf;
        if (strongSelf == nil || error != nil) return;

        strongSelf->_presenceText = MAXPresenceText(presence[@(strongSelf->_contactId)]);
        strongSelf->_presenceLabel.text = strongSelf->_presenceText;
    }];
}

#pragma mark - UITableView

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? (NSInteger)_infoRows.count : (NSInteger)_actionRows.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return section == 0 ? @"Сведения" : nil;
}

- (NSString *)rowAtIndexPath:(NSIndexPath *)indexPath {
    NSArray *rows = indexPath.section == 0 ? _infoRows : _actionRows;
    return rows[(NSUInteger)indexPath.row];
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *row = [self rowAtIndexPath:indexPath];
    MAXContact *contact = [[MAXChatsModule shared] contactWithId:_contactId];

    if (indexPath.section == 0) {
        static NSString *identifier = @"MAXProfileInfoCell";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
        if (cell == nil) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                          reuseIdentifier:identifier];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            cell.detailTextLabel.textColor = [MAXTheme secondaryTextColor];
            cell.detailTextLabel.font = [UIFont systemFontOfSize:12.0];
        }

        [MAXTheme applyToCell:cell indexPath:indexPath inTableView:tableView];
        cell.textLabel.numberOfLines = 1;
        cell.textLabel.font = [UIFont systemFontOfSize:16.0];
        cell.textLabel.textColor = [MAXTheme textColor];

        if ([row isEqualToString:MAXProfileRowPhone]) {
            cell.textLabel.text = [NSString stringWithFormat:@"+%lld", contact.phone];
            cell.detailTextLabel.text = @"телефон";
        } else if ([row isEqualToString:MAXProfileRowAbout]) {
            cell.textLabel.numberOfLines = 0;
            cell.textLabel.text = contact.about;
            cell.detailTextLabel.text = @"о себе";
        } else {
            cell.textLabel.text = [NSString stringWithFormat:@"%lld", _contactId];
            cell.detailTextLabel.text = @"идентификатор";
        }
        return cell;
    }

    static NSString *identifier = @"MAXProfileActionCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                      reuseIdentifier:identifier];
        cell.textLabel.textAlignment = NSTextAlignmentCenter;
        cell.textLabel.font = [UIFont systemFontOfSize:16.0];
    }

    [MAXTheme applyToCell:cell indexPath:indexPath inTableView:tableView];
    if ([row isEqualToString:MAXProfileRowWrite]) {
        cell.textLabel.text = @"Написать";
        cell.textLabel.textColor = [MAXTheme accentColor];
    } else if ([row isEqualToString:MAXProfileRowContact]) {
        cell.textLabel.text = contact.isSavedContact
            ? @"Удалить из контактов" : @"Добавить в контакты";
        cell.textLabel.textColor = [MAXTheme accentColor];
    } else {
        cell.textLabel.text = _blocked ? @"Разблокировать" : @"Заблокировать";
        cell.textLabel.textColor = [MAXTheme destructiveColor];
    }
    return cell;
}

/// Строка «о себе» бывает в несколько строк — считаем её высоту по тексту.
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (![[self rowAtIndexPath:indexPath] isEqualToString:MAXProfileRowAbout]) return 44.0;

    MAXContact *contact = [[MAXChatsModule shared] contactWithId:_contactId];
    CGSize size = [contact.about sizeWithFont:[UIFont systemFontOfSize:16.0]
                            constrainedToSize:CGSizeMake(tableView.bounds.size.width - 60, 200)
                                lineBreakMode:NSLineBreakByWordWrapping];
    return MAX(44.0, size.height + 26.0);
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 0) return;

    NSString *row = [self rowAtIndexPath:indexPath];
    if ([row isEqualToString:MAXProfileRowWrite]) {
        [self openChat];
    } else if ([row isEqualToString:MAXProfileRowContact]) {
        [self toggleContact];
    } else {
        [self toggleBlock];
    }
}

#pragma mark - Действия

/// Аватарка во весь экран — как в Komet, где по ней открывается просмотрщик.
- (void)openAvatar {
    if (_avatarURL.length == 0) return;

    MAXPhotoViewController *viewer =
        [[MAXPhotoViewController alloc] initWithImageURL:_avatarURL];
    UINavigationController *stack =
        [[UINavigationController alloc] initWithRootViewController:viewer];
    [MAXTheme applyToNavigationBar:stack.navigationBar];
    [self presentViewController:stack animated:YES completion:nil];
}

/// Переписка открывается и с тем, с кем её ещё не было: идентификатор диалога
/// в MAX выводится из двух участников, а на сервере он заведётся при первой
/// отправке. Komet поступает так же (`openContactDialogProfile`).
- (void)openChat {
    MAXChat *dialog = [[MAXChatsModule shared] dialogChatForContact:_contactId];

    MAXChatViewController *screen = [[MAXChatViewController alloc] initWithChat:dialog];
    [self.navigationController pushViewController:screen animated:YES];
}

- (void)toggleContact {
    MAXContact *contact = [[MAXChatsModule shared] contactWithId:_contactId];
    BOOL saved = contact.isSavedContact;

    __weak MAXContactViewController *weakSelf = self;
    [[MAXChatsModule shared] updateContact:_contactId
                                    action:(saved ? @"REMOVE" : @"ADD")
                                 firstName:(saved ? nil : contact.name)
                                completion:^(NSError *error) {
        MAXContactViewController *strongSelf = weakSelf;
        if (strongSelf == nil) return;

        if (error != nil) {
            [strongSelf showAlert:@"Не вышло" message:error.localizedDescription];
            return;
        }
        [strongSelf refresh];
    }];
}

- (void)toggleBlock {
    BOOL blocking = !_blocked;

    __weak MAXContactViewController *weakSelf = self;
    [[MAXChatsModule shared] updateContact:_contactId
                                    action:(blocking ? @"BLOCK" : @"UNBLOCK")
                                 firstName:nil
                                completion:^(NSError *error) {
        MAXContactViewController *strongSelf = weakSelf;
        if (strongSelf == nil) return;

        if (error != nil) {
            [strongSelf showAlert:@"Не вышло" message:error.localizedDescription];
            return;
        }
        strongSelf->_blocked = blocking;
        [strongSelf refresh];
    }];
}

- (void)showAlert:(NSString *)title message:(NSString *)message {
    id alert = [MAXTheme alertWithTitle:title
                              message:message
                             delegate:nil
                    cancelButtonTitle:@"OK"
                     otherButtonTitle:nil];
    [alert show];
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
