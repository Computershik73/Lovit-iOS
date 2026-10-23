#!/bin/sh
# OpenSSL 1.1.1w для iOS, по срезу на каждую архитектуру.
#
#     sh tools/build-openssl.sh
#
# Собирается своя криптография, а не берётся системная, по одной причине:
# сервер MAX согласовывает TLS 1.3, а на TLS 1.2 из шифров эпохи iOS 6
# принимает ровно один — ECDHE-RSA-AES128-SHA256. Secure Transport той поры
# его не предлагает, и рукопожатие не состаивается вовсе. Подробности —
# в src/Core/Transport/MAXTls.h и в README.
#
# Результат кладётся в $SSL_OUT/<срез>/openssl, откуда его и берёт Makefile.
set -e

THEOS="${THEOS:-$HOME/theos}"
IOS_SDK="${IOS_SDK:-$THEOS/sdks/iPhoneOS9.3.sdk}"
TOOLCHAIN_BIN="${TOOLCHAIN_BIN:-$THEOS/toolchain/linux/iphone/bin}"

# 6.0 — нижняя граница самого приложения. Библиотека обязана совпадать:
# если она соберётся с более высокой, приложение на iOS 6 просто не пойдёт.
IOS_MIN_VERSION="${IOS_MIN_VERSION:-6.0}"
IOS_ARCHS="${IOS_ARCHS:-armv7 arm64}"

OPENSSL_VERSION="${OPENSSL_VERSION:-1.1.1w}"

WORK="${WORK:-$HOME/lovit}"
DL_DIR="$WORK/dl"
BUILD_DIR="$WORK/build"
SSL_OUT="${SSL_OUT:-$WORK/out}"

die() { echo "ОШИБКА: $*" >&2; exit 1; }

[ -d "$THEOS" ]               || die "нет $THEOS — сначала tools/setup.sh"
[ -x "$TOOLCHAIN_BIN/clang" ] || die "нет $TOOLCHAIN_BIN/clang"
[ -d "$IOS_SDK" ]             || die "нет $IOS_SDK — сначала tools/setup.sh"

mkdir -p "$DL_DIR" "$BUILD_DIR"
tarball="$DL_DIR/openssl-$OPENSSL_VERSION.tar.gz"

if [ ! -f "$tarball" ] || ! gzip -t "$tarball" 2>/dev/null; then
	echo "== Качаю OpenSSL $OPENSSL_VERSION =="
	rm -f "$tarball"
	curl -fL --retry 3 -o "$tarball" \
		"https://github.com/openssl/openssl/releases/download/OpenSSL_$(echo $OPENSSL_VERSION | tr . _)/openssl-$OPENSSL_VERSION.tar.gz" ||
	curl -fL --retry 3 -o "$tarball" \
		"https://www.openssl.org/source/openssl-$OPENSSL_VERSION.tar.gz"
	gzip -t "$tarball" || die "архив OpenSSL повреждён"
fi

# Правки к порождённому Makefile — две, и обе обязательны.
#
# 1. AR и RANLIB. Системные собраны под ELF и с форматом Mach-O не работают.
#
# 2. CNF_CFLAGS. Цели ios-cross и ios64-cross рассчитаны на Xcode
#    и дописывают в флаги вот это:
#
#      -arch armv7 -mios-version-min=6.0.0 -fno-common \
#      -isysroot $(CROSS_TOP)/SDKs/$(CROSS_SDK)
#
#    Обе переменные Configure ждёт из окружения и до make не доносит, так что
#    путь превращается в «-isysroot /SDKs/» и перекрывает наш, правильный:
#    сборка встаёт на первом же #include <stdio.h>. Оставляем от строки
#    только -fno-common: срез и граница приходят из -target
#    и -miphoneos-version-min в CC.
fix_makefile() {
	sed -i \
		-e "s|^AR=.*|AR=$TOOLCHAIN_BIN/ar|" \
		-e "s|^RANLIB=.*|RANLIB=$TOOLCHAIN_BIN/ranlib|" \
		-e "s|^CNF_CFLAGS=.*|CNF_CFLAGS=-fno-common|" \
		Makefile
}

for arch in $IOS_ARCHS; do
	triple="$arch-apple-ios$IOS_MIN_VERSION"
	src="$BUILD_DIR/openssl-$arch"
	prefix="$SSL_OUT/$arch/openssl"

	# Цели в 1.1.1 разные для 32 и 64 бит: у них отличается модель данных
	# (ILP32 против LP64), и от этого зависит выбор реализации длинной
	# арифметики — самой горячей части всей библиотеки.
	case "$arch" in
		armv7) target=ios-cross ;;
		arm64) target=ios64-cross ;;
		*)     die "неизвестный срез $arch" ;;
	esac

	echo
	echo "=============================================================="
	echo "  OpenSSL $OPENSSL_VERSION -> $arch ($triple, $target)"
	echo "=============================================================="

	rm -rf "$src"
	tar xzf "$tarball" -C "$BUILD_DIR"
	mv "$BUILD_DIR/openssl-$OPENSSL_VERSION" "$src"
	cd "$src"

	# CC передаётся целиком, вместе с тройкой и SDK: цели ios*-cross
	# рассчитаны на Xcode, который сам знает, где что лежит.
	#
	# Ключи:
	#   no-shared      статикой — разделяемых библиотек в приложении iOS быть
	#                  не может;
	#   no-dso         динамическая загрузка модулей не нужна и не работает;
	#   no-async       механизм асинхронных заданий использует контексты
	#                  выполнения, на iOS от него одни неприятности;
	#   no-ui-console   консольный ввод пароля на телефоне бессмыслен.
	CC="$TOOLCHAIN_BIN/clang -target $triple -isysroot $IOS_SDK -miphoneos-version-min=$IOS_MIN_VERSION" \
	CROSS_COMPILE="" \
	./Configure "$target" \
		no-shared no-dso no-tests no-async no-engine no-ui-console \
		no-comp no-ssl3 no-weak-ssl-ciphers \
		--prefix="$prefix" --openssldir="$prefix/ssl" > "$WORK/openssl-$arch-configure.log" 2>&1 ||
		{ tail -20 "$WORK/openssl-$arch-configure.log"; die "Configure ($arch)"; }

	fix_makefile

	echo "-- собираю (лог: $WORK/openssl-$arch-make.log)"
	if ! make -j"$(nproc)" build_libs > "$WORK/openssl-$arch-make.log" 2>&1; then
		# Ассемблерные вставки — самая частая причина отказа при сборке
		# чужим тулчейном. Без них AES на arm64 теряет аппаратное ускорение,
		# поэтому сначала пробуем с ними и только потом отступаем.
		echo "-- не собралось с ассемблером, повторяю с no-asm"
		make clean > /dev/null 2>&1 || true
		CC="$TOOLCHAIN_BIN/clang -target $triple -isysroot $IOS_SDK -miphoneos-version-min=$IOS_MIN_VERSION" \
		./Configure "$target" no-asm \
			no-shared no-dso no-tests no-async no-engine no-ui-console \
			no-comp no-ssl3 no-weak-ssl-ciphers \
			--prefix="$prefix" --openssldir="$prefix/ssl" >> "$WORK/openssl-$arch-configure.log" 2>&1
		sed -i \
			-e "s|^AR=.*|AR=$TOOLCHAIN_BIN/ar|" \
			-e "s|^RANLIB=.*|RANLIB=$TOOLCHAIN_BIN/ranlib|" \
			Makefile
		make -j"$(nproc)" build_libs > "$WORK/openssl-$arch-make.log" 2>&1 ||
			{ tail -30 "$WORK/openssl-$arch-make.log"; die "make ($arch)"; }
	fi

	mkdir -p "$prefix/lib" "$prefix/include"
	cp libcrypto.a libssl.a "$prefix/lib/"
	rm -rf "$prefix/include/openssl"
	cp -r include/openssl "$prefix/include/openssl"

	echo "-- готово: $prefix"

	# Нижняя граница проверяется прямо в собранном файле, и это не
	# перестраховка: ровно здесь Configure и пытался подсунуть свою.
	minver=$("$TOOLCHAIN_BIN/otool" -l "$prefix/lib/libssl.a" 2>/dev/null |
	         grep -A2 LC_VERSION_MIN_IPHONEOS | grep -m1 version | awk '{print $2}')
	echo "-- нижняя граница в библиотеке: ${minver:-не определилась}"
	if [ -n "$minver" ] && [ "$minver" != "$IOS_MIN_VERSION" ]; then
		die "в библиотеке граница $minver, а должна быть $IOS_MIN_VERSION"
	fi
done

echo
echo "OpenSSL $OPENSSL_VERSION собран для: $IOS_ARCHS"
echo "Путь для Makefile:  SSL_OUT=$SSL_OUT"
