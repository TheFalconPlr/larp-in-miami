"""Ikony gamepassów i produktów do Creator Hub: 24 kolorowe PNG 512×512 w stylu ikon gry.

Styl jak w tools/build_icons.py (naklejki 3D: gruby ciemny obrys, kolorowa góra, ciemniejszy bok), do tego
kolorowe tło z promieniami w kolorze karty ze sklepu (Theme.Gradients) i napisy czcionką FredokaOne.
Wszystko ważne stoi w środku koła, bo Roblox może uciąć rogi ikony.

Uruchom z głównego folderu projektu:  python tools/build_shop_icons.py
Wymaga: pip install playwright oraz Chrome albo  python -m playwright install chromium
Wynik: assets/shop-icons/passes/<klucz>.png, assets/shop-icons/products/<klucz>.png i podgląd
assets/shop-icons/preview.png. Klucze są te same co w src/shared/Config/RobuxIds.luau.
Czcionka: assets/fonts/fredoka-one-latin-400-normal.woff2 (SIL OFL 1.1, licencja w licenses/).
"""
import base64
import math
import os
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, '..'))
sys.path.insert(0, HERE)
import build_icons as bi  # noqa: E402  (wspólne klocki stylu ikon)

OUT_DIR = os.path.join(ROOT, 'assets', 'shop-icons')
FONT_FILE = os.path.join(ROOT, 'assets', 'fonts', 'fredoka-one-latin-400-normal.woff2')
FONT = 'FredokaOne'
SIZE = 512
ART = 1.6          # rysunek powstaje w polu 256×256 i jest powiększany 1,6× na środek płótna 512
OUT = bi.OUT

# Kolory tła: (środek, brzeg). Odpowiadają kolorom kart w sklepie (Theme.Gradients).
BG = {
    'LP': ('#A8F7FF', '#1677E0'),
    'Green': ('#B4F58A', '#259018'),
    'Yellow': ('#FFF08A', '#FF8F00'),
    'Cyan': ('#9BEBFF', '#1468CF'),
    'Pink': ('#FFA8D4', '#C2196F'),
    'Premium': ('#E2C2FF', '#5E1CCB'),
    'Red': ('#FF9AA4', '#C20F2B'),
    'Gold': ('#FFF29A', '#FF9100'),
    'Portal': ('#D2B8FF', '#2F3FD8'),
    'Starter': ('#FFB9DE', '#F2402A'),
    'Epic': ('#E6C2FF', '#6A1FCC'),
    'Legendary': ('#FFEBA0', '#F27A00'),
    'Mythic': ('#FFBCD2', '#CF0F4C'),
}

GOLD_TEXT = (('#FFFCD6', '#FFC21A'), '#B86E00')
WHITE_TEXT = (('#FFFFFF', '#E6EEFF'), '#8E9CC0')


# ------------------------------------------------------------------ klocki
def mix(c1, c2, t):
    a = [int(c1[i:i + 2], 16) for i in (1, 3, 5)]
    b = [int(c2[i:i + 2], 16) for i in (1, 3, 5)]
    return '#%02X%02X%02X' % tuple(int(round(a[k] + (b[k] - a[k]) * t)) for k in range(3))


class Ids:
    """Unikalne id gradientów w jednej ikonie."""

    def __init__(self):
        self.n = 0

    def __call__(self, name):
        self.n += 1
        return '%s%d' % (name, self.n)


def parts_svg(parts):
    return ''.join(bi.render_part(p) for p in parts)


def borrowed(fn, cx, cy, k, ref):
    """Rysunek z build_icons.py przesunięty i przeskalowany; obrys i wytłoczenie zostają tej samej grubości."""
    saved = (bi.OW, bi.EDGE, bi.EX)
    bi.OW, bi.EDGE, bi.EX = saved[0] / k, saved[1] / k, (saved[2][0] / k, saved[2][1] / k)
    try:
        defs, parts, extra = fn()
        body = parts_svg(parts) + extra
    finally:
        bi.OW, bi.EDGE, bi.EX = saved
    return defs, '<g transform="translate(%.1f %.1f) scale(%.3f) translate(%.1f %.1f)">%s</g>' % (
        cx, cy, k, -ref[0], -ref[1], body)


def label(ids, text, x, y, size, style=GOLD_TEXT, ow=7.0, edge=4.0, ex=(4.0, 9.0)):
    """Napis jak naklejka: obrys, bok i góra z gradientem. y = linia bazowa."""
    (c1, c2), side = style
    gid = ids('lbl')
    defs = bi.grad(gid, c1, c2)
    base = 'x="%.1f" y="%.1f" font-family="%s" font-size="%s" text-anchor="middle"' % (x, y, FONT, size)
    outline, sides = [], []
    for i in range(bi.STEPS + 1):
        t = i / float(bi.STEPS)
        tr = 'transform="translate(%.2f %.2f)"' % (ex[0] * t, ex[1] * t)
        outline.append('<text %s %s fill="%s" stroke="%s" stroke-width="%.1f" stroke-linejoin="round">%s</text>' % (
            base, tr, OUT, OUT, 2 * ow, text))
        if i > 0:
            sides.append('<text %s %s fill="%s">%s</text>' % (base, tr, side, text))
    top = ('<text %s fill="url(#%s)" stroke="%s" stroke-width="%.1f" stroke-linejoin="round" paint-order="stroke">'
           '%s</text>' % (base, gid, OUT, edge, text))
    return defs, ''.join(outline) + ''.join(sides) + top


def pill(ids, cx, cy, w, h, text, size, top=('#FFF07A', '#FFAE00'), side='#B86E00'):
    gid = ids('pill')
    defs = bi.grad(gid, top[0], top[1])
    part = bi.fill('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" rx="%.1f" {A}/>' % (
        cx - w / 2, cy - h / 2, w, h, h / 2), 'url(#%s)' % gid, side,
        bi.gloss('M%.1f %.1f H%.1f' % (cx - w / 2 + 18, cy - h / 2 + 10, cx - w / 2 + 44), width=6, opacity=0.8))
    ldefs, lsvg = label(ids, text, cx, cy + size * 0.36, size, WHITE_TEXT, ow=4.5, edge=2.5, ex=(1.5, 3.5))
    return defs + ldefs, parts_svg([part]) + lsvg


def sparkles(*items):
    return ''.join(bi.sparkle(x, y, r) for x, y, r in items)


def rot_scale(cx, cy, k, rot):
    c, s = math.cos(math.radians(rot)), math.sin(math.radians(rot))

    def f(x, y):
        return cx + k * (x * c - y * s), cy + k * (x * s + y * c)
    return f


def outlined_path(d, color, width):
    return ('<path d="%s" fill="none" stroke="%s" stroke-width="%.1f" stroke-linecap="round" stroke-linejoin="round"/>'
            '<path d="%s" fill="none" stroke="%s" stroke-width="%.1f" stroke-linecap="round" stroke-linejoin="round"/>'
            % (d, OUT, width + 8, d, color, width))


# ------------------------------------------------------------------ jajka
EGG_SEGS = [((30, -60), (50, -12), (50, 14)), ((50, 44), (28, 62), (0, 62)),
            ((-28, 62), (-50, 44), (-50, 14)), ((-50, -12), (-30, -60), (0, -60))]

EGG_COLORS = {
    'pink': ('#FFD1E8', '#FF6FB5', '#B8336F', ['#FFF3A6', '#FFFFFF', '#FFF3A6']),
    'cyan': ('#D2F8FF', '#33BDF0', '#1C78AD', ['#FF8CC6', '#FFFFFF', '#FF8CC6']),
    'green': ('#E2FFC0', '#5CD23A', '#2B8A27', ['#FFF3A6', '#FFFFFF', '#FFF3A6']),
    'cream': ('#FFFEF6', '#FFD79A', '#C98A40', ['#FF8FB8', '#7FD8FF', '#B98CFF']),
    'premium': ('#F6DCFF', '#A24BFF', '#5A1FA8', None),
}


def egg(ids, cx, cy, k, rot, color):
    f = rot_scale(cx, cy, k, rot)
    x0, y0 = f(0, -60)
    d = 'M%.1f %.1f' % (x0, y0)
    for a, b, c in EGG_SEGS:
        d += ' C%.1f %.1f %.1f %.1f %.1f %.1f' % (f(*a) + f(*b) + f(*c))
    d += ' Z'
    light, dark, side, spots = EGG_COLORS[color]
    gid = ids('egg')
    defs = bi.grad(gid, light, dark)
    details = ''
    if spots:
        for (sx, sy, r), col in zip(((-22, -22, 11), (22, -2, 14), (-10, 30, 10)), spots):
            px, py = f(sx, sy)
            details += '<circle cx="%.1f" cy="%.1f" r="%.1f" fill="%s" stroke="%s" stroke-width="4"/>' % (
                px, py, r * k, col, OUT)
    else:  # premium: złoty zygzak i błysk
        pts = [f(x, y) for x, y in ((-49, 12), (-34, -2), (-18, 13), (-2, -2), (14, 13), (30, -2), (45, 11))]
        zig = 'M' + ' L'.join('%.1f %.1f' % p for p in pts)
        details += outlined_path(zig, '#FFD43B', 9 * k + 2)
        px, py = f(-14, -32)
        details += bi.sparkle(px, py, 13 * k + 3, '#FFFFFF')
    g0, g1 = f(-34, -18), f(-38, 6)
    details += bi.gloss('M%.1f %.1f L%.1f %.1f' % (g0 + g1), width=9 * k + 2)
    return defs, bi.fill('<path d="%s" {A}/>' % d, 'url(#%s)' % gid, side, details)


def eggs(ids, specs):
    defs, parts = '', []
    for spec in specs:
        dd, p = egg(ids, *spec)
        defs += dd
        parts.append(p)
    return defs, parts_svg(parts)


# ------------------------------------------------------------------ inne kształty
BOLT = [(70, 0), (18, 112), (56, 112), (30, 200), (110, 82), (70, 82), (98, 0)]


def bolt(ids, x, y, k, top=('#FFF6A0', '#FFC21A'), side='#C47A00'):
    gid = ids('bolt')
    pts = ' '.join('%.1f,%.1f' % (x + k * px, y + k * py) for px, py in BOLT)
    g0 = (x + k * 66, y + k * 18)
    g1 = (x + k * 40, y + k * 76)
    return bi.grad(gid, top[0], top[1]), bi.fill('<polygon points="%s" {A}/>' % pts, 'url(#%s)' % gid, side,
                                                 bi.gloss('M%.1f %.1f L%.1f %.1f' % (g0 + g1), width=8))


def auto_ring(ids, top=('#FFFFFF', '#D8FFCF'), side='#2B8A27'):
    gid = ids('ring')
    parts = bi.arc_arrow(128, 128, 106, 200, 312, 24, 'url(#%s)' % gid, side)
    parts += bi.arc_arrow(128, 128, 106, 20, 132, 24, 'url(#%s)' % gid, side)
    return bi.grad(gid, top[0], top[1]), parts_svg(parts)


def seal(ids, cx, cy, R, n=12):
    pts = [(cx + R * math.cos(2 * math.pi * i / n - math.pi / 2), cy + R * math.sin(2 * math.pi * i / n - math.pi / 2))
           for i in range(n)]
    bump = R * math.sin(math.pi / n) * 1.25
    d = 'M%.1f %.1f' % pts[0]
    for i in range(n):
        d += ' A%.1f %.1f 0 0 1 %.1f %.1f' % ((bump, bump) + pts[(i + 1) % n])
    d += ' Z'
    gid = ids('seal')
    check = 'M%.1f %.1f L%.1f %.1f L%.1f %.1f' % (cx - 38, cy + 2, cx - 10, cy + 30, cx + 40, cy - 28)
    details = ('<path d="%s" fill="none" stroke="%s" stroke-width="40" stroke-linecap="round" stroke-linejoin="round"/>'
               '<path d="%s" fill="none" stroke="#FFFFFF" stroke-width="24" stroke-linecap="round" '
               'stroke-linejoin="round"/>' % (check, OUT, check)
               + bi.gloss('M%.1f %.1f A%.1f %.1f 0 0 1 %.1f %.1f' % (cx - 66, cy - 22, R * 0.75, R * 0.75,
                                                                     cx - 26, cy - 64), width=10))
    return bi.grad(gid, '#8EE6FF', '#1A86E0'), bi.fill('<path d="%s" {A}/>' % d, 'url(#%s)' % gid, '#0D58A6', details)


def portal(ids):
    disc, ring = ids('disc'), ids('ring')
    defs = ('<radialGradient id="%s" cx="50%%" cy="50%%" r="50%%"><stop offset="0" stop-color="#FFFFFF"/>'
            '<stop offset="0.25" stop-color="#FFC6F2"/><stop offset="0.62" stop-color="#B15CFF"/>'
            '<stop offset="1" stop-color="#3A1AA8"/></radialGradient>' % disc
            + bi.grad(ring, '#FFA6EC', '#6F6BFF'))
    arms = ''
    for k, (col, w, op) in enumerate((('#FFFFFF', 8, 0.9), ('#9FF3FF', 6, 0.85), ('#FFFFFF', 8, 0.9))):
        a0 = k * 120
        pts = []
        for j in range(25):
            t = j / 24.0
            r = 76 - 66 * t
            a = math.radians(a0 + 280 * t)
            pts.append('%.1f %.1f' % (128 + r * math.cos(a), 128 + r * math.sin(a)))
        arms += ('<path d="M%s" fill="none" stroke="%s" stroke-width="%d" stroke-linecap="round" '
                 'stroke-linejoin="round" opacity="%s"/>' % (' L'.join(pts), col, w, op))
    arms += '<circle cx="128" cy="128" r="11" fill="#FFFFFF"/>'
    disc_part = bi.fill('<circle cx="128" cy="128" r="84" {A}/>', 'url(#%s)' % disc, '#2A1673', arms)
    ring_part = bi.stroke_line('M30 128 A98 98 0 1 1 226 128 A98 98 0 1 1 30 128', 'url(#%s)' % ring, '#3A2A9E', 30,
                               details=bi.gloss('M52 82 A92 92 0 0 1 96 40', width=8))
    return defs, parts_svg([disc_part, ring_part])


def chain_loop(ids, cx, cy, rx, ry):
    """Złoty łańcuch jako zamknięta pętla: pasek z obrysem i ogniwa na przemian płaskie i bokiem."""
    gid, lg = ids('chain'), ids('link')
    d = 'M%.1f %.1f A%.1f %.1f 0 1 1 %.1f %.1f A%.1f %.1f 0 1 1 %.1f %.1f Z' % (
        cx - rx, cy, rx, ry, cx + rx, cy, rx, ry, cx - rx, cy)
    side_on, face_on = '', ''
    n = 18
    for i in range(n):
        a = 2 * math.pi * i / n
        x, y = cx + rx * math.cos(a), cy + ry * math.sin(a)
        ang = math.degrees(math.atan2(ry * math.cos(a), -rx * math.sin(a)))
        tr = 'transform="rotate(%.1f %.1f %.1f)"' % (ang, x, y)
        if i % 2:
            side_on += ('<ellipse cx="%.1f" cy="%.1f" rx="8" ry="3.5" fill="#E08A00" stroke="%s" stroke-width="3" %s/>'
                        % (x, y, OUT, tr))
        else:
            face_on += ('<ellipse cx="%.1f" cy="%.1f" rx="12" ry="9" fill="url(#%s)" stroke="%s" stroke-width="3.5" %s/>'
                        '<ellipse cx="%.1f" cy="%.1f" rx="5" ry="2.2" fill="%s" %s/>' % (x, y, lg, OUT, tr, x, y, OUT, tr))
    defs = bi.grad(gid, '#FFD95A', '#E59400') + bi.grad(lg, '#FFF6B0', '#FFB400')
    return defs, bi.stroke_line(d, 'url(#%s)' % gid, '#CF8A00', 18, details=side_on + face_on)


def gem(ids, cx, cy):
    gid = ids('gem')
    pts = [(cx - 30, cy - 8), (cx - 17, cy - 24), (cx + 17, cy - 24), (cx + 30, cy - 8), (cx, cy + 30)]
    poly = ' '.join('%.1f,%.1f' % q for q in pts)
    facets = ('<path d="M%.1f %.1f H%.1f M%.1f %.1f L%.1f %.1f L%.1f %.1f M%.1f %.1f L%.1f %.1f L%.1f %.1f" '
              'fill="none" stroke="%s" stroke-width="3.5" stroke-linejoin="round" opacity="0.55"/>' % (
                  cx - 30, cy - 8, cx + 30, cx - 17, cy - 24, cx - 9, cy - 8, cx, cy + 30,
                  cx + 17, cy - 24, cx + 9, cy - 8, cx, cy + 30, OUT))
    return bi.grad(gid, '#EAFDFF', '#36BFF0'), bi.fill('<polygon points="%s" {A}/>' % poly, 'url(#%s)' % gid,
                                                       '#1A6FA6', facets + bi.sparkle(cx - 10, cy - 12, 7, '#FFFFFF'))


def watch(ids, cx, cy, rot, strap, strap_side):
    f = rot_scale(cx, cy, 1, rot)
    sg, cg, fg = ids('strap'), ids('case'), ids('face')
    defs = bi.grad(sg, strap[0], strap[1]) + bi.grad(cg, '#FFF08A', '#FFAA00') + bi.grad(fg, '#FFFFFF', '#DCE8FF')
    tr = 'transform="rotate(%s %s %s)"' % (rot, cx, cy)
    holes = ''
    for hy in (62, 76):
        hx, hyy = f(0, hy)
        holes += '<circle cx="%.1f" cy="%.1f" r="4" fill="%s"/>' % (hx, hyy, OUT)
    strap_part = bi.fill('<rect x="%.1f" y="%.1f" width="46" height="190" rx="16" %s {A}/>' % (cx - 23, cy - 95, tr),
                         'url(#%s)' % sg, strap_side, holes)
    crown = bi.fill('<rect x="%.1f" y="%.1f" width="16" height="20" rx="5" %s {A}/>' % (cx + 44, cy - 10, tr),
                    'url(#%s)' % cg, '#B06E00')
    ticks = ''
    for i in range(12):
        a = math.radians(i * 30 + rot)
        r0 = 26 if i % 3 else 22
        ticks += '<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="%s" stroke-width="4" stroke-linecap="round"/>' % (
            cx + r0 * math.sin(a), cy - r0 * math.cos(a), cx + 31 * math.sin(a), cy - 31 * math.cos(a), OUT)
    h1, h2 = f(0, -22), f(15, 8)
    face = ('<circle cx="%.1f" cy="%.1f" r="37" fill="url(#%s)" stroke="%s" stroke-width="5"/>' % (cx, cy, fg, OUT)
            + ticks
            + '<path d="M%.1f %.1f L%.1f %.1f L%.1f %.1f" fill="none" stroke="%s" stroke-width="6" '
              'stroke-linecap="round" stroke-linejoin="round"/>' % (h1 + (cx, cy) + h2 + (OUT,))
            + '<circle cx="%.1f" cy="%.1f" r="5" fill="#FF3D8B" stroke="%s" stroke-width="3"/>' % (cx, cy, OUT))
    case = bi.fill('<circle cx="%.1f" cy="%.1f" r="50" {A}/>' % (cx, cy), 'url(#%s)' % cg, '#B06E00',
                   face + bi.gloss('M%.1f %.1f A44 44 0 0 1 %.1f %.1f' % (cx - 42, cy - 12, cx - 14, cy - 42), width=7))
    return defs, parts_svg([strap_part, crown, case])


def gift(ids):
    """Prezent jak ikona Gift z gry, w kolorach Starter Packa."""
    box, lid, rib = ids('gbox'), ids('glid'), ids('grib')
    defs = bi.grad(box, '#FFA0C8', '#FF5A6E') + bi.grad(lid, '#FFC0DC', '#FF6F8C') + bi.grad(rib, '#FFF07A', '#FFC21A')
    bow_l = bi.fill('<ellipse cx="98" cy="70" rx="36" ry="23" transform="rotate(-24 98 70)" {A}/>', 'url(#%s)' % rib,
                    '#C98A00')
    bow_r = bi.fill('<ellipse cx="158" cy="70" rx="36" ry="23" transform="rotate(24 158 70)" {A}/>', 'url(#%s)' % rib,
                    '#C98A00')
    body = bi.fill('<rect x="48" y="120" width="160" height="108" rx="12" {A}/>', 'url(#%s)' % box, '#B0263E',
                   '<rect x="113" y="120" width="30" height="108" fill="url(#%s)" stroke="%s" stroke-width="5"/>' % (
                       rib, OUT) + bi.gloss('M64 146 L64 204', width=10))
    top = bi.fill('<rect x="36" y="88" width="184" height="46" rx="12" {A}/>', 'url(#%s)' % lid, '#B83050',
                  '<rect x="113" y="88" width="30" height="46" fill="url(#%s)" stroke="%s" stroke-width="5"/>' % (rib, OUT)
                  + '<circle cx="128" cy="84" r="16" fill="url(#%s)" stroke="%s" stroke-width="5"/>' % (rib, OUT))
    return defs, parts_svg([bow_l, bow_r, body, top])


PET_COLORS = {
    'Epic': (('#F0D6FF', '#B060FF'), '#6A26B8', ('#A646F5', '#6A1FC0'), '#3A0F78'),
    'Legendary': (('#FFF4B0', '#FFB21E'), '#C27200', ('#FFA21E', '#E06A00'), '#8A3A00'),
    'Mythic': (('#FFD3E2', '#FF4F86'), '#B0204E', ('#FF4A80', '#C8104A'), '#7A0A2C'),
}


def pet(ids, rarity):
    (b1, b2), side, (r1, r2), rside = PET_COLORS[rarity]
    bg_, rg = ids('pet'), ids('rib')
    defs = bi.grad(bg_, b1, b2) + bi.grad(rg, r1, r2)
    ear_l = bi.fill('<path d="M74 82 L60 24 L112 56 Z" {A}/>', 'url(#%s)' % bg_, side,
                    '<path d="M74 62 L68 40 L90 54 Z" fill="#FF9CC9" stroke="%s" stroke-width="3" '
                    'stroke-linejoin="round"/>' % OUT)
    ear_r = bi.fill('<path d="M182 82 L196 24 L144 56 Z" {A}/>', 'url(#%s)' % bg_, side,
                    '<path d="M182 62 L188 40 L166 54 Z" fill="#FF9CC9" stroke="%s" stroke-width="3" '
                    'stroke-linejoin="round"/>' % OUT)
    face = ''
    for ex_ in (100, 156):
        face += ('<ellipse cx="%d" cy="108" rx="17" ry="21" fill="#FFFFFF" stroke="%s" stroke-width="5"/>'
                 '<ellipse cx="%d" cy="112" rx="10" ry="13" fill="%s"/>'
                 '<circle cx="%d" cy="105" r="5" fill="#FFFFFF"/>' % (ex_, OUT, ex_ + 3, OUT, ex_ - 1))
    face += ('<ellipse cx="80" cy="136" rx="13" ry="8" fill="#FF6FB0" opacity="0.6"/>'
             '<ellipse cx="176" cy="136" rx="13" ry="8" fill="#FF6FB0" opacity="0.6"/>'
             '<path d="M118 134 Q128 146 138 134" fill="none" stroke="%s" stroke-width="5" stroke-linecap="round"/>' % OUT
             + bi.gloss('M70 92 A70 64 0 0 1 98 62', width=10))
    body = bi.fill('<ellipse cx="128" cy="118" rx="82" ry="72" {A}/>', 'url(#%s)' % bg_, side, face)
    feet = [bi.fill('<ellipse cx="%d" cy="186" rx="20" ry="13" {A}/>' % x, 'url(#%s)' % bg_, side) for x in (98, 158)]
    ribbon = bi.fill('<path d="M36 192 H220 L208 213 L220 234 H36 L48 213 Z" {A}/>', 'url(#%s)' % rg, rside)
    return defs, parts_svg([ear_l, ear_r, body] + feet + [ribbon])


# ------------------------------------------------------------------ ikony (w polu 256×256; środek 128,128)
def art_two_x_lp(ids):
    d1, star = borrowed(bi.icon_lp, 128, 104, 0.9, (122, 122))
    d2, lbl = label(ids, '2x', 128, 240, 96)
    return 'LP', d1 + d2, star + lbl + sparkles((32, 64, 15))


def art_auto_sell(ids):
    d1, ring = auto_ring(ids)
    d2, cash = borrowed(bi.icon_sell, 128, 132, 0.66, (122, 136))
    return 'Green', d1 + d2, ring + cash


def art_auto_click(ids):
    d1, ring = auto_ring(ids, ('#FFFFFF', '#FFF0A8'), '#C47A00')
    d2, cursor = borrowed(bi.icon_click, 130, 130, 0.66, (124, 120))
    return 'Yellow', d1 + d2, ring + cursor


def art_verified(ids):
    defs, part = seal(ids, 128, 126, 92)
    return 'Cyan', defs, parts_svg([part]) + sparkles((222, 46, 20), (34, 210, 15))


def art_pet_slots(ids):
    d1, paw = borrowed(bi.icon_pets, 128, 102, 0.86, (123, 128))
    d2, lbl = label(ids, '+2', 128, 242, 96)
    return 'Pink', d1 + d2, paw + lbl + sparkles((222, 52, 17))


def art_triple_open(ids):
    d1, e = eggs(ids, [(70, 128, 0.78, -14, 'pink'), (186, 128, 0.78, 14, 'green'), (128, 108, 0.98, 0, 'cyan')])
    d2, lbl = label(ids, 'x3', 128, 244, 90)
    return 'Premium', d1 + d2, e + lbl


def art_fast_open(ids):
    lines = ''.join(outlined_path(d, '#FFFFFF', 11) for d in ('M18 96 H52', 'M8 130 H46', 'M20 164 H50'))
    d1, e = egg(ids, 112, 132, 1.18, -10, 'cream')
    d2, b = bolt(ids, 150, 40, 0.86)
    return 'Red', d1 + d2, lines + parts_svg([e, b]) + sparkles((214, 214, 15))


def art_two_x_bag(ids):
    d1, bag = borrowed(bi.icon_bag, 128, 102, 0.86, (122, 126))
    d2, lbl = label(ids, '2x', 128, 242, 96, WHITE_TEXT)
    return 'Gold', d1 + d2, bag + lbl + sparkles((224, 58, 17))


def art_teleport(ids):
    defs, svg = portal(ids)
    return 'Portal', defs, svg + sparkles((222, 40, 18), (36, 216, 14), (226, 206, 12))


def art_double_chain(ids):
    d1, c1 = chain_loop(ids, 92, 100, 54, 70)
    cd, coin = bi.coin_part(92, 194, 24, ids('coin'))
    d2, c2 = chain_loop(ids, 164, 112, 54, 70)
    d3, g = gem(ids, 164, 210)
    return 'Gold', d1 + cd + d2 + d3, parts_svg([c1, coin, c2, g]) + sparkles((226, 40, 16), (30, 214, 13))


def art_double_wrist(ids):
    d1, w1 = watch(ids, 90, 124, -16, ('#FFB0DA', '#E8409A'), '#A0185E')
    d2, w2 = watch(ids, 170, 134, 14, ('#A8F5EA', '#18B8A8'), '#0F7268')
    return 'Pink', d1 + d2, w1 + w2 + sparkles((222, 40, 16))


def art_premium_egg1(ids):
    d1, e = egg(ids, 128, 122, 1.4, 0, 'premium')
    return 'Premium', d1, parts_svg([e]) + sparkles((210, 56, 20), (44, 196, 15), (214, 196, 12))


def art_premium_egg3(ids):
    d1, e = eggs(ids, [(70, 128, 0.78, -14, 'premium'), (186, 128, 0.78, 14, 'premium'),
                       (128, 108, 0.98, 0, 'premium')])
    d2, lbl = label(ids, 'x3', 128, 244, 90)
    return 'Premium', d1 + d2, e + lbl


def art_premium_egg10(ids):
    d1, e = eggs(ids, [(88, 86, 0.6, -10, 'premium'), (168, 86, 0.6, 10, 'premium'),
                       (56, 136, 0.64, -16, 'premium'), (200, 136, 0.64, 16, 'premium'),
                       (128, 122, 0.8, 0, 'premium')])
    d2, lbl = label(ids, 'x10', 128, 246, 88)
    return 'Premium', d1 + d2, e + lbl


def art_starter(ids):
    defs, svg = gift(ids)
    return 'Starter', defs, svg + sparkles((222, 52, 20), (34, 66, 15), (226, 208, 13))


def boost(ids, minutes, kind):
    if kind == 'LP':
        d1, main = label(ids, '2x', 84, 152, 104)
        bg = 'LP'
    else:
        d1, main = borrowed(bi.icon_sell, 86, 112, 0.58, (122, 136))
        bg = 'Green'
    d2, clock = borrowed(bi.icon_clock, 178, 98, 0.62, (122, 128))
    text = '1 HOUR' if minutes == 60 else '%d MIN' % minutes
    d3, p = pill(ids, 128, 214, 164, 46, text, 32)
    return bg, d1 + d2 + d3, clock + main + p  # zegar z tyłu, napis 2x albo banknoty z przodu


def art_sell_now(ids):
    d1, cash = borrowed(bi.icon_sell, 118, 140, 0.84, (122, 136))
    d2, b = bolt(ids, 158, 18, 0.62, ('#FFFFFF', '#A8ECFF'), '#2A7FC0')
    return 'Gold', d1 + d2, cash + parts_svg([b])


def direct_pet(ids, rarity):
    d1, body = pet(ids, rarity)
    size = 26 if rarity == 'Legendary' else 30
    d2, lbl = label(ids, rarity.upper(), 128, 213 + size * 0.36, size, WHITE_TEXT, ow=4.5, edge=2.5, ex=(1.5, 3.5))
    return rarity, d1 + d2, body + lbl + sparkles((222, 44, 17), (34, 52, 13))


PASSES = [
    ('TwoXLP', art_two_x_lp), ('AutoSell', art_auto_sell), ('AutoClick', art_auto_click),
    ('Verified', art_verified), ('PetSlots', art_pet_slots), ('TripleOpen', art_triple_open),
    ('FastOpen', art_fast_open), ('TwoXBag', art_two_x_bag), ('Teleport', art_teleport),
    ('DoubleChain', art_double_chain), ('DoubleWrist', art_double_wrist),
]

PRODUCTS = [
    ('PremiumEgg1', art_premium_egg1), ('PremiumEgg3', art_premium_egg3), ('PremiumEgg10', art_premium_egg10),
    ('StarterPack', art_starter),
    ('Boost2xLP5', lambda ids: boost(ids, 5, 'LP')), ('Boost2xLP15', lambda ids: boost(ids, 15, 'LP')),
    ('Boost2xLP60', lambda ids: boost(ids, 60, 'LP')),
    ('BoostAutoSell15', lambda ids: boost(ids, 15, 'AutoSell')),
    ('BoostAutoSell60', lambda ids: boost(ids, 60, 'AutoSell')),
    ('SellNow', art_sell_now),
    ('DirectPetEpic', lambda ids: direct_pet(ids, 'Epic')),
    ('DirectPetLegendary', lambda ids: direct_pet(ids, 'Legendary')),
    ('DirectPetMythic', lambda ids: direct_pet(ids, 'Mythic')),
]


# ------------------------------------------------------------------ płótno 512×512
def background(center, edge):
    mid = mix(center, edge, 0.5)
    dark = mix(edge, OUT, 0.22)
    rays = []
    n = 16
    for i in range(n):
        a0 = math.radians(i * 360.0 / n - 90)
        a1 = math.radians((i + 0.5) * 360.0 / n - 90)
        rays.append('<polygon points="256,256 %.1f,%.1f %.1f,%.1f"/>' % (
            256 + 420 * math.cos(a0), 256 + 420 * math.sin(a0), 256 + 420 * math.cos(a1), 256 + 420 * math.sin(a1)))
    defs = ('<radialGradient id="bg" cx="50%%" cy="46%%" r="72%%"><stop offset="0" stop-color="%s"/>'
            '<stop offset="0.5" stop-color="%s"/><stop offset="1" stop-color="%s"/></radialGradient>'
            '<radialGradient id="glow" cx="50%%" cy="50%%" r="50%%"><stop offset="0" stop-color="#FFFFFF" '
            'stop-opacity="0.8"/><stop offset="0.55" stop-color="#FFFFFF" stop-opacity="0.22"/>'
            '<stop offset="1" stop-color="#FFFFFF" stop-opacity="0"/></radialGradient>'
            '<radialGradient id="rayfade" cx="50%%" cy="50%%" r="50%%"><stop offset="0.15" stop-color="#FFFFFF" '
            'stop-opacity="0"/><stop offset="0.5" stop-color="#FFFFFF" stop-opacity="1"/>'
            '<stop offset="1" stop-color="#FFFFFF" stop-opacity="0.35"/></radialGradient>'
            '<mask id="raymask"><rect width="512" height="512" fill="url(#rayfade)"/></mask>' % (center, mid, dark))
    body = ('<rect width="512" height="512" fill="url(#bg)"/>'
            '<g fill="#FFFFFF" opacity="0.16" mask="url(#raymask)">%s</g>'
            '<circle cx="256" cy="252" r="232" fill="url(#glow)"/>' % ''.join(rays))
    return defs, body


def icon_svg(fn):
    ids = Ids()
    bg_key, defs, art = fn(ids)
    bdefs, bbody = background(*BG[bg_key])
    off = 256 - 128 * ART
    return ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="512" height="512">'
            '<defs>%s%s</defs>%s<g transform="translate(%.1f %.1f) scale(%s)">%s</g></svg>' % (
                bdefs, defs, bbody, off, off, ART, art))


def font_css():
    with open(FONT_FILE, 'rb') as fh:
        data = base64.b64encode(fh.read()).decode('ascii')
    return '@font-face{font-family:"%s";src:url(data:font/woff2;base64,%s) format("woff2");}' % (FONT, data)


def launch(p):
    try:
        return p.chromium.launch()
    except Exception:
        pass
    try:
        return p.chromium.launch(channel='chrome')
    except Exception:
        pass
    exe = shutil.which('google-chrome') or shutil.which('chrome') or shutil.which('chromium')
    return p.chromium.launch(executable_path=exe)


def page_html(css, inner, w, h):
    return ('<!doctype html><html><head><style>%s html,body{margin:0;background:transparent}</style></head><body>'
            '<div id="shot" style="position:relative;width:%dpx;height:%dpx">%s</div></body></html>' % (css, w, h, inner))


def preview_html(css, tiles):
    cards = []
    for i, (group, key, path) in enumerate(tiles):
        with open(path, 'rb') as fh:
            src = 'data:image/png;base64,' + base64.b64encode(fh.read()).decode('ascii')
        col, row = i % 6, i // 6
        cards.append('<div style="position:absolute;left:%dpx;top:%dpx;width:184px;text-align:center">'
                     '<img src="%s" style="width:160px;height:160px;border-radius:28px;display:block;margin:0 auto"/>'
                     '<div style="font:15px FredokaOne;color:#1E1233;margin-top:8px">%s</div></div>' % (
                         24 + col * 196, 24 + row * 214, src, key))
    return ''.join(cards)


def main():
    from playwright.sync_api import sync_playwright
    css = font_css()
    tiles = []
    with sync_playwright() as p:
        browser = launch(p)
        page = browser.new_page(viewport={'width': SIZE, 'height': SIZE}, device_scale_factor=1)
        for group, items in (('passes', PASSES), ('products', PRODUCTS)):
            os.makedirs(os.path.join(OUT_DIR, group), exist_ok=True)
            for key, fn in items:
                path = os.path.join(OUT_DIR, group, key + '.png')
                page.set_content(page_html(css, icon_svg(fn), SIZE, SIZE))
                page.evaluate("document.fonts.load('80px %s').then(() => document.fonts.ready)" % FONT)
                page.locator('#shot').screenshot(path=path)
                tiles.append((group, key, path))
        w, h = 24 * 2 + 6 * 196 - 12, 24 * 2 + 4 * 214 - 20
        page.set_viewport_size({'width': w, 'height': h})
        sheet = '<div style="position:absolute;inset:0;background:#F4F1FA"></div>' + preview_html(css, tiles)
        page.set_content(page_html(css, sheet, w, h))
        page.evaluate("document.fonts.load('15px %s').then(() => document.fonts.ready)" % FONT)
        page.locator('#shot').screenshot(path=os.path.join(OUT_DIR, 'preview.png'))
        browser.close()
    print('zapisano %d ikon w assets/shop-icons/ (passes, products) i podgląd preview.png' % len(tiles))


if __name__ == '__main__':
    main()
