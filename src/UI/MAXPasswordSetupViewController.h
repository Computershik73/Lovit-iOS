//
//  MAXPasswordSetupViewController.h
//  Установка и смена пароля для входа.
//
//  Один экран на два случая: пароля ещё нет — тогда спрашиваются новый
//  пароль, повтор, подсказка и необязательная почта; пароль есть — тогда
//  сверху добавляется поле текущего пароля, а почта не трогается.
//

#import "MAXFormViewController.h"

@interface MAXPasswordSetupViewController : MAXFormViewController <UITextFieldDelegate>

/// YES — смена существующего пароля: спрашивается ещё и текущий.
@property (nonatomic, assign) BOOL changingExisting;

/// Вызывается после успешной установки, чтобы предыдущий экран обновил
/// состояние.
@property (nonatomic, copy) void (^completion)(void);

@end
