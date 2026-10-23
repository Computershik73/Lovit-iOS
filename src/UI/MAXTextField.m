//
//  MAXTextField.m
//

#import "MAXTextField.h"

static const CGFloat MAXTextFieldInset = 10.0;

@implementation MAXTextField

/**
 * Отступ по горизонтали — всё, что здесь считается.
 *
 * Вертикаль отдана системе намеренно. Своя строка высотой ровно в `lineHeight`,
 * поставленная по центру, выглядела правильно ровно до тех пор, пока поле
 * не оказывалось нулевой ширины: `CGRectInset` на такой ширине возвращает
 * `CGRectNull`, у которого начало координат — бесконечность, и набранное
 * уезжало из виду совсем. А ширина у поля нулевая в самом обычном случае —
 * его создают с `CGRectZero` и раскладывают позже.
 *
 * Выравнивание по вертикали задаётся теперь `contentVerticalAlignment`
 * в `MAXTheme.styleTextField:` — тем самым способом, для которого оно
 * и придумано.
 */
- (CGRect)textRectForBounds:(CGRect)bounds {
    if (bounds.size.width <= MAXTextFieldInset * 2.0) return bounds;

    return CGRectMake(bounds.origin.x + MAXTextFieldInset,
                      bounds.origin.y,
                      bounds.size.width - MAXTextFieldInset * 2.0,
                      bounds.size.height);
}

/// Текст, подсказка и курсор живут в одном прямоугольнике: посчитай их
/// по-разному — и при начале ввода текст прыгает.
- (CGRect)editingRectForBounds:(CGRect)bounds {
    return [self textRectForBounds:bounds];
}

- (CGRect)placeholderRectForBounds:(CGRect)bounds {
    return [self textRectForBounds:bounds];
}

@end
