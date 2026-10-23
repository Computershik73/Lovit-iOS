//
//  MAXSettings.h
//  Max — пользовательские переключатели «невидимости».
//
//  Порт lib/core/config/komet_settings.dart (та часть, что влияет на протокол).
//
//  ghostMode  — в PING и LOGIN уходит interactive:false, сервер не поднимает
//               статус «онлайн».
//  antiRead   — CHAT_MARK не отправляется, отправитель не видит прочтение.
//  antiTyping — MSG_TYPING не отправляется.
//

#import <Foundation/Foundation.h>

extern NSString *const MAXSettingsDidChangeNotification;

@interface MAXSettings : NSObject

+ (BOOL)ghostMode;
+ (void)setGhostMode:(BOOL)value;

+ (BOOL)antiRead;
+ (void)setAntiRead:(BOOL)value;

+ (BOOL)antiTyping;
+ (void)setAntiTyping:(BOOL)value;

/// Значение поля `interactive` для PING и LOGIN.
+ (BOOL)interactive;

@end
