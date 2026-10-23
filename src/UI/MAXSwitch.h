//
//  MAXSwitch.h
//  Переключатель в стиле iOS 7 — плоский, без глянца и надписей ON/OFF.
//
//  Своим он стал не от хорошей жизни: у `UISwitch` меняется ровно один
//  параметр вида — цвет включённого состояния. Форма, глянец и надписи
//  зашиты в систему, и на iOS 6 переключатель остаётся выпуклым синим
//  тумблером, как бы ни выглядело всё вокруг.
//
//  Наружу выставлены те же имена, что у `UISwitch` (`on`, `isOn`,
//  `setOn:animated:`, событие `UIControlEventValueChanged`), поэтому в местах
//  использования различима только сборка объекта — см. `MAXTheme.switchWithValue:`.
//

#import <UIKit/UIKit.h>

@interface MAXSwitch : UIControl

@property (nonatomic, assign, getter=isOn) BOOL on;

- (void)setOn:(BOOL)on animated:(BOOL)animated;

/// Размер фиксированный, как у системного: 51×31.
+ (CGSize)standardSize;

@end
