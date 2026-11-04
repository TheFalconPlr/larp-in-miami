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

-- Wygląd po łączeniu: Złoty (1) i Diamentowy (2). mix = ile koloru poziomu w kolorze części.
local LEVEL_LOOK = {
	[1] = { color = Color3.fromRGB(255, 196, 40), material = Enum.Material.Foil, mix = 0.8, light = Color3.fromRGB(255, 210, 90) },
	[2] = { color = Color3.fromRGB(150, 232, 255), material = Enum.Material.Glass, mix = 0.78, light = Color3.fromRGB(150, 232, 255) },
}

-- Barwi peta na złoto albo diament. Oczy kulki (Eye, Shine) i części z atrybutem KeepColor
-- (np. oczy we własnym modelu) zostają bez zmian.
local function applyLevel(model, level)
	local look = LEVEL_LOOK[level]
	if look == nil then
		return
	end
	local biggest = nil
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d.Name ~= "Eye" and d.Name ~= "Shine" and not d:GetAttribute("KeepColor") then
			d.Color = d.Color:Lerp(look.color, look.mix)
			d.Material = look.material
			if biggest == nil or d.Size.Magnitude > biggest.Size.Magnitude then
				biggest = d
			end
		end
	end
	if biggest ~= nil then
		local light = Instance.new("PointLight")
		light.Color = look.light
		light.Range = 7
		light.Brightness = 1.2
		light.Parent = biggest
	end
end

-- Model peta (strefa, rzadkość i poziom jak w zapisie gracza; poziom 1 złoty, 2 diamentowy).
function PetModels.pet(zone, rarity, level)
	local name = PetsConfig.name(zone, rarity)
	local folder = ReplicatedStorage:FindFirstChild("PetModels")
	local custom = folder and folder:FindFirstChild(name)
	local model
	if custom ~= nil and custom:IsA("Model") then
		model = prepare(custom:Clone())
	else
		model = placeholder(rarity)
	end
	applyLevel(model, level or 0)
	model.Name = name
	return model
end

local EGG_SIZE = Vector3.new(4.4, 5.6, 4.4)
local EGG_COLORS = {
	A = Color3.fromRGB(245, 247, 250),
	B = Color3.fromRGB(255, 196, 60),
}
local CRACK_COLORS = {
	A = Color3.fromRGB(70, 72, 92),
	B = Color3.fromRGB(110, 62, 18),
}
-- Rysa na przodzie jajka: zygzak w poprzek (x, y w studs od środka). Pojawia się w 3 etapach,
-- po 2 odcinki na każde pęknięcie.
local CRACK_POINTS = {
	{ -1.8, 0.3 },
	{ -1.2, -0.1 },
	{ -0.62, 0.42 },
	{ 0, -0.02 },
	{ 0.6, 0.48 },
	{ 1.18, 0.02 },
	{ 1.8, 0.38 },
}

function PetModels.eggColor(egg)
	return EGG_COLORS[egg] or EGG_COLORS.A
end

-- Punkt na powierzchni jajka (elipsoida) od strony kamery (-Z), trochę nad skorupką.
local function surfacePoint(x, y)
	local half = EGG_SIZE / 2
	local k = 1 - (x / half.X) ^ 2 - (y / half.Y) ^ 2
	local z = -half.Z * math.sqrt(math.max(0, k))
	return Vector3.new(x, y, z) * 1.03
end

-- Jajko do animacji otwierania (A białe, B złote) z ukrytymi rysami (PetModels.crack).
function PetModels.egg(egg)
	local model = Instance.new("Model")
	local shell = Instance.new("Part")
	shell.Name = "Egg"
	shell.Size = EGG_SIZE
	shell.CFrame = CFrame.new()
	shell.Material = Enum.Material.SmoothPlastic
	shell.Color = PetModels.eggColor(egg)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = shell
	shell.Parent = model
	for i = 1, #CRACK_POINTS - 1 do
		local a = surfacePoint(CRACK_POINTS[i][1], CRACK_POINTS[i][2])
		local b = surfacePoint(CRACK_POINTS[i + 1][1], CRACK_POINTS[i + 1][2])
		local crack = Instance.new("Part")
		crack.Name = "Crack"
		crack.Size = Vector3.new(0.17, 0.17, (b - a).Magnitude + 0.14)
		crack.CFrame = CFrame.lookAt((a + b) / 2, b)
		crack.Color = CRACK_COLORS[egg] or CRACK_COLORS.A
		crack.Material = Enum.Material.SmoothPlastic
		crack.Transparency = 1
		crack:SetAttribute("CrackStage", math.ceil(i / 2))
		crack.Parent = model
	end
	model.PrimaryPart = shell
	return prepare(model)
end

-- Pokazuje rysy do danego pęknięcia (1–3; 0 = całe jajko).
function PetModels.crack(model, stage)
	for _, d in ipairs(model:GetDescendants()) do
		local crackStage = d:GetAttribute("CrackStage")
		if crackStage ~= nil and d:IsA("BasePart") then
			if crackStage <= stage then
				d.Transparency = 0
			else
				d.Transparency = 1
			end
		end
	end
end

-- Jajko na kupce monet (okno kupna).
local COINS = {
	-- x, z, ile monet w stosie
	{ -2.3, -0.7, 3 },
	{ 2.1, -1.0, 2 },
	{ -1.0, -2.1, 1 },
	{ 1.0, -2.3, 2 },
	{ 2.9, 0.7, 1 },
	{ -2.9, 1.0, 2 },
}

function PetModels.eggWithCoins(egg)
	local model = PetModels.egg(egg)
	local bottom = -EGG_SIZE.Y / 2
	for _, stack in ipairs(COINS) do
		for n = 1, stack[3] do
			local coin = Instance.new("Part")
			coin.Name = "Coin"
			coin.Shape = Enum.PartType.Cylinder
			coin.Size = Vector3.new(0.32, 1.7, 1.7)
			coin.CFrame = CFrame.new(stack[1], bottom + 0.16 + (n - 1) * 0.33, stack[2])
				* CFrame.Angles(0, math.rad(n * 17), math.rad(90))
			coin.Color = Color3.fromRGB(255, 200, 50)
			coin.Material = Enum.Material.SmoothPlastic
			coin.Parent = model
		end
	end
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
