//
//  MAXSearchViewController.m
//

#import "MAXSearchViewController.h"
#import "MAXChatViewController.h"
#import "MAXContactViewController.h"
#import "MAXTheme.h"
#import "MAXTextField.h"
#import "MAXAvatarView.h"
#import "MAXSearchModule.h"
#import "MAXChatsModule.h"
#import "MAXChat.h"
#import "MAXContact.h"

typedef NS_ENUM(NSInteger, MAXSearchSection) {
    MAXSearchSectionContacts = 0,
    MAXSearchSectionChats,
    MAXSearchSectionMessages,
    MAXSearchSectionPublic,
    MAXSearchSectionCount
};

static const CGFloat MAXSearchFieldHeight = 44.0;
static const CGFloat MAXSearchRowHeight = 56.0;

/// Задержка перед запросом. Без неё каждая набранная буква уходила бы
/// на сервер отдельным поиском; 0,3 с — то же значение, что в Komet.
static const NSTimeInterval MAXSearchDelay = 0.3;

@implementation MAXSearchViewController {
    UITextField *_field;
    UITableView *_tableView;
    UIActivityIndicatorView *_spinner;
    UILabel *_emptyLabel;

    NSArray *_contacts;   // MAXContact
    NSArray *_chats;      // MAXChat
    NSArray *_messages;   // MAXMessageHit
    NSArray *_public;     // MAXPublicHit

    /// Номер запроса. Ответы приходят вразнобой, и от старого запроса они
    /// приходят уже после того, как строка поиска сменилась.
    NSUInteger _sequence;
    NSUInteger _pending;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"Поиск";
    self.view.backgroundColor = [MAXTheme backgroundColor];

    if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)]) {
        self.edgesForExtendedLayout = UIRectEdgeNone;
    }

    CGRect bounds = self.view.bounds;

    _field = [[MAXTextField alloc] initWithFrame:
              CGRectMake(8, 6, bounds.size.width - 16, MAXSearchFieldHeight - 12)];
    _field.placeholder = @"Имя, чат, сообщение или канал";
    _field.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    _field.returnKeyType = UIReturnKeySearch;
    _field.clearButtonMode = UITextFieldViewModeWhileEditing;
    _field.delegate = self;
    [MAXTheme styleTextField:_field];
    [_field addTarget:self action:@selector(queryChanged)
     forControlEvents:UIControlEventEditingChanged];
    [self.view addSubview:_field];

    _tableView = [[UITableView alloc] initWithFrame:
                  CGRectMake(0, MAXSearchFieldHeight,
                             bounds.size.width, bounds.size.height - MAXSearchFieldHeight)
                                              style:UITableViewStylePlain];
    _tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth
                                | UIViewAutoresizingFlexibleHeight;
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.rowHeight = MAXSearchRowHeight;
    [MAXTheme applyToTableView:_tableView];
    [self.view addSubview:_tableView];

    _emptyLabel = [[UILabel alloc] initWithFrame:_tableView.frame];
    _emptyLabel.text = @"Ничего не нашлось";
    _emptyLabel.textAlignment = NSTextAlignmentCenter;
    _emptyLabel.font = [UIFont systemFontOfSize:15.0];
    _emptyLabel.textColor = [MAXTheme secondaryTextColor];
    _emptyLabel.backgroundColor = [UIColor clearColor];
    _emptyLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth
                                 | UIViewAutoresizingFlexibleHeight;
    _emptyLabel.hidden = YES;
    [self.view addSubview:_emptyLabel];

    _spinner = [[UIActivityIndicatorView alloc]
                initWithActivityIndicatorStyle:[MAXTheme activityIndicatorStyle]];
    _spinner.center = CGPointMake(CGRectGetMidX(bounds), MAXSearchFieldHeight + 40.0);
    _spinner.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin
                              | UIViewAutoresizingFlexibleRightMargin;
    [self.view addSubview:_spinner];

    // Отсюда открываются чаты и карточки; со словом «Поиск» на кнопке возврата
    // их заголовки съезжали с центра.
    self.navigationItem.backBarButtonItem = [MAXTheme backBarButtonItem];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [_field becomeFirstResponder];
}

#pragma mark - Запрос

- (void)queryChanged {
    [NSObject cancelPreviousPerformRequestsWithTarget:self
                                             selector:@selector(runSearch)
                                               object:nil];

    NSString *term = [_field.text stringByTrimmingCharactersInSet:
                      [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (term.length == 0) {
        _sequence++;
        _pending = 0;
        [_spinner stopAnimating];
        [self showResults:@[] chats:@[] messages:@[] public:@[]];
        _emptyLabel.hidden = YES;
        return;
    }

    [self performSelector:@selector(runSearch) withObject:nil afterDelay:MAXSearchDelay];
}

- (void)runSearch {
    NSString *term = _field.text;
    NSUInteger token = ++_sequence;

    // Своё — сразу: кэш в памяти, ждать нечего.
    MAXSearchModule *search = [MAXSearchModule shared];
    _contacts = [search localContactsMatching:term];
    _chats = [search localChatsMatching:term];
    _messages = @[];
    _public = @[];
    [self refresh];

    // Серверных запросов два, и ответы у них приходят порознь: считаем
    // незакрытые, чтобы крутилка погасла на последнем.
    _pending = 2;
    [_spinner startAnimating];

    __weak MAXSearchViewController *weakSelf = self;

    [search searchMessages:term completion:^(NSArray *hits, NSError *error) {
        MAXSearchViewController *strongSelf = weakSelf;
        if (strongSelf == nil || token != strongSelf->_sequence) return;

        strongSelf->_messages = hits ?: @[];
        [strongSelf finishOneRequest];
    }];

    [search searchPublic:term completion:^(NSArray *hits, NSError *error) {
        MAXSearchViewController *strongSelf = weakSelf;
        if (strongSelf == nil || token != strongSelf->_sequence) return;

        // Найденное на стороне сервера часто уже есть у нас: подписанный канал
        // приходит и в свои чаты, и в общий поиск. Дважды показывать не нужно.
        NSMutableSet *known = [NSMutableSet set];
        for (MAXChat *chat in strongSelf->_chats) [known addObject:@(chat.chatId)];

        NSMutableArray *fresh = [NSMutableArray array];
        for (MAXPublicHit *hit in hits) {
            if ([known containsObject:@(hit.chatId)]) continue;
            [fresh addObject:hit];
        }

        strongSelf->_public = fresh;
        [strongSelf finishOneRequest];
    }];
}

- (void)finishOneRequest {
    if (_pending > 0) _pending--;
    if (_pending == 0) [_spinner stopAnimating];
    [self refresh];
}

- (void)showResults:(NSArray *)contacts
              chats:(NSArray *)chats
           messages:(NSArray *)messages
             public:(NSArray *)publicHits {
    _contacts = contacts;
    _chats = chats;
    _messages = messages;
    _public = publicHits;
    [self refresh];
}

- (void)refresh {
    [_tableView reloadData];

    BOOL empty = (_contacts.count + _chats.count + _messages.count + _public.count) == 0;
    _emptyLabel.hidden = !(empty && _pending == 0 && _field.text.length > 0);
}

#pragma mark - UITableView

- (NSArray *)itemsInSection:(NSInteger)section {
    switch (section) {
        case MAXSearchSectionContacts: return _contacts;
        case MAXSearchSectionChats: return _chats;
        case MAXSearchSectionMessages: return _messages;
        default: return _public;
    }
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return MAXSearchSectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)[[self itemsInSection:section] count];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if ([[self itemsInSection:section] count] == 0) return nil;

    switch (section) {
        case MAXSearchSectionContacts: return @"Контакты";
        case MAXSearchSectionChats: return @"Чаты";
        case MAXSearchSectionMessages: return @"Сообщения";
        default: return @"Каналы и группы";
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"MAXSearchCell";
    static const NSInteger avatarTag = 100;

    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                      reuseIdentifier:identifier];
        cell.detailTextLabel.font = [UIFont systemFontOfSize:13.0];

        MAXAvatarView *avatar = [[MAXAvatarView alloc] initWithFrame:
                                 CGRectMake(12.0, (MAXSearchRowHeight - 40.0) / 2.0, 40.0, 40.0)];
        avatar.tag = avatarTag;
        [cell.contentView addSubview:avatar];

        cell.indentationLevel = 1;
        cell.indentationWidth = 52.0;
    }

    [MAXTheme applyToCell:cell];

    MAXChatsModule *module = [MAXChatsModule shared];
    MAXAvatarView *avatar = (MAXAvatarView *)[cell.contentView viewWithTag:avatarTag];
    id item = [[self itemsInSection:indexPath.section] objectAtIndex:(NSUInteger)indexPath.row];

    if (indexPath.section == MAXSearchSectionContacts) {
        MAXContact *contact = item;
        NSString *name = contact.name.length > 0
            ? contact.name : [NSString stringWithFormat:@"ID %lld", contact.contactId];

        cell.textLabel.text = name;
        cell.detailTextLabel.text = contact.phone > 0
            ? [NSString stringWithFormat:@"+%lld", contact.phone] : @"";
        [avatar setTitle:name avatarURL:contact.avatarUrl identifier:contact.contactId];
        return cell;
    }

    if (indexPath.section == MAXSearchSectionChats) {
        MAXChat *chat = item;
        NSString *title = [module displayTitleForChat:chat];

        cell.textLabel.text = title;
        cell.detailTextLabel.text = [module subtitleForChat:chat];
        [avatar setTitle:title avatarURL:[module avatarURLForChat:chat] identifier:chat.chatId];
        return cell;
    }

    if (indexPath.section == MAXSearchSectionMessages) {
        MAXMessageHit *hit = item;
        MAXChat *chat = [module chatWithId:hit.chatId];
        NSString *title = chat != nil
            ? [module displayTitleForChat:chat]
            : [NSString stringWithFormat:@"Чат %lld", hit.chatId];

        // Первой строкой чат, второй — найденный текст: искали по тексту,
        // но открывать придётся чат, и он важнее для узнавания.
        cell.textLabel.text = title;
        cell.detailTextLabel.text = hit.text;
        [avatar setTitle:title
               avatarURL:(chat != nil ? [module avatarURLForChat:chat] : nil)
              identifier:hit.chatId];
        return cell;
    }

    MAXPublicHit *hit = item;
    cell.textLabel.text = hit.title;
    cell.detailTextLabel.text = hit.subtitle;
    [avatar setTitle:hit.title avatarURL:hit.avatarUrl identifier:hit.chatId];
    return cell;
}

#pragma mark - Переходы

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    [_field resignFirstResponder];

    id item = [[self itemsInSection:indexPath.section] objectAtIndex:(NSUInteger)indexPath.row];

    if (indexPath.section == MAXSearchSectionContacts) {
        MAXContact *contact = item;
        MAXContactViewController *profile =
            [[MAXContactViewController alloc] initWithContactId:contact.contactId];
        [self.navigationController pushViewController:profile animated:YES];
        return;
    }

    if (indexPath.section == MAXSearchSectionChats) {
        [self openChat:item atMessage:nil time:0];
        return;
    }

    if (indexPath.section == MAXSearchSectionMessages) {
        MAXMessageHit *hit = item;
        MAXChat *chat = [[MAXChatsModule shared] chatWithId:hit.chatId];

        // Чата может не быть в кэше — например, сообщение из канала, который
        // давно пролистали. Открываем по заготовке: историю экран запросит сам.
        if (chat == nil) {
            chat = [[MAXChat alloc] init];
            chat.chatId = hit.chatId;
            chat.type = @"CHAT";
        }
        [self openChat:chat atMessage:hit.messageId time:hit.time];
        return;
    }

    [self openChat:[(MAXPublicHit *)item chatStub] atMessage:nil time:0];
}

- (void)openChat:(MAXChat *)chat atMessage:(NSString *)messageId time:(long long)time {
    MAXChatViewController *screen = [[MAXChatViewController alloc] initWithChat:chat];
    screen.initialMessageId = messageId;
    screen.initialMessageTime = time;
    [self.navigationController pushViewController:screen animated:YES];
}

#pragma mark - Прочее

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return NO;
}

- (void)dealloc {
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
}

- (void)tableView:(UITableView *)tableView
  willDisplayHeaderView:(UIView *)view
         forSection:(NSInteger)section {
    [MAXTheme applyToHeaderFooterView:view];
}

@end
