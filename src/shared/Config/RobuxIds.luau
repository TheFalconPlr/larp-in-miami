-- ID gamepassów i produktów za Robuxy (developer products). Ten plik edytujesz ręcznie: gdy utworzysz
-- gamepass albo produkt w Creator Hub (Monetization → Passes / Developer Products), wklej jego ID
-- obok klucza. 0 = jeszcze nie ma: wtedy w trybie testowym przycisk kupna działa bez płacenia (zakup
-- testowy), a zwykły gracz widzi „coming soon”. Ceny, opisy i zawartość są w Economy (Robux), a ceny
-- w UI i tak przychodzą z GetProductInfoAsync (ceny regionalne).
-- Wszystkie ID wpisane 8.11.2026 (gra grupy Larping Studio$). Gamepassy sprawdzone w API Robloxa:
-- nazwa, cena i właściciel się zgadzają. Produkty utworzone w tej kolejności co tutaj (rosnące ID).

return {
	Gamepasses = {
		AutoSell = 2075680045, -- Auto Sell (599 R$)
		TwoXLP = 2075548057, -- 2x LP (399 R$)
		AutoClick = 2075314122, -- Auto Click (299 R$)
		Verified = 2076250003, -- Verified (299 R$): +10% LP, niebieski znaczek, 15 min 2x LP co dzień
		PetSlots = 2075511960, -- +2 Pet Slots (299 R$)
		DoubleChain = 2074462079, -- drugi łańcuch (199 R$)
		DoubleWrist = 2075194047, -- drugi zegarek (199 R$)
		TripleOpen = 2074348055, -- Buy 3 przy jajkach i boxach (199 R$)
		Teleport = 2074978058, -- teleport do każdej odblokowanej strefy (149 R$)
		TwoXBag = 2074708082, -- 2x Bag (99 R$)
		FastOpen = 2074438026, -- 3× szybsze otwieranie (79 R$)
	},
	Products = {
		PremiumEgg1 = 3729451138, -- 1 premium jajko (99 R$)
		PremiumEgg3 = 3729451492, -- 3 premium jajka (269 R$)
		PremiumEgg10 = 3729451728, -- 10 premium jajek (799 R$)
		StarterPack = 3729452089, -- Starter Pack (79 R$, 72 h od pierwszego wejścia)
		Boost2xLP5 = 3729452296, -- 2x LP na 5 min (19 R$); ten sam produkt jest nagrodą za reklamę
		Boost2xLP15 = 3729452592, -- 2x LP na 15 min (49 R$)
		Boost2xLP60 = 3729452806, -- 2x LP na 60 min (149 R$)
		BoostAutoSell15 = 3729453160, -- Auto-Sell na 15 min (49 R$)
		BoostAutoSell60 = 3729453540, -- Auto-Sell na 60 min (149 R$)
		SellNow = 3729453828, -- sprzedaj Bag od razu, gdziekolwiek jesteś (9 R$)
		DirectPetEpic = 3729454151, -- pet Epic bez losowania (75 R$), tylko dla graczy z ograniczeniem losowań
		DirectPetLegendary = 3729454382, -- pet Legendary bez losowania (149 R$), j.w.
		DirectPetMythic = 3729454685, -- pet Mythic bez losowania (299 R$), j.w.
	},
	-- Reklamy za nagrodę (rewarded video): Placement ID z Creator Hub (Monetization → Ads → Placements),
	-- 0 = bez. Nagrodą jest produkt Economy.Robux.AdReward (Boost2xLP5), więc musi on mieć ID wyżej.
	AdPlacementId = 0,
}
