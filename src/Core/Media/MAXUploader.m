//
//  MAXUploader.m
//

#import "MAXUploader.h"
#import "MAXApi.h"
#import "MAXOpcodes.h"
#import "MAXPacket.h"
#import "MAXHttp.h"

static NSString *const MAXUploaderErrorDomain = @"ru.max.uploader";

@implementation MAXUploader {
    dispatch_queue_t _queue;
}

+ (instancetype)shared {
    static MAXUploader *instance = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        instance = [[MAXUploader alloc] init];
    });
    return instance;
}

- (id)init {
    self = [super init];
    if (self) {
        _queue = dispatch_queue_create("ru.max.upload", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (NSError *)errorWithMessage:(NSString *)message code:(NSInteger)code {
    return [NSError errorWithDomain:MAXUploaderErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

#pragma mark - Фото

- (void)uploadPhoto:(NSData *)imageData
           fileName:(NSString *)fileName
         completion:(MAXUploadCompletion)completion {
    if (imageData.length == 0) {
        completion(nil, 0, [self errorWithMessage:@"Пустой файл" code:1]);
        return;
    }

    __weak MAXUploader *weakSelf = self;
    [[MAXApi shared] sendRequestWithOpcode:MAXOpcodePhotoUpload
                                   payload:@{@"count": @(1)}
                                completion:^(MAXPacket *packet, NSError *error) {
        MAXUploader *strongSelf = weakSelf;
        if (strongSelf == nil) return;

        if (error != nil) {
            completion(nil, 0, error);
            return;
        }

        NSString *url = packet.payloadMap[@"url"];
        if (![url isKindOfClass:[NSString class]] || url.length == 0) {
            completion(nil, 0, [strongSelf errorWithMessage:@"Сервер не дал адрес для загрузки"
                                                       code:2]);
            return;
        }

        [strongSelf postData:imageData
                    fileName:(fileName.length > 0 ? fileName : @"photo.jpg")
                   mimeType:@"image/jpeg"
                       toURL:url
                  completion:^(NSData *response, NSError *uploadError) {
            if (uploadError != nil) {
                completion(nil, 0, uploadError);
                return;
            }

            // CDN отвечает JSON'ом, форма которого меняется от типа загрузки,
            // поэтому токен ищется по всему дереву, а не по точному пути.
            NSString *token = [strongSelf findTokenInJSON:response];
            if (token.length == 0) {
                NSLog(@"[Max/Upload] В ответе CDN нет токена: %@",
                      [[NSString alloc] initWithData:response encoding:NSUTF8StringEncoding]);
                completion(nil, 0, [strongSelf errorWithMessage:@"CDN не вернул токен фото"
                                                           code:3]);
                return;
            }
            completion(token, 0, nil);
        }];
    }];
}

#pragma mark - Файл

- (void)uploadFile:(NSData *)fileData
          fileName:(NSString *)fileName
        completion:(MAXUploadCompletion)completion {
    if (fileData.length == 0) {
        completion(nil, 0, [self errorWithMessage:@"Пустой файл" code:1]);
        return;
    }

    __weak MAXUploader *weakSelf = self;
    [[MAXApi shared] sendRequestWithOpcode:MAXOpcodeFileUpload
                                   payload:@{@"count": @(1)}
                                completion:^(MAXPacket *packet, NSError *error) {
        MAXUploader *strongSelf = weakSelf;
        if (strongSelf == nil) return;

        if (error != nil) {
            completion(nil, 0, error);
            return;
        }

        id infoList = packet.payloadMap[@"info"];
        NSDictionary *info = ([infoList isKindOfClass:[NSArray class]] && [infoList count] > 0)
            ? [infoList objectAtIndex:0] : nil;

        NSString *url = info[@"url"];
        if (![url isKindOfClass:[NSString class]] || url.length == 0) {
            completion(nil, 0, [strongSelf errorWithMessage:@"Сервер не дал адрес для загрузки"
                                                       code:2]);
            return;
        }

        NSString *token = [info[@"token"] isKindOfClass:[NSString class]] ? info[@"token"] : nil;
        long long fileId = [info[@"fileId"] isKindOfClass:[NSNumber class]]
            ? [info[@"fileId"] longLongValue] : 0;

        [strongSelf postRawData:fileData
                       fileName:(fileName.length > 0 ? fileName : @"file.bin")
                          toURL:url
                     completion:^(NSData *response, NSError *uploadError) {
            if (uploadError != nil) {
                completion(nil, 0, uploadError);
                return;
            }
            completion(token, fileId, nil);
        }];
    }];
}

#pragma mark - Записи

- (void)uploadMedia:(NSData *)data
               kind:(NSInteger)kind
         completion:(MAXUploadCompletion)completion {
    if (data.length == 0) {
        completion(nil, 0, [self errorWithMessage:@"Пустая запись" code:1]);
        return;
    }

    NSDictionary *request = @{@"uploaderType": @(1),
                              @"type": @(kind),
                              @"count": @(1)};

    __weak MAXUploader *weakSelf = self;
    [[MAXApi shared] sendRequestWithOpcode:MAXOpcodeVideoUpload
                                   payload:request
                                completion:^(MAXPacket *packet, NSError *error) {
        MAXUploader *strongSelf = weakSelf;
        if (strongSelf == nil) return;

        if (error != nil) {
            completion(nil, 0, error);
            return;
        }

        id infoList = packet.payloadMap[@"info"];
        NSDictionary *info = ([infoList isKindOfClass:[NSArray class]] && [infoList count] > 0)
            ? [infoList objectAtIndex:0] : nil;

        NSString *url = info[@"url"];
        if (![url isKindOfClass:[NSString class]] || url.length == 0) {
            completion(nil, 0, [strongSelf errorWithMessage:@"Сервер не дал адрес для загрузки"
                                                       code:2]);
            return;
        }

        NSString *token = [info[@"token"] isKindOfClass:[NSString class]] ? info[@"token"] : nil;
        long long videoId = [info[@"videoId"] isKindOfClass:[NSNumber class]]
            ? [info[@"videoId"] longLongValue] : 0;

        NSString *name = [NSString stringWithFormat:@"%u", arc4random() & 0x7FFFFFFF];

        [strongSelf postRawData:data
                       fileName:name
                       mimeType:@"application/octet-stream"
                          toURL:url
                     completion:^(NSData *response, NSError *uploadError) {
            if (uploadError != nil) {
                completion(nil, 0, uploadError);
                return;
            }

            // Ответ CDN — в журнал целиком, насколько он короток. Сервер потом
            // отвечает одним «вложение в обработке», и без этой строки не
            // отличить «CDN отверг тело» от «CDN не успел его обработать».
            NSString *said = [[NSString alloc] initWithData:response
                                                   encoding:NSUTF8StringEncoding] ?: @"";
            NSLog(@"[Max/Upload] CDN о записи (%lu б): %@",
                  (unsigned long)response.length,
                  said.length > 200 ? [said substringToIndex:200] : said);

            if ([said rangeOfString:@"error" options:NSCaseInsensitiveSearch].location
                    != NSNotFound) {
                completion(nil, 0, [strongSelf errorWithMessage:@"CDN отверг запись" code:5]);
                return;
            }

            if (token.length == 0 && videoId == 0) {
                completion(nil, 0, [strongSelf errorWithMessage:@"Сервер не вернул токен записи"
                                                           code:6]);
                return;
            }
            completion(token, videoId, nil);
        }];
    }];
}

#pragma mark - HTTP

/// Тип части по расширению — как content_type_for_filename в ядре.
- (NSString *)mimeTypeForFileName:(NSString *)fileName {
    NSString *extension = [[fileName pathExtension] lowercaseString];

    if ([extension isEqualToString:@"jpg"] || [extension isEqualToString:@"jpeg"]) {
        return @"image/jpeg";
    }
    if ([extension isEqualToString:@"png"]) return @"image/png";
    if ([extension isEqualToString:@"gif"]) return @"image/gif";
    if ([extension isEqualToString:@"webp"]) return @"image/webp";
    if ([extension isEqualToString:@"mp4"]) return @"video/mp4";
    if ([extension isEqualToString:@"pdf"]) return @"application/pdf";
    return @"application/octet-stream";
}

/// Заголовок User-Agent, которым ядро подписывает заливку: он собирается
/// из тех же подменённых полей, что уходят в SESSION_INIT, — иначе сессия
/// и загрузка выглядели бы как разные устройства.
- (NSString *)httpUserAgent {
    NSDictionary *agent = [MAXApi shared].userAgent;
    if (agent == nil) return @"OKMessages/26.23.2";

    return [NSString stringWithFormat:@"OKMessages/%@ (%@; %@; %@)",
            agent[@"appVersion"] ?: @"",
            agent[@"osVersion"] ?: @"",
            agent[@"deviceName"] ?: @"",
            agent[@"screen"] ?: @""];
}

- (NSMutableURLRequest *)requestForURL:(NSString *)urlString {
    NSURL *url = [NSURL URLWithString:urlString];
    if (url == nil) return nil;

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    request.timeoutInterval = 120.0;
    [request setValue:@"keep-alive" forHTTPHeaderField:@"Connection"];
    [request setValue:[self httpUserAgent] forHTTPHeaderField:@"User-Agent"];
    return request;
}

/// Имя файла для заголовка — знаками из первой сотни таблицы.
///
/// Имя файла сервер берёт только отсюда, из заголовка, а заголовки по своему
/// устройству однобайтовые: русское имя, отправленное как есть, он прочитывал
/// побайтно и сохранял кракозябрами — «Лекция» у собеседника становилась
/// «ÐÐµÐºÑÐ¸Ñ». Так и появляются испорченные имена, которые приходится
/// чинить при получении (MAXRepairedFileName), — и наш же клиент их плодил.
///
/// Записываем его так же, как версия под Windows Phone (Uploader.Escape) и
/// любой браузер: каждый байт вне латиницы, цифр и «.-_~» — знаком процента
/// и двумя цифрами.
///
/// Здесь была ошибка в диагнозе. В 1.0.55 имя уже кодировалось, а в 1.0.61
/// я вернул «как есть», решив, что это кодирование и ломало отправку. Ломало
/// не оно: сервер отвечал «вложение ещё не готово» (см. MAXMessagesModule,
/// 1.0.63). Форма `filename=` с процентами — ровно та, что годами работает в
/// версии под Windows Phone на том же сервере.
- (NSString *)escapedFileName:(NSString *)fileName {
    if (fileName.length == 0) return @"file.bin";

    NSData *utf8 = [fileName dataUsingEncoding:NSUTF8StringEncoding];
    const uint8_t *bytes = utf8.bytes;
    NSMutableString *made = [NSMutableString stringWithCapacity:utf8.length * 3];

    for (NSUInteger i = 0; i < utf8.length; i++) {
        uint8_t value = bytes[i];
        BOOL plain = (value >= 'a' && value <= 'z') || (value >= 'A' && value <= 'Z')
                  || (value >= '0' && value <= '9')
                  || value == '.' || value == '-' || value == '_' || value == '~';

        if (plain) [made appendFormat:@"%c", value];
        else [made appendFormat:@"%%%02X", value];
    }
    return made;
}

/// Файл уходит сырым телом, а не формой.
///
/// Так делает ядро (upload_file в kolibri-net/src/media/upload.rs): один POST
/// с Content-Range на весь объём, тип application/x-binary и именем файла
/// в Content-Disposition. Раньше здесь была форма multipart — та же, что для
/// фото, — и это была ошибка: сервер такой файл не принимает.
- (void)postRawData:(NSData *)data
           fileName:(NSString *)fileName
              toURL:(NSString *)urlString
         completion:(void (^)(NSData *response, NSError *error))completion {
    [self postRawData:data fileName:fileName mimeType:nil toURL:urlString completion:completion];
}

- (void)postRawData:(NSData *)data
           fileName:(NSString *)fileName
           mimeType:(NSString *)mimeType
              toURL:(NSString *)urlString
         completion:(void (^)(NSData *response, NSError *error))completion {
    NSMutableURLRequest *request = [self requestForURL:urlString];
    if (request == nil) {
        completion(nil, [self errorWithMessage:@"Некорректный адрес загрузки" code:4]);
        return;
    }

    NSUInteger total = data.length;
    [request setValue:(mimeType ?: @"application/x-binary; charset=x-user-defined")
   forHTTPHeaderField:@"Content-Type"];
    [request setValue:[NSString stringWithFormat:@"attachment; filename=%@",
                       [self escapedFileName:fileName]]
   forHTTPHeaderField:@"Content-Disposition"];
    [request setValue:[NSString stringWithFormat:@"bytes 0-%lu/%lu",
                       (unsigned long)(total > 0 ? total - 1 : 0), (unsigned long)total]
   forHTTPHeaderField:@"Content-Range"];
    request.HTTPBody = data;

    // Что ответил CDN на сам файл — в журнал: когда отправка не складывается,
    // сервер потом говорит только «ошибка» на MSG_SEND, и по ней не понять,
    // дошёл ли файл вообще.
    [self sendRequest:request completion:^(NSData *response, NSError *error) {
        NSLog(@"[Max/Upload] CDN о файле «%@»: %@", fileName,
              error != nil
                  ? error.localizedDescription
                  : ([[NSString alloc] initWithData:response
                                           encoding:NSUTF8StringEncoding] ?: @"пусто"));
        completion(response, error);
    }];
}

/// Фото уходит формой multipart/form-data с полем «file» — так делает
/// upload_photo в ядре, и в ответе приходит JSON с photoToken.
- (void)postData:(NSData *)data
        fileName:(NSString *)fileName
        mimeType:(NSString *)mimeType
           toURL:(NSString *)urlString
      completion:(void (^)(NSData *response, NSError *error))completion {
    NSMutableURLRequest *request = [self requestForURL:urlString];
    if (request == nil) {
        completion(nil, [self errorWithMessage:@"Некорректный адрес загрузки" code:4]);
        return;
    }

    NSString *boundary = [NSString stringWithFormat:@"----MaxBoundary%08x%08x",
                          arc4random(), arc4random()];

    NSMutableData *body = [NSMutableData data];
    [body appendData:[[NSString stringWithFormat:
                       @"--%@\r\nContent-Disposition: form-data; name=\"file\"; "
                       @"filename=\"%@\"\r\nContent-Type: %@\r\n\r\n",
                       boundary, fileName,
                       (mimeType ?: [self mimeTypeForFileName:fileName])]
                      dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:data];
    [body appendData:[[NSString stringWithFormat:@"\r\n--%@--\r\n", boundary]
                      dataUsingEncoding:NSUTF8StringEncoding]];

    [request setValue:[NSString stringWithFormat:@"multipart/form-data; boundary=%@", boundary]
   forHTTPHeaderField:@"Content-Type"];
    request.HTTPBody = body;

    [self sendRequest:request completion:completion];
}

- (void)sendRequest:(NSURLRequest *)request
         completion:(void (^)(NSData *response, NSError *error))completion {
    dispatch_async(_queue, ^{
        NSHTTPURLResponse *response = nil;
        NSError *error = nil;
        // Через свой HTTP, а не через NSURLConnection: тот ходит системным
        // Secure Transport, а на iOS 6 он с этими узлами не договаривается
        // вовсе — см. MAXTls.h. Заодно снимается зависимость от системного
        // хранилища корней.
        NSData *result = [MAXHttp sendSynchronousRequest:request
                                                response:&response
                                                   error:&error];

        dispatch_async(dispatch_get_main_queue(), ^{
            if (error != nil) {
                completion(nil, error);
                return;
            }
            if (response.statusCode < 200 || response.statusCode >= 300) {
                completion(nil, [self errorWithMessage:
                    [NSString stringWithFormat:@"CDN ответил %ld", (long)response.statusCode]
                                                  code:5]);
                return;
            }
            completion(result, nil);
        });
    });
}

/// Ищет первое значение по ключу token/photoToken на любой глубине.
- (NSString *)findTokenInJSON:(NSData *)data {
    if (data.length == 0) return nil;

    id root = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    return [self findTokenInObject:root];
}

- (NSString *)findTokenInObject:(id)object {
    if ([object isKindOfClass:[NSDictionary class]]) {
        for (NSString *key in @[@"photoToken", @"token"]) {
            id value = ((NSDictionary *)object)[key];
            if ([value isKindOfClass:[NSString class]] && [value length] > 0) return value;
        }
        for (id value in [(NSDictionary *)object allValues]) {
            NSString *found = [self findTokenInObject:value];
            if (found != nil) return found;
        }
    } else if ([object isKindOfClass:[NSArray class]]) {
        for (id value in object) {
            NSString *found = [self findTokenInObject:value];
            if (found != nil) return found;
        }
    }
    return nil;
}

@end
