/* Кусочки устройства C++, которые приходится нести с собой.
 *
 * Их полагается брать из системной libc++abi, и SDK 9.3 именно её и
 * называет. Но на iOS 6 в `/usr/lib/libc++abi.dylib` их нет: `operator new`
 * там ещё не жил, и dyld обрывает приложение в тот миг, когда C++ впервые
 * просит памяти:
 *
 *     Symbol not found: __Znwm
 *     Expected in: /usr/lib/libc++abi.dylib
 *
 * Названная библиотека записана в приложение накрепко, на выбор её при
 * запуске никак не повлиять. Поэтому все семь нужных нам вещей делаются
 * здесь и остаются внутри приложения — от libc++abi не остаётся зависимости
 * вовсе, а значит и разницы между прошивками.
 *
 * Занимать память нечем, кроме malloc: `operator new` в libc++abi так и
 * устроен, так что ни на устройстве, ни на новых прошивках разницы нет.
 *
 * Только для C++: Objective-C сюда не заглядывает.
 */

#include <stddef.h>
#include <stdlib.h>
#include <pthread.h>

/* --- Память ---------------------------------------------------------------
 *
 * Библиотека собрана без исключений (-fno-exceptions), поэтому сказать
 * «памяти нет» нечем: остаётся упасть сразу и честно, а не отдать ноль,
 * от которого упадёт следующая же строка, но уже непонятно почему.
 *
 * Ноль байт просить разрешено, и два таких запроса должны дать разные
 * ответы — отсюда единица.
 */

void *operator new(size_t size)
{
    void *memory = malloc(size == 0 ? 1 : size);
    if (memory == NULL) abort();
    return memory;
}

void *operator new[](size_t size)
{
    return operator new(size);
}

void operator delete(void *memory)
{
    free(memory);
}

void operator delete[](void *memory)
{
    free(memory);
}

/* --- Статические переменные внутри функций --------------------------------
 *
 * `static` внутри функции создаётся при первом заходе, и компилятор просит
 * приглядеть, чтобы два потока не создали её дважды. Порядок такой:
 * acquire возвращает 1 — «создавай, замок у тебя», после чего release
 * помечает готовность и отпускает замок; вернул 0 — уже создано.
 *
 * Помета — самый первый байт (так эту проверку и пишет компилятор).
 *
 * Замок один на всё приложение и **допускает повторный захват**: создание
 * одной такой переменной легко упирается в другую, и на обычном замке это
 * встало бы намертво. Стикеры рисуются не только нашей очередью — внутри
 * библиотеки есть свои потоки, поэтому обойтись без замка нельзя.
 */

static pthread_mutex_t MaxOnceLock;
static pthread_once_t MaxOnceLockReady = PTHREAD_ONCE_INIT;

static void MaxMakeOnceLock(void)
{
    pthread_mutexattr_t how;
    pthread_mutexattr_init(&how);
    pthread_mutexattr_settype(&how, PTHREAD_MUTEX_RECURSIVE);
    pthread_mutex_init(&MaxOnceLock, &how);
    pthread_mutexattr_destroy(&how);
}

extern "C" int __cxa_guard_acquire(void *guard)
{
    pthread_once(&MaxOnceLockReady, MaxMakeOnceLock);
    pthread_mutex_lock(&MaxOnceLock);

    if (*(volatile char *)guard != 0) {          // успели без нас
        pthread_mutex_unlock(&MaxOnceLock);
        return 0;
    }

    return 1;                                    // замок остаётся за нами
}

extern "C" void __cxa_guard_release(void *guard)
{
    *(volatile char *)guard = 1;
    pthread_mutex_unlock(&MaxOnceLock);
}

extern "C" void __cxa_guard_abort(void *guard)
{
    (void)guard;
    pthread_mutex_unlock(&MaxOnceLock);
}

/* --- Чисто виртуальный вызов ----------------------------------------------
 *
 * Сюда попадают, только если позвали метод у недоделанного объекта —
 * это ошибка в самой программе, и продолжать нельзя.
 */

extern "C" void __cxa_pure_virtual(void)
{
    abort();
}
