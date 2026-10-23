//
//  MAXMessage.h
//  Max — сообщение из CHAT_HISTORY / MSG_SEND / NOTIF_MESSAGE.
//
//  Порт CachedMessage из lib/backend/modules/messages.dart.
//

#import <Foundation/Foundation.h>

@interface MAXMessage : NSObject

@property (nonatomic, copy) NSString *messageId;
@property (nonatomic, assign) long long chatId;
@property (nonatomic, assign) long long senderId;
@property (nonatomic, copy) NSString *text;
@property (nonatomic, assign) long long time;
@property (nonatomic, copy) NSString *status;
@property (nonatomic, strong) NSDictionary *payload;
@property (nonatomic, assign) BOOL isControl;

/// Пересланное сообщение: у него самого нет ни текста, ни вложений — всё
/// лежит в `link.message`. Здесь тот самый вложенный словарь, либо nil.
@property (nonatomic, strong) NSDictionary *forwardedPayload;
/// Имя источника для пометки «Переслано»: для канала сервер даёт `chatName`.
@property (nonatomic, copy) NSString *forwardedFrom;
/// Автор исходного сообщения — по нему ищется контакт, когда имени нет.
@property (nonatomic, assign) long long forwardedSenderId;
/// Откуда переслано и что именно: этого хватает, чтобы открыть источник.
@property (nonatomic, assign) long long forwardedChatId;
@property (nonatomic, copy) NSString *forwardedMessageId;
@property (nonatomic, assign) long long forwardedTime;
/// Источник — канал. У Komet от этого зависит поведение нажатия.
@property (nonatomic, assign) BOOL forwardedIsChannel;

/// Сообщение, на которое отвечают (`link.type == REPLY`), либо nil. В отличие
/// от пересылки, у ответа своё содержимое на месте — это только цитата.
@property (nonatomic, strong) NSDictionary *replyPayload;
@property (nonatomic, assign) long long replySenderId;
@property (nonatomic, copy) NSString *replyMessageId;
@property (nonatomic, assign) long long replyTime;
/// Строка для цитаты: текст исходного сообщения либо метка вложения.
@property (nonatomic, readonly) NSString *replyPreview;

/// Реакции строкой — «👍 3  ❤️ 1» — либо nil, если их нет.
@property (nonatomic, readonly) NSString *reactionsSummary;
/// Реакция, которую поставил сам пользователь, либо nil.
@property (nonatomic, copy) NSString *myReaction;

/// Кладёт свежие счётчики реакций из пуша. Пересчитывать нечего — сервер
/// присылает их готовыми; своя реакция при этом не трогается: о ней пуш
/// говорит отдельным полем, а до его прихода правдивее то, что человек
/// только что нажал.
- (void)applyReactionCounters:(NSArray *)counters;

/// Поправляет счётчики под свою только что поставленную (или снятую) реакцию.
///
/// Нужна затем, чтобы своя реакция появлялась сразу, а не после того, как
/// сервер пришлёт пуш: без этого приходилось перечитывать всю историю, а
/// вместе с ней уезжала и прокрутка. Пуш придёт следом и всё уточнит.
/// Пустая строка в `emoji` — реакцию сняли.
- (void)applyMyReaction:(NSString *)emoji instead:(NSString *)previous;
/// Локальное сообщение, ещё не подтверждённое сервером.
@property (nonatomic, assign) BOOL isPending;

@property (nonatomic, readonly) NSDate *date;
/// Текст либо метка вложения — то, что показывается в пузыре.
@property (nonatomic, readonly) NSString *displayText;

/// Разметка текста (MAXTextRange): жирное, ссылки, упоминания и прочее.
///
/// Сервер шлёт её отдельным списком отрезков в `elements`, а не тегами
/// внутри текста. У пересылки текст и разметка лежат внутри `link.message` —
/// берётся то же место, откуда взят сам текст.
@property (nonatomic, readonly) NSArray *markupRanges;

/// Разобранные вложения (MAXAttachment) либо nil.
@property (nonatomic, readonly) NSArray *attachments;
/// Первое вложение-картинка, если оно есть.
@property (nonatomic, readonly) id photoAttachment;
/// Все картинки сообщения по порядку: их бывает несколько в одном пузыре.
@property (nonatomic, readonly) NSArray *photoAttachments;
/// Первое вложение-файл, если оно есть.
@property (nonatomic, readonly) id fileAttachment;
/// Голосовое сообщение, если это оно. У него своя строка в пузыре — с
/// графиком громкости и кнопкой, — а не общая с файлами.
@property (nonatomic, readonly) id voiceAttachment;

+ (instancetype)messageFromServerMap:(NSDictionary *)map chatId:(long long)chatId;

@end

/// Метка вложения для превью: «Фото», «Голосовое сообщение», «Стикер» и т. д.
/// Порт lib/backend/modules/chat_preview.dart.
NSString *MAXAttachmentPreviewLabel(id attaches);

/// Текст сообщения либо метка вложения.
NSString *MAXMessagePreviewText(NSDictionary *message);

/// Вложенное сообщение из `link`, если это пересылка (`link.type == FORWARD`).
/// У самой пересылки ни текста, ни вложений нет — всё содержимое здесь.
NSDictionary *MAXForwardedMessageFromPayload(NSDictionary *message);
