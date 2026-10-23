# -*- coding: utf-8 -*-
"""
Достаёт контуры иконок из ресурсов Android-клиента MAX.

Иконки там — vector drawable, то есть XML с атрибутом pathData в синтаксисе
путей SVG. Сами файлы лежат в скомпилированном виде (AXML), но строковый пул
в них не сжат: pathData читается из байтов как есть, между нулями. Поэтому
разбирать формат чанков целиком не нужно — достаточно вытащить строки,
похожие на путь.

Размер холста (viewportWidth) хранится не строкой, а числом с плавающей
точкой в таблице значений, и достать его тем же способом нельзя. Угадывать
его по наибольшей координате не выходит: в сокращённой записи дуг радиус
бывает трёхзначным, и оценка уезжает втрое. Поэтому холст не извлекается
вовсе — MAXIconRenderer вписывает контур по его собственным границам
(CGPathGetBoundingBox). Для панели вкладок это даже лучше: иконки с разным
внутренним отступом получаются одного видимого размера.

    python3 tools/extract-icons.py /путь/к/res/drawable

Результат — src/UI/Icons/MAXIconData.m, который рисуется в рантайме
через MAXIconRenderer.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEST = os.path.join(ROOT, "src", "UI", "Icons", "MAXIconData.m")

# Что берём и под каким именем это будет known в коде.
WANTED = {
    # нижняя панель
    "icon_message": "chats",
    "icon_message_fill": "chatsFilled",
    "icon_phone_book_fill": "contacts",
    "icon_settings": "settings",
    "icon_settings_fill": "settingsFilled",
    # строка ввода
    "icon_attachment": "attach",
    "icon_camera": "camera",
    "icon_send": "send",
    "icon_arrow_up": "arrowUp",
    # сообщения и вложения
    "icon_file": "file",
    "icon_file_fill": "fileFilled",
    "icon_download": "download",
    "icon_media": "media",
    "icon_check": "check",
    "icon_check_mini": "checkMini",
    "icon_search": "search",
    "icon_plus": "plus",
    # Проигрывание. Отдельной иконки «играть» в ресурсах нет: в Android она
    # живёт кадрами перехода «играть -> пауза», и нужен нам самый первый
    # кадр — там треугольник ещё целый. Второй контур в этом кадре — палочка
    # паузы, она пока сжата в точку; отсюда выбор контура по счёту.
    "$play_to_pause__0": ("play", [0]),
    # Пауза — последний кадр того же перехода лежит в другом файле.
    "icon_video_message_stop": ("pause", [1]),
    # Буква «Т» — расшифровка голосового. Два контура: ножка и перекладина.
    "icon_text": "text",
}

# Нарисованное нами, а не взятое у Android: там этих знаков нет вовсе.
# Холст 24x24, как у остальных.
OWN = {
    # Квадрат со скруглением: «стоп». В Android на этом месте пауза, а наш
    # проигрыватель голосовых именно останавливает — с начала, а не с места.
    "stop": [
        "M8 5h8a3 3 0 0 1 3 3v8a3 3 0 0 1-3 3H8a3 3 0 0 1-3-3V8a3 3 0 0 1 3-3z"
    ],
    # Три точки: «качается». Заменяют собой многоточие, которое стояло
    # раньше и на разных прошивках рисовалось по-разному.
    "waiting": [
        "M4 12a2 2 0 1 0 4 0 2 2 0 1 0-4 0",
        "M10 12a2 2 0 1 0 4 0 2 2 0 1 0-4 0",
        "M16 12a2 2 0 1 0 4 0 2 2 0 1 0-4 0"
    ],
}

# Путь ищется подстрокой, а не «весь кусок между нулями»: перед строкой в пуле
# стоят байты её длины, и точного совпадения куска с контуром не бывает.
PATH_RE = re.compile(r"[Mm] ?-?\d[MmLlHhVvCcSsQqTtAaZz0-9.,\-+eE \t]{15,}")


def paths_from_axml(data):
    text = data.decode("latin-1")

    found = []
    for match in PATH_RE.finditer(text):
        path = match.group(0).strip()
        # Хвост из одних цифр без команд — это не контур, а обрывок таблицы.
        if not re.search(r"[LlHhVvCcSsQqTtAaZz]", path):
            continue
        if path not in found:
            found.append(path)
    return found


def escape(text):
    return text.replace("\\", "\\\\").replace('"', '\\"')


def main():
    if len(sys.argv) < 2:
        print("укажите папку res/drawable из распакованного APK MAX")
        return 1
    source = sys.argv[1]

    collected = {}
    for filename, wanted in sorted(WANTED.items()):
        # Значением бывает либо имя, либо имя и номера нужных контуров.
        name, keep = wanted if isinstance(wanted, tuple) else (wanted, None)

        full = os.path.join(source, filename + ".xml")
        if not os.path.exists(full):
            print("нет %s — пропускаю" % filename)
            continue

        with open(full, "rb") as handle:
            data = handle.read()

        paths = paths_from_axml(data)
        if not paths:
            print("в %s не нашлось контуров — пропускаю" % filename)
            continue

        if keep is not None:
            if max(keep) >= len(paths):
                print("в %s нет контура №%d — пропускаю" % (filename, max(keep)))
                continue
            paths = [paths[position] for position in keep]

        collected[name] = (paths, filename)
        print("%-22s %-16s контуров: %d" % (filename, name, len(paths)))

    for name in sorted(OWN):
        collected[name] = (OWN[name], "нарисовано нами")
        print("%-22s %-16s контуров: %d" % ("—", name, len(OWN[name])))

    if not collected:
        print("ничего не извлечено")
        return 1

    os.makedirs(os.path.dirname(DEST), exist_ok=True)

    with open(DEST, "w", encoding="utf-8") as out:
        out.write("//\n//  MAXIconData.m\n//\n")
        out.write("//  СГЕНЕРИРОВАНО tools/extract-icons.py из ресурсов\n")
        out.write("//  Android-клиента MAX. Правки вносить в генератор.\n")
        out.write("//\n\n")
        out.write('#import "MAXIcons.h"\n\n')
        out.write("NSDictionary *MAXIconDefinitions(void) {\n")
        out.write("    static NSDictionary *icons = nil;\n")
        out.write("    static dispatch_once_t once;\n")
        out.write("    dispatch_once(&once, ^{\n")
        out.write("        icons = @{\n")

        names = sorted(collected)
        for index, name in enumerate(names):
            paths, filename = collected[name]
            tail = "," if index < len(names) - 1 else ""
            out.write('            // %s\n' % filename)
            out.write('            @"%s": @[\n' % name)
            for position, path in enumerate(paths):
                comma = "," if position < len(paths) - 1 else ""
                out.write('                @"%s"%s\n' % (escape(path), comma))
            out.write("            ]%s\n" % tail)

        out.write("        };\n    });\n    return icons;\n}\n")

    print("\nзаписано: %s" % DEST)
    return 0


if __name__ == "__main__":
    sys.exit(main())
