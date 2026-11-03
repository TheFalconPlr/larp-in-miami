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
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)
local GamepassService = require(script.Parent.GamepassService)
local LoopService = require(script.Parent.LoopService)
local ZoneService = require(script.Parent.ZoneService)

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

command("max", "/max", "wszystko na maksa: strefy 1–5, Click, Bag i najlepsze auto (L$ bez zmian)", function(_, data)
	data.ZonesUnlocked = #Economy.Zones
	data.ClickLevel = Loop.MaxLevel.Click
	data.BagLevel = Loop.MaxLevel.Bag
	if data.ActivityTiers == nil then
		data.ActivityTiers = {}
	end
	for _, kind in ipairs(Loop.ActivityKinds) do
		data.ActivityTiers[kind] = #Economy.Activities[kind].Tiers
	end
	return string.format(
		"Na maksa: strefy 1–%d, Click Lv %d, Bag Lv %d, auto tier %d",
		data.ZonesUnlocked,
		data.ClickLevel,
		data.BagLevel,
		Loop.activityTier(data, "Car")
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

local function givePet(data, zone, rarity)
	local id = tostring(data.NextPetId)
	data.NextPetId = data.NextPetId + 1
	data.Pets[id] = { Zone = zone, Rarity = rarity, Level = 0 }
	return id
end

command("pet", "/pet [rzadkość|all] [strefa]", "daj peta, np. /pet Legendary 2; /pet all = po jednym z każdej rzadkości", function(_, data, args)
	local wanted = string.lower(args[1] or "")
	if wanted == "all" then
		local zone = 1
		if args[2] ~= nil then
			zone = needZone(args[2])
		end
		local order = Economy.Pets.RarityOrder
		if Loop.petCount(data) + #order > PetsConfig.MaxInventory then
			error(string.format("nie zmieści się %d petów (najwyżej %d)", #order, PetsConfig.MaxInventory), 0)
		end
		for _, rarity in ipairs(order) do
			givePet(data, zone, rarity)
		end
		return string.format("Nowe pety: po jednym z każdej rzadkości ze strefy %d (%d). Załóż je w oknie PETS.", zone, #order)
	end
	local rarity = nil
	for _, name in ipairs(Economy.Pets.RarityOrder) do
		if string.lower(name) == wanted then
			rarity = name
		end
	end
	if rarity == nil then
		error("rzadkości: " .. table.concat(Economy.Pets.RarityOrder, ", "), 0)
	end
	local zone = 1
	if args[2] ~= nil then
		zone = needZone(args[2])
	end
	if Loop.petCount(data) >= PetsConfig.MaxInventory then
		error(string.format("ekwipunek pełny (%d petów)", PetsConfig.MaxInventory), 0)
	end
	givePet(data, zone, rarity)
	return string.format(
		"Nowy pet: %s (%s, strefa %d, +%s%% L$). Wyposaż go w oknie PETS.",
		PetsConfig.name(zone, rarity),
		rarity,
		zone,
		Format.small(Formulas.petPower(zone, rarity, 0) * 100)
	)
end)

command("clearpets", "/clearpets", "usuń wszystkie pety", function(_, data)
	local n = Loop.petCount(data)
	data.Pets = {}
	data.Equipped = {}
	return string.format("Usunięte pety: %d", n)
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

command("tier", "/tier [car] [poziom]", "ustaw tier aktywności, np. /tier car 3", function(_, data, args)
	local wanted = string.lower(args[1] or "")
	for _, kind in ipairs(Loop.ActivityKinds) do
		if string.lower(kind) == wanted then
			local tiers = Economy.Activities[kind].Tiers
			local level = math.floor(needNumber(args[2]))
			if level < 1 or level > #tiers then
				error(string.format("podaj poziom od 1 do %d", #tiers), 0)
			end
			if data.ActivityTiers == nil then
				data.ActivityTiers = {}
			end
			data.ActivityTiers[kind] = level
			return string.format("%s: tier %d (%s, ×%s)", kind, level, tiers[level].WorkingName, tostring(tiers[level].Multiplier))
		end
	end
	local names = {}
	for _, kind in ipairs(Loop.ActivityKinds) do
		table.insert(names, string.lower(kind))
	end
	error("aktywności: " .. table.concat(names, ", "), 0)
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

command("stats", "/stats", "pokaż swój zapis", function(_, data)
	return string.format(
		"L$ %s · Bag %s LP · Click Lv %d · Bag Lv %d · strefy 1–%d · auto tier %d (zdjęcia: %d) · pety %d (wyposażone %d, jajka: %d) · Rebirth %d (Lv %d) · Aura %s · kliknięcia %d · sprzedaże %d · czas gry %s",
		Format.number(data.Cash),
		Format.number(data.Bag),
		data.ClickLevel,
		data.BagLevel,
		data.ZonesUnlocked,
		Loop.activityTier(data, "Car"),
		data.Stats.CarPhotos or 0,
		Loop.petCount(data),
		#data.Equipped,
		data.Stats.EggsOpened or 0,
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
	Net.event("Admin").OnServerEvent:Connect(onAdminMessage)
end

return AdminService
