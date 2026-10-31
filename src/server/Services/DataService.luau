-- Zapis danych gracza przez ProfileStore: blokada sesji (dane nie dublują się między serwerami),
-- autozapis co 5 minut, zapis przy wyjściu i przy wyłączeniu serwera.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Settings = require(Shared.Config.Settings)
local Template = require(Shared.Data.Template)
local ProfileStore = require(script.Parent.Parent.Vendor.ProfileStore)

local DataService = {}

local store = nil
local profiles = {} -- [player] = profile
local loadedCallbacks = {}
local warnedNoAccess = false

local function deepCopy(t)
	local c = {}
	for k, v in pairs(t) do
		if type(v) == "table" then
			c[k] = deepCopy(v)
		else
			c[k] = v
		end
	end
	return c
end

-- Migracje zapisu: [nowa wersja] = function(data). Na razie jest tylko wersja 1.
local MIGRATIONS = {}

local function migrate(data)
	local version = data.Version or 1
	while MIGRATIONS[version + 1] do
		MIGRATIONS[version + 1](data)
		version = version + 1
	end
	data.Version = math.max(version, Template.Version)
end

-- fn(player, data) wywołuje się, gdy zapis gracza jest gotowy.
function DataService.onLoaded(fn)
	table.insert(loadedCallbacks, fn)
end

-- Aktualne dane gracza albo nil, gdy jeszcze się wczytują. Nie trzymaj tej tabeli na dłużej:
-- po /reset gracz dostaje nową, więc zawsze pobieraj ją od nowa.
function DataService.get(player)
	local profile = profiles[player]
	if profile ~= nil and profile:IsActive() then
		return profile.Data
	end
	return nil
end

-- Zapis jak u nowego gracza (komenda /reset w trybie testowym).
function DataService.reset(player)
	local profile = profiles[player]
	if profile == nil then
		return false
	end
	local fresh = deepCopy(Template)
	fresh.FirstJoin = os.time()
	fresh.LastJoin = os.time()
	profile.Data = fresh
	return true
end

local function onPlayerAdded(player)
	local profile = store:StartSessionAsync(Settings.Data.KeyPrefix .. player.UserId, {
		Cancel = function()
			return player.Parent ~= Players
		end,
	})
	if profile == nil then
		if player.Parent == Players then
			player:Kick("Could not load your data. Please rejoin.")
		end
		return
	end

	profile:AddUserId(player.UserId)
	profile:Reconcile()
	migrate(profile.Data)

	profile.OnSessionEnd:Connect(function()
		profiles[player] = nil
		player:Kick("Your data was opened on another server. Please rejoin.")
	end)

	if player.Parent ~= Players then
		profile:EndSession()
		return
	end

	local data = profile.Data
	if data.FirstJoin == 0 then
		data.FirstJoin = os.time()
	end
	data.LastJoin = os.time()
	profiles[player] = profile

	print(string.format("[Dane] %s: zapis wczytany (DataStore: %s)", player.Name, tostring(ProfileStore.DataStoreState)))
	if ProfileStore.DataStoreState ~= "Access" and RunService:IsStudio() and not warnedNoAccess then
		warnedNoAccess = true
		warn(
			"[Dane] Studio nie ma dostępu do DataStore, więc postęp nie zapisze się po Stop. Włącz: "
				.. "File → Experience Settings → Security → Enable Studio Access to API Services."
		)
	end

	for _, fn in ipairs(loadedCallbacks) do
		task.spawn(fn, player, data)
	end
end

local function onPlayerRemoving(player)
	local profile = profiles[player]
	if profile ~= nil then
		profiles[player] = nil
		profile:EndSession()
	end
end

function DataService.start()
	store = ProfileStore.New(Settings.Data.StoreName, Template)
	if RunService:IsStudio() and Settings.Data.UseMockInStudio then
		store = store.Mock
	end
	ProfileStore.OnError:Connect(function(message, storeName, key)
		warn("[Dane] Błąd ProfileStore:", message, storeName, key)
	end)
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayerAdded, player)
	end
end

return DataService
