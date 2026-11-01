-- Strefy na mapie: w której strefie gracz stoi (od tego zależy mnożnik LP) i bramki między strefami.
--
-- Jak oznaczyć strefy w Studio:
--   Strefa N (2–5) to część (Part), model albo folder o nazwie „ZoneN”: podłoga strefy, niewidzialne
--   pudło albo cały model strefy. Do strefy liczy się obszar nad jej częściami (do 60 studów w górę).
--   Wszystko poza strefami 2–5 to strefa 1 (spawn i pole Sell).
--   Bramka do strefy N to część, model albo folder o nazwie „GateN”. Dla wszystkich jest ścianą, a gracz,
--   który kupił strefę, przechodzi przez nią (otwiera ją tylko u siebie klient: Client/Zones).
-- Gdy na mapie nie ma żadnej strefy, serwer stawia tymczasowe (jak tymczasowe pole Sell).
-- Serwer sam pilnuje mnożnika: kto obejdzie bramkę, dostaje mnożnik ostatniej kupionej strefy.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared.Config.Economy)

local ZoneService = {}

ZoneService.GateTag = "LarpGate" -- tag części bramek (klient szuka ich po tym tagu)

local HEIGHT_ABOVE = 60 -- tyle studów nad częścią strefy jeszcze liczy się do strefy
local CHECK_INTERVAL = 0.2 -- co ile sekund sprawdzamy, gdzie stoją gracze

local areas = {} -- [strefa] = { części }
local gates = {} -- [strefa] = { części bramki }
local standing = {} -- [gracz] = strefa, w której stoi
local listeners = {}

----------------------------------------------------------------- Części na mapie
local function zoneNumber(name, prefix)
	local digits = string.match(name, "^" .. prefix .. "(%d+)$")
	local n = tonumber(digits)
	if n == nil or n < 2 or Economy.Zones[n] == nil then
		return nil
	end
	return n
end

local function addAreaPart(part, n)
	local list = areas[n]
	if list == nil then
		list = {}
		areas[n] = list
	end
	for _, existing in ipairs(list) do
		if existing == part then
			return
		end
	end
	table.insert(list, part)
end

-- Strefa może być jedną częścią albo modelem/folderem z całą strefą (liczą się wszystkie części w nim).
local function addArea(inst, n)
	if inst:IsA("BasePart") then
		addAreaPart(inst, n)
	end
	for _, child in ipairs(inst:GetDescendants()) do
		if child:IsA("BasePart") then
			addAreaPart(child, n)
		end
	end
end

local function addGatePart(part, n)
	local list = gates[n]
	if list == nil then
		list = {}
		gates[n] = list
	end
	for _, existing in ipairs(list) do
		if existing == part then
			return
		end
	end
	part:SetAttribute("Zone", n)
	CollectionService:AddTag(part, ZoneService.GateTag)
	table.insert(list, part)
end

local function addGate(inst, n)
	if inst:IsA("BasePart") then
		addGatePart(inst, n)
	end
	for _, child in ipairs(inst:GetDescendants()) do
		if child:IsA("BasePart") then
			addGatePart(child, n)
		end
	end
end

local function scan()
	for _, inst in ipairs(Workspace:GetDescendants()) do
		if inst:IsA("BasePart") or inst:IsA("Model") or inst:IsA("Folder") then
			local zone = zoneNumber(inst.Name, "Zone")
			if zone ~= nil then
				addArea(inst, zone)
			end
			local gate = zoneNumber(inst.Name, "Gate")
			if gate ~= nil then
				addGate(inst, gate)
			end
		end
	end
end

local function hasAreas()
	for _ in pairs(areas) do
		return true
	end
	return false
end

----------------------------------------------------------------- Tymczasowe strefy
-- Ścieżka od spawnu w stronę, w którą patrzy SpawnLocation. Środek strefy N jest tak daleko od spawnu,
-- ile gracz przejdzie w czasie powrotu na Sell z arkusza (WalkBackSeconds × WalkSpeed).
local PLACEHOLDER_WIDTH = 100
local PLACEHOLDER_COLORS = {
	[2] = Color3.fromRGB(235, 64, 80), -- Luxury Cars
	[3] = Color3.fromRGB(160, 92, 245), -- Luxury Mall
	[4] = Color3.fromRGB(46, 196, 232), -- Miami Beach
	[5] = Color3.fromRGB(245, 184, 46), -- Private Airport
}

local function placeholderPart(folder, name, size, cframe, color, material, transparency)
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material
	part.Transparency = transparency
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = folder
	return part
end

local function buildPlaceholder()
	local origin = Vector3.new(0, 0, 0)
	local forward = Vector3.new(0, 0, -1)
	local spawnPart = Workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	if spawnPart ~= nil then
		origin = spawnPart.Position - Vector3.new(0, spawnPart.Size.Y / 2, 0)
		local look = spawnPart.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		if flat.Magnitude > 0.1 then
			forward = flat.Unit
		end
	end
	local frame = CFrame.lookAt(origin, origin + forward) -- oś -Z ramki = w głąb ścieżki
	local function along(distance, height, side)
		return frame * CFrame.new(side or 0, height, -distance)
	end

	local count = #Economy.Zones
	local centers = {}
	for n, zone in ipairs(Economy.Zones) do
		centers[n] = zone.WalkBackSeconds * Economy.WalkSpeed
	end
	-- granica między strefami n i n+1 leży w połowie drogi między ich środkami
	local bounds = {}
	for n = 1, count - 1 do
		bounds[n] = (centers[n] + centers[n + 1]) / 2
	end
	bounds[count] = centers[count] + (centers[count] - bounds[count - 1])

	local folder = Instance.new("Folder")
	folder.Name = "PlaceholderZones"
	local wallColor = Color3.fromRGB(235, 240, 250)
	for n = 2, count do
		local from, to = bounds[n - 1], bounds[n]
		local length = to - from
		local middle = (from + to) / 2
		placeholderPart(
			folder,
			"Zone" .. n,
			Vector3.new(PLACEHOLDER_WIDTH, 0.4, length),
			along(middle, 0.2),
			PLACEHOLDER_COLORS[n],
			Enum.Material.SmoothPlastic,
			0.1
		)
		placeholderPart(
			folder,
			"Gate" .. n,
			Vector3.new(PLACEHOLDER_WIDTH, 18, 2),
			along(from, 9),
			PLACEHOLDER_COLORS[n],
			Enum.Material.Neon,
			0.35
		)
		for _, side in ipairs({ -1, 1 }) do
			placeholderPart(
				folder,
				"Wall",
				Vector3.new(2, 14, length),
				along(middle, 7, side * (PLACEHOLDER_WIDTH / 2 + 1)),
				wallColor,
				Enum.Material.Glass,
				0.5
			)
		end
	end
	placeholderPart(
		folder,
		"Wall",
		Vector3.new(PLACEHOLDER_WIDTH + 4, 14, 2),
		along(bounds[count] + 1, 7),
		wallColor,
		Enum.Material.Glass,
		0.5
	)
	folder.Parent = Workspace
	print(
		"[Strefy] Na mapie nie ma stref, więc stoją tymczasowe: kolorowa ścieżka przed spawnem."
			.. " Prawdziwe strefy to części ZoneN (podłoga strefy) i bramki GateN (README, Etap 3)."
	)
end

----------------------------------------------------------------- Gdzie stoi gracz
-- Czy punkt jest nad częścią strefy (w jej obrysie, od jej spodu do 60 studów nad nią).
local function above(part, position)
	local p = part.CFrame:PointToObjectSpace(position)
	local half = part.Size / 2
	return math.abs(p.X) <= half.X and math.abs(p.Z) <= half.Z and p.Y >= -half.Y and p.Y <= half.Y + HEIGHT_ABOVE
end

-- Najwyższa strefa, nad którą jest punkt. Poza strefami 2–5 jest strefa 1.
function ZoneService.zoneAt(position)
	for n = #Economy.Zones, 2, -1 do
		local list = areas[n]
		if list ~= nil then
			for _, part in ipairs(list) do
				if part.Parent ~= nil and above(part, position) then
					return n
				end
			end
		end
	end
	return 1
end

-- Strefa, w której gracz stoi (bez sprawdzania, czy ją kupił; to robi Loop.effectiveZone).
function ZoneService.standing(player)
	return standing[player] or 1
end

-- fn(player, zone) po wejściu gracza do innej strefy.
function ZoneService.onChanged(fn)
	table.insert(listeners, fn)
end

local function update(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root == nil then
		return
	end
	local zone = ZoneService.zoneAt(root.Position)
	if standing[player] ~= zone then
		standing[player] = zone
		for _, fn in ipairs(listeners) do
			task.spawn(fn, player, zone)
		end
	end
end

----------------------------------------------------------------- Teleport (tryb testowy)
-- Miejsce w strefie: nad środkiem jej największej części, czyli zwykle podłogi (strefa 1: nad spawnem).
function ZoneService.spawnPoint(n)
	if n == 1 then
		local spawnPart = Workspace:FindFirstChildWhichIsA("SpawnLocation", true)
		if spawnPart == nil then
			return nil
		end
		return spawnPart.Position + Vector3.new(0, spawnPart.Size.Y / 2 + 4, 0)
	end
	local best, bestArea = nil, -1
	for _, part in ipairs(areas[n] or {}) do
		local footprint = part.Size.X * part.Size.Z
		if part.Parent ~= nil and footprint > bestArea then
			best, bestArea = part, footprint
		end
	end
	if best == nil then
		return nil
	end
	return (best.CFrame * CFrame.new(0, -best.Size.Y / 2 + 4, 0)).Position
end

function ZoneService.teleport(player, n)
	local point = ZoneService.spawnPoint(n)
	local character = player.Character
	if point == nil or character == nil then
		return false
	end
	character:PivotTo(CFrame.new(point))
	return true
end

----------------------------------------------------------------- Start
function ZoneService.start()
	scan()
	if not hasAreas() then
		buildPlaceholder()
		scan()
	end
	for n = 2, #Economy.Zones do
		if areas[n] == nil then
			warn(string.format("[Strefy] Brak strefy %d (%s): dodaj część o nazwie Zone%d.", n, Economy.Zones[n].Name, n))
		elseif gates[n] == nil then
			warn(string.format("[Strefy] Strefa %d (%s) nie ma bramki: dodaj część albo model Gate%d.", n, Economy.Zones[n].Name, n))
		end
	end

	local timer = 0
	RunService.Heartbeat:Connect(function(dt)
		timer = timer + dt
		if timer < CHECK_INTERVAL then
			return
		end
		timer = 0
		for _, player in ipairs(Players:GetPlayers()) do
			update(player)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		standing[player] = nil
	end)
end

return ZoneService
