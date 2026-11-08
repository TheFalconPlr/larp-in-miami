-- Nagrody (Etap 11): kody, a w kolejnych częściach nagroda dzienna i zadania dzienne. Czysta logika na
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

return Rewards
