#!/usr/bin/env python3
"""
Увеличивает номер сборки на единицу.

Зачем. Версия у приложения одна и та же от сборки к сборке, и установщик
вправе счесть, что ставить нечего: файлы совпадают по версии, значит и
обновлять их незачем. Отсюда «поставил, а изменений не видно» — на устройстве
осталась прежняя сборка.

Что меняется:

* `CFBundleVersion` в Resources/Info.plist — техническая версия, тот самый
  versionCode из Android. Пользователю она на глаза не попадается: имя и
  «версию» в списке приложений система берёт из `CFBundleShortVersionString`,
  а его скрипт не трогает.
* `Version:` в control — по нему пакет сравнивает версии dpkg, когда
  приложение ставят из .deb.

Номер хранится в самом Info.plist последним числом: `1.0` → `1.0.1` → `1.0.2`.
Отдельный файл со счётчиком не нужен, а в «О приложении» строка версии уже
показывает `CFBundleVersion` в скобках — по ней и видно, что на устройстве
именно свежая сборка.

Вызывается из Makefile при упаковке; печатает новый номер.
"""

import io
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
INFO_PLIST = os.path.join(ROOT, "Resources", "Info.plist")
CONTROL = os.path.join(ROOT, "control")

# Значение ключа в plist: правится подстроками, а не через plistlib —
# тот перепишет файл целиком и переставит отступы там, где их не просили.
PLIST_VALUE = r"(<key>{0}</key>\s*<string>)([^<]*)(</string>)"


def read(path):
    with io.open(path, encoding="utf-8") as handle:
        return handle.read()


def write(path, text):
    with io.open(path, "w", encoding="utf-8", newline="") as handle:
        handle.write(text)


def plist_value(text, key):
    found = re.search(PLIST_VALUE.format(re.escape(key)), text)
    return found.group(2) if found else None


def set_plist_value(text, key, value):
    return re.sub(PLIST_VALUE.format(re.escape(key)),
                  lambda m: m.group(1) + value + m.group(3), text, count=1)


def next_version(short, current):
    """Следующий номер сборки.

    Если техническая версия уже начинается с пользовательской — увеличиваем
    её последнее число. Если нет (например, версию в plist правили руками),
    отсчёт начинается заново от единицы: продолжать чужую нумерацию хуже,
    чем начать свою.
    """
    prefix = short + "."
    if current is not None and current.startswith(prefix):
        tail = current[len(prefix):]
        if tail.isdigit():
            return prefix + str(int(tail) + 1)
    return prefix + "1"


def main():
    plist = read(INFO_PLIST)

    short = plist_value(plist, "CFBundleShortVersionString")
    if short is None:
        sys.stderr.write("bump-build: в Info.plist нет CFBundleShortVersionString\n")
        return 1

    version = next_version(short, plist_value(plist, "CFBundleVersion"))
    write(INFO_PLIST, set_plist_value(plist, "CFBundleVersion", version))

    control = read(CONTROL)
    if re.search(r"(?m)^Version:", control):
        control = re.sub(r"(?m)^Version:.*$", "Version: " + version, control, count=1)
        write(CONTROL, control)

    sys.stdout.write(version)
    return 0


if __name__ == "__main__":
    sys.exit(main())
