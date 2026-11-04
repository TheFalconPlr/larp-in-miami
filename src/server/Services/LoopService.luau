-- Rdzeń pętli na serwerze: klik z limitem, Auto-Click, Bag, pole Sell, darmowy teleport na Sell,
-- ulepszenia i strefy za L$, leaderstats i wysyłanie stanu do gracza. Liczby liczy Shared/Logic/Loop,
-- a to, w której strefie gracz stoi, ZoneService. Serwer sprawdza każde żądanie; klient tylko prosi
-- i pokazuje.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared.Config.Economy)
local Settings = require(Shared.Config.Settings)
local Format = require(Shared.Format)
local Loop = require(Shared.Logic.Loop)
local Clothes = require(Shared.Logic.Clothes)
local RateLimiter = require(Shared.Logic.RateLimiter)
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)
local GamepassService = require(script.Parent.GamepassService)
local ZoneService = require(script.Parent.ZoneService)

local LoopService = {}
LoopService.TestLuckAttribute = "LarpTestLuck" -- /adminluck: mnożnik szczęścia (atrybut gracza)

local sessions = {} -- [player] = stan sesji (limit kliknięć, Auto-Click, teleport, leaderstats)
local viewHooks = {}
local busyChecks = {}
local pads = {} -- lista pól Sell
local hookedPads = {}

----------------------------------------------------------------- Pomocnicze
-- Kontekst do obliczeń z Shared/Logic/Loop. Kolejne etapy dopiszą tu bonusy i boosty.
local function contextFor(player)
	local zone = 1
	local data = DataService.get(player)
	if data ~= nil then
		-- strefa, w której gracz stoi, ale najwyżej ostatnia kupiona
		zone = Loop.effectiveZone(data, ZoneService.standing(player))
	end
	local ctx = {
		zone = zone,
		passes = GamepassService.passes(player),
		inGroup = false, -- Etap 10: bonus za grupę
		friends = 0, -- Etap 10: bonus za znajomych
		boost = false, -- Etap 9: boost 2x LP
		petLayer = 1,
		clothLayer = 1,
	}
	if data ~= nil then
		ctx.petLayer = Loop.petLayer(data, ctx) -- wyposażone pety mnożą L$ przy Sell
		ctx.clothLayer = Clothes.layer(data, ctx) -- założone ubrania mnożą LP (klik i aktywności)
	end
	-- tryb testowy: /adminluck mnoży szczęście w jajkach i boxach (atrybut gracza, tylko do wyjścia)
	local boost = player:GetAttribute(LoopService.TestLuckAttribute)
	if type(boost) == "number" and boost > 1 then
		ctx.luckBoost = boost
	end
	return ctx
end
LoopService.contextFor = contextFor

function LoopService.markDirty(player)
	local s = sessions[player]
	if s ~= nil then
		s.dirty = true
	end
end

-- fn(player, view) może dopisać pola do stanu wysyłanego graczowi (np. IsAdmin).
function LoopService.addViewHook(fn)
	table.insert(viewHooks, fn)
end

-- fn(player) zwraca true, gdy gracz jest zajęty (np. w aktywności): wtedy kliknięcia, Auto-Click
-- i teleport na Sell się nie liczą.
function LoopService.addBusyCheck(fn)
	table.insert(busyChecks, fn)
end

local function isBusy(player)
	for _, check in ipairs(busyChecks) do
		if check(player) then
			return true
		end
	end
	return false
end

local function notify(player, payload)
	Net.event("Notify"):FireClient(player, payload)
end
LoopService.notify = notify

----------------------------------------------------------------- leaderstats
local function makeLeaderstats(player)
	local old = player:FindFirstChild("leaderstats")
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "leaderstats"
	local cash = Instance.new("StringValue")
	cash.Name = "L$"
	cash.Parent = folder
	local rebirths = Instance.new("IntValue")
	rebirths.Name = "Rebirths"
	rebirths.Parent = folder
	folder.Parent = player
	return { cash = cash, rebirths = rebirths }
end

local function updateLeaderstats(s, data)
	local cashText = Format.number(data.Cash)
	if s.stats.cash.Value ~= cashText then
		s.stats.cash.Value = cashText
	end
	if s.stats.rebirths.Value ~= data.RebirthCount then
		s.stats.rebirths.Value = data.RebirthCount
	end
end

----------------------------------------------------------------- Stan dla gracza
local function flush(player, s)
	local data = DataService.get(player)
	if data == nil then
		return
	end
	s.dirty = false
	local ctx = contextFor(player)
	local view = Loop.view(data, ctx)
	view.Passes = ctx.passes
	view.Settings = {
		AutoClick = data.Settings.AutoClick ~= false,
		AutoSell = data.Settings.AutoSell ~= false,
		ShowClothes = data.Settings.ShowClothes ~= false,
		HideMenu = data.Settings.HideMenu == true,
	}
	for _, hook in ipairs(viewHooks) do
		hook(player, view)
	end
	Net.event("Sync"):FireClient(player, view)
	updateLeaderstats(s, data)
end

----------------------------------------------------------------- Klik
-- count kliknięć naraz (paczka od klienta albo Auto-Click). Limit serwera decyduje, ile się liczy.
local function doClicks(player, s, count)
	local data = DataService.get(player)
	if data == nil or isBusy(player) then
		return
	end
	local granted = s.limiter:take(os.clock(), count)
	if granted < 1 then
		return
	end
	local ctx = contextFor(player)
	local soldTotal = 0
	for _ = 1, granted do
		local added, sold = Loop.click(data, ctx)
		if added > 0 or sold > 0 then
			s.dirty = true
		end
		soldTotal = soldTotal + sold
		if added <= 0 and sold <= 0 then
			break -- pełny Bag bez Auto-Sell: kolejne kliknięcia też nic nie dadzą
		end
	end
	if soldTotal > 0 then
		notify(player, { Kind = "Sold", Cash = soldTotal, Auto = true })
	end
end

----------------------------------------------------------------- Sell
local function sellFor(player, s)
	local data = DataService.get(player)
	if data == nil or data.Bag <= 0 then
		return 0
	end
	local lp = data.Bag
	local gained = Loop.sell(data, contextFor(player))
	s.dirty = true
	notify(player, { Kind = "Sold", LP = lp, Cash = gained })
	return gained
end

local function playerFromHit(hit)
	local character = hit:FindFirstAncestorOfClass("Model")
	if character == nil then
		return nil
	end
	return Players:GetPlayerFromCharacter(character)
end

local function hookPad(pad)
	if hookedPads[pad] then
		return
	end
	hookedPads[pad] = true
	table.insert(pads, pad)
	pad.Touched:Connect(function(hit)
		local player = playerFromHit(hit)
		local s = player and sessions[player]
		if s == nil then
			return
		end
		local now = os.clock()
		if now - s.lastPadSell < Settings.Sell.TouchCooldown then
			return
		end
		s.lastPadSell = now
		sellFor(player, s)
	end)
end

-- Tymczasowe pole Sell obok spawnu, dopóki na mapie nie ma prawdziwego (tag lub nazwa „SellPad”).
local function createPlaceholderPad()
	local spawnPart = Workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	local base = Vector3.new(0, 0, 0)
	local groundY = 0
	if spawnPart ~= nil then
		base = spawnPart.Position
		groundY = spawnPart.Position.Y - spawnPart.Size.Y / 2
	end
	local pad = Instance.new("Part")
	pad.Name = Settings.Sell.PadTag
	pad.Anchored = true
	pad.Size = Vector3.new(12, 0.4, 12)
	pad.Position = Vector3.new(base.X, groundY + 0.2, base.Z - 24)
	pad.Material = Enum.Material.Neon
	pad.Color = Color3.fromRGB(46, 204, 113)
	pad.TopSurface = Enum.SurfaceType.Smooth
	pad.BottomSurface = Enum.SurfaceType.Smooth

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.new(8, 0, 2.5, 0)
	billboard.StudsOffset = Vector3.new(0, 4, 0)
	billboard.MaxDistance = 200
	billboard.Parent = pad
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text = "SELL"
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.2
	label.Parent = billboard

	CollectionService:AddTag(pad, Settings.Sell.PadTag)
	pad.Parent = Workspace
	print("[Pętla] Na mapie nie ma pola Sell, więc stoi tymczasowe obok spawnu (zielone).")
	return pad
end

local function setupPads()
	local tag = Settings.Sell.PadTag
	for _, inst in ipairs(CollectionService:GetTagged(tag)) do
		if inst:IsA("BasePart") then
			hookPad(inst)
		end
	end
	for _, inst in ipairs(Workspace:GetDescendants()) do
		if inst.Name == tag and inst:IsA("BasePart") then
			hookPad(inst)
		end
	end
	if #pads == 0 then
		hookPad(createPlaceholderPad())
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(function(inst)
		if inst:IsA("BasePart") then
			hookPad(inst)
		end
	end)
end

local function nearestPad(position)
	local best, bestDist = nil, math.huge
	for _, pad in ipairs(pads) do
		if pad.Parent ~= nil then
			local dist = (pad.Position - position).Magnitude
			if dist < bestDist then
				best, bestDist = pad, dist
			end
		end
	end
	return best
end

local function teleportToSell(player)
	local s = sessions[player]
	if s == nil or isBusy(player) then
		return
	end
	local now = os.clock()
	if now - s.lastTeleport < Settings.Sell.TeleportCooldown then
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if humanoid == nil or root == nil or humanoid.Health <= 0 then
		return
	end
	local pad = nearestPad(root.Position)
	if pad == nil then
		return
	end
	s.lastTeleport = now
	local offset = Vector3.new(math.random(-20, 20) / 10, pad.Size.Y / 2 + 3, math.random(-20, 20) / 10)
	character:PivotTo(CFrame.new(pad.Position + offset))
	s.lastPadSell = now
	sellFor(player, s)
end

-- Dla trybu testowego: /sell sprzedaje od razu, /tp sell przenosi nad najbliższe pole Sell.
function LoopService.sellNow(player)
	local s = sessions[player]
	if s == nil then
		return 0
	end
	return sellFor(player, s)
end

-- Pierwsze pole Sell (np. żeby postawić obok niego sklep Aury) albo nil.
function LoopService.firstSellPad()
	for _, pad in ipairs(pads) do
		if pad.Parent ~= nil then
			return pad
		end
	end
	return nil
end

function LoopService.sellPadPosition(position)
	local pad = nearestPad(position)
	if pad == nil then
		return nil
	end
	return pad.Position + Vector3.new(0, pad.Size.Y / 2 + 3, 0)
end

----------------------------------------------------------------- Ulepszenia
local function buyUpgrade(player, kind, mode)
	if (kind ~= "Click" and kind ~= "Bag") or (mode ~= "One" and mode ~= "Max") then
		return { Ok = false, Reason = "BadRequest" }
	end
	local data = DataService.get(player)
	if data == nil then
		return { Ok = false, Reason = "NotLoaded" }
	end
	if Loop.nextCost(data, kind) == nil then
		return { Ok = false, Reason = "MaxLevel" }
	end
	local limit = 1
	if mode == "Max" then
		limit = nil
	end
	local bought, spent = Loop.buy(data, kind, limit)
	if bought == 0 then
		return { Ok = false, Reason = "NotEnough" }
	end
	LoopService.markDirty(player)
	local level = data.ClickLevel
	if kind == "Bag" then
		level = data.BagLevel
	end
	return { Ok = true, Bought = bought, Spent = spent, Level = level }
end

-- Kupno strefy (tylko następnej po kolei). Bramkę otwiera potem klient, gdy dostanie nowy stan.
local function buyZone(player, id)
	if type(id) ~= "number" then
		return { Ok = false, Reason = "BadRequest" }
	end
	local data = DataService.get(player)
	if data == nil then
		return { Ok = false, Reason = "NotLoaded" }
	end
	local ok, reason = Loop.buyZone(data, id)
	if not ok then
		return { Ok = false, Reason = reason }
	end
	LoopService.markDirty(player)
	return { Ok = true, Zone = id }
end

local SETTINGS = { AutoClick = true, AutoSell = true, ShowClothes = true, HideMenu = true }

local function setSetting(player, key, value)
	if type(key) ~= "string" or not SETTINGS[key] or type(value) ~= "boolean" then
		return
	end
	local data = DataService.get(player)
	if data == nil then
		return
	end
	data.Settings[key] = value
	LoopService.markDirty(player)
end

----------------------------------------------------------------- Pętla serwera
local syncTimer = 0

local function onHeartbeat(dt)
	local autoRate = Economy.Robux.Gamepasses.AutoClick.ClicksPerSecond
	for player, s in pairs(sessions) do
		local data = DataService.get(player)
		if data ~= nil then
			s.playTimer = s.playTimer + dt
			if s.playTimer >= 1 then
				local whole = math.floor(s.playTimer)
				data.Stats.PlaySeconds = data.Stats.PlaySeconds + whole
				s.playTimer = s.playTimer - whole
			end
			if GamepassService.owns(player, "AutoClick") and data.Settings.AutoClick ~= false then
				s.autoTimer = s.autoTimer + dt * autoRate
				if s.autoTimer >= 1 then
					local whole = math.floor(s.autoTimer)
					s.autoTimer = s.autoTimer - whole
					doClicks(player, s, whole)
				end
			else
				s.autoTimer = 0
			end
		end
	end
	syncTimer = syncTimer + dt
	if syncTimer >= Settings.SyncInterval then
		syncTimer = 0
		for player, s in pairs(sessions) do
			if s.dirty then
				flush(player, s)
			end
		end
	end
end

function LoopService.start()
	DataService.onLoaded(function(player)
		sessions[player] = {
			limiter = RateLimiter.new(Settings.Click.MaxPerSecond, Settings.Click.Burst),
			autoTimer = 0,
			playTimer = 0,
			dirty = true,
			lastTeleport = -math.huge,
			lastPadSell = -math.huge,
			stats = makeLeaderstats(player),
		}
	end)
	Players.PlayerRemoving:Connect(function(player)
		sessions[player] = nil
	end)
	GamepassService.onChanged(function(player)
		LoopService.markDirty(player)
	end)
	-- inna strefa = inny mnożnik LP, więc HUD dostaje nowy stan
	ZoneService.onChanged(function(player)
		LoopService.markDirty(player)
	end)

	Net.event("Click").OnServerEvent:Connect(function(player, count)
		local s = sessions[player]
		if s == nil then
			return
		end
		if type(count) ~= "number" or count ~= count then
			count = 1
		end
		count = math.min(math.floor(count), Settings.Click.MaxBatch)
		if count >= 1 then
			doClicks(player, s, count)
		end
	end)
	Net.event("TeleportToSell").OnServerEvent:Connect(teleportToSell)
	Net.event("SetSetting").OnServerEvent:Connect(setSetting)
	Net.func("BuyUpgrade").OnServerInvoke = buyUpgrade
	Net.func("BuyZone").OnServerInvoke = buyZone

	setupPads()
	RunService.Heartbeat:Connect(onHeartbeat)
end

return LoopService
