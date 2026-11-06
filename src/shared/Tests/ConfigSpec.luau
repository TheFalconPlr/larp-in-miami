-- Sprawdza, czy liczby i wzory w grze zgadzają się z arkuszem ekonomii v2.
-- Uruchamia go ConfigCheck (tylko w Studio) i test w Pythonie (tools/test_luau.py).

local function approx(a, b, tol)
	if a == nil or b == nil then
		return a == b
	end
	tol = tol or 1e-9
	return math.abs(a - b) <= tol * math.max(1, math.abs(b))
end

return function(Economy, Formulas, Format)
	local passed, failed, messages = 0, 0, {}

	local function check(name, actual, expected, tol)
		local ok
		if type(expected) == "number" then
			ok = type(actual) == "number" and approx(actual, expected, tol)
		else
			ok = actual == expected
		end
		if ok then
			passed = passed + 1
		else
			failed = failed + 1
			table.insert(messages, string.format("BŁĄD %s: jest %s, powinno być %s", name, tostring(actual), tostring(expected)))
		end
	end

	-- Ceny z arkusza
	check("Strefa 5", Economy.Zones[5].Cost, 3e12)
	check("Mnożnik strefy 5", Economy.Zones[5].ClickMultiplier, 250)
	check("Jajko 5B", Economy.Pets.Eggs[5].B.Price, 2e11)
	check("Box Iced", Economy.Clothes.Boxes.Iced.Price, 8e10)
	check("Box Iced wymaga strefy", Economy.Clothes.Boxes.Iced.RequiresZone, 5)
	check("Opłata R1", Economy.Rebirth.Fees[1], 4e13)
	check("Opłata R10", Economy.Rebirth.Fees[10], 7.5e17)
	check("Mnożnik R10", Economy.Rebirth.LPMultiplier[10], 25)
	check("Click Multiplier: koszt poz. 1", Formulas.clickCost(1), 25)
	check("Bag: pojemność poz. 0", Formulas.bagCapacity(0, false), 100)
	check("Bag: 2x Bag", Formulas.bagCapacity(0, true), 200)

	-- Click Multiplier (ZAOKR jak w arkuszu, połówki w górę)
	check("LP za klik poz. 0", Formulas.clickValue(0), 1)
	check("LP za klik poz. 5", Formulas.clickValue(5), 9)
	check("LP za klik poz. 15", Formulas.clickValue(15), 39)
	check("LP za klik poz. 25", Formulas.clickValue(25), 89)
	check("LP za klik poz. 150", Formulas.clickValue(150), 2401)

	-- Sklep Aury
	check("Click Boost poz. 1", Formulas.auraUpgradeCost("ClickBoost", 1), 100)
	check("Click Boost poz. 2", Formulas.auraUpgradeCost("ClickBoost", 2), 110)
	check("Click Boost poz. 5", Formulas.auraUpgradeCost("ClickBoost", 5), 150)
	check("Click Boost poz. 10", Formulas.auraUpgradeCost("ClickBoost", 10), 240)
	check("Click Boost poz. 30", Formulas.auraUpgradeCost("ClickBoost", 30), 1600)
	check("Click Boost poz. 50", Formulas.auraUpgradeCost("ClickBoost", 50), 11000)
	check("Luck poz. 20", Formulas.auraUpgradeCost("Luck", 20), 610)
	check("Aura Gain poz. 10", Formulas.auraUpgradeCost("AuraGain", 10), 880)
	check("Aura Gain poz. 20", Formulas.auraUpgradeCost("AuraGain", 20), 3600)
	check("Merge Luck poz. 5", Formulas.auraUpgradeCost("MergeLuck", 5), 3000)
	check("Merge Luck po limicie", Formulas.auraUpgradeCost("MergeLuck", 6), nil)
	local sum = 0
	for L = 1, 10 do
		sum = sum + Formulas.auraUpgradeCost("ClickBoost", L)
	end
	check("Click Boost łącznie do 10", sum, 1590)
	check("Click Boost efekt poz. 10", Formulas.clickBoost(10), 2)
	check("Luck efekt poz. 10", Formulas.luck(10), 1.5)
	check("Poświata przy Aura Level 33", Formulas.glowFor(33), "Blue")
	check("Poświata przy Aura Level 5", Formulas.glowFor(5), nil)
	check("Poświata przy Aura Level 150", Formulas.glowFor(150), "Rainbow")

	-- Łączenie
	check("Łączenie 3 sztuki", Formulas.mergeChance(3, 0), 0.6)
	check("Łączenie 4 sztuki, Merge Luck 5", Formulas.mergeChance(4, 5), 1)
	check("Łączenie 4 sztuki, Merge Luck 4", Formulas.mergeChance(4, 4), 0.96)
	check("Sztuk do 100%, Merge Luck 0", Formulas.piecesForCertain(0), 5)
	check("Sztuk do 100%, Merge Luck 4", Formulas.piecesForCertain(4), 5)
	check("Sztuk do 100%, Merge Luck 5", Formulas.piecesForCertain(5), 4)

	-- Rebirth po limicie
	check("Opłata 11. Rebirthu", Formulas.rebirthFee(11), 9.375e17)
	check("Opłata 12. Rebirthu", Formulas.rebirthFee(12), 1.171875e18)
	check("Aura za R3", Formulas.rebirthAura(3), 300)
	check("Aura za 11. Rebirth", Formulas.rebirthAura(11), 1000)

	-- Szczęście i szanse
	local B = Economy.Pets.Eggs[5].B.Odds
	local total = 0
	for _, p in pairs(B) do
		total = total + p
	end
	check("Jajko B: suma szans", total, 1, 1e-9)
	check("Sekret bez szczęścia", Formulas.effectiveOdds(B, 1).Secret, 4e-5, 1e-6)
	check("Sekret przy szczęściu 2,0", Formulas.effectiveOdds(B, 2).Secret, 7.99984e-5, 1e-4)
	check("Legendary przy szczęściu 2,0", Formulas.effectiveOdds(B, 2).Legendary, 0.0395984, 1e-5)
	check("Rare przy szczęściu 1,5", Formulas.effectiveOdds(B, 1.5).Rare, 0.411236, 1e-5)
	local eff = Formulas.effectiveOdds(B, 3)
	local effTotal = 0
	for _, p in pairs(eff) do
		effTotal = effTotal + p
	end
	check("Szczęście 3,0: suma szans", effTotal, 1, 1e-9)
	check("Moc sekreta strefy 5", Formulas.petPower(5, "Secret", 0), 1.28e2)
	check("Moc Złotego Legendary strefy 5", Formulas.petPower(5, "Legendary", 1), 64)

	-- Zapis liczb w grze
	check("Zapis 40T", Format.number(4e13), "40T")
	check("Zapis 937.5Qa", Format.number(9.375e17), "937.5Qa")
	check("Zapis 1.17Qi", Format.number(1.171875e18), "1.17Qi")
	check("Zapis 999", Format.number(999), "999")
	check("Zapis 1.5K", Format.number(1500), "1.5K")
	check("Zapis 999999", Format.number(999999), "1M")
	check("Zapis 999.6", Format.number(999.6), "1K")
	check("Zapis 0", Format.number(0), "0")
	check("Zapis 999Vg", Format.number(9.99e65), "999Vg")
	check("Zapis ponad Vg: 1e66", Format.number(1e66), "1e66")
	check("Zapis ponad Vg: 1.5e70", Format.number(1.5e70), "1.5e70")
	check("Czas 1h 05m", Format.duration(3905), "1h 05m")
	check("Czas 3m 05s", Format.duration(185), "3m 05s")
	check("Procent 5%", Format.percent(0.05), "5%")
	check("Procent sekreta", Format.percent(4e-5), "0.004%")
	check("1 in 25,000", Format.oneIn(4e-5), "1 in 25,000")

	return passed, failed, messages
end
