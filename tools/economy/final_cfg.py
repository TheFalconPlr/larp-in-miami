"""Ostateczne (zaokrąglone) ceny Larp in Miami — źródło prawdy dla arkusza."""
import economy as e


def final_cfg():
    cfg = e.default_cfg()
    cfg['PET_ZONE'] = {1: 0.05, 2: 0.12, 3: 0.30, 4: 0.75, 5: 2.0}
    cfg['ZONE_COST'] = {2: 6e3, 3: 8e5, 4: 1.5e8, 5: 3e12}
    cfg['TIER_COST'] = {'car': [0, 2e4, 5e4, 1e5, 2e5],
                        'yacht': [0, 4e8, 1.5e9, 4e9, 8e9],
                        'jet': [1.2e11, 1e12, 4e12]}
    cfg['EGG_PRICE'] = {(1, 'A'): 400, (1, 'B'): 2e3, (2, 'A'): 6e3, (2, 'B'): 4e4,
                        (3, 'A'): 1e6, (3, 'B'): 5e6, (4, 'A'): 6e7, (4, 'B'): 4e8,
                        (5, 'A'): 3e10, (5, 'B'): 2e11}
    cfg['BOX_PRICE'] = {'street': 2.5e6, 'designer': 2e8, 'iced': 8e10}
    cfg['REB_FEE'] = [0, 4e13, 4e14, 5e15, 1e16, 2e16, 3e16, 5e16, 1e17, 1.5e17, 2e17]
    return cfg
