-- Zakupy za Robuxy (Etap 10): co daje każdy produkt, boosty, Starter Pack, dzienny boost Verified,
-- limit reklam za nagrodę i pamięć paragonów. Czysta logika na zapisie gracza (bez Roblox API), więc
-- działa na serwerze i w testach (ShopSpec). ProcessReceipt obsługuje ShopService i woła Shop.grant.
--
-- Zasady z dokumentu projektu i z zasad Roblox o płatnych losowaniach (od 26.05.2026):
--   • za Robuxy nie ma L$, Aury ani niczego losowego poza premium jajkami (Starter Pack ma same pewne
--     rzeczy, bo losowa rzecz w paczce robi z całej paczki płatne losowanie),
--   • premium jajka mają stałe szanse (bez szczęścia), a ich pety (Egg = "P") łączą się tylko przy 100%,
--   • gracz z ograniczeniem płatnych losowań (PolicyService) zamiast jajka kupuje konkretnego peta
--     za cenę według wartości oczekiwanej (DirectPet…).

local Economy = require(script.Parent.Parent.Config.Economy)
local Formulas = require(script.Parent.Parent.Formulas)
local Loop = require(script.Parent.Loop)
local Clothes = require(script.Parent.Clothes)

local Shop = {}

Shop.ReceiptMemory = 100 -- tyle ostatnich PurchaseId pamiętamy (ProfileStore robi tak samo)
Shop.DaySeconds = 86400
Shop.BoostKinds = { "LP", "AutoSell" }

local PRODUCTS = Economy.Robux.Products

local function robuxOf(data)
	if type(data.Robux) ~= "table" then
		data.Robux = {}
	end
	local r = data.Robux
	if type(r.Receipts) ~= "table" then
		r.Receipts = {}
	end
	if type(r.Bought) ~= "table" then
		r.Bought = {}
	end
	r.Spent = r.Spent or 0
	r.AdDay = r.AdDay or 0
	r.AdCount = r.AdCount or 0
	r.VerifiedDay = r.VerifiedDay or 0
	return r
end

local function boostsOf(data)
	if type(data.Boosts) ~= "table" then
		data.Boosts = {}
	end
	local b = data.Boosts
	for _, kind in ipairs(Shop.BoostKinds) do
		if type(b[kind]) ~= "number" then
			b[kind] = 0
		end
	end
	return b
end

-- Numer dnia UTC (zmienia się o północy UTC).
function Shop.day(now)
	return math.floor(now / Shop.DaySeconds)
end

----------------------------------------------------------------- Paragony
function Shop.hasReceipt(data, purchaseId)
	for _, id in ipairs(robuxOf(data).Receipts) do
		if id == purchaseId then
			return true
		end
	end
	return false
end

function Shop.rememberReceipt(data, purchaseId)
	local list = robuxOf(data).Receipts
	if Shop.hasReceipt(data, purchaseId) then
		return
	end
	while #list >= Shop.ReceiptMemory do
		table.remove(list, 1)
	end
	table.insert(list, purchaseId)
end

----------------------------------------------------------------- Boosty
-- Dodaje minuty boosta (kupione boosty się sumują).
function Shop.addBoost(data, kind, minutes)
	local b = boostsOf(data)
	if b[kind] == nil or type(minutes) ~= "number" or minutes <= 0 then
		return 0
	end
	b[kind] = b[kind] + minutes * 60
	return b[kind]
end

function Shop.boostLeft(data, kind)
	return boostsOf(data)[kind] or 0
end

-- Odlicza czas boostów (tylko gdy gracz jest w grze). Zwraca listę boostów, które się właśnie skończyły.
function Shop.tickBoosts(data, dt)
	local b = boostsOf(data)
	local ended = {}
	for _, kind in ipairs(Shop.BoostKinds) do
		if b[kind] > 0 then
			b[kind] = b[kind] - dt
			if b[kind] <= 0 then
				b[kind] = 0
				table.insert(ended, kind)
			end
		end
	end
	return ended
end

----------------------------------------------------------------- Verified
-- Raz dziennie (dzień UTC) gracz z Verified dostaje boost 2x LP. Zwraca minuty (0, gdy już był).
function Shop.verifiedDaily(data, now)
	local r = robuxOf(data)
	local today = Shop.day(now)
	if r.VerifiedDay == today then
		return 0
	end
	r.VerifiedDay = today
	local minutes = Economy.Robux.Gamepasses.Verified.DailyBoostMinutes
	Shop.addBoost(data, "LP", minutes)
	return minutes
end

----------------------------------------------------------------- Reklamy za nagrodę
function Shop.adsLeft(data, now)
	local r = robuxOf(data)
	local max = Economy.Bonuses.RewardedVideoDailyMax
	if r.AdDay ~= Shop.day(now) then
		return max
	end
	return math.max(0, max - r.AdCount)
end

-- Liczy obejrzaną reklamę. Zwraca false, gdy dzisiejszy limit już minął.
function Shop.countAd(data, now)
	local r = robuxOf(data)
	local today = Shop.day(now)
	if r.AdDay ~= today then
		r.AdDay = today
		r.AdCount = 0
	end
	if r.AdCount >= Economy.Bonuses.RewardedVideoDailyMax then
		return false
	end
	r.AdCount = r.AdCount + 1
	return true
end

----------------------------------------------------------------- Starter Pack
-- Ile sekund zostało do końca oferty (0, gdy już kupiony albo minęło 72 h od pierwszego wejścia).
function Shop.starterSecondsLeft(data, now)
	if robuxOf(data).StarterPack then
		return 0
	end
	local first = data.FirstJoin
	if type(first) ~= "number" or first <= 0 then
		first = now
	end
	local ends = first + PRODUCTS.StarterPack.HoursAvailable * 3600
	return math.max(0, ends - now)
end

----------------------------------------------------------------- Premium jajka
-- Strefa premium jajka: wybrana, gdy jest odblokowana i ma premium jajko, inaczej najwyższa
-- odblokowana z premium jajkiem (np. paragon, który przyszedł dopiero po ponownym wejściu).
function Shop.premiumZone(data, zone)
	local unlocked = data.ZonesUnlocked or 1
	if type(zone) == "number" and zone >= 1 and zone <= unlocked and Loop.premiumInfo(zone) ~= nil then
		return zone
	end
	for z = math.min(unlocked, #Economy.Pets.Eggs), 1, -1 do
		if Loop.premiumInfo(z) ~= nil then
			return z
		end
	end
	return 1
end

-- Otwiera count premium jajek strefy: stałe szanse (bez szczęścia z Aury i bez trybu testowego),
-- jak w oknie jajka. Zwraca listę { id, pet, new }.
function Shop.openPremium(data, ctx, zone, count, random01)
	local info = Loop.premiumInfo(zone)
	local list = {}
	if info == nil then
		return list
	end
	for _ = 1, count do
		local rarity = Formulas.roll(info.Odds, 1, random01)
		local id, pet, isNew = Loop.addPet(data, ctx, zone, rarity, "P")
		table.insert(list, { id = id, pet = pet, new = isNew })
		data.Stats.PremiumEggs = (data.Stats.PremiumEggs or 0) + 1
		data.Stats.EggsOpened = data.Stats.EggsOpened + 1
	end
	return list
end

-- Rzadkość peta z produktu DirectPet… (nil dla innych produktów).
function Shop.directRarity(key)
	local info = PRODUCTS[key]
	if info ~= nil and string.sub(key, 1, 9) == "DirectPet" then
		return info.Rarity
	end
	return nil
end

----------------------------------------------------------------- Zanim pokażemy okno zakupu
-- Czy produkt można teraz kupić (serwer sprawdza to przed oknem zakupu Roblox). opts.zone = strefa
-- stoiska premium jajka, opts.restricted = gracz z ograniczeniem płatnych losowań. Zwraca true albo
-- false i powód: Unknown, Zone, Restricted, NotRestricted, Expired, Owned, EmptyBag.
function Shop.canPrompt(data, key, opts, now)
	local info = PRODUCTS[key]
	if info == nil then
		return false, "Unknown"
	end
	opts = opts or {}
	if info.Count ~= nil then -- premium jajka
		if opts.restricted then
			return false, "Restricted"
		end
		local zone = opts.zone
		if type(zone) ~= "number" or Loop.premiumInfo(zone) == nil then
			return false, "Zone"
		end
		if zone > (data.ZonesUnlocked or 1) then
			return false, "Zone"
		end
	elseif Shop.directRarity(key) ~= nil then
		if not opts.restricted then
			return false, "NotRestricted"
		end
		local zone = opts.zone
		if type(zone) ~= "number" or Loop.premiumInfo(zone) == nil or zone > (data.ZonesUnlocked or 1) then
			return false, "Zone"
		end
	elseif key == "StarterPack" then
		if robuxOf(data).StarterPack then
			return false, "Owned"
		end
		if Shop.starterSecondsLeft(data, now) <= 0 then
			return false, "Expired"
		end
	elseif key == "SellNow" then
		if (data.Bag or 0) <= 0 then
			return false, "EmptyBag"
		end
	end
	return true, nil
end

----------------------------------------------------------------- Przyznanie produktu
-- Daje graczowi kupiony produkt. opts:
--   zone      strefa (premium jajko, DirectPet); bez niej najwyższa odblokowana
--   random01  losowanie (premium jajka)
--   ad        true: nagroda za reklamę (liczy się do dziennego limitu)
--   spent     ile Robuxów wydano (z paragonu)
--   restricted  gracz z ograniczeniem płatnych losowań: premium jajko kupione mimo to (np. w sklepie
--             Roblox, gdy produkt nie był ukryty) daje bez losowania peta Epic za każde jajko
-- Zwraca wynik dla gracza (Kind: Pets, Starter, Boost, Sell) albo nil i powód (Unknown).
function Shop.grant(data, ctx, key, opts)
	local info = PRODUCTS[key]
	if info == nil then
		return nil, "Unknown"
	end
	opts = opts or {}
	local r = robuxOf(data)
	r.Bought[key] = (r.Bought[key] or 0) + 1
	if type(opts.spent) == "number" and opts.spent > 0 then
		r.Spent = r.Spent + opts.spent
	end
	local random01 = opts.random01 or math.random

	if info.Count ~= nil then
		local zone = Shop.premiumZone(data, opts.zone)
		if opts.restricted then
			local list = {}
			for _ = 1, info.Count do
				local id, pet, isNew = Loop.addPet(data, ctx, zone, PRODUCTS.DirectPetEpic.Rarity, "P")
				table.insert(list, { id = id, pet = pet, new = isNew })
			end
			return { Kind = "Pets", Key = key, Zone = zone, Pets = list, Direct = true }
		end
		return { Kind = "Pets", Key = key, Zone = zone, Pets = Shop.openPremium(data, ctx, zone, info.Count, random01) }
	end
	local rarity = Shop.directRarity(key)
	if rarity ~= nil then
		local zone = Shop.premiumZone(data, opts.zone)
		local id, pet, isNew = Loop.addPet(data, ctx, zone, rarity, "P")
		return { Kind = "Pets", Key = key, Zone = zone, Pets = { { id = id, pet = pet, new = isNew } } }
	end
	if key == "StarterPack" then
		r.StarterPack = true
		local itemId, item, worn = Clothes.addItem(data, ctx, "Watch", info.Watch, 0, "P")
		local zone = math.max(1, math.min(data.ZonesUnlocked or 1, #Economy.Pets.Eggs))
		local petId, pet, isNew = Loop.addPet(data, ctx, zone, info.PetRarity, "P")
		Shop.addBoost(data, "LP", info.BoostMinutes)
		Shop.addBoost(data, "AutoSell", info.AutoSellMinutes)
		return {
			Kind = "Starter",
			Key = key,
			Item = { id = itemId, item = item, worn = worn },
			Pet = { id = petId, pet = pet, new = isNew },
			BoostMinutes = info.BoostMinutes,
			AutoSellMinutes = info.AutoSellMinutes,
		}
	end
	if key == "SellNow" then
		local lp = data.Bag or 0
		local cash = Loop.sell(data, ctx)
		return { Kind = "Sell", Key = key, LP = lp, Cash = cash }
	end
	if info.Minutes ~= nil then
		local kind = "LP"
		if string.find(key, "AutoSell", 1, true) then
			kind = "AutoSell"
		end
		local counted = nil
		if opts.ad then
			counted = Shop.countAd(data, opts.now or 0)
		end
		local left = Shop.addBoost(data, kind, info.Minutes)
		return { Kind = "Boost", Key = key, Boost = kind, Minutes = info.Minutes, Left = left, Ad = opts.ad == true, Counted = counted }
	end
	return nil, "Unknown"
end

return Shop
