-- Testy ubrań (Etap 8): bonusy, sloty, boxy, zakładanie, warstwa LP, sprzedaż i łączenie.
-- Uruchamia je ConfigCheck w Studio i tools/test_luau.py poza Roblox.
-- Zwraca funkcję: passed, failed, messages.

local Shared = script.Parent.Parent
local Economy = require(Shared.Config.Economy)
local Loop = require(Shared.Logic.Loop)
local Clothes = require(Shared.Logic.Clothes)
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
			table.insert(messages, "ClothesSpec: " .. msg)
		end
	end

	local function near(a, b)
		return math.abs(a - b) <= 1e-9 * math.max(1, math.abs(b))
	end

	local function fresh()
		return copy(Template)
	end

	-- „losowanie” z listy liczb (po kolei; potem zawsze ostatnia)
	local function seq(list)
		local i = 0
		return function()
			i = i + 1
			return list[math.min(i, #list)]
		end
	end

	local function always(x)
		return function()
			return x
		end
	end

	local boxes = Economy.Clothes.Boxes
	local street = boxes.Street.Price

	----------------------------------------------------------------- Bonusy i sloty
	check(near(Clothes.bonus({ Rarity = "Rare", Level = 0 }), 0.8), "Rare daje +80% LP")
	check(near(Clothes.bonus({ Rarity = "Rare", Level = 1 }), 1.6) and near(Clothes.bonus({ Rarity = "Mythic", Level = 2 }), 25.6), "Golden ×2, Diamond ×4")
	check(Clothes.slots({}, "Chain") == 1 and Clothes.slots({ passes = { DoubleChain = true } }, "Chain") == 2, "Double Chain daje drugi łańcuch")
	check(Clothes.slots({ passes = { DoubleWrist = true } }, "Watch") == 2 and Clothes.slots({ passes = { DoubleChain = true } }, "Hair") == 1, "Double Wrist daje drugi zegarek, reszta kategorii ma 1 slot")
	check(#Clothes.Categories == 7, "7 kategorii ubrań")

	----------------------------------------------------------------- Boxy
	local d = fresh()
	local _, whyZone = Clothes.canBuy(d, "Street", 1)
	check(whyZone == "Zone", "box Street dopiero po odblokowaniu Mall (strefa 3)")
	d.ZonesUnlocked = 3
	local _, whyCash = Clothes.canBuy(d, "Street", 1)
	local _, whyDesigner = Clothes.canBuy(d, "Designer", 1)
	check(whyCash == "NotEnough" and whyDesigner == "Zone", "w Mall Street wymaga L$, a Designer plaży")
	local _, whyBad = Clothes.canBuy(d, "Nope", 1)
	check(whyBad == "BadRequest", "nieznany box")
	d.Cash = street * 3
	-- losowania: szczęście (część ułamkowa), rzadkość, kategoria
	local id1, item1, worn1 = Clothes.openBox(d, {}, "Street", seq({ 0.5, 0.95, 0.45 }), 250)
	check(item1.Rarity == "Rare" and item1.Category == "Watch" and item1.Box == "Street" and item1.Level == 0, "box: Rare (0,95) i 4. kategoria (0,45 → Watch)")
	check(worn1 and Clothes.isWorn(d, id1) and d.Cash == street * 2 and d.NextClothId == 2 and d.Stats.BoxesOpened == 1, "nowe ubranie samo się zakłada na wolny slot, L$ pobrane")
	local id2, item2, worn2 = Clothes.openBox(d, {}, "Street", seq({ 0.5, 0.1, 0.5 }), 250)
	check(item2.Rarity == "Common" and item2.Category == "Watch" and not worn2 and Clothes.isWorn(d, id1), "słabszy zegarek nie zdejmuje lepszego")
	local id3, item3, worn3 = Clothes.openBox(d, {}, "Street", seq({ 0.5, 0.99, 0.5 }), 250)
	check(item3.Rarity == "Epic" and worn3 and Clothes.isWorn(d, id3) and not Clothes.isWorn(d, id1), "lepszy zegarek zastępuje słabszy")
	local _, whyFull = Clothes.openBox(d, {}, "Street", always(0.5), 3)
	check(whyFull == "Inventory" or whyFull == "NotEnough", "pełny ekwipunek albo brak L$ blokuje box")
	check(not Clothes.isWorn(d, id2), "Common zegarek leży w ekwipunku")

	----------------------------------------------------------------- Zakładanie i warstwa LP
	d = fresh()
	d.Clothes = {
		a = { Category = "Chain", Rarity = "Rare", Level = 0, Box = "Street" },
		b = { Category = "Chain", Rarity = "Epic", Level = 0, Box = "Street" },
		c = { Category = "Chain", Rarity = "Common", Level = 0, Box = "Street" },
		h = { Category = "Hair", Rarity = "Mythic", Level = 2, Box = "Iced" },
	}
	check(Clothes.wear(d, {}, "a") and Clothes.wear(d, {}, "b") and #d.Worn == 1 and d.Worn[1] == "b", "1 slot: nowy łańcuch zastępuje stary")
	local double = { passes = { DoubleChain = true } }
	check(Clothes.wear(d, double, "a") and #Clothes.active(d, double) == 2, "z Double Chain dwa łańcuchy naraz")
	check(Clothes.wear(d, double, "c") and Clothes.isWorn(d, "b") and Clothes.isWorn(d, "c") and not Clothes.isWorn(d, "a"), "przy 2 pełnych slotach schodzi najsłabszy")
	check(#Clothes.active(d, {}) == 1, "bez gamepassa działa tylko pierwszy łańcuch")
	local best = Clothes.wearBest(d, double)
	check(#best == 3 and Clothes.isWorn(d, "h") and Clothes.isWorn(d, "b") and Clothes.isWorn(d, "a"), "WEAR BEST: Mythic we włosach i dwa najlepsze łańcuchy")
	check(near(Clothes.layer(d, double), 1 + 25.6 + 1.6 + 0.8) and near(Clothes.layer(d, {}), 1 + 25.6 + 1.6), "warstwa ubrań = 1 + suma bonusów założonych")
	local layer = Clothes.layer(d, {})
	check(near(Loop.lpMultiplier(d, { clothLayer = layer }), layer), "warstwa ubrań mnoży LP (Loop.lpMultiplier)")
	check(Clothes.unwear(d, "h") and not Clothes.isWorn(d, "h") and not Clothes.unwear(d, "h"), "zdejmowanie")
	check(Clothes.view(d, {}).ClothesCount == 4 and Clothes.view(d, {}).ShowClothes == true, "widok dla HUD")

	----------------------------------------------------------------- Sprzedaż
	check(Clothes.sellValue({ Rarity = "Common", Level = 0 }) == street * 0.1, "sprzedaż: 10% ceny boxa Street")
	check(Clothes.sellValue({ Rarity = "Legendary", Level = 0 }) == boxes.Designer.Price * 0.1 and Clothes.sellValue({ Rarity = "Mythic", Level = 0 }) == boxes.Iced.Price * 0.1, "Legendary liczy się od Designer, Mythic od Iced")
	check(Clothes.sellValue({ Rarity = "Rare", Level = 1 }) == street * 0.1 * 5 and Clothes.sellValue({ Rarity = "Rare", Level = 2 }) == street * 0.1 * 25, "Golden ×5, Diamond ×25")
	d.Worn = { "b" }
	local sold, soldCash = Clothes.sell(d, {}, { "a", "b", "c", "brak" })
	check(sold == 2 and soldCash == street * 0.2 and d.Clothes.b ~= nil and d.Cash == soldCash and d.Stats.ClothesSold == 2, "sprzedaż 2 ubrań, założonego nie sprzedaje")
	check(d.Stats.LifetimeCash == soldCash, "L$ ze sprzedaży liczą się do zarobionych")

	----------------------------------------------------------------- Łączenie
	local function fiveShirts(level, box)
		local data = fresh()
		for i = 1, 5 do
			data.Clothes["s" .. i] = { Category = "Shirt", Rarity = "Rare", Level = level, Box = box }
		end
		return data, { "s1", "s2", "s3", "s4", "s5" }
	end
	d = fiveShirts(0, "Street")
	local info2 = Clothes.mergeInfo(d, { "s1", "s2" })
	check(near(info2.Chance, 0.4) and info2.Fee == street * 2 / 5 and info2.Level == 1 and info2.Category == "Shirt", "2 koszule: 40% i 2/5 opłaty (cena Street)")
	local _, all5 = fiveShirts(0, "Street")
	check(near(Clothes.mergeInfo(d, all5).Chance, 1) and Clothes.mergeInfo(d, all5).Fee == street, "5 ubrań: 100% i pełna opłata")
	d.Clothes.s5.Category = "Pants"
	local notSame, whyNotSame = Clothes.mergeInfo(d, all5)
	check(notSame == nil and whyNotSame == "NotSame", "łączyć można tylko identyczne ubrania")
	local dMax = fiveShirts(2, "Street")
	local _, whyMax = Clothes.mergeInfo(dMax, { "s1" })
	check(whyMax == "MaxLevel", "Diamond nie łączy się dalej")
	local dGold = fiveShirts(1, "Iced")
	check(Clothes.mergeInfo(dGold, { "s1" }).Fee == street * 5 / 5, "Diamond: opłata × 5 (cena Street, bo Rare)")
	local dPrem = fiveShirts(0, "P")
	local prem, whyPrem = Clothes.mergeInfo(dPrem, { "s1", "s2" })
	check(prem == nil and whyPrem == "Premium" and Clothes.mergeInfo(dPrem, all5) ~= nil, "kupione za Robuxy tylko przy 100%")

	d = fiveShirts(0, "Street")
	d.Worn = { "s1" }
	local poor, whyPoor = Clothes.merge(d, {}, { "s1", "s2" }, always(0))
	check(poor == nil and whyPoor == "NotEnough" and d.Clothes.s1 ~= nil, "bez L$ na opłatę nic nie znika")
	d.Cash = 1e9
	local win = Clothes.merge(d, {}, { "s1", "s2" }, always(0.39))
	check(win.Success and win.Item.Level == 1 and win.Worn and Clothes.isWorn(d, win.Id) and d.Clothes.s1 == nil, "sukces: Golden koszula, założona zamiast połączonej")
	check(d.Cash == 1e9 - info2.Fee and d.Stats.ClothMerges == 1, "opłata pobrana")
	local lose = Clothes.merge(d, {}, { "s3", "s4" }, always(0.4))
	check(not lose.Success and d.Clothes.s3 == nil and d.Clothes.s4 == nil and Clothes.count(d) == 2 and d.Stats.ClothMergesFailed == 1, "porażka: oba ubrania przepadają")

	return passed, failed, messages
end
