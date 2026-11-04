-- Wzory ekonomii — dokładnie te same co w arkuszu v2 (zakładki Click Multiplier, Aura, Pety, Rebirth).
-- Same obliczenia, bez stanu gracza: serwer i UI korzystają z jednego źródła.

local Economy = require(script.Parent.Config.Economy)

local Formulas = {}

-- Zaokrąglenie „połówka w górę”, jak ZAOKR w arkuszu (dla liczb dodatnich).
local function roundHalfUp(x)
	return math.floor(x + 0.5 + 1e-9)
end

-- Zaokrąglenie do 2 cyfr znaczących: 133 -> 130, 146 -> 150, 1610 -> 1600.
local function round2(x)
	if x < 100 then
		return roundHalfUp(x)
	end
	local p = 10 ^ (math.floor(math.log10(x) + 1e-12) - 1)
	return math.floor(x / p + 0.5) * p
end

----------------------------------------------------------------- Click Multiplier
-- LP za klik z Click Multipliera (przed warstwami): ZAOKR(1 + poziom + 0,1 × poziom²)
function Formulas.clickValue(level)
	return roundHalfUp(1 + level + 0.1 * level * level)
end

-- Koszt poziomu Click Multipliera (poziomy 1..MaxLevel), nil po limicie
function Formulas.clickCost(level)
	return Economy.ClickMultiplier.Costs[level]
end

----------------------------------------------------------------- Bag
function Formulas.bagCapacity(level, hasTwoXBag)
	local cap = Economy.Bag.Capacity[level]
	if cap and hasTwoXBag then
		cap = cap * Economy.Robux.Gamepasses.TwoXBag.CapacityX
	end
	return cap
end

function Formulas.bagCost(level)
	return Economy.Bag.Costs[level]
end

----------------------------------------------------------------- Aura
-- Koszt kolejnego poziomu ulepszenia Aury. Bez limitu: koszt1 × (1 + wzrost)^(poziom − 1),
-- zaokrąglony do 2 cyfr znaczących. Merge Luck: stała tabela, nil po 5. poziomie.
function Formulas.auraUpgradeCost(key, level)
	local u = Economy.Aura.Upgrades[key]
	if u == nil or level < 1 then
		return nil
	end
	if u.Costs then
		return u.Costs[level]
	end
	return round2(u.BaseCost * (1 + u.Growth) ^ (level - 1))
end

function Formulas.clickBoost(level)
	return 1 + Economy.Aura.Upgrades.ClickBoost.Effect * level
end

function Formulas.luck(level)
	return 1 + Economy.Aura.Upgrades.Luck.Effect * level
end

function Formulas.auraGain(level)
	return 1 + Economy.Aura.Upgrades.AuraGain.Effect * level
end

-- Aura Level = suma poziomów wszystkich ulepszeń; poświata wg progów
function Formulas.glowFor(auraLevel)
	local color = nil
	for _, g in ipairs(Economy.Aura.Glow) do
		if auraLevel >= g.Level then
			color = g.Color
		end
	end
	return color
end

----------------------------------------------------------------- Łączenie
function Formulas.mergeChancePerPiece(mergeLuckLevel)
	return Economy.Pets.Merge.ChancePerPiece + Economy.Aura.Upgrades.MergeLuck.Effect * (mergeLuckLevel or 0)
end

-- Szansa udanego łączenia przy danej liczbie sztuk (1–5)
function Formulas.mergeChance(pieces, mergeLuckLevel)
	return math.min(1, pieces * Formulas.mergeChancePerPiece(mergeLuckLevel))
end

-- Najmniej sztuk, które dają 100% (pety premium łączymy tylko tak)
function Formulas.piecesForCertain(mergeLuckLevel)
	local q = Formulas.mergeChancePerPiece(mergeLuckLevel)
	return math.ceil(1 / q - 1e-9)
end

----------------------------------------------------------------- Rebirth
-- Opłata za kolejny Rebirth (licznik wszystkich Rebirthów, także po limicie poziomów)
function Formulas.rebirthFee(nextCount)
	local R = Economy.Rebirth
	if nextCount <= R.Cap then
		return R.Fees[nextCount]
	end
	return R.Fees[R.Cap] * (1 + R.PostCapFeeGrowth) ^ (nextCount - R.Cap)
end

-- Poziom Rebirth (mnożnik) przy danym liczniku
function Formulas.rebirthLevel(count)
	return math.min(count, Economy.Rebirth.Cap)
end

-- Aura za kolejny Rebirth (przed mnożnikiem Aura Gain)
function Formulas.rebirthAura(nextCount)
	return Economy.Aura.RebirthReward * Formulas.rebirthLevel(nextCount)
end

----------------------------------------------------------------- Szczęście
-- Szanse po szczęściu: gra losuje floor(luck) razy i jeszcze raz z szansą = część ułamkowa,
-- gracz dostaje najrzadszy wynik. Zwraca tabelę rzadkość -> szansa (suma = 1).
-- order = kolejność rzadkości od najczęstszej (domyślnie pety; ubrania mają własną z UltraSecret).
function Formulas.effectiveOdds(odds, luck, order)
	luck = luck or 1
	order = order or Economy.Pets.RarityOrder
	local n0 = math.floor(luck + 1e-12)
	local fr = luck - n0
	if n0 < 1 then
		n0, fr = 1, 0
	end
	local out = {}
	local acc, prev = 0, 0
	for _, rar in ipairs(order) do
		local p = odds[rar]
		if p ~= nil then
			acc = acc + p
			local F = math.min(1, acc)
			local Fm = (1 - fr) * F ^ n0 + fr * F ^ (n0 + 1)
			out[rar] = math.max(0, Fm - prev)
			prev = Fm
		end
	end
	return out
end

-- Jedno losowanie z uwzględnieniem szczęścia. random01 = funkcja zwracająca liczbę z [0, 1),
-- np. function() return rng:NextNumber() end. order jak w effectiveOdds.
function Formulas.roll(odds, luck, random01, order)
	luck = luck or 1
	order = order or Economy.Pets.RarityOrder
	local n = math.floor(luck)
	if random01() < luck - n then
		n = n + 1
	end
	if n < 1 then
		n = 1
	end
	local rank = {}
	for i, rar in ipairs(order) do
		rank[rar] = i
	end
	local best = nil
	for _ = 1, n do
		local r = random01()
		local acc, pick = 0, nil
		for _, rar in ipairs(order) do
			local p = odds[rar]
			if p ~= nil then
				acc = acc + p
				pick = rar
				if r < acc then
					break
				end
			end
		end
		if best == nil or rank[pick] > rank[best] then
			best = pick
		end
	end
	return best
end

----------------------------------------------------------------- Pety
-- Moc peta (+% L$ jako ułamek): moc strefy × mnożnik rzadkości × (Złoty ×2, Diamentowy ×4)
function Formulas.petPower(zone, rarity, mergeLevel)
	local power = Economy.Pets.ZonePower[zone] * Economy.Pets.RarityMultiplier[rarity]
	if mergeLevel == 1 then
		power = power * Economy.Pets.Merge.GoldMultiplier
	elseif mergeLevel == 2 then
		power = power * Economy.Pets.Merge.DiamondMultiplier
	end
	return power
end

----------------------------------------------------------------- Ubrania
-- Bonus ubrania (+% LP jako ułamek): bonus rzadkości × (Golden ×2, Diamond ×4), np. Rare = 0,8.
function Formulas.clothBonus(rarity, mergeLevel)
	local bonus = Economy.Clothes.RarityBonus[rarity] or 0
	if mergeLevel == 1 then
		bonus = bonus * Economy.Pets.Merge.GoldMultiplier
	elseif mergeLevel == 2 then
		bonus = bonus * Economy.Pets.Merge.DiamondMultiplier
	end
	return bonus
end

return Formulas
