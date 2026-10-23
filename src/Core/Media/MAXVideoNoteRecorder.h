//
//  MAXVideoNoteRecorder.h
//  Max — съёмка кружка-видеосообщения.
//
//  Снимается он не `UIImagePickerController`: тому нельзя задать ни сторону
//  кадра, ни поток, ни частоту, а сервер принимает кружок только в строго
//  определённом виде (см. MAXMp4Facts.h). Поэтому кадры и звук берутся
//  сырыми из `AVCaptureSession` и складываются в файл `AVAssetWriter`ом —
//  ему и задаются все условия разом.
//
//  Одно здесь проще, чем на Windows Phone: там камера не умела обрезать
//  кадр, и квадрат приходилось добывать анаморфной записью с последующей
//  правкой SPS. Здесь достаточно попросить `AVVideoScalingModeResizeAspectFill`
//  — прямоугольник обрезается до квадрата по-настоящему, без чёрных полей и
//  без растягивания.
//
//  Порт Lovit/Core/Media/VideoNoteRecorder.cs.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

/// Что получилось из съёмки.
@interface MAXNoteTake : NSObject
/// Готовый mp4, уже приведённый к виду, который берёт сервер.
@property (nonatomic, strong) NSData *data;
@property (nonatomic, assign) NSInteger durationMs;
/// Заполнено, если ничего не вышло; тогда `data` пуст.
@property (nonatomic, copy) NSString *error;
@end

@interface MAXVideoNoteRecorder : NSObject

+ (instancetype)shared;

/// Сколько кружок длится самое большее. Столько же, сколько у настоящего
/// клиента; дальше запись заканчивается сама.
+ (NSTimeInterval)longest;

@property (nonatomic, readonly) BOOL recording;
@property (nonatomic, readonly) NSTimeInterval elapsed;

/// Какой камерой снимать. Меняется только между записями.
@property (nonatomic, assign) BOOL front;

/// Слой предпросмотра — его кладут в круглое окошко поверх переписки.
/// Существует, пока идёт съёмка.
@property (nonatomic, readonly) AVCaptureVideoPreviewLayer *previewLayer;

/// Спрошено ли разрешение на камеру. До iOS 7 его нет вовсе — там всегда YES.
+ (BOOL)permissionSettled;
+ (void)askPermission:(void (^)(BOOL granted))done;

/// Включить камеру и начать съёмку. `done` приходит на главную очередь:
/// камера открывается не мгновенно, и ждать её на месте нельзя.
- (void)startWithCompletion:(void (^)(BOOL ready, NSString *problem))done;

/// Остановить и отдать снятое. Приведение файла к виду, который берёт
/// сервер, идёт с фоновой очереди, `done` — на главной.
- (void)stopWithCompletion:(void (^)(MAXNoteTake *take))done;

/// Бросить съёмку и ничего не собирать.
- (void)cancel;

@end
