-- Gamepassy: kto co ma. Produkty tworzymy w Etapie 6. Do tego czasu (Id = 0 w Economy) działają
-- tylko testowe przełączniki z trybu testowego (/pass), ważne do końca sesji.

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Economy = require(ReplicatedStorage:WaitForChild("Shared").Config.Economy)

local GamepassService = {}

local owned = {} -- [player] = { [klucz] = true }
local overrides = {} -- [player] = { [klucz] = true/false } (tryb testowy)
local changedCallbacks = {}

local KEYS = {}
for key in pairs(Economy.Robux.Gamepasses) do
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

local function refresh(player)
	local own = {}
	for key, info in pairs(Economy.Robux.Gamepasses) do
		if info.Id ~= 0 then
			local ok, has = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, info.Id)
			if ok and has then
				own[key] = true
			end
		end
	end
	owned[player] = own
	fireChanged(player)
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
		for key, info in pairs(Economy.Robux.Gamepasses) do
			if info.Id == passId then
				if owned[player] == nil then
					owned[player] = {}
				end
				owned[player][key] = true
				fireChanged(player)
			end
		end
	end)
end

return GamepassService
