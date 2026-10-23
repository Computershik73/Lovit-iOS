//
//  MAXWaveView.h
//  Max — график громкости голосового.
//
//  Столбики, а не линия: так их рисует и MAX, и все, у кого голосовые есть.
//  Проигранная часть закрашивается на ходу — по ней и видно, докуда дошло.
//
//  Рисуется вручную в drawRect:, а не набором подвидов: столбиков восемь
//  десятков, и восемьдесят UIView на каждый пузырь телефон тех лет не
//  прокрутит.
//

#import <UIKit/UIKit.h>

@interface MAXWaveView : UIView

/// Столбики от нуля до единицы. Пустой массив — рисуется ровная полоска.
@property (nonatomic, strong) NSArray *bars;

/// Сколько проиграно, от нуля до единицы.
@property (nonatomic, assign) CGFloat progress;

/// Цвета: закрашенная часть и остальное.
@property (nonatomic, strong) UIColor *playedColor;
@property (nonatomic, strong) UIColor *restColor;

@end
