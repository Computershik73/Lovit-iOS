//
//  MAXTheme.h
//  Max — цвета и мелкие помощники интерфейса.
//
//  Цвета сняты со скриншотов клиента MAX: синий акцент, светло-голубой фон
//  переписки, свои сообщения голубым пузырём справа, чужие — белым слева.
//
//  Оформление здесь раскладывается на две независимые оси:
//
//    * светлая / тёмная — что почём в палитре;
//    * скевоморфизм / современная — как это нарисовано: градиенты, рамки
//      и тени эпохи iOS 6 против плоских заливок iOS 7.
//
//  Оси не пересекаются и дают четыре сочетания. Системными средствами ни то,
//  ни другое не получить: `UIUserInterfaceStyle` появился в iOS 13, а нижняя
//  граница у нас 6.0, и рисовать «плоско» на iOS 6 система тоже не умеет.
//  Поэтому цвет и способ отрисовки спрашиваются у темы всегда — даже белый
//  фон, — и ни один экран не красит себя сам.
//

#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, MAXThemeMode) {
    MAXThemeModeSystem = 0,   // как в системе; до iOS 13 — светлая
    MAXThemeModeLight,
    MAXThemeModeDark
};

typedef NS_ENUM(NSInteger, MAXThemeStyle) {
    MAXThemeStyleSystem = 0,  // как в системе: до iOS 7 — скевоморфизм
    MAXThemeStyleSkeuomorphic,
    MAXThemeStyleModern
};

/// Тема сменилась: экраны пересобираются, содержимое не трогается.
extern NSString *const MAXThemeDidChangeNotification;

@interface MAXTheme : NSObject

+ (MAXThemeMode)mode;
+ (void)setMode:(MAXThemeMode)mode;

+ (MAXThemeStyle)style;
+ (void)setStyle:(MAXThemeStyle)style;

/// Названия для списка настроек.
+ (NSString *)nameForMode:(MAXThemeMode)mode;
+ (NSString *)nameForStyle:(MAXThemeStyle)style;

/// Тёмная ли тема сейчас — с учётом системной, если выбрана она.
+ (BOOL)isDark;

/// Скевоморфная ли — с учётом системного выбора.
+ (BOOL)isSkeuomorphic;

/// До iOS 7: разделение по возможностям, а не по вкусу — от него зависит,
/// какими ключами вообще можно что-то задать.
+ (BOOL)isLegacySystem;

+ (UIColor *)accentColor;            // синий MAX — кнопки и активные элементы
+ (UIColor *)badgeColor;             // счётчики непрочитанных и галочка
+ (UIColor *)destructiveColor;       // «Покинуть чат», «Заблокировать»

+ (UIColor *)backgroundColor;        // фон экранов и ячеек
+ (UIColor *)groupedBackgroundColor; // фон под группами в таблицах
+ (UIColor *)fieldBackgroundColor;   // подложка полей ввода
+ (UIColor *)barBackgroundColor;     // панели навигации, вкладок, строки ввода

+ (UIColor *)textColor;              // основной текст
+ (UIColor *)secondaryTextColor;     // подписи и подсказки
+ (UIColor *)placeholderColor;       // подсказка в пустом поле
+ (UIColor *)separatorColor;

+ (UIColor *)outgoingBubbleColor;    // свои сообщения
+ (UIColor *)incomingBubbleColor;    // чужие сообщения
+ (UIColor *)outgoingTextColor;
+ (UIColor *)incomingTextColor;
+ (UIColor *)chatBackgroundColor;    // фон переписки
+ (UIColor *)placeholderTileColor;   // подложка под ещё не загруженной картинкой

/// Цвет подписей на панели навигации и вкладок. Отдельно от `textColor`:
/// у скевоморфной панели фон свой и не обязан совпадать с фоном экрана.
+ (UIColor *)barTextColor;
+ (UIColor *)barTintColorForButtons;

/// Стиль клавиатуры под текущую тему.
+ (UIKeyboardAppearance)keyboardAppearance;

/// Общее оформление через UIAppearance: подписи кнопок панели навигации
/// и вкладок. Вызывать до того, как построен хоть один экран, — прокси
/// действует только на то, что создано после него.
+ (void)applyAppearance;

+ (void)applyToNavigationBar:(UINavigationBar *)navigationBar;

/// Нижняя панель. На iOS 6 и на iOS 7 у неё разные ключи оформления, и
/// одинаковый вид получается только разными способами.
+ (void)applyToTabBar:(UITabBar *)tabBar;

/// Таблица: фон, разделители и стиль под текущую тему.
+ (void)applyToTableView:(UITableView *)tableView;

/// Ячейка таблицы: фон, цвет текста и подсветка нажатия. Системные ячейки
/// в тёмной теме остаются белыми с чёрным текстом, если их не покрасить.
+ (void)applyToCell:(UITableViewCell *)cell;

/// То же, но с оглядкой на место строки в секции. Нужно скевоморфной теме
/// на iOS 7: там сгруппированная таблица идёт во всю ширину плоскими полосами,
/// а должна — вставленными блоками со скруглёнными краями.
+ (void)applyToCell:(UITableViewCell *)cell
          indexPath:(NSIndexPath *)indexPath
        inTableView:(UITableView *)tableView;

/// Заголовок или подпись секции таблицы. Система рисует их тёмно-серыми
/// со светлым ореолом — расчёт на светлый фон; в тёмной теме читать нечего.
+ (void)applyToHeaderFooterView:(UIView *)view;

/// Крутилка: серая на светлом, белая на тёмном.
+ (UIActivityIndicatorViewStyle)activityIndicatorStyle;

/// Пузырь сообщения: заливка, а в скевоморфной теме ещё градиент, рамка
/// и тень. Вызывать после того, как выставлен `frame`, — градиент рисуется
/// по текущим границам.
+ (void)applyBubbleStyleTo:(UIView *)view outgoing:(BOOL)outgoing;

/// Убирает пузырь совсем: ни заливки, ни рамки, ни тени, ни градиента.
/// Нужно стикеру — он рисуется прямо на фоне переписки, без облачка вокруг.
+ (void)clearBubbleStyleOf:(UIView *)view;

/// Стиль кнопок панели навигации.
+ (UIBarButtonItemStyle)barButtonStyle;

/// Кнопка возврата для `navigationItem.backBarButtonItem`.
///
/// До iOS 7 у неё нет стрелки — там это капсула с надписью, и пустое имя
/// означает пустую кнопку: вернуться из переписки было нечем. С iOS 7
/// стрелка рисуется сама, и надпись только отнимает место у заголовка.
+ (UIBarButtonItem *)backBarButtonItem;

/// Значок под текущий стиль: плоская заливка в современной теме, тиснёная
/// с градиентом — в скевоморфной. Все значки в приложении надо брать здесь,
/// а не у `MAXIcons` напрямую.
+ (UIImage *)iconNamed:(NSString *)name size:(CGFloat)size color:(UIColor *)color;

/// Микрофон для кнопки записи.
///
/// Рисуется здесь, а не берётся из MAXIconData: тот файл порождается
/// tools/extract-icons.py из ресурсов Android-клиента, микрофона среди
/// вытащенных путей нет, а дописывать в порождаемый файл руками — значит
/// потерять правку при следующем прогоне генератора.
+ (UIImage *)microphoneIconOfSize:(CGFloat)size color:(UIColor *)color;

/// Вкладка нижней панели. На iOS 6 система перерисовывает значок по-своему —
/// с тиснением и подсветкой; в современной теме это приходится обходить
/// готовыми картинками.
+ (UITabBarItem *)tabBarItemWithTitle:(NSString *)title
                             iconName:(NSString *)iconName
                                  tag:(NSInteger)tag;

/// Стрелка «дальше» и галочка выбора: системные до iOS 7 нарисованы
/// объёмными, поэтому в современной теме подставляются свои.
+ (void)setDisclosureOnCell:(UITableViewCell *)cell;
+ (void)setCheckmark:(BOOL)checked onCell:(UITableViewCell *)cell;

/// Переключатель: системный `UISwitch` в скевоморфной теме, свой плоский
/// `MAXSwitch` в современной. Возвращается `id`, но у обоих одинаковые
/// `isOn` / `setOn:animated:` и событие `UIControlEventValueChanged`.
+ (id)switchWithValue:(BOOL)value target:(id)target action:(SEL)action;

/// Предупреждение или вопрос. В скевоморфной теме это системный `UIAlertView`,
/// в современной — свой `MAXAlertView`: у системного на iOS 6 синий выпуклый
/// короб, который ничем не перекрасить.
///
/// У обоих одинаковые `show`, `addButtonWithTitle:`, `cancelButtonIndex`,
/// `textFieldAtIndex:` и `alertViewStyle`, а делегату приходит всё тот же
/// `alertView:clickedButtonAtIndex:`.
+ (id)alertWithTitle:(NSString *)title
             message:(NSString *)message
            delegate:(id)delegate
   cancelButtonTitle:(NSString *)cancelButtonTitle
    otherButtonTitle:(NSString *)otherButtonTitle;

/// Колонка содержимого для экранов, свёрстанных фреймами.
///
/// На телефоне это вся ширина за вычетом полей. На планшете — колонка не шире
/// 420 pt по центру: поле ввода номера, растянутое на 1024 pt, выглядит нелепо,
/// да и читать строку такой длины неудобно. Возвращает `x` и `width`; высота
/// в расчёте не участвует.
+ (CGRect)contentColumnInBounds:(CGRect)bounds;

/// Кнопка на всю ширину для экранов авторизации.
+ (UIButton *)primaryButtonWithTitle:(NSString *)title;

/// Кнопка отправки в строке ввода: капсула с градиентом в скевоморфной теме,
/// синяя надпись без подложки — в современной. Ширину задаёт вызывающий по
/// `sizeThatFits:`.
+ (UIButton *)composerSendButton;

/// Кнопка без подложки — синяя надпись. Замена `UIButtonTypeSystem`, которого
/// на iOS 6 нет: там та же константа означает `UIButtonTypeRoundedRect`
/// и рисует глянцевый белый прямоугольник.
+ (UIButton *)plainButtonWithTitle:(NSString *)title;

/// Скруглённая подложка для полей ввода.
+ (void)styleTextField:(UITextField *)textField;

/// «Сегодня», «Вчера» или «17 августа» — надпись над первым сообщением дня.
/// Год дописывается, только если он не нынешний.
+ (NSString *)daySeparatorFromMilliseconds:(long long)milliseconds;

/// Один ли это день. Нужно, чтобы понять, где в переписке начинается новый.
+ (BOOL)isSameDayMilliseconds:(long long)first and:(long long)second;

+ (NSString *)shortTimeFromMilliseconds:(long long)milliseconds;
+ (NSString *)relativeDateFromMilliseconds:(long long)milliseconds;

@end
