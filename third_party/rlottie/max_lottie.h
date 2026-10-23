/* Отрисовщик движущихся стикеров для «Ловита».
 *
 * Своя обёртка вместо той, что идёт с rlottie (src/binding/c), и вот почему:
 * та тянет за собой подмену свойств сцены — `lottie_animation_property_override`
 * и четыре перегрузки `Animation::setValue`, — а в этой копии библиотеки их
 * определений нет вовсе (`lottieproxymodel.cpp` пуст). Нам подмена не нужна, и
 * тянуть ради неё недостающие куски незачем.
 *
 * Наружу вынесено самое малое: открыть, спросить число кадров и частоту,
 * нарисовать кадр в готовый буфер, закрыть. Кадры готовятся по одному, по
 * требованию: держать их все разом на телефоне негде.
 *
 * Так же устроено и на Windows Phone (native/LovitOpus рядом с
 * native/LovitLottie), только там обёртке пришлось ещё и перехватывать
 * аппаратные сбои — здесь библиотека собрана нормальным компилятором, и
 * этого не нужно.
 */

#ifndef MAX_LOTTIE_H
#define MAX_LOTTIE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Открывает стикер из его описания — строки JSON, оканчивающейся нулём.
 * `key` нужен самой библиотеке для её внутреннего счёта разобранных сцен;
 * годится номер стикера. NULL, если не вышло. */
void *max_lottie_open(const char *json, const char *key);

/* Сколько всего кадров. */
int max_lottie_frames(void *handle);

/* Кадров в секунду. Ноль, если сказать нечего. */
double max_lottie_rate(void *handle);

/* Рисует кадр в буфер: точки по четыре байта, помноженные на прозрачность,
 * в том порядке, в каком их читает CoreGraphics на этой архитектуре. */
void max_lottie_render(void *handle, int frame, uint32_t *buffer,
                       int width, int height, int stride);

void max_lottie_close(void *handle);

#ifdef __cplusplus
}
#endif

#endif
