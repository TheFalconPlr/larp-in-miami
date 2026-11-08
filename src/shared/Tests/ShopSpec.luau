-- Testy zakupów za Robuxy (Etap 10): paragony, boosty, Verified, reklamy, Starter Pack, premium jajka
-- (stałe szanse), pety bez losowania dla graczy z ograniczeniem i sprawdzanie przed oknem zakupu.
-- Uruchamia je ConfigCheck w Studio i tools/test_luau.py poza Roblox. Zwraca funkcję: passed, failed, messages.

local Shared = script.Parent.Parent
local Economy = require(Shared.Config.Economy)
local Loop = require(Shared.Logic.Loop)
local Clothes = require(Shared.Logic.Clothes)
local Shop = require(Shared.Logic.Shop)
local Robux = require(Shared.Robux)
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

-- Prosty, powtarzalny generator liczb z [0, 1) (LCG), żeby wyniki testów były zawsze te same.
local function lcg(seed)
	local state = seed
	return function()
		state = (state * 1103515245 + 12345) % 2147483648
		return state / 2147483648
	end
end

return function()
	local passed, failed, messages = 0, 0, {}

	local function check(cond, msg)
		if cond then
			passed = passed + 1
		else
			failed = failed + 1
			table.insert(messages, msg)
		end
	end

	local NOW = 1800000000 -- stały „teraz” (sekundy UTC)

	local function fresh()
		local d = copy(Template)
		d.FirstJoin = NOW - 3600
		return d
	end

	------------------------------------------------------------- Config
	local products = Economy.Robux.Products
	local passCount, passTotal = 0, 0
	for _, info in pairs(Economy.Robux.Gamepasses) do
		passCount = passCount + 1
		passTotal = passTotal + info.Price
	end
	check(passCount == 11 and passTotal == 2819, "11 gamepassów za 2 819 R$ razem (dokument projektu)")
	check(products.PremiumEgg1.Price == 99 and products.PremiumEgg3.Price == 269 and products.PremiumEgg10.Price == 799, "premium jajka 99 / 269 / 799 R$")
	local order = 0
	for _, key in ipairs(Robux.PassOrder) do
		if Economy.Robux.Gamepasses[key] ~= nil then
			order = order + 1
		end
	end
	check(order == passCount, "kolejność gamepassów w sklepie ma każdy gamepass")
	check(products[Economy.Robux.AdReward] ~= nil and products[Economy.Robux.AdReward].Minutes ~= nil, "nagroda za reklamę to zwykły produkt ze sklepu (boost)")
	check(Robux.passKey(0) == nil and Robux.productKey(0) == nil, "ID 0 = jeszcze nie ma (nil)")
	-- Niezależnie od wpisanych liczb: każde ID z Config/RobuxIds jest liczbą całkowitą i wraca do swojego
	-- klucza, więc paragon albo zakup gamepassa trafia do właściwej rzeczy (powtórzone ID by to psuło).
	local idsOk = true
	for key in pairs(Economy.Robux.Gamepasses) do
		local id = Robux.passId(key)
		if id ~= nil and (id % 1 ~= 0 or Robux.passKey(id) ~= key) then
			idsOk = false
		end
	end
	for key in pairs(products) do
		local id = Robux.productId(key)
		if id ~= nil and (id % 1 ~= 0 or Robux.productKey(id) ~= key) then
			idsOk = false
		end
	end
	check(idsOk, "każde ID gamepassa i produktu jest całkowite i prowadzi z powrotem do swojego klucza")
	-- pety bez losowania: cena według wartości oczekiwanej premium jajka (najwyżej 5% taniej)
	local rm = Economy.Pets.RarityMultiplier
	local prem = Loop.premiumInfo(1)
	local ev = 0
	for rarity, p in pairs(prem.Odds) do
		ev = ev + p * rm[rarity]
	end
	local evOk = true
	for _, rarity in ipairs({ "Epic", "Legendary", "Mythic" }) do
		local exact = products.PremiumEgg1.Price * rm[rarity] / ev
		local price = products["DirectPet" .. rarity].Price
		if price > exact + 1e-9 or price < exact * 0.95 then
			evOk = false
		end
	end
	check(evOk, "DirectPet: ceny według wartości oczekiwanej premium jajka")
	-- Starter Pack: same pewne rzeczy (bez L$, Aury i losowania)
	local sp = products.StarterPack
	check(sp.Price == 79 and sp.HoursAvailable == 72 and sp.Watch ~= nil and sp.PetRarity ~= nil and sp.Count == nil, "Starter Pack: 79 R$, 72 h, bez losowania")

	------------------------------------------------------------- Paragony
	local d = fresh()
	check(not Shop.hasReceipt(d, "a"), "nowy paragon nieznany")
	Shop.rememberReceipt(d, "a")
	Shop.rememberReceipt(d, "a")
	check(Shop.hasReceipt(d, "a") and #d.Robux.Receipts == 1, "paragon zapamiętany raz")
	for i = 1, 150 do
		Shop.rememberReceipt(d, "p" .. i)
	end
	check(#d.Robux.Receipts == Shop.ReceiptMemory and Shop.hasReceipt(d, "p150") and not Shop.hasReceipt(d, "p1"), "pamięć paragonów: ostatnie 100")

	------------------------------------------------------------- Boosty
	d = fresh()
	check(Shop.addBoost(d, "LP", 15) == 900 and Shop.addBoost(d, "LP", 5) == 1200, "boosty się sumują (15 + 5 min)")
	Shop.addBoost(d, "AutoSell", 1)
	local ended = Shop.tickBoosts(d, 59)
	check(#ended == 0 and Shop.boostLeft(d, "LP") == 1141 and Shop.boostLeft(d, "AutoSell") == 1, "boosty lecą w grze")
	ended = Shop.tickBoosts(d, 2)
	check(#ended == 1 and ended[1] == "AutoSell" and Shop.boostLeft(d, "AutoSell") == 0, "koniec boosta Auto-Sell")
	check(Shop.addBoost(d, "Nope", 5) == 0, "nieznany boost nic nie robi")
	local ctx = { boost = Shop.boostLeft(d, "LP") > 0 }
	check(Loop.lpMultiplier(d, ctx) == 2 * Loop.lpMultiplier(d, {}), "boost 2x LP podwaja LP")
	local old = { Cash = 0 } -- stary zapis bez pól Robux i Boosts
	check(Shop.boostLeft(old, "LP") == 0 and Shop.adsLeft(old, NOW) == 5 and not Shop.hasReceipt(old, "x"), "stary zapis bez pól nie psuje sklepu")

	------------------------------------------------------------- Verified
	d = fresh()
	check(Shop.verifiedDaily(d, NOW) == 15 and Shop.boostLeft(d, "LP") == 900, "Verified: 15 min 2x LP dziennie")
	check(Shop.verifiedDaily(d, NOW + 60) == 0, "Verified: drugi raz tego samego dnia nic")
	check(Shop.verifiedDaily(d, NOW + Shop.DaySeconds) == 15, "Verified: następnego dnia znowu")

	------------------------------------------------------------- Reklamy
	d = fresh()
	local counted = 0
	for _ = 1, 7 do
		if Shop.countAd(d, NOW) then
			counted = counted + 1
		end
	end
	check(counted == 5 and Shop.adsLeft(d, NOW) == 0, "reklamy: najwyżej 5 dziennie")
	check(Shop.adsLeft(d, NOW + Shop.DaySeconds) == 5, "reklamy: następnego dnia znowu 5")
	local r = Shop.grant(d, {}, Economy.Robux.AdReward, { ad = true, now = NOW + Shop.DaySeconds })
	check(r.Kind == "Boost" and r.Boost == "LP" and r.Ad and r.Counted and Shop.adsLeft(d, NOW + Shop.DaySeconds) == 4, "nagroda za reklamę: boost i -1 reklama")

	------------------------------------------------------------- Starter Pack
	d = fresh()
	check(Shop.starterSecondsLeft(d, NOW) == 71 * 3600, "Starter Pack: 72 h od pierwszego wejścia")
	check(Shop.starterSecondsLeft(d, NOW + 72 * 3600) == 0, "Starter Pack: po 72 h znika")
	check(Shop.canPrompt(d, "StarterPack", {}, NOW), "Starter Pack: można kupić")
	local ok, why = Shop.canPrompt(d, "StarterPack", {}, NOW + 80 * 3600)
	check(not ok and why == "Expired", "Starter Pack: po czasie nie")
	d.ZonesUnlocked = 3
	r = Shop.grant(d, {}, "StarterPack", { now = NOW })
	local watch = d.Clothes[r.Item.id]
	local pet = d.Pets[r.Pet.id]
	check(r.Kind == "Starter" and watch.Category == "Watch" and watch.Rarity == sp.Watch and watch.Box == "P" and r.Item.worn, "Starter Pack: zegarek kupiony za Robuxy, od razu założony")
	check(pet.Rarity == sp.PetRarity and pet.Zone == 3 and pet.Egg == "P" and Loop.isEquipped(d, r.Pet.id), "Starter Pack: pet z najwyższej strefy, od razu wyposażony")
	check(Shop.boostLeft(d, "LP") == sp.BoostMinutes * 60 and Shop.boostLeft(d, "AutoSell") == sp.AutoSellMinutes * 60, "Starter Pack: boosty")
	check(d.Cash == 0 and d.Aura == 0, "Starter Pack: bez L$ i Aury")
	ok, why = Shop.canPrompt(d, "StarterPack", {}, NOW)
	check(not ok and why == "Owned" and Shop.starterSecondsLeft(d, NOW) == 0, "Starter Pack: raz na konto")
	local mergeOne, mergeWhy = Clothes.mergeInfo(d, { r.Item.id })
	check(mergeOne == nil and mergeWhy == "Premium", "Starter Pack: zegarek za Robuxy łączy się tylko przy 100%")

	------------------------------------------------------------- Premium jajka
	d = fresh()
	d.ZonesUnlocked = 2
	ok, why = Shop.canPrompt(d, "PremiumEgg3", { zone = 2 }, NOW)
	check(ok, "premium jajko odblokowanej strefy")
	ok, why = Shop.canPrompt(d, "PremiumEgg3", { zone = 4 }, NOW)
	check(not ok and why == "Zone", "premium jajko zablokowanej strefy: nie")
	ok, why = Shop.canPrompt(d, "PremiumEgg1", { zone = 1, restricted = true }, NOW)
	check(not ok and why == "Restricted", "gracz z ograniczeniem losowań nie kupi jajka")
	ok, why = Shop.canPrompt(d, "DirectPetEpic", { zone = 1 }, NOW)
	check(not ok and why == "NotRestricted", "pet bez losowania tylko dla graczy z ograniczeniem")
	check(Shop.canPrompt(d, "DirectPetMythic", { zone = 2, restricted = true }, NOW), "gracz z ograniczeniem kupi konkretnego peta")
	r = Shop.grant(d, {}, "PremiumEgg3", { zone = 2, random01 = lcg(7), spent = 269 })
	local allP, allZone, allOdds = true, true, true
	for _, entry in ipairs(r.Pets) do
		local p = d.Pets[entry.id]
		allP = allP and p.Egg == "P"
		allZone = allZone and p.Zone == 2
		allOdds = allOdds and Loop.premiumInfo(2).Odds[p.Rarity] ~= nil
	end
	check(r.Kind == "Pets" and #r.Pets == 3 and allP and allZone and allOdds, "3 premium jajka: 3 pety z premium jajka strefy 2")
	check(d.Stats.PremiumEggs == 3 and d.Stats.EggsOpened == 3 and d.Robux.Spent == 269 and d.Robux.Bought.PremiumEgg3 == 1, "statystyki zakupu")
	check(#d.Equipped == 3, "nowe pety zajmują wolne sloty")
	r = Shop.grant(d, {}, "PremiumEgg10", { zone = 2, random01 = lcg(9) })
	check(#r.Pets == 10 and Loop.petCount(d) == 13 and #d.Equipped == 3, "10 premium jajek naraz (bez limitu ekwipunku, sloty pełne)")
	r = Shop.grant(d, {}, "PremiumEgg1", { zone = 5, random01 = lcg(3) })
	check(r.Zone == 2, "zakup spoza gry: strefa = najwyższa odblokowana")
	-- stałe szanse: szczęście z Aury nie działa na premium jajka
	local luckyD = fresh()
	luckyD.ZonesUnlocked = 5
	luckyD.AuraUpgrades.Luck = 60
	local counts = { Epic = 0, Legendary = 0, Mythic = 0 }
	local random01 = lcg(12345)
	local N = 20000
	for _ = 1, N do
		local list = Shop.openPremium(luckyD, { luckBoost = 1000 }, 5, 1, random01)
		local rarity = list[1].pet.Rarity
		counts[rarity] = (counts[rarity] or 0) + 1
		luckyD.Pets[list[1].id] = nil
	end
	local odds = Loop.premiumInfo(5).Odds
	local oddsOk = true
	for rarity, p in pairs(odds) do
		local got = counts[rarity] / N
		if math.abs(got - p) > 4 * math.sqrt(p * (1 - p) / N) + 0.002 then
			oddsOk = false
		end
	end
	check(oddsOk, string.format("premium jajko: szanse jak w oknie mimo szczęścia (Epic %.3f, Legendary %.3f, Mythic %.3f)", counts.Epic / N, counts.Legendary / N, counts.Mythic / N))
	local sum = 0
	for _, p in pairs(odds) do
		sum = sum + p
	end
	check(math.abs(sum - 1) < 1e-9, "premium jajko: szanse sumują się do 100%")

	-- premium jajko kupione mimo ograniczenia (sklep Roblox): bez losowania, Epic za każde jajko
	d = fresh()
	r = Shop.grant(d, {}, "PremiumEgg3", { zone = 1, restricted = true, random01 = lcg(1) })
	local allEpic = #r.Pets == 3 and r.Direct == true
	for _, entry in ipairs(r.Pets) do
		allEpic = allEpic and d.Pets[entry.id].Rarity == "Epic" and d.Pets[entry.id].Egg == "P"
	end
	check(allEpic, "gracz z ograniczeniem: premium jajko bez losowania (Epic za każde)")

	-- pety z premium jajek łączą się tylko przy 100% (5 sztuk)
	d = fresh()
	local ids = {}
	for _ = 1, 5 do
		local id = Loop.addPet(d, {}, 1, "Epic", "P")
		table.insert(ids, id)
	end
	local info4, why4 = Loop.mergeInfo(d, { ids[1], ids[2], ids[3], ids[4] })
	local info5 = Loop.mergeInfo(d, ids)
	check(info4 == nil and why4 == "Premium" and info5 ~= nil and info5.Chance >= 1 - 1e-9, "premium pety: łączenie tylko przy 100%")

	-- pet bez losowania
	d = fresh()
	d.ZonesUnlocked = 4
	r = Shop.grant(d, {}, "DirectPetLegendary", { zone = 3 })
	pet = d.Pets[r.Pets[1].id]
	check(r.Kind == "Pets" and pet.Rarity == "Legendary" and pet.Zone == 3 and pet.Egg == "P" and r.Pets[1].new, "DirectPet: konkretny pet ze strefy stoiska, nowy w indeksie")

	------------------------------------------------------------- Indeks z Mythic
	check(Loop.indexTotal() == 35, "indeks: 35 (5 stref × 7 rzadkości, z Mythic z premium jajek)")

	------------------------------------------------------------- Sell Now i boosty
	d = fresh()
	ok, why = Shop.canPrompt(d, "SellNow", {}, NOW)
	check(not ok and why == "EmptyBag", "Sell Now z pustym Bag: nie")
	d.Bag = 500
	r = Shop.grant(d, { petLayer = 2 }, "SellNow", {})
	check(r.Kind == "Sell" and r.LP == 500 and r.Cash == 1000 and d.Bag == 0 and d.Cash == 1000, "Sell Now sprzedaje Bag (pety mnożą L$)")
	r = Shop.grant(d, {}, "BoostAutoSell60", {})
	check(r.Kind == "Boost" and r.Boost == "AutoSell" and Shop.boostLeft(d, "AutoSell") == 3600, "boost Auto-Sell 60 min")
	check(Loop.autoSellOn(d, { autoSellBoost = true }), "boost Auto-Sell włącza Auto-Sell bez gamepassa")
	r, why = Shop.grant(d, {}, "Nope", {})
	check(r == nil and why == "Unknown", "nieznany produkt")

	return passed, failed, messages
end
