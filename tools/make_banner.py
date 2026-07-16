#!/usr/bin/env python3
"""MTF title cards at Nexus specs.

  thumbnail  1920x1080  (16:9 main image) -- stacked two-line title
  banner     1300x372   (page header)     -- single-line title

Gabriola 'Magic Tattoos' + Cambria Bold 'Framework', white on black with a
faint emissive glow (#8C6CD0, the Hermaeus Mora SHOWCASE preset's emissive,
so the halo matches the showcase video). Pure typography + procedural glow.
"""
from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageChops
import os

OUT = os.path.join(os.path.dirname(__file__), "..", "_build", "banner")
os.makedirs(OUT, exist_ok=True)

GABRIOLA = r"C:\Windows\Fonts\Gabriola.ttf"
CAMBRIA_B = r"C:\Windows\Fonts\cambriab.ttf"
FILL = (245, 245, 245)
GLOW = (140, 108, 208)        # #8C6CD0

# word, font, size-scale relative to fitted base
W1, W2 = ("Magic Tattoos", GABRIOLA, 1.18), ("Framework", CAMBRIA_B, 0.92)

probe = ImageDraw.Draw(Image.new("RGB", (4, 4)))

def mkruns(items, base):
    return [(t, ImageFont.truetype(p, max(1, int(base * s)))) for t, p, s in items]

def runs_w(rs):
    return sum(probe.textlength(t, font=f) for t, f in rs)

def fit(items, target_w):
    lo, hi, best = 20, 700, 20
    while lo <= hi:
        mid = (lo + hi) // 2
        if runs_w(mkruns(items, mid)) <= target_w:
            best, lo = mid, mid + 1
        else:
            hi = mid - 1
    return best

def draw_runs(d, rs, cx, baseline, fill, sep=" "):
    # rs may be one word or two with a separator space between.
    total = runs_w(rs) + (probe.textlength(sep, font=rs[0][1]) if len(rs) > 1 else 0)
    x = cx - total / 2
    for i, (t, f) in enumerate(rs):
        d.text((x, baseline), t, font=f, fill=fill, anchor="ls")
        x += probe.textlength(t, font=f)
        if i == 0 and len(rs) > 1:
            x += probe.textlength(sep, font=f)

def asc_desc(rs):
    return (max(f.getmetrics()[0] for _, f in rs),
            max(f.getmetrics()[1] for _, f in rs))

def glow_compose(W, H, paint, blurs):
    """paint(draw, fill) renders the text; returns composited glow+white image."""
    base = Image.new("RGB", (W, H), (0, 0, 0))
    glow = Image.new("RGB", (W, H), (0, 0, 0))
    paint(ImageDraw.Draw(glow), GLOW)
    for r in blurs:
        base = ImageChops.add(base, glow.filter(ImageFilter.GaussianBlur(r)))
    paint(ImageDraw.Draw(base), FILL)
    return base

def banner(W=1300, H=372, frac=0.86):
    items = [W1, W2]
    rs = mkruns(items, fit(items, int(W * frac)))
    asc, desc = asc_desc(rs)
    baseline = (H - (asc + desc)) // 2 + asc
    img = glow_compose(W, H, lambda d, c: draw_runs(d, rs, W / 2, baseline, c),
                       blurs=(30, 16, 8))
    p = os.path.join(OUT, "FINAL_banner_1300x372.png"); img.save(p); print("wrote", p)

def thumbnail(W=1920, H=1080, frac=0.72):
    r1 = mkruns([W1], fit([W1], int(W * frac)))
    r2 = mkruns([W2], fit([W2], int(W * frac)))
    a1, d1 = asc_desc(r1); a2, d2 = asc_desc(r2)
    gap = int(H * 0.05)
    block = (a1 + d1) + gap + (a2 + d2)
    top = (H - block) // 2
    b1 = top + a1
    b2 = top + (a1 + d1) + gap + a2
    def paint(d, c):
        draw_runs(d, r1, W / 2, b1, c)
        draw_runs(d, r2, W / 2, b2, c)
    img = glow_compose(W, H, paint, blurs=(48, 26, 13))
    p = os.path.join(OUT, "FINAL_thumbnail_1920x1080.png"); img.save(p); print("wrote", p)

banner()
thumbnail()
