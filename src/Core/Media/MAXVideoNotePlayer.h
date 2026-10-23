//
//  MAXVideoNotePlayer.h
//  Max — проигрывание кружка на его месте в переписке.
//
//  Системным проигрывателем (`MPMoviePlayerController`) кружок не играем, и
//  это не выбор из вкусов: на iOS 6 он падал. В отчёте видно, что исключение
//  брошено внутри AVFoundation, а позвала её MediaPlayer со своей очереди, —
//  то есть поймать его снаружи нечем и поправить нечего. Заодно у системного
//  проигрывателя нельзя ни обрезать кадр в круг, ни оставить его в переписке.
//
//  Поэтому AVPlayer заводится своими руками, а кадр отдаётся слоем, который
//  можно положить куда угодно и обрезать как угодно.
//
//  Запись сперва скачивается целиком и играется с диска. Причина та же, что
//  у голосовых: своим корням мы верим сами (MAXHttp), а AVFoundation на iOS 6
//  проверяет цепочку системным хранилищем, где корней этого CDN нет вовсе.
//  Кружок короткий — минута при полутора мегабитах это около десяти
//  мегабайт, — так что скачать его целиком дешевле, чем объяснять
//  проигрывателю, кому верить.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

/// Что-то изменилось: началось, кончилось, подвинулось.
/// userInfo[@"messageId"] — чьё именно, если это известно.
extern NSString *const MAXVideoNotePlayerDidChangeNotification;

@interface MAXVideoNotePlayer : NSObject

+ (instancetype)shared;

/// Какой кружок сейчас занят проигрывателем, либо nil.
@property (nonatomic, readonly, copy) NSString *messageId;

/// Запись качается или раскладывается — играть ещё нечего.
@property (nonatomic, readonly) BOOL preparing;

/// Слой с кадром. Его и кладут в круглое окошко; существует, пока играет.
@property (nonatomic, readonly) AVPlayerLayer *playerLayer;

/// Насколько проиграно, от нуля до единицы.
@property (nonatomic, readonly) CGFloat progress;

/// Нажали на кружок: играет этот — остановить, иначе начать его.
- (void)toggleMessage:(NSString *)messageId url:(NSString *)url;

- (void)stop;

@end
