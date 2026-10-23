//
//  MAXAboutViewController.m
//

#import "MAXAboutViewController.h"
#import "MAXSecureStore.h"
#import "MAXTheme.h"

typedef NS_ENUM(NSInteger, MAXAboutSection) {
    MAXAboutSectionApp = 0,
    MAXAboutSectionDeveloper,
    MAXAboutSectionCount
};

@implementation MAXAboutViewController {
    // Ссылки лежат данными, а не в switch: строк здесь ровно столько же,
    // сколько записей, и добавление ссылки не требует править разметку.
    NSArray *_links;
}

- (id)init {
    self = [super initWithStyle:UITableViewStyleGrouped];
    if (self != nil) {
        _links = @[
            @{@"title": @"Профиль на 4PDA",
              @"detail": @"4pda.to",
              @"url": @"https://4pda.to/forum/index.php?showuser=4458524"},
            @{@"title": @"Канал в Telegram",
              @"detail": @"@cmplog",
              @"url": @"https://t.me/cmplog"},
            @{@"title": @"Поддержать финансово",
              @"detail": @"CloudTips",
              @"url": @"https://pay.cloudtips.ru/p/83821e32"},
        ];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"О приложении";
    [MAXTheme applyToTableView:self.tableView];
}

#pragma mark - Данные

- (NSString *)infoValueForKey:(NSString *)key {
    NSString *value = [[NSBundle mainBundle] objectForInfoDictionaryKey:key];
    return value.length > 0 ? value : @"—";
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return MAXAboutSectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case MAXAboutSectionApp: return 3;
        // Первая строка — имя автора, дальше по строке на ссылку.
        case MAXAboutSectionDeveloper: return 1 + (NSInteger)_links.count;
        default: return 0;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case MAXAboutSectionApp: return @"Приложение";
        case MAXAboutSectionDeveloper: return @"Разработчик";
        default: return nil;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    switch (section) {
        case MAXAboutSectionApp:
            // Где на деле лежат токены, видно только на устройстве: Keychain
            // на джейлбрейке зависит от прав в подписи, и при отказе всё
            // уезжает в настройки — переустановку такой вход не переживёт.
            return [NSString stringWithFormat:@"Токены и профиль устройства: %@.",
                    [MAXSecureStore storageDescription]];
        case MAXAboutSectionDeveloper:
            // Признание в самом приложении, а не только в README: протокол,
            // авторизация и слой подмен разобраны по Komet, и знать об этом
            // стоит тому, кто держит приложение в руках.
            return @"Ссылки открываются в Safari.\n\n"
                   @"Вдохновлено приложением Komet — клиентом MAX для Android. "
                   @"По нему разобраны протокол, авторизация и работа с чатами.";
        default:
            return nil;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc]
                             initWithStyle:UITableViewCellStyleValue1
                             reuseIdentifier:nil];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    [MAXTheme applyToCell:cell indexPath:indexPath inTableView:tableView];
    cell.textLabel.font = [UIFont systemFontOfSize:15.0];

    // Идентификатор пакета в правую колонку целиком не влезает на 320 точках,
    // а обрезанный он бесполезен — пусть лучше ужмётся шрифтом.
    cell.detailTextLabel.adjustsFontSizeToFitWidth = YES;
    cell.detailTextLabel.minimumFontSize = 10.0;

    if (indexPath.section == MAXAboutSectionApp) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Название";
            cell.detailTextLabel.text = [self infoValueForKey:@"CFBundleDisplayName"];
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"Версия";
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ (%@)",
                                         [self infoValueForKey:@"CFBundleShortVersionString"],
                                         [self infoValueForKey:@"CFBundleVersion"]];
        } else {
            cell.textLabel.text = @"Идентификатор";
            cell.detailTextLabel.text = [self infoValueForKey:@"CFBundleIdentifier"];
        }
        return cell;
    }

    if (indexPath.row == 0) {
        cell.textLabel.text = @"Автор";
        cell.detailTextLabel.text = @"Computershik";
        return cell;
    }

    NSDictionary *link = _links[(NSUInteger)(indexPath.row - 1)];
    cell.textLabel.text = link[@"title"];
    cell.detailTextLabel.text = link[@"detail"];
    cell.detailTextLabel.textColor = [MAXTheme accentColor];
    [MAXTheme setDisclosureOnCell:cell];
    cell.selectionStyle = UITableViewCellSelectionStyleBlue;
    return cell;
}

#pragma mark - Действия

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.section != MAXAboutSectionDeveloper || indexPath.row == 0) return;

    NSDictionary *link = _links[(NSUInteger)(indexPath.row - 1)];
    NSURL *url = [NSURL URLWithString:link[@"url"]];
    if (url != nil) [[UIApplication sharedApplication] openURL:url];
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
