-- Jajka i pety (Etap 5): stoiska z jajkami w strefach, kupno i otwieranie jajek za L$, ekwipunek,
-- wyposażanie petów i bonus petów do L$ przy Sell (ctx.petLayer w LoopService).
--
-- Jak oznaczyć stoiska w Studio:
--   Model albo część o nazwie „EggAN” albo „EggBN”, gdzie N to strefa (np. EggA1, EggB1, EggA2…).
--   A to zwykłe jajko, B złote (lepsze szanse). Ceny i szanse są w arkuszu (Economy.Pets.Eggs).
--   Gdy na mapie nie ma żadnego stoiska, serwer stawia tymczasowe: w strefie 1 obok spawnu,
--   a w strefach 2–5 na podłodze strefy.
--
-- Pety gracza widzą wszyscy: serwer zapisuje wyposażone pety w atrybucie gracza „LarpPets”
-- („strefa:rzadkość:poziom” po przecinku), a każdy klient rysuje je sam (Client/Pets).

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared.Config.Economy)
local PetsConfig = require(Shared.Config.Pets)
local Loop = require(Shared.Logic.Loop)
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)
local GamepassService = require(script.Parent.GamepassService)
local LoopService = require(script.Parent.LoopService)
local ZoneService = require(script.Parent.ZoneService)

local PetService = {}

PetService.EggTag = "LarpEgg" -- tag stoisk (klient szuka ich po tym tagu)
PetService.Attribute = "LarpPets" -- atrybut gracza z wyposażonymi petami

local MAX_DISTANCE = 15 -- tak blisko stoiska (do jego najbliższej części) trzeba stać, żeby kupić jajko (studs)

local stands = {} -- lista stoisk (Model albo część z atrybutami Zone i Egg)
local lastOpen = {} -- [gracz] = czas ostatniego otwarcia
local sentInventory = {} -- [gracz] = podpis ekwipunku wysłanego klientowi
local rng = Random.new()

local function random01()
	return rng:NextNumber()
end

----------------------------------------------------------------- Stoiska z jajkami
local function addStand(inst, zone, egg)
	for _, existing in ipairs(stands) do
		if existing == inst then
			return
		end
	end
	inst:SetAttribute("Zone", zone)
	inst:SetAttribute("Egg", egg)
	CollectionService:AddTag(inst, PetService.EggTag)
	table.insert(stands, inst)
end

local function scan()
	for _, inst in ipairs(Workspace:GetDescendants()) do
		if inst:IsA("Model") or inst:IsA("BasePart") then
			local egg, digits = string.match(inst.Name, "^Egg([AB])(%d+)$")
			local zone = tonumber(digits)
			if egg ~= nil and zone ~= nil and Loop.eggInfo(zone, egg) ~= nil then
				addStand(inst, zone, egg)
			end
		end
	end
end

-- Odległość od punktu do najbliższej części stoiska (jak u gracza, który otwiera okno w 7 studs).
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

local EGG_COLORS = {
	A = Color3.fromRGB(245, 247, 250),
	B = Color3.fromRGB(255, 196, 60),
}

-- Stoisko: niski cokół i duże jajko. frame = środek cokołu na ziemi.
local function buildStand(zone, egg, frame)
	local model = Instance.new("Model")
	model.Name = "Egg" .. egg .. zone
	local base = Instance.new("Part")
	base.Name = "Pedestal"
	base.Shape = Enum.PartType.Cylinder
	base.Anchored = true
	base.Size = Vector3.new(1.2, 7, 7)
	base.CFrame = frame * CFrame.new(0, 0.6, 0) * CFrame.Angles(0, 0, math.rad(90))
	base.Color = Color3.fromRGB(60, 66, 82)
	base.Material = Enum.Material.SmoothPlastic
	base.Parent = model
	local shell = Instance.new("Part")
	shell.Name = "Egg"
	shell.Anchored = true
	shell.Size = Vector3.new(4.4, 5.6, 4.4)
	shell.CFrame = frame * CFrame.new(0, 1.2 + 2.8, 0)
	shell.Color = EGG_COLORS[egg]
	shell.Material = Enum.Material.SmoothPlastic
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = shell
	shell.Parent = model
	model.WorldPivot = frame
	model.Parent = Workspace
	return model
end

local function buildPlaceholders()
	local folder = Instance.new("Folder")
	folder.Name = "PlaceholderEggs"
	folder.Parent = Workspace
	local built = 0
	for zone in ipairs(Economy.Zones) do
		local frames = nil
		if zone == 1 then
			-- strefa 1: z boku drogi od spawnu do bramki strefy 2
			local spawnPart = Workspace:FindFirstChildWhichIsA("SpawnLocation", true)
			if spawnPart ~= nil then
				local ground = spawnPart.Position - Vector3.new(0, spawnPart.Size.Y / 2, 0)
				local look = spawnPart.CFrame.LookVector
				local flat = Vector3.new(look.X, 0, look.Z)
				if flat.Magnitude < 0.1 then
					flat = Vector3.new(0, 0, -1)
				end
				local frame = CFrame.lookAt(ground, ground + flat.Unit)
				frames = { A = frame * CFrame.new(-26, 0, -58), B = frame * CFrame.new(-26, 0, -74) }
			end
		else
			-- strefy 2–5: po drugiej stronie ścieżki niż auto do zdjęć
			local floor = ZoneService.floorPart(zone)
			if floor ~= nil then
				local top = floor.CFrame * CFrame.new(0, floor.Size.Y / 2, 0)
				local side = math.min(28, math.max(0, floor.Size.X / 2 - 8))
				frames = { A = top * CFrame.new(side, 0, -9), B = top * CFrame.new(side, 0, 9) }
			end
		end
		if frames ~= nil then
			for _, egg in ipairs({ "A", "B" }) do
				if Loop.eggInfo(zone, egg) ~= nil then
					buildStand(zone, egg, frames[egg]).Parent = folder
					built = built + 1
				end
			end
		end
	end
	if built > 0 then
		print("[Pety] Na mapie nie ma stoisk z jajkami, więc stoją tymczasowe (EggA1, EggB1 obok spawnu i w strefach 2–5).")
	end
end

local function nearStand(player, zone, egg)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root == nil then
		return false
	end
	for _, stand in ipairs(stands) do
		if stand.Parent ~= nil and stand:GetAttribute("Zone") == zone and stand:GetAttribute("Egg") == egg then
			if distanceToStand(stand, root.Position) <= MAX_DISTANCE then
				return true
			end
		end
	end
	return false
end

----------------------------------------------------------------- Ekwipunek dla klienta
local function equippedText(data, ctx)
	local list = {}
	for _, id in ipairs(Loop.activePets(data, ctx)) do
		local pet = data.Pets[id]
		table.insert(list, string.format("%d:%s:%d", pet.Zone, pet.Rarity, pet.Level or 0))
	end
	return table.concat(list, ",")
end

local function inventorySignature(data)
	return string.format("%d|%d|%s", Loop.petCount(data), data.NextPetId, table.concat(data.Equipped, ","))
end

-- Po każdej zmianie: atrybut z wyposażonymi petami (dla wszystkich) i pełny ekwipunek (dla gracza).
local function syncPets(player)
	local data = DataService.get(player)
	if data == nil then
		return
	end
	local ctx = LoopService.contextFor(player)
	local text = equippedText(data, ctx)
	if player:GetAttribute(PetService.Attribute) ~= text then
		player:SetAttribute(PetService.Attribute, text)
	end
	local signature = inventorySignature(data)
	if sentInventory[player] == signature then
		return
	end
	sentInventory[player] = signature
	local pets = {}
	for id, pet in pairs(data.Pets) do
		table.insert(pets, { Id = id, Zone = pet.Zone, Rarity = pet.Rarity, Level = pet.Level or 0 })
	end
	local active = {}
	for _, id in ipairs(Loop.activePets(data, ctx)) do
		table.insert(active, id)
	end
	LoopService.notify(player, { Kind = "Pets", Pets = pets, Equipped = active })
end

----------------------------------------------------------------- Żądania gracza
-- Ile trwa otwieranie jajka (animacja u gracza). Z Fast Open 3× krócej.
local function openTime(player)
	local seconds = Economy.OpenTimeSeconds
	if GamepassService.owns(player, "FastOpen") then
		seconds = seconds * Economy.Robux.Gamepasses.FastOpen.OpenTimeX
	end
	return seconds
end

-- Następne jajko można otworzyć dopiero pod koniec animacji poprzedniego.
local function openCooldown(player)
	return math.max(0.5, openTime(player) - 0.25)
end

local function buyEgg(player, zone, egg)
	if type(zone) ~= "number" or type(egg) ~= "string" then
		return { Ok = false, Reason = "BadRequest" }
	end
	local data = DataService.get(player)
	if data == nil then
		return { Ok = false, Reason = "NotLoaded" }
	end
	local now = os.clock()
	if lastOpen[player] ~= nil and now - lastOpen[player] < openCooldown(player) then
		return { Ok = false, Reason = "Cooldown" }
	end
	if not nearStand(player, zone, egg) then
		return { Ok = false, Reason = "TooFar" }
	end
	local id, result = Loop.openEgg(data, LoopService.contextFor(player), zone, egg, random01, PetsConfig.MaxInventory)
	if id == nil then
		return { Ok = false, Reason = result }
	end
	lastOpen[player] = now
	LoopService.markDirty(player)
	local equipped = false
	for _, equippedId in ipairs(data.Equipped) do
		if equippedId == id then
			equipped = true
		end
	end
	return {
		Ok = true,
		Id = id,
		Pet = { Zone = result.Zone, Rarity = result.Rarity, Level = result.Level },
		Equipped = equipped,
		OpenTime = openTime(player),
	}
end

local function equipPet(player, id, on)
	if type(id) ~= "string" or type(on) ~= "boolean" then
		return { Ok = false, Reason = "BadRequest" }
	end
	local data = DataService.get(player)
	if data == nil then
		return { Ok = false, Reason = "NotLoaded" }
	end
	local ok, reason
	if on then
		ok, reason = Loop.equipPet(data, LoopService.contextFor(player), id)
	else
		ok, reason = Loop.unequipPet(data, id)
	end
	if not ok then
		return { Ok = false, Reason = reason }
	end
	LoopService.markDirty(player)
	return { Ok = true }
end

local function equipBest(player)
	local data = DataService.get(player)
	if data == nil then
		return { Ok = false, Reason = "NotLoaded" }
	end
	Loop.equipBest(data, LoopService.contextFor(player))
	LoopService.markDirty(player)
	return { Ok = true }
end

----------------------------------------------------------------- Start
function PetService.start()
	scan()
	if #stands == 0 then
		buildPlaceholders()
		scan()
	end

	-- przy każdym wysłaniu stanu sprawdzamy, czy pety się zmieniły
	LoopService.addViewHook(function(player)
		syncPets(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastOpen[player] = nil
		sentInventory[player] = nil
	end)
	Net.func("BuyEgg").OnServerInvoke = buyEgg
	Net.func("EquipPet").OnServerInvoke = equipPet
	Net.func("EquipBest").OnServerInvoke = equipBest
end

return PetService
