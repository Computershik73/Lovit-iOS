//
//  MAXAttachment.h
//  Max — вложение сообщения.
//
//  Урезанный порт lib/models/attachment.dart: из полутора десятков типов
//  здесь разбираются те, что участвуют в показе и скачивании. Остальные
//  доезжают как `MAXAttachmentTypeOther` и показываются меткой из
//  MAXAttachmentPreviewLabel.
//

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, MAXAttachmentType) {
    MAXAttachmentTypeOther = 0,
    MAXAttachmentTypePhoto,
    MAXAttachmentTypeVideo,
    MAXAttachmentTypeAudio,
    MAXAttachmentTypeFile,
    MAXAttachmentTypeSticker,
    MAXAttachmentTypeControl
};

/// Чинит имя файла, испорченное двойной перекодировкой на той стороне
/// («ÐÐµÐºÑÐ¸Ñ.pptx» -> «Лекция.pptx»). Целое имя возвращает как есть.
/// Подробности — у самой функции в MAXAttachment.m.
///
/// Снаружи нужна строке списка чатов: там «Файл: …» собирается прямо из
/// сырого сообщения, мимо разбора вложения.
NSString *MAXRepairedFileName(NSString *name);

@interface MAXAttachment : NSObject

@property (nonatomic, assign) MAXAttachmentType type;

/// Прямая ссылка на картинку, если сервер её уже дал.
@property (nonatomic, copy) NSString *previewUrl;

/// Кадр ролика — то, что показывается до проигрывания.
///
/// У видео он приходит **отдельным полем** `thumbnail`, а `previewUrl` у него
/// не бывает вовсе: из-за этого кружок до запуска оставался чёрным кругом.
/// Если и `thumbnail` нет, кадром служит `baseUrl`: у ролика по этому адресу
/// лежит не сам ролик, а его картинка.
@property (nonatomic, copy) NSString *thumbnailUrl;

/// Кадр, вложенный в само сообщение, — байтами и без всякого адреса.
/// Его видно сразу, не дожидаясь сети; он крошечный и оттого размытый.
@property (nonatomic, strong) NSData *previewBytes;
/// Адрес для FILE_DOWNLOAD, когда прямой ссылки нет.
@property (nonatomic, copy) NSString *baseUrl;
@property (nonatomic, copy) NSString *token;
@property (nonatomic, assign) long long fileId;

@property (nonatomic, copy) NSString *name;
@property (nonatomic, assign) long long size;

/// Длительность записи в миллисекундах — у голосового и у видео.
@property (nonatomic, assign) long long duration;

/// График громкости голосового: по байту на столбик, обычно восемьдесят.
/// Значение — высота столбика от нуля до 120. nil, если сервер его не дал.
@property (nonatomic, strong) NSData *wave;

/// Номер стикера. По нему находится набор, из которого он взят, — этим и
/// открывается предпросмотр набора по нажатию. У прочих вложений ноль.
@property (nonatomic, assign) long long stickerId;

/// Описание движущегося стикера. Не картинка, а векторная сцена во времени:
/// показать её можно только отрисовав (MAXLottie). nil у неподвижных.
@property (nonatomic, copy) NSString *lottieUrl;

/// Кружок-видеосообщение, а не обычный ролик. Отличается одним полем —
/// `videoType` со значением единица, — и показывается кругом, без пузыря.
@property (nonatomic, assign) BOOL isVideoNote;
@property (nonatomic, assign) CGFloat width;
@property (nonatomic, assign) CGFloat height;

/// Пропорции для показа: высота при заданной ширине, с разумными пределами.
- (CGFloat)displayHeightForWidth:(CGFloat)width;

/// «1,4 МБ» — подпись под именем файла.
- (NSString *)humanReadableSize;

/// «0:07» — длительность записи для подписи.
- (NSString *)humanReadableDuration;

/// Столбики графика, приведённые к 0..1. Пустой массив, если графика нет.
/// `count` — сколько их нужно: у сервера их восемьдесят, а на экране
/// помещается меньше.
- (NSArray *)waveBarsCount:(NSUInteger)count;

+ (NSArray *)attachmentsFromMessagePayload:(NSDictionary *)payload;

@end
