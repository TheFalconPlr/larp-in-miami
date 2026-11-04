"""Larp in Miami — model ekonomii + symulacja gracza (backtest progresji), v2.

Waluty: LP (zbierane do Bag, sprzedawane na Sell) -> L$ (wydawane).
Warstwy mnożników (wewnątrz warstwy dodajemy, między warstwami mnożymy):
  LP za klik      = Clout x MnożnikStrefy x Ubrania x Rebirth x Robux
  LP za aktywność = Clout x Baza x Tier x Ubrania x Rebirth x Robux
  L$ przy Sell    = LP x Pety
"""
import math, random, statistics, copy, json

NICE = [1, 1.2, 1.5, 2, 2.5, 3, 4, 5, 6, 7.5, 8, 10]


def nice(x):
    """Zaokrąglenie do czytelnych liczb (1, 1.2, 1.5, 2, 2.5, 3, 4, 5, 6, 7.5, 8 x 10^n)."""
    if x <= 0:
        return 0
    e = math.floor(math.log10(x))
    m = x / 10 ** e
    best = min(NICE, key=lambda n: abs(math.log(n / m)))
    v = best * 10 ** e
    return int(round(v)) if v >= 1 else round(v, 4)


RARS = ['C', 'U', 'R', 'E', 'L', 'M']
RAR_NAME = {'C': 'Common', 'U': 'Uncommon', 'R': 'Rare', 'E': 'Epic', 'L': 'Legendary', 'M': 'Mythic'}
CATS = ['hair', 'glasses', 'chain', 'watch', 'shirt', 'pants', 'shoes']
CAT_PL = {'hair': 'Włosy', 'glasses': 'Okulary', 'chain': 'Łańcuch', 'watch': 'Zegarek',
          'shirt': 'Koszulka', 'pants': 'Spodnie', 'shoes': 'Buty'}


def default_cfg():
    return dict(
        K=4.0,                 # kliknięcia/s aktywnego gracza (ręcznie)
        AUTO_K=3.0,            # Auto-Click (gamepass)
        TELEPORT=2.0,          # darmowy teleport na Sell (s)
        WALK={1: 5, 2: 10, 3: 15, 4: 25, 5: 35},  # powrót pieszo ze Sell do strefy (s)
        REB_SPEED=0.05,        # +5% szybkości chodzenia za każdy poziom Rebirth
        OPEN_TIME=3.0,         # animacja otwarcia jajka/boxa (s)
        FAST_OPEN=1.0 / 3,     # Fast Open + Triple Open (s na sztukę)
        HATCH_H=1200.0,        # 1. przejście: jajko/box musi się zwrócić (z czasem otwierania) w 20 min
        HATCH_H_REB=2 * 3600.0,  # po Rebirthie (polowanie na rzadkie): w 2 h — pety/ubrania zostają na zawsze
        # mnożnik kliknięcia zależny od strefy, w której stoisz (~25% bazowej aktywności strefy)
        ZONE_CLICK={1: 1, 2: 1.5, 3: 5, 4: 8, 5: 250},
        # Clout = poziom „wpływów”: LP za klik i baza dla wszystkich aktywności
        CLOUT_C0=25.0, CLOUT_G=1.30, CLOUT_MAX=150,
        # Bag = pojemność na LP
        BAG0=100.0, BAG_G=2.5, BAG_COSTF=0.15, BAG_CG=3.15, BAG_MAX=40,
        ZONE_COST={2: 2500.0, 3: 2e5, 4: 5e6, 5: 6e8},
        ACT={
            'car': dict(zone=2, base=110, dur=8, over=3, tiers=[1, 1.5, 2.5, 4, 6]),
            # wywiad: 45 s (3 pytania w spokojnym tempie); baza 3000 = dawne 1800 × (45+5)/(25+5),
            # więc LP na minutę zostają takie same jak przy 25 s
            'interview': dict(zone=3, base=3000, dur=45, over=5, tiers=[1], viral=1.5),
            'yacht': dict(zone=4, base=6000, dur=45, over=5, tiers=[1, 2, 5, 10, 25]),
            'jet': dict(zone=5, base=315000, dur=60, over=10, tiers=[1, 2.5, 6]),
        },
        # cena tieru = dochód przy wejściu do strefy x sekundy
        TIER_SEC={'car': [0, 60, 150, 300, 600], 'yacht': [0, 120, 500, 1200, 3000], 'jet': [90, 700, 2400]},
        TIER_COST={'car': [0, 2e4, 6e4, 1.5e5, 4e5], 'yacht': [0, 1e7, 5e7, 1.5e8, 5e8], 'jet': [1e9, 5e9, 2e10]},
        # pety: bonus do L$ = baza strefy x mnożnik rzadkości x 2,5^poziom (Złoty/Diamentowy)
        PET_P0=0.05, PET_ZR=2.5,   # moc Common w strefie 1 i mnożnik mocy petów między strefami
        RAR_MULT={'C': 1, 'U': 2, 'R': 4, 'E': 8, 'L': 16, 'M': 32},
        EGG_ODDS={'A': {'C': .60, 'U': .28, 'R': .10, 'E': .02},
                  'B': {'U': .50, 'R': .35, 'E': .13, 'L': .02}},
        PREM_ODDS={'E': .75, 'L': .22, 'M': .03},
        EGG_SEC={'A': 20}, EGG_SEC_Z1={'A': 15}, EGG_B_MULT=6,
        EGG_PRICE={(1, 'A'): 150, (1, 'B'): 600, (2, 'A'): 3e3, (2, 'B'): 1.2e4, (3, 'A'): 1e5, (3, 'B'): 4e5,
                   (4, 'A'): 3e6, (4, 'B'): 1.2e7, (5, 'A'): 1e9, (5, 'B'): 4e9},
        PET_SLOTS=3,
        MERGE_N=5, MERGE_MULT=2.0, MERGE_FEE=[1, 5],
        # ubrania: bonus do LP wg rzadkości, 1 slot / kategoria
        CLOTH_BONUS={'C': .20, 'U': .40, 'R': .80, 'E': 1.60, 'L': 3.20, 'M': 6.40},
        BOX_ODDS={'street': {'C': .60, 'U': .28, 'R': .10, 'E': .02},
                  'designer': {'U': .50, 'R': .35, 'E': .13, 'L': .02},
                  'iced': {'R': .50, 'E': .35, 'L': .13, 'M': .02}},
        BOX_ANCHOR={'street': (3, 'entry', 60), 'designer': (4, 'entry', 60), 'iced': (5, 'entry', 60)},
        BOX_PRICE={'street': 1e5, 'designer': 2e7, 'iced': 5e9},
        # Rebirth: łączny mnożnik LP na danym poziomie (nie kumuluje się) i opłata w L$
        REB_MULT=[1, 2, 3, 4, 5, 7, 10, 13, 16, 20, 25],
        REB_FEE=[0, 3e10, 2e11, 1e12, 5e12, 2e13, 8e13, 3e14, 1e15, 4e15, 1.5e16],
        REB_PET_SLOT={3: 1, 7: 1},   # dodatkowe sloty petów od Rebirthu
    )


PAYER_ALL = dict(autosell=True, lp=2.1, pet_slots=2, extra_cloth=('chain', 'watch'), fast_open=True)
PAYER_2XLP = dict(autosell=False, lp=2.0, pet_slots=0, extra_cloth=(), fast_open=False)
PAYER_AUTOSELL = dict(autosell=True, lp=1.0, pet_slots=0, extra_cloth=(), fast_open=False)


def clout_value(L):
    return round(1 + L + 0.1 * L * L)


def clout_cost(cfg, L):
    return nice(cfg['CLOUT_C0'] * cfg['CLOUT_G'] ** (L - 1))


def bag_capacity(cfg, L):
    return nice(cfg['BAG0'] * cfg['BAG_G'] ** L)


def bag_cost(cfg, L):
    return nice(cfg['BAG_COSTF'] * cfg['BAG0'] * cfg['BAG_CG'] ** L)


def egg_power(cfg, z, egg):
    # pety z jajek A, B i premium tej samej strefy mają tę samą moc bazową; różnią się szansami na rzadkość
    if cfg.get('PET_ZONE'):
        return cfg['PET_ZONE'][z]
    return cfg['PET_P0'] * cfg['PET_ZR'] ** (z - 1)


def cloth_source(rar):
    if rar in ('C', 'U', 'R', 'E'):
        return 'street'
    if rar == 'L':
        return 'designer'
    return 'iced'


class Player:
    def __init__(s, cfg, payer=None, seed=0, max_rebirths=1, premium=0):
        s.cfg = cfg
        s.rng = random.Random(seed)
        s.payer = payer or {}
        s.max_reb = max_rebirths
        s.premium = premium          # ile premium jajek kupuje przy wejściu do każdej strefy
        s.t = 0.0
        s.R = 0
        s.pets = {}      # (zone, egg, rar, lvl) -> count
        s.clothes = {}   # (cat, rar, lvl) -> count
        s.ms = {}        # kamienie milowe -> czas
        s.snap = {}      # kamienie milowe -> stan
        s.entry_income = {}
        s.exit_income = {}
        s.open_total = 0.0
        s.counts = dict(eggs=0, boxes=0, merges=0, prem=0, trips=0)
        s.buys = {}
        s.first_egg = True
        s.lifetime_lp = 0.0
        s.over_time = 0.0
        s.zstat = {}     # (R, zone) -> [czas, narzut, tripy, czas_napełnienia]
        s.reset_run()

    # ---------- stan przejścia ----------
    def reset_run(s):
        s.cash = 0.0
        s.clout = 0
        s.bagL = 0
        s.zone = 1
        s.tier = {'car': -1, 'interview': -1, 'yacht': -1, 'jet': -1}
        s._pl = None
        s._cl = None

    # ---------- warstwy ----------
    def pet_slots(s):
        extra = sum(v for r, v in s.cfg['REB_PET_SLOT'].items() if s.R >= r)
        return s.cfg['PET_SLOTS'] + extra + s.payer.get('pet_slots', 0)

    def pet_bonus(s, key):
        z, egg, rar, lvl = key
        return egg_power(s.cfg, z, egg) * s.cfg['RAR_MULT'][rar] * s.cfg['MERGE_MULT'] ** lvl

    def equipped_pet_bonuses(s):
        b = []
        for k, c in s.pets.items():
            b += [s.pet_bonus(k)] * c
        b.sort(reverse=True)
        return b[:s.pet_slots()]

    def pet_layer(s):
        if s._pl is None:
            s._pl = 1 + sum(s.equipped_pet_bonuses())
        return s._pl

    def cloth_slots(s, cat):
        return 2 if cat in s.payer.get('extra_cloth', ()) else 1

    def cloth_bonus(s, key):
        cat, rar, lvl = key
        return s.cfg['CLOTH_BONUS'][rar] * s.cfg['MERGE_MULT'] ** lvl

    def cat_equipped(s, cat):
        b = []
        for k, c in s.clothes.items():
            if k[0] == cat:
                b += [s.cloth_bonus(k)] * c
        b.sort(reverse=True)
        return b[:s.cloth_slots(cat)]

    def cloth_layer(s):
        if s._cl is None:
            s._cl = 1 + sum(sum(s.cat_equipped(c)) for c in CATS)
        return s._cl

    def lp_mult(s):
        return s.cloth_layer() * s.cfg['REB_MULT'][s.R] * s.payer.get('lp', 1.0)

    def cp(s):
        return clout_value(s.clout)

    def cap(s):
        return bag_capacity(s.cfg, s.bagL)

    # ---------- dochód ----------
    def acts(s):
        m = s.lp_mult()
        cp = s.cp()
        out = [('click', s.zone, cp * s.cfg['K'] * s.cfg['ZONE_CLICK'][s.zone] * m, None, None)]
        for a, d in s.cfg['ACT'].items():
            ti = s.tier[a]
            if ti < 0:
                continue
            reward = cp * d['base'] * d['tiers'][ti] * d.get('viral', 1) * m
            cyc = d['dur'] + d['over']
            out.append((a, d['zone'], reward / cyc, reward, cyc))
        return out

    def trip(s, act):
        name, zone, rate, chunk, cyc = act
        if s.payer.get('autosell'):
            if chunk is None:
                return rate * 30.0, 30.0
            n = max(1, round(30.0 / cyc))
            return n * chunk, n * cyc
        cap = s.cap()
        if chunk is None:
            return cap, cap / rate
        n = max(1, math.ceil(cap / chunk))
        return n * chunk, n * cyc

    def overhead(s, zone, tt):
        if s.payer.get('autosell'):
            return 0.0
        walk = s.cfg['WALK'][zone] / (1 + s.cfg['REB_SPEED'] * s.R)
        return s.cfg['TELEPORT'] + walk

    def best(s):
        pl = s.pet_layer()
        best = None
        for act in s.acts():
            lp, tt = s.trip(act)
            ov = s.overhead(act[1], tt)
            r = lp / (tt + ov) * pl
            if best is None or r > best[0]:
                best = (r, act, lp, tt, ov)
        return best

    def income(s):
        return s.best()[0]

    # ---------- ekwipunek ----------
    def add_pet(s, key):
        s.pets[key] = s.pets.get(key, 0) + 1
        s._pl = None

    def add_cloth(s, key):
        s.clothes[key] = s.clothes.get(key, 0) + 1
        s._cl = None

    def egg_price(s, z, e):
        if e == 'P':
            return s.cfg['EGG_PRICE'][(z, 'B')]
        return s.cfg['EGG_PRICE'][(z, e)]

    def _merge_try(s, inv, key, layer_fn, fee, mk_new):
        cfg = s.cfg
        before = layer_fn()
        nk = mk_new(key)
        inv[key] -= cfg['MERGE_N']
        if inv[key] == 0:
            del inv[key]
        inv[nk] = inv.get(nk, 0) + 1
        s._pl = None
        s._cl = None
        after = layer_fn()
        if after > before + 1e-12 and s.cash >= fee:
            s.cash -= fee
            s.counts['merges'] += 1
            return True
        inv[nk] -= 1
        if inv[nk] == 0:
            del inv[nk]
        inv[key] = inv.get(key, 0) + cfg['MERGE_N']
        s._pl = None
        s._cl = None
        return False

    def try_merges(s):
        cfg = s.cfg
        changed = True
        while changed:
            changed = False
            for k, c in list(s.pets.items()):
                z, e, rar, lvl = k
                if c >= cfg['MERGE_N'] and lvl < 2:
                    fee = s.egg_price(z, e) * cfg['MERGE_FEE'][lvl]
                    if s._merge_try(s.pets, k, s.pet_layer, fee, lambda k: (k[0], k[1], k[2], k[3] + 1)):
                        changed = True
                        break
            if changed:
                continue
            for k, c in list(s.clothes.items()):
                cat, rar, lvl = k
                if c >= cfg['MERGE_N'] and lvl < 2:
                    fee = cfg['BOX_PRICE'][cloth_source(rar)] * cfg['MERGE_FEE'][lvl]
                    if s._merge_try(s.clothes, k, s.cloth_layer, fee, lambda k: (k[0], k[1], k[2] + 1)):
                        changed = True
                        break

    # ---------- zakupy ----------
    def candidates(s, inc):
        cfg = s.cfg
        out = []
        if s.clout < cfg['CLOUT_MAX']:
            c = clout_cost(cfg, s.clout + 1)
            g = inc * (clout_value(s.clout + 1) / clout_value(s.clout) - 1)

            def ap():
                s.clout += 1
            out.append(('clout', c, g, ap))
        if s.bagL < cfg['BAG_MAX'] and not s.payer.get('autosell'):
            base = s.bagL
            bestj = None
            c = 0.0
            for j in range(1, cfg['BAG_MAX'] + 1):
                if base + j > cfg['BAG_MAX']:
                    break
                c += bag_cost(cfg, base + j)
                if c > s.cash:
                    break
                s.bagL = base + j
                g = s.income() - inc
                if g > 0 and (bestj is None or c / g < bestj[1] / bestj[2]):
                    bestj = (j, c, g)
            s.bagL = base
            if bestj:
                j, c, g = bestj

                def ap(j=j):
                    s.bagL += j
                out.append(('bag', c, g, ap))
        for a in ('car', 'yacht', 'jet'):
            d = cfg['ACT'][a]
            ti = s.tier[a]
            if s.zone < d['zone']:
                continue
            nt = ti + 1
            if nt >= len(d['tiers']):
                continue
            c = cfg['TIER_COST'][a][nt]
            s.tier[a] = nt
            g = s.income() - inc
            s.tier[a] = ti

            def ap(a=a, nt=nt):
                s.tier[a] = nt
            out.append((a + str(nt + 1), c, g, ap))
        pl = s.pet_layer()
        eq = s.equipped_pet_bonuses()
        worst = eq[-1] if len(eq) >= s.pet_slots() else 0.0
        for z in range(1, s.zone + 1):
            for e in ('A', 'B'):
                c = s.egg_price(z, e)
                exp = 0.0
                for rar, p in cfg['EGG_ODDS'][e].items():
                    k = (z, e, rar, 0)
                    exp += p * s.item_value(s.pet_bonus(k), worst, s.pets.get(k, 0))
                g = inc * exp / pl

                def ap(z=z, e=e):
                    s.open_egg(z, e)
                out.append(('egg%d%s' % (z, e), c, g, ap))
        if s.zone >= 3:
            cl = s.cloth_layer()
            for bx, odds in cfg['BOX_ODDS'].items():
                if s.zone < cfg['BOX_ANCHOR'][bx][0]:
                    continue   # Designer wymaga plaży, Iced wymaga lotniska
                c = cfg['BOX_PRICE'][bx]
                exp = 0.0
                for cat in CATS:
                    eqc = s.cat_equipped(cat)
                    w = eqc[-1] if len(eqc) >= s.cloth_slots(cat) else 0.0
                    for rar, p in odds.items():
                        k = (cat, rar, 0)
                        exp += p / len(CATS) * s.item_value(cfg['CLOTH_BONUS'][rar], w, s.clothes.get(k, 0))
                g = inc * exp / cl

                def ap(bx=bx):
                    s.open_box(bx)
                out.append(('box_' + bx, c, g, ap))
        return out

    def item_value(s, b, worst, have):
        """Wartość nowej sztuki: natychmiastowa poprawa + udział w przyszłym łączeniu (Złoty/Diamentowy)."""
        N, M = s.cfg['MERGE_N'], s.cfg['MERGE_MULT']
        v = max(0.0, b - worst)
        gold = max(0.0, M * b - worst)
        dia = max(0.0, M * M * b - worst)
        w_gold = 1.0 if (have % N) == N - 1 else 0.6
        return max(v, gold * w_gold / N + dia * 0.3 / (N * N))

    def draw(s, odds):
        r = s.rng.random()
        acc = 0.0
        for k, p in odds.items():
            acc += p
            if r <= acc:
                return k
        return list(odds)[-1]

    def open_time(s):
        return s.cfg['FAST_OPEN'] if s.payer.get('fast_open') else s.cfg['OPEN_TIME']

    def _opened(s):
        ot = s.open_time()
        s.t += ot
        s.open_total += ot

    def open_egg(s, z, e):
        if s.first_egg and z == 1 and e == 'A':
            rar = 'R'   # samouczek: pierwsze jajko = gwarantowany Rare
            s.first_egg = False
        else:
            rar = s.draw(s.cfg['EGG_ODDS'][e])
        s.add_pet((z, e, rar, 0))
        s.counts['eggs'] += 1
        s._opened()
        s.ms.setdefault('first_egg', s.t)

    def open_premium(s, z):
        rar = s.draw(s.cfg['PREM_ODDS'])
        s.add_pet((z, 'P', rar, 0))
        s.counts['prem'] += 1
        s._opened()

    def open_box(s, bx):
        rar = s.draw(s.cfg['BOX_ODDS'][bx])
        cat = s.rng.choice(CATS)
        s.add_cloth((cat, rar, 0))
        s.counts['boxes'] += 1
        s._opened()

    def snapshot(s, key):
        s.snap[key] = dict(t=s.t, clout=s.clout, cp=s.cp(), bagL=s.bagL, cap=s.cap(),
                           pets=s.pet_layer(), cloth=s.cloth_layer(), income=s.income(),
                           eggs=s.counts['eggs'], boxes=s.counts['boxes'], merges=s.counts['merges'],
                           over=s.over_time / max(1.0, s.t), lifetime_lp=s.lifetime_lp, R=s.R,
                           opening=s.open_total / max(1.0, s.t))

    def on_zone(s, z):
        if z == 2:
            s.tier['car'] = max(s.tier['car'], 0)
        if z == 3:
            s.tier['interview'] = 0
        if z == 4:
            s.tier['yacht'] = max(s.tier['yacht'], 0)
        for _ in range(s.premium if s.R == 0 else 0):
            s.open_premium(z)
        key = 'R%d_zone%d' % (s.R, z)
        s.ms[key] = s.t
        s.entry_income.setdefault((s.R, z), s.income())
        s.snapshot(key)

    def rebirth(s):
        s.R += 1
        key = 'rebirth%d' % s.R
        s.ms[key] = s.t
        s.reset_run()
        s.snapshot(key)

    def spend(s):
        cfg = s.cfg
        while True:
            if s.zone < 5:
                zc = cfg['ZONE_COST'][s.zone + 1]
                if s.cash >= zc:
                    s.exit_income.setdefault((s.R, s.zone), s.income())
                    s.cash -= zc
                    s.zone += 1
                    s.on_zone(s.zone)
                    continue
                goal = zc
            else:
                nxt = s.R + 1
                fee = cfg['REB_FEE'][nxt] if (nxt < len(cfg['REB_FEE']) and nxt <= s.max_reb) else None
                if fee is not None and s.cash >= fee:
                    s.exit_income.setdefault((s.R, 5), s.income())
                    s.snapshot('pre_rebirth%d' % nxt)
                    s.rebirth()
                    return 'rebirth'
                goal = fee
            inc = s.income()
            best = None
            for name, cost, gain, ap in s.candidates(inc):
                price = cost
                if cost > s.cash or gain <= 0:
                    continue
                coll = name.startswith('egg') or name.startswith('box')
                if coll:
                    cost = cost + s.open_time() * inc   # czas otwierania też kosztuje
                payback = cost / gain
                if coll:
                    limit = cfg['HATCH_H'] if s.R == 0 else cfg['HATCH_H_REB']
                elif goal is None:
                    limit = 1800.0
                else:
                    limit = max(60.0, (goal - (s.cash - price)) / inc)
                if payback < limit and (best is None or payback < best[0]):
                    best = (payback, name, price, ap)
            if best:
                s.cash -= best[2]
                s.buys[best[1][:5] if best[1].startswith('egg') else best[1]] = s.buys.get(best[1][:5] if best[1].startswith('egg') else best[1], 0) + 1
                if best[1] == 'clout':
                    s.ms.setdefault('first_upgrade', s.t)
                best[3]()
                s.try_merges()
                continue
            return None

    def run(s, t_max=4e5):
        while s.t < t_max:
            r, act, lp, tt, ov = s.best()
            if s.R == 0 and s.zone == 1 and 'entry1' not in s.ms and s.t >= 60:
                s.ms['entry1'] = s.t
                s.entry_income.setdefault((0, 1), r)
            s.t += tt + ov
            s.over_time += ov
            zs = s.zstat.setdefault((s.R, s.zone), [0.0, 0.0, 0, 0.0])
            zs[0] += tt + ov; zs[1] += ov; zs[2] += 1; zs[3] += tt
            s.counts['trips'] += 1
            s.cash += lp * s.pet_layer()
            s.lifetime_lp += lp
            s.ms.setdefault('first_sell', s.t)
            res = s.spend()
            if res == 'rebirth' and s.R >= s.max_reb:
                break
        return s


def fmt_t(sec):
    if sec is None:
        return '-'
    m = sec / 60
    if m < 60:
        return '%.1f min' % m
    return '%dh%02d' % (int(m // 60), int(round(m % 60)) if round(m % 60) < 60 else 59)


def simulate(cfg, n=8, payer=None, max_reb=1, premium=0, t_max=4e5):
    res, entry, snaps, exits = {}, {}, {}, {}
    players = []
    for seed in range(n):
        p = Player(cfg, payer=payer, seed=seed, max_rebirths=max_reb, premium=premium).run(t_max)
        players.append(p)
        for k, v in p.ms.items():
            res.setdefault(k, []).append(v)
        for k, v in p.entry_income.items():
            entry.setdefault(k, []).append(v)
        for k, v in p.exit_income.items():
            exits.setdefault(k, []).append(v)
        for k, v in p.snap.items():
            for kk, vv in v.items():
                snaps.setdefault(k, {}).setdefault(kk, []).append(vv)
    zst = {}
    for p in players:
        for k, v in p.zstat.items():
            a = zst.setdefault(k, [0.0, 0.0, 0, 0.0])
            for i in range(4):
                a[i] += v[i]
    ms = {k: statistics.mean(v) for k, v in res.items() if len(v) == n}
    ent = {k: statistics.mean(v) for k, v in entry.items()}
    for k, v in exits.items():
        ent[('exit',) + k] = statistics.mean(v)
    sn = {k: {kk: statistics.mean(vv) for kk, vv in v.items()} for k, v in snaps.items()}
    sn['_zstat'] = {k: dict(over=v[1] / max(1e-9, v[0]), fill=v[3] / max(1, v[2])) for k, v in zst.items()}
    return ms, ent, sn, players


def derive_prices(cfg, ent, keep_nice=False):
    """Ceny tierów, jajek i boxów z dochodu przy wejściu do strefy."""
    f = nice if keep_nice else (lambda x: x)
    for a, secs in cfg['TIER_SEC'].items():
        z = cfg['ACT'][a]['zone']
        inc = ent[(0, z)]
        cfg['TIER_COST'][a] = [f(inc * sc) if sc > 0 else 0 for sc in secs]
    for z in range(1, 6):
        secs = cfg['EGG_SEC_Z1'] if z == 1 else cfg['EGG_SEC']
        cfg['EGG_PRICE'][(z, 'A')] = f(ent[(0, z)] * secs['A'])
        cfg['EGG_PRICE'][(z, 'B')] = f(ent[(0, z)] * secs['A'] * cfg['EGG_B_MULT'])
    for bx, (z, when, sc) in cfg['BOX_ANCHOR'].items():
        inc = ent[(0, z)] if when == 'entry' else ent[('exit', 0, z)]
        cfg['BOX_PRICE'][bx] = f(inc * sc)


def calibrate_r0(cfg, targets, iters=14, n=8, verbose=True):
    """Stroi ceny stref i opłatę R1 pod docelowe czasy (sekundy, sim)."""
    for it in range(iters):
        ms, ent, sn, _ = simulate(cfg, n=n, max_reb=1)
        derive_prices(cfg, ent)
        times = [0.0] + [ms['R0_zone%d' % z] for z in range(2, 6)] + [ms['rebirth1']]
        tgt = [0.0] + [targets[k] for k in ('z2', 'z3', 'z4', 'z5', 'r1')]
        err = []
        for i, z in enumerate([2, 3, 4, 5], start=1):
            d_act = max(1.0, times[i] - times[i - 1])
            d_tgt = tgt[i] - tgt[i - 1]
            ratio = d_tgt / d_act
            cfg['ZONE_COST'][z] *= ratio ** 0.75
            err.append(ratio)
        d_act = max(1.0, times[5] - times[4])
        d_tgt = tgt[5] - tgt[4]
        ratio = d_tgt / d_act
        cfg['REB_FEE'][1] *= ratio ** 0.75
        err.append(ratio)
        if verbose:
            print('it %2d' % it, ' '.join(fmt_t(t) for t in times[1:]),
                  ' maxerr %.3f' % max(abs(math.log(e)) for e in err))
        if max(abs(math.log(e)) for e in err) < 0.02:
            break
    return cfg


def round_all(cfg):
    for z in cfg['ZONE_COST']:
        cfg['ZONE_COST'][z] = nice(cfg['ZONE_COST'][z])
    for a in cfg['TIER_COST']:
        cfg['TIER_COST'][a] = [nice(x) if x else 0 for x in cfg['TIER_COST'][a]]
    for k in cfg['EGG_PRICE']:
        cfg['EGG_PRICE'][k] = nice(cfg['EGG_PRICE'][k])
    for k in cfg['BOX_PRICE']:
        cfg['BOX_PRICE'][k] = nice(cfg['BOX_PRICE'][k])
    cfg['REB_FEE'] = [nice(x) if x else 0 for x in cfg['REB_FEE']]
    return cfg


def cfg_to_json(cfg, path):
    def enc(o):
        if isinstance(o, dict):
            return {('|'.join(map(str, k)) if isinstance(k, tuple) else str(k)): enc(v) for k, v in o.items()}
        if isinstance(o, (list, tuple)):
            return [enc(x) for x in o]
        return o
    json.dump(enc(cfg), open(path, 'w'), indent=1)


PRICE_KEYS = ('ZONE_COST', 'TIER_COST', 'EGG_PRICE', 'BOX_PRICE', 'REB_FEE')


def cfg_from_json(path, only_prices=True):
    """Wczytuje ceny z pliku; parametry konstrukcyjne zawsze z default_cfg()."""
    raw = json.load(open(path))
    cfg = default_cfg()
    for k, v in raw.items():
        if only_prices and k not in PRICE_KEYS:
            continue
        if k == 'EGG_PRICE':
            cfg[k] = {(int(a.split('|')[0]), a.split('|')[1]): x for a, x in v.items()}
        elif k in ('ZONE_COST', 'WALK', 'ZONE_CLICK', 'REB_PET_SLOT'):
            cfg[k] = {int(a): x for a, x in v.items()}
        elif k == 'BOX_ANCHOR':
            cfg[k] = {a: tuple(x) for a, x in v.items()}
        else:
            cfg[k] = v
    return cfg


def zreport(sn):
    zs = sn.get('_zstat', {})
    for k in sorted(zs):
        print('  R%d strefa %d: narzut %4.1f%%  napełnienie Bag %6.1f s' % (k[0], k[1], 100 * zs[k]['over'], zs[k]['fill']))


def report(ms, sn, label=''):
    print('---', label)
    order = sorted(ms, key=lambda k: ms[k])
    for k in order:
        line = '%-16s %10s' % (k, fmt_t(ms[k]))
        if k in sn:
            d = sn[k]
            line += '  clout %5.1f  bagL %4.1f  pets x%7.2f  cloth x%6.2f  inc %9.3g/s  eggs %6.1f  boxes %5.1f  merges %5.1f  over %4.1f%%  open %4.1f%%' % (
                d['clout'], d['bagL'], d['pets'], d['cloth'], d['income'], d['eggs'], d['boxes'], d['merges'], 100 * d['over'], 100 * d['opening'])
        print(line)


if __name__ == '__main__':
    cfg = default_cfg()
    T = dict(z2=4 * 60, z3=16 * 60, z4=45 * 60, z5=120 * 60, r1=195 * 60)
    calibrate_r0(cfg, T, iters=16, n=8)
    cfg_to_json(cfg, 'cfg_r0.json')
    ms, ent, sn, _ = simulate(cfg, n=8, max_reb=1)
    report(ms, sn, 'F2P (po kalibracji, ceny surowe)')
    zreport(sn)
    _, _, _, pl = simulate(cfg, n=4, max_reb=1)
    tot = {}
    for p in pl:
        for k, v in p.buys.items():
            if k.startswith('egg') or k.startswith('box') or k.startswith(('car', 'yacht', 'jet')):
                tot[k] = tot.get(k, 0) + v / len(pl)
    print('  zakupy (średnio):', {k: round(v, 1) for k, v in sorted(tot.items())})


def calibrate_rebirths(cfg, cycle_targets, n=6, iters=10, verbose=True):
    """Stroi opłaty Rebirth 2..10 pod docelową długość kolejnych cykli (sekundy, sim).
    Gracze są kopiowani w stanie tuż po poprzednim Rebirthie, więc każdy poziom liczony jest osobno."""
    players = [Player(cfg, seed=sd, max_rebirths=1).run() for sd in range(n)]
    out = {}
    for lvl in range(2, len(cfg['REB_FEE'])):
        base = [copy.deepcopy(p, {id(cfg): cfg}) for p in players]
        tgt = cycle_targets[lvl]
        for it in range(iters):
            trial = [copy.deepcopy(p, {id(cfg): cfg}) for p in base]
            for p in trial:
                p.max_reb = lvl
                p.run(t_max=p.t + 60 * 3600)
            cyc = statistics.mean(p.ms.get('rebirth%d' % lvl, p.t) - p.ms['rebirth%d' % (lvl - 1)] for p in trial)
            ratio = tgt / max(60.0, cyc)
            if abs(math.log(ratio)) < 0.03:
                break
            cfg['REB_FEE'][lvl] *= ratio ** 0.85
        players = trial
        back = statistics.mean(p.ms['R%d_zone5' % (lvl - 1)] - p.ms['rebirth%d' % (lvl - 1)] for p in trial)
        open_share = statistics.mean((p.open_total - b.open_total) / max(1.0, p.t - b.t) for p, b in zip(trial, base))
        over_share = statistics.mean((p.over_time - b.over_time) / max(1.0, p.t - b.t) for p, b in zip(trial, base))
        out[lvl] = dict(cycle=cyc, back=back, fee=cfg['REB_FEE'][lvl],
                        pets=statistics.mean(p.snap['pre_rebirth%d' % lvl]['pets'] for p in trial),
                        cloth=statistics.mean(p.snap['pre_rebirth%d' % lvl]['cloth'] for p in trial),
                        clout=statistics.mean(p.snap['pre_rebirth%d' % lvl]['clout'] for p in trial),
                        bagL=statistics.mean(p.snap['pre_rebirth%d' % lvl]['bagL'] for p in trial),
                        eggs=statistics.mean(p.counts['eggs'] for p in trial),
                        boxes=statistics.mean(p.counts['boxes'] for p in trial),
                        t=statistics.mean(p.t for p in trial), open=open_share, over=over_share)
        if verbose:
            d = out[lvl]
            print('R%-2d cykl %8s  powrót %7s  opłata %.3g  pets x%.1f cloth x%.1f clout %.0f bagL %.0f  eggs %.0f boxes %.0f  otwieranie %.0f%% narzut %.0f%%  łącznie %s' % (
                lvl, fmt_t(d['cycle']), fmt_t(d['back']), d['fee'], d['pets'], d['cloth'], d['clout'], d['bagL'], d['eggs'], d['boxes'], 100 * d['open'], 100 * d['over'], fmt_t(d['t'])))
    return out


CYCLE_TARGETS = {2: 90 * 60, 3: 105 * 60, 4: 120 * 60, 5: 150 * 60, 6: 165 * 60,
                 7: 180 * 60, 8: 210 * 60, 9: 225 * 60, 10: 255 * 60}
