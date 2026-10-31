"""Test modułów Luau poza Roblox (Lua 5.1 przez bibliotekę lupa): pip install lupa

Sprawdza:
  1. czy wszystkie pliki .luau się kompilują (kod piszemy w podzbiorze zgodnym z Lua 5.1, więc to też poprawny Luau),
  2. ConfigSpec (te same testy, które w Studio uruchamia ConfigCheck),
  3. zgodność wzorów z modelem ekonomii w Pythonie (koszty Aury, LP za klik, szanse, ceny),
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

import economy2 as v2            # noqa: E402
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
    local node = { Name = name, __path = path, Parent = parent }
    return node
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
''')
make_node = lua.globals().make_node
shared_dir = os.path.join(SRC, 'shared')
Shared = make_node('Shared', None, None)
Config = make_node('Config', None, Shared)
Tests = make_node('Tests', None, Shared)
Shared.Config = Config
Shared.Tests = Tests
Config.Economy = make_node('Economy', os.path.join(shared_dir, 'Config', 'Economy.luau'), Config)
Shared.Format = make_node('Format', os.path.join(shared_dir, 'Format.luau'), Shared)
Shared.Formulas = make_node('Formulas', os.path.join(shared_dir, 'Formulas.luau'), Shared)
Tests.ConfigSpec = make_node('ConfigSpec', os.path.join(shared_dir, 'Tests', 'ConfigSpec.luau'), Tests)

req = lua.globals().require
Economy = req(Config.Economy)
Format = req(Shared.Format)
Formulas = req(Shared.Formulas)
spec = req(Tests.ConfigSpec)
passed, failed, messages = spec(Economy, Formulas, Format)
for i in range(1, (len(messages) if messages else 0) + 1):
    fails.append('ConfigSpec: ' + messages[i])
print('ConfigSpec: %d OK, %d błędów' % (passed, failed))

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
names = {'C': 'Common', 'U': 'Uncommon', 'R': 'Rare', 'E': 'Epic', 'L': 'Legendary', 'M': 'Mythic', 'S': 'Secret'}
odds_b = Economy.Pets.Eggs[5].B.Odds
for lam in (1.0, 1.25, 1.5, 2.0, 2.35, 3.0, 4.5):
    py = v2.eff_odds(cfg['EGG_ODDS']['B'], lam)
    lu = Formulas.effectiveOdds(odds_b, lam)
    for k, p in py.items():
        ok(abs(lu[names[k]] - p) < 1e-12, 'szanse B przy szczęściu %.2f, %s' % (lam, names[k]))
for L in range(1, 11):
    ok(Formulas.rebirthFee(L) == cfg['REB_FEE'][L], 'opłata R%d' % L)
fees = {1: '40T', 2: '100T', 3: '5Qa', 4: '15Qa', 5: '40Qa', 6: '75Qa', 7: '150Qa', 8: '300Qa', 9: '500Qa', 10: '750Qa'}
for L, s in fees.items():
    ok(Format.number(cfg['REB_FEE'][L]) == s, 'zapis opłaty R%d: %s' % (L, Format.number(cfg['REB_FEE'][L])))

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
