"""Larp in Miami — ekonomia v2: Aura (waluta od Rebirth 1), sklep Aury, szczęście, sekrety, łączenie z szansą.

Rozszerza economy.Player (v1) bez zmiany pierwszego przejścia: Aura pojawia się dopiero po Rebirth 1.
"""
import math, copy, statistics, random
import economy as E
from final_cfg import final_cfg

ORDER = {'C': 0, 'U': 1, 'R': 2, 'E': 3, 'L': 4, 'M': 5, 'S': 6, 'X': 7}  # X = Ultra Secret (ubrania)


def v2_cfg(cfg=None):
    cfg = cfg or final_cfg()
    cfg = copy.deepcopy(cfg)
    # --- sekrety: tylko jajka B za L$, moc x64 (Mythic x32)
    cfg['SECRET_P'] = 1 / 25000
    cfg['RAR_MULT'] = dict(cfg['RAR_MULT'], S=64)
    b = dict(cfg['EGG_ODDS']['B'])
    b['U'] = round(b['U'] - cfg['SECRET_P'], 8)
    b['S'] = cfg['SECRET_P']
    cfg['EGG_ODDS'] = dict(cfg['EGG_ODDS'], B=b)
    # --- Ultra Secret (4.11.2026): tylko w boxie Iced, 10× rzadszy niż sekret z jajka, ubrania „chrome”,
    # bonus 2× Mythic (jak sekret u petów: ×64 przy Mythic ×32). Odejmujemy go od Rare, jak sekret od Uncommon.
    cfg['ULTRA_P'] = round(cfg['SECRET_P'] / 10, 12)
    cfg['CLOTH_BONUS'] = dict(cfg['CLOTH_BONUS'], X=cfg['CLOTH_BONUS']['M'] * 2)
    iced = dict(cfg['BOX_ODDS']['iced'])
    iced['R'] = round(iced['R'] - cfg['ULTRA_P'], 8)
    iced['X'] = cfg['ULTRA_P']
    cfg['BOX_ODDS'] = dict(cfg['BOX_ODDS'], iced=iced)
    # --- Aura: źródła
    cfg['AURA_REB'] = 100          # Rebirth N daje 100 x N (po limicie poziomów: 100 x limit)
    cfg['REB_CAP'] = 10            # poziomy Rebirth na premierę
    cfg['AURA_BAR_SEC'] = 600      # pasek Aury: 10 min aktywności = +AURA_BAR
    cfg['AURA_BAR'] = 10
    cfg['INTERVIEW_BAR'] = 2.0     # wywiad napełnia pasek 2x szybciej
    cfg['AURA_DAILY'] = 50         # 3 zadania x10 + 20 za komplet
    cfg['PLAY_H_DAY'] = 2.0        # założenie: 2 h realnej gry dziennie
    cfg['REAL_F'] = 1.3            # realny gracz ~30% wolniej niż symulowany
    cfg['POST_CAP_G'] = 1.25       # Rebirth po limicie: opłata +25% za każdy kolejny
    # --- sklep Aury
    cfg['UPG'] = {
        'click': dict(c0=100, g=1.10, eff=0.10, w=1.0),    # Click Boost: +0.1x Click Multiplier
        'luck': dict(c0=100, g=1.10, eff=0.05, w=1.25),    # Luck: +5% szczęścia (jajka i boxy za L$)
        'gain': dict(c0=250, g=1.15, eff=0.05, w=2.0),     # Aura Gain: +5% Aury
    }
    cfg['MERGE_UPG'] = dict(costs=[200, 400, 800, 1500, 3000], eff=0.01, w=1.5)  # Merge Luck: +1 pp na peta
    cfg['MERGE_Q'] = 0.20
    return cfg


def sig2(x):
    """Zaokrąglenie do 2 cyfr znaczących (100, 110, 120, 130, 150...)."""
    if x < 100:
        return int(round(x))
    e = int(math.floor(math.log10(x))) - 1
    return int(math.floor(x / 10 ** e + 0.5) * 10 ** e)


def upg_cost(cfg, key, L):
    """Koszt poziomu L (1, 2, 3...) ulepszenia nielimitowanego."""
    u = cfg['UPG'][key]
    return sig2(u['c0'] * u['g'] ** (L - 1))


def upg_cost_raw(cfg, key, L):
    u = cfg['UPG'][key]
    return int(round(u['c0'] * u['g'] ** (L - 1)))


_EO_CACHE = {}


def eff_odds(odds, lam):
    """Szanse po szczęściu: najlepszy z n losowań, n = floor(lam) lub +1 z p = frac(lam)."""
    ck = (tuple(sorted(odds.items())), round(lam, 6))
    hit = _EO_CACHE.get(ck)
    if hit is not None:
        return hit
    res = _eff_odds(odds, lam)
    _EO_CACHE[ck] = res
    return res


def _eff_odds(odds, lam):
    keys = sorted(odds, key=lambda k: ORDER[k])
    n0 = int(math.floor(lam + 1e-12))
    fr = lam - n0
    cum = []
    acc = 0.0
    for k in keys:
        acc += odds[k]
        cum.append(min(1.0, acc))
    out = {}
    prev = 0.0
    for k, F in zip(keys, cum):
        Fm = (1 - fr) * F ** max(1, n0) + fr * F ** (max(1, n0) + 1) if lam >= 1 else F
        out[k] = max(0.0, Fm - prev)
        prev = Fm
    return out


class AuraPlayer(E.Player):
    def __init__(s, cfg, payer=None, seed=0, max_rebirths=1, premium=0, play_h_day=None, buy_aura=True):
        s.aura = 0.0
        s.aura_tot = 0.0
        s.aura_src = dict(reb=0.0, bar=0.0, daily=0.0)
        s.lv = dict(click=0, luck=0, gain=0, merge=0)
        s.RC = 0
        s.buy_aura = buy_aura
        s.secrets = 0
        s.play_h_day = play_h_day or cfg['PLAY_H_DAY']
        s.lvlog = {}
        s.merge_tries = 0
        s.merge_fail = 0
        super().__init__(cfg, payer=payer, seed=seed, max_rebirths=max_rebirths, premium=premium)

    # ---------- efekty sklepu ----------
    def cp(s):
        return E.clout_value(s.clout) * (1 + s.cfg['UPG']['click']['eff'] * s.lv['click'])

    def luck(s):
        return 1 + s.cfg['UPG']['luck']['eff'] * s.lv['luck']

    def gain(s):
        return 1 + s.cfg['UPG']['gain']['eff'] * s.lv['gain']

    def merge_q(s):
        return s.cfg['MERGE_Q'] + s.cfg['MERGE_UPG']['eff'] * s.lv['merge']

    def aura_level(s):
        return sum(s.lv.values())

    # ---------- Aura ----------
    def add_aura(s, x, src):
        if s.RC < 1 or x <= 0:
            return
        x *= s.gain()
        s.aura += x
        s.aura_tot += x
        s.aura_src[src] += x
        if s.buy_aura:
            s.spend_aura()

    def next_upgrade(s):
        cfg = s.cfg
        opts = []
        for k, u in cfg['UPG'].items():
            c = upg_cost(cfg, k, s.lv[k] + 1)
            opts.append((c * u['w'], c, k))
        mu = cfg['MERGE_UPG']
        if s.lv['merge'] < len(mu['costs']):
            c = mu['costs'][s.lv['merge']]
            opts.append((c * mu['w'], c, 'merge'))
        return min(opts)

    def spend_aura(s):
        while True:
            _, c, k = s.next_upgrade()
            if c > s.aura:
                return
            s.aura -= c
            s.lv[k] += 1

    # ---------- szczęście ----------
    def draw_luck(s, odds):
        lam = s.luck()
        n = int(lam)
        if s.rng.random() < lam - n:
            n += 1
        best = None
        for _ in range(max(1, n)):
            r = s.draw(odds)
            if best is None or ORDER[r] > ORDER[best]:
                best = r
        return best

    def open_egg(s, z, e):
        if s.first_egg and z == 1 and e == 'A':
            rar = 'R'
            s.first_egg = False
        else:
            rar = s.draw_luck(s.cfg['EGG_ODDS'][e])
        if rar == 'S':
            s.secrets += 1
            s.ms.setdefault('first_secret', s.t)
        s.add_pet((z, e, rar, 0))
        s.counts['eggs'] += 1
        s._opened()
        s.ms.setdefault('first_egg', s.t)

    def open_box(s, bx):
        rar = s.draw_luck(s.cfg['BOX_ODDS'][bx])
        cat = s.rng.choice(E.CATS)
        s.add_cloth((cat, rar, 0))
        s.counts['boxes'] += 1
        s._opened()

    def candidates(s, inc):
        """Decyzje zakupowe na szansach po szczęściu. Sekret jest pomijany w wartości oczekiwanej:
        symulowany gracz nie poluje na sekrety (to loteria), ale może je wylosować."""
        cfg = s.cfg
        lam = s.luck()
        eo, bo = cfg['EGG_ODDS'], cfg['BOX_ODDS']
        key = round(lam, 6)
        cache = s.__dict__.setdefault('_odds_cache', {})
        if key not in cache:
            ev_eggs = {}
            for k, v in eo.items():
                o = {r: p for r, p in v.items() if r != 'S'}
                ev_eggs[k] = eff_odds(o, lam) if lam > 1.0 else o
            ev_boxes = {}
            for k, v in bo.items():
                o = {r: p for r, p in v.items() if r != 'X'}  # na Ultra Secret też nie poluje
                ev_boxes[k] = eff_odds(o, lam) if lam > 1.0 else o
            cache[key] = (ev_eggs, ev_boxes)
        cfg['EGG_ODDS'], cfg['BOX_ODDS'] = cache[key]
        try:
            return super().candidates(inc)
        finally:
            cfg['EGG_ODDS'], cfg['BOX_ODDS'] = eo, bo

    # ---------- łączenie z szansą (1-5 sztuk, każda +q) ----------
    def _merge_rand(s, inv, key, layer_fn, full_fee, mk_new, premium=False):
        q = s.merge_q()
        if premium:
            n = int(math.ceil(1 / q - 1e-9))
            p = 1.0
        else:
            n = min(5, int(math.floor(1 / q + 1e-9)))
            p = min(1.0, n * q)
        if inv.get(key, 0) < n:
            return False
        fee = full_fee / 5 * n
        if s.cash < fee:
            return False
        before = layer_fn()
        nk = mk_new(key)
        inv[nk] = inv.get(nk, 0) + 1
        inv[key] -= n
        s._pl = s._cl = None
        after = layer_fn()
        inv[nk] -= 1
        if inv[nk] == 0:
            del inv[nk]
        inv[key] += n
        s._pl = s._cl = None
        if after <= before + 1e-12:
            return False
        s.cash -= fee
        inv[key] -= n
        if inv[key] == 0:
            del inv[key]
        s.merge_tries += 1
        if s.rng.random() < p:
            inv[nk] = inv.get(nk, 0) + 1
            s.counts['merges'] += 1
        else:
            s.merge_fail += 1
        s._pl = s._cl = None
        return True

    def try_merges(s):
        cfg = s.cfg
        changed = True
        guard = 0
        while changed and guard < 200:
            guard += 1
            changed = False
            for k, c in list(s.pets.items()):
                z, e, rar, lvl = k
                if c >= 4 and lvl < 2:
                    fee = s.egg_price(z, e) * cfg['MERGE_FEE'][lvl]
                    if s._merge_rand(s.pets, k, s.pet_layer, fee, lambda k: (k[0], k[1], k[2], k[3] + 1), premium=(e == 'P')):
                        changed = True
                        break
            if changed:
                continue
            for k, c in list(s.clothes.items()):
                cat, rar, lvl = k
                if c >= 4 and lvl < 2:
                    fee = cfg['BOX_PRICE'][E.cloth_source(rar)] * cfg['MERGE_FEE'][lvl]
                    if s._merge_rand(s.clothes, k, s.cloth_layer, fee, lambda k: (k[0], k[1], k[2] + 1)):
                        changed = True
                        break

    # ---------- Rebirth: poziom (mnożnik) vs licznik ----------
    def next_fee(s):
        cfg = s.cfg
        nxt = s.RC + 1
        if nxt > s.max_reb:
            return None
        if nxt <= cfg['REB_CAP']:
            return cfg['REB_FEE'][nxt]
        return cfg['REB_FEE'][cfg['REB_CAP']] * cfg['POST_CAP_G'] ** (nxt - cfg['REB_CAP'])

    def on_zone(s, z):
        if z == 2:
            s.tier['car'] = max(s.tier['car'], 0)
        if z == 3:
            s.tier['interview'] = 0
        if z == 4:
            s.tier['yacht'] = max(s.tier['yacht'], 0)
        for _ in range(s.premium if s.RC == 0 else 0):
            s.open_premium(z)
        key = 'R%d_zone%d' % (s.RC, z)
        s.ms[key] = s.t
        s.entry_income.setdefault((s.RC, z), s.income())
        s.snapshot(key)

    def snapshot(s, key):
        super().snapshot(key)
        s.snap[key].update(aura_tot=s.aura_tot, aura_lvl=s.aura_level(), lv=dict(s.lv), luck=s.luck(),
                           secrets=s.secrets, RC=s.RC)

    def rebirth(s):
        s.RC += 1
        s.R = min(s.RC, s.cfg['REB_CAP'])
        key = 'rebirth%d' % s.RC
        s.ms[key] = s.t
        s.reset_run()
        s.add_aura(s.cfg['AURA_REB'] * s.R, 'reb')
        s.snapshot(key)

    def spend(s):
        cfg = s.cfg
        while True:
            if s.zone < 5:
                zc = cfg['ZONE_COST'][s.zone + 1]
                if s.cash >= zc:
                    s.exit_income.setdefault((s.RC, s.zone), s.income())
                    s.cash -= zc
                    s.zone += 1
                    s.on_zone(s.zone)
                    continue
                goal = zc
            else:
                fee = s.next_fee()
                if fee is not None and s.cash >= fee:
                    s.exit_income.setdefault((s.RC, 5), s.income())
                    s.snapshot('pre_rebirth%d' % (s.RC + 1))
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
                    cost = cost + s.open_time() * inc
                payback = cost / gain
                if coll:
                    limit = cfg['HATCH_H'] if s.RC == 0 else cfg['HATCH_H_REB']
                elif goal is None:
                    limit = 1800.0
                else:
                    limit = max(60.0, (goal - (s.cash - price)) / inc)
                if payback < limit and (best is None or payback < best[0]):
                    best = (payback, name, price, ap)
            if best:
                s.cash -= best[2]
                bk = best[1][:5] if best[1].startswith('egg') else best[1]
                s.buys[bk] = s.buys.get(bk, 0) + 1
                if best[1] == 'clout':
                    s.ms.setdefault('first_upgrade', s.t)
                best[3]()
                s.try_merges()
                continue
            return None

    def run(s, t_max=4e5):
        cfg = s.cfg
        daily_rate = cfg['AURA_DAILY'] / (s.play_h_day * 3600 / cfg['REAL_F'])
        while s.t < t_max:
            r, act, lp, tt, ov = s.best()
            if s.RC == 0 and s.zone == 1 and 'entry1' not in s.ms and s.t >= 60:
                s.ms['entry1'] = s.t
                s.entry_income.setdefault((0, 1), r)
            s.t += tt + ov
            s.over_time += ov
            zs = s.zstat.setdefault((s.RC, s.zone), [0.0, 0.0, 0, 0.0])
            zs[0] += tt + ov; zs[1] += ov; zs[2] += 1; zs[3] += tt
            s.counts['trips'] += 1
            s.cash += lp * s.pet_layer()
            s.lifetime_lp += lp
            s.ms.setdefault('first_sell', s.t)
            if s.RC >= 1:
                if act[0] != 'click':
                    f = cfg['INTERVIEW_BAR'] if act[0] == 'interview' else 1.0
                    s.add_aura(tt * f / cfg['AURA_BAR_SEC'] * cfg['AURA_BAR'], 'bar')
                s.add_aura((tt + ov) * daily_rate, 'daily')
            res = s.spend()
            if res == 'rebirth' and s.RC >= s.max_reb:
                break
        return s


def simulate(cfg, n=6, payer=None, max_reb=10, t_max=4e5, buy_aura=True, play_h_day=None):
    players = [AuraPlayer(cfg, payer=payer, seed=sd, max_rebirths=max_reb, buy_aura=buy_aura,
                          play_h_day=play_h_day).run(t_max) for sd in range(n)]
    return players


def mean_ms(players, key):
    v = [p.ms[key] for p in players if key in p.ms]
    return statistics.mean(v) if len(v) == len(players) else None


def table(players, upto=10, label=''):
    print('---', label)
    prev = 0.0
    for r in range(1, upto + 1):
        t = mean_ms(players, 'rebirth%d' % r)
        if t is None:
            print('R%d: nie wszyscy doszli' % r)
            break
        sn = [p.snap['rebirth%d' % r] for p in players]
        pre = [p.snap['pre_rebirth%d' % r] for p in players]
        lv = {k: statistics.mean(x['lv'][k] for x in sn) for k in ('click', 'luck', 'gain', 'merge')}
        print('R%-2d łącznie %7s cykl %7s | Aura łącznie %7.0f poziom %5.1f (click %4.1f luck %4.1f gain %4.1f merge %3.1f) | pets x%.0f cloth x%.0f clout %.0f eggs %.0f sekrety %.2f' % (
            r, E.fmt_t(t), E.fmt_t(t - prev), statistics.mean(x['aura_tot'] for x in sn), statistics.mean(x['aura_lvl'] for x in sn),
            lv['click'], lv['luck'], lv['gain'], lv['merge'],
            statistics.mean(x['pets'] for x in pre), statistics.mean(x['cloth'] for x in pre),
            statistics.mean(x['clout'] for x in pre), statistics.mean(x['eggs'] for x in pre),
            statistics.mean(x['secrets'] for x in pre)))
        prev = t
    src = {k: statistics.mean(p.aura_src[k] for p in players) for k in ('reb', 'bar', 'daily')}
    print('  źródła Aury (średnio):', {k: round(v) for k, v in src.items()},
          ' łączenie: prób %.0f, porażek %.0f' % (statistics.mean(p.merge_tries for p in players), statistics.mean(p.merge_fail for p in players)))


def calibrate_fees(cfg, targets, n=6, iters=10, verbose=True, seed0=0):
    """Stroi opłaty Rebirth 2..10 (z Aurą) pod docelowe długości cykli (sekundy symulacji)."""
    players = [AuraPlayer(cfg, seed=seed0 + sd, max_rebirths=1).run() for sd in range(n)]
    out = {}
    for lvl in range(2, cfg['REB_CAP'] + 1):
        base = [copy.deepcopy(p, {id(cfg): cfg}) for p in players]
        tgt = targets[lvl]
        trial = None
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
        sn = [p.snap['rebirth%d' % lvl] for p in trial]
        out[lvl] = dict(cycle=cyc, fee=cfg['REB_FEE'][lvl], t=statistics.mean(p.ms['rebirth%d' % lvl] for p in trial),
                        aura=statistics.mean(x['aura_tot'] for x in sn), lvl=statistics.mean(x['aura_lvl'] for x in sn),
                        click=statistics.mean(x['lv']['click'] for x in sn), luck=statistics.mean(x['lv']['luck'] for x in sn))
        if verbose:
            d = out[lvl]
            print('R%-2d cykl %7s opłata %.3g łącznie %7s | Aura %5.0f poziom %4.1f click %4.1f luck %4.1f' % (
                lvl, E.fmt_t(d['cycle']), d['fee'], E.fmt_t(d['t']), d['aura'], d['lvl'], d['click'], d['luck']), flush=True)
    return out
