-- Testy nagród (Etap 11): dane nagród z modelu, kody (raz na konto, wielkość liter, miejsce w ekwipunku,
-- koniec ważności), jajka i boxy z nagród za darmo, najlepszy box, premium jajko, nagroda dzienna
-- (seria, cykl 7 dni, opuszczony dzień, północ UTC), zadania dzienne (pula według stref, losowanie,
-- postęp, Aura, komplet, zamiana po Rebirthie) i bonus za grupę i znajomych. Uruchamia je ConfigCheck
-- w Studio i tools/test_luau.py poza Roblox.
-- Zwraca funkcję: passed, failed, messages.

local Shared = script.Parent.Parent
local Economy = require(Shared.Config.Economy)
local Loop = require(Shared.Logic.Loop)
local Clothes = require(Shared.Logic.Clothes)
local Shop = require(Shared.Logic.Shop)
local Rebirth = require(Shared.Logic.Rebirth)
local Rewards = require(Shared.Logic.Rewards)
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

local function count(t)
	local n = 0
	for _ in pairs(t) do
		n = n + 1
	end
	return n
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
	local ctx = { zone = 1, passes = {} }

	local function fresh(zones)
		local d = copy(Template)
		d.ZonesUnlocked = zones or 1
		return d
	end

	------------------------------------------------------------- Dane nagród z modelu
	local R = Economy.Rewards
	local boostKinds = {}
	for _, kind in ipairs(Shop.BoostKinds) do
		boostKinds[kind] = true
	end
	local function validReward(reward)
		if type(reward) ~= "table" or type(reward.Label) ~= "string" or type(reward.Items) ~= "table" or #reward.Items == 0 then
			return false
		end
		for _, item in ipairs(reward.Items) do
			if not Rewards.Kinds[item.Kind] then
				return false
			end
			if item.Kind == "Boost" then
				if not boostKinds[item.Boost] or type(item.Minutes) ~= "number" or item.Minutes <= 0 then
					return false
				end
			else
				if type(item.Count) ~= "number" or item.Count < 1 or item.Count % 1 ~= 0 then
					return false
				end
				if item.Kind == "Egg" and item.Egg ~= "A" and item.Egg ~= "B" then
					return false
				end
				if item.Kind == "Box" and item.Box ~= "Best" and Clothes.boxInfo(item.Box) == nil then
					return false
				end
			end
		end
		return true
	end
	local allValid = #R.DailyStreak == 7
	for _, reward in ipairs(R.DailyStreak) do
		allValid = allValid and validReward(reward)
	end
	check(allValid, "nagroda dzienna: 7 dni, każdy z poprawną listą rzeczy")
	local questsValid = #R.DailyQuests >= 15 and R.QuestsPerDay >= 1 and R.QuestsPerDay <= #R.DailyQuests
	-- Requires: tylko znane warunki (Activity = rodzaj aktywności, Zone, Rebirth, Upgrade)
	local function validNeeds(needs)
		if needs == nil then
			return true
		end
		for field, value in pairs(needs) do
			if field == "Activity" then
				if Economy.Activities[value] == nil then
					return false
				end
			elseif field == "Zone" or field == "Rebirth" then
				if type(value) ~= "number" or value < 1 then
					return false
				end
			elseif field == "Upgrade" then
				if value ~= true then
					return false
				end
			else
				return false
			end
		end
		return true
	end
	local questKeys = {}
	for _, quest in ipairs(R.DailyQuests) do
		questsValid = questsValid and type(quest.Key) == "string" and not questKeys[quest.Key]
		questsValid = questsValid and type(quest.Target) == "number" and quest.Target >= 1 and validReward(quest.Reward)
		questsValid = questsValid and validNeeds(quest.Requires)
		questKeys[quest.Key] = true
	end
	check(questsValid, "zadania dzienne: co najmniej 15 różnych, cel ≥ 1, poprawna nagroda i warunki, 3 dziennie")
	local codesValid = count(R.Codes) >= 3
	for code, reward in pairs(R.Codes) do
		-- kod z małymi literami albo spacją byłby nie do wpisania (porównujemy po normalizeCode)
		codesValid = codesValid and Rewards.normalizeCode(code) == code and validReward(reward)
	end
	check(codesValid, "kody: wielkie litery bez spacji, każdy z poprawną nagrodą")
	check(R.Codes.LARPINMIAMI ~= nil and R.Codes.SECURETHEBAG ~= nil and R.Codes.LIKES1K ~= nil, "kody z dokumentu: LARPINMIAMI, SECURETHEBAG, LIKES1K")
	check(Template.Codes ~= nil and next(Template.Codes) == nil, "nowy gracz nie ma wpisanych kodów")

	------------------------------------------------------------- Strefa jajka i najlepszy box
	check(Rewards.eggZone(fresh(1), "A") == 1 and Rewards.eggZone(fresh(3), "B") == 3, "jajko z najwyższej odblokowanej strefy")
	check(Rewards.eggZone(fresh(99), "A") == #Economy.Pets.Eggs, "jajko: najwyżej ostatnia strefa z jajkami")
	check(Rewards.bestBox(fresh(1)) == "Street" and Rewards.bestBox(fresh(2)) == "Street", "box przed strefą 3: Street")
	check(Rewards.bestBox(fresh(3)) == "Street" and Rewards.bestBox(fresh(4)) == "Designer" and Rewards.bestBox(fresh(5)) == "Iced", "najlepszy odblokowany box: Street, Designer, Iced")

	------------------------------------------------------------- Darmowe jajka i boxy
	local d = fresh(1)
	d.Cash = 0
	local list, reason = Loop.openEggs(d, ctx, 1, "A", 3, lcg(1), nil)
	check(list == nil and reason == "NotEnough", "kupione jajko dalej kosztuje L$")
	list = Loop.openEggs(d, ctx, 1, "A", 3, lcg(1), nil, true)
	check(list ~= nil and #list == 3 and d.Cash == 0 and count(d.Pets) == 3, "jajko z nagrody nic nie kosztuje")
	check(d.Stats.EggsOpened == 3 and list[1].pet.Rarity == Economy.Pets.FirstEggRarity, "jajko z nagrody liczy się jak otwarte (pierwsze jajko A daje Rare)")
	local items
	items, reason = Clothes.openBoxes(d, ctx, "Street", 1, lcg(2), nil, nil)
	check(items == nil and reason == "Zone", "kupiony box dalej wymaga strefy")
	items = Clothes.openBoxes(d, ctx, "Street", 2, lcg(2), nil, nil, true)
	check(items ~= nil and #items == 2 and d.Cash == 0 and Clothes.count(d) == 2 and d.Clothes[items[1].id].Box == "Street", "box z nagrody: bez L$ i bez strefy")

	------------------------------------------------------------- grant
	d = fresh(4)
	d.Cash = 123
	local result = Rewards.grant(d, ctx, R.DailyStreak[6].Items, lcg(3))
	check(#result.Boxes == 1 and result.Boxes[1].Box == "Designer" and #result.Boxes[1].Items == 2, "dzień 6: 2 najlepsze boxy (strefa 4: Designer)")
	check(#result.Boosts == 1 and result.Boosts[1].Boost == "AutoSell" and Shop.boostLeft(d, "AutoSell") == 15 * 60, "dzień 6: Auto-Sell na 15 minut")
	check(d.Cash == 123, "nagroda nie zabiera L$")
	d = fresh(3)
	result = Rewards.grant(d, ctx, R.DailyStreak[7].Items, lcg(4))
	local premiumOk = #result.Eggs == 1 and result.Eggs[1].Egg == "P" and #result.Eggs[1].Pets == 1
	premiumOk = premiumOk and result.Eggs[1].Pets[1].pet.Egg == "P" and result.Eggs[1].Zone == Shop.premiumZone(d, nil)
	check(premiumOk, "dzień 7: premium jajko z najwyższej strefy (pet z Egg = P)")
	check(Shop.boostLeft(d, "LP") == 30 * 60, "dzień 7: boost 2x LP 30 minut")
	result = Rewards.grant(d, ctx, R.DailyStreak[5].Items, lcg(5))
	local eggsOk = #result.Eggs == 1 and result.Eggs[1].Egg == "B" and result.Eggs[1].Zone == 3 and #result.Eggs[1].Pets == 3
	for _, entry in ipairs((result.Eggs[1] or { Pets = {} }).Pets) do
		eggsOk = eggsOk and entry.pet.Egg == "B" and entry.pet.Zone == 3
	end
	check(eggsOk, "dzień 5: 3 jajka B ze strefy 3")

	------------------------------------------------------------- Miejsce w ekwipunku
	local pets, clothes = Rewards.counts(R.DailyStreak[6].Items)
	check(pets == 0 and clothes == 2, "dzień 6 dodaje 2 ubrania i żadnego peta")
	d = fresh(1)
	for i = 1, 5 do
		d.Pets["x" .. i] = { Zone = 1, Rarity = "Common", Level = 0, Egg = "A" }
	end
	local ok
	ok, reason = Rewards.fits(d, R.Codes.SECURETHEBAG.Items, { pets = 7 })
	check(not ok and reason == "PetInventory", "3 pety nie zmieszczą się przy 5 z 7")
	ok = Rewards.fits(d, R.Codes.SECURETHEBAG.Items, { pets = 8 })
	check(ok, "3 pety mieszczą się przy 5 z 8")
	check(Rewards.fits(d, R.Codes.LARPINMIAMI.Items, { pets = 5, clothes = 0 }), "boost mieści się zawsze")

	------------------------------------------------------------- Kody
	check(Rewards.normalizeCode("  larpInMiami ") == "LARPINMIAMI" and Rewards.normalizeCode("LARP IN MIAMI") == "LARPINMIAMI", "kod bez spacji i bez wielkości liter")
	check(Rewards.normalizeCode("") == nil and Rewards.normalizeCode("   ") == nil and Rewards.normalizeCode(nil) == nil and Rewards.normalizeCode(5) == nil, "pusty albo nietekstowy kod")
	check(Rewards.normalizeCode(string.rep("A", Rewards.CodeMaxLength + 1)) == nil, "za długi kod")

	d = fresh(2)
	d.Cash = 50
	result, reason = Rewards.redeemCode(d, ctx, "nope", lcg(6), nil, NOW)
	check(result == nil and reason == "Unknown", "nieznany kod")
	result, reason = Rewards.redeemCode(d, ctx, "", lcg(6), nil, NOW)
	check(result == nil and reason == "Invalid", "pusty kod")
	result = Rewards.redeemCode(d, ctx, "securethebag", lcg(6), { pets = 50 }, NOW)
	local codeOk = result ~= nil and result.Code == "SECURETHEBAG" and #result.Eggs == 1 and #result.Eggs[1].Pets == 3
	codeOk = codeOk and result.Eggs[1].Zone == 2 and result.Eggs[1].Egg == "A" and d.Cash == 50 and d.Codes.SECURETHEBAG == true
	check(codeOk, "SECURETHEBAG: 3 jajka A z najwyższej strefy, za darmo, kod zapisany")
	result, reason = Rewards.redeemCode(d, ctx, "SecureTheBag", lcg(6), { pets = 50 }, NOW)
	check(result == nil and reason == "Used" and count(d.Pets) == 3, "drugi raz ten sam kod: Used (bez nagrody)")
	result = Rewards.redeemCode(d, ctx, "LARPINMIAMI", lcg(6), { pets = 50 }, NOW)
	check(result ~= nil and #result.Boosts == 1 and Shop.boostLeft(d, "LP") == 15 * 60 and #result.Eggs == 0, "LARPINMIAMI: boost 2x LP 15 minut")
	Rewards.redeemCode(d, ctx, "LIKES1K", lcg(6), nil, NOW)
	check(Shop.boostLeft(d, "LP") == 45 * 60, "LIKES1K: +30 minut do boosta (boosty się sumują)")

	-- bez miejsca kod zostaje niewpisany, więc działa po zrobieniu miejsca
	d = fresh(1)
	for i = 1, 6 do
		d.Pets["x" .. i] = { Zone = 1, Rarity = "Common", Level = 0, Egg = "A" }
	end
	result, reason = Rewards.redeemCode(d, ctx, "SECURETHEBAG", lcg(7), { pets = 8 }, NOW)
	check(result == nil and reason == "PetInventory" and not Rewards.codeUsed(d, "SECURETHEBAG") and count(d.Pets) == 6, "pełny ekwipunek: kod nie przepada")
	d.Pets.x1 = nil
	d.Pets.x2 = nil
	d.Pets.x3 = nil
	result = Rewards.redeemCode(d, ctx, "SECURETHEBAG", lcg(7), { pets = 8 }, NOW)
	check(result ~= nil and Rewards.codeUsed(d, "SECURETHEBAG") and count(d.Pets) == 6, "po zrobieniu miejsca kod działa")

	-- kod z końcem ważności (Ends w sekundach UTC)
	R.Codes.SPECTESTCODE = { Label = "test", Items = { { Kind = "Boost", Boost = "LP", Minutes = 5 } }, Ends = NOW }
	d = fresh(1)
	result, reason = Rewards.redeemCode(d, ctx, "spectestcode", lcg(8), nil, NOW)
	check(result == nil and reason == "Expired" and not Rewards.codeUsed(d, "SPECTESTCODE"), "kod po końcu ważności: Expired")
	result = Rewards.redeemCode(d, ctx, "spectestcode", lcg(8), nil, NOW - 1)
	check(result ~= nil and Shop.boostLeft(d, "LP") == 5 * 60, "kod przed końcem ważności działa")
	R.Codes.SPECTESTCODE = nil

	------------------------------------------------------------- Nagroda dzienna
	local DAY = 86400
	local T0 = 20000 * DAY + 3600 -- 1:00 UTC
	d = fresh(3)
	local st = Rewards.dailyState(d, T0)
	check(st.CanClaim and st.Day == 1 and st.Streak == 0 and not st.Lost, "nowy gracz: dzień 1 do odebrania")
	result = Rewards.claimDaily(d, ctx, lcg(9), nil, T0)
	check(result ~= nil and result.Day == 1 and result.Streak == 1 and #result.Boosts == 1 and Shop.boostLeft(d, "LP") == 10 * 60, "dzień 1: boost 2x LP 10 minut")
	result, reason = Rewards.claimDaily(d, ctx, lcg(9), nil, T0 + 3600)
	check(result == nil and reason == "Claimed" and Shop.boostLeft(d, "LP") == 10 * 60, "drugi raz tego samego dnia: Claimed (bez nagrody)")
	st = Rewards.dailyState(d, T0 + 3600)
	check(not st.CanClaim and st.Day == 1 and st.SecondsLeft == DAY - 2 * 3600, "po odbiorze: następna o północy UTC")
	result = Rewards.claimDaily(d, ctx, lcg(9), { pets = 50 }, T0 + DAY)
	check(result ~= nil and result.Day == 2 and result.Streak == 2 and #result.Eggs == 1 and #result.Eggs[1].Pets == 3, "następny dzień: dzień 2 (3 jajka A)")
	st = Rewards.dailyState(d, T0 + 3 * DAY)
	check(st.CanClaim and st.Day == 1 and st.Lost and st.Streak == 0, "opuszczony dzień: od dnia 1, seria zerwana")
	result = Rewards.claimDaily(d, ctx, lcg(9), nil, T0 + 3 * DAY)
	check(result ~= nil and result.Day == 1 and result.Streak == 1 and d.Daily.Claimed == 3, "po zerwanej serii: dzień 1 i seria 1")
	d = fresh(5)
	local days = {}
	for i = 0, 7 do
		local r = Rewards.claimDaily(d, ctx, lcg(10 + i), { pets = 500, clothes = 500 }, T0 + i * DAY)
		table.insert(days, (r and r.Day) or -1)
	end
	check(table.concat(days, ",") == "1,2,3,4,5,6,7,1" and d.Daily.Streak == 8 and d.Daily.Claimed == 8, "7 dni pod rząd, potem znowu dzień 1 (seria 8)")
	d = fresh(1)
	Rewards.claimDaily(d, ctx, lcg(11), nil, T0)
	for i = 1, 8 do
		d.Pets["y" .. i] = { Zone = 1, Rarity = "Common", Level = 0, Egg = "A" }
	end
	result, reason = Rewards.claimDaily(d, ctx, lcg(11), { pets = 8 }, T0 + DAY)
	check(result == nil and reason == "PetInventory" and d.Daily.Streak == 1 and Rewards.dailyState(d, T0 + DAY).CanClaim, "pełny ekwipunek: dzień 2 czeka, seria bez zmian")
	d = fresh(1)
	Rewards.claimDaily(d, ctx, lcg(12), nil, 20000 * DAY + DAY - 1)
	st = Rewards.dailyState(d, 20001 * DAY)
	check(st.CanClaim and st.Day == 2, "nowy dzień zaczyna się o północy UTC")
	check(Template.Daily ~= nil and Template.Daily.Day == 0 and Template.Daily.Streak == 0, "nowy gracz: nagroda dzienna od zera")

	------------------------------------------------------------- Zadania dzienne
	local Q = R.DailyQuests
	local function poolIndex(key)
		for i, quest in ipairs(Q) do
			if quest.Key == key then
				return i
			end
		end
		return -1
	end
	local function keysOf(list)
		local out = {}
		for _, quest in ipairs(list) do
			table.insert(out, quest.Key)
		end
		return table.concat(out, ",")
	end
	local function poolOf(data)
		local out = {}
		for _, quest in ipairs(Q) do
			if Rewards.questAvailable(data, quest.Key) then
				table.insert(out, { Key = quest.Key })
			end
		end
		return keysOf(out)
	end
	local function setQuests(data, list, day)
		data.Quests = { Day = Rewards.day(day or T0), List = list, Bonus = false, Completed = 0 }
	end
	local mapOk = true
	for _, kind in ipairs(Loop.ActivityKinds) do
		mapOk = mapOk and Rewards.questInfo(Rewards.ActivityQuests[kind]) ~= nil
	end
	check(mapOk, "każda aktywność ma swoje zadanie (Rewards.ActivityQuests)")
	check(3 * Economy.Aura.DailyQuestReward + Economy.Aura.DailyAllQuestsBonus == 50, "zadania dają najwyżej 50 Aury dziennie (bez Aura Gain)")
	check(poolOf(fresh(1)) == "Sells,EggsOpened,Clicks,Merges,PlayMinutes,Upgrades,SellPets,GoldenEggs,MergeWins", "strefa 1: zadania bez aktywności, boxów i Aury (9)")
	check(poolOf(fresh(2)) == "CarPhotos,Sells,EggsOpened,Clicks,Merges,PlayMinutes,Upgrades,SellPets,Activities,GoldenEggs,MergeWins", "strefa 2: dochodzą sesje zdjęciowe i dowolne aktywności")
	check(poolOf(fresh(4)) == "CarPhotos,Interviews,YachtSessions,Sells,EggsOpened,Clicks,Merges,PlayMinutes,BoxesOpened,Upgrades,SellPets,Activities,ViralInterviews,GoldenEggs,MergeWins", "strefa 4: wywiady, jacht i boxy (od strefy 3)")
	check(not Rewards.questAvailable(fresh(2), "BoxesOpened") and Rewards.questAvailable(fresh(3), "BoxesOpened"), "boxy od strefy 3")
	d = fresh(5)
	check(not Rewards.questAvailable(d, "JetRentals"), "loty odrzutowcem dopiero po kupnie pierwszego odrzutowca")
	d.ActivityTiers.Jet = 1
	check(not Rewards.questAvailable(d, "AuraBar"), "pasek Aury dopiero od Rebirth 1")
	d.RebirthCount = 1
	check(Rewards.questAvailable(d, "AuraBar") and #poolOf(d) > 0 and select(2, string.gsub(poolOf(d), ",", "")) + 1 == #R.DailyQuests, "strefa 5, odrzutowiec i Rebirth 1: cała pula")
	d.ClickLevel = Loop.MaxLevel.Click
	check(Rewards.questAvailable(d, "Upgrades"), "Upgrades: dopóki Bag nie jest na maksa")
	d.BagLevel = Loop.MaxLevel.Bag
	check(not Rewards.questAvailable(d, "Upgrades"), "Upgrades: nie, gdy Click i Bag są na maksa")
	check(Rewards.ViralGrade == 3 and Economy.Activities.Interview.Grades[Rewards.ViralGrade].Name == "Viral", "wywiad Viral i lepszy liczy się do ViralInterviews")

	-- losowanie: 3 różne z puli gracza, w kolejności puli, z zerowym postępem
	local seen = {}
	local pickOk = true
	for seed = 1, 40 do
		local dz = fresh(1)
		local q = Rewards.ensureQuests(dz, lcg(seed), T0)
		pickOk = pickOk and #q.List == R.QuestsPerDay and q.Day == Rewards.day(T0) and not q.Bonus
		local used, last = {}, 0
		for _, quest in ipairs(q.List) do
			pickOk = pickOk and not used[quest.Key] and Rewards.questAvailable(dz, quest.Key)
			pickOk = pickOk and quest.Progress == 0 and not quest.Claimed and poolIndex(quest.Key) > last
			used[quest.Key] = true
			last = poolIndex(quest.Key)
			seen[quest.Key] = true
		end
	end
	check(pickOk, "losowanie: 3 różne zadania z puli gracza, w kolejności puli, od zera")
	check(count(seen) == 9, "w strefie 1 trafia się każde z 9 zadań")
	d = fresh(5)
	d.ActivityTiers.Jet = 1
	local first = keysOf(Rewards.ensureQuests(d, lcg(41), T0).List)
	Rewards.ensureQuests(d, lcg(99), T0 + 5 * 3600)
	check(keysOf(d.Quests.List) == first, "przez cały dzień te same zadania")
	local yesterday = {}
	for _, quest in ipairs(d.Quests.List) do
		yesterday[quest.Key] = true
	end
	Rewards.ensureQuests(d, lcg(42), T0 + DAY)
	local newOk = #d.Quests.List == 3
	for _, quest in ipairs(d.Quests.List) do
		newOk = newOk and not yesterday[quest.Key]
	end
	check(newOk, "następnego dnia inne zadania (przy dużej puli żadne z wczoraj)")

	-- postęp i odbiór (lista ustawiona ręcznie: Sells 10, Clicks 500, Merges 1)
	d = fresh(1)
	setQuests(d, {
		{ Key = "Sells", Progress = 0, Claimed = false },
		{ Key = "Clicks", Progress = 0, Claimed = false },
		{ Key = "Merges", Progress = 0, Claimed = false },
	})
	local changed, done = Rewards.questProgress(d, "EggsOpened", 5, lcg(50), T0)
	check(not changed and done == nil, "postęp zadania, którego dziś nie ma: nic")
	changed, done = Rewards.questProgress(d, "Clicks", 499, lcg(50), T0)
	check(changed and done == nil and d.Quests.List[2].Progress == 499, "499 z 500 kliknięć: jeszcze nieskończone")
	result, reason = Rewards.claimQuest(d, ctx, 2, lcg(50), nil, T0)
	check(result == nil and reason == "NotDone", "nieskończone zadanie: NotDone")
	changed, done = Rewards.questProgress(d, "Clicks", 10, lcg(50), T0)
	check(changed and done ~= nil and #done == 1 and done[1] == 2 and d.Quests.List[2].Progress == 500, "500 kliknięć: zadanie 2 skończone, postęp najwyżej do celu")
	changed, done = Rewards.questProgress(d, "Clicks", 10, lcg(50), T0)
	check(not changed and done == nil, "skończone zadanie nie liczy dalej i nie kończy się drugi raz")
	check(not Rewards.questProgress(d, "Sells", 0 / 0, lcg(50), T0) and not Rewards.questProgress(d, "Sells", -3, lcg(50), T0), "zły postęp (NaN, ujemny): nic")
	result = Rewards.claimQuest(d, ctx, 2, lcg(51), { pets = 50 }, T0)
	check(result ~= nil and result.Key == "Clicks" and #result.Eggs == 1 and #result.Eggs[1].Pets == 2 and result.Aura == 0 and d.Aura == 0, "Clicks: 2 jajka A, przed Rebirth 1 bez Aury")
	result, reason = Rewards.claimQuest(d, ctx, 2, lcg(51), { pets = 50 }, T0)
	check(result == nil and reason == "Claimed" and count(d.Pets) == 2, "drugi raz to samo zadanie: Claimed (bez nagrody)")
	check(Rewards.claimQuest(d, ctx, 7, lcg(51), nil, T0) == nil and Rewards.claimQuest(d, ctx, "1", lcg(51), nil, T0) == nil, "zły numer zadania: BadRequest")
	d.RebirthCount = 1
	d.RebirthLevel = 1
	d.AuraUpgrades.AuraGain = 3
	local gain = Rebirth.gain(d)
	Rewards.questProgress(d, "Sells", 10, lcg(52), T0)
	result = Rewards.claimQuest(d, ctx, 1, lcg(52), nil, T0)
	check(result ~= nil and math.abs(result.Aura - 10 * gain) < 1e-9 and result.BonusAura == 0 and not result.AllDone and Shop.boostLeft(d, "LP") == 15 * 60, "Sells: boost 15 min i +10 Aury razy Aura Gain")
	Rewards.questProgress(d, "Merges", 1, lcg(53), T0)
	result = Rewards.claimQuest(d, ctx, 3, lcg(53), nil, T0)
	check(result ~= nil and result.AllDone and math.abs(result.BonusAura - 20 * gain) < 1e-9 and d.Quests.Bonus and d.Quests.Completed == 3, "trzecie zadanie: komplet +20 Aury")
	check(math.abs(d.Aura - 40 * gain) < 1e-9 and math.abs(d.Stats.AuraEarned - 40 * gain) < 1e-9, "Aura: 0 + 10 + 10 + 20 (pierwsze przed Rebirth 1), też w AuraEarned")
	local qv = Rewards.questView(d, T0 + 60)
	check(#qv.List == 3 and qv.List[2].Index == 2 and qv.List[2].Target == 500 and qv.List[2].Claimed and qv.Bonus, "stan zadań dla okna: numer, cel, odebrane, komplet")
	check(math.abs(qv.Aura - 10 * gain) < 1e-9 and math.abs(qv.BonusAura - 20 * gain) < 1e-9 and qv.SecondsLeft == DAY - 3600 - 60, "okno: Aura za zadanie i komplet, czas do północy UTC")
	Rewards.ensureQuests(d, lcg(54), T0 + DAY)
	local resetOk = d.Quests.Day == Rewards.day(T0 + DAY) and not d.Quests.Bonus and #d.Quests.List == 3 and d.Quests.Completed == 3
	for _, quest in ipairs(d.Quests.List) do
		resetOk = resetOk and quest.Progress == 0 and not quest.Claimed
	end
	check(resetOk, "nowy dzień: nowe zadania od zera, komplet znowu do zdobycia")

	-- pełny ekwipunek: nagroda czeka na CLAIM
	d = fresh(1)
	setQuests(d, { { Key = "Clicks", Progress = 500, Claimed = false } })
	for i = 1, 7 do
		d.Pets["z" .. i] = { Zone = 1, Rarity = "Common", Level = 0, Egg = "A" }
	end
	result, reason = Rewards.claimQuest(d, ctx, 1, lcg(55), { pets = 8 }, T0)
	check(result == nil and reason == "PetInventory" and not d.Quests.List[1].Claimed and count(d.Pets) == 7, "pełny ekwipunek: nagroda zadania czeka")
	d.Pets.z1 = nil
	result = Rewards.claimQuest(d, ctx, 1, lcg(55), { pets = 8 }, T0)
	check(result ~= nil and d.Quests.List[1].Claimed and count(d.Pets) == 8, "po zrobieniu miejsca CLAIM działa")

	-- po Rebirthie (strefa 1) nieskończone zadanie z aktywnością zamienia się na inne
	d = fresh(5)
	d.ActivityTiers.Jet = 1
	setQuests(d, {
		{ Key = "CarPhotos", Progress = 3, Claimed = false },
		{ Key = "JetRentals", Progress = 3, Claimed = false },
		{ Key = "Sells", Progress = 2, Claimed = false },
	})
	d.ZonesUnlocked = 1
	d.ActivityTiers = { Car = 1, Yacht = 1, Jet = 0 }
	Rewards.ensureQuests(d, lcg(56), T0 + 60)
	local list = d.Quests.List
	local swapOk = #list == 3 and list[1].Key == "JetRentals" and list[1].Progress == 3 and list[2].Key == "Sells" and list[2].Progress == 2
	swapOk = swapOk and list[3] ~= nil and poolIndex(list[3].Key) > poolIndex("Sells") and list[3].Progress == 0
	check(swapOk, "po Rebirthie: zdjęcia zamienione na zadanie ze strefy 1, skończone i Sells zostają")
	check(Template.Quests ~= nil and Template.Quests.Day == 0 and #Template.Quests.List == 0 and Template.Quests.Bonus == false, "nowy gracz: zadania jeszcze niewylosowane")

	------------------------------------------------------------- Bonus za grupę i znajomych
	local B = Economy.Bonuses
	check(math.abs(Loop.lpBonus({ inGroup = true, friends = 0 }) - (1 + B.Group)) < 1e-9, "grupa: +5% LP")
	check(math.abs(Loop.lpBonus({ inGroup = false, friends = 2 }) - (1 + 2 * B.FriendEach)) < 1e-9, "2 znajomych: +20% LP")
	check(math.abs(Loop.lpBonus({ inGroup = true, friends = 7 }) - (1 + B.Group + B.FriendMax * B.FriendEach)) < 1e-9, "znajomi najwyżej 3 (+30%), razem z grupą +35%")

	return passed, failed, messages
end
