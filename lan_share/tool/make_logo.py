"""Draws the LAN Share logo and writes every icon size the app needs.

Run from lan_share/:  python tool/make_logo.py
"""
import os
from PIL import Image, ImageDraw, ImageFilter

S = 2048  # supersampled master size
BLUE, VIOLET = (59, 130, 246), (139, 92, 246)


def gradient(size):
    # smooth diagonal blue -> violet
    import numpy as np
    t = (np.add.outer(np.arange(size), np.arange(size)) / (2.0 * (size - 1)))[..., None]
    a, b = np.array(BLUE, float), np.array(VIOLET, float)
    return Image.fromarray((a + (b - a) * t).astype("uint8"), "RGB")


def master():
    bg = gradient(S)
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, S - 1, S - 1), radius=int(S * 0.225), fill=255)
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    img.paste(bg, (0, 0), mask)

    glyph = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(glyph)
    w = int(S * 0.10)
    tip = (int(S * 0.70), int(S * 0.30))
    tail = (int(S * 0.42), int(S * 0.58))
    arm_h = (int(S * 0.45), tip[1])
    arm_v = (tip[0], int(S * 0.55))
    for a, b in ((tail, tip), (arm_h, tip), (tip, arm_v)):
        d.line((*a, *b), fill="white", width=w)
    for cx, cy in (tail, tip, arm_h, arm_v):
        d.ellipse((cx - w // 2, cy - w // 2, cx + w // 2, cy + w // 2), fill="white")
    # signal arcs, bottom-left corner, fading outward
    cx, cy = int(S * 0.16), int(S * 0.84)
    for i, a in enumerate((245, 170, 100)):
        r = int(S * (0.10 + 0.09 * i))
        d.arc((cx - r, cy - r, cx + r, cy + r), start=270, end=360,
              fill=(255, 255, 255, a), width=int(S * 0.04))
    shadow = glyph.filter(ImageFilter.GaussianBlur(S * 0.012))
    shadow = Image.composite(Image.new("RGBA", (S, S), (20, 20, 80, 90)), Image.new("RGBA", (S, S), (0, 0, 0, 0)), shadow.split()[3])
    img = Image.alpha_composite(img, shadow.transform((S, S), Image.AFFINE, (1, 0, 0, 0, 1, -S * 0.012)))
    return Image.alpha_composite(img, glyph)


def main():
    m = master()
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    os.makedirs(os.path.join(root, "assets"), exist_ok=True)
    m.resize((1024, 1024), Image.LANCZOS).save(os.path.join(root, "assets", "logo.png"))
    ico = os.path.join(root, "windows", "runner", "resources", "app_icon.ico")
    m.save(ico, format="ICO", sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
    stage = os.path.join(root, "windows", "sparse", "stage", "Assets")
    os.makedirs(stage, exist_ok=True)
    for f in os.listdir(stage):
        os.remove(os.path.join(stage, f))

    def save(name, px):
        m.resize((px, px), Image.LANCZOS).save(os.path.join(stage, name))

    # Windows picks icons by qualified file name; give it every standard variant.
    for scale in (100, 125, 150, 200, 400):
        save(f"Square44x44Logo.scale-{scale}.png", round(44 * scale / 100))
        save(f"Square150x150Logo.scale-{scale}.png", round(150 * scale / 100))
        save(f"StoreLogo.scale-{scale}.png", round(50 * scale / 100))
    for size in (16, 20, 24, 30, 32, 36, 40, 44, 48, 60, 64, 72, 80, 96, 256):
        save(f"Square44x44Logo.targetsize-{size}.png", size)
        save(f"Square44x44Logo.targetsize-{size}_altform-unplated.png", size)
    print("logo written")


if __name__ == "__main__":
    main()
