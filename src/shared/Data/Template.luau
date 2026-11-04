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
	Pets = {}, -- [id jako tekst] = { Zone = strefa jajka, Rarity = "Rare", Level = 0, Egg = "A" } (Etap 5)
	Equipped = {}, -- lista id wyposażonych petów
	NextPetId = 1, -- id następnego peta
	Index = {}, -- [„strefa:rzadkość”] = true: pety, które gracz już miał (indeks, Etap 7)
	Clothes = {}, -- [id jako tekst] = { Category = "Chain", Rarity = "Rare", Level = 0, Box = "Street" } (Etap 8)
	Worn = {}, -- lista id założonych ubrań (1 na kategorię; Chain i Watch po 2 z gamepassem)
	NextClothId = 1, -- id następnego ubrania
	RebirthLevel = 0, -- poziom Rebirth, czyli mnożnik LP (na premierę maks. 10)
	RebirthCount = 0, -- wszystkie Rebirthy, także po R10 (ranking)
	Aura = 0, -- druga waluta (od Rebirth 1), z ułamkiem; gra pokazuje część całkowitą
	AuraBar = 0, -- pasek Aury: sekundy aktywności do następnych +10 Aury (Etap 9)
	AuraUpgrades = {
		ClickBoost = 0,
		Luck = 0,
		AuraGain = 0,
		MergeLuck = 0,
	},
	Settings = {
		AutoClick = true, -- działa tylko z gamepassem Auto-Click
		AutoSell = true, -- działa tylko z gamepassem Auto-Sell
		ShowClothes = true, -- ubrania z gry widać na awatarze (false = własny wygląd, bonus zostaje)
		HideMenu = false, -- menu po lewej schowane przyciskiem „<” (więcej widać ekranu)
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
		PetsSold = 0, -- sprzedane pety (Etap 7)
		Merges = 0, -- próby łączenia petów
		MergesFailed = 0, -- nieudane łączenia
		SecretsHatched = 0, -- sekretne pety z jajek (ranking „Sekrety” w dokumencie projektu)
		BoxesOpened = 0, -- otwarte boxy z ubraniami (Etap 8)
		UltraSecrets = 0, -- ubrania Ultra Secret z boxa Iced
		ClothesSold = 0, -- sprzedane ubrania
		ClothMerges = 0, -- próby łączenia ubrań
		ClothMergesFailed = 0, -- nieudane łączenia ubrań
		AuraEarned = 0, -- cała zdobyta Aura (Rebirthy, pasek, później zadania)
	},
	FirstJoin = 0,
	LastJoin = 0,
}
