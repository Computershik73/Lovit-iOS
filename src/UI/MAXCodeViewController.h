//
//  MAXCodeViewController.h
//  Max — ввод кода из SMS (AUTH).
//

#import <UIKit/UIKit.h>
#import "MAXFormViewController.h"

@interface MAXCodeViewController : MAXFormViewController

/// Временный токен из AUTH_REQUEST.
@property (nonatomic, copy) NSString *authToken;
@property (nonatomic, copy) NSString *phone;

@end
