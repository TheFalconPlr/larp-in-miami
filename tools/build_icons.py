"""Ikony gry: rysuje każdą ikonę jako SVG i składa arkusz PNG 1024×1024 (4×4 pola po 256 px).

Arkusz wgrywasz do Roblox raz (jeden obrazek = jedno ID), a gra wycina z niego ikony
(ImageRectOffset / ImageRectSize). Kolejność pól = ICONS poniżej; ta sama lista jest
w src/client/Ui/Icons.luau. Nowa ikona = nowe pole na końcu, potem ponowne wgranie arkusza.

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

O = '#2A1638'      # obrys (śliwkowy granat)
SW = 14            # grubość obrysu; połowa wychodzi na zewnątrz (paint-order: stroke)
CELL = 256
COLS = 4


def grad(gid, c1, c2, x1=0, y1=0, x2=0, y2=1):
    return ('<linearGradient id="%s" x1="%s" y1="%s" x2="%s" y2="%s">'
            '<stop offset="0" stop-color="%s"/><stop offset="1" stop-color="%s"/></linearGradient>'
            % (gid, x1, y1, x2, y2, c1, c2))


def shape(tag, attrs, fill, sw=SW):
    return '<%s %s fill="%s" stroke="%s" stroke-width="%s" stroke-linejoin="round" paint-order="stroke"/>' % (
        tag, attrs, fill, O, sw)


def line(d, color, width, outline=True, cap='round'):
    """Gruba linia z obrysem: najpierw szersza w kolorze obrysu, potem właściwa."""
    out = ''
    if outline:
        out += '<path d="%s" fill="none" stroke="%s" stroke-width="%s" stroke-linecap="%s" stroke-linejoin="round"/>' % (
            d, O, width + SW, cap)
    out += '<path d="%s" fill="none" stroke="%s" stroke-width="%s" stroke-linecap="%s" stroke-linejoin="round"/>' % (
        d, color, width, cap)
    return out


def gloss(d, width=10, opacity=0.75):
    return '<path d="%s" fill="none" stroke="#FFFFFF" stroke-width="%s" stroke-linecap="round" opacity="%s"/>' % (
        d, width, opacity)


def sparkle(cx, cy, r, color='#FFF6B0'):
    k = r * 0.28
    d = 'M%s %s Q%s %s %s %s Q%s %s %s %s Q%s %s %s %s Q%s %s %s %sZ' % (
        cx, cy - r, cx + k, cy - k, cx + r, cy, cx + k, cy + k, cx, cy + r,
        cx - k, cy + k, cx - r, cy, cx - k, cy - k, cx, cy - r)
    return shape('path', 'd="%s"' % d, color, sw=8)


def star_points(cx, cy, R, r, n=5, rot=-90):
    pts = []
    for i in range(2 * n):
        ang = math.radians(rot + i * 180 / n)
        rad = R if i % 2 == 0 else r
        pts.append('%.1f,%.1f' % (cx + rad * math.cos(ang), cy + rad * math.sin(ang)))
    return ' '.join(pts)


def dollar(cx, cy, s, color):
    """Znak dolara z linii (bez czcionek): kreska i litera S."""
    d_s = ('M{a} {b} C{c} {d} {e} {f} {g} {f} C{h} {f} {i} {j} {i} {k} '
           'C{i} {l} {m} {n} {m} {o} C{m} {p} {q} {r} {g} {r} C{s} {r} {t} {u} {v} {w}').format(
        a=cx + 26 * s, b=cy - 28 * s, c=cx + 18 * s, d=cy - 40 * s, e=cx + 8 * s, f=cy - 44 * s, g=cx - 2 * s,
        h=cx - 20 * s, i=cx - 30 * s, j=cy - 34 * s, k=cy - 22 * s, l=cy + 6 * s, m=cx + 30 * s, n=cy - 6 * s,
        o=cy + 24 * s, p=cy + 38 * s, q=cx + 18 * s, r=cy + 46 * s, s=cx - 14 * s, t=cx - 26 * s, u=cy + 40 * s,
        v=cx - 32 * s, w=cy + 28 * s)
    d_bar = 'M%s %s V%s' % (cx, cy - 62 * s, cy + 64 * s)
    out = '<path d="%s" fill="none" stroke="%s" stroke-width="%s" stroke-linecap="round"/>' % (d_bar, O, 26 * s)
    out += '<path d="%s" fill="none" stroke="%s" stroke-width="%s" stroke-linecap="round"/>' % (d_s, O, 30 * s)
    out += '<path d="%s" fill="none" stroke="%s" stroke-width="%s" stroke-linecap="round"/>' % (d_bar, color, 12 * s)
    out += '<path d="%s" fill="none" stroke="%s" stroke-width="%s" stroke-linecap="round"/>' % (d_s, color, 16 * s)
    return out


def coin(cx, cy, r, gid):
    s = r / 92.0
    out = '<defs>%s%s</defs>' % (grad(gid + 'a', '#FFE680', '#F5A300'), grad(gid + 'b', '#F9B90F', '#E08E00'))
    out += shape('circle', 'cx="%s" cy="%s" r="%s"' % (cx, cy + 12 * s, r), '#C26A00')
    out += shape('circle', 'cx="%s" cy="%s" r="%s"' % (cx, cy, r), 'url(#%sa)' % gid)
    out += '<circle cx="%s" cy="%s" r="%s" fill="url(#%sb)"/>' % (cx, cy, r * 0.7, gid)
    out += dollar(cx, cy, 0.95 * s, '#FFF3B0')
    out += gloss('M%s %s A%s %s 0 0 1 %s %s' % (cx - 58 * s, cy - 34 * s, 70 * s, 70 * s, cx - 14 * s, cy - 68 * s),
                 width=10 * s)
    return out


# ------------------------------------------------------------------ ikony
def icon_coin():
    return coin(128, 116, 92, 'coin')


def icon_lp():
    out = '<defs>%s</defs>' % grad('lpg', '#FF9AD5', '#FF3D8B')
    out += shape('polygon', 'points="%s"' % star_points(128, 140, 108, 50), '#C2185B')
    out += shape('polygon', 'points="%s"' % star_points(128, 128, 108, 50), 'url(#lpg)')
    out += gloss('M86 112 L104 96', width=12)
    out += sparkle(208, 52, 26)
    return out


def icon_bag():
    out = '<defs>%s%s%s</defs>' % (grad('bagg', '#FF8BCB', '#E0338A'), grad('bagf', '#FFB3DD', '#FF6FB5'),
                                   grad('bagc', '#FFE680', '#F5A300'))
    out += line('M86 112 C86 46 170 46 170 112', '#B0207A', 16)
    out += shape('path', 'd="M42 108 H214 L202 216 Q200 232 184 232 H72 Q56 232 54 216 Z"', 'url(#bagg)')
    out += shape('path', 'd="M42 108 H214 L206 150 Q128 176 50 150 Z"', 'url(#bagf)')
    out += shape('rect', 'x="110" y="140" width="36" height="30" rx="9"', 'url(#bagc)', sw=10)
    out += gloss('M64 176 L70 210', width=10)
    return out


def icon_sell():
    out = '<defs>%s%s</defs>' % (grad('sella', '#5BD27A', '#2E9E4F'), grad('sellb', '#9AF0A3', '#3DBA5C'))
    out += '<g transform="rotate(-14 118 118)">' + shape('rect', 'x="26" y="66" width="184" height="104" rx="18"',
                                                          'url(#sella)') + '</g>'
    out += '<g transform="rotate(7 134 146)">'
    out += shape('rect', 'x="40" y="94" width="188" height="106" rx="18"', 'url(#sellb)')
    out += '<rect x="54" y="108" width="160" height="78" rx="12" fill="none" stroke="#E9FFEA" stroke-width="6" opacity="0.8"/>'
    out += '<circle cx="134" cy="147" r="30" fill="#2E9E4F" stroke="%s" stroke-width="8"/>' % O
    out += dollar(134, 147, 0.42, '#E9FFEA')
    out += '</g>'
    out += coin(196, 196, 40, 'sellc')
    return out


def icon_upgrades():
    out = '<defs>%s</defs>' % grad('upg', '#C6FF6B', '#22B04A')
    out += shape('polygon', 'points="128,24 222,124 168,124 168,228 88,228 88,124 34,124"', 'url(#upg)')
    out += gloss('M126 54 L72 112', width=12)
    out += sparkle(214, 44, 24)
    out += sparkle(40, 202, 18)
    return out


def icon_click():
    out = '<defs>%s</defs>' % grad('clk', '#FFFFFF', '#CFE0FF')
    out += line('M66 70 L42 46', '#FFD23F', 10)
    out += line('M56 110 L26 110', '#FFD23F', 10)
    out += line('M106 60 L106 28', '#FFD23F', 10)
    out += shape('polygon', 'points="96,74 96,222 132,188 158,240 188,226 162,174 214,172"', 'url(#clk)')
    out += gloss('M110 106 L110 170', width=9, opacity=0.9)
    return out


def icon_aura():
    out = '<defs>%s%s</defs>' % (grad('aur', '#EBB0FF', '#7B2FF7'), grad('aui', '#FFFFFF', '#F2C9FF'))
    out += shape('path', 'd="M128 20 C144 64 200 90 200 156 C200 206 166 236 128 236 C90 236 56 208 56 160 '
                 'C56 120 82 100 92 70 C106 90 110 104 112 120 C122 84 134 58 128 20 Z"', 'url(#aur)')
    out += '<path d="M128 112 C140 136 164 150 164 180 C164 206 148 220 128 220 C108 220 92 206 92 182 ' \
           'C92 160 110 152 116 134 C122 142 124 148 126 154 C130 138 132 126 128 112 Z" fill="url(#aui)"/>'
    out += sparkle(206, 50, 22)
    out += sparkle(44, 72, 16)
    return out


def arrow_arc(cx, cy, R, a0, a1):
    """Łuk od kąta a0 do a1 (stopnie, zgodnie z ruchem wskazówek) i grot na końcu."""
    def pt(a, rad):
        return cx + rad * math.cos(math.radians(a)), cy + rad * math.sin(math.radians(a))
    x0, y0 = pt(a0, R)
    x1, y1 = pt(a1, R)
    large = 1 if (a1 - a0) % 360 > 180 else 0
    arc = 'M%.1f %.1f A%s %s 0 %d 1 %.1f %.1f' % (x0, y0, R, R, large, x1, y1)
    tip = pt(a1 + 16, R)
    w1 = pt(a1 - 2, R + 30)
    w2 = pt(a1 - 2, R - 30)
    head = '%.1f,%.1f %.1f,%.1f %.1f,%.1f' % (tip[0], tip[1], w1[0], w1[1], w2[0], w2[1])
    return arc, head


def icon_rebirth():
    out = '<defs>%s</defs>' % grad('reb', '#7FE7FF', '#1E8FEA')
    for a0, a1 in ((200, 318), (20, 138)):
        arc, head = arrow_arc(128, 128, 76, a0, a1)
        out += line(arc, 'url(#reb)', 26, cap='butt')
        out += shape('polygon', 'points="%s"' % head, 'url(#reb)')
    out += sparkle(128, 128, 22)
    return out


def icon_shop():
    out = '<defs>%s%s</defs>' % (grad('shp', '#FFE07A', '#FF9F1A'), grad('shb', '#FF8A5C', '#F0532E'))
    out += line('M92 104 C92 44 164 44 164 104', '#C24A1A', 14)
    out += shape('path', 'd="M48 96 H208 L216 222 Q216 236 202 236 H54 Q40 236 40 222 Z"', 'url(#shp)')
    out += shape('path', 'd="M48 96 H208 L210 130 H46 Z"', 'url(#shb)', sw=10)
    out += '<circle cx="92" cy="104" r="9" fill="%s"/><circle cx="164" cy="104" r="9" fill="%s"/>' % (O, O)
    out += gloss('M64 150 L60 210', width=10)
    return out


def icon_gift():
    out = '<defs>%s%s%s</defs>' % (grad('gfb', '#FF8FA8', '#E0335E'), grad('gfl', '#FFADC0', '#F0476E'),
                                   grad('gfr', '#FFF07A', '#FFC21A'))
    out += shape('ellipse', 'cx="98" cy="70" rx="34" ry="22" transform="rotate(-24 98 70)"', 'url(#gfr)')
    out += shape('ellipse', 'cx="158" cy="70" rx="34" ry="22" transform="rotate(24 158 70)"', 'url(#gfr)')
    out += shape('rect', 'x="50" y="120" width="156" height="110" rx="12"', 'url(#gfb)')
    out += shape('rect', 'x="36" y="88" width="184" height="46" rx="12"', 'url(#gfl)')
    out += shape('rect', 'x="112" y="88" width="32" height="142"', 'url(#gfr)', sw=10)
    out += shape('circle', 'cx="128" cy="84" r="16"', 'url(#gfr)', sw=10)
    out += gloss('M66 150 L66 208', width=10)
    return out


def icon_gear():
    out = '<defs>%s</defs>' % grad('gea', '#E3E9F5', '#8C99B8')
    pts = []
    teeth = 9
    for i in range(teeth * 4):
        ang = math.radians(i * 360 / (teeth * 4) - 90)
        rad = 106 if i % 4 in (1, 2) else 82
        pts.append('%.1f,%.1f' % (128 + rad * math.cos(ang), 128 + rad * math.sin(ang)))
    out += shape('polygon', 'points="%s"' % ' '.join(pts), 'url(#gea)')
    out += shape('circle', 'cx="128" cy="128" r="34"', '#F4F0FF', sw=12)
    out += gloss('M78 92 A60 60 0 0 1 108 70', width=10)
    return out


def icon_paw():
    out = '<defs>%s</defs>' % grad('paw', '#9BEBFF', '#2BA8E8')
    out += shape('path', 'd="M128 136 C164 136 196 168 196 196 C196 222 172 230 150 222 C138 218 118 218 106 222 '
                 'C84 230 60 222 60 196 C60 168 92 136 128 136 Z"', 'url(#paw)')
    for cx, cy, rot in ((66, 116, -20), (102, 70, -8), (154, 70, 8), (190, 116, 20)):
        out += shape('ellipse', 'cx="%s" cy="%s" rx="24" ry="30" transform="rotate(%s %s %s)"' % (cx, cy, rot, cx, cy),
                     'url(#paw)')
    out += gloss('M92 168 L84 186', width=10)
    return out


def icon_lock():
    out = '<defs>%s</defs>' % grad('lck', '#FFE680', '#F5A300')
    out += line('M86 118 V90 C86 40 170 40 170 90 V118', '#C4CCDD', 18, cap='butt')
    out += shape('rect', 'x="50" y="110" width="156" height="122" rx="26"', 'url(#lck)')
    out += '<circle cx="128" cy="160" r="16" fill="%s"/><rect x="120" y="164" width="16" height="36" rx="6" fill="%s"/>' % (
        O, O)
    out += gloss('M70 132 L70 200', width=10)
    return out


def icon_trophy():
    out = '<defs>%s</defs>' % grad('trp', '#FFE680', '#F59E00')
    out += line('M74 70 C24 70 30 140 86 140', '#F5B400', 14)
    out += line('M182 70 C232 70 226 140 170 140', '#F5B400', 14)
    out += shape('path', 'd="M70 44 H186 V104 C186 146 160 170 128 170 C96 170 70 146 70 104 Z"', 'url(#trp)')
    out += shape('rect', 'x="112" y="166" width="32" height="34" rx="6"', 'url(#trp)', sw=10)
    out += shape('rect', 'x="72" y="196" width="112" height="36" rx="12"', '#7B4BD6')
    out += sparkle(128, 96, 22)
    out += gloss('M88 62 L88 112', width=10)
    return out


def icon_clock():
    out = '<defs>%s</defs>' % grad('clc', '#FFFFFF', '#D8E6FF')
    out += shape('rect', 'x="112" y="22" width="32" height="26" rx="8"', '#FF7A59', sw=10)
    out += shape('circle', 'cx="128" cy="140" r="94"', 'url(#clc)')
    for i in range(12):
        ang = math.radians(i * 30)
        r0, r1 = (68, 82) if i % 3 else (60, 82)
        out += '<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="%s" stroke-width="8" stroke-linecap="round"/>' % (
            128 + r0 * math.sin(ang), 140 - r0 * math.cos(ang), 128 + r1 * math.sin(ang), 140 - r1 * math.cos(ang), O)
    out += '<path d="M128 140 V90" stroke="%s" stroke-width="12" stroke-linecap="round"/>' % O
    out += '<path d="M128 140 L164 160" stroke="#FF3D8B" stroke-width="10" stroke-linecap="round"/>'
    out += '<circle cx="128" cy="140" r="10" fill="%s"/>' % O
    return out


def icon_camera():
    out = '<defs>%s%s</defs>' % (grad('cam', '#8D8FFF', '#4B4FDB'), grad('cml', '#E6F3FF', '#7FB6FF'))
    out += shape('rect', 'x="84" y="56" width="70" height="40" rx="12"', '#3A3FC4', sw=12)
    out += shape('rect', 'x="30" y="82" width="196" height="138" rx="28"', 'url(#cam)')
    out += shape('circle', 'cx="128" cy="152" r="50"', 'url(#cml)')
    out += '<circle cx="128" cy="152" r="24" fill="%s"/>' % O
    out += '<circle cx="118" cy="142" r="8" fill="#FFFFFF" opacity="0.9"/>'
    out += shape('rect', 'x="182" y="98" width="28" height="18" rx="6"', '#FFD23F', sw=8)
    out += gloss('M50 114 L50 190', width=10)
    return out


ICONS = [
    ('Cash', icon_coin), ('LP', icon_lp), ('Bag', icon_bag), ('Sell', icon_sell),
    ('Upgrades', icon_upgrades), ('Click', icon_click), ('Aura', icon_aura), ('Rebirth', icon_rebirth),
    ('Shop', icon_shop), ('Gift', icon_gift), ('Settings', icon_gear), ('Pets', icon_paw),
    ('Lock', icon_lock), ('Trophy', icon_trophy), ('Clock', icon_clock), ('Camera', icon_camera),
]

SHADOW = ('<filter id="sh" x="-20%" y="-20%" width="140%" height="140%">'
          '<feDropShadow dx="0" dy="7" stdDeviation="0" flood-color="#2A1638" flood-opacity="0.28"/></filter>')


def svg_for(fn):
    return ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" width="256" height="256">'
            '<defs>%s</defs><g filter="url(#sh)">%s</g></svg>' % (SHADOW, fn()))


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
