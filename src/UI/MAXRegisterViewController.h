//
//  MAXRegisterViewController.h
//  Max — завершение регистрации (AUTH_CONFIRM).
//

#import <UIKit/UIKit.h>
#import "MAXFormViewController.h"

@interface MAXRegisterViewController : MAXFormViewController

/// Токен REGISTER из tokenAttrs ответа AUTH.
@property (nonatomic, copy) NSString *registerToken;

@end
