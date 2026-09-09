# -*- coding: utf-8 -*-
"""
Значок приложения и экраны запуска — в цветах YClients.

Плитка жёлтая, знак — чёрная угловатая «Y»: две наклонные полосы, сходящиеся
в ножку. Это не логотип YClients, а узнаваемый родственник: чужой знак
в чужое приложение не кладём, но жёлтая плитка с чёрной буквой в списке
программ читается однозначно.

Что не делаем:

* не скругляем углы — их обрезает сама система, вышел бы двойной радиус;
* не рисуем блик — в Info.plist стоит UIPrerenderedIcon.

Размеры не по плотностям, а по устройствам: 57 и 114 — iPhone до iOS 7,
120 — iPhone с iOS 7, 72 и 144 — iPad, 76 и 152 — iPad с iOS 7, 180 — Plus.

Рисуется вчетверо крупнее и уменьшается: у PIL нет сглаживания фигур.

    python3 tools/gen-icons.py
"""
import os

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RESOURCES = os.path.join(ROOT, "Resources")

YELLOW = (255, 200, 0, 255)
INK = (28, 28, 30, 255)
WHITE = (255, 255, 255, 255)

SIZES = [57, 72, 76, 114, 120, 144, 152, 180]

LAUNCH = [
    ("Default.png", 320, 480),
    ("Default@2x.png", 640, 960),
    ("Default-568h@2x.png", 640, 1136),
    ("Default-667h@2x.png", 750, 1334),
    ("Default-736h@3x.png", 1242, 2208),
    ("Default-Portrait~ipad.png", 768, 1024),
    ("Default-Portrait@2x~ipad.png", 1536, 2048),
    ("Default-Landscape~ipad.png", 1024, 768),
    ("Default-Landscape@2x~ipad.png", 2048, 1536),
]

SCALE = 4


def mark(big, ink):
    """Знак «Y» на прозрачном холсте: две наклонные полосы и ножка."""
    layer = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    u = big / 100.0

    def p(x, y):
        return (x * u, y * u)

    # Левая полоса — толще, правая — тоньше: так знак не симметричен
    # и не читается как буква из шрифта.
    draw.polygon([p(20, 22), p(38, 22), p(58, 60), p(48, 78)], fill=ink)
    draw.polygon([p(66, 22), p(80, 22), p(58, 60), p(51, 47)], fill=ink)
    draw.polygon([p(44, 62), p(58, 62), p(58, 82), p(44, 82)], fill=ink)

    return layer


def tile(size):
    big = size * SCALE
    image = Image.new("RGBA", (big, big), YELLOW)
    image = Image.alpha_composite(image, mark(big, INK))
    return image.resize((size, size), Image.LANCZOS)


def launch(width, height):
    """Белое поле и жёлтая плитка со знаком по центру — как экран входа."""
    image = Image.new("RGBA", (width, height), WHITE)

    side = int(min(width, height) * 0.26)
    plate = tile(side)

    # Скругление плитки на экране запуска рисуем сами: тут система углы
    # не режет.
    maskbig = Image.new("L", (side * SCALE, side * SCALE), 0)
    ImageDraw.Draw(maskbig).rounded_rectangle(
        [0, 0, side * SCALE - 1, side * SCALE - 1], radius=int(side * SCALE * 0.22), fill=255)
    mask = maskbig.resize((side, side), Image.LANCZOS)

    image.paste(plate, ((width - side) // 2, (height - side) // 2), mask)

    return image.convert("RGB")


if __name__ == "__main__":
    if not os.path.isdir(RESOURCES):
        os.makedirs(RESOURCES)

    for size in SIZES:
        name = "Icon-%d.png" % size
        tile(size).convert("RGB").save(os.path.join(RESOURCES, name))
        print(name, size)

    for name, width, height in LAUNCH:
        launch(width, height).save(os.path.join(RESOURCES, name))
        print(name, "%dx%d" % (width, height))
