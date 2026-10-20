"""Genera logo e icone di Dollarz (monogramma D$) in tutti i formati.

Uso (da dollarz/):  python tool/brand.py
Scrive: assets/brand/*, windows/runner/resources/app_icon.ico,
android/app/src/main/res/drawable-*/ic_stat_dollarz.png, launch_mark.png,
installer/wizard*.bmp. Poi: dart run flutter_launcher_icons
"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
NAVY = (12, 19, 38, 255)        # #0C1326 sfondo
CARD = (21, 32, 57, 255)        # #152039
ACCENT = (108, 140, 255, 255)   # #6C8CFF
INK = (231, 236, 247, 255)      # #E7ECF7
SS = 4                          # supersampling


def mark_mask(size):
    """Maschera L del monogramma su una tela quadrata [size] (D con il taglio del dollaro)."""
    n = size * SS
    m = Image.new('L', (n, n), 0)
    d = ImageDraw.Draw(m)
    k = n / 1024
    W, H, s = 540 * k, 600 * k, 100 * k
    left, top = (n - W) / 2, (n - H) / 2
    bottom = top + H
    R = H / 2
    cx = left + W - R          # centro della pancia della D
    cy = n / 2
    rc = 34 * k                # angoli a sinistra appena arrotondati
    # esterno
    d.rounded_rectangle([left, top, cx + rc, bottom], radius=rc, fill=255)
    d.pieslice([cx - R, cy - R, cx + R, cy + R], -90, 90, fill=255)
    # interno
    r2 = R - s
    d.rectangle([left + s, top + s, cx, bottom - s], fill=0)
    d.pieslice([cx - r2, cy - r2, cx + r2, cy + r2], -90, 90, fill=0)
    # taglio verticale del dollaro: attraversa la D e sporge sopra e sotto
    b = 64 * k
    bx = left + W / 2
    ext = 104 * k
    d.rounded_rectangle([bx - b / 2, top - ext, bx + b / 2, bottom + ext], radius=b / 2, fill=255)
    return m.resize((size, size), Image.LANCZOS)


def mark_image(size, color, bg=None, scale=1.0, radius=0.0):
    """Monogramma colorato; [bg] riempie lo sfondo (con angoli [radius] in frazione del lato)."""
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    if bg is not None:
        tile = Image.new('L', (size * SS, size * SS), 0)
        ImageDraw.Draw(tile).rounded_rectangle([0, 0, size * SS - 1, size * SS - 1], radius=radius * size * SS, fill=255)
        tile = tile.resize((size, size), Image.LANCZOS)
        img.paste(Image.new('RGBA', (size, size), bg), (0, 0), tile)
    inner = max(1, round(size * scale))
    m = mark_mask(inner)
    off = (size - inner) // 2
    img.paste(Image.new('RGBA', (inner, inner), color), (off, off), m)
    return img


def save_ico(path, sizes, **kw):
    imgs = [mark_image(s, **kw) for s in sizes]
    path.parent.mkdir(parents=True, exist_ok=True)
    imgs[-1].save(path, format='ICO', sizes=[(s, s) for s in sizes], append_images=imgs[:-1])


def wizard(w, h, small=False):
    img = Image.new('RGB', (w, h), NAVY[:3])
    if small:
        m = mark_image(min(w, h), ACCENT, scale=0.8)
        img.paste(m, ((w - m.width) // 2, (h - m.height) // 2), m)
        return img
    m = mark_image(int(w * 0.62), ACCENT, scale=0.9)
    img.paste(m, ((w - m.width) // 2, int(h * 0.22)), m)
    try:
        font = ImageFont.truetype(str(ROOT / 'assets' / 'fonts' / 'Sora-700.ttf'), int(w * 0.17))
        d = ImageDraw.Draw(img)
        tw = d.textlength('Dollarz', font=font)
        d.text(((w - tw) / 2, int(h * 0.22) + m.height + int(h * 0.04)), 'Dollarz', font=font, fill=INK[:3])
    except OSError:
        pass
    return img


def main():
    brand = ROOT / 'assets' / 'brand'
    brand.mkdir(parents=True, exist_ok=True)
    # nell'app: bianco su trasparente, colorato con Image.color
    mark_image(512, (255, 255, 255, 255), scale=0.92).save(brand / 'mark.png')
    # launcher Android: icona intera (legacy), primo piano adattivo e monocromatica
    mark_image(1024, ACCENT, bg=NAVY, scale=0.62).save(brand / 'icon_full.png')
    mark_image(1024, ACCENT, scale=0.50).save(brand / 'icon_fg.png')
    mark_image(1024, (255, 255, 255, 255), scale=0.50).save(brand / 'icon_mono.png')
    mark_image(1024, ACCENT, bg=NAVY, scale=0.62, radius=0.22).save(brand / 'icon_rounded.png')
    # Windows: exe e area di notifica
    save_ico(ROOT / 'windows' / 'runner' / 'resources' / 'app_icon.ico', [16, 20, 24, 32, 40, 48, 64, 128, 256],
             color=ACCENT, bg=NAVY, scale=0.74, radius=0.22)
    save_ico(brand / 'tray.ico', [16, 20, 24, 32, 40, 48, 64], color=ACCENT, bg=NAVY, scale=0.78, radius=0.24)
    # Android: icona piccola delle notifiche (bianca) e marchio della schermata di avvio
    res = ROOT / 'android' / 'app' / 'src' / 'main' / 'res'
    for dpi, px in {'mdpi': 24, 'hdpi': 36, 'xhdpi': 48, 'xxhdpi': 72, 'xxxhdpi': 96}.items():
        p = res / f'drawable-{dpi}'
        p.mkdir(parents=True, exist_ok=True)
        mark_image(px, (255, 255, 255, 255), scale=0.9).save(p / 'ic_stat_dollarz.png')
    nodpi = res / 'drawable-nodpi'
    nodpi.mkdir(parents=True, exist_ok=True)
    mark_image(288, ACCENT, scale=0.9).save(nodpi / 'launch_mark.png')
    # installer
    inst = ROOT / 'installer'
    inst.mkdir(exist_ok=True)
    wizard(164, 314).save(inst / 'wizard.bmp')
    wizard(410, 797).save(inst / 'wizard_250.bmp')
    wizard(55, 55, small=True).save(inst / 'wizard_small.bmp')
    wizard(138, 140, small=True).save(inst / 'wizard_small_250.bmp')
    print('icone generate')


if __name__ == '__main__':
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    main()
