//
//  MAXWebP.h
//  Max — декодирование WebP.
//
//  Зачем это здесь. CDN картинок MAX отдаёт только WebP: согласования формата
//  у него нет, на любой Accept и любой User-Agent приходит `image/webp`
//  (проверено запросами к i.oneme.ru). ImageIO научился читать WebP только
//  в iOS 14, поэтому на iOS 7 `[UIImage imageWithData:]` возвращал nil —
//  без единой ошибки сети. Со стороны это выглядело так: фотографии в
//  переписке не появлялись, а при открытии показывался чёрный экран.
//
//  Декодер — libwebp (third_party/libwebp, BSD), только разбирающая часть.
//

#import <UIKit/UIKit.h>

@interface MAXWebP : NSObject

/// YES, если данные начинаются сигнатурой RIFF….WEBP.
+ (BOOL)isWebPData:(NSData *)data;

/// Возвращает картинку либо nil, если это не WebP или он повреждён.
+ (UIImage *)imageWithData:(NSData *)data;

@end
