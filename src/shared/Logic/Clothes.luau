-- Ubrania (Etap 8, zasady z dokumentu projektu): 7 kategorii po 1 slocie (Chain i Watch po 2
-- z gamepassami Double Chain i Double Wrist), bonus do LP według rzadkości (Golden ×2, Diamond ×4),
-- 3 mystery boxy w Mall (Street; Designer po odblokowaniu plaży; Iced po odblokowaniu lotniska)
-- oraz sprzedaż i łączenie na tych samych zasadach co pety. Czysta logika bez Roblox API
-- (testy w tools/test_luau.py i w Studio).
--
-- Ubranie w zapisie: data.Clothes[id] = { Category = "Chain", Rarity = "Rare", Level = 0, Box = "Street" }
-- (Level 0 zwykłe, 1 Golden, 2 Diamond; Box = P: kupione za Robuxy, łączy się tylko przy 100%).
-- data.Worn = lista id założonych ubrań. Warstwa ubrań (Clothes.layer) mnoży LP: LoopService
-- wpisuje ją do ctx.clothLayer, a Loop.lpMultiplier ją uwzględnia.

local Economy = require(script.Parent.Parent.Config.Economy)
local Formulas = require(script.Parent.Parent.Formulas)

local Clothes = {}

local C = Economy.Clothes
local MERGE = Economy.Pets.Merge
local LEVEL_SELL = { [0] = 1, [1] = C.GoldSellX, [2] = C.DiamondSellX }
local NO_PASSES = {}

Clothes.Categories = C.Categories
Clothes.BoxOrder = { "Street", "Designer", "Iced" }

local CATEGORY = {}
for i, name in ipairs(C.Categories) do
	CATEGORY[name] = i
end

-- Zaokrąglenie jak w arkuszu: połówki w górę.
local function roundHalfUp(x)
	return math.floor(x + 0.5 + 1e-9)
end

local function passesOf(ctx)
	return (ctx and ctx.passes) or NO_PASSES
end

function Clothes.isCategory(name)
	return CATEGORY[name] ~= nil
end

function Clothes.categoryIndex(name)
	return CATEGORY[name]
end

-- Sloty w kategorii: 1, a Chain i Watch po 2 z gamepassem (Double Chain, Double Wrist).
function Clothes.slots(ctx, category)
	local pass = C.ExtraSlotGamepass[category]
	if pass ~= nil and passesOf(ctx)[pass] then
		return 2
	end
	return 1
end

-- Bonus ubrania do LP jako ułamek, np. Rare = 0,8 (+80% LP).
function Clothes.bonus(item)
	return Formulas.clothBonus(item.Rarity, item.Level or 0)
end

function Clothes.count(data)
	local n = 0
	for _ in pairs(data.Clothes) do
		n = n + 1
	end
	return n
end

-- Założone ubrania, które naprawdę działają: istnieją i mieszczą się w slotach swojej kategorii
-- (np. po utracie gamepassa Double Chain działa tylko pierwszy łańcuch).
function Clothes.active(data, ctx)
	local used = {}
	local list = {}
	for _, id in ipairs(data.Worn) do
		local item = data.Clothes[id]
		if item ~= nil then
			local n = used[item.Category] or 0
			if n < Clothes.slots(ctx, item.Category) then
				used[item.Category] = n + 1
				table.insert(list, id)
			end
		end
	end
	return list
end

function Clothes.isWorn(data, id)
	for _, existing in ipairs(data.Worn) do
		if existing == id then
			return true
		end
	end
	return false
end

-- Założone ubrania według kategorii: [kategoria] = lista id (pierwsze założone najpierw).
function Clothes.wornByCategory(data, ctx)
	local out = {}
	for _, id in ipairs(Clothes.active(data, ctx)) do
		local category = data.Clothes[id].Category
		if out[category] == nil then
			out[category] = {}
		end
		table.insert(out[category], id)
	end
	return out
end

-- Warstwa ubrań: 1 + suma bonusów założonych ubrań (w warstwie dodajemy). Mnoży LP.
function Clothes.layer(data, ctx)
	local layer = 1
	for _, id in ipairs(Clothes.active(data, ctx)) do
		layer = layer + Clothes.bonus(data.Clothes[id])
	end
	return layer
end

-- Czy ubranie warto założyć od razu: w jego kategorii jest wolny slot albo jest lepsze od
-- najsłabszego założonego.
function Clothes.betterThanWorn(data, ctx, item)
	local worn = Clothes.wornByCategory(data, ctx)[item.Category] or {}
	if #worn < Clothes.slots(ctx, item.Category) then
		return true
	end
	local bonus = Clothes.bonus(item)
	for _, id in ipairs(worn) do
		if bonus > Clothes.bonus(data.Clothes[id]) + 1e-12 then
			return true
		end
	end
	return false
end

-- Zakłada ubranie. Gdy sloty kategorii są pełne, zdejmuje najsłabsze z tej kategorii (jak zmiana
-- czapki na nową). Zwraca true albo false i powód: Missing, Already.
function Clothes.wear(data, ctx, id)
	local item = data.Clothes[id]
	if item == nil then
		return false, "Missing"
	end
	data.Worn = Clothes.active(data, ctx)
	if Clothes.isWorn(data, id) then
		return false, "Already"
	end
	local same = {}
	for i, other in ipairs(data.Worn) do
		if data.Clothes[other].Category == item.Category then
			table.insert(same, i)
		end
	end
	if #same >= Clothes.slots(ctx, item.Category) then
		local weakest = same[1]
		for _, i in ipairs(same) do
			if Clothes.bonus(data.Clothes[data.Worn[i]]) < Clothes.bonus(data.Clothes[data.Worn[weakest]]) then
				weakest = i
			end
		end
		table.remove(data.Worn, weakest)
	end
	table.insert(data.Worn, id)
	return true, nil
end

function Clothes.unwear(data, id)
	for i = #data.Worn, 1, -1 do
		if data.Worn[i] == id then
			table.remove(data.Worn, i)
			return true, nil
		end
	end
	return false, "NotWorn"
end

-- Ubrania od najlepszego (przy równym bonusie starsze pierwsze). Zwraca listę id.
function Clothes.byBonus(data)
	local ids = {}
	for id in pairs(data.Clothes) do
		table.insert(ids, id)
	end
	table.sort(ids, function(a, b)
		local ba, bb = Clothes.bonus(data.Clothes[a]), Clothes.bonus(data.Clothes[b])
		if ba ~= bb then
			return ba > bb
		end
		return (tonumber(a) or 0) < (tonumber(b) or 0)
	end)
	return ids
end

-- Zakłada najlepsze ubranie w każdej kategorii (na wszystkie sloty).
function Clothes.wearBest(data, ctx)
	local used = {}
	local best = {}
	for _, id in ipairs(Clothes.byBonus(data)) do
		local category = data.Clothes[id].Category
		local n = used[category] or 0
		if n < Clothes.slots(ctx, category) then
			used[category] = n + 1
			table.insert(best, id)
		end
	end
	data.Worn = best
	return best
end

----------------------------------------------------------------- Boxy
-- Box z arkusza (Price, RequiresZone, Odds) albo nil.
function Clothes.boxInfo(box)
	local info = C.Boxes[box]
	if info == nil or info.Price == nil then
		return nil
	end
	return info
end

-- Czy można kupić count boxów naraz. Zwraca true albo false i powód: BadRequest, Zone (trzeba
-- odblokować strefę RequiresZone), Inventory (nie zmieszczą się), NotEnough (nie stać).
function Clothes.canBuy(data, box, count, maxItems)
	local info = Clothes.boxInfo(box)
	if count == nil then
		count = 1
	end
	if info == nil or type(count) ~= "number" or count < 1 or count ~= math.floor(count) then
		return false, "BadRequest"
	end
	if data.ZonesUnlocked < info.RequiresZone then
		return false, "Zone"
	end
	if maxItems ~= nil and Clothes.count(data) + count > maxItems then
		return false, "Inventory"
	end
	if data.Cash < info.Price * count then
		return false, "NotEnough"
	end
	return true, nil
end

-- Kupuje i otwiera box. random01 = funkcja losująca liczbę z [0, 1). Najpierw rzadkość (szczęście
-- z Aury działa na boxy za L$), potem kategoria (każda tak samo często). Nowe ubranie samo się
-- zakłada, gdy w kategorii jest wolny slot albo jest lepsze od najsłabszego założonego.
-- Zwraca id, ubranie i czy zostało założone albo nil i powód (jak canBuy).
function Clothes.openBox(data, ctx, box, random01, maxItems)
	local ok, reason = Clothes.canBuy(data, box, 1, maxItems)
	if not ok then
		return nil, reason
	end
	local info = Clothes.boxInfo(box)
	data.Cash = data.Cash - info.Price
	local luck = 1
	if info.LuckApplies ~= false then
		luck = Formulas.luck(data.AuraUpgrades.Luck)
	end
	local rarity = Formulas.roll(info.Odds, luck, random01)
	local n = #C.Categories
	local index = math.floor(random01() * n) + 1
	if index > n then
		index = n
	end
	local item = { Category = C.Categories[index], Rarity = rarity, Level = 0, Box = box }
	local id = tostring(data.NextClothId)
	data.NextClothId = data.NextClothId + 1
	data.Clothes[id] = item
	data.Stats.BoxesOpened = (data.Stats.BoxesOpened or 0) + 1
	local worn = false
	if Clothes.betterThanWorn(data, ctx, item) then
		Clothes.wear(data, ctx, id)
		worn = true
	end
	return id, item, worn
end

----------------------------------------------------------------- Sprzedaż i łączenie
-- Cena ubrania tej rzadkości: cena boxa, z którego zwykle pochodzi (SourceBox: Common–Epic Street,
-- Legendary Designer, Mythic Iced). Tak liczy opłatę za łączenie model ekonomii, więc identyczne
-- ubrania mają tę samą wartość bez względu na to, z którego boxa wypadły.
function Clothes.sourcePrice(rarity)
	local box = C.SourceBox[rarity]
	local info = box and C.Boxes[box]
	return (info and info.Price) or 0
end

-- Ile L$ za sprzedaż: 10% tej ceny, Golden ×5, Diamond ×25.
function Clothes.sellValue(item)
	return roundHalfUp(Clothes.sourcePrice(item.Rarity) * C.SellReturn * (LEVEL_SELL[item.Level or 0] or 1))
end

-- Sprzedaje ubrania za L$. Założonych nie sprzedaje. Zwraca liczbę sprzedanych i L$.
function Clothes.sell(data, ctx, ids)
	data.Worn = Clothes.active(data, ctx)
	local count, cash = 0, 0
	for _, id in ipairs(ids) do
		local item = data.Clothes[id]
		if item ~= nil and not Clothes.isWorn(data, id) then
			cash = cash + Clothes.sellValue(item)
			data.Clothes[id] = nil
			count = count + 1
		end
	end
	data.Cash = data.Cash + cash
	data.Stats.LifetimeCash = (data.Stats.LifetimeCash or 0) + cash
	data.Stats.ClothesSold = (data.Stats.ClothesSold or 0) + count
	return count, cash
end

-- Łączenie jak u petów: 1–5 identycznych ubrań (kategoria, rzadkość i poziom), każde daje 20%
-- szansy (+1 pkt proc. za poziom Merge Luck). Sukces daje wersję Golden (z Golden: Diamond),
-- porażka zabiera wszystkie użyte. Opłata za sztukę to 1/5 pełnej (cena × 1 za Golden, × 5 za
-- Diamond). Kupione za Robuxy tylko przy 100%. Zwraca { Chance, Fee, Level (po łączeniu),
-- Category, Rarity, Pieces, Premium } albo nil i powód: BadRequest, Missing, NotSame, MaxLevel, Premium.
function Clothes.mergeInfo(data, ids)
	if type(ids) ~= "table" or #ids < 1 or #ids > MERGE.MaxPieces then
		return nil, "BadRequest"
	end
	local first = nil
	local seen = {}
	local premium = false
	for _, id in ipairs(ids) do
		local item = nil
		if type(id) == "string" then
			item = data.Clothes[id]
		end
		if item == nil or seen[id] then
			return nil, "Missing"
		end
		seen[id] = true
		if first == nil then
			first = item
		elseif item.Category ~= first.Category or item.Rarity ~= first.Rarity or (item.Level or 0) ~= (first.Level or 0) then
			return nil, "NotSame"
		end
		if item.Box == "P" then
			premium = true
		end
	end
	local level = first.Level or 0
	if level >= 2 then
		return nil, "MaxLevel"
	end
	local chance = Formulas.mergeChance(#ids, (data.AuraUpgrades and data.AuraUpgrades.MergeLuck) or 0)
	if premium and chance < 1 - 1e-9 then
		return nil, "Premium"
	end
	local feeX = MERGE.GoldFeeX
	if level == 1 then
		feeX = MERGE.DiamondFeeX
	end
	local fee = Clothes.sourcePrice(first.Rarity) * feeX * #ids / MERGE.MaxPieces
	return {
		Chance = chance,
		Fee = roundHalfUp(fee),
		Level = level + 1,
		Category = first.Category,
		Rarity = first.Rarity,
		Pieces = #ids,
		Premium = premium,
	}
end

-- Łączy ubrania (opłata zawsze, wynik losowy). random01() < szansa = sukces. Nowe ubranie zakłada
-- się, gdy któreś z połączonych było założone albo jest lepsze od założonych. Zwraca
-- { Success, Id, Item, Info, Worn } albo nil i powód (jak mergeInfo albo NotEnough).
function Clothes.merge(data, ctx, ids, random01)
	local info, reason = Clothes.mergeInfo(data, ids)
	if info == nil then
		return nil, reason
	end
	if data.Cash < info.Fee then
		return nil, "NotEnough"
	end
	data.Cash = data.Cash - info.Fee
	data.Worn = Clothes.active(data, ctx)
	local wasWorn = false
	local box = nil
	for _, id in ipairs(ids) do
		local item = data.Clothes[id]
		box = box or item.Box
		for i = #data.Worn, 1, -1 do
			if data.Worn[i] == id then
				table.remove(data.Worn, i)
				wasWorn = true
			end
		end
		data.Clothes[id] = nil
	end
	data.Stats.ClothMerges = (data.Stats.ClothMerges or 0) + 1
	if random01() >= info.Chance then
		data.Stats.ClothMergesFailed = (data.Stats.ClothMergesFailed or 0) + 1
		return { Success = false, Info = info }
	end
	local id = tostring(data.NextClothId)
	data.NextClothId = data.NextClothId + 1
	local item = { Category = info.Category, Rarity = info.Rarity, Level = info.Level, Box = box }
	if info.Premium then
		item.Box = "P"
	end
	data.Clothes[id] = item
	local worn = false
	if wasWorn or Clothes.betterThanWorn(data, ctx, item) then
		Clothes.wear(data, ctx, id)
		worn = true
	end
	return { Success = true, Id = id, Item = item, Info = info, Worn = worn }
end

----------------------------------------------------------------- Widok dla HUD
function Clothes.view(data, ctx)
	return {
		ClothLayer = Clothes.layer(data, ctx),
		ClothesCount = Clothes.count(data),
		ClothesWorn = #Clothes.active(data, ctx),
		BoxesOpened = data.Stats.BoxesOpened or 0,
		ShowClothes = data.Settings.ShowClothes ~= false,
	}
end

return Clothes
