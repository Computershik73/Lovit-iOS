#!/bin/sh
#
# Сборка rlottie срезом на архитектуру — так же, как tools/build-opus.sh
# собирает кодек голосовых.
#
# Зачем. Движущийся стикер в MAX — это не картинка, а Lottie: описание
# векторной сцены во времени, слои и ключевые кадры. Показать его можно
# только отрисовав, и рисует его rlottie — та же библиотека, что рисует
# такие стикеры в Telegram и в клиенте под Windows Phone.
#
# Вместе с библиотекой собирается max_cxx.cpp — семь кусочков устройства
# C++ (operator new и родня), которых на iOS 6 нет в системной libc++abi.
# Подробности там же, в самом файле.
#
# Обёртка своя — third_party/rlottie/max_lottie.cpp. Та, что идёт с
# библиотекой (src/binding/c), тянет за собой подмену свойств сцены, а её
# определений в этой копии нет вовсе: lottieproxymodel.cpp пуст. Подмена нам
# не нужна, и тянуть ради неё недостающие куски незачем.
#
#   sh tools/build-rlottie.sh          собрать обе архитектуры
#   sh tools/build-rlottie.sh armv7    только одну
#
# Получается $RLOTTIE_OUT/<арх>/lib/librlottie.a и общие заголовки в
# $RLOTTIE_OUT/include. Сборка занимает пару минут на архитектуру.

set -e

THEOS="${THEOS:-$HOME/theos}"
SDK="${SDK:-$THEOS/sdks/iPhoneOS9.3.sdk}"
TOOLCHAIN="${TOOLCHAIN:-$THEOS/toolchain/linux/iphone/bin}"

RLOTTIE_OUT="${RLOTTIE_OUT:-$HOME/lovit/rlottie}"

HERE=$(cd "$(dirname "$0")/.." && pwd)
SRC="$HERE/third_party/rlottie"

CXX="$TOOLCHAIN/clang++"
AR="$TOOLCHAIN/ar"
RANLIB="$TOOLCHAIN/ranlib"

[ -x "$CXX" ] || { echo "нет компилятора: $CXX"; exit 1; }
[ -d "$SDK" ] || { echo "нет SDK: $SDK"; exit 1; }
[ -f "$SRC/src/lottie/lottieanimation.cpp" ] || { echo "нет исходников rlottie: $SRC"; exit 1; }

ARCHS="$*"
[ -n "$ARCHS" ] || ARCHS="armv7 arm64"

mkdir -p "$RLOTTIE_OUT/include"
cp "$SRC/inc/"*.h "$SRC/max_lottie.h" "$RLOTTIE_OUT/include/"

for ARCH in $ARCHS; do
    case "$ARCH" in
        armv7) TRIPLE="armv7-apple-ios6.0" ;;
        arm64) TRIPLE="arm64-apple-ios6.0" ;;
        *) echo "неизвестная архитектура: $ARCH"; exit 1 ;;
    esac

    WORK=$(mktemp -d)
    trap 'rm -rf "$WORK"' EXIT

    echo "==> rlottie ($ARCH)"

    # -U__ARM_NEON__ выключает ускоренную отрисовку намеренно.
    #
    # Ускорение у rlottie написано ассемблером под 32-разрядный ARM
    # (pixman-arm-neon-asm.S), и на arm64 оно не собирается вовсе, а собирать
    # по-разному под каждую архитектуру — лишний повод разойтись. Стикер
    # рисуется 128×128: обычный C справляется и с запасом.
    #
    # Потоков нет: LOTTIE_THREAD_SUPPORT не объявлен, и rlottie рисует прямо
    # в том потоке, из которого её позвали. Нам это и нужно — зовём мы её с
    # фоновой очереди, своей.
    #
    # Заголовки libc++ берутся у тулчейна, а не из SDK: в SDK лежит только
    # libstdc++ 4.2.1 времён GCC, а rlottie написана на C++14. Сама
    # библиотека на устройстве при этом системная — /usr/lib/libc++.1.dylib,
    # она есть и на iOS 6.
    #
    # -fno-exceptions и -fno-rtti — как в её собственной сборке.
    FLAGS="-target $TRIPLE -isysroot $SDK -miphoneos-version-min=6.0 \
        -std=c++14 -O2 -fPIC -fvisibility=hidden -w \
        -nostdinc++ -isystem $TOOLCHAIN/../include/c++/v1 \
        -D_LIBCPP_DISABLE_AVAILABILITY \
        -fno-exceptions -fno-rtti \
        -fno-unwind-tables -fno-asynchronous-unwind-tables \
        -U__ARM_NEON__ \
        -I$SRC -I$SRC/inc -I$SRC/src/lottie -I$SRC/src/vector \
        -I$SRC/src/vector/freetype -I$SRC/src/vector/stb"

    SOURCES=$(ls "$SRC"/src/lottie/*.cpp "$SRC"/src/vector/*.cpp \
                 "$SRC"/src/vector/freetype/*.cpp "$SRC"/src/vector/stb/*.cpp \
                 "$SRC"/max_lottie.cpp "$SRC"/max_cxx.cpp 2>/dev/null)

    COUNT=0
    for FILE in $SOURCES; do
        NAME=$(basename "$FILE" .cpp)
        SUB=$(basename "$(dirname "$FILE")")
        [ "$SUB" = "rlottie" ] && SUB=shim
        mkdir -p "$WORK/$SUB"
        $CXX $FLAGS -c "$FILE" -o "$WORK/$SUB/$NAME.o"
        COUNT=$((COUNT + 1))
    done

    mkdir -p "$RLOTTIE_OUT/$ARCH/lib"
    rm -f "$RLOTTIE_OUT/$ARCH/lib/librlottie.a"
    $AR rcs "$RLOTTIE_OUT/$ARCH/lib/librlottie.a" $(find "$WORK" -name '*.o')
    $RANLIB "$RLOTTIE_OUT/$ARCH/lib/librlottie.a" 2>/dev/null || true

    echo "    $COUNT файлов -> $RLOTTIE_OUT/$ARCH/lib/librlottie.a"

    rm -rf "$WORK"
    trap - EXIT
done

echo "готово: $RLOTTIE_OUT"
