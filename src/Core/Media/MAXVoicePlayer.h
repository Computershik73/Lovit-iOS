//
//  MAXVoicePlayer.h
//  Max — проигрывание голосовых.
//
//  Присланное приходит в Opus внутри Ogg, а системный проигрыватель такого
//  файла не открывает вовсе. Поэтому запись скачивается, раскодируется своей
//  библиотекой (MAXOpus) в обычный WAV и уже его играет AVAudioPlayer.
//  Раскодированное остаётся на диске: второй раз то же голосовое
//  проигрывается сразу.
//
//  Проигрыватель один на всё приложение: два голосовых разом — это не
//  «удобно», а каша, и так же поступают и MAX, и Komet.
//

#import <Foundation/Foundation.h>

/// Что-то изменилось: началось, кончилось, подвинулось.
/// userInfo[@"messageId"] — чьё именно, если это известно.
extern NSString *const MAXVoicePlayerDidChangeNotification;

@interface MAXVoicePlayer : NSObject

+ (instancetype)shared;

/// Какое голосовое сейчас занято проигрывателем, либо nil.
@property (nonatomic, readonly, copy) NSString *messageId;

/// Идёт ли звук прямо сейчас. Пока запись качается и раскодируется — NO,
/// а `messageId` уже занят: по этой паре и рисуется «готовится».
@property (nonatomic, readonly) BOOL playing;

/// Готовится ли запись к проигрыванию — качается или раскодируется.
@property (nonatomic, readonly) BOOL preparing;

/// Насколько проигралось, от нуля до единицы.
@property (nonatomic, readonly) CGFloat progress;

/// Нажали на голосовое: играет это — остановить, иначе начать его.
- (void)toggleMessage:(NSString *)messageId url:(NSString *)url;

/// Остановить и освободить проигрыватель.
- (void)stop;

@end
