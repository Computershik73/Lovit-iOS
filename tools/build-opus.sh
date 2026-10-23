#!/bin/sh
#
# Сборка libopus срезом на архитектуру — так же, как tools/build-openssl.sh
# собирает криптографию.
#
# Зачем своя. Голосовые MAX ходят в Opus внутри Ogg, а на iOS 6 такого кодека
# нет вовсе: AVAudioRecorder умеет только AAC и линейный PCM, системный
# проигрыватель Opus не открывает. Ни записать, ни послушать голосовое без
# своей библиотеки нельзя.
#
# Почему не autotools. `configure` под кросс-сборку iOS из Linux настраивается
# долго и норовит нащупать не тот компилятор; список файлов у libopus известен
# и невелик, а настройки — в third_party/opus/config-ios.h.
#
#   sh tools/build-opus.sh          собрать обе архитектуры
#   sh tools/build-opus.sh armv7    только одну
#
# Получается $OPUS_OUT/<арх>/lib/libopus.a и общие заголовки в
# $OPUS_OUT/include. Повторный запуск пересобирает с нуля — сборка занимает
# около минуты на архитектуру.

set -e

THEOS="${THEOS:-$HOME/theos}"
SDK="${SDK:-$THEOS/sdks/iPhoneOS9.3.sdk}"
TOOLCHAIN="${TOOLCHAIN:-$THEOS/toolchain/linux/iphone/bin}"

# Не $HOME/lovit/out: там лежит OpenSSL, и Makefile ищет его каталог по
# точному совпадению. Своя папка рядом ничего не задевает.
OPUS_OUT="${OPUS_OUT:-$HOME/lovit/opus}"

HERE=$(cd "$(dirname "$0")/.." && pwd)
SRC="$HERE/third_party/opus"

CC="$TOOLCHAIN/clang"
AR="$TOOLCHAIN/ar"
RANLIB="$TOOLCHAIN/ranlib"

[ -x "$CC" ] || { echo "нет компилятора: $CC"; exit 1; }
[ -d "$SDK" ] || { echo "нет SDK: $SDK"; exit 1; }
[ -f "$SRC/src/opus_encoder.c" ] || { echo "нет исходников libopus: $SRC"; exit 1; }

ARCHS="$*"
[ -n "$ARCHS" ] || ARCHS="armv7 arm64"

# Заголовки одни на все архитектуры — они от неё не зависят.
mkdir -p "$OPUS_OUT/include/opus"
cp "$SRC/include/"*.h "$OPUS_OUT/include/opus/"

for ARCH in $ARCHS; do
    case "$ARCH" in
        armv7) TRIPLE="armv7-apple-ios6.0" ;;
        arm64) TRIPLE="arm64-apple-ios6.0" ;;
        *) echo "неизвестная архитектура: $ARCH"; exit 1 ;;
    esac

    WORK=$(mktemp -d)
    trap 'rm -rf "$WORK"' EXIT

    echo "==> libopus ($ARCH)"

    # Настройки подставляются ключом -include всем файлам разом, а не через
    # HAVE_CONFIG_H: с ним каждый исходник ждёт файл ровно с именем config.h,
    # который обычно порождает `configure`, — а его тут и нет.
    FLAGS="-target $TRIPLE -isysroot $SDK -miphoneos-version-min=6.0 \
        -O2 -fPIC -fvisibility=hidden -w \
        -include $SRC/config-ios.h \
        -I$SRC -I$SRC/include -I$SRC/celt -I$SRC/silk -I$SRC/silk/float"

    # Подкаталоги arm, x86 и fixed не берём: первые два — оптимизации со
    # своими правилами сборки и ассемблером, третий — целочисленный счёт,
    # которого при FLOATING_POINT не бывает.
    SOURCES=$(ls "$SRC"/celt/*.c "$SRC"/silk/*.c "$SRC"/silk/float/*.c "$SRC"/src/*.c)

    COUNT=0
    for FILE in $SOURCES; do
        NAME=$(basename "$FILE" .c)
        # Имена в celt и silk кое-где совпадают — раскладываем по подпапкам.
        SUB=$(basename "$(dirname "$FILE")")
        mkdir -p "$WORK/$SUB"
        $CC $FLAGS -c "$FILE" -o "$WORK/$SUB/$NAME.o"
        COUNT=$((COUNT + 1))
    done

    mkdir -p "$OPUS_OUT/$ARCH/lib"
    rm -f "$OPUS_OUT/$ARCH/lib/libopus.a"
    $AR rcs "$OPUS_OUT/$ARCH/lib/libopus.a" $(find "$WORK" -name '*.o')
    $RANLIB "$OPUS_OUT/$ARCH/lib/libopus.a" 2>/dev/null || true

    echo "    $COUNT файлов -> $OPUS_OUT/$ARCH/lib/libopus.a"

    rm -rf "$WORK"
    trap - EXIT
done

echo "готово: $OPUS_OUT"
