#!/bin/sh
# Установка всего, что нужно для сборки «Ловит», одной командой.
#
#     sh tools/setup.sh
#
# Ставит по очереди: пакеты системы, Theos, SDK iPhoneOS9.3, заплатки к нему
# и OpenSSL. Каждый шаг сначала проверяет, не сделан ли он уже, поэтому
# скрипт можно запускать повторно — он доделает недостающее.
#
# Работает в Linux и в WSL 2. Xcode и Mac не нужны нигде.
set -e

here=$(cd "$(dirname "$0")" && pwd)
root=$(dirname "$here")

THEOS="${THEOS:-$HOME/theos}"
SDK_NAME="iPhoneOS9.3.sdk"
SDK_PATH="$THEOS/sdks/$SDK_NAME"
WORK="${WORK:-$HOME/lovit}"
SSL_OUT="${SSL_OUT:-$WORK/out}"
OPUS_OUT="${OPUS_OUT:-$WORK/opus}"
RLOTTIE_OUT="${RLOTTIE_OUT:-$WORK/rlottie}"

say() { echo; echo "== $* =="; }
die() { echo "ОШИБКА: $*" >&2; exit 1; }

# --- 1. Пакеты системы -------------------------------------------------------
#
# perl нужен самому Theos, dpkg-dev даёт dpkg-deb, zip — упаковку .ipa,
# python3 — проверку бинарника и номер сборки.

say "Проверяю пакеты"

missing=""
for tool in git curl perl make python3 zip dpkg-deb; do
	command -v "$tool" > /dev/null 2>&1 || missing="$missing $tool"
done

if [ -n "$missing" ]; then
	echo "Не хватает:$missing"
	if command -v apt-get > /dev/null 2>&1; then
		echo "Ставлю через apt (нужен sudo)…"
		sudo apt-get update
		sudo apt-get install -y git curl perl make python3 zip dpkg-dev build-essential
	else
		die "поставьте их сами:$missing"
	fi
else
	echo "всё на месте"
fi

# --- 2. Theos ----------------------------------------------------------------

say "Theos"

if [ -d "$THEOS/makefiles" ]; then
	echo "уже стоит: $THEOS"
else
	echo "Ставлю в $THEOS…"
	git clone --recursive https://github.com/theos/theos.git "$THEOS"
fi

# Тулчейн: у Theos он ставится отдельно и не всегда приезжает с клоном.
if [ -x "$THEOS/toolchain/linux/iphone/bin/clang" ]; then
	echo "тулчейн на месте"
else
	say "Тулчейн (clang для iOS)"
	mkdir -p "$THEOS/toolchain"
	tmp=$(mktemp -d)
	curl -fL --retry 3 -o "$tmp/toolchain.tar.lzma" \
		"https://github.com/theos/toolchain/releases/download/iOS15.5/iOS_15.5_toolchain_linux_x86_64.tar.lzma" ||
		die "не скачался тулчейн — см. https://theos.dev/docs/installation-linux"
	tar -xf "$tmp/toolchain.tar.lzma" -C "$THEOS/toolchain"
	rm -rf "$tmp"

	# В разных выпусках каталог называется по-разному, а Theos ищет
	# строго toolchain/linux/iphone.
	if [ ! -x "$THEOS/toolchain/linux/iphone/bin/clang" ]; then
		found=$(find "$THEOS/toolchain" -name clang -type f -perm -u+x | head -1)
		[ -n "$found" ] || die "clang не нашёлся в $THEOS/toolchain"
		mkdir -p "$THEOS/toolchain/linux"
		ln -sfn "$(dirname "$(dirname "$found")")" "$THEOS/toolchain/linux/iphone"
	fi
	echo "тулчейн поставлен"
fi

# --- 3. SDK ------------------------------------------------------------------
#
# Нужен именно 9.3: это последний, где ещё живы заголовки эпохи iOS 5–6
# и есть срез armv7.

say "SDK $SDK_NAME"

if [ -d "$SDK_PATH" ]; then
	echo "уже стоит: $SDK_PATH"
else
	echo "Качаю набор SDK (около 200 МБ)…"
	mkdir -p "$THEOS/sdks"
	tmp=$(mktemp -d)
	git clone --depth 1 https://github.com/theos/sdks.git "$tmp/sdks"
	[ -d "$tmp/sdks/$SDK_NAME" ] || die "в наборе нет $SDK_NAME"
	cp -r "$tmp/sdks/$SDK_NAME" "$THEOS/sdks/"
	rm -rf "$tmp"
	echo "поставлен: $SDK_PATH"
fi

# --- 4. Заплатки к SDK -------------------------------------------------------
#
# Обязательный шаг, а не украшение: без него сборка либо не линкуется, либо —
# что хуже — линкуется и падает на устройстве до main. Что именно правится
# и почему, написано в самом скрипте и в README.

say "Заплатки к SDK"
sh "$here/patch-sdk.sh"

# --- 5. OpenSSL --------------------------------------------------------------

say "OpenSSL"

if [ -f "$SSL_OUT/armv7/openssl/lib/libssl.a" ] && \
   [ -f "$SSL_OUT/arm64/openssl/lib/libssl.a" ]; then
	echo "уже собран: $SSL_OUT"
else
	echo "Собираю (это надолго — минут десять)…"
	SSL_OUT="$SSL_OUT" WORK="$WORK" sh "$here/build-openssl.sh"
fi

# --- 6. libopus --------------------------------------------------------------
#
# Голосовые MAX ходят в Opus, а на iOS 6 такого кодека нет вовсе. Исходники
# лежат в third_party/opus, качать нечего — сборка занимает пару минут.

say "libopus"

if [ -f "$OPUS_OUT/armv7/lib/libopus.a" ] &&    [ -f "$OPUS_OUT/arm64/lib/libopus.a" ]; then
	echo "уже собран: $OPUS_OUT"
else
	OPUS_OUT="$OPUS_OUT" sh "$here/build-opus.sh"
fi

# --- 7. rlottie --------------------------------------------------------------
#
# Движущиеся стикеры. Исходники лежат в third_party/rlottie, качать нечего.

say "rlottie"

if [ -f "$RLOTTIE_OUT/armv7/lib/librlottie.a" ] && \
   [ -f "$RLOTTIE_OUT/arm64/lib/librlottie.a" ]; then
	echo "уже собран: $RLOTTIE_OUT"
else
	RLOTTIE_OUT="$RLOTTIE_OUT" sh "$here/build-rlottie.sh"
fi

# --- Готово ------------------------------------------------------------------

cat <<EOF

==============================================================
  Готово. Собрать приложение:

      cd $root
      make ipa FINALPACKAGE=1

  Получится packages/Lovit.ipa. Проверить, что внутри задумано:

      python3 tools/check-macho.py packages/Lovit.ipa

  Если библиотеки лежат не там, где их ждёт Makefile, передайте пути:

      make ipa FINALPACKAGE=1 SSL_OUT=$SSL_OUT OPUS_OUT=$OPUS_OUT RLOTTIE_OUT=$RLOTTIE_OUT
==============================================================
EOF
