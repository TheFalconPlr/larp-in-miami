"""Przejście gry „na sucho” (bez Roblox): symulowany gracz bez Robuxów gra od zera do Rebirth 1.

Po co: szukanie nudnych miejsc w pętli gry. Dla każdej strefy pokazuje, ile trwa, ile w niej sesji
tej samej aktywności, ile czasu gracz tylko patrzy, ile chodzi po Sell i jak długo nie ma nic nowego
do kupienia. Uruchom z głównego folderu projektu:

    python tools/playtest.py                      gra dziś: gracz idealny i 8-latek
    python tools/playtest.py --hype 0.5           propozycja: aktywne sesje (do +50% nagrody)
    python tools/playtest.py --z5 1e12 --r1 2.5e13 --yacht 4e8,2e9,1.5e10,1.2e11
                                                  propozycja: tańsza strefa 5 i Rebirth 1, jachty rozłożone
    python tools/playtest.py --rebirths 3         kolejne przejścia (po Rebirthie)

Liczy na modelu ekonomii z tools/economy (ten sam, z którego powstaje Economy.luau; wzory porównuje
z kodem gry tools/test_luau.py) z jedną regułą z gry, której model nie ma: nagroda aktywności wchodzi
do Bag tylko do pełna (Loop.finishActivity), więc reszta przepada.

Profile (to założenia, nie pomiary):
  ideal  4 kliknięcia na sekundę, zero namysłu, kupuje to, co najszybciej się zwraca (jak model),
         sprzedaje przed sesją, która nie zmieściłaby się w Bag. Najszybsze możliwe przejście.
  kid    8-latek: 3 kliknięcia na sekundę, chodzi 1,4 raza dłużej, 4 s namysłu przy każdej sprzedaży,
         3 s przed każdą sesją, 2 s na każdy zakup. Kupuje strefę i nowy pojazd, gdy tylko go stać,
         ulepszenie, gdy jest tanie (do 30% portfela) albo gdy nagroda nie mieści się w Bag, a jajko
         albo box, gdy jest bardzo tani (do 8% portfela, najwyżej 3 na postój). Gra do pełnego Bag.
         Prawdziwe dziecko będzie gdzieś między tym profilem a idealnym.
"""
import argparse
import math
import os
import statistics
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, 'economy'))

import economy2 as v2              # noqa: E402
from final_cfg2 import final_cfg2  # noqa: E402

PROFILES = {
    # K = kliknięcia/s, walk = mnożnik czasu chodzenia, think = sekundy namysłu przy każdej sprzedaży,
    # start = sekundy przed każdą sesją (dojście i E), shop = sekundy na jeden zakup, policy = jak wydaje
    'ideal': dict(K=4.0, walk=1.0, think=0.0, start=0.0, shop=0.0, policy='payback'),
    'kid': dict(K=3.0, walk=1.4, think=4.0, start=3.0, shop=2.0, policy='kid', up_frac=0.30, toy_frac=0.08, toy_max=3),
}
PROFILE_NAMES = {'ideal': 'gracz idealny', 'kid': '8-latek (szacunek)'}
ZONE_NAMES = {1: 'Downtown', 2: 'Luxury Cars', 3: 'Luxury Mall', 4: 'Miami Beach', 5: 'Private Airport'}
VEHICLES = ('car', 'yacht', 'jet')
ACT_PL = {'car': 'zdjęcia aut', 'interview': 'wywiady', 'yacht': 'imprezy na jachcie', 'jet': 'loty'}


def make_cfg(mod=None):
    cfg = final_cfg2()
    cfg['BAG_MAX'] = 35  # w grze Bag ma 35 poziomów
    if mod is not None:
        mod(cfg)
    return cfg


class Bot(v2.AuraPlayer):
    """Gracz z modelu (economy2.AuraPlayer) z regułą Bag z gry, profilem i dziennikiem."""

    def __init__(s, cfg, profile, seed=0, max_rebirths=1, hype=0.0, overfill=False):
        s.pf = PROFILES[profile]
        s.hype = hype          # propozycja: aktywna sesja (każda aktywność) daje nagrodę × (1 + hype)
        s.overfill = overfill  # propozycja: ostatnia sesja może przepełnić Bag (nic nie przepada)
        s.zlog = {}            # (numer przejścia, strefa) -> statystyki
        s.events = []          # (czas, nazwa zakupu, numer przejścia, strefa)
        super().__init__(dict(cfg, K=s.pf['K']), seed=seed, max_rebirths=max_rebirths)

    # ----- dochód jak w grze
    def acts(s):
        out = []
        for name, zone, rate, chunk, cyc in super().acts():
            if chunk is not None:
                # premia w każdej aktywności, też w wywiadzie: sama dla aut, jachtów i odrzutowców
                # sprawia, że wywiad przestaje się opłacać (w strefie 3 wygrywają wtedy zdjęcia aut)
                chunk = chunk * (1 + s.hype)
                cyc = cyc + s.pf['start']
                rate = chunk / cyc
            out.append((name, zone, rate, chunk, cyc))
        return out

    def trip(s, act):
        """Jeden kurs: LP do sprzedania i czas zbierania. Sesje do pełnego Bag, nadwyżka przepada."""
        name, zone, rate, chunk, cyc = act
        cap = s.cap()
        if chunk is None:
            return cap, cap / rate
        n = max(1, math.ceil(cap / chunk - 1e-9))
        if s.overfill:
            return n * chunk, n * cyc
        if s.pf['policy'] != 'kid' and n > 1:
            # gracz idealny sprzedaje przed sesją, która się nie zmieści, jeśli to daje więcej na minutę
            ov = s.overhead(zone, 0)
            lo = n - 1
            if lo * chunk / (lo * cyc + ov) > min(cap, n * chunk) / (n * cyc + ov):
                return lo * chunk, lo * cyc
        return min(cap, n * chunk), n * cyc

    def overhead(s, zone, tt):
        walk = s.cfg['WALK'][zone] / (1 + s.cfg['REB_SPEED'] * s.R) * s.pf['walk']
        return s.cfg['TELEPORT'] + walk + s.pf['think']

    # ----- dziennik
    def z(s):
        return s.zlog.setdefault((s.RC, s.zone), dict(time=0.0, click=0.0, walk=0.0, shop=0.0, sells=0,
                                                       sess={}, sess_time={}, lost=0.0, earned=0.0))

    def _opened(s):
        ot = s.open_time() + s.pf['shop']
        s.t += ot
        s.open_total += ot
        zl = s.z()
        zl['shop'] += ot
        zl['time'] += ot

    def buy(s, name, price, apply):
        s.cash -= price
        key = name[:5] if name.startswith('egg') else name
        s.buys[key] = s.buys.get(key, 0) + 1
        if not (name.startswith('egg') or name.startswith('box')) and s.pf['shop'] > 0:
            s.t += s.pf['shop']
            zl = s.z()
            zl['shop'] += s.pf['shop']
            zl['time'] += s.pf['shop']
        apply()
        s.events.append((s.t, name, s.RC, s.zone))
        s.try_merges()

    # ----- zakupy
    def advance(s):
        """Strefa albo Rebirth, gdy gracza stać. Zwraca 'zone', 'rebirth' albo None."""
        cfg = s.cfg
        if s.zone < 5:
            cost = cfg['ZONE_COST'][s.zone + 1]
            if s.cash < cost:
                return None
            s.exit_income.setdefault((s.RC, s.zone), s.income())
            s.cash -= cost
            s.zone += 1
            s.on_zone(s.zone)
            return 'zone'
        fee = s.next_fee()
        if fee is None or s.cash < fee:
            return None
        s.exit_income.setdefault((s.RC, 5), s.income())
        s.snapshot('pre_rebirth%d' % (s.RC + 1))
        s.rebirth()
        return 'rebirth'

    def spend(s):
        if s.pf['policy'] == 'kid':
            return s.spend_kid()
        cfg = s.cfg
        while True:
            step = s.advance()
            if step == 'zone':
                continue
            if step == 'rebirth':
                return 'rebirth'
            goal = cfg['ZONE_COST'][s.zone + 1] if s.zone < 5 else s.next_fee()
            inc = s.income()
            best = None
            for name, cost, gain, apply in s.candidates(inc):
                price = cost
                if cost > s.cash or gain <= 0:
                    continue
                toy = name.startswith('egg') or name.startswith('box')
                if toy:
                    cost = cost + s.open_time() * inc  # czas otwierania też kosztuje
                payback = cost / gain
                if toy:
                    limit = cfg['HATCH_H'] if s.RC == 0 else cfg['HATCH_H_REB']
                elif goal is None:
                    limit = 1800.0
                else:
                    limit = max(60.0, (goal - (s.cash - price)) / inc)
                if payback < limit and (best is None or payback < best[0]):
                    best = (payback, name, price, apply)
            if best is None:
                return None
            s.buy(best[1], best[2], best[3])

    def spend_kid(s):
        pf = s.pf
        toys_bought = 0
        for _ in range(400):
            step = s.advance()
            if step == 'zone':
                continue
            if step == 'rebirth':
                return 'rebirth'
            cands = [c for c in s.candidates(s.income()) if c[1] <= s.cash]
            pick = None
            for c in cands:  # nowy pojazd: zawsze, gdy stać
                if c[0][:-1] in VEHICLES:
                    pick = c
                    break
            if pick is None:
                act = s.best()[1]
                small_bag = act[3] is not None and act[3] > s.cap()  # gra pokazuje, że nagroda się nie mieści
                ups = sorted((c for c in cands if c[0] in ('clout', 'bag') and c[2] > 0), key=lambda c: c[1])
                for c in ups:
                    if c[1] <= pf['up_frac'] * s.cash or (c[0] == 'bag' and small_bag):
                        pick = c
                        break
            if pick is None and toys_bought < pf['toy_max']:
                toys = [c for c in cands if (c[0].startswith('egg') or c[0].startswith('box')) and c[1] <= pf['toy_frac'] * s.cash]
                if toys:
                    pick = max(toys, key=lambda c: c[1])  # najdroższe z tanich = z najnowszej strefy
                    toys_bought += 1
            if pick is None:
                return None
            s.buy(pick[0], pick[1], pick[3])
        return None

    # ----- gra
    def run(s, t_max=60 * 3600):
        cfg = s.cfg
        daily_rate = cfg['AURA_DAILY'] / (s.play_h_day * 3600 / cfg['REAL_F'])
        while s.t < t_max:
            income, act, lp, tt, ov = s.best()
            name, zone, rate, chunk, cyc = act
            zl = s.z()
            zl['time'] += tt + ov
            zl['walk'] += ov
            zl['sells'] += 1
            zl['earned'] += lp
            if chunk is None:
                zl['click'] += tt
            else:
                n = int(round(tt / cyc))
                zl['sess'][name] = zl['sess'].get(name, 0) + n
                zl['sess_time'][name] = zl['sess_time'].get(name, 0.0) + tt
                zl['lost'] += max(0.0, n * chunk - lp)
            s.t += tt + ov
            s.over_time += ov
            s.counts['trips'] += 1
            s.cash += lp * s.pet_layer()
            s.lifetime_lp += lp
            if s.RC >= 1:
                if name != 'click':
                    factor = cfg['INTERVIEW_BAR'] if name == 'interview' else 1.0
                    s.add_aura(tt * factor / cfg['AURA_BAR_SEC'] * cfg['AURA_BAR'], 'bar')
                s.add_aura((tt + ov) * daily_rate, 'daily')
            if s.spend() == 'rebirth' and s.RC >= s.max_reb:
                break
        return s


def play(profile, seeds=8, mod=None, hype=0.0, overfill=False, rebirths=1, t_max=60 * 3600):
    cfg = make_cfg(mod)
    return [Bot(cfg, profile, seed=sd, max_rebirths=rebirths, hype=hype, overfill=overfill).run(t_max)
            for sd in range(seeds)]


# ---------------------------------------------------------------- raport
def minutes(sec):
    m = sec / 60.0
    if m >= 100:
        return '%.1f h' % (m / 60.0)
    return '%.0f min' % m


def zone_window(bot, rc, z):
    """Czas wejścia do strefy i wyjścia z niej (kupno następnej albo Rebirth) w przejściu rc."""
    if z > 1:
        t_in = bot.ms.get('R%d_zone%d' % (rc, z))
    else:
        t_in = bot.ms.get('rebirth%d' % rc, 0.0) if rc > 0 else 0.0
    t_out = bot.ms.get('R%d_zone%d' % (rc, z + 1)) if z < 5 else bot.ms.get('rebirth%d' % (rc + 1))
    return t_in, t_out


def report(bots, label, rc=0):
    mean = statistics.mean
    print('=' * 110)
    print(label)
    for z in range(1, 6):
        logs = [b.zlog.get((rc, z)) for b in bots]
        if not all(logs):
            print('strefa %d: nie każdy gracz do niej doszedł' % z)
            continue
        t = mean(x['time'] for x in logs)
        sess, watch = {}, 0.0
        for x in logs:
            for k, v in x['sess'].items():
                sess[k] = sess.get(k, 0.0) + v / len(logs)
            watch += sum(x['sess_time'].values()) / len(logs)
        no_new, no_buy, tail = [], [], []
        for b in bots:
            t_in, t_out = zone_window(b, rc, z)
            if t_in is None or t_out is None:
                continue
            buys = [e for e in b.events if e[2] == rc and e[3] == z]
            new = sorted(set([t_in] + [e[0] for e in buys if e[1][:-1] in VEHICLES] + [t_out]))
            anyb = sorted(set([t_in] + [e[0] for e in buys] + [t_out]))
            no_new.append(max(b2 - a for a, b2 in zip(new, new[1:])))
            no_buy.append(max(b2 - a for a, b2 in zip(anyb, anyb[1:])))
            tail.append(t_out - new[-2])
        acts = ', '.join('%d × %s' % (int(v + 0.5), ACT_PL[k]) for k, v in sorted(sess.items()) if v >= 0.5) or 'samo klikanie'
        lost = mean(x['lost'] / max(1.0, x['lost'] + x['earned']) for x in logs)
        print('strefa %d %-15s %8s | %s' % (z, ZONE_NAMES[z], minutes(t), acts))
        print('    czas: klikanie %.0f%%, oglądanie sesji %.0f%%, droga po Sell %.0f%%, zakupy i jajka %.0f%% | Sell %.0f razy | LP, które nie zmieściły się w Bag: %.0f%%' % (
            100 * mean(x['click'] for x in logs) / t, 100 * watch / t, 100 * mean(x['walk'] for x in logs) / t,
            100 * mean(x['shop'] for x in logs) / t, mean(x['sells'] for x in logs), 100 * lost))
        if no_new:
            print('    najdłużej bez nowego pojazdu albo strefy: %s | od ostatniego pojazdu do bramki: %s | najdłużej bez żadnego zakupu: %s' % (
                minutes(mean(no_new)), minutes(mean(tail)), minutes(mean(no_buy))))
    key = 'rebirth%d' % (rc + 1)
    done = [b.ms[key] for b in bots if key in b.ms]
    if len(done) == len(bots):
        start = mean(b.ms.get('rebirth%d' % rc, 0.0) for b in bots) if rc > 0 else 0.0
        print('do Rebirth %d: %s' % (rc + 1, minutes(mean(done) - start)))
    else:
        print('do Rebirth %d doszło %d z %d graczy w limicie czasu' % (rc + 1, len(done), len(bots)))


def numbers(text):
    return [float(x) for x in text.split(',')]


def main():
    ap = argparse.ArgumentParser(description='Przejście gry bez Robuxów na modelu ekonomii.')
    ap.add_argument('--profile', choices=sorted(PROFILES), help='tylko jeden profil (domyślnie oba)')
    ap.add_argument('--seeds', type=int, default=8, help='ilu graczy uśrednić (domyślnie 8)')
    ap.add_argument('--rebirths', type=int, default=1, help='do którego Rebirthu grać (domyślnie 1)')
    ap.add_argument('--hype', type=float, default=0.0, help='premia za aktywną sesję, np. 0.5 = +50%% nagrody')
    ap.add_argument('--overfill', action='store_true', help='ostatnia sesja może przepełnić Bag (nic nie przepada)')
    ap.add_argument('--z5', type=float, help='cena strefy 5 (dziś 3e12)')
    ap.add_argument('--r1', type=float, help='opłata za Rebirth 1 (dziś 4e13)')
    ap.add_argument('--yacht', type=numbers, help='ceny jachtów 2–5, np. 4e8,2e9,1.5e10,1.2e11')
    ap.add_argument('--jet', type=numbers, help='ceny odrzutowców 1–3, np. 1.2e11,1e12,4e12')
    args = ap.parse_args()

    def mod(cfg):
        if args.z5:
            cfg['ZONE_COST'][5] = args.z5
        if args.r1:
            cfg['REB_FEE'][1] = args.r1
        if args.yacht:
            cfg['TIER_COST']['yacht'] = [0] + args.yacht
        if args.jet:
            cfg['TIER_COST']['jet'] = args.jet

    changes = [k for k in ('hype', 'overfill', 'z5', 'r1', 'yacht', 'jet') if getattr(args, k)]
    what = 'ze zmianami: ' + ', '.join(changes) if changes else 'gra dziś'
    for profile in ([args.profile] if args.profile else ['ideal', 'kid']):
        bots = play(profile, seeds=args.seeds, mod=mod, hype=args.hype, overfill=args.overfill, rebirths=args.rebirths)
        for rc in range(args.rebirths):
            title = '%s, %s' % (PROFILE_NAMES[profile], what)
            if args.rebirths > 1:
                title += ', przejście %d' % (rc + 1) + (' (po Rebirth %d)' % rc if rc else '')
            report(bots, title, rc)


if __name__ == '__main__':
    main()
