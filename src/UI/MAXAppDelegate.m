//
//  MAXAppDelegate.m
//

#import "MAXAppDelegate.h"
#import "MAXPhoneViewController.h"
#import "MAXChatsViewController.h"
#import "MAXContactsViewController.h"
#import "MAXSettingsViewController.h"
#import "MAXIcons.h"
#import "MAXApi.h"
#import "MAXAccountModule.h"
#import "MAXChatsModule.h"
#import "MAXTokenStorage.h"
#import "MAXProfile.h"
#import "MAXTheme.h"
#import "MAXKeyboardDismisser.h"
#import "MAXCrashHandler.h"

@implementation MAXAppDelegate

+ (MAXAppDelegate *)shared {
    return (MAXAppDelegate *)[UIApplication sharedApplication].delegate;
}

- (BOOL)application:(UIApplication *)application
didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    // Раньше всего остального: падение до этой строки объяснить будет нечем,
    // а после — уже есть чем. Отчёт системы называет место, но не причину:
    // у брошенного исключения вся суть в названии и объяснении, а их там нет.
    [MAXCrashHandler install];

    // Первая строка в журнале — она же признак, что журнал вообще работает:
    // без неё «файла нет» означает и «не пишется», и «нечего было писать».
    // Номер сборки в первой же строке: по нему видно, что на устройстве
    // именно свежий пакет, а не прежний, который установщик решил не менять.
    NSLog(@"[Max] Запуск, версия %@ (сборка %@), iOS %@",
          [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"],
          [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"],
          [[UIDevice currentDevice] systemVersion]);
    NSLog(@"[Max] Журнал: %@", MAXLogPath());

    // До постройки экранов: прокси UIAppearance действует только на то,
    // что создано после него.
    [MAXTheme applyAppearance];

    // Смахивание по клавиатуре закрывает её — на всех экранах сразу.
    [MAXKeyboardDismisser install];

    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    self.window.backgroundColor = [MAXTheme backgroundColor];

    // До постройки экранов и до соединения: имена и значки собеседников с
    // прошлого запуска. Список чатов приезжает быстро, а карточки к нему —
    // отдельными запросами и через несколько секунд; без этого всё это время
    // в списке стоят номера вместо имён.
    [[MAXChatsModule shared] loadCachedContacts];

    if ([MAXTokenStorage activeToken].length > 0) {
        self.window.rootViewController = [self buildTabBarController];
    } else {
        MAXPhoneViewController *phone = [[MAXPhoneViewController alloc] init];
        self.navigationController =
            [[UINavigationController alloc] initWithRootViewController:phone];
        [MAXTheme applyToNavigationBar:self.navigationController.navigationBar];
        self.window.rootViewController = self.navigationController;
    }

    [self.window makeKeyAndVisible];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(sessionExpired:)
                                                 name:MAXApiSessionExpiredNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(serverError:)
                                                 name:MAXApiErrorNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(themeChanged:)
                                                 name:MAXThemeDidChangeNotification
                                               object:nil];

    // Хэндшейк проходит при каждом коннекте; авто-логин вешается сюда, чтобы
    // после реконнекта сессия снова становилась авторизованной.
    __weak MAXAppDelegate *weakSelf = self;
    [MAXApi shared].reconnectHandler = ^{
        [weakSelf performAutoLogin];
    };
    [[MAXApi shared] connect];

    return YES;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)performAutoLogin {
    if ([MAXTokenStorage activeToken].length == 0) return;

    [[MAXAccountModule shared] loginWithCompletion:^(NSDictionary *payload,
                                                     MAXProfile *profile,
                                                     NSError *error) {
        if (error != nil) {
            NSLog(@"[Max] авто-логин не удался: %@", error.localizedDescription);
            return;
        }
        [[MAXChatsModule shared] applyLoginPayload:payload currentUserId:profile.profileId];
        [[MAXChatsModule shared] paginateChatsFromLoginPayload:payload];
    }];
}

/// Панель вкладок повторяет нижнюю панель MAX, только без звонков — их
/// в этом порте нет вовсе, и пустая вкладка была бы обманом.
- (UITabBarController *)buildTabBarController {
    MAXContactsViewController *contacts = [[MAXContactsViewController alloc] init];
    MAXChatsViewController *chats = [[MAXChatsViewController alloc] init];
    MAXSettingsViewController *settings = [[MAXSettingsViewController alloc] init];

    NSArray *screens = @[contacts, chats, settings];
    NSArray *titles = @[@"Контакты", @"Чаты", @"Настройки"];
    NSArray *icons = @[@"contacts", @"chatsFilled", @"settings"];

    NSMutableArray *stacks = [NSMutableArray array];
    for (NSUInteger i = 0; i < screens.count; i++) {
        UINavigationController *stack =
            [[UINavigationController alloc] initWithRootViewController:screens[i]];
        [MAXTheme applyToNavigationBar:stack.navigationBar];

        stack.tabBarItem = [MAXTheme tabBarItemWithTitle:titles[i]
                                                iconName:icons[i]
                                                     tag:(NSInteger)i];
        [stacks addObject:stack];
    }

    UITabBarController *tabs = [[UITabBarController alloc] init];
    tabs.viewControllers = stacks;
    tabs.selectedIndex = 1;   // «Чаты» — то, ради чего приложение открывают

    [MAXTheme applyToTabBar:tabs.tabBar];

    self.navigationController = stacks[1];
    return tabs;
}

- (void)showChats {
    self.window.rootViewController = [self buildTabBarController];
}

- (void)showAuth {
    MAXPhoneViewController *phone = [[MAXPhoneViewController alloc] init];
    self.navigationController =
        [[UINavigationController alloc] initWithRootViewController:phone];
    [MAXTheme applyToNavigationBar:self.navigationController.navigationBar];
    self.window.rootViewController = self.navigationController;
}

#pragma mark - Оформление

/**
 * Смена темы.
 *
 * Цвета в этом порте расставляются кодом, а не через `UIAppearance` и не через
 * динамические цвета iOS 13 — их нет ни в SDK 9.3, ни в iOS 6. Значит, уже
 * построенные экраны сами о смене не узнают, и единственный честный способ
 * показать новую тему целиком — собрать интерфейс заново.
 *
 * Открытая вкладка при этом сохраняется, а стеки навигации сбрасываются к
 * корню: переключатель темы лежит в корне «Настроек», так что видимый экран
 * остаётся тем же самым.
 */
- (void)themeChanged:(NSNotification *)note {
    self.window.backgroundColor = [MAXTheme backgroundColor];
    [MAXTheme applyAppearance];

    UIViewController *root = self.window.rootViewController;
    if (![root isKindOfClass:[UITabBarController class]]) {
        if ([MAXTokenStorage activeToken].length > 0) {
            [self showChats];
        } else {
            [self showAuth];
        }
        return;
    }

    NSUInteger selected = ((UITabBarController *)root).selectedIndex;
    UITabBarController *tabs = [self buildTabBarController];
    if (selected < tabs.viewControllers.count) {
        tabs.selectedIndex = selected;
        self.navigationController = tabs.viewControllers[selected];
    }
    self.window.rootViewController = tabs;
}

#pragma mark - Уведомления сессии

- (void)sessionExpired:(NSNotification *)note {
    NSString *message = note.userInfo[@"message"] ?: @"Сессия истекла";

    long long accountId = [MAXTokenStorage activeAccountId];
    if (accountId != 0) [MAXTokenStorage deleteAccount:accountId];
    [[MAXChatsModule shared] reset];

    id alert = [MAXTheme alertWithTitle:@"Сессия"
                              message:message
                             delegate:nil
                    cancelButtonTitle:@"OK"
                     otherButtonTitle:nil];
    [alert show];
    [self showAuth];
}

- (void)serverError:(NSNotification *)note {
    NSString *message = note.userInfo[@"message"];
    if (message.length == 0) return;

    id alert = [MAXTheme alertWithTitle:nil
                              message:message
                             delegate:nil
                    cancelButtonTitle:@"OK"
                     otherButtonTitle:nil];
    [alert show];
}

#pragma mark - Фон

- (void)applicationDidBecomeActive:(UIApplication *)application {
    [[MAXApi shared] wakeUp];
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
    // Соединение не рвём: iOS сама усыпит сокет, а wakeUp поднимет сессию.
    // А вот карточки кладём на диск сейчас же: следующего запуска приложение
    // может и не увидеть — система вправе снять его из фона молча.
    [[MAXChatsModule shared] persistContactsNow];
}

@end
