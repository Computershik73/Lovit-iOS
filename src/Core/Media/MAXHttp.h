//
//  MAXHttp.h
//  Max — HTTP с нашими корнями.
//
//  Зачем отдельный слой. Сокет протокола проверяет цепочку сам
//  (MAXConnection), подставляя вшитые корни. А `NSData dataWithContentsOfURL:`
//  и `NSURLConnection sendSynchronousRequest:` ходят через системное
//  хранилище — и другого пути им не задать. На старых iOS это значит отказ
//  на ровном месте:
//
//    api2.oneme.ru  ← Russian Trusted Sub CA ← Russian Trusted Root CA
//    i.oneme.ru     ← Let's Encrypt YR2      ← ISRG Root YR
//
//  Ни одного из этих корней в хранилище iOS 7 нет. Первый ломал бы протокол,
//  второй ломал именно картинки: фотографии в переписке не загружались, а
//  при открытии показывался чёрный экран — TLS обрывался раньше, чем
//  приходил хоть один байт.
//
//  Поэтому запросы идут через NSURLConnection с делегатом, который повторяет
//  проверку из MAXConnection: системные якоря плюс наши.
//

#import <Foundation/Foundation.h>

@interface MAXHttp : NSObject

/// Синхронный запрос. Вызывать только с фоновой очереди: метод крутит
/// собственный цикл выполнения, пока не придёт ответ.
+ (NSData *)sendSynchronousRequest:(NSURLRequest *)request
                          response:(NSHTTPURLResponse **)response
                             error:(NSError **)error;

/// Обычный GET по адресу. Возвращает nil при любой неудаче.
+ (NSData *)dataWithContentsOfURLString:(NSString *)urlString;

@end
