-- Testy Rebirth i Aury (Etap 9): warunki i reset, poziomy po R10, Aura, pasek Aury, sklep Aury,
-- Aura Level i poświata. Uruchamia je ConfigCheck w Studio i tools/test_luau.py poza Roblox.
-- Zwraca funkcję: passed, failed, messages.

local Shared = script.Parent.Parent
local Economy = require(Shared.Config.Economy)
local Formulas = require(Shared.Formulas)
local Loop = require(Shared.Logic.Loop)
local Rebirth = require(Shared.Logic.Rebirth)
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

	local function near(a, b)
		return type(a) == "number" and math.abs(a - b) <= 1e-6 * math.max(1, math.abs(b))
	end

	local function fresh()
		return copy(Template)
	end

	local fees = Economy.Rebirth.Fees

	----------------------------------------------------------------- Warunki
	local d = fresh()
	local ok, why = Rebirth.canRebirth(d)
	check(not ok and why == "Zone", "Rebirth dopiero ze wszystkimi strefami")
	d.ZonesUnlocked = #Economy.Zones
	d.Cash = fees[1] - 1
	ok, why = Rebirth.canRebirth(d)
	check(not ok and why == "NotEnough" and near(Rebirth.nextFee(d), 40e12), "opłata za Rebirth 1: 40T")
	check(Rebirth.rebirth(d) == nil and d.RebirthCount == 0 and d.Cash == fees[1] - 1, "bez L$ na opłatę nic się nie dzieje")

	----------------------------------------------------------------- Rebirth 1: reset i nagrody
	d.Cash = fees[1] * 3
	d.Bag = 123
	d.ClickLevel = 50
	d.BagLevel = 20
	d.ActivityTiers = { Car = 5, Yacht = 4, Jet = 3 }
	d.Pets["1"] = { Zone = 1, Rarity = "Rare", Level = 0, Egg = "A" }
	d.Equipped = { "1" }
	d.Clothes["1"] = { Category = "Hair", Rarity = "Rare", Level = 0, Box = "Street" }
	d.Worn = { "1" }
	d.Index["1:Rare"] = true
	local r1 = Rebirth.rebirth(d)
	check(r1 ~= nil and r1.Count == 1 and r1.Level == 1 and r1.LevelUp and r1.FirstAura and r1.Title == "Wannabe", "R1: poziom 1 i tytuł Wannabe")
	check(d.Cash == 0 and d.Bag == 0 and d.ClickLevel == 0 and d.BagLevel == 0 and d.ZonesUnlocked == 1, "R1 zeruje L$, Bag, Click, Bag i strefy")
	check(d.ActivityTiers.Car == 1 and d.ActivityTiers.Yacht == 1 and d.ActivityTiers.Jet == 0, "R1: auta, jachty i odrzutowce jak u nowego gracza")
	check(d.Pets["1"] ~= nil and #d.Equipped == 1 and d.Clothes["1"] ~= nil and #d.Worn == 1 and d.Index["1:Rare"], "R1: pety, ubrania i indeks zostają")
	check(near(d.Aura, 100) and near(r1.Aura, 100) and near(d.Stats.AuraEarned, 100), "R1: +100 Aury")
	d.ActivityTiers.Car = 3
	check(Template.ActivityTiers.Car == 1, "Rebirth kopiuje tiery z szablonu, nie zmienia szablonu")

	local zero, one = fresh(), fresh()
	one.RebirthLevel = 1
	check(near(Loop.clickLP(one, {}), Loop.clickLP(zero, {}) * 2), "R1: LP z kliknięcia ×2")

	----------------------------------------------------------------- R10 i dalej
	local e = fresh()
	for i = 1, 10 do
		e.ZonesUnlocked = #Economy.Zones
		e.Cash = Formulas.rebirthFee(i)
		Rebirth.rebirth(e)
	end
	check(e.RebirthLevel == 10 and e.RebirthCount == 10 and Rebirth.title(10) == "Certified Larper", "R10: poziom 10, Certified Larper")
	check(near(e.Aura, 5500), "Aura z R1–R10: 100 + 200 + … + 1 000 = 5 500")
	check(near(Loop.clickLP(e, {}), Loop.clickLP(zero, {}) * 25), "R10: LP ×25")
	check(near(Rebirth.walkSpeed(10), 24) and near(Rebirth.walkSpeed(0), Economy.WalkSpeed), "R10: szybkość chodzenia +50% (24)")
	check(near(Rebirth.nextFee(e), fees[10] * 1.25), "R11: opłata o 25% wyższa niż R10")
	e.ZonesUnlocked = #Economy.Zones
	e.Cash = Rebirth.nextFee(e)
	local r11 = Rebirth.rebirth(e)
	check(r11 ~= nil and r11.Count == 11 and r11.Level == 10 and not r11.LevelUp and near(r11.Aura, 1000), "po R10: licznik rośnie, poziom zostaje, +1 000 Aury")
	check(near(Rebirth.nextFee(e), fees[10] * 1.25 * 1.25), "R12: znowu +25%")
	check(Rebirth.petSlotsAt(2) == 0 and Rebirth.petSlotsAt(3) == 1 and Rebirth.petSlotsAt(7) == 2, "sloty na pety: +1 od R3, +1 od R7")
	local three = fresh()
	three.RebirthLevel = 3
	check(Loop.petSlots(three, {}) == Loop.petSlots(zero, {}) + 1, "R3: jeden slot na peta więcej")
	local forced = fresh()
	local rf = Rebirth.rebirth(forced, true)
	check(rf ~= nil and forced.RebirthCount == 1, "tryb testowy: Rebirth bez opłaty i stref")

	----------------------------------------------------------------- Aura i pasek
	local f = fresh()
	check(Rebirth.addAura(f, 50) == 0 and f.Aura == 0, "przed R1 Aura nie przychodzi")
	check(Rebirth.addBarTime(f, 10000) == 0 and f.AuraBar == 0, "przed R1 pasek Aury stoi")
	f.RebirthCount = 1
	local added, full = Rebirth.addBarTime(f, 599)
	check(added == 0 and full == 0 and near(f.AuraBar, 599), "pasek: 599 s to jeszcze nic")
	added, full = Rebirth.addBarTime(f, 1)
	check(near(added, 10) and full == 1 and near(f.AuraBar, 0), "pasek: 10 minut aktywności = +10 Aury")
	added, full = Rebirth.addBarTime(f, 1300)
	check(near(added, 20) and full == 2 and near(f.AuraBar, 100), "pasek: dwa pełne naraz i reszta zostaje")
	check(Rebirth.barSecondsFor("Interview") == 2 * Economy.Activities.Interview.DurationSeconds and Rebirth.barSecondsFor("Car") == Economy.Activities.Car.DurationSeconds, "wywiad napełnia pasek 2× szybciej")
	f.AuraUpgrades.AuraGain = 10
	check(near(Rebirth.addAura(f, 100), 150), "Aura Gain 10: +50% Aury")
	local g = fresh()
	g.RebirthCount = 1
	g.RebirthLevel = 1
	g.AuraBar = Economy.Aura.BarSeconds - 10
	local _, _, _, aura = Loop.finishActivity(g, {}, "Interview", 1)
	check(near(aura, 10) and near(g.AuraBar, 2 * Economy.Activities.Interview.DurationSeconds - 10), "koniec wywiadu dolicza pasek: +10 Aury i reszta na następny")

	----------------------------------------------------------------- Sklep Aury
	local s = fresh()
	check(select(2, Rebirth.buyUpgrade(s, "Luck", "One")) == "Locked", "sklep Aury działa od Rebirth 1")
	s.RebirthCount = 1
	s.RebirthLevel = 1
	s.Aura = 99
	check(select(2, Rebirth.buyUpgrade(s, "Luck", "One")) == "NotEnough", "Luck poz. 1 kosztuje 100 Aury")
	s.Aura = 100
	local one1 = Rebirth.buyUpgrade(s, "Luck", "One")
	check(one1 ~= nil and one1.Bought == 1 and one1.Level == 1 and near(s.Aura, 0), "Buy 1: Luck poz. 1 za 100")
	s.Aura = 1490
	local max = Rebirth.buyUpgrade(s, "Luck", "Max")
	check(max ~= nil and max.Bought == 9 and max.Level == 10 and near(max.Spent, 1490) and near(s.Aura, 0), "Buy Max: poziomy 2–10 za 1 490 (razem 1 590)")
	check(near(Rebirth.effect("Luck", 10), 1.5) and near(Formulas.luck(s.AuraUpgrades.Luck), 1.5), "Luck 10: szczęście ×1,5")
	s.Aura = 200 + 400 + 800 + 1500 + 3000 + 50
	local merge = Rebirth.buyUpgrade(s, "MergeLuck", "Max")
	check(merge ~= nil and merge.Bought == 5 and merge.Level == 5 and near(s.Aura, 50), "Merge Luck: 5 poziomów za 5 900")
	check(select(2, Rebirth.buyUpgrade(s, "MergeLuck", "One")) == "Maxed" and Rebirth.nextCost(s, "MergeLuck") == nil and Rebirth.maxLevel("MergeLuck") == 5, "Merge Luck ma limit 5 poziomów")
	check(near(Rebirth.effect("MergeLuck", 5), 0.25), "Merge Luck 5: 25% na sztukę")
	check(select(2, Rebirth.buyUpgrade(s, "Nope", "One")) == "BadRequest" and select(2, Rebirth.buyUpgrade(s, "Luck", "All")) == "BadRequest", "zła nazwa albo tryb")
	s.Aura = 100
	local click = Rebirth.buyUpgrade(s, "ClickBoost", "One")
	check(click ~= nil and click.Level == 1 and near(Loop.clickLP(s, {}), Loop.clickLP(one, {}) * 1.1), "Click Boost 1: LP z kliknięcia ×1,1")

	----------------------------------------------------------------- Aura Level i poświata
	check(Rebirth.auraLevel(s) == 16 and Rebirth.glow(s) == "White", "Aura Level 16 (10 + 5 + 1): biała poświata")
	check(Formulas.glowFor(9) == nil and Formulas.glowFor(25) == "Blue" and Formulas.glowFor(75) == "Gold" and Formulas.glowFor(150) == "Rainbow", "poświata: progi 10, 25, 50, 75, 100, 150")
	local v = Loop.view(s, {})
	check(v.AuraUnlocked and v.AuraLevel == 16 and v.AuraUpgrades.MergeLuck == 5 and v.RebirthTitle == "Wannabe" and near(v.NextRebirthAura, 200), "stan dla klienta: Aura Level, poziomy, tytuł i Aura za następny Rebirth")
	check(Loop.view(fresh(), {}).AuraUnlocked == false, "przed R1 licznik Aury jest ukryty")

	return passed, failed, messages
end
