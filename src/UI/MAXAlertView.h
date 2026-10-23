//
//  MAXAlertView.h
//  Диалог в стиле iOS 7 — плоский короб с волосяными разделителями.
//
//  Системный `UIAlertView` на iOS 6 нарисован синим градиентом с тиснёными
//  кнопками, и оформлению не поддаётся вовсе: ни цвета, ни фона, ни шрифта
//  у него задать нельзя. Поэтому в современной теме показывается этот.
//
//  Набор имён повторяет `UIAlertView` ровно в том объёме, в каком порт им
//  пользуется, — включая `alertView:clickedButtonAtIndex:` у делегата.
//  Собирается он через `MAXTheme.alertWithTitle:…`, и место вызова не знает,
//  какой из двух перед ним.
//

#import <UIKit/UIKit.h>

@interface MAXAlertView : UIView

- (id)initWithTitle:(NSString *)title
            message:(NSString *)message
           delegate:(id)delegate
  cancelButtonTitle:(NSString *)cancelButtonTitle
   otherButtonTitle:(NSString *)otherButtonTitle;

/// Только `UIAlertViewStyleDefault` и `UIAlertViewStylePlainTextInput`:
/// остальными порт не пользуется.
@property (nonatomic, assign) UIAlertViewStyle alertViewStyle;
@property (nonatomic, weak) id delegate;
@property (nonatomic, readonly) NSInteger cancelButtonIndex;

/// Возвращает добавленный индекс — как у системного.
- (NSInteger)addButtonWithTitle:(NSString *)title;

- (UITextField *)textFieldAtIndex:(NSInteger)index;

- (void)show;

@end
