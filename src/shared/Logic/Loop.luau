-- Rdzeń pętli: LP za klik, Bag, Sell, ulepszenia i strefy za L$ oraz aktywności (nagroda, tiery).
-- Same obliczenia na danych gracza,
-- bez Roblox API, więc działają na serwerze, w UI i w testach (tools/test_luau.py).
--
-- data to zapis gracza (Shared/Data/Template). ctx opisuje to, czego nie ma w zapisie:
--   zone        strefa, której mnożnik dostaje gracz (Loop.effectiveZone), domyślnie 1
--   passes      gamepassy, np. { TwoXLP = true, AutoSell = true }
--   inGroup     gracz jest w grupie gry (+5% LP)
--   friends     liczba znajomych na serwerze (+10% LP każdy, maks. 3)
--   boost       aktywny boost 2x LP
--   autoSellBoost  aktywny boost Auto-Sell
--   clothLayer  warstwa ubrań (Etap 8), domyślnie 1
--   petLayer    warstwa petów, mnoży L$ przy Sell (Etap 5), domyślnie 1

local Economy = require(script.Parent.Parent.Config.Economy)
local Formulas = require(script.Parent.Parent.Formulas)
local Rebirth = require(script.Parent.Rebirth)

local Loop = {}

local NO_PASSES = {}

local function passesOf(ctx)
	return (ctx and ctx.passes) or NO_PASSES
end

local function maxKey(t)
	local m = 0
	for k in pairs(t) do
		if type(k) == "number" and k > m then
			m = k
		end
	end
	return m
end

Loop.MaxLevel = {
	Click = Economy.ClickMultiplier.MaxLevel,
	Bag = maxKey(Economy.Bag.Costs),
}

local LEVEL_FIELD = { Click = "ClickLevel", Bag = "BagLevel" }

----------------------------------------------------------------- LP
-- Warstwa bonusów. W warstwie dodajemy: 2x LP +100%, Verified +10%, grupa +5%, znajomi +10% każdy.
function Loop.lpBonus(ctx)
	local passes = passesOf(ctx)
	local gp = Economy.Robux.Gamepasses
	local b = 1
	if passes.TwoXLP then
		b = b + gp.TwoXLP.LPBonus
	end
	if passes.Verified then
		b = b + gp.Verified.LPBonus
	end
	if ctx and ctx.inGroup then
		b = b + Economy.Bonuses.Group
	end
	local friends = (ctx and ctx.friends) or 0
	if friends > Economy.Bonuses.FriendMax then
		friends = Economy.Bonuses.FriendMax
	end
	b = b + Economy.Bonuses.FriendEach * friends
	return b
end

-- Mnożnik LP bez wartości kliku i strefy. Między warstwami mnożymy:
-- Click Boost (Aura) × Rebirth × ubrania × bonusy × boost. Ten sam mnożnik mają aktywności.
function Loop.lpMultiplier(data, ctx)
	local m = Formulas.clickBoost(data.AuraUpgrades.ClickBoost)
	m = m * Economy.Rebirth.LPMultiplier[data.RebirthLevel]
	m = m * ((ctx and ctx.clothLayer) or 1)
	m = m * Loop.lpBonus(ctx)
	if ctx and ctx.boost then
		m = m * Economy.Bonuses.BoostX
	end
	return m
end

function Loop.zoneMultiplier(ctx)
	local zone = Economy.Zones[(ctx and ctx.zone) or 1] or Economy.Zones[1]
	return zone.ClickMultiplier
end

-- LP za jedno kliknięcie przy danym poziomie Click Multipliera.
function Loop.clickLPAt(level, data, ctx)
	return Formulas.clickValue(level) * Loop.zoneMultiplier(ctx) * Loop.lpMultiplier(data, ctx)
end

function Loop.clickLP(data, ctx)
	return Loop.clickLPAt(data.ClickLevel, data, ctx)
end

----------------------------------------------------------------- Bag i Sell
function Loop.capacityAt(level, ctx)
	return Formulas.bagCapacity(level, passesOf(ctx).TwoXBag == true)
end

function Loop.capacity(data, ctx)
	return Loop.capacityAt(data.BagLevel, ctx)
end

-- Auto-Sell działa z gamepassem (albo boostem), jeśli gracz go nie wyłączył.
function Loop.autoSellOn(data, ctx)
	local has = passesOf(ctx).AutoSell or (ctx and ctx.autoSellBoost)
	if has and data.Settings.AutoSell ~= false then
		return true
	end
	return false
end

function Loop.isFull(data, ctx)
	return (not Loop.autoSellOn(data, ctx)) and data.Bag >= Loop.capacity(data, ctx)
end

-- L$ za sprzedaż całego Bag (pety mnożą L$).
function Loop.sellValue(data, ctx)
	return data.Bag * ((ctx and ctx.petLayer) or 1)
end

-- Sprzedaje cały Bag. Zwraca zarobione L$ (0, gdy Bag był pusty).
function Loop.sell(data, ctx)
	if data.Bag <= 0 then
		return 0
	end
	local gained = Loop.sellValue(data, ctx)
	data.Cash = data.Cash + gained
	data.Bag = 0
	data.Stats.Sells = data.Stats.Sells + 1
	data.Stats.LifetimeCash = data.Stats.LifetimeCash + gained
	return gained
end

-- Dodaje LP do Bag. Kliknięcia zatrzymują się na pojemności, a force = true (nagrody z aktywności)
-- wkłada całość nawet do pełnego Bag. Z Auto-Sell pełny Bag sprzedaje się sam, więc nic nie przepada.
-- Zwraca: ile LP weszło do Bag i ile L$ dała automatyczna sprzedaż.
function Loop.collect(data, amount, ctx, force)
	local cap = Loop.capacity(data, ctx)
	local autoSell = Loop.autoSellOn(data, ctx)
	local added = amount
	if not (force or autoSell) then
		added = cap - data.Bag
		if added > amount then
			added = amount
		end
		if added < 0 then
			added = 0
		end
	end
	data.Bag = data.Bag + added
	data.Stats.LifetimeLP = data.Stats.LifetimeLP + added
	local sold = 0
	if autoSell and data.Bag >= cap then
		sold = Loop.sell(data, ctx)
	end
	return added, sold
end

-- Jedno kliknięcie: LP do Bag i licznik kliknięć (liczą się tylko kliknięcia, które coś dały).
function Loop.click(data, ctx)
	local added, sold = Loop.collect(data, Loop.clickLP(data, ctx), ctx, false)
	if added > 0 then
		data.Stats.Clicks = data.Stats.Clicks + 1
	end
	return added, sold
end

----------------------------------------------------------------- Ulepszenia za L$
-- Koszt poziomu `level`, czyli przejścia z level − 1 na level. nil po limicie.
function Loop.levelCost(kind, level)
	if kind == "Click" then
		return Formulas.clickCost(level)
	elseif kind == "Bag" then
		return Formulas.bagCost(level)
	end
	return nil
end

-- Koszt następnego poziomu albo nil, gdy gracz ma już maksimum.
function Loop.nextCost(data, kind)
	local field = LEVEL_FIELD[kind]
	if field == nil then
		return nil
	end
	local level = data[field]
	if level >= Loop.MaxLevel[kind] then
		return nil
	end
	return Loop.levelCost(kind, level + 1)
end

-- Ile kolejnych poziomów (od `level`) da się kupić za `cash`, najwyżej `limit`, i za ile.
function Loop.affordable(kind, level, cash, limit)
	local count, total = 0, 0
	limit = limit or math.huge
	while count < limit and level + count < Loop.MaxLevel[kind] do
		local c = Loop.levelCost(kind, level + count + 1)
		if c == nil or total + c > cash then
			break
		end
		total = total + c
		count = count + 1
	end
	return count, total
end

-- Kupuje do `limit` poziomów (1 = „Kup 1”, nil = „Kup max”). Zwraca liczbę poziomów i koszt.
function Loop.buy(data, kind, limit)
	local field = LEVEL_FIELD[kind]
	if field == nil then
		return 0, 0
	end
	local count, total = Loop.affordable(kind, data[field], data.Cash, limit)
	if count > 0 then
		data.Cash = data.Cash - total
		data[field] = data[field] + count
	end
	return count, total
end

----------------------------------------------------------------- Strefy
-- Strefa, której mnożnik dostaje gracz: ta, w której stoi, ale najwyżej ostatnia odblokowana
-- (kto obejdzie bramkę, nie dostanie lepszego mnożnika). standing nil = strefa 1.
function Loop.effectiveZone(data, standing)
	local zone = standing or 1
	if zone > data.ZonesUnlocked then
		zone = data.ZonesUnlocked
	end
	if zone < 1 then
		zone = 1
	end
	return zone
end

-- Następna strefa do kupienia (tabela z Economy.Zones) albo nil, gdy wszystkie są odblokowane.
function Loop.nextZone(data)
	return Economy.Zones[data.ZonesUnlocked + 1]
end

-- Kupuje strefę `id`. Strefy kupuje się po kolei. Zwraca true albo false i powód:
-- BadRequest (nie ma takiej strefy), Owned (już kupiona), Locked (najpierw poprzednia), NotEnough.
function Loop.buyZone(data, id)
	local zone = Economy.Zones[id]
	if zone == nil then
		return false, "BadRequest"
	end
	if id <= data.ZonesUnlocked then
		return false, "Owned"
	end
	if id ~= data.ZonesUnlocked + 1 then
		return false, "Locked"
	end
	if data.Cash < zone.Cost then
		return false, "NotEnough"
	end
	data.Cash = data.Cash - zone.Cost
	data.ZonesUnlocked = id
	return true, nil
end

----------------------------------------------------------------- Aktywności
-- Aktywności w strefach 2–5: zdjęcia z autem, wywiad (losowa ocena), impreza na jachcie, lot odrzutowcem.
Loop.ActivityKinds = { "Car", "Interview", "Yacht", "Jet" }

-- Licznik sesji w zapisie (pod zadania dzienne, Etap 10).
local ACTIVITY_STAT = { Car = "CarPhotos", Interview = "Interviews", Yacht = "YachtParties", Jet = "JetFlights" }

-- Ile tierów aktywności gracz ma (1 = pierwszy). Pierwszy tier z ceną 0 jest za darmo, a aktywność
-- bez tierów (wywiad) jest zawsze dostępna (tier 1). Pierwszy odrzutowiec trzeba kupić (tier 0).
function Loop.activityTier(data, kind)
	local activity = Economy.Activities[kind]
	if activity ~= nil and activity.Tiers == nil then
		return 1
	end
	local owned = data.ActivityTiers and data.ActivityTiers[kind]
	if owned ~= nil then
		return owned
	end
	local first = activity and activity.Tiers and activity.Tiers[1]
	if first ~= nil and first.Cost == 0 then
		return 1
	end
	return 0
end

-- Mnożnik obecnego tieru (0, gdy gracz nie ma żadnego).
local function tierMultiplier(kind, tier)
	local activity = Economy.Activities[kind]
	if activity.Tiers == nil then
		return 1
	end
	local info = activity.Tiers[tier]
	return (info and info.Multiplier) or 0
end

-- Mnożnik oceny (wywiad: Flop ×0,5 … Mega viral ×4); bez ocen 1.
local function gradeMultiplier(kind, grade)
	local grades = Economy.Activities[kind].Grades
	if grades == nil then
		return 1
	end
	local info = grades[grade]
	return (info and info.Multiplier) or 1
end

-- Losuje ocenę aktywności z szans w arkuszu (random01 = liczba z [0, 1)). Bez ocen nil.
function Loop.rollGrade(kind, random01)
	local grades = Economy.Activities[kind] and Economy.Activities[kind].Grades
	if grades == nil then
		return nil
	end
	local r = random01()
	local acc = 0
	for i, grade in ipairs(grades) do
		acc = acc + grade.Chance
		if r < acc then
			return i
		end
	end
	return #grades
end

-- Ocena „średnia” (mnożnik 1, np. Solid) do pokazywania nagrody przed sesją.
local function baseGrade(kind)
	local grades = Economy.Activities[kind].Grades
	if grades == nil then
		return nil
	end
	for i, grade in ipairs(grades) do
		if grade.Multiplier == 1 then
			return i
		end
	end
	return 1
end

local function rewardWith(data, ctx, kind, multiplier)
	return Formulas.clickValue(data.ClickLevel) * Economy.Activities[kind].Base * multiplier * Loop.lpMultiplier(data, ctx)
end

-- LP za jedną sesję: wartość kliku × baza aktywności × tier × ocena × mnożnik LP (bez mnożnika strefy).
-- grade = numer oceny (wywiad); bez niego liczy się ocena z mnożnikiem 1.
function Loop.activityReward(data, ctx, kind, grade)
	local multiplier = tierMultiplier(kind, Loop.activityTier(data, kind))
	multiplier = multiplier * gradeMultiplier(kind, grade or baseGrade(kind))
	return rewardWith(data, ctx, kind, multiplier)
end

-- Czy można zacząć sesję. Zwraca true albo false i powód: BadRequest, Zone (strefa niekupiona),
-- Tier (brak tieru, np. pierwszy odrzutowiec niekupiony) albo BagFull (pełny Bag bez Auto-Sell:
-- najpierw Sell; ostatnia sesja może przepełnić Bag, ale z pełnym już się nie zaczyna).
function Loop.canStartActivity(data, ctx, kind)
	local activity = Economy.Activities[kind]
	if activity == nil then
		return false, "BadRequest"
	end
	if data.ZonesUnlocked < activity.Zone then
		return false, "Zone"
	end
	if Loop.activityTier(data, kind) < 1 then
		return false, "Tier"
	end
	if Loop.isFull(data, ctx) then
		return false, "BagFull"
	end
	return true, nil
end

-- Następny tier do kupienia: numer i tabela z arkusza, albo nil.
function Loop.nextActivityTier(data, kind)
	local activity = Economy.Activities[kind]
	if activity == nil or activity.Tiers == nil then
		return nil, nil
	end
	local n = Loop.activityTier(data, kind) + 1
	local info = activity.Tiers[n]
	if info == nil then
		return nil, nil
	end
	return n, info
end

-- Kupuje następny tier. Zwraca true albo false i powód: BadRequest, Zone, Max, NotEnough.
function Loop.buyActivityTier(data, kind)
	local activity = Economy.Activities[kind]
	if activity == nil or activity.Tiers == nil then
		return false, "BadRequest"
	end
	if data.ZonesUnlocked < activity.Zone then
		return false, "Zone"
	end
	local n, info = Loop.nextActivityTier(data, kind)
	if n == nil then
		return false, "Max"
	end
	if data.Cash < info.Cost then
		return false, "NotEnough"
	end
	data.Cash = data.Cash - info.Cost
	if data.ActivityTiers == nil then
		data.ActivityTiers = {}
	end
	data.ActivityTiers[kind] = n
	return true, nil
end

-- Ile LP z nagrody `amount` zmieści się teraz w Bag (z Auto-Sell całość, bo pełny Bag sprzedaje się sam).
function Loop.fitsInBag(data, ctx, amount)
	if Loop.autoSellOn(data, ctx) then
		return amount
	end
	local space = Loop.capacity(data, ctx) - data.Bag
	if space < 0 then
		space = 0
	end
	if amount > space then
		return space
	end
	return amount
end

-- Koniec sesji: LP do Bag, ale tylko tyle, ile się zmieści (jak przy klikaniu; z Auto-Sell całość),
-- i licznik sesji. grade = wylosowana ocena (wywiad). Zwraca: pełną nagrodę, ile LP weszło do Bag
-- i ile L$ dała automatyczna sprzedaż.
function Loop.finishActivity(data, ctx, kind, grade)
	local reward = Loop.activityReward(data, ctx, kind, grade)
	local added, sold = Loop.collect(data, reward, ctx, false)
	local field = ACTIVITY_STAT[kind]
	if field ~= nil then
		data.Stats[field] = (data.Stats[field] or 0) + 1
	end
	-- pasek Aury (od Rebirth 1): czas aktywności, wywiad 2×; pełne 10 minut = +10 Aury
	local aura = Rebirth.addBarTime(data, Rebirth.barSecondsFor(kind))
	return reward, added, sold, aura
end

-- Co HUD pokazuje o aktywności: tier, pełna nagroda za sesję i ile z niej zmieści się teraz w Bag
-- (RewardFits), koszt i nagroda następnego tieru.
function Loop.activityView(data, ctx, kind)
	local tier = Loop.activityTier(data, kind)
	local reward = Loop.activityReward(data, ctx, kind)
	local view = {
		Tier = tier,
		Reward = reward,
		RewardFits = Loop.fitsInBag(data, ctx, reward),
	}
	local n, info = Loop.nextActivityTier(data, kind)
	if n ~= nil then
		view.NextCost = info.Cost
		view.NextReward = rewardWith(data, ctx, kind, info.Multiplier)
	end
	-- wywiad: nagroda zależy od oceny, więc okno pokazuje od–do (a limit Bag liczy dla najlepszej)
	local grades = Economy.Activities[kind].Grades
	if grades ~= nil then
		view.MinReward = Loop.activityReward(data, ctx, kind, 1)
		view.MaxReward = Loop.activityReward(data, ctx, kind, #grades)
		view.RewardFits = Loop.fitsInBag(data, ctx, view.MaxReward)
	end
	return view
end

----------------------------------------------------------------- Pety i jajka
-- Pet w zapisie: data.Pets[id] = { Zone = strefa jajka, Rarity = "Rare", Level = 0, Egg = "A" }
-- (Level 0 zwykły, 1 złoty, 2 diamentowy; Egg = jajko, z którego jest: A, B albo P = premium;
-- stare pety bez Egg liczą się jak z jajka A). data.Equipped = lista id wyposażonych petów.
-- data.Index[„strefa:rzadkość”] = true: pety, które gracz już miał (indeks).

-- Zaokrąglenie jak w arkuszu: połówki w górę.
local function roundHalfUp(x)
	return math.floor(x + 0.5 + 1e-9)
end

-- Sloty na pety: 3, +1 od Rebirth 3, +1 od Rebirth 7, +2 z gamepassem Pet Slots.
function Loop.petSlots(data, ctx)
	local slots = Economy.Pets.Slots
	local n = slots.Base
	if data.RebirthLevel >= 3 then
		n = n + slots.Rebirth3
	end
	if data.RebirthLevel >= 7 then
		n = n + slots.Rebirth7
	end
	if passesOf(ctx).PetSlots then
		n = n + slots.Gamepass
	end
	return n
end

-- Moc peta jako ułamek (+% L$ przy Sell), np. Rare ze strefy 1 = 0,05 × 4 = 0,2 (+20%).
function Loop.petPower(pet)
	return Formulas.petPower(pet.Zone, pet.Rarity, pet.Level or 0)
end

function Loop.petCount(data)
	local n = 0
	for _ in pairs(data.Pets) do
		n = n + 1
	end
	return n
end

-- Ile wyposażonych petów naprawdę działa (najwyżej tyle, ile slotów, i tylko istniejące).
function Loop.activePets(data, ctx)
	local slots = Loop.petSlots(data, ctx)
	local list = {}
	for _, id in ipairs(data.Equipped) do
		local pet = data.Pets[id]
		if pet ~= nil and #list < slots then
			table.insert(list, id)
		end
	end
	return list
end

-- Warstwa petów: 1 + suma mocy wyposażonych petów (w warstwie dodajemy). Mnoży L$ przy Sell.
function Loop.petLayer(data, ctx)
	local layer = 1
	for _, id in ipairs(Loop.activePets(data, ctx)) do
		layer = layer + Loop.petPower(data.Pets[id])
	end
	return layer
end

local function isEquipped(data, id)
	for i, existing in ipairs(data.Equipped) do
		if existing == id then
			return i
		end
	end
	return nil
end

-- Wyposaża peta. Zwraca true albo false i powód: Missing (nie ma go), Already, SlotsFull.
-- Najpierw czyści listę z petów, które nie działają (np. po utracie slotów z gamepassa).
function Loop.equipPet(data, ctx, id)
	if data.Pets[id] == nil then
		return false, "Missing"
	end
	data.Equipped = Loop.activePets(data, ctx)
	if isEquipped(data, id) ~= nil then
		return false, "Already"
	end
	if #Loop.activePets(data, ctx) >= Loop.petSlots(data, ctx) then
		return false, "SlotsFull"
	end
	table.insert(data.Equipped, id)
	return true, nil
end

function Loop.unequipPet(data, id)
	local index = isEquipped(data, id)
	if index == nil then
		return false, "NotEquipped"
	end
	table.remove(data.Equipped, index)
	return true, nil
end

-- Pety posortowane od najmocniejszego (przy równej mocy starsze pierwsze). Zwraca listę id.
function Loop.petsByPower(data)
	local ids = {}
	for id in pairs(data.Pets) do
		table.insert(ids, id)
	end
	table.sort(ids, function(a, b)
		local pa, pb = Loop.petPower(data.Pets[a]), Loop.petPower(data.Pets[b])
		if pa ~= pb then
			return pa > pb
		end
		return (tonumber(a) or 0) < (tonumber(b) or 0)
	end)
	return ids
end

-- Wyposaża najmocniejsze pety na wszystkie sloty.
function Loop.equipBest(data, ctx)
	local slots = Loop.petSlots(data, ctx)
	local best = {}
	for _, id in ipairs(Loop.petsByPower(data)) do
		if #best >= slots then
			break
		end
		table.insert(best, id)
	end
	data.Equipped = best
	return best
end

-- Jajko z arkusza (Price i Odds) albo nil. Jajka premium (za Robux) dojdą z produktami w Creator Hub.
function Loop.eggInfo(zone, egg)
	local eggs = Economy.Pets.Eggs[zone]
	local info = eggs and eggs[egg]
	if info == nil or info.Price == nil then
		return nil
	end
	return info
end

-- Premium jajko strefy (za Robuxy, stałe szanse bez szczęścia) albo nil. Na mapie to stoisko EggPN.
function Loop.premiumInfo(zone)
	local eggs = Economy.Pets.Eggs[zone]
	local info = eggs and eggs.Premium
	if info == nil or info.Odds == nil then
		return nil
	end
	return info
end

-- Czy można kupić count jajek naraz (1 albo 3 z Triple Open). Zwraca true albo false i powód:
-- BadRequest, Zone, Inventory (nie zmieszczą się wszystkie), NotEnough (nie stać na wszystkie).
function Loop.canBuyEggs(data, zone, egg, count, maxPets)
	local info = Loop.eggInfo(zone, egg)
	if info == nil or type(count) ~= "number" or count < 1 or count ~= math.floor(count) then
		return false, "BadRequest"
	end
	if data.ZonesUnlocked < zone then
		return false, "Zone"
	end
	if maxPets ~= nil and Loop.petCount(data) + count > maxPets then
		return false, "Inventory"
	end
	if data.Cash < info.Price * count then
		return false, "NotEnough"
	end
	return true, nil
end

function Loop.canBuyEgg(data, zone, egg, maxPets)
	return Loop.canBuyEggs(data, zone, egg, 1, maxPets)
end

----------------------------------------------------------------- Indeks
function Loop.indexKey(zone, rarity)
	return tostring(zone) .. ":" .. tostring(rarity)
end

-- Zapisuje peta w indeksie. Zwraca true, gdy gracz ma go pierwszy raz (napis NEW! przy otwieraniu).
function Loop.addToIndex(data, zone, rarity)
	if type(data.Index) ~= "table" then
		data.Index = {}
	end
	local key = Loop.indexKey(zone, rarity)
	if data.Index[key] then
		return false
	end
	data.Index[key] = true
	return true
end

-- Uzupełnia indeks petami, które gracz już ma (zapisy sprzed indeksu).
function Loop.backfillIndex(data)
	for _, pet in pairs(data.Pets) do
		Loop.addToIndex(data, pet.Zone, pet.Rarity)
	end
end

-- Rzadkości w indeksie strefy: wszystko, co wypada z jajek A i B (za L$) i z premium jajka (Robux,
-- stąd Mythic), w kolejności rzadkości.
function Loop.indexRarities(zone)
	local list = {}
	local eggs = Economy.Pets.Eggs[zone]
	if eggs == nil then
		return list
	end
	local premium = Loop.premiumInfo(zone)
	for _, rarity in ipairs(Economy.Pets.RarityOrder) do
		local found = premium ~= nil and premium.Odds[rarity] ~= nil
		for egg in pairs(eggs) do
			local info = Loop.eggInfo(zone, egg)
			if info ~= nil and info.Odds[rarity] ~= nil then
				found = true
			end
		end
		if found then
			table.insert(list, rarity)
		end
	end
	return list
end

-- Wszystkie pety w indeksie: suma po strefach (dziś 5 stref × 7 rzadkości).
function Loop.indexTotal()
	local n = 0
	for zone in ipairs(Economy.Pets.Eggs) do
		n = n + #Loop.indexRarities(zone)
	end
	return n
end

-- Ile petów z indeksu gracz już miał (pety spoza indeksu się nie liczą).
function Loop.indexCount(data)
	local n = 0
	if type(data.Index) ~= "table" then
		return n
	end
	for zone in ipairs(Economy.Pets.Eggs) do
		for _, rarity in ipairs(Loop.indexRarities(zone)) do
			if data.Index[Loop.indexKey(zone, rarity)] then
				n = n + 1
			end
		end
	end
	return n
end

-- Kupuje i otwiera jajko. random01 = funkcja losująca liczbę z [0, 1). Pierwsze jajko A w strefie 1
-- zawsze daje Rare (dobry start). Szczęście z Aury działa na jajka za L$. Nowy pet trafia na wolny
-- slot. Zwraca id, peta i czy jest nowy w indeksie albo nil i powód (jak canBuyEgg).
function Loop.openEgg(data, ctx, zone, egg, random01, maxPets)
	local ok, reason = Loop.canBuyEgg(data, zone, egg, maxPets)
	if not ok then
		return nil, reason
	end
	local info = Loop.eggInfo(zone, egg)
	data.Cash = data.Cash - info.Price
	local rarity
	if data.Stats.EggsOpened == 0 and zone == 1 and egg == "A" then
		rarity = Economy.Pets.FirstEggRarity
	else
		local luck = 1
		if info.LuckApplies ~= false then
			luck = Formulas.luck(data.AuraUpgrades.Luck)
		end
		luck = luck * ((ctx and ctx.luckBoost) or 1) -- tryb testowy: /adminluck
		rarity = Formulas.roll(info.Odds, luck, random01)
	end
	local id = tostring(data.NextPetId)
	data.NextPetId = data.NextPetId + 1
	local pet = { Zone = zone, Rarity = rarity, Level = 0, Egg = egg }
	data.Pets[id] = pet
	data.Stats.EggsOpened = data.Stats.EggsOpened + 1
	if rarity == "Secret" then
		data.Stats.SecretsHatched = (data.Stats.SecretsHatched or 0) + 1
	end
	if #Loop.activePets(data, ctx) < Loop.petSlots(data, ctx) then
		table.insert(data.Equipped, id)
	end
	local isNew = Loop.addToIndex(data, zone, rarity)
	return id, pet, isNew
end

-- Otwiera count jajek naraz (Triple Open). Najpierw sprawdza, czy stać na wszystkie i czy wszystkie
-- się zmieszczą. Zwraca listę { id, pet, new } albo nil i powód (jak canBuyEggs).
function Loop.openEggs(data, ctx, zone, egg, count, random01, maxPets)
	local ok, reason = Loop.canBuyEggs(data, zone, egg, count, maxPets)
	if not ok then
		return nil, reason
	end
	local list = {}
	for _ = 1, count do
		local id, pet, isNew = Loop.openEgg(data, ctx, zone, egg, random01, maxPets)
		if id == nil then
			break
		end
		table.insert(list, { id = id, pet = pet, new = isNew })
	end
	return list
end

-- Dodaje peta bez losowania i bez płacenia L$ (zakup za Robuxy, Starter Pack): zakłada go, gdy jest
-- wolny slot, i zapisuje w indeksie. Limitu ekwipunku nie sprawdza, bo zapłaconego peta trzeba dać
-- zawsze. Zwraca id, peta i czy jest nowy w indeksie.
function Loop.addPet(data, ctx, zone, rarity, egg, level)
	local id = tostring(data.NextPetId)
	data.NextPetId = data.NextPetId + 1
	local pet = { Zone = zone, Rarity = rarity, Level = level or 0, Egg = egg or "P" }
	data.Pets[id] = pet
	if #Loop.activePets(data, ctx) < Loop.petSlots(data, ctx) then
		table.insert(data.Equipped, id)
	end
	local isNew = Loop.addToIndex(data, zone, rarity)
	return id, pet, isNew
end

-- Czy pet jest na liście wyposażonych.
function Loop.isEquipped(data, id)
	for _, existing in ipairs(data.Equipped) do
		if existing == id then
			return true
		end
	end
	return false
end

----------------------------------------------------------------- Sprzedaż i łączenie (Etap 7)
local LEVEL_SELL = { [0] = 1, [1] = Economy.Pets.GoldSellX, [2] = Economy.Pets.DiamondSellX }

-- Cena jajka, z którego jest pet (premium liczy się jak jajko B, stare pety bez Egg jak A).
function Loop.petEggPrice(pet)
	local eggs = Economy.Pets.Eggs[pet.Zone]
	if eggs == nil then
		return 0
	end
	local egg = pet.Egg or "A"
	if egg == "P" then
		egg = "B"
	end
	local info = eggs[egg] or eggs.A
	return (info and info.Price) or 0
end

-- Ile L$ za sprzedaż peta: 10% ceny jajka, Złoty ×5 (tyle co 5 zwykłych), Diamentowy ×25.
function Loop.petSellValue(pet)
	return roundHalfUp(Loop.petEggPrice(pet) * Economy.Pets.SellReturn * (LEVEL_SELL[pet.Level or 0] or 1))
end

-- Sprzedaje pety za L$. Założonych nie sprzedaje. Sekretnego tylko z confirm = true (u gracza okno
-- „na pewno?”). Zwraca liczbę sprzedanych i L$ albo nil i "ConfirmSecret".
function Loop.sellPets(data, ctx, ids, confirm)
	data.Equipped = Loop.activePets(data, ctx)
	if confirm ~= true then
		for _, id in ipairs(ids) do
			local pet = data.Pets[id]
			if pet ~= nil and pet.Rarity == "Secret" and not Loop.isEquipped(data, id) then
				return nil, "ConfirmSecret"
			end
		end
	end
	local count, cash = 0, 0
	for _, id in ipairs(ids) do
		local pet = data.Pets[id]
		if pet ~= nil and not Loop.isEquipped(data, id) then
			cash = cash + Loop.petSellValue(pet)
			data.Pets[id] = nil
			count = count + 1
		end
	end
	data.Cash = data.Cash + cash
	data.Stats.LifetimeCash = (data.Stats.LifetimeCash or 0) + cash
	data.Stats.PetsSold = (data.Stats.PetsSold or 0) + count
	return count, cash
end

-- Łączenie z szansą (zasady z dokumentu projektu): 1–5 identycznych petów (ta sama strefa, rzadkość
-- i poziom), każdy daje 20% szansy (+1 pkt proc. za poziom Merge Luck ze sklepu Aury). Sukces daje
-- wersję Złotą (ze Złotych: Diamentową), porażka zabiera wszystkie użyte pety. Opłata za każdego
-- peta to 1/5 pełnej opłaty (cena jajka × 1 za Złotego, × 5 za Diamentowego), więc średni koszt
-- Złotego zawsze wynosi 5 petów i jedną pełną opłatę. Pety z jajek premium tylko przy 100%.
-- Zwraca { Chance, Fee, Level (po łączeniu), Zone, Rarity, Pieces, Premium } albo nil i powód:
-- BadRequest, Missing, NotSame, MaxLevel, Premium.
function Loop.mergeInfo(data, ids)
	local merge = Economy.Pets.Merge
	if type(ids) ~= "table" or #ids < 1 or #ids > merge.MaxPieces then
		return nil, "BadRequest"
	end
	local first = nil
	local seen = {}
	local premium = false
	for _, id in ipairs(ids) do
		local pet = data.Pets[id]
		if type(id) ~= "string" or pet == nil or seen[id] then
			return nil, "Missing"
		end
		seen[id] = true
		if first == nil then
			first = pet
		elseif pet.Zone ~= first.Zone or pet.Rarity ~= first.Rarity or (pet.Level or 0) ~= (first.Level or 0) then
			return nil, "NotSame"
		end
		if pet.Egg == "P" then
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
	local feeX = merge.GoldFeeX
	if level == 1 then
		feeX = merge.DiamondFeeX
	end
	local fee = 0
	for _, id in ipairs(ids) do
		fee = fee + Loop.petEggPrice(data.Pets[id]) * feeX / merge.MaxPieces
	end
	return {
		Chance = chance,
		Fee = roundHalfUp(fee),
		Level = level + 1,
		Zone = first.Zone,
		Rarity = first.Rarity,
		Pieces = #ids,
		Premium = premium,
	}
end

-- Łączy pety (opłata zawsze, wynik losowy). random01() < szansa = sukces. Nowy pet zajmuje slot
-- połączonych, jeśli któryś był założony. Zwraca { Success, Id, Pet, Info } albo nil i powód
-- (jak mergeInfo albo NotEnough).
function Loop.mergePets(data, ctx, ids, random01)
	local info, reason = Loop.mergeInfo(data, ids)
	if info == nil then
		return nil, reason
	end
	if data.Cash < info.Fee then
		return nil, "NotEnough"
	end
	data.Cash = data.Cash - info.Fee
	data.Equipped = Loop.activePets(data, ctx)
	local wasEquipped = false
	local egg = nil
	for _, id in ipairs(ids) do
		local pet = data.Pets[id]
		egg = egg or pet.Egg
		for i = #data.Equipped, 1, -1 do
			if data.Equipped[i] == id then
				table.remove(data.Equipped, i)
				wasEquipped = true
			end
		end
		data.Pets[id] = nil
	end
	data.Stats.Merges = (data.Stats.Merges or 0) + 1
	if random01() >= info.Chance then
		data.Stats.MergesFailed = (data.Stats.MergesFailed or 0) + 1
		return { Success = false, Info = info }
	end
	local id = tostring(data.NextPetId)
	data.NextPetId = data.NextPetId + 1
	local pet = { Zone = info.Zone, Rarity = info.Rarity, Level = info.Level, Egg = egg }
	if info.Premium then
		pet.Egg = "P"
	end
	data.Pets[id] = pet
	if wasEquipped or #Loop.activePets(data, ctx) < Loop.petSlots(data, ctx) then
		table.insert(data.Equipped, id)
	end
	return { Success = true, Id = id, Pet = pet, Info = info }
end

-- Usuwa pety z ekwipunku bez zwrotu L$ (gracze sprzedają je przez sellPets; to zostało dla testów).
-- Założonych nie usuwa. Zwraca, ile usunął.
function Loop.deletePets(data, ctx, ids)
	data.Equipped = Loop.activePets(data, ctx)
	local count = 0
	for _, id in ipairs(ids) do
		if data.Pets[id] ~= nil and not Loop.isEquipped(data, id) then
			data.Pets[id] = nil
			count = count + 1
		end
	end
	return count
end

----------------------------------------------------------------- Widok dla HUD
-- Wszystko, co pokazuje HUD, policzone w jednym miejscu (na serwerze).
function Loop.view(data, ctx)
	local clickCost = Loop.nextCost(data, "Click")
	local bagCost = Loop.nextCost(data, "Bag")
	local view = {
		Cash = data.Cash,
		Bag = data.Bag,
		BagCapacity = Loop.capacity(data, ctx),
		BagFull = Loop.isFull(data, ctx),
		AutoSell = Loop.autoSellOn(data, ctx),
		ClickLevel = data.ClickLevel,
		ClickMaxLevel = Loop.MaxLevel.Click,
		LPPerClick = Loop.clickLP(data, ctx),
		NextClickCost = clickCost,
		BagLevel = data.BagLevel,
		BagMaxLevel = Loop.MaxLevel.Bag,
		NextBagCost = bagCost,
		Zone = (ctx and ctx.zone) or 1,
		ZonesUnlocked = data.ZonesUnlocked,
		RebirthLevel = data.RebirthLevel,
		RebirthCount = data.RebirthCount,
		Aura = data.Aura,
		Clicks = data.Stats.Clicks,
		Sells = data.Stats.Sells,
	}
	if clickCost ~= nil then
		view.NextLPPerClick = Loop.clickLPAt(data.ClickLevel + 1, data, ctx)
	end
	if bagCost ~= nil then
		view.NextBagCapacity = Loop.capacityAt(data.BagLevel + 1, ctx)
	end
	view.Activities = {}
	for _, kind in ipairs(Loop.ActivityKinds) do
		view.Activities[kind] = Loop.activityView(data, ctx, kind)
	end
	view.PetLayer = Loop.petLayer(data, ctx)
	view.PetSlots = Loop.petSlots(data, ctx)
	view.PetsEquipped = #Loop.activePets(data, ctx)
	view.PetCount = Loop.petCount(data)
	view.EggsOpened = data.Stats.EggsOpened
	view.IndexCount = Loop.indexCount(data)
	view.IndexTotal = Loop.indexTotal()
	view.MergeLuck = (data.AuraUpgrades and data.AuraUpgrades.MergeLuck) or 0
	for key, value in pairs(Rebirth.view(data)) do
		view[key] = value
	end
	return view
end

return Loop
