//
//  MAXTranscripts.h
//  Max — расшифровка голосовых в текст.
//
//  Распознаёт не приложение, а сервер: ему называют чат, сообщение и запись,
//  он отвечает либо готовым текстом, либо «ещё считаю». Второе — обычное
//  дело: на запись в полминуты у него уходит несколько секунд.
//
//  Поэтому ответ ждут двумя путями сразу. Первый: сервер сам присылает
//  TRANSCRIPTION_RESULT, когда закончит. Второй: если не прислал, мы
//  переспрашиваем — несколько раз с передышкой. Один из двух обычно
//  срабатывает, а какой именно, человеку всё равно.
//
//  Расшифрованное держится в памяти до перезапуска: сервер отдаёт его
//  мгновенно при повторном вопросе, а места текст занимает немного.
//
//  Порт того, что в Komet сделано в MessagesModule.requestTranscription
//  и voice_bubble.dart.
//

#import <Foundation/Foundation.h>

/// Что сейчас с расшифровкой сообщения.
typedef enum {
    MAXTranscriptWaiting = 0,   ///< спросили, сервер ещё считает
    MAXTranscriptReady,         ///< текст есть
    MAXTranscriptFailed         ///< не вышло — текст объясняет, почему
} MAXTranscriptState;

@interface MAXTranscript : NSObject

@property (nonatomic, assign) MAXTranscriptState state;
/// Расшифровка либо строка о том, что происходит: её и показывают.
@property (nonatomic, copy) NSString *text;
/// Раскрыта ли она под сообщением. Нажатие на «Т» сворачивает и разворачивает.
@property (nonatomic, assign) BOOL shown;

@end

/// userInfo[@"messageId"] — чья расшифровка изменилась.
extern NSString *const MAXTranscriptsDidChangeNotification;

@interface MAXTranscripts : NSObject

+ (instancetype)shared;

/// Что известно про это сообщение; nil — не спрашивали.
- (MAXTranscript *)transcriptForMessageId:(NSString *)messageId;

/// Нажали «Т». Первый раз — спрашиваем сервер, дальше просто сворачиваем и
/// разворачиваем уже добытое.
- (void)toggleForMessageId:(NSString *)messageId
                    chatId:(long long)chatId
                   mediaId:(long long)mediaId;

/// Сбрасывает всё при смене аккаунта.
- (void)reset;

@end
