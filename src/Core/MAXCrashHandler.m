//
//  MAXCrashHandler.m
//

#import "MAXCrashHandler.h"
#import <signal.h>

/// Что было до нас: свой перехват ставят и отладочные надстройки, и сама
/// система под отладчиком. Отняв его молча, мы бы сломали их работу.
static NSUncaughtExceptionHandler *MAXPreviousHandler = NULL;

static void MAXHandleException(NSException *exception) {
    // Запись синхронная: обычная откладывается на свою очередь, а очередь у
    // падающего приложения уже не выполнится.
    MAXLogWriteNow(@"[ПАДЕНИЕ] %@: %@", exception.name, exception.reason ?: @"без объяснения");

    NSArray *stack = [exception callStackSymbols];
    if (stack.count > 0) {
        // Целиком стек не пишем: в нём бывает полсотни строк, а журналу
        // отведено четверть мегабайта на всё. Верхушки хватает, чтобы понять,
        // откуда брошено.
        NSUInteger many = MIN((NSUInteger)16, stack.count);
        for (NSUInteger at = 0; at < many; at++) {
            MAXLogWriteNow(@"[ПАДЕНИЕ] %@", stack[at]);
        }
    }

    if (MAXPreviousHandler != NULL) MAXPreviousHandler(exception);
}

/// Сигналы — второй путь гибели, помимо исключения.
///
/// Полноценного отчёта здесь не построить: внутри обработчика сигнала почти
/// ничего делать нельзя, и уж точно нельзя заводить объекты. Одна строка о
/// том, какой это был сигнал, — всё, на что можно рассчитывать, и её уже
/// довольно, чтобы отличить брошенное исключение (SIGABRT) от обращения по
/// негодному адресу (SIGSEGV, SIGBUS).
static void MAXHandleSignal(int number) {
    const char *name = "неизвестный";

    switch (number) {
        case SIGABRT: name = "SIGABRT (прерывание — обычно брошенное исключение)"; break;
        case SIGSEGV: name = "SIGSEGV (обращение по негодному адресу)"; break;
        case SIGBUS:  name = "SIGBUS (негодное обращение к памяти)"; break;
        case SIGILL:  name = "SIGILL (негодная команда)"; break;
        case SIGFPE:  name = "SIGFPE (ошибка вычисления)"; break;
        case SIGTRAP: name = "SIGTRAP (остановка)"; break;
        default: break;
    }

    MAXLogWriteNow(@"[ПАДЕНИЕ] сигнал %d — %s", number, name);

    // Дальше — как было бы без нас: снимаем свой обработчик и посылаем сигнал
    // заново, чтобы система сложила свой отчёт о падении. Иначе приложение
    // осталось бы висеть, а отчёта не появилось бы вовсе.
    signal(number, SIG_DFL);
    raise(number);
}

@implementation MAXCrashHandler

+ (void)install {
    MAXPreviousHandler = NSGetUncaughtExceptionHandler();
    NSSetUncaughtExceptionHandler(&MAXHandleException);

    int signals[] = { SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGFPE, SIGTRAP };
    for (size_t at = 0; at < sizeof(signals) / sizeof(signals[0]); at++) {
        signal(signals[at], &MAXHandleSignal);
    }
}

@end
