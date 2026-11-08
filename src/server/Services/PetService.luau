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
--
-- Etap 7 (dokument projektu, etap 4): sprzedaż petów (SellPets, 10% ceny jajka), łączenie z szansą
-- w wersję Złotą i Diamentową (MergePets), indeks odkrytych petów i komunikat o sekrecie na
-- wszystkich serwerach gry (MessagingService; gdy nie działa, np. w Studio, tylko na tym serwerze).

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local MessagingService = game:GetService("MessagingService")
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
local SECRET_TOPIC = "LarpSecretHatched" -- kanał MessagingService z sekretami

local ACTION_GAP = 0.25 -- najmniejszy odstęp między sprzedażą a łączeniem (s), żeby nie zalać serwera
local SECRET_DELAY = 0.6 -- komunikat o sekrecie po animacji otwierania (s), żeby nie zdradzić wyniku

local stands = {} -- lista stoisk (Model albo część z atrybutami Zone i Egg)
local lastOpen = {} -- [gracz] = czas ostatniego otwarcia
local lastAction = {} -- [gracz] = czas ostatniej sprzedaży albo łączenia
local sentInventory = {} -- [gracz] = podpis ekwipunku wysłanego klientowi
local secretsSubscribed = false -- czy ten serwer słucha sekretów z innych serwerów
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

-- Czy na stoisku o tej nazwie jest jajko: A i B za L$, P = premium (za Robuxy).
local function validEgg(zone, egg)
	if egg == "P" then
		return Loop.premiumInfo(zone) ~= nil
	end
	return Loop.eggInfo(zone, egg) ~= nil
end

local function scan()
	for _, inst in ipairs(Workspace:GetDescendants()) do
		if inst:IsA("Model") or inst:IsA("BasePart") then
			local egg, digits = string.match(inst.Name, "^Egg([ABP])(%d+)$")
			local zone = tonumber(digits)
			if egg ~= nil and zone ~= nil and validEgg(zone, egg) then
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
	P = Color3.fromRGB(164, 92, 255), -- premium: fioletowe, ze złotym pierścieniem
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
	if egg == "P" then
		-- złoty pierścień wokół cokołu i neonowa obwódka: premium jajko widać z daleka
		local ring = Instance.new("Part")
		ring.Name = "Ring"
		ring.Shape = Enum.PartType.Cylinder
		ring.Anchored = true
		ring.Size = Vector3.new(0.5, 7.6, 7.6)
		ring.CFrame = frame * CFrame.new(0, 1.05, 0) * CFrame.Angles(0, 0, math.rad(90))
		ring.Color = Color3.fromRGB(255, 196, 60)
		ring.Material = Enum.Material.Neon
		ring.Parent = model
		base.Color = Color3.fromRGB(46, 30, 86)
	end
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
				frames = { A = frame * CFrame.new(-26, 0, -58), B = frame * CFrame.new(-26, 0, -74), P = frame * CFrame.new(-26, 0, -90) }
			end
		else
			-- strefy 2–5: po drugiej stronie ścieżki niż auto do zdjęć
			local floor = ZoneService.floorPart(zone)
			if floor ~= nil then
				local top = floor.CFrame * CFrame.new(0, floor.Size.Y / 2, 0)
				local side = math.min(28, math.max(0, floor.Size.X / 2 - 8))
				frames = { A = top * CFrame.new(side, 0, -9), B = top * CFrame.new(side, 0, 9), P = top * CFrame.new(side, 0, 27) }
			end
		end
		if frames ~= nil then
			for _, egg in ipairs({ "A", "B", "P" }) do
				if validEgg(zone, egg) then
					buildStand(zone, egg, frames[egg]).Parent = folder
					built = built + 1
				end
			end
		end
	end
	if built > 0 then
		print("[Pety] Na mapie nie ma stoisk z jajkami, więc stoją tymczasowe (EggA1, EggB1, EggP1 obok spawnu i w strefach 2–5).")
	end
end

-- Spód i środek stoiska (Model albo część): ziemia pod nim i jego obrót.
local function standFrame(stand)
	local cf, size
	if stand:IsA("Model") then
		cf, size = stand:GetBoundingBox()
	else
		cf, size = stand.CFrame, stand.Size
	end
	return cf * CFrame.new(0, -size.Y / 2, 0)
end

-- Premium jajko (EggPN) w strefach, które mają już jajka A i B, ale nie mają premium: stawiamy je
-- w tym samym rzędzie, za jajkiem B (B + odstęp A→B), albo 14 studs obok B.
local function buildPremiumPlaceholders()
	local byZone = {}
	for _, stand in ipairs(stands) do
		local zone = stand:GetAttribute("Zone")
		byZone[zone] = byZone[zone] or {}
		byZone[zone][stand:GetAttribute("Egg")] = stand
	end
	local folder = nil
	for zone in ipairs(Economy.Zones) do
		local list = byZone[zone]
		if list ~= nil and list.P == nil and list.B ~= nil and validEgg(zone, "P") then
			local b = standFrame(list.B)
			local step = b.RightVector * 14
			if list.A ~= nil then
				local a = standFrame(list.A)
				local d = b.Position - a.Position
				step = Vector3.new(d.X, 0, d.Z)
			end
			if folder == nil then
				folder = Instance.new("Folder")
				folder.Name = "PlaceholderPremiumEggs"
				folder.Parent = Workspace
			end
			local frame = b.Rotation + (b.Position + step)
			buildStand(zone, "P", frame).Parent = folder
		end
	end
	if folder ~= nil then
		print("[Pety] Brakowało premium jajek (EggP1…EggP5), więc stoją tymczasowe za jajkami B.")
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
	return string.format("%d|%d|%d|%s", Loop.petCount(data), data.NextPetId, Loop.indexCount(data), table.concat(data.Equipped, ","))
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
		table.insert(pets, { Id = id, Zone = pet.Zone, Rarity = pet.Rarity, Level = pet.Level or 0, Egg = pet.Egg or "A" })
	end
	local active = {}
	for _, id in ipairs(Loop.activePets(data, ctx)) do
		table.insert(active, id)
	end
	local index = {}
	for key, found in pairs(data.Index or {}) do
		if found then
			table.insert(index, key)
		end
	end
	LoopService.notify(player, { Kind = "Pets", Pets = pets, Equipped = active, Index = index })
end

----------------------------------------------------------------- Sekret na wszystkich serwerach
local function knownCategory(category)
	for _, name in ipairs(Economy.Clothes.Categories) do
		if name == category then
			return true
		end
	end
	return false
end

-- Każdy gracz na serwerze dostaje komunikat (u siebie pokazuje go jako baner u góry ekranu).
local function deliverSecret(message)
	if type(message) ~= "table" or type(message.Name) ~= "string" then
		return
	end
	-- pet: strefa jajka; ubranie (Ultra Secret z boxa Iced): kategoria
	local cloth = message.Kind == "Cloth"
	if cloth then
		if not knownCategory(message.Category) then
			return
		end
	elseif type(message.Zone) ~= "number" or Economy.Pets.Eggs[message.Zone] == nil then
		return
	end
	local level = message.Level
	if type(level) ~= "number" then
		level = 0
	end
	local userId = message.UserId
	if type(userId) ~= "number" then
		userId = 0
	end
	for _, other in ipairs(Players:GetPlayers()) do
		LoopService.notify(other, {
			Kind = "SecretHatched",
			Item = (cloth and "Cloth") or "Pet",
			Name = string.sub(message.Name, 1, 40),
			UserId = userId,
			Zone = message.Zone,
			Category = message.Category,
			Level = level,
			Mine = other.UserId == userId,
		})
	end
end

-- Ogłasza sekretnego peta: nick, pet i „1 in 25,000” na wszystkich serwerach gry. Gdy
-- MessagingService nie działa (np. w Studio bez dostępu do API), komunikat dostaje tylko ten serwer.
function PetService.announceSecret(player, pet)
	local message = { Name = player.DisplayName, UserId = player.UserId, Zone = pet.Zone, Level = pet.Level or 0 }
	if pet.Category ~= nil then
		-- ubranie Ultra Secret (ClothesService): ten sam komunikat, tylko z kategorią zamiast strefy
		message = { Kind = "Cloth", Name = player.DisplayName, UserId = player.UserId, Category = pet.Category, Level = pet.Level or 0 }
	end
	local sent = false
	if secretsSubscribed then
		sent = pcall(function()
			MessagingService:PublishAsync(SECRET_TOPIC, message)
		end)
	end
	if not sent then
		deliverSecret(message)
	end
end

local function subscribeSecrets()
	local ok, err = pcall(function()
		MessagingService:SubscribeAsync(SECRET_TOPIC, function(packet)
			deliverSecret(packet.Data)
		end)
	end)
	secretsSubscribed = ok
	if not ok then
		warn("[Pety] MessagingService nie działa (" .. tostring(err) .. "), więc sekrety ogłaszamy tylko na tym serwerze.")
	end
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
PetService.openTime = openTime

-- Następne jajko można otworzyć dopiero pod koniec animacji poprzedniego.
local function openCooldown(player)
	return math.max(0.5, openTime(player) - 0.25)
end

-- count: 1 albo 3 (Triple Open, tylko z gamepassem).
local function buyEgg(player, zone, egg, count)
	if count == nil then
		count = 1
	end
	if type(zone) ~= "number" or type(egg) ~= "string" or type(count) ~= "number" then
		return { Ok = false, Reason = "BadRequest" }
	end
	local triple = Economy.Robux.Gamepasses.TripleOpen.OpenCount
	if count ~= 1 and count ~= triple then
		return { Ok = false, Reason = "BadRequest" }
	end
	if count > 1 and not GamepassService.owns(player, "TripleOpen") then
		return { Ok = false, Reason = "NoPass" }
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
	local list, reason = Loop.openEggs(data, LoopService.contextFor(player), zone, egg, count, random01, PetsConfig.MaxInventory)
	if list == nil then
		return { Ok = false, Reason = reason }
	end
	lastOpen[player] = now
	LoopService.markDirty(player)
	-- zadanie EggsOpened: jajka za L$ (premium jajka i jajka z nagród się nie liczą)
	LoopService.progress(player, "EggsOpened", #list)
	local seconds = openTime(player)
	local pets = {}
	for _, entry in ipairs(list) do
		table.insert(pets, {
			Id = entry.id,
			Zone = entry.pet.Zone,
			Rarity = entry.pet.Rarity,
			Level = entry.pet.Level,
			Egg = entry.pet.Egg,
			New = entry.new == true,
			Equipped = Loop.isEquipped(data, entry.id),
		})
		if entry.pet.Rarity == "Secret" then
			local pet = entry.pet
			task.delay(seconds + SECRET_DELAY, function()
				PetService.announceSecret(player, pet)
			end)
		end
	end
	return { Ok = true, Pets = pets, OpenTime = seconds }
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

-- Lista id od gracza: 1..max różnych tekstów, bez dziur.
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

-- Sprzedaż i łączenie najwyżej co ACTION_GAP sekund.
local function tooSoon(player)
	local now = os.clock()
	if lastAction[player] ~= nil and now - lastAction[player] < ACTION_GAP then
		return true
	end
	lastAction[player] = now
	return false
end

local function petForClient(data, id, pet)
	return {
		Id = id,
		Zone = pet.Zone,
		Rarity = pet.Rarity,
		Level = pet.Level or 0,
		Egg = pet.Egg or "A",
		Equipped = Loop.isEquipped(data, id),
	}
end

-- Sprzedaż petów za L$ (tryb SELL w oknie PETS). Założonych serwer nie sprzedaje, a sekretnego
-- tylko z confirm = true (gracz potwierdził w okienku).
local function sellPets(player, ids, confirm)
	if not validIds(ids, PetsConfig.MaxInventory) or (confirm ~= nil and type(confirm) ~= "boolean") then
		return { Ok = false, Reason = "BadRequest" }
	end
	local data = DataService.get(player)
	if data == nil then
		return { Ok = false, Reason = "NotLoaded" }
	end
	if tooSoon(player) then
		return { Ok = false, Reason = "Cooldown" }
	end
	local count, cash = Loop.sellPets(data, LoopService.contextFor(player), ids, confirm == true)
	if count == nil then
		return { Ok = false, Reason = cash }
	end
	LoopService.markDirty(player)
	return { Ok = true, Count = count, Cash = cash }
end

-- Łączenie 1–5 identycznych petów (tryb MERGE). Szansę losuje serwer; opłata przepada zawsze.
local function mergePets(player, ids)
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
	local result, reason = Loop.mergePets(data, LoopService.contextFor(player), ids, random01)
	if result == nil then
		return { Ok = false, Reason = reason }
	end
	LoopService.markDirty(player)
	LoopService.progress(player, "Merges", 1) -- zadanie Merges: każda próba (też nieudana)
	local reply = {
		Ok = true,
		Success = result.Success,
		Chance = result.Info.Chance,
		Fee = result.Info.Fee,
		Zone = result.Info.Zone,
		Rarity = result.Info.Rarity,
		Level = result.Info.Level,
	}
	if result.Success then
		reply.Pet = petForClient(data, result.Id, result.Pet)
	end
	return reply
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
	buildPremiumPlaceholders()
	scan()

	-- indeks: stare zapisy dostają pety, które gracz już ma
	DataService.onLoaded(function(_, data)
		Loop.backfillIndex(data)
	end)
	-- przy każdym wysłaniu stanu sprawdzamy, czy pety się zmieniły
	LoopService.addViewHook(function(player)
		syncPets(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastOpen[player] = nil
		lastAction[player] = nil
		sentInventory[player] = nil
	end)
	Net.func("BuyEgg").OnServerInvoke = buyEgg
	Net.func("EquipPet").OnServerInvoke = equipPet
	Net.func("EquipBest").OnServerInvoke = equipBest
	Net.func("SellPets").OnServerInvoke = sellPets
	Net.func("MergePets").OnServerInvoke = mergePets
	task.spawn(subscribeSecrets)
end

return PetService
