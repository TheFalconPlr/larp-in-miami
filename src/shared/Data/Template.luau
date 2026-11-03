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
	ActivityTiers = { -- najlepszy kupiony tier aktywności (Etap 4 i 6); 1 = pierwszy, darmowy
		Car = 1,
		Yacht = 1,
		Jet = 0, -- pierwszy odrzutowiec trzeba kupić
	},
	Pets = {}, -- [id jako tekst] = { Zone = strefa jajka, Rarity = "Rare", Level = 0 } (Etap 5)
	Equipped = {}, -- lista id wyposażonych petów
	NextPetId = 1, -- id następnego peta
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
	TestPasses = {}, -- tryb testowy: gamepassy z /pass ([klucz] = true/false); działają tylko u adminów
	Stats = {
		LifetimeLP = 0,
		LifetimeCash = 0,
		Clicks = 0,
		Sells = 0,
		PlaySeconds = 0,
		CarPhotos = 0, -- sesje zdjęciowe z autem (Etap 4)
		Interviews = 0, -- wywiady (Etap 6)
		YachtParties = 0, -- imprezy na jachcie (Etap 6)
		JetFlights = 0, -- loty odrzutowcem (Etap 6)
		EggsOpened = 0, -- otwarte jajka (Etap 5; pierwsze jajko A w strefie 1 daje Rare)
	},
	FirstJoin = 0,
	LastJoin = 0,
}
