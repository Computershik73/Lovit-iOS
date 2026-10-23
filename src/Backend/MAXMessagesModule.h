//
//  MAXMessagesModule.h
//  Max — история и отправка сообщений.
//
//  Порт lib/backend/modules/messages.dart.
//

#import <Foundation/Foundation.h>

@class MAXMessage;

typedef void (^MAXHistoryCompletion)(NSArray *messages, NSError *error);
typedef void (^MAXSendCompletion)(NSString *messageId, NSError *error);
typedef void (^MAXVoidCompletionBlock)(NSError *error);

@interface MAXMessagesModule : NSObject

+ (instancetype)shared;

/// CHAT_HISTORY. `fromTime` = 0 — с текущего момента (+сутки, как в оригинале).
- (void)fetchHistoryForChat:(long long)chatId
                   fromTime:(long long)fromTime
                      count:(NSInteger)count
                 completion:(MAXHistoryCompletion)completion;

/// То же, но с обеих сторон от точки отсчёта.
///
/// `backward` — сколько взять из прошлого, `forward` — сколько из будущего.
/// Нужно при переходе к найденному или к источнику пересылки: с одним лишь
/// `backward` открывается хвост, обрывающийся на этом сообщении, и вниз
/// прокрутить нечего.
- (void)fetchHistoryForChat:(long long)chatId
                   fromTime:(long long)fromTime
                    forward:(NSInteger)forward
                   backward:(NSInteger)backward
                 completion:(MAXHistoryCompletion)completion;

/// MSG_SEND. cid — отрицательная метка времени, как у оригинального клиента.
- (void)sendText:(NSString *)text
          toChat:(long long)chatId
 replyToMessageId:(long long)replyToMessageId
      completion:(MAXSendCompletion)completion;

/// То же, но с разметкой, наложенной руками (MAXAppliedMarkup). Ссылки в
/// набранном по-прежнему ищутся сами и добавляются к ней.
- (void)sendText:(NSString *)text
          toChat:(long long)chatId
 replyToMessageId:(long long)replyToMessageId
          markup:(NSArray *)markup
      completion:(MAXSendCompletion)completion;

/// MSG_SEND с голосовым. Токен даёт -[MAXUploader uploadMedia:kind:…] с
/// видом 2; `wave` — график громкости, восемьдесят байтов.
- (void)sendVoiceToken:(NSString *)token
                toChat:(long long)chatId
            durationMs:(NSInteger)durationMs
                  wave:(NSData *)wave
      replyToMessageId:(long long)replyToMessageId
            completion:(MAXSendCompletion)completion;

/// MSG_SEND с кружком-видеосообщением.
///
/// От обычного ролика он отличается одним полем: `videoType` со значением
/// единица. По нему собеседник и показывает его в круге.
- (void)sendVideoNoteToken:(NSString *)token
                    toChat:(long long)chatId
                durationMs:(NSInteger)durationMs
          replyToMessageId:(long long)replyToMessageId
                completion:(MAXSendCompletion)completion;

/// MSG_SEND со стикером. У сообщения со стикером нет ни текста, ни файла —
/// сервер знает его по номеру.
- (void)sendSticker:(long long)stickerId
             toChat:(long long)chatId
   replyToMessageId:(long long)replyToMessageId
         completion:(MAXSendCompletion)completion;

/// MSG_EDIT — правка своего сообщения.
- (void)editMessage:(NSString *)messageId
             inChat:(long long)chatId
               text:(NSString *)text
         completion:(MAXVoidCompletionBlock)completion;

/// То же, с разметкой. Разметку приходится посылать заново: сервер заменяет
/// её целиком, и без этого правленое сообщение осталось бы без жирного.
- (void)editMessage:(NSString *)messageId
             inChat:(long long)chatId
               text:(NSString *)text
             markup:(NSArray *)markup
         completion:(MAXVoidCompletionBlock)completion;

/// MSG_DELETE. `forEveryone` — удалить у всех, иначе только у себя.
- (void)deleteMessages:(NSArray *)messageIds
                inChat:(long long)chatId
           forEveryone:(BOOL)forEveryone
            completion:(MAXVoidCompletionBlock)completion;

/// Пересылка: MSG_SEND с пустым сообщением и `link` типа FORWARD — то же,
/// что показывает разбор входящих пересылок.
- (void)forwardMessage:(NSString *)messageId
              fromChat:(long long)sourceChatId
                toChat:(long long)targetChatId
            completion:(MAXSendCompletion)completion;

/// MSG_REACTION / MSG_CANCEL_REACTION. Пустая строка снимает реакцию.
- (void)setReaction:(NSString *)emoji
         forMessage:(NSString *)messageId
             inChat:(long long)chatId
         completion:(MAXVoidCompletionBlock)completion;

/// MSG_TYPING. Не отправляется, если включён режим «не показывать набор».
- (void)sendTypingToChat:(long long)chatId;

/// MSG_SEND с вложением-фотографией. Токен даёт MAXUploader.
- (void)sendPhotoToken:(NSString *)photoToken
                toChat:(long long)chatId
               caption:(NSString *)caption
            completion:(MAXSendCompletion)completion;

/// MSG_SEND с вложением-файлом. Сервер принимает либо token, либо fileId.
- (void)sendFileToken:(NSString *)token
               fileId:(long long)fileId
                 name:(NSString *)name
               toChat:(long long)chatId
           completion:(MAXSendCompletion)completion;

/// CHAT_MEDIA — вложения чата одним списком: `attachTypes` это `PHOTO`,
/// `VIDEO`, `FILE`, `SHARE`. Возвращает сообщения (MAXMessage), из которых
/// вызывающий берёт нужные вложения. `anchorMessageId` = 0 — с конца.
- (void)fetchMediaForChat:(long long)chatId
          anchorMessageId:(NSString *)anchorMessageId
              attachTypes:(NSArray *)attachTypes
               completion:(MAXHistoryCompletion)completion;

/// FILE_DOWNLOAD: превращает пару baseUrl + token в прямую ссылку на файл.
- (void)resolveDownloadURLForBaseURL:(NSString *)baseURL
                               token:(NSString *)token
                          completion:(void (^)(NSString *url, NSError *error))completion;

/// VIDEO_PLAY — адрес видео.
///
/// Скачиванием файла его не взять: номер видео живёт в своём счёте, и
/// FILE_DOWNLOAD на него отвечает «файл не найден». В ответе не одна ссылка,
/// а набор качеств — от 144p до 1080p; берётся среднее, а не лучшее: у
/// телефона и экран мельче, и связь медленнее, а 1080p он к тому же может
/// и не потянуть.
- (void)resolveVideoURLForVideoId:(long long)videoId
                            token:(NSString *)token
                           chatId:(long long)chatId
                        messageId:(NSString *)messageId
                       completion:(void (^)(NSString *url, NSError *error))completion;

/// FILE_DOWNLOAD по идентификатору файла — так его просит Komet (`getFileUrl`):
/// `fileId` вместе с чатом и сообщением, в ответе поле `url`. Это основной путь
/// для вложений-файлов; вариант с baseUrl и токеном годится не для всех.
- (void)resolveFileURLForFileId:(long long)fileId
                         chatId:(long long)chatId
                      messageId:(NSString *)messageId
                     completion:(void (^)(NSString *url, NSError *error))completion;

@end
