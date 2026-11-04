-- Rebirth i Aura (Etap 9, dokument projektu): stoisko Rebirth na lotnisku, sklep Aury przy spawnie
-- obok Sell, teleport na spawn po Rebirthie, +5% szybkości chodzenia za poziom oraz tytuł i Aura
-- Level nad głową (atrybuty gracza; napisy i poświatę rysuje każdy klient). Pasek Aury dolicza
-- Loop.finishActivity (ActivityService pokazuje „+10 AURA”). Liczy wszystko Shared/Logic/Rebirth.
--
-- Jak oznaczyć stoiska w Studio:
--   Model albo część „RebirthSpot” w strefie 5 (Private Airport): tu robi się Rebirth.
--   Model albo część „AuraShop” przy spawnie, obok pola Sell: sklep Aury (otwarty od Rebirth 1).
--   Gdy któregoś nie ma, serwer stawia tymczasowe.

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared.Config.Economy)
local Rebirth = require(Shared.Logic.Rebirth)
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)
local LoopService = require(script.Parent.LoopService)
local ZoneService = require(script.Parent.ZoneService)

local RebirthService = {}

RebirthService.RebirthTag = "LarpRebirth" -- stoisko Rebirth (klient szuka go po tagu)
RebirthService.ShopTag = "LarpAuraShop" -- sklep Aury
RebirthService.LevelAttribute = "LarpRebirth" -- atrybut gracza: poziom Rebirth (tytuł nad głową)
RebirthService.AuraLevelAttribute = "LarpAuraLevel" -- atrybut gracza: Aura Level (liczba i poświata)

local MAX_DISTANCE = 15 -- tak blisko stoiska trzeba stać (studs)
local TELEPORT_DELAY = 2.6 -- teleport na spawn, gdy u gracza animacja Rebirth zasłania ekran (s)
local REBIRTH_GAP = 3 -- najmniejszy odstęp między Rebirthami (s)
local BUY_GAP = 0.15 -- najmniejszy odstęp między zakupami w sklepie Aury (s)

local rebirthStands = {}
local shopStands = {}
local lastRebirth = {}
local lastBuy = {}

----------------------------------------------------------------- Stoiska
local function addStand(list, inst, tag)
	for _, existing in ipairs(list) do
		if existing == inst then
			return
		end
	end
	CollectionService:AddTag(inst, tag)
	table.insert(list, inst)
end

local function scan()
	for _, inst in ipairs(Workspace:GetDescendants()) do
		if inst:IsA("Model") or inst:IsA("BasePart") then
			if inst.Name == "RebirthSpot" then
				addStand(rebirthStands, inst, RebirthService.RebirthTag)
			elseif inst.Name == "AuraShop" then
				addStand(shopStands, inst, RebirthService.ShopTag)
			end
		end
	end
end

local function distanceToPart(part, position)
	local p = part.CFrame:PointToObjectSpace(position)
	local half = part.Size / 2
	local dx = math.max(math.abs(p.X) - half.X, 0)
	local dy = math.max(math.abs(p.Y) - half.Y, 0)
	local dz = math.max(math.abs(p.Z) - half.Z, 0)
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function distanceToStand(stand, position)
	if stand:IsA("BasePart") then
		return distanceToPart(stand, position)
	end
	local best = math.huge
	for _, d in ipairs(stand:GetDescendants()) do
		if d:IsA("BasePart") then
			best = math.min(best, distanceToPart(d, position))
		end
	end
	return best
end

local function nearAny(player, list)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root == nil then
		return false
	end
	for _, stand in ipairs(list) do
		if stand.Parent ~= nil and distanceToStand(stand, root.Position) <= MAX_DISTANCE then
			return true
		end
	end
	return false
end

local function block(model, name, size, cframe, color, material, transparency)
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.Transparency = transparency or 0
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = model
	return part
end

local PURPLE = Color3.fromRGB(176, 70, 255)
local GOLD = Color3.fromRGB(255, 200, 60)
local DARK = Color3.fromRGB(44, 34, 66)

-- Portal Rebirth: okrągły cokół, pierścień ze złotych świecących klocków i fioletowa tafla.
-- frame = środek cokołu na ziemi, przodem (LookVector) do gracza.
local function buildRebirthStand(frame)
	local model = Instance.new("Model")
	model.Name = "RebirthSpot"
	local base = block(model, "Base", Vector3.new(1, 11, 11), frame * CFrame.new(0, 0.5, 0) * CFrame.Angles(0, 0, math.rad(90)), DARK)
	base.Shape = Enum.PartType.Cylinder
	local center = frame * CFrame.new(0, 6.2, 0)
	local radius = 4.6
	local count = 20
	for i = 1, count do
		local angle = (i - 1) / count * math.pi * 2
		local piece = center * CFrame.Angles(0, 0, angle) * CFrame.new(0, radius, 0)
		block(model, "Ring", Vector3.new(1.55, 0.7, 0.9), piece, GOLD, Enum.Material.Neon)
	end
	local surface = block(model, "Portal", Vector3.new(0.3, 8.6, 8.6), center * CFrame.Angles(0, math.rad(90), 0), PURPLE, Enum.Material.Neon, 0.35)
	surface.Shape = Enum.PartType.Cylinder
	surface.CanCollide = false
	local light = Instance.new("PointLight")
	light.Color = PURPLE
	light.Range = 18
	light.Brightness = 2
	light.Parent = surface
	model.WorldPivot = frame
	model.Parent = Workspace
	return model
end

-- Sklep Aury: cokół jak przy boxach i fioletowy kryształ (obrócony klocek) ze światłem.
local function buildShopStand(frame)
	local model = Instance.new("Model")
	model.Name = "AuraShop"
	local base = block(model, "Pedestal", Vector3.new(1.2, 7, 7), frame * CFrame.new(0, 0.6, 0) * CFrame.Angles(0, 0, math.rad(90)), DARK)
	base.Shape = Enum.PartType.Cylinder
	local crystal = block(model, "Crystal", Vector3.new(2.6, 2.6, 2.6), frame * CFrame.new(0, 3.6, 0) * CFrame.Angles(math.rad(45), 0, math.rad(45)), PURPLE, Enum.Material.Neon)
	crystal.CanCollide = false
	for i = 1, 3 do
		local angle = i * math.pi * 2 / 3
		local shard = frame * CFrame.new(math.cos(angle) * 2.4, 1.9, math.sin(angle) * 2.4) * CFrame.Angles(math.rad(45), angle, math.rad(45))
		block(model, "Shard", Vector3.new(0.9, 0.9, 0.9), shard, Color3.fromRGB(220, 170, 255), Enum.Material.Neon)
	end
	local light = Instance.new("PointLight")
	light.Color = PURPLE
	light.Range = 14
	light.Brightness = 1.6
	light.Parent = crystal
	model.WorldPivot = frame
	model.Parent = Workspace
	return model
end

local function facing(position, toward)
	local flat = Vector3.new(toward.X - position.X, 0, toward.Z - position.Z)
	if flat.Magnitude < 0.1 then
		return CFrame.new(position)
	end
	return CFrame.lookAt(position, position + flat.Unit)
end

local function buildPlaceholders()
	if #rebirthStands == 0 then
		local floor = ZoneService.floorPart(#Economy.Zones)
		if floor ~= nil then
			-- strefa 5: po tej samej stronie ścieżki co jajka, ale dalej w głąb strefy
			local top = floor.CFrame * CFrame.new(0, floor.Size.Y / 2, 0)
			local side = math.min(28, math.max(0, floor.Size.X / 2 - 8))
			local depth = math.min(30, math.max(0, floor.Size.Z / 2 - 10))
			local spot = (top * CFrame.new(side, 0, -depth)).Position
			local stand = buildRebirthStand(facing(spot, top.Position))
			addStand(rebirthStands, stand, RebirthService.RebirthTag)
			print("[Rebirth] Na mapie nie ma RebirthSpot, więc w strefie 5 stoi tymczasowy portal Rebirth.")
		else
			warn("[Rebirth] Strefa 5 nie ma podłogi (Zone5), więc nie ma gdzie postawić RebirthSpot.")
		end
	end
	if #shopStands == 0 then
		local pad = LoopService.firstSellPad()
		local frame = nil
		if pad ~= nil then
			local ground = pad.CFrame * CFrame.new(pad.Size.X / 2 + 10, -pad.Size.Y / 2, 0)
			frame = facing(ground.Position, pad.Position)
		else
			local spawnPart = Workspace:FindFirstChildWhichIsA("SpawnLocation", true)
			if spawnPart ~= nil then
				local ground = spawnPart.Position - Vector3.new(0, spawnPart.Size.Y / 2, 0)
				frame = facing(ground + Vector3.new(14, 0, -24), ground)
			end
		end
		if frame ~= nil then
			local stand = buildShopStand(frame)
			addStand(shopStands, stand, RebirthService.ShopTag)
			print("[Rebirth] Na mapie nie ma AuraShop, więc obok pola Sell stoi tymczasowy sklep Aury.")
		end
	end
end

----------------------------------------------------------------- Gracz: szybkość i napisy nad głową
local function applySpeed(player, level)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid ~= nil then
		humanoid.WalkSpeed = Rebirth.walkSpeed(level)
	end
end

local function updatePlayer(player, data)
	local level = data.RebirthLevel or 0
	if player:GetAttribute(RebirthService.LevelAttribute) ~= level then
		player:SetAttribute(RebirthService.LevelAttribute, level)
		applySpeed(player, level)
	end
	local auraLevel = Rebirth.auraLevel(data)
	if player:GetAttribute(RebirthService.AuraLevelAttribute) ~= auraLevel then
		player:SetAttribute(RebirthService.AuraLevelAttribute, auraLevel)
	end
end

----------------------------------------------------------------- Rebirth
-- Po Rebirthie (ze stoiska albo z komendy /rb): klient pokazuje animację, a gdy ekran jest
-- zasłonięty, serwer przenosi gracza na spawn w Downtown (strefy i tak się zresetowały).
function RebirthService.performed(player, data, result)
	LoopService.markDirty(player)
	updatePlayer(player, data)
	LoopService.notify(player, {
		Kind = "Rebirthed",
		Count = result.Count,
		Level = result.Level,
		LevelUp = result.LevelUp,
		Aura = result.Aura,
		Title = result.Title,
		FirstAura = result.FirstAura,
		PetSlots = result.PetSlots,
		Multiplier = Economy.Rebirth.LPMultiplier[result.Level],
		Speed = Rebirth.walkSpeed(result.Level),
		Teleport = TELEPORT_DELAY,
	})
	task.delay(TELEPORT_DELAY, function()
		if player.Parent ~= nil then
			ZoneService.teleport(player, 1)
		end
	end)
end

local function doRebirth(player)
	local data = DataService.get(player)
	if data == nil then
		return { Ok = false, Reason = "NotLoaded" }
	end
	local now = os.clock()
	if lastRebirth[player] ~= nil and now - lastRebirth[player] < REBIRTH_GAP then
		return { Ok = false, Reason = "Cooldown" }
	end
	if not nearAny(player, rebirthStands) then
		return { Ok = false, Reason = "TooFar" }
	end
	local result, reason = Rebirth.rebirth(data)
	if result == nil then
		return { Ok = false, Reason = reason }
	end
	lastRebirth[player] = now
	RebirthService.performed(player, data, result)
	return { Ok = true, Count = result.Count, Level = result.Level }
end

----------------------------------------------------------------- Sklep Aury
local function buyAuraUpgrade(player, key, mode)
	if type(key) ~= "string" or type(mode) ~= "string" then
		return { Ok = false, Reason = "BadRequest" }
	end
	local data = DataService.get(player)
	if data == nil then
		return { Ok = false, Reason = "NotLoaded" }
	end
	local now = os.clock()
	if lastBuy[player] ~= nil and now - lastBuy[player] < BUY_GAP then
		return { Ok = false, Reason = "Cooldown" }
	end
	if not nearAny(player, shopStands) then
		return { Ok = false, Reason = "TooFar" }
	end
	local result, reason = Rebirth.buyUpgrade(data, key, mode)
	if result == nil then
		return { Ok = false, Reason = reason }
	end
	lastBuy[player] = now
	LoopService.markDirty(player)
	updatePlayer(player, data)
	return { Ok = true, Bought = result.Bought, Spent = result.Spent, Level = result.Level, Key = key }
end

----------------------------------------------------------------- Start
function RebirthService.start()
	scan()
	buildPlaceholders()

	-- poziom Rebirth i Aura Level jako atrybuty gracza (napisy nad głową i poświata u wszystkich)
	LoopService.addViewHook(function(player)
		local data = DataService.get(player)
		if data ~= nil then
			updatePlayer(player, data)
		end
	end)
	local function onPlayer(player)
		player.CharacterAdded:Connect(function(character)
			local humanoid = character:WaitForChild("Humanoid", 10)
			local data = DataService.get(player)
			if humanoid ~= nil and data ~= nil then
				humanoid.WalkSpeed = Rebirth.walkSpeed(data.RebirthLevel or 0)
			end
		end)
	end
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayer(player)
	end
	Players.PlayerAdded:Connect(onPlayer)
	DataService.onLoaded(function(player, data)
		updatePlayer(player, data)
		applySpeed(player, data.RebirthLevel or 0)
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastRebirth[player] = nil
		lastBuy[player] = nil
	end)
	Net.func("Rebirth").OnServerInvoke = doRebirth
	Net.func("BuyAuraUpgrade").OnServerInvoke = buyAuraUpgrade
end

return RebirthService
