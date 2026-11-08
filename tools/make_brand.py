from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
LOGO = ROOT / "media" / "logos"
ICON = ROOT / "media" / "icons"
LOGO.mkdir(parents=True, exist_ok=True)
ICON.mkdir(parents=True, exist_ok=True)

TOP = (91, 84, 240)
BOTTOM = (62, 52, 199)
WHITE = (255, 255, 255, 255)


def rounded_mask(size, radius):
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size - 1, size - 1), radius=radius, fill=255)
    return mask


def gradient(size):
    img = Image.new("RGB", (size, size), TOP)
    draw = ImageDraw.Draw(img)
    for y in range(size):
        t = y / max(1, size - 1)
        colour = tuple(round(TOP[i] + (BOTTOM[i] - TOP[i]) * t) for i in range(3))
        draw.line([(0, y), (size, y)], fill=colour)
    return img


def render(size):
    scale = size / 1024
    img = gradient(size).convert("RGBA")

    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)

    ring = int(round(150 * scale))
    inset = int(round(212 * scale))
    draw.arc(
        (inset, inset, size - inset, size - inset),
        start=-52,
        end=232,
        fill=WHITE,
        width=ring,
    )

    stroke = int(round(86 * scale))
    pts = [
        (int(438 * scale), int(524 * scale)),
        (int(492 * scale), int(582 * scale)),
        (int(606 * scale), int(452 * scale)),
    ]
    draw.line(pts, fill=WHITE, width=stroke, joint="curve")
    for x, y in (pts[0], pts[-1]):
        r = stroke // 2
        draw.ellipse((x - r, y - r, x + r, y + r), fill=WHITE)

    img = Image.alpha_composite(img, layer)
    img.putalpha(rounded_mask(size, int(round(232 * scale))))
    return img


render(1024).save(LOGO / "testerloop-logo-1024.png")
render(512).save(ICON / "testerloop-icon-512.png")
render(256).save(ICON / "testerloop-icon-256.png")
render(114).save(ICON / "testerloop-icon-114.png")

ico_sizes = [(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)]
render(256).save(ICON / "testerloop.ico", sizes=ico_sizes)

print("wrote:", *(p.name for p in sorted(LOGO.glob("*.png"))), *(p.name for p in sorted(ICON.glob("*.png"))), "testerloop.ico")
