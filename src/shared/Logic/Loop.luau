-- Rdzeń pętli: LP za klik, Bag, Sell i ulepszenia za L$. Same obliczenia na danych gracza,
-- bez Roblox API, więc działają na serwerze, w UI i w testach (tools/test_luau.py).
--
-- data to zapis gracza (Shared/Data/Template). ctx opisuje to, czego nie ma w zapisie:
--   zone        strefa, w której gracz stoi (Mnożnik strefy), domyślnie 1
--   passes      gamepassy, np. { TwoXLP = true, AutoSell = true }
--   inGroup     gracz jest w grupie gry (+5% LP)
--   friends     liczba znajomych na serwerze (+10% LP każdy, maks. 3)
--   boost       aktywny boost 2x LP
--   autoSellBoost  aktywny boost Auto-Sell
--   clothLayer  warstwa ubrań (Etap 4), domyślnie 1
--   petLayer    warstwa petów, mnoży L$ przy Sell (Etap 4), domyślnie 1

local Economy = require(script.Parent.Parent.Config.Economy)
local Formulas = require(script.Parent.Parent.Formulas)

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
-- Click Boost (Aura) × Rebirth × ubrania × bonusy × boost. Ten sam mnożnik dostaną aktywności (Etap 3).
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
	return view
end

return Loop
