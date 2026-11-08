-- Nagrody (Etap 11): kody, nagroda dzienna, a w kolejnej części zadania dzienne. Czysta logika na
-- zapisie gracza (bez Roblox API), więc działa na serwerze (RewardsService) i w testach (RewardsSpec).
--
-- Nagroda z Economy.Rewards to { Label, Items }. Label to opis z dokumentu projektu, a Items to lista
-- rzeczy, które gra naprawdę daje:
--   { Kind = "Boost", Boost = "LP"|"AutoSell", Minutes = 15 }   boost (sumuje się z kupionymi)
--   { Kind = "Egg", Egg = "A"|"B", Count = 3 }                    jajka z najwyższej odblokowanej strefy
--   { Kind = "Box", Box = "Best", Count = 2 }                     najlepszy odblokowany box (przed strefą 3 Street)
--   { Kind = "PremiumEgg", Count = 1 }                            premium jajko z najwyższej strefy
-- Jajka i boxy z nagród losują tak samo jak kupione za L$ (ze szczęściem z Aury), tylko nic nie
-- kosztują. Darmowe premium jajko nie jest płatnym losowaniem, więc dostaje je każdy tak samo.

local Economy = require(script.Parent.Parent.Config.Economy)
local Loop = require(script.Parent.Loop)
local Clothes = require(script.Parent.Clothes)
local Shop = require(script.Parent.Shop)

local Rewards = {}

Rewards.CodeMaxLength = 30 -- dłuższy tekst to na pewno nie kod
Rewards.Kinds = { Boost = true, Egg = true, Box = true, PremiumEgg = true }

----------------------------------------------------------------- Skąd jajko i który box
-- Najwyższa odblokowana strefa, w której jest jajko egg (A albo B).
function Rewards.eggZone(data, egg)
	local unlocked = math.min(data.ZonesUnlocked or 1, #Economy.Pets.Eggs)
	for zone = unlocked, 1, -1 do
		if Loop.eggInfo(zone, egg or "A") ~= nil then
			return zone
		end
	end
	return 1
end

-- Najlepszy odblokowany box (najwyższe RequiresZone, które gracz ma), a przed strefą z boxami
-- najtańszy (Street), żeby nagroda zawsze coś dawała.
function Rewards.bestBox(data)
	local unlocked = data.ZonesUnlocked or 1
	local best, bestZone, bestPrice = nil, -1, -1
	local cheapest, cheapestPrice = nil, math.huge
	for name in pairs(Economy.Clothes.Boxes) do
		local info = Clothes.boxInfo(name)
		if info ~= nil and info.RequiresZone ~= nil then
			if info.RequiresZone <= unlocked then
				if info.RequiresZone > bestZone or (info.RequiresZone == bestZone and info.Price > bestPrice) then
					best, bestZone, bestPrice = name, info.RequiresZone, info.Price
				end
			end
			if info.Price < cheapestPrice then
				cheapest, cheapestPrice = name, info.Price
			end
		end
	end
	return best or cheapest
end

----------------------------------------------------------------- Miejsce w ekwipunku
-- Ile petów i ubrań doda nagroda.
function Rewards.counts(items)
	local pets, clothes = 0, 0
	for _, item in ipairs(items or {}) do
		local count = item.Count or 1
		if item.Kind == "Egg" or item.Kind == "PremiumEgg" then
			pets = pets + count
		elseif item.Kind == "Box" then
			clothes = clothes + count
		end
	end
	return pets, clothes
end

-- Czy wszystko z nagrody się zmieści. limits = { pets = najwięcej petów, clothes = najwięcej ubrań }
-- (nil albo brak pola = bez limitu). Zwraca true albo false i powód: PetInventory, ClothInventory.
function Rewards.fits(data, items, limits)
	local pets, clothes = Rewards.counts(items)
	if limits ~= nil then
		if pets > 0 and limits.pets ~= nil and Loop.petCount(data) + pets > limits.pets then
			return false, "PetInventory"
		end
		if clothes > 0 and limits.clothes ~= nil and Clothes.count(data) + clothes > limits.clothes then
			return false, "ClothInventory"
		end
	end
	return true, nil
end

----------------------------------------------------------------- Przyznanie
-- Daje wszystko z listy items (miejsce sprawdza wcześniej Rewards.fits). random01 = funkcja losująca
-- liczbę z [0, 1). Zwraca, co gracz dostał:
--   Boosts = { { Boost, Minutes } }
--   Eggs   = { { Zone, Egg ("A", "B" albo "P" = premium), Pets = { { id, pet, new } } } }
--   Boxes  = { { Box, Items = { { id, item, worn } } } }
function Rewards.grant(data, ctx, items, random01)
	local result = { Boosts = {}, Eggs = {}, Boxes = {} }
	random01 = random01 or math.random
	for _, item in ipairs(items or {}) do
		local count = item.Count or 1
		if item.Kind == "Boost" then
			if Shop.addBoost(data, item.Boost, item.Minutes) > 0 then
				table.insert(result.Boosts, { Boost = item.Boost, Minutes = item.Minutes })
			end
		elseif item.Kind == "Egg" then
			local zone = Rewards.eggZone(data, item.Egg)
			local list = Loop.openEggs(data, ctx, zone, item.Egg, count, random01, nil, true)
			if list ~= nil and #list > 0 then
				table.insert(result.Eggs, { Zone = zone, Egg = item.Egg, Pets = list })
			end
		elseif item.Kind == "PremiumEgg" then
			local zone = Shop.premiumZone(data, nil)
			local list = Shop.openPremium(data, ctx, zone, count, random01)
			if #list > 0 then
				table.insert(result.Eggs, { Zone = zone, Egg = "P", Pets = list })
			end
		elseif item.Kind == "Box" then
			local box = item.Box
			if box == "Best" or Clothes.boxInfo(box) == nil then
				box = Rewards.bestBox(data)
			end
			local list = Clothes.openBoxes(data, ctx, box, count, random01, nil, nil, true)
			if list ~= nil and #list > 0 then
				table.insert(result.Boxes, { Box = box, Items = list })
			end
		end
	end
	return result
end

----------------------------------------------------------------- Kody
-- Kod tak, jak go porównujemy: bez spacji i wielkimi literami („ larpinmiami” = LARPINMIAMI).
-- Zwraca nil dla pustego, zbyt długiego albo nietekstowego.
function Rewards.normalizeCode(text)
	if type(text) ~= "string" or #text > Rewards.CodeMaxLength * 4 then
		return nil
	end
	local code = string.upper((string.gsub(text, "%s", "")))
	if code == "" or #code > Rewards.CodeMaxLength then
		return nil
	end
	return code
end

-- Nagroda za kod (z Economy.Rewards.Codes) albo nil.
function Rewards.codeInfo(code)
	if type(code) ~= "string" then
		return nil
	end
	return Economy.Rewards.Codes[code]
end

-- Czy kod jeszcze działa: Ends = koniec w sekundach UTC (os.time()); bez Ends działa zawsze.
function Rewards.codeActive(info, now)
	return info ~= nil and (info.Ends == nil or now == nil or now < info.Ends)
end

-- Czy gracz już wpisał ten kod.
function Rewards.codeUsed(data, code)
	return type(data.Codes) == "table" and data.Codes[code] == true
end

-- Wpisany kod. limits jak w Rewards.fits, now = os.time() (dla kodów z końcem). Zwraca wynik jak
-- Rewards.grant (z polami Code i Label) albo nil i powód: Invalid (pusty albo za długi), Unknown
-- (nie ma takiego kodu), Expired, Used (już wpisany na tym koncie), PetInventory, ClothInventory.
-- Bez miejsca kod zostaje niewpisany, więc można go użyć po zrobieniu miejsca.
function Rewards.redeemCode(data, ctx, text, random01, limits, now)
	local code = Rewards.normalizeCode(text)
	if code == nil then
		return nil, "Invalid"
	end
	local info = Rewards.codeInfo(code)
	if info == nil then
		return nil, "Unknown"
	end
	if not Rewards.codeActive(info, now) then
		return nil, "Expired"
	end
	if type(data.Codes) ~= "table" then
		data.Codes = {}
	end
	if data.Codes[code] then
		return nil, "Used"
	end
	local ok, reason = Rewards.fits(data, info.Items, limits)
	if not ok then
		return nil, reason
	end
	data.Codes[code] = true
	local result = Rewards.grant(data, ctx, info.Items, random01)
	result.Code = code
	result.Label = info.Label
	return result
end

----------------------------------------------------------------- Nagroda dzienna
-- 7 dni z Economy.Rewards.DailyStreak. Dzień zmienia się o północy UTC (jak Verified i reklamy).
-- Odbiór dzień po dniu podnosi serię, a po dniu 7 cykl zaczyna się od dnia 1 (seria rośnie dalej).
-- Opuszczony dzień: seria od nowa (dzień 1). Zapis: data.Daily = { Day, Streak, Claimed }.
function Rewards.day(now)
	return Shop.day(now)
end

local function dailyOf(data)
	if type(data.Daily) ~= "table" then
		data.Daily = {}
	end
	local d = data.Daily
	d.Day = d.Day or 0 -- dzień UTC ostatniego odbioru (0 = nigdy)
	d.Streak = d.Streak or 0 -- ile dni pod rząd (rośnie też po dniu 7)
	d.Claimed = d.Claimed or 0 -- wszystkie odebrane nagrody dzienne
	return d
end

-- Stan nagrody dziennej w chwili now (sekundy UTC):
--   Day          dzień w cyklu (1–7): do odebrania albo odebrany dziś
--   CanClaim     czy można dziś odebrać
--   Streak       seria (przy zerwanej 0)
--   Lost         seria właśnie się zerwała (opuszczony dzień)
--   SecondsLeft  do następnej nagrody (0, gdy można odebrać)
--   Reward       nagroda dnia Day (z Economy.Rewards.DailyStreak)
function Rewards.dailyState(data, now)
	local d = dailyOf(data)
	local today = Rewards.day(now)
	local days = #Economy.Rewards.DailyStreak
	local state = { Streak = d.Streak, SecondsLeft = 0, Lost = false }
	if d.Day == today and d.Streak > 0 then
		state.CanClaim = false
		state.Day = ((d.Streak - 1) % days) + 1
		state.SecondsLeft = (today + 1) * Shop.DaySeconds - now
	elseif d.Day == today - 1 and d.Streak > 0 then
		state.CanClaim = true
		state.Day = (d.Streak % days) + 1
		state.Continues = true
	else
		state.CanClaim = true
		state.Day = 1
		state.Lost = d.Streak > 0
		state.Streak = 0
	end
	state.Reward = Economy.Rewards.DailyStreak[state.Day]
	return state
end

-- Odbiera dzisiejszą nagrodę. limits jak w Rewards.fits. Zwraca wynik jak Rewards.grant (z polami
-- Day i Streak) albo nil i powód: Claimed (już dziś), PetInventory, ClothInventory. Bez miejsca
-- nagroda czeka (można ją odebrać po zrobieniu miejsca, tego samego dnia).
function Rewards.claimDaily(data, ctx, random01, limits, now)
	local state = Rewards.dailyState(data, now)
	if not state.CanClaim then
		return nil, "Claimed"
	end
	local ok, reason = Rewards.fits(data, state.Reward.Items, limits)
	if not ok then
		return nil, reason
	end
	local d = dailyOf(data)
	if state.Continues then
		d.Streak = d.Streak + 1
	else
		d.Streak = 1
	end
	d.Day = Rewards.day(now)
	d.Claimed = d.Claimed + 1
	local result = Rewards.grant(data, ctx, state.Reward.Items, random01)
	result.Day = state.Day
	result.Streak = d.Streak
	return result
end

return Rewards
