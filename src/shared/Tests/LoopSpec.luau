-- Testy pętli: klik, Bag, Sell, Auto-Sell, ulepszenia, strefy, limit kliknięć i zapis liczb w komendach.
-- Uruchamia je ConfigCheck w Studio i tools/test_luau.py poza Roblox.
-- Zwraca funkcję: passed, failed, messages.

local Shared = script.Parent.Parent
local Economy = require(Shared.Config.Economy)
local Formulas = require(Shared.Formulas)
local Format = require(Shared.Format)
local Loop = require(Shared.Logic.Loop)
local RateLimiter = require(Shared.Logic.RateLimiter)
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
			table.insert(messages, "LoopSpec: " .. msg)
		end
	end

	local function near(a, b)
		return math.abs(a - b) <= 1e-9 * math.max(1, math.abs(b))
	end

	local function fresh()
		return copy(Template)
	end

	----------------------------------------------------------------- LP za klik
	local d = fresh()
	local v10 = Formulas.clickValue(10)
	check(Loop.clickLP(d, {}) == 1, "nowy gracz ma 1 LP za klik")
	d.ClickLevel = 10
	check(Loop.clickLP(d, {}) == v10, "poziom 10 daje clickValue(10)")
	check(near(Loop.clickLP(d, { zone = 2 }), v10 * 1.5), "strefa 2 mnoży ×1,5")
	check(near(Loop.clickLP(d, { zone = 5 }), v10 * 250), "strefa 5 mnoży ×250")
	check(near(Loop.clickLP(d, { passes = { TwoXLP = true } }), v10 * 2), "2x LP podwaja")
	check(
		near(Loop.clickLP(d, { passes = { TwoXLP = true, Verified = true } }), v10 * 2.1),
		"2x LP + Verified = ×2,1 (w warstwie dodajemy)"
	)
	check(near(Loop.clickLP(d, { inGroup = true, friends = 5 }), v10 * 1.35), "grupa +5%, znajomi maks. 3 × 10%")
	check(near(Loop.clickLP(d, { boost = true }), v10 * 2), "boost 2x LP")
	d.RebirthLevel = 10
	check(near(Loop.clickLP(d, {}), v10 * 25), "Rebirth 10 mnoży ×25")
	d.AuraUpgrades.ClickBoost = 10
	check(near(Loop.clickLP(d, {}), v10 * 25 * 2), "Click Boost poziom 10 mnoży ×2")

	----------------------------------------------------------------- Bag
	d = fresh()
	check(Loop.capacity(d, {}) == 100, "Bag poziom 0 mieści 100 LP")
	check(Loop.capacity(d, { passes = { TwoXBag = true } }) == 200, "2x Bag mieści 200 LP")
	d.Bag = 99.5
	local added = Loop.collect(d, 5, {})
	check(near(added, 0.5) and d.Bag == 100, "klik zatrzymuje się na pojemności")
	check(Loop.isFull(d, {}), "Bag jest pełny")
	added = Loop.click(d, {})
	check(added == 0 and d.Stats.Clicks == 0, "klik przy pełnym Bag nic nie daje i się nie liczy")
	added = Loop.collect(d, 50, {}, true)
	check(added == 50 and d.Bag == 150, "nagroda z aktywności wchodzi do pełnego Bag")

	----------------------------------------------------------------- Sell
	d = fresh()
	d.Bag = 80
	local gained = Loop.sell(d, {})
	check(gained == 80 and d.Cash == 80 and d.Bag == 0 and d.Stats.Sells == 1, "Sell: 80 LP daje 80 L$")
	check(Loop.sell(d, {}) == 0 and d.Stats.Sells == 1, "pusty Bag nic nie sprzedaje")
	d.Bag = 100
	check(Loop.sell(d, { petLayer = 1.5 }) == 150, "pety mnożą L$ przy Sell")

	----------------------------------------------------------------- Auto-Sell
	d = fresh()
	local ctx = { passes = { AutoSell = true } }
	d.Bag = 99
	local added2, sold = Loop.collect(d, 5, ctx)
	check(added2 == 5 and sold == 104 and d.Bag == 0 and d.Cash == 104, "Auto-Sell sprzedaje pełny Bag bez strat")
	check(not Loop.isFull(d, ctx), "z Auto-Sell Bag nie blokuje kliknięć")
	d.Settings.AutoSell = false
	check(Loop.autoSellOn(d, ctx) == false, "Auto-Sell można wyłączyć w ustawieniach")

	----------------------------------------------------------------- Ulepszenia
	d = fresh()
	d.Cash = 24
	check(Loop.buy(d, "Click", 1) == 0 and d.Cash == 24, "za mało L$ na 1. poziom (25)")
	d.Cash = 25
	local n, spent = Loop.buy(d, "Click", 1)
	check(n == 1 and spent == 25 and d.ClickLevel == 1 and d.Cash == 0, "Kup 1: poziom 1 za 25 L$")
	d.Cash = 1000
	local expectN, expectSpent = 0, 0
	while true do
		local c = Economy.ClickMultiplier.Costs[d.ClickLevel + expectN + 1]
		if c == nil or expectSpent + c > 1000 then
			break
		end
		expectSpent = expectSpent + c
		expectN = expectN + 1
	end
	n, spent = Loop.buy(d, "Click", nil)
	check(
		n == expectN and spent == expectSpent and d.Cash == 1000 - expectSpent and n > 1,
		"Kup max kupuje tyle poziomów, na ile starczy L$"
	)
	d.ClickLevel = Loop.MaxLevel.Click
	d.Cash = 1e30
	check(Loop.nextCost(d, "Click") == nil and Loop.buy(d, "Click", nil) == 0, "Click Multiplier kończy się na 150")
	d = fresh()
	d.Cash = 50
	n = Loop.buy(d, "Bag", 1)
	check(n == 1 and d.BagLevel == 1 and Loop.capacity(d, {}) == 250, "Bag poziom 1 za 50 L$ mieści 250 LP")
	check(Loop.MaxLevel.Bag == 35, "Bag ma 35 poziomów")

	----------------------------------------------------------------- Widok dla HUD
	d = fresh()
	local view = Loop.view(d, {})
	check(
		view.LPPerClick == 1
			and view.NextLPPerClick == 2
			and view.NextClickCost == 25
			and view.BagCapacity == 100
			and view.NextBagCapacity == 250
			and view.BagFull == false,
		"widok dla HUD nowego gracza"
	)

	----------------------------------------------------------------- Strefy
	d = fresh()
	check(Loop.nextZone(d) == Economy.Zones[2], "nowy gracz może kupić strefę 2")
	d.Cash = Economy.Zones[2].Cost - 1
	local bought, why = Loop.buyZone(d, 2)
	check(not bought and why == "NotEnough" and d.ZonesUnlocked == 1, "za mało L$ na strefę 2")
	d.Cash = Economy.Zones[2].Cost
	bought, why = Loop.buyZone(d, 3)
	check(not bought and why == "Locked", "strefy kupuje się po kolei")
	bought = Loop.buyZone(d, 2)
	check(bought and d.ZonesUnlocked == 2 and d.Cash == 0, "strefa 2 kosztuje 6K L$")
	bought, why = Loop.buyZone(d, 2)
	check(not bought and why == "Owned", "kupionej strefy nie kupuje się drugi raz")
	bought, why = Loop.buyZone(d, 9)
	check(not bought and why == "BadRequest", "nie ma strefy 9")
	check(
		Loop.effectiveZone(d, 4) == 2 and Loop.effectiveZone(d, 2) == 2 and Loop.effectiveZone(d, nil) == 1,
		"mnożnik najwyżej z ostatniej odblokowanej strefy"
	)
	check(Loop.view(d, { zone = 2 }).Zone == 2 and Loop.view(d, {}).ZonesUnlocked == 2, "widok ma strefę i odblokowane strefy")
	d.ZonesUnlocked = #Economy.Zones
	check(Loop.nextZone(d) == nil, "po ostatniej strefie nie ma następnej")

	----------------------------------------------------------------- Limit kliknięć
	local limiter = RateLimiter.new(10, 10)
	local got = 0
	for _ = 1, 15 do
		got = got + limiter:take(0, 1)
	end
	check(got == 10, "limit: najwyżej 10 kliknięć naraz")
	check(limiter:take(0.5, 10) == 5, "limit: po 0,5 s wraca 5 kliknięć")
	check(limiter:take(10, 100) == 10, "limit: nie zbiera więcej niż 10")

	----------------------------------------------------------------- Liczby w komendach
	check(Format.parse("1.5M") == 1500000, "parse 1.5M")
	check(Format.parse("3t") == 3e12, "parse 3t")
	check(Format.parse("1e12") == 1e12, "parse 1e12")
	check(Format.parse("2.5Qa") == 2.5e15, "parse 2.5Qa")
	check(Format.parse("-100") == -100, "parse -100")
	check(Format.parse("abc") == nil and Format.parse("1.5X") == nil and Format.parse("") == nil, "parse odrzuca złe liczby")
	check(Format.small(1.5) == "1.5" and Format.small(2) == "2" and Format.small(1500) == "1.5K", "zapis małych liczb")

	return passed, failed, messages
end
