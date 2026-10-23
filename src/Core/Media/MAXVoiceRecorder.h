//
//  MAXVoiceRecorder.h
//  Max — запись голосового сообщения.
//
//  Дорога в два шага, и короче её на iOS 6 нет. `AVAudioRecorder` умеет
//  только AAC и линейный PCM, а сервер ждёт Opus, — значит пишем сырые
//  отсчёты в файл, а на остановке прогоняем их через свой кодировщик
//  (MAXOpus). Читается файл кусками, а не целиком: пять минут звука на
//  48 кГц — это почти тридцать мегабайт, и телефону тех лет столько разом
//  не поднять.
//
//  Живых буферов `AVAudioRecorder` не даёт, зато даёт замер громкости — по
//  нему и рисуется график, тот самый, что уезжает вместе с записью.
//
//  Порт Lovit/Core/Media/VoiceRecorder.cs.
//

#import <Foundation/Foundation.h>

/// Что получилось из записи.
@interface MAXVoiceTake : NSObject
/// Готовый Ogg с Opus внутри.
@property (nonatomic, strong) NSData *data;
@property (nonatomic, assign) NSInteger durationMs;
/// График громкости: восемьдесят столбиков высотой до 120.
@property (nonatomic, strong) NSData *wave;
/// Заполнено, если ничего не вышло; тогда `data` пуст.
@property (nonatomic, copy) NSString *error;
@end

@interface MAXVoiceRecorder : NSObject

+ (instancetype)shared;

@property (nonatomic, readonly) BOOL recording;

/// Сколько идёт запись, в секундах.
@property (nonatomic, readonly) NSTimeInterval elapsed;

/// Громкость прямо сейчас, от нуля до единицы — для живого графика.
@property (nonatomic, readonly) CGFloat level;

/// Спрошено ли уже разрешение на микрофон.
///
/// Система спрашивает его в тот миг, когда микрофон впервые открывают, — и,
/// спрашивая, отбирает у кнопки нажатие: для приложения это выглядит так,
/// будто палец отпустили, и запись кончается, не начавшись. Поэтому вопрос
/// задаётся заранее и отдельно, а запись начинается следующим удержанием.
/// На iOS 6 разрешения нет вовсе — там всегда YES.
+ (BOOL)permissionSettled;

/// Задать вопрос о микрофоне. `done` приходит на главную очередь.
+ (void)askPermission:(void (^)(BOOL granted))done;

/// Начать запись. Возвращает NO и объяснение, если не вышло: чаще всего это
/// запрет на микрофон.
- (BOOL)startWithProblem:(NSString **)problem;

/// Остановить и собрать готовое голосовое. Кодирование идёт с фоновой
/// очереди, `completion` приходит на главную.
- (void)stopWithCompletion:(void (^)(MAXVoiceTake *take))completion;

/// Бросить запись и ничего не собирать.
- (void)cancel;

@end
