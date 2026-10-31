-- Szablon zapisu gracza (ProfileStore). Tak wygląda zapis nowego gracza.
-- Nowe pola można dodawać śmiało: Reconcile() dopisze je starym graczom przy wejściu.
-- Zmiana znaczenia istniejącego pola wymaga migracji: podbij Version i dopisz krok w DataService.

return {
	Version = 1,
	Cash = 0, -- L$
	Bag = 0, -- LP w Bag
	ClickLevel = 0, -- poziom Click Multipliera
	BagLevel = 0, -- poziom Bag
	ZonesUnlocked = 1, -- najwyższa odblokowana strefa (Etap 3)
	RebirthLevel = 0, -- poziom Rebirth, czyli mnożnik LP (na premierę maks. 10)
	RebirthCount = 0, -- wszystkie Rebirthy, także po R10 (ranking)
	Aura = 0,
	AuraUpgrades = {
		ClickBoost = 0,
		Luck = 0,
		AuraGain = 0,
		MergeLuck = 0,
	},
	Settings = {
		AutoClick = true, -- działa tylko z gamepassem Auto-Click
		AutoSell = true, -- działa tylko z gamepassem Auto-Sell
	},
	Stats = {
		LifetimeLP = 0,
		LifetimeCash = 0,
		Clicks = 0,
		Sells = 0,
		PlaySeconds = 0,
	},
	FirstJoin = 0,
	LastJoin = 0,
}
