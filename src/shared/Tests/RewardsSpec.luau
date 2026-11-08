-- Testy nagród (Etap 11): dane nagród z modelu, kody (raz na konto, wielkość liter, miejsce w ekwipunku,
-- koniec ważności), jajka i boxy z nagród za darmo, najlepszy box, premium jajko i bonus za grupę
-- i znajomych. Uruchamia je ConfigCheck w Studio i tools/test_luau.py poza Roblox.
-- Zwraca funkcję: passed, failed, messages.

local Shared = script.Parent.Parent
local Economy = require(Shared.Config.Economy)
local Loop = require(Shared.Logic.Loop)
local Clothes = require(Shared.Logic.Clothes)
local Shop = require(Shared.Logic.Shop)
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
	local questsValid = #R.DailyQuests == 8 and R.QuestsPerDay >= 1 and R.QuestsPerDay <= #R.DailyQuests
	local questKeys = {}
	for _, quest in ipairs(R.DailyQuests) do
		questsValid = questsValid and type(quest.Key) == "string" and not questKeys[quest.Key]
		questsValid = questsValid and type(quest.Target) == "number" and quest.Target >= 1 and validReward(quest.Reward)
		questKeys[quest.Key] = true
	end
	check(questsValid, "zadania dzienne: 8 różnych, cel ≥ 1, nagroda z poprawną listą rzeczy, 3 dziennie")
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

	------------------------------------------------------------- Bonus za grupę i znajomych
	local B = Economy.Bonuses
	check(math.abs(Loop.lpBonus({ inGroup = true, friends = 0 }) - (1 + B.Group)) < 1e-9, "grupa: +5% LP")
	check(math.abs(Loop.lpBonus({ inGroup = false, friends = 2 }) - (1 + 2 * B.FriendEach)) < 1e-9, "2 znajomych: +20% LP")
	check(math.abs(Loop.lpBonus({ inGroup = true, friends = 7 }) - (1 + B.Group + B.FriendMax * B.FriendEach)) < 1e-9, "znajomi najwyżej 3 (+30%), razem z grupą +35%")

	return passed, failed, messages
end
