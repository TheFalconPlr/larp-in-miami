"""Ostateczne (zaokrąglone) ceny Larp in Miami v2 — źródło prawdy dla arkusza v2.
v1 + sekrety, Aura (sklep), łączenie z szansą, opłaty Rebirth 2–10 przeliczone z Aurą."""
import economy2 as v2


def final_cfg2():
    cfg = v2.v2_cfg()
    cfg['REB_FEE'] = [0, 4e13, 1e14, 5e15, 1.5e16, 4e16, 7.5e16, 1.5e17, 3e17, 5e17, 7.5e17]
    return cfg
