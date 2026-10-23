//
//  MAXPasswordViewController.h
//  Max — пароль второго фактора при входе (AUTH_LOGIN_CHECK_PASSWORD).
//

#import <UIKit/UIKit.h>
#import "MAXFormViewController.h"

@interface MAXPasswordViewController : MAXFormViewController

/// trackId из passwordChallenge в ответе AUTH.
@property (nonatomic, copy) NSString *trackId;

/// Подсказка к паролю, если владелец аккаунта её задал.
@property (nonatomic, copy) NSString *hint;

/// В какой сессии выдан `trackId` — [MAXApi shared].session на тот момент.
///
/// Сервер держит незаконченный вход при своей сессии. Оборвись связь, пока
/// набирают пароль, — и она поднимется сама, незаметно для человека, а
/// пароль уедет в сессию, где о нём уже никто не помнит: отказ будет
/// одинаковым на любой пароль. Сверка спасает от этой бессмыслицы.
@property (nonatomic, assign) NSUInteger authSession;

@end
