-- Modele petów i jajek po stronie gracza. Pet: własny model z ReplicatedStorage → PetModels
-- (nazwa jak pet w Shared/Config/Pets, np. „Pigeon”), a bez niego kolorowa kulka z oczami
-- w kolorze rzadkości. Modele są tylko u gracza (kotwiczone, bez kolizji).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local PetsConfig = require(Shared.Config.Pets)

local PetModels = {}

-- Rzadsze kulki są trochę większe (studs).
local BALL_SIZE = { Common = 1.6, Uncommon = 1.7, Rare = 1.8, Epic = 2, Legendary = 2.2, Mythic = 2.4, Secret = 2.6 }
local GLOW = { Legendary = true, Mythic = true, Secret = true }

local function prepare(model)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
			d.CastShadow = false
		end
	end
	return model
end

local function ball(parent, name, size, cframe, color, material)
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(size, size, size)
	part.CFrame = cframe
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local function placeholder(rarity)
	local size = BALL_SIZE[rarity] or 1.8
	local color = PetsConfig.RarityColors[rarity] or Color3.new(1, 1, 1)
	local model = Instance.new("Model")
	local body = ball(model, "Body", size, CFrame.new(), color)
	-- oczy z przodu (przód modelu to -Z)
	for _, side in ipairs({ -1, 1 }) do
		ball(model, "Eye", size * 0.24, CFrame.new(side * size * 0.2, size * 0.12, -size * 0.4), Color3.fromRGB(25, 20, 35))
		ball(model, "Shine", size * 0.08, CFrame.new(side * size * 0.2 + size * 0.04, size * 0.17, -size * 0.5), Color3.new(1, 1, 1))
	end
	if rarity == "Secret" then
		-- sekret: ciemna kulka ze złotą obręczą
		local ring = Instance.new("Part")
		ring.Name = "Ring"
		ring.Shape = Enum.PartType.Cylinder
		ring.Size = Vector3.new(0.2, size * 1.15, size * 1.15)
		ring.CFrame = CFrame.Angles(0, 0, math.rad(90))
		ring.Color = Color3.fromRGB(255, 200, 60)
		ring.Material = Enum.Material.Neon
		ring.Parent = model
	end
	if GLOW[rarity] then
		local light = Instance.new("PointLight")
		light.Color = color
		light.Range = 8
		light.Brightness = 1.5
		light.Parent = body
	end
	model.PrimaryPart = body
	return prepare(model)
end

-- Model peta (strefa i rzadkość jak w zapisie gracza).
function PetModels.pet(zone, rarity)
	local name = PetsConfig.name(zone, rarity)
	local folder = ReplicatedStorage:FindFirstChild("PetModels")
	local custom = folder and folder:FindFirstChild(name)
	local model
	if custom ~= nil and custom:IsA("Model") then
		model = prepare(custom:Clone())
	else
		model = placeholder(rarity)
	end
	model.Name = name
	return model
end

-- Jajko do animacji otwierania (A białe, B złote).
function PetModels.egg(egg)
	local model = Instance.new("Model")
	local shell = Instance.new("Part")
	shell.Name = "Egg"
	shell.Size = Vector3.new(4.4, 5.6, 4.4)
	shell.CFrame = CFrame.new()
	shell.Material = Enum.Material.SmoothPlastic
	if egg == "B" then
		shell.Color = Color3.fromRGB(255, 196, 60)
	else
		shell.Color = Color3.fromRGB(245, 247, 250)
	end
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = shell
	shell.Parent = model
	model.PrimaryPart = shell
	return prepare(model)
end

-- Ustawia model w ViewportFrame: kamera patrzy na przód modelu z odległości dopasowanej do jego wielkości.
function PetModels.show(viewport, model, distanceScale)
	for _, child in ipairs(viewport:GetChildren()) do
		if child:IsA("Model") or child:IsA("Camera") then
			child:Destroy()
		end
	end
	model:PivotTo(CFrame.new())
	model.Parent = viewport
	local camera = Instance.new("Camera")
	local size = model:GetExtentsSize().Magnitude
	camera.FieldOfView = 40
	camera.CFrame = CFrame.lookAt(Vector3.new(size * 0.35, size * 0.3, -size * (distanceScale or 1.45)), Vector3.new(0, 0, 0))
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	return camera
end

return PetModels
