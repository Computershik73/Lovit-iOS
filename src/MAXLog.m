//
//  MAXLog.m
//

#import "MAXLog.h"

/**
 * Здесь NSLog нужен настоящий.
 *
 * Ключ -include подставляет MAXLog.h в самое начало каждого файла, включая
 * этот, — раньше любых наших строк. Поэтому объявить что-либо «до» подмены
 * нельзя, её можно только снять, и делается это здесь.
 */
#undef NSLog

/**
 * Потолок на размер журнала.
 *
 * Приложение пишет на каждый запрос и каждый пуш, и без потолка файл рос бы
 * неограниченно. По достижении предела он откладывается в сторону и
 * начинается новый: под рукой всегда есть не меньше четверти мегабайта
 * истории, а больше двух файлов не занимает.
 */
static const unsigned long long MAXLogLimit = 256 * 1024;

static NSString *MAXLogFolder(void) {
    return [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,
                                                NSUserDomainMask, YES) objectAtIndex:0];
}

NSString *MAXLogPath(void) {
    return [MAXLogFolder() stringByAppendingPathComponent:@"max.log"];
}

static NSString *MAXLogPreviousPath(void) {
    return [MAXLogFolder() stringByAppendingPathComponent:@"max-prev.log"];
}

/// Очередь одна на всё: писать в файл из нескольких потоков разом нельзя,
/// а пуши и ответы сокета приходят не только с главного.
static dispatch_queue_t MAXLogQueue(void) {
    static dispatch_queue_t queue = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        queue = dispatch_queue_create("ru.computershik.scam.log", DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

static NSDateFormatter *MAXLogClock(void) {
    static NSDateFormatter *formatter = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        formatter = [[NSDateFormatter alloc] init];
        [formatter setDateFormat:@"HH:mm:ss.SSS"];
    });
    return formatter;
}

void MAXLogClear(void) {
    dispatch_sync(MAXLogQueue(), ^{
        NSFileManager *manager = [NSFileManager defaultManager];
        [manager removeItemAtPath:MAXLogPath() error:NULL];
        [manager removeItemAtPath:MAXLogPreviousPath() error:NULL];
    });
}

NSString *MAXLogContents(void) {
    __block NSString *result = @"";

    dispatch_sync(MAXLogQueue(), ^{
        NSString *previous = [NSString stringWithContentsOfFile:MAXLogPreviousPath()
                                                        encoding:NSUTF8StringEncoding
                                                           error:NULL];
        NSString *current = [NSString stringWithContentsOfFile:MAXLogPath()
                                                      encoding:NSUTF8StringEncoding
                                                         error:NULL];
        result = [NSString stringWithFormat:@"%@%@", previous ?: @"", current ?: @""];
    });

    return result;
}

/// Дописывает строку в конец файла, перекладывая его при переполнении.
static void MAXLogAppend(NSString *line) {
    NSFileManager *manager = [NSFileManager defaultManager];
    NSString *path = MAXLogPath();

    if (![manager fileExistsAtPath:path]) {
        [line writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        return;
    }

    NSDictionary *attributes = [manager attributesOfItemAtPath:path error:NULL];
    if ([attributes fileSize] >= MAXLogLimit) {
        [manager removeItemAtPath:MAXLogPreviousPath() error:NULL];
        [manager moveItemAtPath:path toPath:MAXLogPreviousPath() error:NULL];
        [line writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        return;
    }

    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
    if (handle == nil) return;

    [handle seekToEndOfFile];
    [handle writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
    [handle closeFile];
}

/// Общая часть обеих записей. `always` — писать в системный журнал, даже
/// когда журнал выключен: так уходит причина падения. `wait` — дожидаться ли,
/// пока строка окажется на диске.
///
/// Условия обычные, а не препроцессорные: при нуле ветка всё равно
/// выбрасывается компилятором, зато файл целиком остаётся собранным и не
/// рассыпается на неиспользуемые куски.
static void MAXLogPut(NSString *message, BOOL wait, BOOL always) {
    if (MAX_LOG_TO_SYSLOG || always) NSLog(@"%@", message);

    if (!MAX_LOG_TO_FILE) return;

    NSDate *now = [NSDate date];
    NSString *line = [NSString stringWithFormat:@"%@ %@\n",
                      [MAXLogClock() stringFromDate:now], message];

    if (wait) {
        dispatch_sync(MAXLogQueue(), ^{ MAXLogAppend(line); });
        return;
    }
    dispatch_async(MAXLogQueue(), ^{ MAXLogAppend(line); });
}

void MAXLogWriteNow(NSString *format, ...) {
    va_list arguments;
    va_start(arguments, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:arguments];
    va_end(arguments);

    // Причина падения уходит в системный журнал при любых настройках:
    // сборка, которая умирает молча, неисправима.
    MAXLogPut(message, YES, YES);
}

void MAXLogWrite(NSString *format, ...) {
    va_list arguments;
    va_start(arguments, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:arguments];
    va_end(arguments);

    MAXLogPut(message, NO, NO);
}
