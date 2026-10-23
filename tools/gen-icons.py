# -*- coding: utf-8 -*-
"""
Режет значок приложения по размерам, которые нужны iOS, и собирает из него
экраны запуска.

Источник — `tools/icon-source.jpg`: готовая картинка, кольцо-облачко с машиной
внутри на фирменном градиенте MAX. Отсылка к рекламе мессенджера, «ловит даже
на парковке», откуда и название приложения. Значок не рисуется здесь заново
и не подгоняется: что дано, то и раскладывается по размерам.

Почему теперь с Pillow. Прежняя версия рисовала фигуру сама на голом `zlib` —
в WSL не было Pillow, и заводить зависимость ради одной фигуры не хотелось.
Теперь задача другая: не нарисовать, а уменьшить готовый JPEG. Писать под это
свой декодер JPEG и приличный ресемплер — несоизмеримо больше кода, чем стоит
вопрос, а Pillow в системе уже есть (проверить: `python3 -c "import PIL"`).

Экран запуска — не просто вставленный значок: квадратная плитка посреди
экрана выглядела бы наклейкой. Поэтому фон разливается по углам исходника
(цвета берутся из него же, так что расхождения с значком нет), а поверх
кладётся белая фигура, вырезанная из картинки по яркости.

Скругления нет: углы обрезает сама система, и SpringBoard на джейлбрейке,
и обычная iOS. Скругли мы их сами, вышел бы двойной радиус. Блик тоже
не рисуется — в Info.plist стоит UIPrerenderedIcon.

    python3 tools/gen-icons.py
"""
import os

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RESOURCES = os.path.join(ROOT, "Resources")
SOURCE = os.path.join(ROOT, "tools", "icon-source.jpg")

# Размеры, объявленные в CFBundleIconFiles.
SIZES = [57, 72, 76, 114, 120, 144, 152, 180]

# Экраны запуска: по наличию картинки нужного размера iOS решает, умеет ли
# приложение работать на этом экране.
LAUNCH = [
    ("Default.png", 320, 480),                     # 3,5 дюйма, без ретины
    ("Default@2x.png", 640, 960),                  # iPhone 4 и 4S
    ("Default-568h@2x.png", 640, 1136),            # iPhone 5, 5s, SE
    ("Default-667h@2x.png", 750, 1334),            # iPhone 6, 7, 8
    ("Default-736h@3x.png", 1242, 2208),           # iPhone 6 Plus и новее
    ("Default-Portrait~ipad.png", 768, 1024),      # iPad без ретины
    ("Default-Portrait@2x~ipad.png", 1536, 2048),  # iPad с ретиной

    # Планшет запускают лёжа не реже, чем стоя. Без этих двух файлов система
    # показывает портретную заставку повёрнутой набок — на iPad 2 это первое,
    # что видно при запуске.
    ("Default-Landscape~ipad.png", 1024, 768),
    ("Default-Landscape@2x~ipad.png", 2048, 1536),
]

# Доля короткой стороны экрана, которую занимает фигура на заставке.
LAUNCH_FIGURE = 0.34

# Порог белого при вырезании фигуры. Берётся по самому тёмному каналу: у белой
# фигуры он 255, а у фона — 86 в левом верхнем углу и 96 в правом нижнем,
# то есть между ними целая пропасть, и порог можно ставить смело.
WHITE_FLOOR = 150


def figure_mask(source):
    """
    Маска белой фигуры: 255 там, где кольцо и машина, 0 на градиенте.

    Считается по самому тёмному каналу, а не по яркости: фон синий и
    фиолетовый, у него канал B под самый потолок, и по яркости фигура местами
    сливалась бы с фоном.
    """
    red, green, blue = source.split()

    darkest = Image.new("L", source.size)
    darkest_pixels = darkest.load()
    red_pixels, green_pixels, blue_pixels = red.load(), green.load(), blue.load()

    width, height = source.size
    span = 255 - WHITE_FLOOR

    for y in range(height):
        for x in range(width):
            value = min(red_pixels[x, y], green_pixels[x, y], blue_pixels[x, y])
            if value <= WHITE_FLOOR:
                darkest_pixels[x, y] = 0
            else:
                darkest_pixels[x, y] = int((value - WHITE_FLOOR) * 255 / span)

    return darkest


def corner_gradient(source, width, height):
    """
    Фон заставки: цвета четырёх углов исходника, разлитые по экрану.

    Так заставка и значок остаются одного семейства даже при том, что
    пропорции у них разные.
    """
    source_width, source_height = source.size
    corners = Image.new("RGB", (2, 2))
    corners.putpixel((0, 0), source.getpixel((0, 0)))
    corners.putpixel((1, 0), source.getpixel((source_width - 1, 0)))
    corners.putpixel((0, 1), source.getpixel((0, source_height - 1)))
    corners.putpixel((1, 1), source.getpixel((source_width - 1, source_height - 1)))

    return corners.resize((width, height), Image.BICUBIC)


def main():
    if not os.path.isfile(SOURCE):
        raise SystemExit("нет %s — значок брать неоткуда" % SOURCE)

    if not os.path.isdir(RESOURCES):
        os.makedirs(RESOURCES)

    source = Image.open(SOURCE).convert("RGB")

    for size in SIZES:
        name = "Icon-%d.png" % size
        source.resize((size, size), Image.LANCZOS).save(
            os.path.join(RESOURCES, name), "PNG")
        print(name)

    mask = figure_mask(source)

    for name, width, height in LAUNCH:
        canvas = corner_gradient(source, width, height)

        figure = int(min(width, height) * LAUNCH_FIGURE)
        white = Image.new("RGB", (figure, figure), (255, 255, 255))
        scaled_mask = mask.resize((figure, figure), Image.LANCZOS)

        canvas.paste(white, ((width - figure) // 2, (height - figure) // 2),
                     scaled_mask)
        canvas.save(os.path.join(RESOURCES, name), "PNG")
        print(name)


if __name__ == "__main__":
    main()
