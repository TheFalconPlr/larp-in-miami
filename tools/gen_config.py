"""Generuje src/shared/Config/Economy.luau z modelu ekonomii (tools/economy) i stałych z arkusza v2.

Uruchom z głównego folderu projektu:  python tools/gen_config.py
Nie edytuj Economy.luau ręcznie — zmień liczby tutaj albo w modelu i wygeneruj plik od nowa.
"""
import calendar
import datetime
import math
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, 'economy'))

import economy as e          # noqa: E402
from final_cfg2 import final_cfg2  # noqa: E402

OUT = os.path.join(HERE, '..', 'src', 'shared', 'Config', 'Economy.luau')
VERSION = 'v2 (arkusz z 29.10.2026)'

RAR = {'C': 'Common', 'U': 'Uncommon', 'R': 'Rare', 'E': 'Epic', 'L': 'Legendary', 'M': 'Mythic', 'S': 'Secret',
       'X': 'UltraSecret'}
RAR_ORDER = ['Common', 'Uncommon', 'Rare', 'Epic', 'Legendary', 'Mythic', 'Secret']


def rar_odds(odds):
    return {RAR[k]: odds[k] for k in ['C', 'U', 'R', 'E', 'L', 'M', 'S', 'X'] if k in odds}


# ---------------------------------------------------------------- serializacja Python -> Luau
IDENT = re.compile(r'^[A-Za-z_][A-Za-z0-9_]*$')


class Raw(str):
    """Tekst wstawiany do Luau bez cudzysłowów (np. komentarz)."""


def num(x):
    if isinstance(x, bool):
        return 'true' if x else 'false'
    if isinstance(x, int):
        return str(x)
    if float(x).is_integer() and abs(x) < 1e15:
        return str(int(x))
    r = repr(float(x))
    if 'e' not in r and abs(x) >= 1e15:
        g = '%.15g' % x          # 5000000000000000.0 -> 5e+15
        if float(g) == float(x):
            r = g
    return r


def lua(v, ind=0):
    pad = '\t' * ind
    if isinstance(v, Raw):
        return str(v)
    if isinstance(v, bool) or isinstance(v, (int, float)):
        return num(v)
    if isinstance(v, str):
        return '"' + v.replace('\\', '\\\\').replace('"', '\\"') + '"'
    if v is None:
        return 'nil'
    if isinstance(v, dict):
        if not v:
            return '{}'
        lines = []
        for k, val in v.items():
            if isinstance(k, str) and IDENT.match(k):
                key = k
            else:
                key = '[%s]' % lua(k)
            lines.append('%s\t%s = %s,' % (pad, key, lua(val, ind + 1)))
        return '{\n' + '\n'.join(lines) + '\n' + pad + '}'
    if isinstance(v, (list, tuple)):
        if not v:
            return '{}'
        simple = all(isinstance(x, (int, float, str)) and not isinstance(x, Raw) for x in v)
        if simple and len(v) <= 12:
            return '{ ' + ', '.join(lua(x) for x in v) + ' }'
        if simple:
            rows = []
            for i in range(0, len(v), 10):
                rows.append(pad + '\t' + ', '.join(lua(x) for x in v[i:i + 10]) + ',')
            return '{\n' + '\n'.join(rows) + '\n' + pad + '}'
        return '{\n' + '\n'.join('%s\t%s,' % (pad, lua(x, ind + 1)) for x in v) + '\n' + pad + '}'
    raise TypeError(type(v))


# ---------------------------------------------------------------- dane
def build():
    c = final_cfg2()

    zones_names = {1: 'Downtown Miami', 2: 'Luxury Cars', 3: 'Luxury Mall', 4: 'Miami Beach', 5: 'Private Airport'}
    zones = []
    for z in range(1, 6):
        zones.append({'Id': z, 'Name': zones_names[z], 'Cost': 0 if z == 1 else c['ZONE_COST'][z],
                      'ClickMultiplier': c['ZONE_CLICK'][z], 'WalkBackSeconds': c['WALK'][z]})

    click_costs = [e.clout_cost(c, L) for L in range(1, c['CLOUT_MAX'] + 1)]
    bag_cap = {L: e.bag_capacity(c, L) for L in range(0, 36)}
    bag_cost = {L: e.bag_cost(c, L) for L in range(1, 36)}

    def vehicle(act, names):
        d = c['ACT'][act]
        tiers = []
        for i, nm in enumerate(names):
            tiers.append({'WorkingName': nm, 'Cost': c['TIER_COST'][act][i], 'Multiplier': d['tiers'][i]})
        return {'Zone': d['zone'], 'Base': d['base'], 'DurationSeconds': d['dur'], 'TransitionSeconds': d['over'], 'Tiers': tiers}

    activities = {
        'Car': vehicle('car', ['Kompakt z wypożyczalni', 'Niemiecki sedan', 'Muscle car', 'Włoski supercar', 'Hipercar']),
        'Interview': {
            'Zone': 3, 'Base': c['ACT']['interview']['base'], 'DurationSeconds': c['ACT']['interview']['dur'],
            'TransitionSeconds': c['ACT']['interview']['over'],
            'Grades': [{'Name': 'Flop', 'Multiplier': 0.5, 'Chance': 0.20}, {'Name': 'Solid', 'Multiplier': 1, 'Chance': 0.40},
                       {'Name': 'Viral', 'Multiplier': 2, 'Chance': 0.30}, {'Name': 'Mega viral', 'Multiplier': 4, 'Chance': 0.10}],
        },
        'Yacht': vehicle('yacht', ['Mała motorówka', 'Jacht motorowy', 'Duży jacht', 'Superjacht', 'Megajacht z lądowiskiem']),
        'Jet': vehicle('jet', ['Light jet', 'Midsize jet', 'Ultra long range']),
    }

    eggs = {}
    for z in range(1, 6):
        eggs[z] = {
            'A': {'Price': c['EGG_PRICE'][(z, 'A')], 'Odds': rar_odds(c['EGG_ODDS']['A'])},
            'B': {'Price': c['EGG_PRICE'][(z, 'B')], 'Odds': rar_odds(c['EGG_ODDS']['B'])},
            'Premium': {'Robux': 99, 'Odds': rar_odds(c['PREM_ODDS']), 'LuckApplies': False},
        }

    pets = {
        'RarityOrder': RAR_ORDER,
        'RarityMultiplier': {RAR[k]: v for k, v in c['RAR_MULT'].items()},
        'ZonePower': [c['PET_ZONE'][z] for z in range(1, 6)],
        'Eggs': eggs,
        'Merge': {'ChancePerPiece': c['MERGE_Q'], 'MaxPieces': 5, 'GoldMultiplier': c['MERGE_MULT'],
                  'DiamondMultiplier': c['MERGE_MULT'] ** 2, 'GoldFeeX': c['MERGE_FEE'][0], 'DiamondFeeX': c['MERGE_FEE'][1],
                  'PremiumOnlyAt100': True},
        'Slots': {'Base': c['PET_SLOTS'], 'Rebirth3': 1, 'Rebirth7': 1, 'Gamepass': 2},
        'SellReturn': 0.10, 'GoldSellX': 5, 'DiamondSellX': 25,
        'SecretChance': c['SECRET_P'],
        'FirstEggRarity': 'Rare',
    }

    clothes = {
        'Categories': ['Hair', 'Glasses', 'Chain', 'Watch', 'Shirt', 'Pants', 'Shoes'],
        # rzadkości ubrań od najczęstszej; UltraSecret tylko w boxie Iced (ubrania „chrome”)
        'RarityOrder': ['Common', 'Uncommon', 'Rare', 'Epic', 'Legendary', 'Mythic', 'UltraSecret'],
        'UltraSecretChance': c['ULTRA_P'],
        'RarityBonus': {RAR[k]: v for k, v in c['CLOTH_BONUS'].items()},
        'Boxes': {
            'Street': {'Price': c['BOX_PRICE']['street'], 'RequiresZone': c['BOX_ANCHOR']['street'][0], 'Odds': rar_odds(c['BOX_ODDS']['street'])},
            'Designer': {'Price': c['BOX_PRICE']['designer'], 'RequiresZone': c['BOX_ANCHOR']['designer'][0], 'Odds': rar_odds(c['BOX_ODDS']['designer'])},
            'Iced': {'Price': c['BOX_PRICE']['iced'], 'RequiresZone': c['BOX_ANCHOR']['iced'][0], 'Odds': rar_odds(c['BOX_ODDS']['iced'])},
        },
        'ExtraSlotGamepass': {'Chain': 'DoubleChain', 'Watch': 'DoubleWrist'},
        # box, od którego liczy się cena ubrania danej rzadkości (opłata za łączenie w modelu,
        # e.cloth_source, i sprzedaż: 10% tej ceny); łączenie na tych samych zasadach co pety
        'SourceBox': {RAR[k]: e.cloth_source(k).capitalize() for k in c['CLOTH_BONUS']},
        'SellReturn': 0.10, 'GoldSellX': 5, 'DiamondSellX': 25,
    }

    titles = ['Broke', 'Wannabe', 'Fake Rich', 'Influencer', 'Main Character', 'Self-Made', 'Trust Fund', 'Old Money',
              'Yacht Club', 'Jet Set', 'Certified Larper']
    rebirth = {
        'Cap': c['REB_CAP'],
        'Fees': {L: c['REB_FEE'][L] for L in range(1, c['REB_CAP'] + 1)},
        'LPMultiplier': {L: c['REB_MULT'][L] for L in range(0, c['REB_CAP'] + 1)},
        'WalkSpeedPerLevel': c['REB_SPEED'],
        'PostCapFeeGrowth': c['POST_CAP_G'] - 1,
        'Titles': {L: titles[L] for L in range(0, c['REB_CAP'] + 1)},
        'TeleportToSpawn': True,
    }

    U = c['UPG']
    aura = {
        'UnlockAtRebirth': 1,
        'RebirthReward': c['AURA_REB'],
        'PostCapReward': c['AURA_REB'] * c['REB_CAP'],
        'BarSeconds': c['AURA_BAR_SEC'], 'BarReward': c['AURA_BAR'], 'InterviewBarMultiplier': c['INTERVIEW_BAR'],
        'DailyQuestReward': 10, 'DailyAllQuestsBonus': 20,
        'Upgrades': {
            'ClickBoost': {'Effect': U['click']['eff'], 'BaseCost': U['click']['c0'], 'Growth': round(U['click']['g'] - 1, 6)},
            'Luck': {'Effect': U['luck']['eff'], 'BaseCost': U['luck']['c0'], 'Growth': round(U['luck']['g'] - 1, 6)},
            'AuraGain': {'Effect': U['gain']['eff'], 'BaseCost': U['gain']['c0'], 'Growth': round(U['gain']['g'] - 1, 6)},
            'MergeLuck': {'Effect': c['MERGE_UPG']['eff'], 'Costs': c['MERGE_UPG']['costs']},
        },
        'Glow': [{'Level': 10, 'Color': 'White'}, {'Level': 25, 'Color': 'Blue'}, {'Level': 50, 'Color': 'Purple'},
                 {'Level': 75, 'Color': 'Gold'}, {'Level': 100, 'Color': 'Red'}, {'Level': 150, 'Color': 'Rainbow'}],
    }

    # Robux (Etap 10). ID gamepassów i produktów są w src/shared/Config/RobuxIds.luau (ręczny plik),
    # bo ten plik jest generowany. Ceny tutaj to tylko zapas: UI bierze ceny z GetProductInfoAsync
    # (ceny regionalne). Nic za Robuxy nie daje L$, Aury ani niczego losowego poza premium jajkami.
    prem = rar_odds(c['PREM_ODDS'])
    rm = pets['RarityMultiplier']
    ev = sum(p * rm[r] for r, p in prem.items())  # średnia moc premium jajka (w mocach Epic = 8)
    # Gracze z ograniczeniem płatnych losowań (PolicyService) kupują konkretnego peta zamiast jajka.
    # Cena według wartości oczekiwanej: jajko 99 R$ = średnia moc, więc pet kosztuje 99 × moc / średnia
    # (75,6 / 151,1 / 302,3 R$), zaokrąglone w dół do zwykłych cen Roblox.
    direct = {}
    for rarity, nice in (('Epic', 75), ('Legendary', 149), ('Mythic', 299)):
        exact = 99 * rm[rarity] / ev
        assert nice <= exact and nice >= exact * 0.95, (rarity, exact)
        direct['DirectPet' + rarity] = {'Price': nice, 'Rarity': rarity}
    robux = {
        'Gamepasses': {
            'AutoSell': {'Price': 599},
            'TwoXLP': {'Price': 399, 'LPBonus': 1.0},
            'AutoClick': {'Price': 299, 'ClicksPerSecond': c['AUTO_K']},
            'Verified': {'Price': 299, 'LPBonus': 0.10, 'DailyBoostMinutes': 15},
            'PetSlots': {'Price': 299, 'ExtraSlots': 2},
            'DoubleChain': {'Price': 199},
            'DoubleWrist': {'Price': 199},
            'TripleOpen': {'Price': 199, 'OpenCount': 3},
            'Teleport': {'Price': 149},
            'TwoXBag': {'Price': 99, 'CapacityX': 2},
            'FastOpen': {'Price': 79, 'OpenTimeX': round(1 / 3, 6)},
        },
        'Products': dict({
            'PremiumEgg1': {'Price': 99, 'Count': 1},
            'PremiumEgg3': {'Price': 269, 'Count': 3},
            'PremiumEgg10': {'Price': 799, 'Count': 10},
            # Starter Pack: przez 72 h od pierwszego wejścia, raz na konto. Same pewne rzeczy:
            # zegarek Rare (kupiony za Robuxy, więc łączy się tylko przy 100%), pet Epic z najwyższej
            # odblokowanej strefy i boosty 2x LP oraz Auto-Sell po 30 minut.
            'StarterPack': {'Price': 79, 'HoursAvailable': 72, 'Watch': 'Rare', 'PetRarity': 'Epic',
                            'BoostMinutes': 30, 'AutoSellMinutes': 30},
            # 2x LP na 5 minut: też nagroda za reklamę (rewarded video, najwyżej 5 dziennie)
            'Boost2xLP5': {'Price': 19, 'Minutes': 5},
            'Boost2xLP15': {'Price': 49, 'Minutes': 15},
            'Boost2xLP60': {'Price': 149, 'Minutes': 60},
            'BoostAutoSell15': {'Price': 49, 'Minutes': 15},
            'BoostAutoSell60': {'Price': 149, 'Minutes': 60},
            'SellNow': {'Price': 9},
        }, **direct),
        'AdReward': 'Boost2xLP5',
        'Note': 'Ceny w UI zawsze z MarketplaceService:GetProductInfoAsync. ID są w Config/RobuxIds.',
    }

    # Nagrody (Etap 11): Label to opis z dokumentu projektu, a Items to to, co gra naprawdę daje
    # (Shared/Logic/Rewards). Strefę dobiera gra: jajko A albo B z najwyższej odblokowanej strefy,
    # box „Best” = najlepszy odblokowany (przed strefą 3 Street), premium jajko z najwyższej strefy.
    def boost(minutes, kind='LP'):
        return {'Kind': 'Boost', 'Boost': kind, 'Minutes': minutes}

    def eggs(egg, count):
        return {'Kind': 'Egg', 'Egg': egg, 'Count': count}

    def boxes(count):
        return {'Kind': 'Box', 'Box': 'Best', 'Count': count}

    def premium(count):
        return {'Kind': 'PremiumEgg', 'Count': count}

    def reward(label, *items, ends=None):
        r = {'Label': label, 'Items': list(items)}
        if ends is not None:
            # ends = ostatni dzień kodu ('2026-12-31'): działa do północy UTC po tym dniu
            day = datetime.date.fromisoformat(ends) + datetime.timedelta(days=1)
            r['Ends'] = calendar.timegm(day.timetuple())
        return r

    rewards = {
        'DailyStreak': [
            reward('Boost 2x LP 10 min', boost(10)),
            reward('3x jajko A', eggs('A', 3)),
            reward('2x najlepszy box', boxes(2)),
            reward('Boost 2x LP 30 min', boost(30)),
            reward('3x jajko B', eggs('B', 3)),
            reward('2x najlepszy box + Auto-Sell 15 min', boxes(2), boost(15, 'AutoSell')),
            reward('1x premium jajko + boost 2x LP 30 min', premium(1), boost(30)),
        ],
        'DailyQuests': [
            {'Key': 'CarPhotos', 'Target': 25, 'Reward': reward('2x jajko A', eggs('A', 2))},
            {'Key': 'Interviews', 'Target': 5, 'Reward': reward('1x box', boxes(1))},
            {'Key': 'YachtSessions', 'Target': 5, 'Reward': reward('2x jajko B', eggs('B', 2))},
            {'Key': 'JetRentals', 'Target': 3, 'Reward': reward('1x box', boxes(1))},
            {'Key': 'Sells', 'Target': 10, 'Reward': reward('Boost 2x LP 15 min', boost(15))},
            {'Key': 'EggsOpened', 'Target': 10, 'Reward': reward('1x box', boxes(1))},
            {'Key': 'Clicks', 'Target': 500, 'Reward': reward('2x jajko A', eggs('A', 2))},
            {'Key': 'Merges', 'Target': 1, 'Reward': reward('Boost 2x LP 15 min', boost(15))},
        ],
        'QuestsPerDay': 3,
        # Kody wpisuje się w budce z kodami (każdy raz na konto). Nagrody za progi polubień też są
        # kodami (LIKES1K…): dostaje je każdy, kto wpisze kod, a nie tylko ci, którzy polubili grę.
        # Kod z końcem ważności: reward('…', boost(30), ends='2026-12-31'). Nazwa: wielkie litery i cyfry.
        'Codes': {
            'LARPINMIAMI': reward('Boost 2x LP 15 min', boost(15)),
            'SECURETHEBAG': reward('3x jajko A', eggs('A', 3)),
            'LIKES1K': reward('Boost 2x LP 30 min', boost(30)),
        },
    }

    bonuses = {'Group': 0.05, 'FriendEach': 0.10, 'FriendMax': 3, 'RewardedVideoDailyMax': 5, 'BoostX': 2}

    return {
        'Version': VERSION,
        'TeleportToSellSeconds': c['TELEPORT'],
        'WalkSpeed': 16,
        'OpenTimeSeconds': c['OPEN_TIME'],
        'Zones': zones,
        'ClickMultiplier': {'MaxLevel': c['CLOUT_MAX'], 'Costs': click_costs,
                            'Formula': 'LP za klik = ZAOKR(1 + poziom + 0,1 x poziom^2)'},
        'Bag': {'Capacity': bag_cap, 'Costs': bag_cost},
        'Activities': activities,
        'Pets': pets,
        'Clothes': clothes,
        'Rebirth': rebirth,
        'Aura': aura,
        'Robux': robux,
        'Rewards': rewards,
        'Bonuses': bonuses,
    }


def main():
    data = build()
    header = ('-- Larp in Miami — ekonomia %s\n'
              '-- WYGENEROWANE przez tools/gen_config.py z modelu ekonomii (tools/economy). Nie edytuj ręcznie.\n'
              '-- Wszystkie kwoty w L$, chyba że klucz mówi inaczej (Robux, Price w R$).\n\n' % VERSION)
    body = 'local Economy = ' + lua(data) + '\n\nreturn Economy\n'
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, 'w', encoding='utf-8', newline='\n') as f:
        f.write(header + body)
    print('zapisano', os.path.normpath(OUT))


if __name__ == '__main__':
    main()
