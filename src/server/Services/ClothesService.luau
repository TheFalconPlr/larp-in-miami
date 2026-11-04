-- Ubrania (Etap 8, dokument projektu): stoiska z mystery boxami w Mall, kupno i otwieranie boxów
-- za L$, zakładanie (1 slot na kategorię, Chain i Watch po 2 z gamepassami), sprzedaż i łączenie
-- jak u petów oraz ubrania na awatarze (widzą je wszyscy; gracz może je ukryć, bonus zostaje).
-- Liczy wszystko Shared/Logic/Clothes, a warstwa ubrań mnoży LP (ctx.clothLayer w LoopService).
--
-- Jak oznaczyć stoiska w Studio:
--   Model albo część o nazwie „BoxStreet”, „BoxDesigner” albo „BoxIced” (wszystkie w Mall).
--   Designer da się kupić dopiero po odblokowaniu plaży, a Iced po odblokowaniu lotniska.
--   Gdy na mapie nie ma żadnego stoiska, serwer stawia tymczasowe na podłodze Mall.

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared.Config.Economy)
local ClothesConfig = require(Shared.Config.Clothes)
local Clothes = require(Shared.Logic.Clothes)
local ClothModels = require(Shared.ClothModels)
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)
local GamepassService = require(script.Parent.GamepassService)
local LoopService = require(script.Parent.LoopService)
local ZoneService = require(script.Parent.ZoneService)

local ClothesService = {}

ClothesService.BoxTag = "LarpBox" -- tag stoisk (klient szuka ich po tym tagu)
ClothesService.Zone = 3 -- boxy stoją w Mall

local MAX_DISTANCE = 15 -- tak blisko stoiska trzeba stać, żeby kupić box (studs)
local ACTION_GAP = 0.25 -- najmniejszy odstęp między sprzedażą a łączeniem (s)

local stands = {}
local lastOpen = {} -- [gracz] = czas ostatniego otwarcia
local lastAction = {} -- [gracz] = czas ostatniej sprzedaży albo łączenia
local sentInventory = {} -- [gracz] = podpis ekwipunku wysłanego klientowi
local dressed = {} -- [gracz] = podpis ubrań na postaci
local rng = Random.new()

local function random01()
	return rng:NextNumber()
end

----------------------------------------------------------------- Stoiska
local function addStand(inst, box)
	for _, existing in ipairs(stands) do
		if existing == inst then
			return
		end
	end
	inst:SetAttribute("Box", box)
	inst:SetAttribute("Zone", ClothesService.Zone)
	CollectionService:AddTag(inst, ClothesService.BoxTag)
	table.insert(stands, inst)
end

local function scan()
	for _, inst in ipairs(Workspace:GetDescendants()) do
		if inst:IsA("Model") or inst:IsA("BasePart") then
			local box = string.match(inst.Name, "^Box(%a+)$")
			if box ~= nil and Clothes.boxInfo(box) ~= nil then
				addStand(inst, box)
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

local function block(model, name, size, cframe, color, material)
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = model
	return part
end

-- Stoisko: niski cokół i pudełko prezentowe ze wstążką (ClothModels.box). frame = środek cokołu na ziemi.
local function buildStand(box, frame)
	local model = Instance.new("Model")
	model.Name = "Box" .. box
	local base = block(model, "Pedestal", Vector3.new(1.2, 7, 7), frame * CFrame.new(0, 0.6, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(60, 66, 82))
	base.Shape = Enum.PartType.Cylinder
	local gift = ClothModels.box(box)
	gift:PivotTo(frame * CFrame.new(0, 1.2, 0))
	for _, part in ipairs(gift:GetChildren()) do
		part.Parent = model
	end
	gift:Destroy()
	model.WorldPivot = frame
	model.Parent = Workspace
	return model
end

local function buildPlaceholders()
	local floor = ZoneService.floorPart(ClothesService.Zone)
	if floor == nil then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "PlaceholderBoxes"
	folder.Parent = Workspace
	local top = floor.CFrame * CFrame.new(0, floor.Size.Y / 2, 0)
	-- po tej samej stronie ścieżki co jajka, dalej w głąb strefy (studio wywiadu jest po drugiej)
	local side = math.min(28, math.max(0, floor.Size.X / 2 - 8))
	local room = math.max(0, floor.Size.Z / 2 - 6)
	for i, box in ipairs(Clothes.BoxOrder) do
		local z = math.min(room, 22 + 9 * (i - 1))
		buildStand(box, top * CFrame.new(side, 0, -z)).Parent = folder
	end
	print("[Ubrania] Na mapie nie ma stoisk z boxami, więc stoją tymczasowe w Mall (BoxStreet, BoxDesigner, BoxIced).")
end

local function nearStand(player, box)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root == nil then
		return false
	end
	for _, stand in ipairs(stands) do
		if stand.Parent ~= nil and stand:GetAttribute("Box") == box then
			if distanceToStand(stand, root.Position) <= MAX_DISTANCE then
				return true
			end
		end
	end
	return false
end

----------------------------------------------------------------- Ubrania na postaci
-- Lista ubrań do założenia na postać: { Category, Rarity, Level, Slot }.
local function outfit(data, ctx)
	local items = {}
	for category, ids in pairs(Clothes.wornByCategory(data, ctx)) do
		for slot, id in ipairs(ids) do
			local item = data.Clothes[id]
			table.insert(items, { Category = category, Rarity = item.Rarity, Level = item.Level or 0, Slot = slot })
		end
	end
	table.sort(items, function(a, b)
		local ia, ib = Clothes.categoryIndex(a.Category) or 0, Clothes.categoryIndex(b.Category) or 0
		if ia ~= ib then
			return ia < ib
		end
		return a.Slot < b.Slot
	end)
	return items
end

local function outfitSignature(items, show)
	local parts = { tostring(show) }
	for _, entry in ipairs(items) do
		table.insert(parts, string.format("%s:%s:%d:%d", entry.Category, entry.Rarity, entry.Level, entry.Slot))
	end
	return table.concat(parts, ",")
end

-- Ubiera postać gracza tak, jak w zapisie (albo zdejmuje ubrania, gdy gracz je ukrył).
local function dressNow(player, force)
	local data = DataService.get(player)
	local character = player.Character
	if data == nil or character == nil or character:FindFirstChildOfClass("Humanoid") == nil then
		return
	end
	local show = data.Settings.ShowClothes ~= false
	local items = outfit(data, LoopService.contextFor(player))
	local signature = outfitSignature(items, show)
	local wanted = show and #items > 0
	local present = character:FindFirstChild(ClothModels.FolderName) ~= nil
	if not force and dressed[player] == signature and wanted == present then
		return
	end
	dressed[player] = signature
	if wanted then
		ClothModels.dress(character, items)
	else
		ClothModels.undress(character)
	end
end

-- Błąd w ubieraniu nie może zatrzymać wysyłania stanu do gracza, więc łapiemy go tutaj.
local function dressPlayer(player, force)
	local ok, err = pcall(dressNow, player, force)
	if not ok then
		warn("[Ubrania] ubieranie postaci: " .. tostring(err))
	end
end

local function watchCharacter(player, character)
	dressed[player] = nil
	task.spawn(function()
		character:WaitForChild("Humanoid", 10)
		dressPlayer(player, true)
	end)
	-- włosy gracza wczytują się później niż postać: gdy nosi włosy z gry, chowamy też te nowe
	character.ChildAdded:Connect(function(child)
		if child:IsA("Accessory") and child.AccessoryType == Enum.AccessoryType.Hair then
			task.defer(function()
				local folder = character:FindFirstChild(ClothModels.FolderName)
				if folder ~= nil and dressed[player] ~= nil and string.find(dressed[player], "Hair:", 1, true) then
					ClothModels.setOwnHairHidden(character, true)
				end
			end)
		end
	end)
end

----------------------------------------------------------------- Ekwipunek dla klienta
local function inventorySignature(data, ctx)
	return string.format(
		"%d|%d|%s|%s",
		Clothes.count(data),
		data.NextClothId,
		table.concat(Clothes.active(data, ctx), ","),
		tostring(data.Settings.ShowClothes ~= false)
	)
end

local function itemForClient(data, id, item)
	return {
		Id = id,
		Category = item.Category,
		Rarity = item.Rarity,
		Level = item.Level or 0,
		Box = item.Box or "Street",
		Worn = Clothes.isWorn(data, id),
	}
end

local function syncClothes(player)
	local data = DataService.get(player)
	if data == nil then
		return
	end
	local ctx = LoopService.contextFor(player)
	dressPlayer(player, false)
	local signature = inventorySignature(data, ctx)
	if sentInventory[player] == signature then
		return
	end
	sentInventory[player] = signature
	local list = {}
	for id, item in pairs(data.Clothes) do
		table.insert(list, itemForClient(data, id, item))
	end
	LoopService.notify(player, { Kind = "Clothes", Clothes = list, Worn = Clothes.active(data, ctx) })
end

----------------------------------------------------------------- Żądania gracza
local function openTime(player)
	local seconds = Economy.OpenTimeSeconds
	if GamepassService.owns(player, "FastOpen") then
		seconds = seconds * Economy.Robux.Gamepasses.FastOpen.OpenTimeX
	end
	return seconds
end

local function buyBox(player, box)
	if type(box) ~= "string" or Clothes.boxInfo(box) == nil then
		return { Ok = false, Reason = "BadRequest" }
	end
	local data = DataService.get(player)
	if data == nil then
		return { Ok = false, Reason = "NotLoaded" }
	end
	local now = os.clock()
	local cooldown = math.max(0.5, openTime(player) - 0.25)
	if lastOpen[player] ~= nil and now - lastOpen[player] < cooldown then
		return { Ok = false, Reason = "Cooldown" }
	end
	if not nearStand(player, box) then
		return { Ok = false, Reason = "TooFar" }
	end
	local ctx = LoopService.contextFor(player)
	local id, item, worn = Clothes.openBox(data, ctx, box, random01, ClothesConfig.MaxInventory)
	if id == nil then
		return { Ok = false, Reason = item }
	end
	lastOpen[player] = now
	LoopService.markDirty(player)
	local reply = itemForClient(data, id, item)
	reply.Worn = worn
	return { Ok = true, Item = reply, OpenTime = openTime(player) }
end

local function wearCloth(player, id, on)
	if type(id) ~= "string" or type(on) ~= "boolean" then
		return { Ok = false, Reason = "BadRequest" }
	end
	local data = DataService.get(player)
	if data == nil then
		return { Ok = false, Reason = "NotLoaded" }
	end
	local ok, reason
	if on then
		ok, reason = Clothes.wear(data, LoopService.contextFor(player), id)
	else
		ok, reason = Clothes.unwear(data, id)
	end
	if not ok then
		return { Ok = false, Reason = reason }
	end
	LoopService.markDirty(player)
	return { Ok = true }
end

local function wearBest(player)
	local data = DataService.get(player)
	if data == nil then
		return { Ok = false, Reason = "NotLoaded" }
	end
	Clothes.wearBest(data, LoopService.contextFor(player))
	LoopService.markDirty(player)
	return { Ok = true }
end

local function validIds(ids, max)
	if type(ids) ~= "table" or #ids == 0 or #ids > max then
		return false
	end
	local seen = {}
	local count = 0
	for _, id in ipairs(ids) do
		if type(id) ~= "string" or #id > 12 or seen[id] then
			return false
		end
		seen[id] = true
		count = count + 1
	end
	return count == #ids
end

local function tooSoon(player)
	local now = os.clock()
	if lastAction[player] ~= nil and now - lastAction[player] < ACTION_GAP then
		return true
	end
	lastAction[player] = now
	return false
end

local function sellClothes(player, ids)
	if not validIds(ids, ClothesConfig.MaxInventory) then
		return { Ok = false, Reason = "BadRequest" }
	end
	local data = DataService.get(player)
	if data == nil then
		return { Ok = false, Reason = "NotLoaded" }
	end
	if tooSoon(player) then
		return { Ok = false, Reason = "Cooldown" }
	end
	local count, cash = Clothes.sell(data, LoopService.contextFor(player), ids)
	LoopService.markDirty(player)
	return { Ok = true, Count = count, Cash = cash }
end

local function mergeClothes(player, ids)
	if not validIds(ids, Economy.Pets.Merge.MaxPieces) then
		return { Ok = false, Reason = "BadRequest" }
	end
	local data = DataService.get(player)
	if data == nil then
		return { Ok = false, Reason = "NotLoaded" }
	end
	if tooSoon(player) then
		return { Ok = false, Reason = "Cooldown" }
	end
	local result, reason = Clothes.merge(data, LoopService.contextFor(player), ids, random01)
	if result == nil then
		return { Ok = false, Reason = reason }
	end
	LoopService.markDirty(player)
	local reply = {
		Ok = true,
		Success = result.Success,
		Chance = result.Info.Chance,
		Fee = result.Info.Fee,
		Category = result.Info.Category,
		Rarity = result.Info.Rarity,
		Level = result.Info.Level,
	}
	if result.Success then
		reply.Item = itemForClient(data, result.Id, result.Item)
	end
	return reply
end

----------------------------------------------------------------- Dla innych modułów
-- Daje ubranie (komenda testowa). Zwraca id.
function ClothesService.give(data, category, rarity, level)
	local id = tostring(data.NextClothId)
	data.NextClothId = data.NextClothId + 1
	data.Clothes[id] = { Category = category, Rarity = rarity, Level = level or 0, Box = Economy.Clothes.SourceBox[rarity] or "Street" }
	return id
end

----------------------------------------------------------------- Start
function ClothesService.start()
	scan()
	if #stands == 0 then
		buildPlaceholders()
		scan()
	end

	LoopService.addViewHook(function(player, view)
		local data = DataService.get(player)
		if data == nil then
			return
		end
		local ctx = LoopService.contextFor(player)
		for key, value in pairs(Clothes.view(data, ctx)) do
			view[key] = value
		end
		syncClothes(player)
	end)
	local function onPlayer(player)
		player.CharacterAdded:Connect(function(character)
			watchCharacter(player, character)
		end)
		-- wygląd gracza (części ciała, akcesoria) wczytuje się po postaci: ubieramy jeszcze raz
		player.CharacterAppearanceLoaded:Connect(function()
			dressPlayer(player, true)
		end)
		if player.Character ~= nil then
			watchCharacter(player, player.Character)
		end
	end
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayer(player)
	end
	Players.PlayerAdded:Connect(onPlayer)
	DataService.onLoaded(function(player)
		dressPlayer(player, true)
	end)
	-- gamepassy Double Chain i Double Wrist zmieniają liczbę slotów, więc też to, co widać
	GamepassService.onChanged(function(player)
		LoopService.markDirty(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastOpen[player] = nil
		lastAction[player] = nil
		sentInventory[player] = nil
		dressed[player] = nil
	end)
	Net.func("BuyBox").OnServerInvoke = buyBox
	Net.func("WearCloth").OnServerInvoke = wearCloth
	Net.func("WearBest").OnServerInvoke = wearBest
	Net.func("SellClothes").OnServerInvoke = sellClothes
	Net.func("MergeClothes").OnServerInvoke = mergeClothes
end

return ClothesService
