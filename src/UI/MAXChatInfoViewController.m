//
//  MAXChatInfoViewController.m
//

#import "MAXChatInfoViewController.h"
#import "MAXContactViewController.h"
#import "MAXChatMediaViewController.h"
#import "MAXPhotoViewController.h"
#import "MAXAvatarView.h"
#import "MAXTheme.h"
#import "MAXChatsModule.h"
#import "MAXChat.h"
#import "MAXContact.h"

static const CGFloat MAXInfoAvatarSize = 76.0;
static const CGFloat MAXInfoHeaderHeight = 212.0;
static const CGFloat MAXInfoRowHeight = 52.0;

@implementation MAXChatInfoViewController {
    MAXChat *_chat;
    NSMutableArray *_participantIds;   // NSNumber, отсортированы по имени
    NSMutableSet *_knownIds;           // чтобы страницы не задваивали людей
    UITableView *_tableView;
    UIActivityIndicatorView *_spinner;
    UILabel *_descriptionLabel;
    NSString *_avatarURL;
    NSString *_pendingAction;   // что подтверждает открытый UIAlertView
    long long _marker;
    BOOL _loading;
    BOOL _loadedAll;
}

- (id)initWithChat:(MAXChat *)chat {
    self = [super init];
    if (self) {
        _chat = chat;
        self.hidesBottomBarWhenPushed = YES;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"Сведения";
    self.view.backgroundColor = [MAXTheme backgroundColor];

    // Отсюда открываются профили участников; со словом «Сведения» на кнопке
    // возврата их заголовки съезжали с центра.
    self.navigationItem.backBarButtonItem = [MAXTheme backBarButtonItem];

    _tableView = [[UITableView alloc] initWithFrame:self.view.bounds
                                              style:UITableViewStylePlain];
    _tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth
                                | UIViewAutoresizingFlexibleHeight;
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.rowHeight = MAXInfoRowHeight;
    [MAXTheme applyToTableView:_tableView];
    [self.view addSubview:_tableView];

    _tableView.tableHeaderView = [self buildHeader];

    _spinner = [[UIActivityIndicatorView alloc]
                initWithActivityIndicatorStyle:[MAXTheme activityIndicatorStyle]];
    _spinner.center = CGPointMake(CGRectGetMidX(self.view.bounds),
                                  CGRectGetMidY(self.view.bounds));
    _spinner.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin
                              | UIViewAutoresizingFlexibleRightMargin
                              | UIViewAutoresizingFlexibleTopMargin
                              | UIViewAutoresizingFlexibleBottomMargin;
    [self.view addSubview:_spinner];

    _participantIds = [NSMutableArray array];
    _knownIds = [NSMutableSet set];

    // В самом чате лежит горстка участников — состав приходится спрашивать
    // отдельно, страницами. Карточки приезжают вместе с ним, так что
    // догружать контакты потом не нужно.
    [self loadNextPage];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(contactsChanged:)
                                                 name:MAXChatsDidChangeNotification
                                               object:nil];
}

- (void)loadNextPage {
    if (_loading || _loadedAll) return;
    _loading = YES;
    if (_participantIds.count == 0) [_spinner startAnimating];

    __weak MAXChatInfoViewController *weakSelf = self;
    [[MAXChatsModule shared] fetchMembersForChat:_chat.chatId
                                          marker:_marker
                                      completion:^(NSArray *memberIds,
                                                   long long nextMarker,
                                                   NSError *error) {
        MAXChatInfoViewController *strongSelf = weakSelf;
        if (strongSelf == nil) return;

        strongSelf->_loading = NO;
        [strongSelf->_spinner stopAnimating];

        if (error != nil) {
            // Состав не пришёл — показываем хотя бы тех, кого знаем из чата.
            strongSelf->_loadedAll = YES;
            [strongSelf addParticipantIds:[strongSelf->_chat.participants allKeys]];
            return;
        }

        [strongSelf addParticipantIds:memberIds];

        // Маркер повторился или обнулился — страницы кончились.
        strongSelf->_loadedAll = (nextMarker == 0 || nextMarker == strongSelf->_marker
                                  || memberIds.count == 0);
        strongSelf->_marker = nextMarker;
    }];
}

- (void)addParticipantIds:(NSArray *)ids {
    for (NSNumber *contactId in ids) {
        if ([_knownIds containsObject:contactId]) continue;
        [_knownIds addObject:contactId];
        [_participantIds addObject:contactId];
    }
    [self sortParticipants];
    [_tableView reloadData];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)contactsChanged:(NSNotification *)note {
    [self sortParticipants];
    [_tableView reloadData];
}

- (UIView *)buildHeader {
    CGFloat width = self.view.bounds.size.width;
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, MAXInfoHeaderHeight)];
    header.backgroundColor = [MAXTheme backgroundColor];

    MAXChatsModule *module = [MAXChatsModule shared];
    NSString *title = [module displayTitleForChat:_chat];

    MAXAvatarView *avatar = [[MAXAvatarView alloc] initWithFrame:
                             CGRectMake((width - MAXInfoAvatarSize) / 2.0, 20,
                                        MAXInfoAvatarSize, MAXInfoAvatarSize)];
    avatar.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin
                            | UIViewAutoresizingFlexibleRightMargin;
    avatar.userInteractionEnabled = YES;
    _avatarURL = [module avatarURLForChat:_chat];
    [avatar setTitle:title avatarURL:_avatarURL identifier:_chat.chatId];
    [header addSubview:avatar];

    UITapGestureRecognizer *avatarTap =
        [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(openAvatar)];
    [avatar addGestureRecognizer:avatarTap];

    // Названия у рабочих групп длинные — в одну строку они не влезают вовсе.
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 106, width - 40, 48)];
    titleLabel.font = [UIFont boldSystemFontOfSize:19.0];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.numberOfLines = 2;
    titleLabel.backgroundColor = [UIColor clearColor];
    titleLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    titleLabel.text = title;
    [header addSubview:titleLabel];

    UILabel *subtitleLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 158, width - 40, 18)];
    subtitleLabel.font = [UIFont systemFontOfSize:14.0];
    subtitleLabel.textAlignment = NSTextAlignmentCenter;
    subtitleLabel.textColor = [MAXTheme secondaryTextColor];
    subtitleLabel.backgroundColor = [UIColor clearColor];
    subtitleLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    subtitleLabel.text = [module subtitleForChat:_chat];
    [header addSubview:subtitleLabel];

    UILabel *idLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 180, width - 40, 16)];
    idLabel.font = [UIFont systemFontOfSize:12.0];
    idLabel.textAlignment = NSTextAlignmentCenter;
    idLabel.textColor = [MAXTheme secondaryTextColor];
    idLabel.backgroundColor = [UIColor clearColor];
    idLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    idLabel.text = [NSString stringWithFormat:@"ID %lld", _chat.chatId];
    [header addSubview:idLabel];

    // Описание в списке чатов не приходит — за ним нужен отдельный CHAT_INFO.
    // Место под него занимается по факту: пустая рамка под каждым чатом без
    // описания выглядела бы недосмотром.
    _descriptionLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 200, width - 40, 0)];
    _descriptionLabel.font = [UIFont systemFontOfSize:14.0];
    _descriptionLabel.textColor = [MAXTheme textColor];
    _descriptionLabel.textAlignment = NSTextAlignmentCenter;
    _descriptionLabel.numberOfLines = 0;
    _descriptionLabel.backgroundColor = [UIColor clearColor];
    _descriptionLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [header addSubview:_descriptionLabel];

    __weak MAXChatInfoViewController *weakSelf = self;
    [module fetchDescriptionForChat:_chat.chatId
                         completion:^(NSString *text, NSError *error) {
        MAXChatInfoViewController *strongSelf = weakSelf;
        if (strongSelf == nil || text.length == 0) return;
        [strongSelf applyDescription:text];
    }];

    return header;
}

/// Заголовок таблицы после правки надо переустановить целиком: UITableView
/// запоминает его высоту при назначении и сам её не пересчитывает.
- (void)applyDescription:(NSString *)text {
    UIView *header = _tableView.tableHeaderView;
    if (header == nil) return;

    CGFloat width = header.bounds.size.width - 40.0;
    CGSize size = [text sizeWithFont:_descriptionLabel.font
                   constrainedToSize:CGSizeMake(width, 120.0)
                       lineBreakMode:NSLineBreakByWordWrapping];

    _descriptionLabel.text = text;
    _descriptionLabel.frame = CGRectMake(20, MAXInfoHeaderHeight - 8.0, width, size.height);

    CGRect frame = header.frame;
    frame.size.height = MAXInfoHeaderHeight + size.height + 4.0;
    header.frame = frame;

    _tableView.tableHeaderView = header;
}

- (void)openAvatar {
    if (_avatarURL.length == 0) return;

    MAXPhotoViewController *viewer =
        [[MAXPhotoViewController alloc] initWithImageURL:_avatarURL];
    UINavigationController *stack =
        [[UINavigationController alloc] initWithRootViewController:viewer];
    [MAXTheme applyToNavigationBar:stack.navigationBar];
    [self presentViewController:stack animated:YES completion:nil];
}

- (void)sortParticipants {
    MAXChatsModule *module = [MAXChatsModule shared];

    [_participantIds sortUsingComparator:^NSComparisonResult(NSNumber *a, NSNumber *b) {
        NSString *left = [module contactWithId:[a longLongValue]].name ?: @"";
        NSString *right = [module contactWithId:[b longLongValue]].name ?: @"";

        // Безымянные — в конец: иначе они разбивали бы список посередине.
        if (left.length == 0 && right.length > 0) return NSOrderedDescending;
        if (right.length == 0 && left.length > 0) return NSOrderedAscending;
        if (left.length == 0 && right.length == 0) {
            return [a compare:b];
        }
        return [left localizedCaseInsensitiveCompare:right];
    }];
}

#pragma mark - Действия

/// Список действий строится по месту: у канала нельзя звать участников,
/// а из диалога — выходить. Пункты хранятся кодами, чтобы порядок и наличие
/// решались в одном месте.
- (NSArray *)actions {
    NSMutableArray *actions = [NSMutableArray array];
    [actions addObject:@"media"];
    [actions addObject:@"mute"];
    [actions addObject:@"clear"];

    if (!_chat.isDialog) {
        [actions addObject:@"add"];
        [actions addObject:@"leave"];
    }
    return actions;
}

- (NSString *)titleForAction:(NSString *)action {
    if ([action isEqualToString:@"media"]) return @"Медиа, файлы и ссылки";
    if ([action isEqualToString:@"mute"]) {
        return _chat.isMuted ? @"Включить уведомления" : @"Отключить уведомления";
    }
    if ([action isEqualToString:@"clear"]) return @"Очистить историю";
    if ([action isEqualToString:@"add"]) return @"Добавить участников";
    if ([action isEqualToString:@"leave"]) {
        return [_chat.type isEqualToString:@"CHANNEL"] ? @"Отписаться от канала" : @"Покинуть чат";
    }
    return action;
}

- (void)performAction:(NSString *)action {
    if ([action isEqualToString:@"media"]) {
        MAXChatMediaViewController *media =
            [[MAXChatMediaViewController alloc] initWithChat:_chat];
        [self.navigationController pushViewController:media animated:YES];
        return;
    }

    if ([action isEqualToString:@"mute"]) {
        // -1 — «навсегда», 0 — обратно. Промежуточных сроков в порте нет:
        // выбор длительности потребовал бы своего экрана.
        long long until = _chat.isMuted ? 0 : -1;
        __weak MAXChatInfoViewController *weakSelf = self;
        [[MAXChatsModule shared] setMuteUntil:until
                                      forChat:_chat.chatId
                                   completion:^(NSError *error) {
            MAXChatInfoViewController *strongSelf = weakSelf;
            if (strongSelf == nil) return;
            if (error != nil) {
                [strongSelf showAlert:@"Не вышло" message:error.localizedDescription];
                return;
            }
            [strongSelf->_tableView reloadData];
        }];
        return;
    }

    if ([action isEqualToString:@"clear"]) {
        _pendingAction = @"clear";
        id alert = [MAXTheme alertWithTitle:@"Очистить историю?"
                              message:@"Сообщения пропадут только у вас"
                             delegate:self
                    cancelButtonTitle:@"Отмена"
                     otherButtonTitle:@"Очистить"];
        [alert show];
        return;
    }

    if ([action isEqualToString:@"add"]) {
        MAXMemberPickerViewController *picker =
            [[MAXMemberPickerViewController alloc] initWithExcludedIds:_knownIds];
        picker.delegate = self;
        UINavigationController *stack =
            [[UINavigationController alloc] initWithRootViewController:picker];
        [MAXTheme applyToNavigationBar:stack.navigationBar];
        [self presentViewController:stack animated:YES completion:nil];
        return;
    }

    if ([action isEqualToString:@"leave"]) {
        _pendingAction = @"leave";
        id alert = [MAXTheme alertWithTitle:[self titleForAction:@"leave"]
                              message:@"Действие необратимо"
                             delegate:self
                    cancelButtonTitle:@"Отмена"
                     otherButtonTitle:@"Выйти"];
        [alert show];
    }
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    NSString *action = _pendingAction;
    _pendingAction = nil;

    if (buttonIndex == alertView.cancelButtonIndex || action == nil) return;

    __weak MAXChatInfoViewController *weakSelf = self;

    if ([action isEqualToString:@"clear"]) {
        [[MAXChatsModule shared] clearHistoryForChat:_chat.chatId
                                              forAll:NO
                                          completion:^(NSError *error) {
            MAXChatInfoViewController *strongSelf = weakSelf;
            if (strongSelf == nil || error == nil) return;
            [strongSelf showAlert:@"Не вышло" message:error.localizedDescription];
        }];
        return;
    }

    if ([action isEqualToString:@"leave"]) {
        [[MAXChatsModule shared] leaveChat:_chat.chatId completion:^(NSError *error) {
            MAXChatInfoViewController *strongSelf = weakSelf;
            if (strongSelf == nil) return;

            if (error != nil) {
                [strongSelf showAlert:@"Не вышло" message:error.localizedDescription];
                return;
            }
            // Возвращаемся сразу к списку чатов: и сведения, и сама переписка
            // теперь ведут в никуда.
            [strongSelf.navigationController popToRootViewControllerAnimated:YES];
        }];
    }
}

- (void)memberPicker:(MAXMemberPickerViewController *)picker didPickIds:(NSArray *)ids {
    [self dismissViewControllerAnimated:YES completion:nil];
    if (ids.count == 0) return;

    __weak MAXChatInfoViewController *weakSelf = self;
    [[MAXChatsModule shared] updateMembers:ids
                                   forChat:_chat.chatId
                                 operation:@"add"
                                completion:^(NSError *error) {
        MAXChatInfoViewController *strongSelf = weakSelf;
        if (strongSelf == nil) return;

        if (error != nil) {
            [strongSelf showAlert:@"Не добавились" message:error.localizedDescription];
            return;
        }
        [strongSelf addParticipantIds:ids];
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

#pragma mark - UITableView

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? (NSInteger)[self actions].count : (NSInteger)_participantIds.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return nil;
    if (_participantIds.count == 0) return nil;
    return _chat.isDialog ? @"Собеседник" : @"Участники";
}

- (UITableViewCell *)actionCellForTable:(UITableView *)tableView row:(NSUInteger)row {
    static NSString *identifier = @"MAXChatActionCell";

    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                      reuseIdentifier:identifier];
    }

    [MAXTheme applyToCell:cell];
    NSString *action = [self actions][row];
    cell.textLabel.text = [self titleForAction:action];
    cell.textLabel.font = [UIFont systemFontOfSize:16.0];
    if ([action isEqualToString:@"media"]) {
        [MAXTheme setDisclosureOnCell:cell];
    } else {
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.accessoryView = nil;
    }

    BOOL destructive = [action isEqualToString:@"leave"] || [action isEqualToString:@"clear"];
    cell.textLabel.textColor = destructive
        ? [MAXTheme destructiveColor]
        : [MAXTheme accentColor];

    return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        return [self actionCellForTable:tableView row:(NSUInteger)indexPath.row];
    }

    static NSString *identifier = @"MAXChatInfoCell";

    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    MAXAvatarView *avatar = nil;

    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                      reuseIdentifier:identifier];
        avatar = [[MAXAvatarView alloc] initWithFrame:CGRectMake(12, 8, 36, 36)];
        avatar.tag = 100;
        [cell.contentView addSubview:avatar];
    } else {
        avatar = (MAXAvatarView *)[cell.contentView viewWithTag:100];
    }

    [MAXTheme applyToCell:cell];
    long long contactId = [_participantIds[(NSUInteger)indexPath.row] longLongValue];
    MAXContact *contact = [[MAXChatsModule shared] contactWithId:contactId];

    NSString *name = contact.name.length > 0
        ? contact.name
        : [NSString stringWithFormat:@"ID %lld", contactId];

    cell.textLabel.text = name;
    cell.textLabel.font = [UIFont systemFontOfSize:16.0];
    cell.detailTextLabel.text = contact.phone > 0
        ? [NSString stringWithFormat:@"+%lld", contact.phone] : @"";
    cell.detailTextLabel.textColor = [MAXTheme secondaryTextColor];
    [MAXTheme setDisclosureOnCell:cell];

    // Место под аватарку: у стандартной ячейки текст начинается от края.
    cell.indentationLevel = 4;
    cell.indentationWidth = 10.0;

    [avatar setTitle:name avatarURL:contact.avatarUrl identifier:contactId];
    return cell;
}

/// Следующая страница состава — когда список подошёл к концу. У больших
/// каналов участников тысячи, тянуть их разом незачем.
- (void)tableView:(UITableView *)tableView
  willDisplayCell:(UITableViewCell *)cell
forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section != 1) return;
    if ((NSUInteger)indexPath.row + 10 < _participantIds.count) return;
    [self loadNextPage];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.section == 0) {
        [self performAction:[self actions][(NSUInteger)indexPath.row]];
        return;
    }

    long long contactId = [_participantIds[(NSUInteger)indexPath.row] longLongValue];
    MAXContactViewController *card =
        [[MAXContactViewController alloc] initWithContactId:contactId];
    [self.navigationController pushViewController:card animated:YES];
}

/// Смахиванием — удалить участника. Право на это есть не всегда; сервер
/// откажет, и мы вернём строку на место.
- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section != 1 || _chat.isDialog) return NO;
    return [_participantIds[(NSUInteger)indexPath.row] longLongValue]
        != [MAXChatsModule shared].currentUserId;
}

- (NSString *)tableView:(UITableView *)tableView
titleForDeleteConfirmationButtonForRowAtIndexPath:(NSIndexPath *)indexPath {
    return @"Удалить";
}

- (void)tableView:(UITableView *)tableView
commitEditingStyle:(UITableViewCellEditingStyle)editingStyle
forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle != UITableViewCellEditingStyleDelete) return;

    NSNumber *contactId = _participantIds[(NSUInteger)indexPath.row];

    __weak MAXChatInfoViewController *weakSelf = self;
    [[MAXChatsModule shared] updateMembers:@[contactId]
                                   forChat:_chat.chatId
                                 operation:@"remove"
                                completion:^(NSError *error) {
        MAXChatInfoViewController *strongSelf = weakSelf;
        if (strongSelf == nil) return;

        if (error != nil) {
            [strongSelf showAlert:@"Не удалось удалить" message:error.localizedDescription];
            return;
        }

        [strongSelf->_participantIds removeObject:contactId];
        [strongSelf->_knownIds removeObject:contactId];
        [strongSelf->_tableView reloadData];
    }];
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
