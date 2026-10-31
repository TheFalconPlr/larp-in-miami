-- Tryb testowy: komendy na czacie (/cmds). W Studio działają zawsze, a w opublikowanej grze tylko
-- dla właściciela grupy i osób z Settings.Admin.UserIds (i tylko gdy AllowInLive = true).
-- Komendy tworzy klient (TextChatCommand), a serwer sprawdza uprawnienia i wykonuje.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared.Config.Economy)
local Settings = require(Shared.Config.Settings)
local Format = require(Shared.Format)
local Formulas = require(Shared.Formulas)
local Loop = require(Shared.Logic.Loop)
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)
local GamepassService = require(script.Parent.GamepassService)
local LoopService = require(script.Parent.LoopService)

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

command("pass", "/pass [nazwa|all|none]", "włącz albo wyłącz gamepass do końca testu", function(player, _, args)
	local wanted = string.lower(args[1] or "")
	if wanted == "all" or wanted == "none" then
		for _, key in ipairs(GamepassService.Keys) do
			GamepassService.setOverride(player, key, wanted == "all")
		end
		return wanted == "all" and "Wszystkie gamepassy włączone." or "Wszystkie gamepassy wyłączone."
	end
	for _, key in ipairs(GamepassService.Keys) do
		if string.lower(key) == wanted then
			local on = not GamepassService.owns(player, key)
			GamepassService.setOverride(player, key, on)
			return key .. (on and ": włączony" or ": wyłączony")
		end
	end
	error("nazwy: " .. table.concat(GamepassService.Keys, ", "), 0)
end)

command("stats", "/stats", "pokaż swój zapis", function(_, data)
	return string.format(
		"L$ %s · Bag %s LP · Click Lv %d · Bag Lv %d · Rebirth %d (Lv %d) · Aura %s · kliknięcia %d · sprzedaże %d · czas gry %s",
		Format.number(data.Cash),
		Format.number(data.Bag),
		data.ClickLevel,
		data.BagLevel,
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
	DataService.onLoaded(function(player)
		local isAdmin = checkAdmin(player)
		adminCache[player] = isAdmin
		if isAdmin then
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
