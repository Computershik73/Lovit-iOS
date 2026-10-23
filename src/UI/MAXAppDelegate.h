//
//  MAXAppDelegate.h
//  Max
//

#import <UIKit/UIKit.h>

@interface MAXAppDelegate : UIResponder <UIApplicationDelegate>

@property (nonatomic, strong) UIWindow *window;
/// На экранах авторизации — обычный стек; после входа его место занимает
/// панель вкладок (Контакты / Чаты / Настройки).
@property (nonatomic, strong) UINavigationController *navigationController;

+ (MAXAppDelegate *)shared;

/// Показывает список чатов (после успешного входа).
- (void)showChats;

/// Показывает экран ввода телефона (после выхода или протухшей сессии).
- (void)showAuth;

@end
