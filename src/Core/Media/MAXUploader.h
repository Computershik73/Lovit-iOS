//
//  MAXUploader.h
//  Max — отправка вложений.
//
//  Порядок такой же, как в Komet (lib/backend/modules/file_uploader.dart):
//
//    1. по опкоду просим адрес для заливки —
//       FILE_UPLOAD {count:1} -> info[0] = {url, fileId, token}
//       PHOTO_UPLOAD {count:1} -> {url}
//    2. кладём байты по этому адресу обычным HTTP;
//    3. отправляем сообщение с вложением, ссылающимся на token/fileId.
//
//  Шаг 2 в Komet выполняет Rust-ядро (kolibri-net/src/media/upload.rs), и вид
//  запроса у него разный для фото и для файла — это не мелочь, сервер
//  принимает только своё:
//
//    фото  — POST multipart/form-data, поле «file», в ответе JSON с
//            photoToken;
//    файл  — POST, тело сырыми байтами (не multipart!), с заголовками
//            Content-Disposition: attachment и Content-Range на весь объём.
//
//  Здесь всё делается целиком из памяти: файлы, которые можно выбрать на
//  iOS 6, на порядок меньше того, ради чего ядру нужна потоковая заливка.
//

#import <Foundation/Foundation.h>

typedef void (^MAXUploadCompletion)(NSString *token, long long fileId, NSError *error);

@interface MAXUploader : NSObject

+ (instancetype)shared;

/// Фото: PHOTO_UPLOAD -> заливка -> photoToken из ответа CDN.
- (void)uploadPhoto:(NSData *)imageData
           fileName:(NSString *)fileName
         completion:(MAXUploadCompletion)completion;

/// Файл: FILE_UPLOAD -> заливка -> token и fileId из ответа опкода.
- (void)uploadFile:(NSData *)fileData
          fileName:(NSString *)fileName
        completion:(MAXUploadCompletion)completion;

/// Запись: голосовое или кружок. VIDEO_UPLOAD -> заливка -> token и videoId.
///
/// У этих вложений своя дорога, третья. Адрес спрашивается опкодом 82 с
/// полями `uploaderType` и `type` (1 — кружок, 2 — голосовое), а тело уходит
/// просто двоичным потоком: назвать часть «video/mp4» было бы естественно,
/// но на такую CDN отвечает BAD_REQUEST — проверено на клиенте под Windows
/// Phone. Имя части — число, как у настоящего клиента.
- (void)uploadMedia:(NSData *)data
               kind:(NSInteger)kind
         completion:(MAXUploadCompletion)completion;

@end
