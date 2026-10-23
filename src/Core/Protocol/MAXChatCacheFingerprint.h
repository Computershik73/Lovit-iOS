//
//  MAXChatCacheFingerprint.h
//  Max — подделка отпечатка сборки Android-клиента.
//
//  Порт lib/core/protocol/chat_cache_fingerprint.md → chat_cache_fingerprint.dart.
//  Сервер ждёт три SHA-256 от «дайджестов» APK-подписи, classes.dex и .so —
//  здесь они зашиты константами оригинального клиента MAX, чтобы сессия
//  выглядела как официальное Android-приложение. Отпечаток уходит в LOGIN
//  (поле chatCacheFingerprint) и в AUTH_REQUEST (поле mode).
//

#import <Foundation/Foundation.h>

@interface MAXChatCacheFingerprint : NSObject

+ (NSData *)computeWithCallsSeed:(long long)callsSeed deviceId:(NSString *)deviceId;

@end
