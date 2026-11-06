-- Tryb testowy: komendy na czacie (/cmds). W Studio działają zawsze, a w opublikowanej grze tylko
-- dla właściciela grupy i osób z Settings.Admin.UserIds (i tylko gdy AllowInLive = true).
-- Komendy tworzy klient (TextChatCommand), a serwer sprawdza uprawnienia i wykonuje.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared.Config.Economy)
local PetsConfig = require(Shared.Config.Pets)
local Settings = require(Shared.Config.Settings)
local Format = require(Shared.Format)
local Formulas = require(Shared.Formulas)
local Loop = require(Shared.Logic.Loop)
local Clothes = require(Shared.Logic.Clothes)
local Rebirth = require(Shared.Logic.Rebirth)
local ClothesConfig = require(Shared.Config.Clothes)
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)
local GamepassService = require(script.Parent.GamepassService)
local LoopService = require(script.Parent.LoopService)
local PetService = require(script.Parent.PetService)
local ClothesService = require(script.Parent.ClothesService)
local RebirthService = require(script.Parent.RebirthService)
local ZoneService = require(script.Parent.ZoneService)
local ShopService = require(script.Parent.ShopService)
local Robux = require(Shared.Robux)
local Shop = require(Shared.Logic.Shop)

local AdminService = {}

local adminCache = {} -- [player] = true/false
local COMMANDS = {}
local ORDER = {}

----------------------------------------------------------------- Uprawnienia
local function checkAdmin(player)
	if RunService:IsStudio() then
		return Settings.Admin.AllowInStudio == true
	end
	if not Settings.Admin.AllowInLive then
		return false
	end
	for _, id in ipairs(Settings.Admin.UserIds) do
		if id == player.UserId then
			return true
		end
	end
	if game.CreatorType == Enum.CreatorType.Group then
		local ok, rank = pcall(player.GetRankInGroup, player, game.CreatorId)
		return ok and rank == 255
	end
	return player.UserId == game.CreatorId
end

function AdminService.isAdmin(player)
	return adminCache[player] == true
end

----------------------------------------------------------------- Komendy
local function command(name, usage, help, fn)
	COMMANDS[name] = { usage = usage, help = help, fn = fn }
	table.insert(ORDER, name)
end

local function needNumber(arg)
	local n = Format.parse(arg)
	if n == nil then
		error("podaj liczbę, np. 1.5M, 3T albo 1e12", 0)
	end
	return n
end

local function needLevel(arg, max)
	local n = math.floor(needNumber(arg))
	if n < 0 or n > max then
		error(string.format("podaj liczbę od 0 do %d", max), 0)
	end
	return n
end

command("cmds", "/cmds", "lista komend", function()
	local lines = { "Komendy testowe:" }
	for _, name in ipairs(ORDER) do
		local c = COMMANDS[name]
		table.insert(lines, c.usage .. " · " .. c.help)
	end
	return table.concat(lines, "\n")
end)

command("cash", "/cash [ile]", "dodaj L$, np. /cash 1.5M (minus odejmuje)", function(_, data, args)
	data.Cash = math.max(0, data.Cash + needNumber(args[1]))
	return "L$: " .. Format.number(data.Cash)
end)

command("lp", "/lp [ile]", "dodaj LP do Bag, także ponad pojemność", function(_, data, args)
	data.Bag = math.max(0, data.Bag + needNumber(args[1]))
	return "Bag: " .. Format.number(data.Bag) .. " LP"
end)

command("fill", "/fill", "napełnij Bag do pełna", function(player, data)
	data.Bag = Loop.capacity(data, LoopService.contextFor(player))
	return "Bag: " .. Format.number(data.Bag) .. " LP (pełny)"
end)

command("sell", "/sell", "sprzedaj Bag od razu, bez chodzenia na Sell", function(player, data)
	if data.Bag <= 0 then
		error("Bag jest pusty", 0)
	end
	local gained = LoopService.sellNow(player)
	return "Sprzedane za " .. Format.number(gained) .. " L$ (L$: " .. Format.number(data.Cash) .. ")"
end)

command("click", "/click [poziom]", "ustaw Click Multiplier (0–150)", function(_, data, args)
	data.ClickLevel = needLevel(args[1], Loop.MaxLevel.Click)
	return string.format(
		"Click Multiplier: poziom %d (%s LP za klik przed bonusami)",
		data.ClickLevel,
		Format.number(Formulas.clickValue(data.ClickLevel))
	)
end)

command("bag", "/bag [poziom]", "ustaw poziom Bag (0–35)", function(_, data, args)
	data.BagLevel = needLevel(args[1], Loop.MaxLevel.Bag)
	return string.format("Bag: poziom %d (%s LP)", data.BagLevel, Format.number(Formulas.bagCapacity(data.BagLevel, false)))
end)

command("max", "/max", "wszystko na maksa: strefy 1–5, Click, Bag i najlepsze auto, jacht i odrzutowiec (L$ bez zmian)", function(_, data)
	data.ZonesUnlocked = #Economy.Zones
	data.ClickLevel = Loop.MaxLevel.Click
	data.BagLevel = Loop.MaxLevel.Bag
	if data.ActivityTiers == nil then
		data.ActivityTiers = {}
	end
	for _, kind in ipairs(Loop.ActivityKinds) do
		local tiers = Economy.Activities[kind].Tiers
		if tiers ~= nil then
			data.ActivityTiers[kind] = #tiers
		end
	end
	return string.format(
		"Na maksa: strefy 1–%d, Click Lv %d, Bag Lv %d, auto %d, jacht %d, odrzutowiec %d",
		data.ZonesUnlocked,
		data.ClickLevel,
		data.BagLevel,
		Loop.activityTier(data, "Car"),
		Loop.activityTier(data, "Yacht"),
		Loop.activityTier(data, "Jet")
	)
end)

local function needZone(arg)
	local n = math.floor(needNumber(arg))
	if Economy.Zones[n] == nil then
		error(string.format("podaj strefę od 1 do %d", #Economy.Zones), 0)
	end
	return n
end

command("zone", "/zone [1–5]", "ustaw ostatnią kupioną strefę (1 = tylko start)", function(_, data, args)
	data.ZonesUnlocked = needZone(args[1])
	return string.format("Kupione strefy: 1–%d (ostatnia: %s)", data.ZonesUnlocked, Economy.Zones[data.ZonesUnlocked].Name)
end)

command("tp", "/tp [1–5|sell]", "teleport do strefy albo na pole Sell (mnożnik działa tylko w kupionej strefie)", function(player, _, args)
	if string.lower(args[1] or "") == "sell" then
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local position = root and LoopService.sellPadPosition(root.Position)
		if position == nil then
			error("nie ma pola Sell albo nie masz postaci", 0)
		end
		character:PivotTo(CFrame.new(position))
		return "Teleport: pole Sell"
	end
	local n = needZone(args[1])
	if not ZoneService.teleport(player, n) then
		error("ta strefa nie ma części na mapie albo nie masz postaci", 0)
	end
	return string.format("Teleport: strefa %d (%s)", n, Economy.Zones[n].Name)
end)

command("speed", "/speed [ile]", "prędkość chodzenia, np. /speed 60 (16 = normalnie, po odrodzeniu wraca)", function(player, _, args)
	local n = needNumber(args[1])
	if n < 0 or n > 300 then
		error("podaj liczbę od 0 do 300", 0)
	end
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid == nil then
		error("nie masz postaci", 0)
	end
	humanoid.WalkSpeed = n
	return "Prędkość: " .. Format.small(n) .. " (normalnie " .. tostring(Economy.WalkSpeed) .. ")"
end)

command("time", "/time [0–24]", "pora dnia dla wszystkich, np. /time 14 (dzień) albo /time 0 (noc)", function(_, _, args)
	local hour = needNumber(args[1])
	if hour < 0 or hour > 24 then
		error("podaj godzinę od 0 do 24", 0)
	end
	Lighting.ClockTime = hour
	return "Godzina: " .. Format.small(hour)
end)

-- Jajko, z którego pet tej rzadkości mógł wypaść: A, potem B, a gdy nie ma go w żadnym (Mythic),
-- premium (P). Od jajka zależy cena sprzedaży i opłata za łączenie.
local function eggFor(zone, rarity)
	for _, egg in ipairs({ "A", "B" }) do
		local info = Loop.eggInfo(zone, egg)
		if info ~= nil and info.Odds[rarity] ~= nil then
			return egg
		end
	end
	return "P"
end

local function givePet(data, zone, rarity, level)
	local id = tostring(data.NextPetId)
	data.NextPetId = data.NextPetId + 1
	data.Pets[id] = { Zone = zone, Rarity = rarity, Level = level or 0, Egg = eggFor(zone, rarity) }
	Loop.addToIndex(data, zone, rarity)
	return id
end

local function needRarity(arg)
	local wanted = string.lower(arg or "")
	for _, name in ipairs(Economy.Pets.RarityOrder) do
		if string.lower(name) == wanted then
			return name
		end
	end
	error("rzadkości: " .. table.concat(Economy.Pets.RarityOrder, ", "), 0)
end

local LEVEL_WORDS = { normal = 0, gold = 1, golden = 1, diamond = 2 }

local function needRoom(data, count)
	if Loop.petCount(data) + count > PetsConfig.MaxInventory then
		error(string.format("nie zmieści się %d petów (najwyżej %d w ekwipunku)", count, PetsConfig.MaxInventory), 0)
	end
end

command(
	"pet",
	"/pet [rzadkość|all] [strefa] [ile] [gold|diamond]",
	"daj peta, np. /pet Rare 1 5 (5 sztuk do łączenia), /pet Epic 2 1 gold; /pet all 3 = po jednym z każdej rzadkości",
	function(_, data, args)
		local zone = 1
		if args[2] ~= nil then
			zone = needZone(args[2])
		end
		local count = 1
		local level = 0
		for i = 3, #args do
			local word = string.lower(args[i])
			if LEVEL_WORDS[word] ~= nil then
				level = LEVEL_WORDS[word]
			else
				count = math.floor(needNumber(args[i]))
				if count < 1 or count > PetsConfig.MaxInventory then
					error(string.format("podaj od 1 do %d sztuk", PetsConfig.MaxInventory), 0)
				end
			end
		end
		if string.lower(args[1] or "") == "all" then
			local order = Economy.Pets.RarityOrder
			needRoom(data, #order)
			for _, rarity in ipairs(order) do
				givePet(data, zone, rarity, level)
			end
			return string.format("Nowe pety: po jednym z każdej rzadkości ze strefy %d (%d). Załóż je w oknie PETS.", zone, #order)
		end
		local rarity = needRarity(args[1])
		needRoom(data, count)
		for _ = 1, count do
			givePet(data, zone, rarity, level)
		end
		return string.format(
			"Nowy pet: %s × %d (%s, strefa %d, +%s%% L$ każdy). Wyposaż go w oknie PETS.",
			PetsConfig.fullName(zone, rarity, level),
			count,
			rarity,
			zone,
			Format.small(Formulas.petPower(zone, rarity, level) * 100)
		)
	end
)

command("secret", "/secret [strefa]", "daj sekretnego peta i ogłoś go (na wszystkich serwerach, gdy działa MessagingService)", function(player, data, args)
	local zone = 1
	if args[1] ~= nil then
		zone = needZone(args[1])
	end
	needRoom(data, 1)
	local id = givePet(data, zone, "Secret", 0)
	data.Stats.SecretsHatched = (data.Stats.SecretsHatched or 0) + 1
	PetService.announceSecret(player, data.Pets[id])
	return string.format("Sekret: %s (strefa %d). Komunikat poszedł do wszystkich graczy.", PetsConfig.name(zone, "Secret"), zone)
end)

command("mergeluck", "/mergeluck [0–5]", "ustaw ulepszenie Merge Luck z Aury (+1 pkt proc. na peta przy łączeniu)", function(_, data, args)
	local max = #Economy.Aura.Upgrades.MergeLuck.Costs
	data.AuraUpgrades.MergeLuck = needLevel(args[1], max)
	return string.format(
		"Merge Luck: poziom %d (1 pet = %s, 4 pety = %s)",
		data.AuraUpgrades.MergeLuck,
		Format.percent(Formulas.mergeChance(1, data.AuraUpgrades.MergeLuck)),
		Format.percent(Formulas.mergeChance(4, data.AuraUpgrades.MergeLuck))
	)
end)

command("clearpets", "/clearpets", "usuń wszystkie pety (indeks zostaje)", function(_, data)
	local n = Loop.petCount(data)
	data.Pets = {}
	data.Equipped = {}
	return string.format("Usunięte pety: %d", n)
end)

command("clearindex", "/clearindex", "wyczyść indeks petów (znów pokażą się napisy NEW!)", function(_, data)
	data.Index = {}
	Loop.backfillIndex(data)
	return string.format("Indeks: %d/%d (zostały pety, które masz)", Loop.indexCount(data), Loop.indexTotal())
end)

local function needCategory(arg)
	local wanted = string.lower(arg or "")
	for _, name in ipairs(Clothes.Categories) do
		if string.lower(name) == wanted then
			return name
		end
	end
	error("kategorie: " .. table.concat(Clothes.Categories, ", "), 0)
end

-- Rzadkości ubrań: jak u petów, tylko bez Secret, a na końcu UltraSecret (można wpisać „ultra”).
local function needClothRarity(arg)
	local wanted = string.lower(arg or "")
	if wanted == "ultra" then
		wanted = "ultrasecret"
	end
	for _, name in ipairs(Economy.Clothes.RarityOrder) do
		if string.lower(name) == wanted then
			return name
		end
	end
	error("rzadkości ubrań: " .. table.concat(Economy.Clothes.RarityOrder, ", ") .. " (albo ultra)", 0)
end

command(
	"cloth",
	"/cloth [kategoria|all] [rzadkość] [ile] [gold|diamond]",
	"daj ubranie, np. /cloth Chain Rare 5 (5 do łączenia), /cloth Hair Mythic 1 gold, /cloth Shirt ultra; /cloth all Epic = po jednym z każdej kategorii",
	function(_, data, args)
		local categories = Clothes.Categories
		if string.lower(args[1] or "") ~= "all" then
			categories = { needCategory(args[1]) }
		end
		local rarity = "Common"
		if args[2] ~= nil then
			rarity = needClothRarity(args[2])
		end
		local count = 1
		local level = 0
		for i = 3, #args do
			local word = string.lower(args[i])
			if LEVEL_WORDS[word] ~= nil then
				level = LEVEL_WORDS[word]
			else
				count = math.floor(needNumber(args[i]))
				if count < 1 or count > ClothesConfig.MaxInventory then
					error(string.format("podaj od 1 do %d sztuk", ClothesConfig.MaxInventory), 0)
				end
			end
		end
		if Clothes.count(data) + count * #categories > ClothesConfig.MaxInventory then
			error(string.format("nie zmieści się (najwyżej %d ubrań)", ClothesConfig.MaxInventory), 0)
		end
		for _, category in ipairs(categories) do
			for _ = 1, count do
				ClothesService.give(data, category, rarity, level)
			end
		end
		return string.format(
			"Nowe ubrania: %s × %d (%s, +%s%% LP każde). Załóż je w oknie CLOTHES (WEAR BEST).",
			#categories == 1 and ClothesConfig.fullName(categories[1], rarity, level) or (rarity .. " z każdej kategorii"),
			count,
			rarity,
			Format.small(Formulas.clothBonus(rarity, level) * 100)
		)
	end
)

command("ultra", "/ultra [kategoria]", "daj ubranie Ultra Secret (chrome) i ogłoś je (na wszystkich serwerach, gdy działa MessagingService), np. /ultra Shirt", function(player, data, args)
	local category = "Shirt"
	if args[1] ~= nil then
		category = needCategory(args[1])
	end
	if Clothes.count(data) + 1 > ClothesConfig.MaxInventory then
		error(string.format("nie zmieści się (najwyżej %d ubrań)", ClothesConfig.MaxInventory), 0)
	end
	ClothesService.give(data, category, "UltraSecret", 0)
	data.Stats.UltraSecrets = (data.Stats.UltraSecrets or 0) + 1
	PetService.announceSecret(player, { Category = category, Level = 0 })
	return string.format(
		"Ultra Secret: %s (+%s%% LP). Komunikat poszedł do wszystkich graczy.",
		ClothesConfig.name(category, "UltraSecret"),
		Format.small(Formulas.clothBonus("UltraSecret", 0) * 100)
	)
end)

command("nextbox", "/nextbox [rzadkość|off]", "następny box da tę rzadkość (przy Buy 3 pierwszy z trzech), np. /nextbox ultra, żeby zobaczyć animację", function(player, _, args)
	if string.lower(args[1] or "") == "off" then
		ClothesService.forceNext(player, nil)
		return "Następny box znów losuje."
	end
	local rarity = needClothRarity(args[1])
	ClothesService.forceNext(player, rarity)
	return string.format("Następny box da %s. Kup go przy stoisku (L$ normalnie schodzą).", rarity)
end)

command("clearclothes", "/clearclothes", "usuń wszystkie ubrania", function(_, data)
	local n = Clothes.count(data)
	data.Clothes = {}
	data.Worn = {}
	return string.format("Usunięte ubrania: %d", n)
end)

command("odds", "/odds [ile] [strefa] [A|B]", "losuje jajka na próbę (bez L$ i bez petów), np. /odds 10000 1 B", function(_, data, args)
	local count = 1000
	if args[1] ~= nil then
		count = math.floor(needNumber(args[1]))
	end
	if count < 1 or count > 100000 then
		error("podaj od 1 do 100000 jajek", 0)
	end
	local zone = 1
	if args[2] ~= nil then
		zone = needZone(args[2])
	end
	local egg = string.upper(args[3] or "A")
	local info = Loop.eggInfo(zone, egg)
	if info == nil then
		error("jajko A (zwykłe) albo B (złote)", 0)
	end
	local luck = 1
	if info.LuckApplies ~= false then
		luck = Formulas.luck(data.AuraUpgrades.Luck)
	end
	local counts = {}
	for _ = 1, count do
		local rarity = Formulas.roll(info.Odds, luck, math.random)
		counts[rarity] = (counts[rarity] or 0) + 1
	end
	local parts = {}
	for _, rarity in ipairs(Economy.Pets.RarityOrder) do
		if counts[rarity] ~= nil then
			table.insert(parts, string.format("%s %d (%s)", rarity, counts[rarity], Format.percent(counts[rarity] / count)))
		end
	end
	return string.format(
		"%s × %d, szczęście ×%s: %s",
		string.format(PetsConfig.EggNames[egg] or "%s Egg", Economy.Zones[zone].Name),
		count,
		tostring(math.floor(luck * 100 + 0.5) / 100),
		table.concat(parts, ", ")
	)
end)

command("luck", "/luck [poziom]", "ustaw ulepszenie Luck z Aury (szczęście w jajkach), np. /luck 20", function(_, data, args)
	data.AuraUpgrades.Luck = needLevel(args[1], 1000)
	local luck = Formulas.luck(data.AuraUpgrades.Luck)
	return string.format(
		"Luck: poziom %d, szczęście ×%s (tyle losowań na jajko, wygrywa najrzadszy pet)",
		data.AuraUpgrades.Luck,
		tostring(math.floor(luck * 100 + 0.5) / 100)
	)
end)

command("adminluck", "/adminluck [ile|off]", "szczęście ×100 000 w jajkach i boxach (do wyjścia z gry), żeby szybko trafić sekrety; /adminluck off wyłącza", function(player, data, args)
	local word = string.lower(args[1] or "")
	if word == "off" or word == "0" or word == "1" then
		player:SetAttribute(LoopService.TestLuckAttribute, nil)
		return "Admin luck wyłączone: szczęście jak w zapisie."
	end
	local boost = 100000
	if args[1] ~= nil then
		boost = needNumber(args[1])
	end
	if boost < 1 or boost > 1e7 then
		error("podaj od 1 do 10M", 0)
	end
	player:SetAttribute(LoopService.TestLuckAttribute, boost)
	local luck = Formulas.luck(data.AuraUpgrades.Luck) * boost
	local secret = Formulas.effectiveOdds(Economy.Pets.Eggs[1].B.Odds, luck).Secret or 0
	local ultra = Formulas.effectiveOdds(Economy.Clothes.Boxes.Iced.Odds, luck, Economy.Clothes.RarityOrder).UltraSecret or 0
	return string.format(
		"Admin luck ×%s (do wyjścia z gry): sekret ze złotego jajka %s, Ultra Secret z Iced Boxa %s. /adminluck off wyłącza.",
		Format.number(boost),
		Format.percent(secret),
		Format.percent(ultra)
	)
end)

command("tier", "/tier [car|yacht|jet] [poziom]", "ustaw tier aktywności, np. /tier yacht 3 (/tier jet 0 = bez odrzutowca)", function(_, data, args)
	local wanted = string.lower(args[1] or "")
	local names = {}
	for _, kind in ipairs(Loop.ActivityKinds) do
		local tiers = Economy.Activities[kind].Tiers
		if tiers ~= nil then
			table.insert(names, string.lower(kind))
			if string.lower(kind) == wanted then
				local level = math.floor(needNumber(args[2]))
				local lowest = 1
				if tiers[1].Cost > 0 then
					lowest = 0 -- pierwszy odrzutowiec jest płatny, więc można go „nie mieć”
				end
				if level < lowest or level > #tiers then
					error(string.format("podaj poziom od %d do %d", lowest, #tiers), 0)
				end
				if data.ActivityTiers == nil then
					data.ActivityTiers = {}
				end
				data.ActivityTiers[kind] = level
				if level == 0 then
					return kind .. ": brak (trzeba kupić pierwszy)"
				end
				return string.format("%s: tier %d (%s, ×%s)", kind, level, tiers[level].WorkingName, tostring(tiers[level].Multiplier))
			end
		end
	end
	error("aktywności z tierami: " .. table.concat(names, ", "), 0)
end)

command("rebirth", "/rebirth [ile]", "ustaw liczbę Rebirthów (poziom = najwyżej 10)", function(_, data, args)
	local count = needLevel(args[1], 1000)
	data.RebirthCount = count
	data.RebirthLevel = Formulas.rebirthLevel(count)
	return string.format(
		"Rebirthy: %d, poziom %d (mnożnik LP ×%s)",
		count,
		data.RebirthLevel,
		tostring(Economy.Rebirth.LPMultiplier[data.RebirthLevel])
	)
end)

command("aura", "/aura [ile]", "ustaw Aurę", function(_, data, args)
	data.Aura = math.max(0, math.floor(needNumber(args[1])))
	return "Aura: " .. Format.number(data.Aura)
end)

command("rb", "/rb", "Rebirth od razu, bez opłaty i bez stoiska (z animacją i teleportem na spawn)", function(player, data)
	local result = Rebirth.rebirth(data, true)
	RebirthService.performed(player, data, result)
	return string.format(
		"Rebirth nr %d: poziom %d (%s), LP ×%s, +%s Aury.",
		result.Count,
		result.Level,
		result.Title,
		tostring(Economy.Rebirth.LPMultiplier[result.Level]),
		Format.number(math.floor(result.Aura + 1e-9))
	)
end)

command("aurabar", "/aurabar [minuty]", "dolicz minuty do paska Aury (10 minut = +10 Aury, działa od Rebirth 1), np. /aurabar 10", function(player, data, args)
	local minutes = 10
	if args[1] ~= nil then
		minutes = needNumber(args[1])
	end
	if minutes <= 0 or minutes > 6000 then
		error("podaj od 0,1 do 6000 minut", 0)
	end
	if not Rebirth.unlocked(data) then
		error("pasek Aury działa od Rebirth 1 (/rb)", 0)
	end
	local added, full = Rebirth.addBarTime(data, minutes * 60)
	if added > 0 then
		LoopService.notify(player, { Kind = "Aura", Amount = added, Source = "Bar" })
	end
	return string.format("Pasek Aury: +%s min, pełnych %d (+%s Aury), teraz %d s z %d.", Format.small(minutes), full, Format.number(math.floor(added + 1e-9)), math.floor(data.AuraBar), Economy.Aura.BarSeconds)
end)

command("auraup", "/auraup [ulepszenie] [poziom]", "ustaw poziom ulepszenia Aury: clickboost, luck, auragain, mergeluck (do 5), np. /auraup luck 20 albo /auraup clickboost 150 (tęczowa poświata)", function(_, data, args)
	local wanted = string.lower(args[1] or "")
	for _, key in ipairs(Rebirth.UpgradeOrder) do
		if string.lower(key) == wanted then
			local max = Rebirth.maxLevel(key) or 100000
			data.AuraUpgrades[key] = needLevel(args[2], max)
			return string.format("%s: poziom %d, Aura Level %d", key, data.AuraUpgrades[key], Rebirth.auraLevel(data))
		end
	end
	error("ulepszenia: " .. table.concat(Rebirth.UpgradeOrder, ", "), 0)
end)

-- Gamepassy z /pass zapisują się w danych gracza (TestPasses), więc są też w następnym teście.
local function setTestPass(player, data, key, on)
	GamepassService.setOverride(player, key, on)
	if type(data.TestPasses) ~= "table" then
		data.TestPasses = {}
	end
	data.TestPasses[key] = on
end

command("pass", "/pass [nazwa|all|none]", "włącz albo wyłącz gamepass (zostaje na kolejne testy, /reset czyści)", function(player, data, args)
	local wanted = string.lower(args[1] or "")
	if wanted == "all" or wanted == "none" then
		for _, key in ipairs(GamepassService.Keys) do
			setTestPass(player, data, key, wanted == "all")
		end
		return wanted == "all" and "Wszystkie gamepassy włączone." or "Wszystkie gamepassy wyłączone."
	end
	for _, key in ipairs(GamepassService.Keys) do
		if string.lower(key) == wanted then
			local on = not GamepassService.owns(player, key)
			setTestPass(player, data, key, on)
			return key .. (on and ": włączony" or ": wyłączony")
		end
	end
	error("nazwy: " .. table.concat(GamepassService.Keys, ", "), 0)
end)

----------------------------------------------------------------- Robux (Etap 10)
local function needProduct(arg)
	local wanted = string.lower(arg or "")
	local keys = {}
	for key in pairs(Robux.Products) do
		table.insert(keys, key)
		if string.lower(key) == wanted then
			return key
		end
	end
	table.sort(keys)
	error("produkty: " .. table.concat(keys, ", "), 0)
end

command("buy", "/buy [produkt] [strefa]", "zakup testowy produktu za Robuxy, bez płacenia (np. /buy PremiumEgg3 2, /buy StarterPack)", function(player, data, args)
	local key = needProduct(args[1])
	local zone = nil
	if args[2] ~= nil then
		zone = needZone(args[2])
	end
	ShopService.grantFor(player, data, key, { zone = zone, random01 = math.random, now = os.time(), test = true })
	return "Kupione na niby: " .. key
end)

command("boost", "/boost [lp|autosell] [minuty]", "dodaj minuty boosta (0 kasuje)", function(_, data, args)
	local kind = string.lower(args[1] or "")
	if kind == "lp" or kind == "2x" then
		kind = "LP"
	elseif kind == "autosell" or kind == "sell" then
		kind = "AutoSell"
	else
		error("boosty: lp, autosell", 0)
	end
	local minutes = needNumber(args[2] or "15")
	if minutes <= 0 then
		data.Boosts[kind] = 0
	else
		Shop.addBoost(data, kind, minutes)
	end
	return string.format("Boost %s: %s", kind, Format.duration(Shop.boostLeft(data, kind)))
end)

command("policy", "/policy [on|off|auto]", "udawaj gracza z ograniczeniem płatnych losowań (on) albo bez (off); auto = jak mówi PolicyService", function(player, _, args)
	local mode = string.lower(args[1] or "")
	if mode == "on" then
		ShopService.setPolicyOverride(player, true)
		return "Ograniczenie płatnych losowań: WŁĄCZONE (premium jajka zamienią się w zakup konkretnego peta)"
	elseif mode == "off" then
		ShopService.setPolicyOverride(player, false)
		return "Ograniczenie płatnych losowań: wyłączone (widzisz premium jajka)"
	elseif mode == "auto" then
		ShopService.setPolicyOverride(player, nil)
		return "Ograniczenie płatnych losowań: jak mówi PolicyService (" .. tostring(ShopService.isRestricted(player)) .. ")"
	end
	error("on, off albo auto", 0)
end)

command("ads", "/ads", "wyzeruj dzisiejsze reklamy za nagrodę (znowu 5)", function(_, data)
	data.Robux.AdDay = 0
	data.Robux.AdCount = 0
	return "Reklamy na dziś: " .. Shop.adsLeft(data, os.time())
end)

command("starter", "/starter", "Starter Pack znowu do kupienia (72 h od teraz)", function(_, data)
	data.Robux.StarterPack = false
	data.FirstJoin = os.time()
	return "Starter Pack: znowu w sklepie na 72 h"
end)

command("stats", "/stats", "pokaż swój zapis", function(player, data)
	return string.format(
		"L$ %s · Bag %s LP · Click Lv %d · Bag Lv %d · strefy 1–%d · auto %d, jacht %d, odrzutowiec %d (zdjęcia %d, wywiady %d, imprezy %d, loty %d) · pety %d (wyposażone %d, jajka: %d, indeks %d/%d, sprzedane %d, łączenia %d, nieudane %d, sekrety %d) · ubrania %d (założone %d, boxy %d, Ultra Secret %d, warstwa ×%s) · Rebirth %d (Lv %d) · Aura %s · kliknięcia %d · sprzedaże %d · czas gry %s",
		Format.number(data.Cash),
		Format.number(data.Bag),
		data.ClickLevel,
		data.BagLevel,
		data.ZonesUnlocked,
		Loop.activityTier(data, "Car"),
		Loop.activityTier(data, "Yacht"),
		Loop.activityTier(data, "Jet"),
		data.Stats.CarPhotos or 0,
		data.Stats.Interviews or 0,
		data.Stats.YachtParties or 0,
		data.Stats.JetFlights or 0,
		Loop.petCount(data),
		#data.Equipped,
		data.Stats.EggsOpened or 0,
		Loop.indexCount(data),
		Loop.indexTotal(),
		data.Stats.PetsSold or 0,
		data.Stats.Merges or 0,
		data.Stats.MergesFailed or 0,
		data.Stats.SecretsHatched or 0,
		Clothes.count(data),
		#data.Worn,
		data.Stats.BoxesOpened or 0,
		data.Stats.UltraSecrets or 0,
		Format.small(Clothes.layer(data, LoopService.contextFor(player))),
		data.RebirthCount,
		data.RebirthLevel,
		Format.number(data.Aura),
		data.Stats.Clicks,
		data.Stats.Sells,
		Format.duration(data.Stats.PlaySeconds)
	)
end)

command("reset", "/reset", "wyczyść swój zapis (jak nowy gracz)", function(player)
	DataService.reset(player)
	GamepassService.clearOverrides(player)
	return "Zapis wyczyszczony. Grasz jak nowy gracz."
end)

local function reply(player, text)
	Net.event("Notify"):FireClient(player, { Kind = "Admin", Text = text })
end

local function onAdminMessage(player, text)
	if type(text) ~= "string" or #text > 200 then
		return
	end
	if not AdminService.isAdmin(player) then
		return
	end
	local data = DataService.get(player)
	if data == nil then
		reply(player, "Zapis jeszcze się wczytuje, spróbuj za chwilę.")
		return
	end
	local words = {}
	for word in string.gmatch(text, "%S+") do
		table.insert(words, word)
	end
	local name = string.lower(string.sub(words[1] or "", 2))
	local cmd = COMMANDS[name]
	if cmd == nil then
		reply(player, "Nie znam tej komendy. Wpisz /cmds.")
		return
	end
	local args = {}
	for i = 2, #words do
		table.insert(args, words[i])
	end
	local ok, result = pcall(cmd.fn, player, data, args)
	if ok then
		if result ~= nil then
			reply(player, result)
		end
		LoopService.markDirty(player)
	else
		reply(player, cmd.usage .. ": " .. tostring(result))
	end
end

function AdminService.start()
	DataService.onLoaded(function(player, data)
		local isAdmin = checkAdmin(player)
		adminCache[player] = isAdmin
		if isAdmin then
			-- gamepassy z poprzedniego testu (tylko u adminów: zwykły gracz nic z nich nie ma)
			if type(data) == "table" and type(data.TestPasses) == "table" then
				for _, key in ipairs(GamepassService.Keys) do
					if data.TestPasses[key] ~= nil then
						GamepassService.setOverride(player, key, data.TestPasses[key] == true)
					end
				end
			end
			Net.event("Notify"):FireClient(player, { Kind = "AdminCommands", Commands = ORDER })
			LoopService.markDirty(player)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		adminCache[player] = nil
	end)
	LoopService.addViewHook(function(player, view)
		view.IsAdmin = adminCache[player] == true
	end)
	-- zakupy „na niby” w sklepie (produkty i gamepassy bez ID) tylko dla testera
	ShopService.isTester = AdminService.isAdmin
	ShopService.setTestPass = function(player, key, on)
		local data = DataService.get(player)
		if data ~= nil then
			setTestPass(player, data, key, on)
		end
	end
	Net.event("Admin").OnServerEvent:Connect(onAdminMessage)
end

return AdminService
