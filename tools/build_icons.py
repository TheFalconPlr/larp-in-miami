"""Ikony gry w stylu 3D „naklejki”: kolorowa góra, ciemniejszy bok (wytłoczenie), gruby ciemny obrys.

Rysuje każdą ikonę jako SVG i składa arkusz PNG 1024×1024 (4×4 pola po 256 px). Arkusz wgrywasz
do Roblox raz (jeden obrazek = jedno ID), a gra wycina z niego ikony (ImageRectOffset / ImageRectSize).
Kolejność pól = ICONS poniżej; ta sama lista jest w src/client/Ui/Icons.luau.
Nowa ikona = nowe pole na końcu, potem ponowne wgranie arkusza.

Uruchom z głównego folderu projektu:  python tools/build_icons.py
Wymaga: pip install playwright  oraz  python -m playwright install chromium
Wynik: assets/icons/larp-icons.png i assets/icons/svg/<nazwa>.svg
"""
import math
import os

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, '..'))
OUT_DIR = os.path.join(ROOT, 'assets', 'icons')
SVG_DIR = os.path.join(OUT_DIR, 'svg')

OUT = '#1E1233'      # obrys
OW = 9               # grubość obrysu na zewnątrz
EDGE = 5             # linia między górą a bokiem
EX = (5.0, 12.0)     # kierunek i głębokość wytłoczenia (w prawo i w dół)
STEPS = 8
CELL = 256
COLS = 4


class Part:
    """Element ikony z wytłoczeniem.

    kind='fill': geom to znacznik SVG z miejscem {A} na atrybuty, np. '<circle cx="1" cy="2" r="3" {A}/>'.
    kind='line': geom to ścieżka d, rysowana grubą linią o szerokości width.
    top: kolor albo 'url(#id)', side: kolor boku. details: znaczniki rysowane na górze tej części.
    """

    def __init__(self, kind, geom, top, side, width=0, cap='round', details=''):
        self.kind = kind
        self.geom = geom
        self.top = top
        self.side = side
        self.width = width
        self.cap = cap
        self.details = details


def fill(geom, top, side, details=''):
    return Part('fill', geom, top, side, details=details)


def stroke_line(d, top, side, width, cap='round', details=''):
    return Part('line', d, top, side, width=width, cap=cap, details=details)


def grad(gid, c1, c2, x1=0, y1=0, x2=0, y2=1):
    return ('<linearGradient id="%s" x1="%s" y1="%s" x2="%s" y2="%s">'
            '<stop offset="0" stop-color="%s"/><stop offset="1" stop-color="%s"/></linearGradient>'
            % (gid, x1, y1, x2, y2, c1, c2))


def shift(markup, t):
    if t == 0:
        return markup
    return '<g transform="translate(%.2f %.2f)">%s</g>' % (EX[0] * t, EX[1] * t, markup)


def render_part(p):
    outline, side = [], []
    for i in range(STEPS + 1):
        t = i / float(STEPS)
        if p.kind == 'fill':
            outline.append(shift(p.geom.format(
                A='fill="%s" stroke="%s" stroke-width="%d" stroke-linejoin="round"' % (OUT, OUT, 2 * OW)), t))
            if i > 0:
                side.append(shift(p.geom.format(A='fill="%s"' % p.side), t))
        else:
            outline.append(shift('<path d="%s" fill="none" stroke="%s" stroke-width="%d" stroke-linecap="%s" '
                                 'stroke-linejoin="round"/>' % (p.geom, OUT, p.width + 2 * OW, p.cap), t))
            if i > 0:
                side.append(shift('<path d="%s" fill="none" stroke="%s" stroke-width="%d" stroke-linecap="%s" '
                                  'stroke-linejoin="round"/>' % (p.geom, p.side, p.width, p.cap), t))
    if p.kind == 'fill':
        top = p.geom.format(A='fill="%s" stroke="%s" stroke-width="%d" stroke-linejoin="round"' % (p.top, OUT, EDGE))
    else:
        top = ('<path d="%s" fill="none" stroke="%s" stroke-width="%d" stroke-linecap="%s" stroke-linejoin="round"/>'
               '<path d="%s" fill="none" stroke="%s" stroke-width="%d" stroke-linecap="%s" stroke-linejoin="round"/>'
               % (p.geom, OUT, p.width + EDGE, p.cap, p.geom, p.top, p.width - EDGE, p.cap))
    return ''.join(outline) + ''.join(side) + top + p.details


def gloss(d, width=10, opacity=0.7):
    return '<path d="%s" fill="none" stroke="#FFFFFF" stroke-width="%s" stroke-linecap="round" opacity="%s"/>' % (
        d, width, opacity)


def outlined(markup_fn, color, width):
    """Szczegół z obrysem: najpierw szerszy w kolorze obrysu, potem właściwy."""
    return markup_fn(OUT, width + 8) + markup_fn(color, width)


def sparkle(cx, cy, r, color='#FFF6B0'):
    k = r * 0.28
    d = 'M%s %s Q%s %s %s %s Q%s %s %s %s Q%s %s %s %s Q%s %s %s %sZ' % (
        cx, cy - r, cx + k, cy - k, cx + r, cy, cx + k, cy + k, cx, cy + r,
        cx - k, cy + k, cx - r, cy, cx - k, cy - k, cx, cy - r)
    return '<path d="%s" fill="%s" stroke="%s" stroke-width="6" stroke-linejoin="round" paint-order="stroke"/>' % (
        d, color, OUT)


def star_points(cx, cy, R, r, n=5, rot=-90):
    pts = []
    for i in range(2 * n):
        ang = math.radians(rot + i * 180 / n)
        rad = R if i % 2 == 0 else r
        pts.append('%.1f,%.1f' % (cx + rad * math.cos(ang), cy + rad * math.sin(ang)))
    return ' '.join(pts)


def dollar(cx, cy, s, color):
    """Znak dolara z linii (bez czcionek): kreska i litera S z obrysem."""
    d_s = ('M{a} {b} C{c} {d} {e} {f} {g} {f} C{h} {f} {i} {j} {i} {k} '
           'C{i} {l} {m} {n} {m} {o} C{m} {p} {q} {r} {g} {r} C{s} {r} {t} {u} {v} {w}').format(
        a=cx + 26 * s, b=cy - 28 * s, c=cx + 18 * s, d=cy - 40 * s, e=cx + 8 * s, f=cy - 44 * s, g=cx - 2 * s,
        h=cx - 20 * s, i=cx - 30 * s, j=cy - 34 * s, k=cy - 22 * s, l=cy + 6 * s, m=cx + 30 * s, n=cy - 6 * s,
        o=cy + 24 * s, p=cy + 38 * s, q=cx + 18 * s, r=cy + 46 * s, s=cx - 14 * s, t=cx - 26 * s, u=cy + 40 * s,
        v=cx - 32 * s, w=cy + 28 * s)
    d_bar = 'M%s %s V%s' % (cx, cy - 62 * s, cy + 64 * s)
    out = ''
    for col, w_bar, w_s in ((OUT, 26 * s, 30 * s), (color, 12 * s, 16 * s)):
        out += '<path d="%s" fill="none" stroke="%s" stroke-width="%.1f" stroke-linecap="round"/>' % (d_bar, col, w_bar)
        out += '<path d="%s" fill="none" stroke="%s" stroke-width="%.1f" stroke-linecap="round"/>' % (d_s, col, w_s)
    return out


def coin_part(cx, cy, r, gid):
    s = r / 92.0
    details = '<circle cx="%s" cy="%s" r="%.1f" fill="url(#%sb)" stroke="#E08A00" stroke-width="%.1f"/>' % (
        cx, cy, r * 0.72, gid, 5 * s)
    details += dollar(cx, cy, 0.95 * s, '#FFF6C4')
    details += gloss('M%.1f %.1f A%.1f %.1f 0 0 1 %.1f %.1f' % (
        cx - 62 * s, cy - 30 * s, 72 * s, 72 * s, cx - 20 * s, cy - 70 * s), width=11 * s)
    defs = grad(gid + 'a', '#FFE97F', '#FFB000') + grad(gid + 'b', '#FFC52E', '#F2A100')
    return defs, fill('<circle cx="%s" cy="%s" r="%s" {A}/>' % (cx, cy, r), 'url(#%sa)' % gid, '#C27200', details)


# ------------------------------------------------------------------ ikony: (defs, [części], dodatki)
def icon_cash():
    defs, coin = coin_part(122, 114, 92, 'cash')
    return defs, [coin], ''


def icon_lp():
    defs = grad('lpg', '#FFB0DD', '#FF3D8B')
    star = fill('<polygon points="%s" {A}/>' % star_points(122, 122, 104, 50), 'url(#lpg)', '#B5175A',
                gloss('M84 104 L100 90', width=12))
    return defs, [star], sparkle(210, 46, 24)


def icon_bag():
    defs = grad('bagg', '#FFA8D6', '#E8409A') + grad('bagc', '#FFE97F', '#FFB000')
    handle = stroke_line('M84 104 C84 36 160 36 160 104', '#F05AA8', '#A0185E', 22)
    details = ('<path d="M40 136 Q122 160 204 136" fill="none" stroke="%s" stroke-width="5"/>' % OUT
               + '<rect x="106" y="130" width="34" height="30" rx="9" fill="url(#bagc)" stroke="%s" stroke-width="5"/>' % OUT
               + gloss('M62 160 L68 196', width=10))
    body = fill('<path d="M36 98 H208 L196 202 Q194 216 180 216 H64 Q50 216 48 202 Z" {A}/>',
                'url(#bagg)', '#A8186A', details)
    return defs, [handle, body], ''


def icon_sell():
    defs = grad('sella', '#6FDD8A', '#2E9E4F') + grad('sellb', '#B2F7BA', '#45C266')
    coin_defs, coin = coin_part(186, 178, 40, 'sellc')
    back = fill('<rect x="20" y="58" width="180" height="100" rx="18" transform="rotate(-12 110 108)" {A}/>',
                'url(#sella)', '#1F7038')
    front_details = ('<g transform="rotate(6 128 138)">'
                     '<rect x="50" y="102" width="156" height="72" rx="12" fill="none" stroke="#E9FFEA" '
                     'stroke-width="5" opacity="0.85"/>'
                     '<circle cx="128" cy="138" r="27" fill="#2E9E4F" stroke="%s" stroke-width="5"/>' % OUT
                     + dollar(128, 138, 0.38, '#E9FFEA') + '</g>')
    front = fill('<rect x="36" y="88" width="184" height="100" rx="18" transform="rotate(6 128 138)" {A}/>',
                 'url(#sellb)', '#24834A', front_details)
    return defs + coin_defs, [back, front, coin], ''


def icon_upgrades():
    defs = grad('upg', '#8DF77A', '#27AE47')
    lower = fill('<polygon points="34,176 122,98 210,176 210,214 122,136 34,214" {A}/>', 'url(#upg)', '#1B8038')
    upper = fill('<polygon points="34,104 122,26 210,104 210,142 122,64 34,142" {A}/>', 'url(#upg)', '#1B8038',
                 gloss('M48 104 L118 42', width=9, opacity=0.65))
    return defs, [lower, upper], ''


def icon_click():
    defs = grad('clk', '#FFFFFF', '#E4EEFF')
    cursor = fill('<polygon points="58,26 58,192 100,154 130,214 164,198 134,138 190,134" {A}/>', 'url(#clk)',
                  '#7DB9E8')
    return defs, [cursor], ''


def icon_aura():
    defs = grad('aur', '#EDB8FF', '#8A3CF5') + grad('aui', '#FFFFFF', '#F2C9FF')
    inner = ('<path d="M122 108 C134 132 158 146 158 176 C158 202 142 214 122 214 C102 214 86 202 86 178 '
             'C86 156 104 148 110 130 C116 138 118 144 120 150 C124 134 126 122 122 108 Z" fill="url(#aui)" '
             'stroke="%s" stroke-width="4"/>' % OUT)
    flame = fill('<path d="M122 20 C138 64 194 88 194 152 C194 200 160 226 122 226 C84 226 50 200 50 154 '
                 'C50 116 76 98 86 68 C100 88 104 102 106 118 C116 82 128 56 122 20 Z" {A}/>',
                 'url(#aur)', '#5320A8', inner)
    return defs, [flame], sparkle(210, 48, 22) + sparkle(36, 74, 15)


def arc_arrow(cx, cy, R, a0, a1, width, top, side):
    """Strzałka po łuku jako jeden kształt: gruby łuk od a0 do a1 i grot na końcu."""
    def pt(a, rad):
        return cx + rad * math.cos(math.radians(a)), cy + rad * math.sin(math.radians(a))
    ro, ri = R + width / 2.0, R - width / 2.0
    o0, o1 = pt(a0, ro), pt(a1, ro)
    i0, i1 = pt(a0, ri), pt(a1, ri)
    w_out, w_in = pt(a1, R + width * 1.15), pt(a1, R - width * 1.15)
    tip = pt(a1 + 28, R)
    d = ('M%.1f %.1f A%.1f %.1f 0 0 1 %.1f %.1f L%.1f %.1f L%.1f %.1f L%.1f %.1f L%.1f %.1f '
         'A%.1f %.1f 0 0 0 %.1f %.1f Z') % (
        o0[0], o0[1], ro, ro, o1[0], o1[1], w_out[0], w_out[1], tip[0], tip[1], w_in[0], w_in[1],
        i1[0], i1[1], ri, ri, i0[0], i0[1])
    return [fill('<path d="%s" {A}/>' % d, top, side)]


def icon_rebirth():
    defs = grad('rbp', '#FFA3C3', '#F0558C') + grad('rbb', '#E2F4FF', '#9ED4FF')
    blue = arc_arrow(122, 118, 68, 30, 140, 36, 'url(#rbb)', '#6AA9DA')
    pink = arc_arrow(122, 118, 68, 210, 320, 36, 'url(#rbp)', '#B83468')
    return defs, blue + pink, ''


def icon_shop():
    defs = grad('shp', '#FFE58A', '#FF9F1A')
    handles = stroke_line('M88 100 C88 40 156 40 156 100', '#D0601F', '#8A3A10', 16)
    details = ('<path d="M44 92 H200 L203 124 H41 Z" fill="#FF7A4C" stroke="%s" stroke-width="5" '
               'stroke-linejoin="round"/>' % OUT
               + '<circle cx="88" cy="104" r="8" fill="%s"/><circle cx="156" cy="104" r="8" fill="%s"/>' % (OUT, OUT)
               + gloss('M60 146 L56 196', width=10))
    body = fill('<path d="M44 92 H200 L210 210 Q210 222 198 222 H46 Q34 222 34 210 Z" {A}/>', 'url(#shp)',
                '#C46A10', details)
    return defs, [handles, body], ''


def icon_gift():
    defs = grad('gfb', '#FF8FA8', '#E0335E') + grad('gfl', '#FFADC0', '#F0476E') + grad('gfr', '#FFF07A', '#FFC21A')
    bow_l = fill('<ellipse cx="94" cy="66" rx="34" ry="22" transform="rotate(-24 94 66)" {A}/>', 'url(#gfr)', '#C98A00')
    bow_r = fill('<ellipse cx="152" cy="66" rx="34" ry="22" transform="rotate(24 152 66)" {A}/>', 'url(#gfr)', '#C98A00')
    box = fill('<rect x="44" y="114" width="156" height="104" rx="12" {A}/>', 'url(#gfb)', '#A8203F',
               '<rect x="108" y="114" width="30" height="104" fill="url(#gfr)" stroke="%s" stroke-width="5"/>' % OUT
               + gloss('M60 140 L60 196', width=10))
    lid = fill('<rect x="32" y="84" width="182" height="44" rx="12" {A}/>', 'url(#gfl)', '#B02A50',
               '<rect x="108" y="84" width="30" height="44" fill="url(#gfr)" stroke="%s" stroke-width="5"/>' % OUT
               + '<circle cx="123" cy="80" r="15" fill="url(#gfr)" stroke="%s" stroke-width="5"/>' % OUT)
    return defs, [bow_l, bow_r, box, lid], ''


def icon_settings():
    defs = grad('gea', '#EEF2FA', '#A9B4CC')
    pts = []
    teeth = 9
    for i in range(teeth * 4):
        ang = math.radians(i * 360 / (teeth * 4) - 90)
        rad = 102 if i % 4 in (1, 2) else 80
        pts.append('%.1f,%.1f' % (122 + rad * math.cos(ang), 120 + rad * math.sin(ang)))
    details = ('<circle cx="122" cy="120" r="34" fill="#F4F0FF" stroke="%s" stroke-width="6"/>' % OUT
               + gloss('M74 84 A58 58 0 0 1 104 62', width=10))
    gear = fill('<polygon points="%s" {A}/>' % ' '.join(pts), 'url(#gea)', '#6E7896', details)
    return defs, [gear], ''


def icon_pets():
    defs = grad('paw', '#B0F0FF', '#35AEEA')
    parts = []
    for cx, cy, rot in ((60, 108, -20), (98, 64, -8), (148, 64, 8), (186, 108, 20)):
        parts.append(fill('<ellipse cx="%s" cy="%s" rx="23" ry="29" transform="rotate(%s %s %s)" {A}/>' % (
            cx, cy, rot, cx, cy), 'url(#paw)', '#1E78B0'))
    parts.append(fill('<path d="M123 128 C158 128 190 160 190 188 C190 214 166 222 144 214 C132 210 114 210 102 214 '
                      'C80 222 56 214 56 188 C56 160 88 128 123 128 Z" {A}/>', 'url(#paw)', '#1E78B0',
                      gloss('M88 160 L80 178', width=10)))
    return defs, parts, ''


def icon_lock():
    defs = grad('lck', '#FFE97F', '#FFB000')
    shackle = stroke_line('M82 112 V86 C82 36 162 36 162 86 V112', '#DCE3F0', '#8E98B0', 22, cap='butt')
    body = fill('<rect x="46" y="104" width="152" height="116" rx="26" {A}/>', 'url(#lck)', '#C47A00',
                '<circle cx="122" cy="152" r="16" fill="%s"/><rect x="114" y="156" width="16" height="36" rx="6" '
                'fill="%s"/>' % (OUT, OUT) + gloss('M66 126 L66 194', width=10))
    return defs, [shackle, body], ''


def icon_trophy():
    defs = grad('trp', '#FFE97F', '#FFA800') + grad('trb', '#A784F5', '#6A3FD0')
    handle_l = stroke_line('M70 66 C22 66 28 134 82 134', '#FFC21A', '#C47A00', 16)
    handle_r = stroke_line('M174 66 C222 66 216 134 162 134', '#FFC21A', '#C47A00', 16)
    cup = fill('<path d="M66 40 H178 V98 C178 140 152 162 122 162 C92 162 66 140 66 98 Z" {A}/>', 'url(#trp)',
               '#C47A00', gloss('M84 58 L84 106', width=10))
    stem = fill('<rect x="106" y="158" width="32" height="30" rx="6" {A}/>', 'url(#trp)', '#C47A00')
    base = fill('<rect x="66" y="184" width="112" height="36" rx="12" {A}/>', 'url(#trb)', '#4A2A99')
    return defs, [handle_l, handle_r, cup, stem, base], sparkle(122, 92, 22)


def icon_clock():
    defs = grad('clc', '#FFFFFF', '#E0EAFF')
    button = fill('<rect x="106" y="18" width="32" height="26" rx="8" {A}/>', '#FF7A59', '#C24A2E')
    ticks = ''
    for i in range(12):
        ang = math.radians(i * 30)
        r0, r1 = (64, 76) if i % 3 else (56, 76)
        ticks += '<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="%s" stroke-width="7" stroke-linecap="round"/>' % (
            122 + r0 * math.sin(ang), 132 - r0 * math.cos(ang), 122 + r1 * math.sin(ang), 132 - r1 * math.cos(ang), OUT)
    hands = ('<path d="M122 132 V86" stroke="%s" stroke-width="11" stroke-linecap="round"/>' % OUT
             + '<path d="M122 132 L156 152" stroke="#FF3D8B" stroke-width="9" stroke-linecap="round"/>'
             + '<circle cx="122" cy="132" r="9" fill="%s"/>' % OUT)
    face = fill('<circle cx="122" cy="132" r="90" {A}/>', 'url(#clc)', '#9FB0D0', ticks + hands)
    return defs, [button, face], ''


def icon_camera():
    defs = grad('cam', '#9A9CFF', '#4B4FDB') + grad('cml', '#EAF5FF', '#86BBFF')
    bump = fill('<rect x="80" y="50" width="70" height="40" rx="12" {A}/>', '#5A5EE8', '#2E3199')
    lens = ('<circle cx="122" cy="146" r="48" fill="url(#cml)" stroke="%s" stroke-width="7"/>' % OUT
            + '<circle cx="122" cy="146" r="22" fill="%s"/>' % OUT
            + '<circle cx="112" cy="136" r="8" fill="#FFFFFF" opacity="0.9"/>'
            + '<rect x="176" y="92" width="28" height="18" rx="6" fill="#FFD23F" stroke="%s" stroke-width="5"/>' % OUT
            + gloss('M44 108 L44 180', width=10))
    body = fill('<rect x="26" y="76" width="194" height="136" rx="28" {A}/>', 'url(#cam)', '#2E3199', lens)
    return defs, [bump, body], ''


ICONS = [
    ('Cash', icon_cash), ('LP', icon_lp), ('Bag', icon_bag), ('Sell', icon_sell),
    ('Upgrades', icon_upgrades), ('Click', icon_click), ('Aura', icon_aura), ('Rebirth', icon_rebirth),
    ('Shop', icon_shop), ('Gift', icon_gift), ('Settings', icon_settings), ('Pets', icon_pets),
    ('Lock', icon_lock), ('Trophy', icon_trophy), ('Clock', icon_clock), ('Camera', icon_camera),
]


def svg_for(fn):
    defs, parts, extra = fn()
    body = ''.join(render_part(p) for p in parts) + extra
    return ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" width="256" height="256">'
            '<defs>%s</defs>%s</svg>' % (defs, body))


def main():
    os.makedirs(SVG_DIR, exist_ok=True)
    cells = []
    for i, (name, fn) in enumerate(ICONS):
        svg = svg_for(fn)
        with open(os.path.join(SVG_DIR, name.lower() + '.svg'), 'w', encoding='utf-8') as fh:
            fh.write(svg)
        col, row = i % COLS, i // COLS
        cells.append('<div style="position:absolute;left:%dpx;top:%dpx;width:256px;height:256px">%s</div>' % (
            col * CELL, row * CELL, svg))
    html = ('<!doctype html><html><head><style>html,body{margin:0;background:transparent}</style></head><body>'
            '<div id="sheet" style="position:relative;width:1024px;height:1024px">%s</div></body></html>' % ''.join(cells))
    from playwright.sync_api import sync_playwright
    with sync_playwright() as p:
        browser = p.chromium.launch()
        page = browser.new_page(viewport={'width': 1024, 'height': 1024}, device_scale_factor=1)
        page.set_content(html)
        page.locator('#sheet').screenshot(path=os.path.join(OUT_DIR, 'larp-icons.png'), omit_background=True)
        browser.close()
    print('zapisano assets/icons/larp-icons.png (%d ikon) i assets/icons/svg/' % len(ICONS))


if __name__ == '__main__':
    main()
