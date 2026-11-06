-- ID gamepassów i produktów za Robuxy (developer products). Ten plik edytujesz ręcznie: gdy utworzysz
-- gamepass albo produkt w Creator Hub (Monetization → Passes / Developer Products), wklej jego ID
-- obok klucza. 0 = jeszcze nie ma: wtedy w trybie testowym przycisk kupna działa bez płacenia (zakup
-- testowy), a zwykły gracz widzi „coming soon”. Ceny, opisy i zawartość są w Economy (Robux), a ceny
-- w UI i tak przychodzą z GetProductInfoAsync (ceny regionalne).

return {
	Gamepasses = {
		AutoSell = 0, -- Auto Sell (599 R$)
		TwoXLP = 0, -- 2x LP (399 R$)
		AutoClick = 0, -- Auto Click (299 R$)
		Verified = 0, -- Verified (299 R$): +10% LP, niebieski znaczek, 15 min 2x LP co dzień
		PetSlots = 0, -- +2 Pet Slots (299 R$)
		DoubleChain = 0, -- drugi łańcuch (199 R$)
		DoubleWrist = 0, -- drugi zegarek (199 R$)
		TripleOpen = 0, -- Buy 3 przy jajkach i boxach (199 R$)
		Teleport = 0, -- teleport do każdej odblokowanej strefy (149 R$)
		TwoXBag = 0, -- 2x Bag (99 R$)
		FastOpen = 0, -- 3× szybsze otwieranie (79 R$)
	},
	Products = {
		PremiumEgg1 = 0, -- 1 premium jajko (99 R$)
		PremiumEgg3 = 0, -- 3 premium jajka (269 R$)
		PremiumEgg10 = 0, -- 10 premium jajek (799 R$)
		StarterPack = 0, -- Starter Pack (79 R$, 72 h od pierwszego wejścia)
		Boost2xLP5 = 0, -- 2x LP na 5 min (19 R$); ten sam produkt jest nagrodą za reklamę
		Boost2xLP15 = 0, -- 2x LP na 15 min (49 R$)
		Boost2xLP60 = 0, -- 2x LP na 60 min (149 R$)
		BoostAutoSell15 = 0, -- Auto-Sell na 15 min (49 R$)
		BoostAutoSell60 = 0, -- Auto-Sell na 60 min (149 R$)
		SellNow = 0, -- sprzedaj Bag od razu, gdziekolwiek jesteś (9 R$)
		DirectPetEpic = 0, -- pet Epic bez losowania (75 R$), tylko dla graczy z ograniczeniem losowań
		DirectPetLegendary = 0, -- pet Legendary bez losowania (149 R$), j.w.
		DirectPetMythic = 0, -- pet Mythic bez losowania (299 R$), j.w.
	},
	-- Reklamy za nagrodę (rewarded video): Placement ID z Creator Hub (Monetization → Ads → Placements),
	-- 0 = bez. Nagrodą jest produkt Economy.Robux.AdReward (Boost2xLP5), więc musi on mieć ID wyżej.
	AdPlacementId = 0,
}
