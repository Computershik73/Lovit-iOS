export THEOS ?= $(HOME)/theos

# OpenSSL по срезу на архитектуру — тот же набор, что у «АльтерВито»,
# собранный его tools/10-build-openssl.sh. Своя криптография здесь не прихоть:
# сервер MAX согласовывает TLS 1.3, а на TLS 1.2 из шифров эпохи iOS 6
# принимает ровно один. Secure Transport той поры его не предлагает, и
# рукопожатие не состаивается вовсе — подробности в src/Core/Transport/MAXTls.h.
#
# Путь ищется в двух местах: сначала свой, собранный tools/build-openssl.sh,
# затем соседский. Порядок такой, потому что у постороннего разработчика
# «АльтерВито» нет вовсе, а `?=` позволяет задать путь и вручную.
SSL_OUT ?= $(firstword $(wildcard $(HOME)/lovit/out $(HOME)/altervito/out) $(HOME)/lovit/out)

# libopus — тем же срезом на архитектуру, собирается tools/build-opus.sh из
# исходников в third_party/opus.
#
# Голосовые MAX ходят в Opus внутри Ogg, а на iOS 6 такого кодека нет вовсе:
# AVAudioRecorder умеет только AAC и линейный PCM, системный проигрыватель
# Opus не открывает. Ни записать, ни послушать голосовое без своей библиотеки
# нельзя — подробности в src/Core/Media/MAXOpus.h.
#
# Каталог отдельный от SSL_OUT намеренно: тот ищется по точному совпадению
# имени, и папка с opus внутри $(HOME)/lovit/out сбила бы поиск.
OPUS_OUT ?= $(HOME)/lovit/opus

# rlottie — движущиеся стикеры, собирается tools/build-rlottie.sh из
# исходников в third_party/rlottie. Та же библиотека, что рисует такие
# стикеры в Telegram и в клиенте под Windows Phone: Lottie — это описание
# векторной сцены во времени, и показать его можно только отрисовав.
RLOTTIE_OUT ?= $(HOME)/lovit/rlottie

# 9.3 — последний SDK, где ещё живы заголовки эпохи iOS 5–6 и есть срез armv7.
# Нижняя граница 6.0: раньше нет ни UICollectionView, ни NSTextAlignment*,
# ни subscripting-методов, на которых стоит весь код.
TARGET := iphone:9.3:6.0

# armv7 покрывает всё от iPhone 3GS до iPhone 5; arm64 — всё, что новее.
ARCHS := armv7 arm64

# dpkg-deb отказывается паковать каталог с правами 777, а именно их выдаёт
# диску Windows подсистема WSL — chmod там ничего не меняет. Поэтому дерево,
# из которого собирается пакет, складывается в файловую систему Linux.
export THEOS_STAGING_DIR ?= /tmp/theos-lovit/_

# Номер сборки — на каждую упаковку новый.
#
# Версия у приложения одна и та же от сборки к сборке, и установщик вправе
# счесть, что ставить нечего. Отсюда «поставил, а изменений не видно»: на
# устройстве остаётся прежняя сборка. Скрипт увеличивает CFBundleVersion
# в Info.plist и Version в control; пользователю на глаза это не попадается —
# имя и версию в списке приложений система берёт из CFBundleShortVersionString.
#
# Вызов идёт через $(shell), а не отдельным правилом, и стоит до common.mk
# намеренно: control разбирается на чтении makefile, а не при сборке, — из
# него берётся и версия в имени .deb. Правило, меняющее файл, опоздало бы
# ровно на один запуск.
#
# Условие по MAKECMDGOALS оставляет `make` без упаковки в покое: во время
# правки кода номер накручивать незачем.
ifneq ($(filter package ipa,$(MAKECMDGOALS)),)
BUILD_NUMBER := $(shell python3 $(CURDIR)/tools/bump-build.py)
$(info Сборка $(BUILD_NUMBER))
endif

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = Lovit

# Декодер WebP из third_party — на чистом C. Картинки в MAX отдаются только
# в WebP (проверено: CDN не умеет согласование формата и на любой Accept
# отвечает image/webp), а в iOS 7 такого декодера нет вовсе — фотографии
# в переписке просто не строились.
Lovit_FILES  = $(shell find src -name '*.m')
Lovit_FILES += $(shell find third_party/libwebp/src -name '*.c')

Lovit_CFLAGS  = -Wall -Wno-deprecated-declarations
Lovit_CFLAGS += $(addprefix -I,$(shell find src -type d))
Lovit_CFLAGS += -Ithird_party/libwebp
Lovit_CFLAGS += -I$(SSL_OUT)/$(THEOS_CURRENT_ARCH)/openssl/include
Lovit_CFLAGS += -I$(OPUS_OUT)/include
Lovit_CFLAGS += -I$(RLOTTIE_OUT)/include
Lovit_CFLAGS += -fvisibility=hidden

# Флаги ниже — только для Objective-C: на файлах libwebp -fobjc-arc бесполезен,
# а префиксные заголовки с Foundation там и вовсе не соберутся.
Lovit_OBJCFLAGS  = -fobjc-arc

# Заголовки, которые раньше давал Max-Prefix.pch в проекте Xcode. Theos своего
# префикса не подставляет, поэтому он подключается флагом.
Lovit_OBJCFLAGS += -include src/MAXPrefix.h

# Подменяет NSLog во всех файлах разом: всё, что уходит в системный журнал,
# попадает ещё и в Documents/max.log — оттуда его можно просто забрать
# с устройства. Подробности в src/MAXLog.h.
Lovit_OBJCFLAGS += -include src/MAXLog.h

# Security — SecTrustEvaluate и SecCertificateCreateWithData: ими проверяется
# цепочка до корня НУЦ Минцифры (src/Core/Security/MAXCertificates.m).
# AVFoundation — и звук, и видео: запись голосового и кружка, их
# проигрывание (AVPlayer, AVAudioPlayer) и режим звука (AVAudioSession).
# Без явного режима запись на устройстве идёт вхолостую, а проигрывание
# молчит при выключенном звонке.
#
# MediaPlayer здесь больше нет намеренно. MPMoviePlayerViewController на
# iOS 6 падал: исключение брошено внутри AVFoundation, а позвала её
# MediaPlayer со своей очереди — снаружи такое ни поймать, ни поправить.
# Видео и кружки играют свои проигрыватели на AVPlayer
# (src/UI/MAXVideoViewController.m, src/Core/Media/MAXVideoNotePlayer.m).
Lovit_FRAMEWORKS = UIKit CoreGraphics QuartzCore Security CFNetwork
Lovit_FRAMEWORKS += AVFoundation AudioToolbox
#
# QuickLook — просмотр скачанных документов (PDF, Word, тексты) средствами
# системы. Есть с iOS 4, своего к нему не требуется.
Lovit_FRAMEWORKS += QuickLook

# OpenSSL — статикой, отдельными файлами, а не через -l: так виднее, что
# именно линкуется, и не нужен -L с надеждой на порядок поиска.
Lovit_LDFLAGS  = $(SSL_OUT)/$(THEOS_CURRENT_ARCH)/openssl/lib/libssl.a
Lovit_LDFLAGS += $(SSL_OUT)/$(THEOS_CURRENT_ARCH)/openssl/lib/libcrypto.a
Lovit_LDFLAGS += $(OPUS_OUT)/$(THEOS_CURRENT_ARCH)/lib/libopus.a
Lovit_LDFLAGS += $(RLOTTIE_OUT)/$(THEOS_CURRENT_ARCH)/lib/librlottie.a

# rlottie написана на C++, отсюда libc++. Она системная и есть на iOS 6:
# /usr/lib/libc++.1.dylib виден в отчётах о падении с той прошивки.
#
# libz — распаковка описаний стикеров: MAX присылает их сжатыми gzip всегда,
# а не изредка.
#
# libc++abi здесь нарочно НЕ названа. То немногое, что от неё нужно
# (operator new и родня, семь символов), лежит в
# third_party/rlottie/max_cxx.cpp и уходит внутрь приложения: на iOS 6 этих
# символов в системной libc++abi нет, а библиотеку, у которой их спрашивать,
# приложение запоминает при сборке навсегда.
Lovit_LDFLAGS += -lc++ -lz

# NSObject ищем по всем библиотекам, а не в той, где он лежит сегодня.
#
# Само по себе приложение с нижней границей 6.0 в этом не нуждается: класс
# переехал в libobjc как раз в iOS 6. Нужда чисто сборочная — в общем наборе
# SDK (github.com/theos/sdks) libobjc.tbd пропатчен под соседний проект
# «Трубач», которому нужна граница 5.1: запись _NSObject из objc-classes там
# снята, чтобы компоновщик не привязывал класс к libobjc жёстко. Проверить
# состояние SDK можно так:
#
#   grep -o 'objc-classes:.*' ~/theos/sdks/iPhoneOS9.3.sdk/usr/lib/libobjc.tbd
#
# Если _NSObject в выводе нет — файл пропатчен, и без -U линковка встаёт на
# «Undefined symbols: _OBJC_CLASS_$_NSObject». Флаг снимает привязку к
# библиотеке ровно для двух имён: dyld ищет их во всём, что загружено.
#
# Доллар закрывается дважды, и оба раза по делу: \$$ превращается в \$ на
# разборе make, а уже \$ доживает до ld как $ — между ними ещё оболочка,
# для которой $_NSObject это имя переменной.
Lovit_LDFLAGS += -Wl,-U,_OBJC_CLASS_\$$_NSObject
Lovit_LDFLAGS += -Wl,-U,_OBJC_METACLASS_\$$_NSObject

# Классы URL-загрузки — та же ловушка, но с другим переездом.
#
# В SDK 9.3 NSURLConnection и NSMutableURLRequest объявлены в CFNetwork, и
# компоновщик записывает источником именно её. На iOS 7 они живут в Foundation,
# и приложение снималось dyld'ом ещё до main:
#
#   Symbol not found: _OBJC_CLASS_$_NSMutableURLRequest
#   Expected in: /System/Library/Frameworks/CFNetwork.framework/CFNetwork
#
# Константы kCFStream* остаются привязанными к CFNetwork намеренно: они и на
# iOS 7 лежат именно там. Проверить, что ничего похожего не осталось, можно
# так — tools/check-macho.py ругается на любой класс NS*, который просят не
# у Foundation:
#
#     python3 tools/check-macho.py packages/Lovit.ipa
Lovit_LDFLAGS += -Wl,-U,_OBJC_CLASS_\$$_NSURLConnection
Lovit_LDFLAGS += -Wl,-U,_OBJC_METACLASS_\$$_NSURLConnection
Lovit_LDFLAGS += -Wl,-U,_OBJC_CLASS_\$$_NSMutableURLRequest
Lovit_LDFLAGS += -Wl,-U,_OBJC_METACLASS_\$$_NSMutableURLRequest
Lovit_LDFLAGS += -Wl,-U,_OBJC_CLASS_\$$_NSHTTPURLResponse
Lovit_LDFLAGS += -Wl,-U,_OBJC_METACLASS_\$$_NSHTTPURLResponse
Lovit_LDFLAGS += -Wl,-U,_OBJC_CLASS_\$$_NSURLCredential
Lovit_LDFLAGS += -Wl,-U,_OBJC_METACLASS_\$$_NSURLCredential

# Подпись — с двумя сводками сразу, и это не прихоть.
#
#   -Cadhoc  признак «подпись сама себе удостоверение» — то, чем она и является;
#   -I…      имя, совпадающее с CFBundleIdentifier, — по нему система сверяет
#            подпись со связкой;
#   -S<файл> права из entitlements.plist. Пустой -S давал подпись вообще без
#            прав, и приложение не получало своей группы в связке ключей:
#            SecItemAdd отказывал, токен на деле не сохранялся, а вход слетал
#            при следующем запуске. Подробности — в самом entitlements.plist.
#
# Ключа -H здесь нет намеренно: без него ldid кладёт в подпись **два** описания
# кода — SHA-1 в основной слот и SHA-256 во второй (CSSLOT_ALTERNATE, 0x1000).
# Нужны оба, потому что ядра разных лет читают подпись по-разному:
#
#   iOS 6 (xnu-2050)   findCodeDirectory перебирает слоты и останавливается на
#                      первом с типом CSSLOT_CODEDIRECTORY (0). До второго
#                      описания дело не доходит вовсе;
#   iOS 7–9 (xnu-2782) cs_validate_csblob обходит все слоты, но разбирает как
#                      описание кода только нулевой; остальным достаётся
#                      cs_validate_blob — проверка длины, и ничего больше.
#                      Тип сводки там не смотрят;
#   iOS 10+ (xnu-3789) перебирает нулевой слот и весь диапазон
#                      CSSLOT_ALTERNATE_CODEDIRECTORIES, считает hash_rank
#                      (SHA-1 < SHA-256) и берёт лучшее из поддерживаемых.
#
# Отсюда и раскладка: SHA-1 внизу для старых, SHA-256 рядом для новых. Раньше
# здесь стояло -Hsha1 — из осторожности и по догадке, что второе описание
# старое ядро оскорбит. Догадка неверна: по коду видно, что оно его не читает.
#
# Двух описаний с **одинаковой** сводкой при этом быть не должно: новое ядро
# такое отвергает вслух («multiple hash=… CodeDirectories in signature»).
# За этим следит tools/check-macho.py.
#
# Что получилось, показывает python3 tools/check-macho.py packages/Lovit.ipa
Lovit_CODESIGN_FLAGS = -Cadhoc -Iru.computershik.lovit -S$(CURDIR)/entitlements.plist

include $(THEOS_MAKE_PATH)/application.mk

# Права на файлы приложения.
#
# WSL выдаёт всему на диске Windows права 777, и chmod там ничего не меняет.
# Каталог сборки поэтому и уносится в файловую систему Linux — но права
# приезжают туда вместе с файлами. Связку с правами 777 LaunchServices не
# регистрирует, а исполняемый файл, открытый на запись всем, система запускать
# отказывается — тихо, без записи в журнале падений.
after-stage::
	@find $(THEOS_STAGING_DIR) -type d -exec chmod 755 {} +
	@find $(THEOS_STAGING_DIR) -type f -exec chmod 644 {} +
	@chmod 755 $(THEOS_STAGING_DIR)/Applications/$(APPLICATION_NAME).app/$(APPLICATION_NAME)

# То же для служебного каталога пакета, и отдельным шагом: layout/DEBIAN
# переносится сюда позже — уже при упаковке, — так что предыдущее правило
# его ещё не застаёт.
before-package::
	@chmod 755 "$(THEOS_STAGING_DIR)/DEBIAN"
	@for script in preinst postinst prerm postrm; do \
		[ -f "$(THEOS_STAGING_DIR)/DEBIAN/$$script" ] && \
			chmod 755 "$(THEOS_STAGING_DIR)/DEBIAN/$$script"; \
	done; true
	@[ -f "$(THEOS_STAGING_DIR)/DEBIAN/control" ] && \
		chmod 644 "$(THEOS_STAGING_DIR)/DEBIAN/control"; true

# Payload/Lovit.app в zip — то же дерево, что кладётся в .deb.
ipa:: package
	@rm -rf $(THEOS_STAGING_DIR)-ipa
	@mkdir -p $(THEOS_STAGING_DIR)-ipa/Payload
	@cp -r $(THEOS_STAGING_DIR)/Applications/$(APPLICATION_NAME).app \
	       $(THEOS_STAGING_DIR)-ipa/Payload/
	@cd $(THEOS_STAGING_DIR)-ipa && zip -qry \
	       $(CURDIR)/packages/$(APPLICATION_NAME).ipa Payload
	@echo "packages/$(APPLICATION_NAME).ipa"
