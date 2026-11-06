-- Gamepassy: kto co ma. ID są w Config/RobuxIds (0 = gamepassa jeszcze nie ma). Własność sprawdza
-- UserOwnsGamePassAsync po wejściu, po zakupie w grze i co kilka minut (gamepass kupiony w sklepie
-- Roblox albo na stronie gry). Tryb testowy (/pass) nadpisuje to tylko u adminów.

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Robux = require(Shared.Robux)

local GamepassService = {}

local REFRESH_SECONDS = 120 -- co tyle sprawdzamy gamepassy, których gracz nie ma

local owned = {} -- [player] = { [klucz] = true }
local overrides = {} -- [player] = { [klucz] = true/false } (tryb testowy)
local changedCallbacks = {}

local KEYS = {}
for key in pairs(Robux.Gamepasses) do
	table.insert(KEYS, key)
end
table.sort(KEYS)
GamepassService.Keys = KEYS

local function fireChanged(player)
	for _, fn in ipairs(changedCallbacks) do
		task.spawn(fn, player)
	end
end

-- fn(player) po każdej zmianie gamepassów gracza.
function GamepassService.onChanged(fn)
	table.insert(changedCallbacks, fn)
end

function GamepassService.owns(player, key)
	local o = overrides[player]
	if o ~= nil and o[key] ~= nil then
		return o[key]
	end
	local own = owned[player]
	return own ~= nil and own[key] == true
end

-- Tabela { [klucz] = true } z gamepassami gracza (do ctx w Shared/Logic/Loop).
function GamepassService.passes(player)
	local t = {}
	for _, key in ipairs(KEYS) do
		if GamepassService.owns(player, key) then
			t[key] = true
		end
	end
	return t
end

function GamepassService.setOverride(player, key, value)
	if overrides[player] == nil then
		overrides[player] = {}
	end
	overrides[player][key] = value
	fireChanged(player)
end

function GamepassService.clearOverrides(player)
	overrides[player] = nil
	fireChanged(player)
end

-- Sprawdza gamepassy z ID (bez tych, które gracz już ma: tych nikt nie traci).
local function refresh(player)
	local own = owned[player] or {}
	local changed = owned[player] == nil
	for _, key in ipairs(KEYS) do
		local id = Robux.passId(key)
		if id ~= nil and own[key] ~= true then
			local ok, has = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, id)
			if ok and has then
				own[key] = true
				changed = true
			end
		end
	end
	if player.Parent ~= Players then
		return
	end
	owned[player] = own
	if changed then
		fireChanged(player)
	end
end

local function markOwned(player, key)
	if owned[player] == nil then
		owned[player] = {}
	end
	if owned[player][key] ~= true then
		owned[player][key] = true
		fireChanged(player)
	end
end

function GamepassService.start()
	Players.PlayerAdded:Connect(refresh)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(refresh, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		owned[player] = nil
		overrides[player] = nil
	end)
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if not purchased then
			return
		end
		local key = Robux.passKey(passId)
		if key ~= nil then
			markOwned(player, key)
		end
	end)
	-- gamepass kupiony poza oknem z gry (sklep Roblox, strona gry): sprawdzamy co jakiś czas
	task.spawn(function()
		while true do
			task.wait(REFRESH_SECONDS)
			for _, player in ipairs(Players:GetPlayers()) do
				task.spawn(refresh, player)
			end
		end
	end)
end

return GamepassService
