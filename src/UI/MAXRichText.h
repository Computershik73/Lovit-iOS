//
//  MAXRichText.h
//  Max — разметка внутри сообщения: жирное, наклонное, подчёркнутое,
//  моноширинное, ссылки и упоминания.
//
//  Сервер шлёт её не тегами внутри текста, а отдельным списком отрезков в
//  `elements`: у каждого вид, начало и длина. Отрезки накладываются друг на
//  друга — жирное внутри ссылки обычное дело, — поэтому текст режется по
//  всем их границам, и у каждого куска выходит свой набор признаков.
//
//  Порт Lovit/Ui/RichText.cs, который сам порт lib/core/utils/text_format.dart.
//

#import <UIKit/UIKit.h>

/// Один отрезок разметки.
@interface MAXTextRange : NSObject
@property (nonatomic, copy) NSString *type;
@property (nonatomic, assign) NSInteger start;
@property (nonatomic, assign) NSInteger length;
/// Адрес у ссылки; у остального пусто.
@property (nonatomic, copy) NSString *url;
@end

/// Разметка, наложенная на выделение в поле ввода.
///
/// Хранится вместе с куском текста, который покрывает. Живого пересчёта при
/// правке нет нарочно: слежение за границами на каждое нажатие клавиши — это
/// отдельный редактор, а ошибётся оно так, что жирным окажется не то слово.
/// Вместо этого перед отправкой каждый отрезок сверяется со своим куском и
/// отбрасывается, если тот уехал.
@interface MAXAppliedMarkup : NSObject
@property (nonatomic, copy) NSString *type;
@property (nonatomic, assign) NSInteger start;
@property (nonatomic, copy) NSString *covered;
@end

@interface MAXRichText : NSObject

/// Отрезки из поля `elements` ответа сервера. Пустой массив, если их нет.
+ (NSArray *)rangesFromElements:(id)elements;

/// Размеченная строка для показа в пузыре: базовый шрифт с наложенными
/// признаками. Возвращает nil, если размечать нечего — тогда вызывающему
/// дешевле оставить обычный текст.
+ (NSAttributedString *)attributedText:(NSString *)text
                                ranges:(NSArray *)ranges
                                  font:(UIFont *)font
                                 color:(UIColor *)color
                             linkColor:(UIColor *)linkColor;

/// Адреса всех ссылок сообщения по порядку, без повторов.
+ (NSArray *)linksInText:(NSString *)text ranges:(NSArray *)ranges;

/// Ссылки в набранном тексте.
///
/// Komet их сам не ищет — там разметку накладывают руками, — но без этого
/// набранная ссылка уходит простым текстом и у собеседника ссылкой не
/// становится. Ищется только со схемой или с «www»: «сходи в ок.ру» ссылкой
/// не является, и принимать за неё любое слово с точкой нельзя.
+ (NSArray *)detectLinksInText:(NSString *)text;

/// Готовый список для поля `elements` при отправке. nil, если размечать нечего.
+ (NSArray *)elementsForText:(NSString *)text;

/// То же, но с наложенным руками (MAXAppliedMarkup). Найденные ссылки
/// добавляются к нему.
+ (NSArray *)elementsForText:(NSString *)text applied:(NSArray *)applied;

/// Адрес, годный для открытия: без схемы «ok.ru» браузер не примет.
+ (NSURL *)absoluteURLFromString:(NSString *)address;

@end
