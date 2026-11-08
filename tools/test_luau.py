"""Test modułów Luau poza Roblox (Lua 5.1 przez bibliotekę lupa): pip install lupa

Sprawdza:
  1. czy wszystkie pliki .luau się kompilują (nasz kod piszemy w podzbiorze zgodnym z Lua 5.1,
     więc to też poprawny Luau; biblioteki z folderów Vendor pomijamy, bo używają pełnego Luau),
  2. ConfigSpec, LoopSpec, ClothesSpec, InterviewSpec, RebirthSpec, ShopSpec i RewardsSpec (te same testy, które w Studio
     uruchamia ConfigCheck),
  3. zgodność wzorów i pętli z modelem ekonomii w Pythonie (koszty, LP za klik, Bag, szanse, ceny,
     warstwy petów i ubrań),
  4. losowanie ze szczęściem (Monte Carlo) względem wzoru na szanse.
Uruchom z głównego folderu projektu:  python tools/test_luau.py
"""
import os
import random
import sys

from lupa import lua51

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, '..'))
sys.path.insert(0, os.path.join(HERE, 'economy'))

import economy as E                # noqa: E402
import economy2 as v2              # noqa: E402
from final_cfg2 import final_cfg2  # noqa: E402

SRC = os.path.join(ROOT, 'src')
lua = lua51.LuaRuntime(unpack_returned_tuples=True)

fails = []


def ok(cond, msg):
    if not cond:
        fails.append(msg)


# ---------------------------------------------------------------- 1. kompilacja
files = []
for dp, dn, fn in os.walk(SRC):
    if 'Vendor' in os.path.relpath(dp, SRC).split(os.sep):
        continue
    for f in fn:
        if f.endswith('.luau'):
            files.append(os.path.join(dp, f))
compile_check = lua.eval('function(src, name) local f, err = loadstring(src, name); return err end')
for p in sorted(files):
    with open(p, encoding='utf-8') as fh:
        err = compile_check(fh.read(), os.path.relpath(p, ROOT))
    ok(err is None, 'kompilacja %s: %s' % (os.path.relpath(p, ROOT), err))
print('kompilacja: %d plików' % len(files))


# ---------------------------------------------------------------- 2. moduły z atrapą script/require
def read_src(path):
    with open(path, encoding='utf-8') as fh:
        return fh.read()


lua.globals().py_read = read_src
lua.execute('''
local cache = {}
function make_node(name, path, parent)
    return { Name = name, __path = path, Parent = parent }
end
function require(mod)
    local p = rawget(mod, "__path")
    if cache[p] then return cache[p] end
    local src = py_read(p)
    local chunk, err = loadstring("return function(script)\\n" .. src .. "\\nend", "@" .. p)
    if not chunk then error(err) end
    local result = chunk()(mod)
    cache[p] = result
    return result
end
function deep_copy(t)
    local c = {}
    for k, v in pairs(t) do
        if type(v) == "table" then c[k] = deep_copy(v) else c[k] = v end
    end
    return c
end
''')
make_node = lua.globals().make_node
req = lua.globals().require
deep_copy = lua.globals().deep_copy


def build_tree(path, name, parent):
    """Folder -> węzeł z dziećmi (jak w Roblox: script.Parent.Config.Economy)."""
    node = make_node(name, None, parent)
    for entry in sorted(os.listdir(path)):
        full = os.path.join(path, entry)
        if os.path.isdir(full):
            node[entry] = build_tree(full, entry, node)
        elif entry.endswith('.luau'):
            stem = entry[:-len('.luau')]
            for suffix in ('.server', '.client'):
                if stem.endswith(suffix):
                    stem = stem[:-len(suffix)]
            node[stem] = make_node(stem, full, node)
    return node


Shared = build_tree(os.path.join(SRC, 'shared'), 'Shared', None)
Economy = req(Shared.Config.Economy)
Format = req(Shared.Format)
Formulas = req(Shared.Formulas)
Loop = req(Shared.Logic.Loop)
Clothes = req(Shared.Logic.Clothes)
Template = req(Shared.Data.Template)


def run_spec(name, result):
    passed, failed, messages = result
    for i in range(1, (len(messages) if messages else 0) + 1):
        fails.append(messages[i])
    print('%s: %d OK, %d błędów' % (name, passed, failed))


run_spec('ConfigSpec', req(Shared.Tests.ConfigSpec)(Economy, Formulas, Format))
run_spec('LoopSpec', req(Shared.Tests.LoopSpec)())
run_spec('ClothesSpec', req(Shared.Tests.ClothesSpec)())
run_spec('InterviewSpec', req(Shared.Tests.InterviewSpec)())
run_spec('RebirthSpec', req(Shared.Tests.RebirthSpec)())
run_spec('ShopSpec', req(Shared.Tests.ShopSpec)())
run_spec('RewardsSpec', req(Shared.Tests.RewardsSpec)())

# ---------------------------------------------------------------- 3. zgodność z modelem w Pythonie
cfg = final_cfg2()
for key, pk in (('ClickBoost', 'click'), ('Luck', 'luck'), ('AuraGain', 'gain')):
    for L in range(1, 101):
        a = Formulas.auraUpgradeCost(key, L)
        b = v2.upg_cost(cfg, pk, L)
        ok(abs(a - b) <= 1e-6 * max(1, b), 'koszt %s poz. %d: Luau %s, Python %s' % (key, L, a, b))
for L in range(0, 151):
    x = 1 + L + 0.1 * L * L
    expected = int(x + 0.5 + 1e-9)          # ZAOKR jak w arkuszu (połówki w górę)
    ok(Formulas.clickValue(L) == expected, 'LP za klik poz. %d' % L)
for z in range(1, 6):
    for egg in ('A', 'B'):
        ok(Economy.Pets.Eggs[z][egg].Price == cfg['EGG_PRICE'][(z, egg)], 'cena jajka %d%s' % (z, egg))
names = {'C': 'Common', 'U': 'Uncommon', 'R': 'Rare', 'E': 'Epic', 'L': 'Legendary', 'M': 'Mythic', 'S': 'Secret',
         'X': 'UltraSecret'}
odds_b = Economy.Pets.Eggs[5].B.Odds
for lam in (1.0, 1.25, 1.5, 2.0, 2.35, 3.0, 4.5):
    py = v2.eff_odds(cfg['EGG_ODDS']['B'], lam)
    lu = Formulas.effectiveOdds(odds_b, lam)
    for k, p in py.items():
        ok(abs(lu[names[k]] - p) < 1e-12, 'szanse B przy szczęściu %.2f, %s' % (lam, names[k]))
for L in range(1, 11):
    ok(Formulas.rebirthFee(L) == cfg['REB_FEE'][L], 'opłata R%d' % L)
# po R10 (Etap 9): opłata +25% za każdy kolejny, Aura 100 × poziom (po limicie 100 × 10), jak w modelu
for n in range(1, 21):
    cap = cfg['REB_CAP']
    py_fee = cfg['REB_FEE'][n] if n <= cap else cfg['REB_FEE'][cap] * cfg['POST_CAP_G'] ** (n - cap)
    ok(abs(Formulas.rebirthFee(n) - py_fee) <= 1e-9 * py_fee, 'opłata za Rebirth nr %d' % n)
    ok(Formulas.rebirthAura(n) == cfg['AURA_REB'] * min(n, cap), 'Aura za Rebirth nr %d' % n)
fees = {1: '40T', 2: '100T', 3: '5Qa', 4: '15Qa', 5: '40Qa', 6: '75Qa', 7: '150Qa', 8: '300Qa', 9: '500Qa', 10: '750Qa'}
for L, s in fees.items():
    ok(Format.number(cfg['REB_FEE'][L]) == s, 'zapis opłaty R%d: %s' % (L, Format.number(cfg['REB_FEE'][L])))

# Pętla: LP za klik i Bag tak jak w modelu (economy.py: cp × K × ZONE_CLICK × lp_mult, v2: × Click Boost)
payer_lp = {'free': 1.0, '2xLP': 2.0, 'all': 2.1}
payer_passes = {'free': {}, '2xLP': {'TwoXLP': True}, 'all': {'TwoXLP': True, 'Verified': True}}
for L in (0, 1, 7, 33, 90, 150):
    for z in range(1, 6):
        for R in (0, 3, 10):
            for cb in (0, 5, 40):
                for payer in ('free', '2xLP', 'all'):
                    d = deep_copy(Template)
                    d.ClickLevel = L
                    d.RebirthLevel = R
                    d.AuraUpgrades.ClickBoost = cb
                    ctx = lua.table_from({'zone': z, 'passes': lua.table_from(payer_passes[payer])})
                    got = Loop.clickLP(d, ctx)
                    exp = (E.clout_value(L) * (1 + 0.1 * cb) * cfg['ZONE_CLICK'][z]
                           * cfg['REB_MULT'][R] * payer_lp[payer])
                    ok(abs(got - exp) <= 1e-9 * max(1, exp),
                       'LP za klik L=%d strefa %d R%d boost %d %s: Luau %s, model %s' % (L, z, R, cb, payer, got, exp))
for L in range(0, 36):
    ok(Loop.capacityAt(L, lua.table_from({})) == E.bag_capacity(cfg, L), 'pojemność Bag poz. %d' % L)
for L in range(1, 151):
    ok(Loop.levelCost('Click', L) == E.clout_cost(cfg, L), 'koszt Click Multipliera poz. %d' % L)
for L in range(1, 36):
    ok(Loop.levelCost('Bag', L) == E.bag_cost(cfg, L), 'koszt Bag poz. %d' % L)
rng = random.Random(3)
for _ in range(300):
    kind = rng.choice(['Click', 'Bag'])
    max_level = 150 if kind == 'Click' else 35
    start = rng.randint(0, max_level)
    cash = 10 ** rng.uniform(0, 19)
    count, total = Loop.affordable(kind, start, cash)
    c, t = 0, 0.0
    while start + c < max_level:
        cost = (E.clout_cost if kind == 'Click' else E.bag_cost)(cfg, start + c + 1)
        if t + cost > cash:
            break
        t += cost
        c += 1
    ok(count == c and abs(total - t) <= 1e-9 * max(1, t), 'Kup max %s od poz. %d za %s' % (kind, start, cash))

# Warstwy petów i ubrań jak w modelu (etap 4 w dokumencie: „mnożniki z petów i ubrań zgadzają się
# z arkuszem”). Losowe ekwipunki: model bierze najlepsze na sloty, a my EQUIP BEST / WEAR BEST.
RARS = ['C', 'U', 'R', 'E', 'L', 'M', 'S']
rng = random.Random(11)
for trial in range(200):
    R = rng.choice([0, 3, 7, 10])
    pet_pass = rng.random() < 0.5
    extra = rng.random() < 0.5
    payer = {'pet_slots': 2 if pet_pass else 0, 'extra_cloth': ('chain', 'watch') if extra else ()}
    p = E.Player(cfg, payer=payer)
    p.R = R
    d = deep_copy(Template)
    d.RebirthLevel = R
    passes = {}
    if pet_pass:
        passes['PetSlots'] = True
    if extra:
        passes['DoubleChain'] = True
        passes['DoubleWrist'] = True
    ctx = lua.table_from({'passes': lua.table_from(passes)})
    pets, clothes = {}, {}
    for i in range(rng.randint(0, 14)):
        key = (rng.randint(1, 5), rng.choice(['A', 'B']), rng.choice(RARS), rng.choice([0, 0, 0, 1, 2]))
        pets[key] = pets.get(key, 0) + 1
        d.Pets['p%d' % i] = lua.table_from({'Zone': key[0], 'Rarity': names[key[2]], 'Level': key[3], 'Egg': key[1]})
    for i in range(rng.randint(0, 14)):
        key = (rng.choice(E.CATS), rng.choice(RARS[:6] + ['X']), rng.choice([0, 0, 0, 1, 2]))
        clothes[key] = clothes.get(key, 0) + 1
        d.Clothes['c%d' % i] = lua.table_from({'Category': key[0].capitalize(), 'Rarity': names[key[1]], 'Level': key[2], 'Box': 'Street'})
    p.pets, p.clothes = pets, clothes
    p._pl, p._cl = None, None
    Loop.equipBest(d, ctx)
    Clothes.wearBest(d, ctx)
    got_p, exp_p = Loop.petLayer(d, ctx), p.pet_layer()
    got_c, exp_c = Clothes.layer(d, ctx), p.cloth_layer()
    ok(abs(got_p - exp_p) <= 1e-9 * max(1, exp_p), 'warstwa petów (próba %d): Luau %s, model %s' % (trial, got_p, exp_p))
    ok(abs(got_c - exp_c) <= 1e-9 * max(1, exp_c), 'warstwa ubrań (próba %d): Luau %s, model %s' % (trial, got_c, exp_c))
for rar in RARS[:6] + ['X']:
    for lvl in (0, 1):
        key_fee = cfg['BOX_PRICE'][E.cloth_source(rar)] * cfg['MERGE_FEE'][lvl]
        d = deep_copy(Template)
        ids = []
        for i in range(5):
            d.Clothes['m%d' % i] = lua.table_from({'Category': 'Chain', 'Rarity': names[rar], 'Level': lvl, 'Box': 'Street'})
            ids.append('m%d' % i)
        info = Clothes.mergeInfo(d, lua.table_from(ids))
        ok(info.Fee == key_fee, 'opłata za łączenie 5 ubrań %s poz. %d: Luau %s, model %s' % (rar, lvl, info.Fee, key_fee))
print('warstwy petów i ubrań: 200 losowych ekwipunków zgodnych z modelem')

# ---------------------------------------------------------------- 4. losowanie ze szczęściem
rng = random.Random(7)
rand01 = lambda: rng.random()  # noqa: E731
N = 200000
for lam in (1.0, 2.0, 2.5):
    counts = {}
    for _ in range(N):
        r = Formulas.roll(odds_b, lam, rand01)
        counts[r] = counts.get(r, 0) + 1
    eff = Formulas.effectiveOdds(odds_b, lam)
    for rar in ('Uncommon', 'Rare', 'Epic', 'Legendary'):
        p = eff[rar]
        got = counts.get(rar, 0) / N
        sd = (p * (1 - p) / N) ** 0.5
        ok(abs(got - p) < 5 * sd + 1e-9, 'losowanie %s przy szczęściu %.1f: %.5f vs %.5f' % (rar, lam, got, p))
print('losowanie: %d prób na każde szczęście' % N)

if fails:
    print('\nBŁĘDY (%d):' % len(fails))
    for f in fails[:40]:
        print(' -', f)
    sys.exit(1)
print('\nWszystko OK')
