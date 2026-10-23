//
//  MAXChatsViewController.m
//

#import "MAXChatsViewController.h"
#import "MAXChatViewController.h"
#import "MAXSearchViewController.h"
#import "MAXChatCell.h"
#import "MAXTheme.h"
#import "MAXApi.h"
#import "MAXChatsModule.h"
#import "MAXSettings.h"
#import "MAXChat.h"
#import "MAXContact.h"
#import "MAXFoldersModule.h"
#import "MAXMemberPickerViewController.h"

static const CGFloat MAXTabsHeight = 44.0;

@implementation MAXChatsViewController {
    NSArray *_allChats;
    NSArray *_visibleChats;
    UIView *_tabsView;
    UIScrollView *_tabsScroll;
    NSMutableArray *_tabButtons;   // UIButton по индексу вкладки
    NSArray *_folders;             // MAXFolder, начиная с третьей вкладки
    NSInteger _selectedTab;        // 0 — все, 1 — новые, дальше папки
    UIView *_underline;
    UILabel *_emptyLabel;
    NSString *_pendingGroupTitle;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"Чаты";
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"Группа"
                                         style:[MAXTheme barButtonStyle]
                                        target:self
                                        action:@selector(startGroupCreation)];
    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"Поиск"
                                         style:[MAXTheme barButtonStyle]
                                        target:self
                                        action:@selector(openSearch)];

    self.tableView.rowHeight = [MAXChatCell rowHeight];
    [MAXTheme applyToTableView:self.tableView];
    // separatorInset появился в iOS 7; на 6.0 обращение к нему — падение
    // с unrecognized selector, поэтому спрашиваем.
    if ([self.tableView respondsToSelector:@selector(setSeparatorInset:)]) {
        self.tableView.separatorInset = UIEdgeInsetsMake(0, 76, 0, 0);
    }
    self.tableView.tableHeaderView = [self buildTabsView];

    _emptyLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _emptyLabel.text = @"Пока пусто";
    _emptyLabel.textAlignment = NSTextAlignmentCenter;
    _emptyLabel.textColor = [MAXTheme secondaryTextColor];
    _emptyLabel.font = [UIFont systemFontOfSize:15.0];
    _emptyLabel.backgroundColor = [UIColor clearColor];
    _emptyLabel.hidden = YES;
    [self.view addSubview:_emptyLabel];

    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    // Селектор наблюдателя обязан принимать уведомление: центр вызывает его
    // с объектом, и метод без аргументов — неопределённое поведение.
    [center addObserver:self selector:@selector(chatsChanged:)
                   name:MAXChatsDidChangeNotification object:nil];
    [center addObserver:self selector:@selector(stateChanged:)
                   name:MAXApiStateDidChangeNotification object:nil];
    [center addObserver:self selector:@selector(stateChanged:)
                   name:MAXSettingsDidChangeNotification object:nil];
    [center addObserver:self selector:@selector(foldersChanged:)
                   name:MAXFoldersDidChangeNotification object:nil];

    [self reload];
    [self updateTitle];

    // Папки приходят отдельным запросом: в ответе LOGIN их нет.
    [[MAXFoldersModule shared] fetchFolders];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reload];
    [self updateTitle];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    _emptyLabel.frame = CGRectMake(0, MAXTabsHeight + 40,
                                   self.view.bounds.size.width, 20);
}

#pragma mark - Вкладки

/// Полоска вкладок живёт в tableHeaderView, а не в отдельной панели: так она
/// уезжает вместе со списком, как в самом MAX.
///
/// Вкладок две постоянные — «Все» и «Новые», — а дальше идут папки аккаунта.
/// Их может быть сколько угодно и с любыми названиями, поэтому полоса
/// прокручивается вбок, а кнопки раскладываются по месту.
- (UIView *)buildTabsView {
    CGFloat width = self.view.bounds.size.width;

    _tabsView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, MAXTabsHeight)];
    _tabsView.backgroundColor = [MAXTheme barBackgroundColor];

    _tabsScroll = [[UIScrollView alloc] initWithFrame:
                   CGRectMake(0, 0, width, MAXTabsHeight)];
    _tabsScroll.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    _tabsScroll.showsHorizontalScrollIndicator = NO;
    _tabsScroll.backgroundColor = [UIColor clearColor];
    [_tabsView addSubview:_tabsScroll];

    _underline = [[UIView alloc] initWithFrame:CGRectZero];
    _underline.backgroundColor = [MAXTheme accentColor];
    [_tabsScroll addSubview:_underline];

    UIView *separator = [[UIView alloc] initWithFrame:
                         CGRectMake(0, MAXTabsHeight - 0.5, width, 0.5)];
    separator.backgroundColor = [MAXTheme separatorColor];
    separator.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [_tabsView addSubview:separator];

    _tabButtons = [NSMutableArray array];
    return _tabsView;
}

/// Названия вкладок по порядку. Папка «Все чаты» с сервера пропускается —
/// такая вкладка у нас и так первая.
- (NSArray *)tabTitles {
    NSUInteger unreadChats = 0;
    for (MAXChat *chat in _allChats) {
        if (chat.unreadCount > 0) unreadChats++;
    }

    NSMutableArray *titles = [NSMutableArray arrayWithObject:@"Все"];
    [titles addObject:(unreadChats > 0
                       ? [NSString stringWithFormat:@"Новые %lu", (unsigned long)unreadChats]
                       : @"Новые")];

    for (MAXFolder *folder in _folders) {
        [titles addObject:(folder.title.length > 0 ? folder.title : @"Папка")];
    }
    return titles;
}

- (void)refreshTabs {
    NSMutableArray *folders = [NSMutableArray array];
    for (MAXFolder *folder in [MAXFoldersModule shared].folders) {
        // Обе первые вкладки у нас свои и на языке приложения; папки с тем же
        // смыслом приходят с сервера переведёнными под язык устройства —
        // на испанском телефоне рядом с «Новые» вставала ещё и «Nuevas».
        if ([folder isAllChats] || [folder isUnreadOnly]) continue;
        [folders addObject:folder];
    }
    _folders = folders;

    if (_selectedTab > (NSInteger)_folders.count + 1) _selectedTab = 0;

    NSArray *titles = [self tabTitles];

    // Кнопки пересоздаются целиком: папки приходят пачкой и меняются редко,
    // а следить за соответствием старых кнопок новому списку — дороже.
    for (UIButton *button in _tabButtons) [button removeFromSuperview];
    [_tabButtons removeAllObjects];

    CGFloat x = 16.0;
    for (NSUInteger i = 0; i < titles.count; i++) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
        button.titleLabel.font = [UIFont boldSystemFontOfSize:16.0];
        button.tag = (NSInteger)i;
        [button setTitle:titles[i] forState:UIControlStateNormal];
        [button addTarget:self action:@selector(tabTapped:)
         forControlEvents:UIControlEventTouchUpInside];

        CGSize size = [titles[i] sizeWithFont:button.titleLabel.font];
        button.frame = CGRectMake(x, 4.0, size.width + 24.0, 32.0);
        x = CGRectGetMaxX(button.frame) - 4.0;

        BOOL active = ((NSInteger)i == _selectedTab);
        [button setTitleColor:(active ? [MAXTheme textColor] : [MAXTheme secondaryTextColor])
                     forState:UIControlStateNormal];

        [_tabsScroll addSubview:button];
        [_tabButtons addObject:button];

        if (active) {
            _underline.frame = CGRectMake(CGRectGetMinX(button.frame) + 12.0,
                                          MAXTabsHeight - 3.0,
                                          CGRectGetWidth(button.frame) - 24.0, 3.0);
        }
    }

    _tabsScroll.contentSize = CGSizeMake(x + 16.0, MAXTabsHeight);
}

- (void)tabTapped:(UIButton *)sender {
    _selectedTab = sender.tag;
    [self reload];
}

- (void)foldersChanged:(NSNotification *)note {
    [self reload];
}

#pragma mark - Поворот

/// Полоска вкладок лежит в tableHeaderView и её ширина не тянется сама:
/// таблица считает заголовок неизменным, пока его не переставят заново.
- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation {
    [super didRotateFromInterfaceOrientation:fromInterfaceOrientation];

    CGRect frame = _tabsView.frame;
    frame.size.width = self.view.bounds.size.width;
    _tabsView.frame = frame;
    self.tableView.tableHeaderView = _tabsView;

    [self refreshTabs];
    [self.tableView reloadData];
}

- (BOOL)shouldAutorotate {
    return YES;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskAllButUpsideDown;
}

#pragma mark - Данные

- (void)chatsChanged:(NSNotification *)note {
    [self reload];
}

- (void)stateChanged:(NSNotification *)note {
    [self updateTitle];
}

- (void)reload {
    MAXChatsModule *chats = [MAXChatsModule shared];
    _allChats = chats.chats;

    _visibleChats = [self chatsForSelectedTab];

    [self refreshTabs];
    [self.tableView reloadData];

    _emptyLabel.hidden = _visibleChats.count > 0;
    _emptyLabel.text = _selectedTab == 1 ? @"Непрочитанных нет" : @"Пока пусто";
}

/// Чаты выбранной вкладки. Папка — это правило отбора, а не список: состав
/// считается здесь, по тем чатам, что уже есть в памяти.
- (NSArray *)chatsForSelectedTab {
    if (_selectedTab == 0) return _allChats;

    if (_selectedTab == 1) {
        NSMutableArray *unread = [NSMutableArray array];
        for (MAXChat *chat in _allChats) {
            if (chat.unreadCount > 0) [unread addObject:chat];
        }
        return unread;
    }

    NSUInteger index = (NSUInteger)_selectedTab - 2;
    if (index >= _folders.count) return _allChats;

    MAXChatsModule *module = [MAXChatsModule shared];
    MAXFolder *folder = _folders[index];

    NSMutableSet *contactIds = [NSMutableSet set];
    for (MAXContact *contact in module.contacts) {
        [contactIds addObject:@(contact.contactId)];
    }

    NSMutableArray *found = [NSMutableArray array];
    for (MAXChat *chat in _allChats) {
        if ([folder matchesChat:chat
                  currentUserId:module.currentUserId
                     contactIds:contactIds]) {
            [found addObject:chat];
        }
    }
    return found;
}

- (void)updateTitle {
    switch ([MAXApi shared].state) {
        case MAXSessionStateDisconnected:
            self.title = @"Нет сети";
            break;
        case MAXSessionStateConnecting:
            self.title = @"Подключение…";
            break;
        case MAXSessionStateConnected:
            self.title = @"Рукопожатие…";
            break;
        case MAXSessionStateOnline:
            self.title = [MAXSettings ghostMode] ? @"Чаты (невидимка)" : @"Чаты";
            break;
    }
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)_visibleChats.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"MAXChatCell";

    MAXChatCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (cell == nil) {
        cell = [[MAXChatCell alloc] initWithStyle:UITableViewCellStyleDefault
                                  reuseIdentifier:identifier];
    }

    // Своя ячейка, но фон у неё всё равно системный — белый. В тёмной теме
    // строки от этого оставались белыми, а имена, покрашенные под тёмный фон,
    // на них пропадали.
    [MAXTheme applyToCell:cell];

    MAXChatsModule *module = [MAXChatsModule shared];
    MAXChat *chat = _visibleChats[(NSUInteger)indexPath.row];

    [cell configureWithChat:chat
                      title:[module displayTitleForChat:chat]
                  avatarURL:[module avatarURLForChat:chat]];
    return cell;
}

#pragma mark - Поиск

- (void)openSearch {
    [self.navigationController pushViewController:[[MAXSearchViewController alloc] init]
                                        animated:YES];
}

#pragma mark - Создание группы

/// Сначала название, потом участники: имя спрашивается в поле ввода алерта —
/// своего экрана ради одной строки заводить незачем.
- (void)startGroupCreation {
    id alert = [MAXTheme alertWithTitle:@"Новая группа"
                              message:@"Как её назвать?"
                             delegate:self
                    cancelButtonTitle:@"Отмена"
                     otherButtonTitle:@"Дальше"];
    // Точечная запись у `id` не работает — фабрика темы отдаёт именно его.
    [alert setAlertViewStyle:UIAlertViewStylePlainTextInput];
    [alert show];
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (buttonIndex == alertView.cancelButtonIndex) return;

    NSString *title = [[alertView textFieldAtIndex:0].text
                       stringByTrimmingCharactersInSet:
                       [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (title.length == 0) return;

    _pendingGroupTitle = title;

    MAXMemberPickerViewController *picker =
        [[MAXMemberPickerViewController alloc] initWithExcludedIds:nil];
    picker.delegate = self;

    UINavigationController *stack =
        [[UINavigationController alloc] initWithRootViewController:picker];
    [MAXTheme applyToNavigationBar:stack.navigationBar];
    [self presentViewController:stack animated:YES completion:nil];
}

- (void)memberPicker:(MAXMemberPickerViewController *)picker didPickIds:(NSArray *)ids {
    [self dismissViewControllerAnimated:YES completion:nil];

    NSString *title = _pendingGroupTitle;
    _pendingGroupTitle = nil;
    if (ids.count == 0 || title.length == 0) return;

    __weak MAXChatsViewController *weakSelf = self;
    [[MAXChatsModule shared] createGroupWithTitle:title
                                          userIds:ids
                                       completion:^(MAXChat *chat, NSError *error) {
        MAXChatsViewController *strongSelf = weakSelf;
        if (strongSelf == nil) return;

        if (error != nil || chat == nil) {
            id alert = [MAXTheme alertWithTitle:@"Не создалась"
                              message:error.localizedDescription
                             delegate:nil
                    cancelButtonTitle:@"OK"
                     otherButtonTitle:nil];
            [alert show];
            return;
        }

        MAXChatViewController *screen = [[MAXChatViewController alloc] initWithChat:chat];
        [strongSelf.navigationController pushViewController:screen animated:YES];
    }];
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    MAXChat *chat = _visibleChats[(NSUInteger)indexPath.row];
    MAXChatViewController *chatScreen = [[MAXChatViewController alloc] initWithChat:chat];
    [self.navigationController pushViewController:chatScreen animated:YES];
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
