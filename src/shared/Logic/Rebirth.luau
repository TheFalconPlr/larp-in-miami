-- Rebirth i Aura (Etap 9, zasady z dokumentu projektu). Czysta logika bez Roblox API (testy
-- w tools/test_luau.py i w Studio: RebirthSpec).
--
-- Rebirth robi się na lotnisku (strefa 5), gdy masz wszystkie strefy i L$ na opłatę. Zeruje L$, Bag,
-- Click Multiplier i Bag, strefy oraz auta, jachty i odrzutowce. W zamian rośnie poziom Rebirth
-- (mnożnik LP ×2 … ×25, tytuł, +5% szybkości chodzenia za poziom, +1 slot na peta od R3 i od R7)
-- i przychodzi Aura: 100 × nowy poziom. Na premierę poziomów jest 10. Kolejne Rebirthy po R10
-- dają po 1 000 Aury bez nowego mnożnika, a opłata rośnie o 25% za każdy. Pety, ubrania, indeks,
-- Aura, sklep Aury i zakupy za Robuxy zostają.
--
-- Aura (druga waluta, od Rebirth 1; wcześniej licznik jest ukryty): Rebirthy, pasek Aury (+10 za
-- każde 10 minut aktywności, wywiad napełnia go 2× szybciej, klikanie się nie liczy), później
-- zadania dzienne. Aura Gain mnoży każdy przychód Aury. Aurę trzymamy z ułamkiem (jak w modelu),
-- a gra pokazuje część całkowitą: koszty są całkowite, więc to wystarcza do sprawdzania zakupów.
-- Sklep Aury: Click Boost, Luck i Aura Gain bez limitu, Merge Luck do 5. poziomu.
-- Aura Level = suma poziomów w sklepie (widać go nad głową, od niego zależy poświata).

local Economy = require(script.Parent.Parent.Config.Economy)
local Formulas = require(script.Parent.Parent.Formulas)
local Template = require(script.Parent.Parent.Data.Template)

local Rebirth = {}

local R = Economy.Rebirth
local A = Economy.Aura

Rebirth.UpgradeOrder = { "ClickBoost", "Luck", "AuraGain", "MergeLuck" }
Rebirth.Cap = R.Cap

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

local function upgrades(data)
	if type(data.AuraUpgrades) ~= "table" then
		data.AuraUpgrades = copy(Template.AuraUpgrades)
	end
	return data.AuraUpgrades
end

----------------------------------------------------------------- Rebirth
function Rebirth.title(level)
	return R.Titles[level or 0] or R.Titles[R.Cap]
end

-- Opłata za następny Rebirth (po R10 rośnie o 25% za każdy).
function Rebirth.nextFee(data)
	return Formulas.rebirthFee((data.RebirthCount or 0) + 1)
end

-- Aura za następny Rebirth, już z Aura Gain (100 × nowy poziom, po R10 zawsze 1 000).
function Rebirth.nextAura(data)
	return Formulas.rebirthAura((data.RebirthCount or 0) + 1) * Rebirth.gain(data)
end

-- Sloty na pety, które daje poziom Rebirth (dokument: +1 od R3 i +1 od R7).
function Rebirth.petSlotsAt(level)
	local slots = Economy.Pets.Slots
	local n = 0
	if level >= 3 then
		n = n + slots.Rebirth3
	end
	if level >= 7 then
		n = n + slots.Rebirth7
	end
	return n
end

-- Prędkość chodzenia: +5% za każdy poziom Rebirth.
function Rebirth.walkSpeed(level)
	return Economy.WalkSpeed * (1 + R.WalkSpeedPerLevel * (level or 0))
end

-- Czy można zrobić Rebirth. Zwraca true albo false i powód: Zone (nie wszystkie strefy),
-- NotEnough (za mało L$ na opłatę).
function Rebirth.canRebirth(data)
	if (data.ZonesUnlocked or 1) < #Economy.Zones then
		return false, "Zone"
	end
	if (data.Cash or 0) < Rebirth.nextFee(data) then
		return false, "NotEnough"
	end
	return true, nil
end

-- Robi Rebirth (force = tryb testowy: bez opłaty i bez warunku stref). Zwraca opis albo nil i powód:
-- { Count, Level, LevelUp, Aura, Title, Fee, FirstAura, PetSlots }.
function Rebirth.rebirth(data, force)
	if not force then
		local ok, reason = Rebirth.canRebirth(data)
		if not ok then
			return nil, reason
		end
	end
	local fee = Rebirth.nextFee(data)
	local before = data.RebirthLevel or 0
	local count = (data.RebirthCount or 0) + 1
	local level = Formulas.rebirthLevel(count)
	-- reset przejścia: opłata schodzi z L$, a reszta L$ i tak przepada razem ze strefami
	data.Cash = 0
	data.Bag = 0
	data.ClickLevel = 0
	data.BagLevel = 0
	data.ZonesUnlocked = 1
	data.ActivityTiers = copy(Template.ActivityTiers)
	data.RebirthCount = count
	data.RebirthLevel = level
	local aura = Rebirth.addAura(data, Formulas.rebirthAura(count))
	return {
		Count = count,
		Level = level,
		LevelUp = level > before,
		Aura = aura,
		Title = Rebirth.title(level),
		Fee = fee,
		FirstAura = count == A.UnlockAtRebirth,
		PetSlots = Rebirth.petSlotsAt(level) - Rebirth.petSlotsAt(before),
	}
end

----------------------------------------------------------------- Aura
function Rebirth.unlocked(data)
	return (data.RebirthCount or 0) >= A.UnlockAtRebirth
end

-- Mnożnik Aury z ulepszenia Aura Gain.
function Rebirth.gain(data)
	return Formulas.auraGain(upgrades(data).AuraGain or 0)
end

-- Dodaje Aurę razy Aura Gain. Przed Rebirth 1 Aury jeszcze nie ma. Zwraca dodaną ilość.
function Rebirth.addAura(data, amount)
	if not Rebirth.unlocked(data) or amount <= 0 then
		return 0
	end
	local added = amount * Rebirth.gain(data)
	data.Aura = (data.Aura or 0) + added
	data.Stats.AuraEarned = (data.Stats.AuraEarned or 0) + added
	return added
end

-- Sekundy paska Aury za jedną aktywność: jej czas, a wywiad 2× (InterviewBarMultiplier).
function Rebirth.barSecondsFor(kind)
	local info = Economy.Activities[kind]
	if info == nil then
		return 0
	end
	local seconds = info.DurationSeconds or 0
	if kind == "Interview" then
		seconds = seconds * A.InterviewBarMultiplier
	end
	return seconds
end

-- Pasek Aury: dolicza sekundy aktywności, a za każde pełne 10 minut daje +10 Aury (razy Aura Gain).
-- Przed Rebirth 1 pasek stoi. Zwraca dodaną Aurę i ile razy pasek się napełnił.
function Rebirth.addBarTime(data, seconds)
	if not Rebirth.unlocked(data) or seconds <= 0 then
		return 0, 0
	end
	local bar = (data.AuraBar or 0) + seconds
	local full = math.floor(bar / A.BarSeconds + 1e-9)
	data.AuraBar = math.max(0, bar - full * A.BarSeconds)
	local added = 0
	if full > 0 then
		added = Rebirth.addAura(data, full * A.BarReward)
	end
	return added, full
end

----------------------------------------------------------------- Sklep Aury
function Rebirth.level(data, key)
	return upgrades(data)[key] or 0
end

-- Najwyższy poziom ulepszenia albo nil (bez limitu).
function Rebirth.maxLevel(key)
	local u = A.Upgrades[key]
	if u ~= nil and u.Costs ~= nil then
		return #u.Costs
	end
	return nil
end

-- Koszt następnego poziomu albo nil (Merge Luck na 5. poziomie).
function Rebirth.nextCost(data, key)
	return Formulas.auraUpgradeCost(key, Rebirth.level(data, key) + 1)
end

-- Aura Level = suma poziomów wszystkich ulepszeń.
function Rebirth.auraLevel(data)
	local n = 0
	for _, key in ipairs(Rebirth.UpgradeOrder) do
		n = n + Rebirth.level(data, key)
	end
	return n
end

-- Kolor poświaty dla Aura Level (nil poniżej 10): White, Blue, Purple, Gold, Red, Rainbow.
function Rebirth.glow(data)
	return Formulas.glowFor(Rebirth.auraLevel(data))
end

-- Efekt ulepszenia na danym poziomie (do okna sklepu i do testów):
-- ClickBoost: mnożnik Click Multipliera, Luck: szczęście, AuraGain: mnożnik Aury,
-- MergeLuck: szansa na sztukę przy łączeniu.
function Rebirth.effect(key, level)
	if key == "ClickBoost" then
		return Formulas.clickBoost(level)
	elseif key == "Luck" then
		return Formulas.luck(level)
	elseif key == "AuraGain" then
		return Formulas.auraGain(level)
	elseif key == "MergeLuck" then
		return Formulas.mergeChancePerPiece(level)
	end
	return nil
end

-- Kupuje ulepszenie za Aurę: mode "One" (1 poziom) albo "Max" (tyle, ile starczy Aury).
-- Zwraca { Bought, Spent, Level } albo nil i powód: BadRequest, Locked (przed Rebirth 1),
-- Maxed, NotEnough.
function Rebirth.buyUpgrade(data, key, mode)
	if A.Upgrades[key] == nil or (mode ~= "One" and mode ~= "Max") then
		return nil, "BadRequest"
	end
	if not Rebirth.unlocked(data) then
		return nil, "Locked"
	end
	local limit = 1
	if mode == "Max" then
		limit = 10000
	end
	local list = upgrades(data)
	local bought, spent = 0, 0
	while bought < limit do
		local cost = Rebirth.nextCost(data, key)
		if cost == nil then
			if bought == 0 then
				return nil, "Maxed"
			end
			break
		end
		if (data.Aura or 0) + 1e-9 < cost then
			if bought == 0 then
				return nil, "NotEnough"
			end
			break
		end
		data.Aura = math.max(0, data.Aura - cost)
		list[key] = (list[key] or 0) + 1
		bought = bought + 1
		spent = spent + cost
	end
	return { Bought = bought, Spent = spent, Level = list[key] }
end

----------------------------------------------------------------- Stan dla klienta
function Rebirth.view(data)
	local ok = Rebirth.canRebirth(data)
	local count = data.RebirthCount or 0
	local nextLevel = Formulas.rebirthLevel(count + 1)
	local levels = {}
	for _, key in ipairs(Rebirth.UpgradeOrder) do
		levels[key] = Rebirth.level(data, key)
	end
	return {
		RebirthTitle = Rebirth.title(data.RebirthLevel or 0),
		CanRebirth = ok,
		NextRebirthFee = Rebirth.nextFee(data),
		NextRebirthLevel = nextLevel,
		NextRebirthAura = Rebirth.nextAura(data),
		AuraUnlocked = Rebirth.unlocked(data),
		AuraBar = data.AuraBar or 0,
		AuraLevel = Rebirth.auraLevel(data),
		AuraUpgrades = levels,
	}
end

return Rebirth
