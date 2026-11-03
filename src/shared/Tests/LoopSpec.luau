-- Testy pętli: klik, Bag, Sell, Auto-Sell, ulepszenia, strefy, limit kliknięć i zapis liczb w komendach.
-- Uruchamia je ConfigCheck w Studio i tools/test_luau.py poza Roblox.
-- Zwraca funkcję: passed, failed, messages.

local Shared = script.Parent.Parent
local Economy = require(Shared.Config.Economy)
local Formulas = require(Shared.Formulas)
local Format = require(Shared.Format)
local Loop = require(Shared.Logic.Loop)
local RateLimiter = require(Shared.Logic.RateLimiter)
local Template = require(Shared.Data.Template)

local function copy(t)
	local c = {}
	for k, v in pairs(t) do
		if type(v) == "table" then
			c[k] = copy(v)
		else
			c[k] = v
		end
	end
	return c
end

return function()
	local passed, failed, messages = 0, 0, {}

	local function check(cond, msg)
		if cond then
			passed = passed + 1
		else
			failed = failed + 1
			table.insert(messages, "LoopSpec: " .. msg)
		end
	end

	local function near(a, b)
		return math.abs(a - b) <= 1e-9 * math.max(1, math.abs(b))
	end

	local function fresh()
		return copy(Template)
	end

	----------------------------------------------------------------- LP za klik
	local d = fresh()
	local v10 = Formulas.clickValue(10)
	check(Loop.clickLP(d, {}) == 1, "nowy gracz ma 1 LP za klik")
	d.ClickLevel = 10
	check(Loop.clickLP(d, {}) == v10, "poziom 10 daje clickValue(10)")
	check(near(Loop.clickLP(d, { zone = 2 }), v10 * 1.5), "strefa 2 mnoży ×1,5")
	check(near(Loop.clickLP(d, { zone = 5 }), v10 * 250), "strefa 5 mnoży ×250")
	check(near(Loop.clickLP(d, { passes = { TwoXLP = true } }), v10 * 2), "2x LP podwaja")
	check(
		near(Loop.clickLP(d, { passes = { TwoXLP = true, Verified = true } }), v10 * 2.1),
		"2x LP + Verified = ×2,1 (w warstwie dodajemy)"
	)
	check(near(Loop.clickLP(d, { inGroup = true, friends = 5 }), v10 * 1.35), "grupa +5%, znajomi maks. 3 × 10%")
	check(near(Loop.clickLP(d, { boost = true }), v10 * 2), "boost 2x LP")
	d.RebirthLevel = 10
	check(near(Loop.clickLP(d, {}), v10 * 25), "Rebirth 10 mnoży ×25")
	d.AuraUpgrades.ClickBoost = 10
	check(near(Loop.clickLP(d, {}), v10 * 25 * 2), "Click Boost poziom 10 mnoży ×2")

	----------------------------------------------------------------- Bag
	d = fresh()
	check(Loop.capacity(d, {}) == 100, "Bag poziom 0 mieści 100 LP")
	check(Loop.capacity(d, { passes = { TwoXBag = true } }) == 200, "2x Bag mieści 200 LP")
	d.Bag = 99.5
	local added = Loop.collect(d, 5, {})
	check(near(added, 0.5) and d.Bag == 100, "klik zatrzymuje się na pojemności")
	check(Loop.isFull(d, {}), "Bag jest pełny")
	added = Loop.click(d, {})
	check(added == 0 and d.Stats.Clicks == 0, "klik przy pełnym Bag nic nie daje i się nie liczy")
	added = Loop.collect(d, 50, {}, true)
	check(added == 50 and d.Bag == 150, "nagroda z aktywności wchodzi do pełnego Bag")

	----------------------------------------------------------------- Sell
	d = fresh()
	d.Bag = 80
	local gained = Loop.sell(d, {})
	check(gained == 80 and d.Cash == 80 and d.Bag == 0 and d.Stats.Sells == 1, "Sell: 80 LP daje 80 L$")
	check(Loop.sell(d, {}) == 0 and d.Stats.Sells == 1, "pusty Bag nic nie sprzedaje")
	d.Bag = 100
	check(Loop.sell(d, { petLayer = 1.5 }) == 150, "pety mnożą L$ przy Sell")

	----------------------------------------------------------------- Auto-Sell
	d = fresh()
	local ctx = { passes = { AutoSell = true } }
	d.Bag = 99
	local added2, sold = Loop.collect(d, 5, ctx)
	check(added2 == 5 and sold == 104 and d.Bag == 0 and d.Cash == 104, "Auto-Sell sprzedaje pełny Bag bez strat")
	check(not Loop.isFull(d, ctx), "z Auto-Sell Bag nie blokuje kliknięć")
	d.Settings.AutoSell = false
	check(Loop.autoSellOn(d, ctx) == false, "Auto-Sell można wyłączyć w ustawieniach")

	----------------------------------------------------------------- Ulepszenia
	d = fresh()
	d.Cash = 24
	check(Loop.buy(d, "Click", 1) == 0 and d.Cash == 24, "za mało L$ na 1. poziom (25)")
	d.Cash = 25
	local n, spent = Loop.buy(d, "Click", 1)
	check(n == 1 and spent == 25 and d.ClickLevel == 1 and d.Cash == 0, "Kup 1: poziom 1 za 25 L$")
	d.Cash = 1000
	local expectN, expectSpent = 0, 0
	while true do
		local c = Economy.ClickMultiplier.Costs[d.ClickLevel + expectN + 1]
		if c == nil or expectSpent + c > 1000 then
			break
		end
		expectSpent = expectSpent + c
		expectN = expectN + 1
	end
	n, spent = Loop.buy(d, "Click", nil)
	check(
		n == expectN and spent == expectSpent and d.Cash == 1000 - expectSpent and n > 1,
		"Kup max kupuje tyle poziomów, na ile starczy L$"
	)
	d.ClickLevel = Loop.MaxLevel.Click
	d.Cash = 1e30
	check(Loop.nextCost(d, "Click") == nil and Loop.buy(d, "Click", nil) == 0, "Click Multiplier kończy się na 150")
	d = fresh()
	d.Cash = 50
	n = Loop.buy(d, "Bag", 1)
	check(n == 1 and d.BagLevel == 1 and Loop.capacity(d, {}) == 250, "Bag poziom 1 za 50 L$ mieści 250 LP")
	check(Loop.MaxLevel.Bag == 35, "Bag ma 35 poziomów")

	----------------------------------------------------------------- Widok dla HUD
	d = fresh()
	local view = Loop.view(d, {})
	check(
		view.LPPerClick == 1
			and view.NextLPPerClick == 2
			and view.NextClickCost == 25
			and view.BagCapacity == 100
			and view.NextBagCapacity == 250
			and view.BagFull == false,
		"widok dla HUD nowego gracza"
	)

	----------------------------------------------------------------- Strefy
	d = fresh()
	check(Loop.nextZone(d) == Economy.Zones[2], "nowy gracz może kupić strefę 2")
	d.Cash = Economy.Zones[2].Cost - 1
	local bought, why = Loop.buyZone(d, 2)
	check(not bought and why == "NotEnough" and d.ZonesUnlocked == 1, "za mało L$ na strefę 2")
	d.Cash = Economy.Zones[2].Cost
	bought, why = Loop.buyZone(d, 3)
	check(not bought and why == "Locked", "strefy kupuje się po kolei")
	bought = Loop.buyZone(d, 2)
	check(bought and d.ZonesUnlocked == 2 and d.Cash == 0, "strefa 2 kosztuje 6K L$")
	bought, why = Loop.buyZone(d, 2)
	check(not bought and why == "Owned", "kupionej strefy nie kupuje się drugi raz")
	bought, why = Loop.buyZone(d, 9)
	check(not bought and why == "BadRequest", "nie ma strefy 9")
	check(
		Loop.effectiveZone(d, 4) == 2 and Loop.effectiveZone(d, 2) == 2 and Loop.effectiveZone(d, nil) == 1,
		"mnożnik najwyżej z ostatniej odblokowanej strefy"
	)
	check(Loop.view(d, { zone = 2 }).Zone == 2 and Loop.view(d, {}).ZonesUnlocked == 2, "widok ma strefę i odblokowane strefy")
	d.ZonesUnlocked = #Economy.Zones
	check(Loop.nextZone(d) == nil, "po ostatniej strefie nie ma następnej")

	----------------------------------------------------------------- Aktywność: zdjęcia z autem
	local car = Economy.Activities.Car
	d = fresh()
	check(Loop.activityTier(d, "Car") == 1, "nowy gracz ma darmowe auto (tier 1)")
	check(Loop.activityReward(d, {}, "Car") == car.Base, "sesja na poziomie 0 daje bazę (110 LP)")
	check(near(Loop.activityReward(d, { zone = 5 }, "Car"), car.Base), "mnożnik strefy nie działa na aktywności")
	check(near(Loop.activityReward(d, { passes = { TwoXLP = true } }, "Car"), car.Base * 2), "2x LP podwaja nagrodę")
	d.ClickLevel = 10
	check(near(Loop.activityReward(d, {}, "Car"), Formulas.clickValue(10) * car.Base), "nagroda rośnie z Click Multiplierem")
	d.ClickLevel = 0
	local started, reason = Loop.canStartActivity(d, {}, "Car")
	check(not started and reason == "Zone", "bez strefy 2 nie ma zdjęć")
	d.ZonesUnlocked = 2
	check(Loop.canStartActivity(d, {}, "Car"), "w strefie 2 można zacząć")
	d.Bag = Loop.capacity(d, {})
	started, reason = Loop.canStartActivity(d, {}, "Car")
	check(not started and reason == "BagFull", "z pełnym Bag najpierw Sell")
	check(Loop.canStartActivity(d, { passes = { AutoSell = true } }, "Car"), "z Auto-Sell pełny Bag nie blokuje")
	d.Bag = 40
	check(Loop.view(d, {}).Activities.Car.RewardFits == 60, "widok: z nagrody 110 LP zmieści się 60")
	d.Bag = 90
	local reward, added = Loop.finishActivity(d, {}, "Car")
	check(reward == 110 and added == 10 and d.Bag == 100 and d.Stats.CarPhotos == 1, "nagroda wchodzi tylko do pełna Bag")
	d.Bag = 90
	local autoReward, autoAdded, autoSold = Loop.finishActivity(d, { passes = { AutoSell = true } }, "Car")
	check(autoReward == 110 and autoAdded == 110 and autoSold == 200 and d.Bag == 0, "z Auto-Sell cała nagroda się sprzedaje")
	d.Cash = car.Tiers[2].Cost - 1
	local boughtTier, whyTier = Loop.buyActivityTier(d, "Car")
	check(not boughtTier and whyTier == "NotEnough", "za mało L$ na drugie auto")
	d.Cash = car.Tiers[2].Cost
	boughtTier = Loop.buyActivityTier(d, "Car")
	check(boughtTier and Loop.activityTier(d, "Car") == 2 and d.Cash == 0, "drugie auto za 20K L$")
	check(near(Loop.activityReward(d, {}, "Car"), car.Base * car.Tiers[2].Multiplier), "drugie auto mnoży nagrodę ×1,5")
	local carView = Loop.view(d, {}).Activities.Car
	check(carView.Tier == 2 and carView.NextCost == car.Tiers[3].Cost and near(carView.NextReward, car.Base * car.Tiers[3].Multiplier), "widok ma tier, nagrodę i następne auto")
	d.ActivityTiers.Car = #car.Tiers
	boughtTier, whyTier = Loop.buyActivityTier(d, "Car")
	check(not boughtTier and whyTier == "Max" and Loop.view(d, {}).Activities.Car.NextCost == nil, "po najlepszym aucie nie ma następnego")
	d.ZonesUnlocked = 1
	boughtTier, whyTier = Loop.buyActivityTier(d, "Car")
	check(not boughtTier and whyTier == "Zone", "auta kupuje się w kupionej strefie 2")

	----------------------------------------------------------------- Aktywności w strefach 3–5 (Etap 6)
	local interview = Economy.Activities.Interview
	local yacht = Economy.Activities.Yacht
	local jet = Economy.Activities.Jet
	local function fixed(x)
		return function()
			return x
		end
	end
	d = fresh()
	d.ZonesUnlocked = #Economy.Zones
	check(Loop.activityTier(d, "Interview") == 1 and Loop.canStartActivity(d, {}, "Interview"), "wywiad nie ma tierów: od razu dostępny")
	check(Loop.rollGrade("Interview", fixed(0)) == 1 and Loop.rollGrade("Interview", fixed(0.9999)) == #interview.Grades, "ocena: 0 = Flop, prawie 1 = Mega viral")
	check(Loop.rollGrade("Interview", fixed(0.3)) == 2 and Loop.rollGrade("Car", fixed(0.5)) == nil, "ocena z szans w arkuszu, auto bez ocen")
	check(near(Loop.activityReward(d, {}, "Interview"), interview.Base), "nagroda wywiadu przed oceną = ocena Solid (×1)")
	check(near(Loop.activityReward(d, {}, "Interview", #interview.Grades), interview.Base * interview.Grades[#interview.Grades].Multiplier), "Mega viral mnoży nagrodę ×4")
	local interviewView = Loop.view(d, {}).Activities.Interview
	check(near(interviewView.MinReward, interview.Base * interview.Grades[1].Multiplier) and near(interviewView.MaxReward, interview.Base * 4) and interviewView.NextCost == nil, "widok wywiadu: od–do i bez ulepszeń")
	d.Bag = 0
	local gradeReward = Loop.finishActivity(d, {}, "Interview", 3)
	check(near(gradeReward, interview.Base * interview.Grades[3].Multiplier) and d.Stats.Interviews == 1, "koniec wywiadu: nagroda za wylosowaną ocenę")
	check(Loop.activityTier(d, "Yacht") == 1 and near(Loop.activityReward(d, {}, "Yacht"), yacht.Base), "pierwszy jacht za darmo")
	d.ActivityTiers.Yacht = 2
	check(near(Loop.activityReward(d, {}, "Yacht"), yacht.Base * yacht.Tiers[2].Multiplier), "drugi jacht ×2")
	d.ActivityTiers.Jet = 0
	local jetStart, jetWhy = Loop.canStartActivity(d, {}, "Jet")
	check(Loop.activityTier(d, "Jet") == 0 and not jetStart and jetWhy == "Tier", "bez odrzutowca nie ma lotu")
	local jetView = Loop.view(d, {}).Activities.Jet
	check(jetView.Tier == 0 and jetView.Reward == 0 and jetView.NextCost == jet.Tiers[1].Cost, "widok: pierwszy odrzutowiec do kupienia")
	d.Cash = jet.Tiers[1].Cost
	d.Bag = 0
	check(Loop.buyActivityTier(d, "Jet") and Loop.activityTier(d, "Jet") == 1 and d.Cash == 0 and Loop.canStartActivity(d, {}, "Jet"), "pierwszy odrzutowiec za 120B, potem lot")
	check(not Loop.buyActivityTier(d, "Interview"), "wywiadu nie da się ulepszyć")

	----------------------------------------------------------------- Pety i jajka
	local function always(x)
		return function()
			return x
		end
	end
	local eggA1 = Economy.Pets.Eggs[1].A
	d = fresh()
	check(Loop.petSlots(d, {}) == 3, "3 sloty na pety na start")
	d.RebirthLevel = 7
	check(Loop.petSlots(d, { passes = { PetSlots = true } }) == 7, "sloty: +1 R3, +1 R7, +2 gamepass")
	d = fresh()
	local petId, why2 = Loop.openEgg(d, {}, 1, "A", always(0), 250)
	check(petId == nil and why2 == "NotEnough", "jajko bez L$ się nie otwiera")
	d.Cash = eggA1.Price * 10
	local firstId, firstPet = Loop.openEgg(d, {}, 1, "A", always(0), 250)
	check(firstPet.Rarity == "Rare" and d.Cash == eggA1.Price * 9 and d.Stats.EggsOpened == 1, "pierwsze jajko A daje Rare")
	check(d.Equipped[1] == firstId and near(Loop.petLayer(d, {}), 1 + 0.05 * 4), "nowy pet od razu działa: Rare ze strefy 1 = +20% L$")
	local _, secondPet = Loop.openEgg(d, {}, 1, "A", always(0), 250)
	check(secondPet.Rarity == "Common", "losowanie 0 daje najczęstszą rzadkość")
	local _, thirdPet = Loop.openEgg(d, {}, 1, "A", always(0.9999), 250)
	check(thirdPet.Rarity == "Epic", "losowanie bliskie 1 daje najrzadszą rzadkość jajka A")
	local fourthId = Loop.openEgg(d, {}, 1, "A", always(0), 250)
	check(#d.Equipped == 3 and Loop.petCount(d) == 4 and d.Equipped[4] == nil, "czwarty pet nie wchodzi na pełne sloty")
	local equipped, whyEquip = Loop.equipPet(d, {}, fourthId)
	check(not equipped and whyEquip == "SlotsFull", "nie ma wolnego slotu")
	check(Loop.unequipPet(d, d.Equipped[2]) and Loop.equipPet(d, {}, fourthId), "zdejmij jednego, załóż innego")
	Loop.equipBest(d, {})
	check(near(Loop.petLayer(d, {}), 1 + 0.05 * 8 + 0.05 * 4 + 0.05 * 1), "Equip Best: Epic, Rare i Common")
	d.Bag = 100
	check(near(Loop.sell(d, { petLayer = Loop.petLayer(d, {}) }), 100 * Loop.petLayer(d, {})), "pety mnożą L$ przy Sell")
	local nope, whyZone = Loop.openEgg(d, {}, 2, "A", always(0), 250)
	check(nope == nil and whyZone == "Zone", "jajka strefy 2 dopiero po jej kupnie")
	d.Cash = 1e12
	local full, whyFull = Loop.openEgg(d, {}, 1, "A", always(0), 4)
	check(full == nil and whyFull == "Inventory", "pełny ekwipunek")
	check(Loop.eggInfo(1, "Premium") == nil, "jajko premium (za Robux) nie idzie za L$")
	local v = Loop.view(d, {})
	check(v.PetSlots == 3 and v.PetsEquipped == 3 and v.PetCount == 4 and near(v.PetLayer, Loop.petLayer(d, {})), "widok ma pety")
	local withPass = { passes = { PetSlots = true } }
	Loop.equipBest(d, withPass)
	check(#d.Equipped == 4 and #Loop.activePets(d, {}) == 3, "bez gamepassa działają tylko 3 pety")
	local extraOk, extraWhy = Loop.equipPet(d, {}, d.Equipped[4])
	check(not extraOk and extraWhy == "SlotsFull" and #d.Equipped == 3, "nadmiarowy pet spada z listy, sloty pełne")

	-- Triple Open: 3 jajka naraz, tylko gdy stać na wszystkie i wszystkie się zmieszczą
	d = fresh()
	d.Cash = eggA1.Price * 3 - 1
	local none, whyCash = Loop.openEggs(d, {}, 1, "A", 3, always(0), 250)
	check(none == nil and whyCash == "NotEnough" and d.Cash == eggA1.Price * 3 - 1 and Loop.petCount(d) == 0, "3 jajka: brakuje L$ na trzecie, nic się nie dzieje")
	d.Cash = eggA1.Price * 3
	local three = Loop.openEggs(d, {}, 1, "A", 3, always(0), 250)
	check(#three == 3 and d.Cash == 0 and d.Stats.EggsOpened == 3 and three[1].pet.Rarity == "Rare" and three[2].pet.Rarity == "Common", "3 jajka naraz: 3 pety, pierwsze jajko dalej daje Rare")
	check(#d.Equipped == 3 and Loop.isEquipped(d, three[3].id), "3 nowe pety same wchodzą na wolne sloty")
	d.Cash = 1e12
	local noRoom, whyRoom = Loop.openEggs(d, {}, 1, "A", 3, always(0), 5)
	check(noRoom == nil and whyRoom == "Inventory" and Loop.petCount(d) == 3, "3 jajka: brak miejsca na wszystkie")
	local bad, whyBad = Loop.openEggs(d, {}, 1, "A", 1.5, always(0), 250)
	check(bad == nil and whyBad == "BadRequest", "zła liczba jajek")

	-- usuwanie petów: tylko niezałożone i tylko te, które są
	Loop.openEggs(d, {}, 1, "A", 1, always(0), 250)
	Loop.openEggs(d, {}, 1, "A", 1, always(0), 250)
	local loose = {}
	for id in pairs(d.Pets) do
		if not Loop.isEquipped(d, id) then
			table.insert(loose, id)
		end
	end
	local deleted = Loop.deletePets(d, {}, { loose[1], loose[2], d.Equipped[1], "nie-ma" })
	check(deleted == 2 and Loop.petCount(d) == 3 and #d.Equipped == 3, "usuwanie: 2 niezałożone tak, założony i nieistniejący nie")

	----------------------------------------------------------------- Limit kliknięć
	local limiter = RateLimiter.new(10, 10)
	local got = 0
	for _ = 1, 15 do
		got = got + limiter:take(0, 1)
	end
	check(got == 10, "limit: najwyżej 10 kliknięć naraz")
	check(limiter:take(0.5, 10) == 5, "limit: po 0,5 s wraca 5 kliknięć")
	check(limiter:take(10, 100) == 10, "limit: nie zbiera więcej niż 10")

	----------------------------------------------------------------- Liczby w komendach
	check(Format.parse("1.5M") == 1500000, "parse 1.5M")
	check(Format.parse("3t") == 3e12, "parse 3t")
	check(Format.parse("1e12") == 1e12, "parse 1e12")
	check(Format.parse("2.5Qa") == 2.5e15, "parse 2.5Qa")
	check(Format.parse("-100") == -100, "parse -100")
	check(Format.parse("abc") == nil and Format.parse("1.5X") == nil and Format.parse("") == nil, "parse odrzuca złe liczby")
	check(Format.small(1.5) == "1.5" and Format.small(2) == "2" and Format.small(1500) == "1.5K", "zapis małych liczb")

	return passed, failed, messages
end
