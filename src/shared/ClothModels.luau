-- Ubrania z klocków (dopóki nie ma rzeczy z katalogu Roblox). Te same kształty służą dwóm celom:
--   • ClothModels.dress(character, items): części przyspawane do ciała gracza (robi to serwer,
--     więc widzą je wszyscy); działa dla R15 i R6,
--   • ClothModels.display(category, rarity, level): model do okienek (okno CLOTHES, boxy).
-- Kolory i kształty są w Config/Clothes. Przód postaci to -Z (tam patrzy twarz).

local ClothesConfig = require(script.Parent.Config.Clothes)

local ClothModels = {}

ClothModels.FolderName = "LarpClothes"

local MANNEQUIN = Color3.fromRGB(233, 226, 216)

-- Golden i Diamond: kolory przesunięte w złoto albo diament (jak u petów)
local LEVEL_LOOK = {
	[1] = { color = Color3.fromRGB(255, 196, 40), mix = 0.75, material = Enum.Material.Foil },
	[2] = { color = Color3.fromRGB(150, 232, 255), mix = 0.72, material = Enum.Material.Glass },
}

local FINISH = {
	Metal = Enum.Material.Foil,
	Ice = Enum.Material.Glass,
	Neon = Enum.Material.Neon,
	Fabric = Enum.Material.Fabric,
}

----------------------------------------------------------------- Ciało
-- Części R15 i ich odpowiedniki w R6: { część R6, środek (część wysokości od środka), wysokość }.
local R6 = {
	Head = { "Head", 0, 1 },
	UpperTorso = { "Torso", 0.2, 0.6 },
	LowerTorso = { "Torso", -0.4, 0.2 },
	LeftUpperArm = { "Left Arm", 0.27, 0.45 },
	LeftLowerArm = { "Left Arm", -0.2, 0.45 },
	LeftHand = { "Left Arm", -0.45, 0.1 },
	RightUpperArm = { "Right Arm", 0.27, 0.45 },
	RightLowerArm = { "Right Arm", -0.2, 0.45 },
	RightHand = { "Right Arm", -0.45, 0.1 },
	LeftUpperLeg = { "Left Leg", 0.25, 0.5 },
	LeftLowerLeg = { "Left Leg", -0.2, 0.4 },
	LeftFoot = { "Left Leg", -0.45, 0.1 },
	RightUpperLeg = { "Right Leg", 0.25, 0.5 },
	RightLowerLeg = { "Right Leg", -0.2, 0.4 },
	RightFoot = { "Right Leg", -0.45, 0.1 },
}

-- Ciało do modeli w okienkach (wymiary jak domyślne R15, studs).
local RIG = {
	Head = { CFrame.new(0, 1.6, 0), Vector3.new(1.2, 1.2, 1.2) },
	UpperTorso = { CFrame.new(0, 0.2, 0), Vector3.new(2, 1.6, 1) },
	LowerTorso = { CFrame.new(0, -0.8, 0), Vector3.new(2, 0.4, 1) },
	LeftUpperArm = { CFrame.new(-1.5, 0.4, 0), Vector3.new(1, 1.2, 1) },
	LeftLowerArm = { CFrame.new(-1.5, -0.7, 0), Vector3.new(1, 1.1, 1) },
	LeftHand = { CFrame.new(-1.5, -1.4, 0), Vector3.new(1, 0.3, 1) },
	RightUpperArm = { CFrame.new(1.5, 0.4, 0), Vector3.new(1, 1.2, 1) },
	RightLowerArm = { CFrame.new(1.5, -0.7, 0), Vector3.new(1, 1.1, 1) },
	RightHand = { CFrame.new(1.5, -1.4, 0), Vector3.new(1, 0.3, 1) },
	LeftUpperLeg = { CFrame.new(-0.5, -1.6, 0), Vector3.new(1, 1.2, 1) },
	LeftLowerLeg = { CFrame.new(-0.5, -2.75, 0), Vector3.new(1, 1.1, 1) },
	LeftFoot = { CFrame.new(-0.5, -3.5, 0), Vector3.new(1, 0.4, 1) },
	RightUpperLeg = { CFrame.new(0.5, -1.6, 0), Vector3.new(1, 1.2, 1) },
	RightLowerLeg = { CFrame.new(0.5, -2.75, 0), Vector3.new(1, 1.1, 1) },
	RightFoot = { CFrame.new(0.5, -3.5, 0), Vector3.new(1, 0.4, 1) },
}

-- Część ciała gracza: (część, przesunięcie środka w jej układzie, wymiary) albo nil.
local function bodyPart(character, name)
	local part = character:FindFirstChild(name)
	if part ~= nil and part:IsA("BasePart") then
		local size = part.Size
		if name == "Head" then
			local mesh = part:FindFirstChildOfClass("SpecialMesh")
			if mesh ~= nil and mesh.MeshType == Enum.MeshType.Head then
				size = Vector3.new(1.2, 1.2, 1.2) -- głowa R6 to klocek 2×1×1 z siatką głowy
			end
		end
		return part, CFrame.new(), size
	end
	local map = R6[name]
	if map == nil then
		return nil
	end
	local r6 = character:FindFirstChild(map[1])
	if r6 == nil or not r6:IsA("BasePart") then
		return nil
	end
	local size = r6.Size
	if map[1] == "Head" then
		size = Vector3.new(1.2, 1.2, 1.2)
		return r6, CFrame.new(), size
	end
	return r6, CFrame.new(0, size.Y * map[2], 0), Vector3.new(size.X, size.Y * map[3], size.Z)
end

----------------------------------------------------------------- Kształty
-- Każda kategoria dodaje części przez add(ciało, kształt, wymiary, położenie, kolor) w układzie
-- części ciała (S = jej wymiary). Kształty: Block, Ball (kula), Egg (spłaszczona kula),
-- Disc (walec osią do przodu) i Ring (walec osią w bok, np. tarcza zegarka).
local BUILD = {}

local FACE_SIDE = CFrame.Angles(0, math.rad(90), 0) -- krzyż na boku (np. rękaw, but) zamiast z przodu

-- Krzyż (jak na ubraniach „chrome”): pionowa belka i krótsza poprzeczka nad środkiem, cienkie
-- w osi Z, więc leżą płasko na przodzie. at = środek krzyża, h = wysokość, depth = grubość.
local function cross(add, body, at, h, role, depth)
	local d = depth or 0.05
	add(body, "Block", Vector3.new(h * 0.22, h, d), at, role)
	add(body, "Block", Vector3.new(h * 0.68, h * 0.22, d), at * CFrame.new(0, h * 0.18, 0), role)
end

function BUILD.Hair(add, S, item)
	local s = S("Head")
	local style = item.Style or "Short"
	if style == "Beanie" then
		add("Head", "Egg", Vector3.new(s.X * 1.14, s.Y * 0.68, s.Z * 1.18), CFrame.new(0, s.Y * 0.3, s.Z * 0.02), "Main")
		add("Head", "Block", Vector3.new(s.X * 1.1, s.Y * 0.16, s.Z * 1.12), CFrame.new(0, s.Y * 0.1, s.Z * 0.02), "Main")
		if item.Crosses then
			cross(add, "Head", CFrame.new(0, s.Y * 0.28, -s.Z * 0.6), s.Y * 0.26, "Accent")
		end
		return
	end
	local h = 0.42
	if style == "Slick" then
		h = 0.5
	elseif style == "Waves" or style == "Flow" then
		h = 0.6
	end
	add("Head", "Egg", Vector3.new(s.X * 1.1, s.Y * h, s.Z * 1.14), CFrame.new(0, s.Y * (0.5 - h * 0.3), s.Z * 0.04), "Main")
	if style ~= "Short" then
		local backH = 0.62
		if style == "Flow" then
			backH = 0.95
		end
		add("Head", "Egg", Vector3.new(s.X * 1.06, s.Y * backH, s.Z * 0.6), CFrame.new(0, s.Y * (0.2 - backH * 0.2), s.Z * 0.3), "Main")
	end
	if style == "Waves" then
		for _, x in ipairs({ -0.22, 0.22 }) do
			add("Head", "Egg", Vector3.new(s.X * 0.48, s.Y * 0.3, s.Z * 0.5), CFrame.new(s.X * x, s.Y * 0.56, -s.Z * 0.12), "Main")
		end
	elseif style == "Flow" then
		for _, x in ipairs({ -0.5, 0.5 }) do
			add("Head", "Egg", Vector3.new(s.X * 0.28, s.Y * 0.85, s.Z * 0.8), CFrame.new(s.X * x, -s.Y * 0.04, s.Z * 0.1), "Main")
		end
	end
end

function BUILD.Glasses(add, S, item)
	local s = S("Head")
	local y = s.Y * 0.1
	local z = -s.Z * 0.53
	if item.Visor then
		add("Head", "Block", Vector3.new(s.X * 0.88, s.Y * 0.2, 0.08), CFrame.new(0, y, z - 0.02), "Main")
		add("Head", "Block", Vector3.new(s.X * 0.92, s.Y * 0.05, 0.12), CFrame.new(0, y + s.Y * 0.11, z), "Accent")
	else
		local d = s.Y * 0.3
		for _, x in ipairs({ -0.21, 0.21 }) do
			add("Head", "Disc", Vector3.new(0.06, d, d), CFrame.new(s.X * x, y, z - 0.02), "Main")
			add("Head", "Disc", Vector3.new(0.04, d + 0.07, d + 0.07), CFrame.new(s.X * x, y, z + 0.01), "Accent")
		end
		add("Head", "Block", Vector3.new(s.X * 0.14, 0.05, 0.05), CFrame.new(0, y + s.Y * 0.05, z), "Accent")
	end
	for _, x in ipairs({ -0.43, 0.43 }) do
		add("Head", "Block", Vector3.new(0.05, 0.05, s.Z * 0.55), CFrame.new(s.X * x, y + 0.02, z + s.Z * 0.27), "Accent")
		if item.Crosses then
			local side = 1
			if x < 0 then
				side = -1
			end
			cross(add, "Head", CFrame.new(s.X * (x + side * 0.03), y + 0.02, z + s.Z * 0.3) * FACE_SIDE, 0.2, "Accent", 0.03)
		end
	end
end

function BUILD.Chain(add, S, item, slot)
	local s = S("UpperTorso")
	local k = 1
	if slot == 2 then
		k = 1.32 -- drugi łańcuch (Double Chain) wisi niżej
	end
	local d = 0.13 * (item.Links or 1)
	local rx, ry = s.X * 0.22 * k, s.Y * 0.3 * k
	local top = s.Y * 0.5 - 0.04
	local z = -s.Z * 0.5 - d * 0.3
	local n = 11
	for i = 1, n do
		local a = math.rad(-75 + 150 * (i - 1) / (n - 1))
		add("UpperTorso", "Ball", Vector3.new(d, d, d), CFrame.new(math.sin(a) * rx, top - math.cos(a) * ry, z), "Accent")
	end
	local bottom = top - ry
	if item.Pendant == "Gem" then
		add("UpperTorso", "Ball", Vector3.new(0.3, 0.3, 0.3), CFrame.new(0, bottom - 0.17, z - 0.02), "Main")
	elseif item.Pendant == "Plate" then
		add("UpperTorso", "Block", Vector3.new(0.42, 0.42, 0.08), CFrame.new(0, bottom - 0.24, z), "Main")
		add("UpperTorso", "Block", Vector3.new(0.48, 0.48, 0.06), CFrame.new(0, bottom - 0.24, z + 0.02), "Accent")
	elseif item.Pendant == "Cross" then
		cross(add, "UpperTorso", CFrame.new(0, bottom - 0.34, z - 0.01), 0.56, "Main", 0.09)
	end
end

function BUILD.Watch(add, S, item, slot)
	local arm, side = "LeftLowerArm", -1
	if slot == 2 then
		arm, side = "RightLowerArm", 1 -- drugi zegarek (Double Wrist) na prawej ręce
	end
	local s = S(arm)
	local y = -s.Y * 0.38
	add(arm, "Block", Vector3.new(s.X * 1.1, s.Y * 0.16, s.Z * 1.1), CFrame.new(0, y, 0), "Main")
	add(arm, "Ring", Vector3.new(0.1, 0.44, 0.44), CFrame.new(side * s.X * 0.56, y, 0), "Accent")
	add(arm, "Ring", Vector3.new(0.06, 0.52, 0.52), CFrame.new(side * s.X * 0.53, y, 0), "Main")
	if item.Crosses then
		cross(add, arm, CFrame.new(side * s.X * 0.62, y, 0) * FACE_SIDE, 0.26, "Main", 0.03)
	end
end

function BUILD.Shirt(add, S, item)
	local t = S("UpperTorso")
	local bulk = 1
	if item.Bulky then
		bulk = 1.1
	end
	add("UpperTorso", "Block", Vector3.new(t.X * 1.06 * bulk, t.Y * 1.04, t.Z * 1.12 * bulk), CFrame.new(), "Main")
	local l = S("LowerTorso")
	add("LowerTorso", "Block", Vector3.new(l.X * 1.06 * bulk, l.Y * 1.12, l.Z * 1.12 * bulk), CFrame.new(), "Main")
	-- kołnierzyk i wstawki z przodu
	local front = -t.Z * 0.56 * bulk
	add("UpperTorso", "Block", Vector3.new(t.X * 0.38, t.Y * 0.1, 0.1), CFrame.new(0, t.Y * 0.47, front), "Accent")
	if item.Sleeves == "Long" then
		add("UpperTorso", "Block", Vector3.new(0.08, t.Y * 0.9, 0.06), CFrame.new(0, -t.Y * 0.04, front - 0.01), "Accent")
	end
	if item.Dots then
		for _, p in ipairs({ { -0.28, 0.2 }, { 0.22, 0.28 }, { 0.3, -0.18 }, { -0.18, -0.26 } }) do
			add("UpperTorso", "Disc", Vector3.new(0.04, 0.32, 0.32), CFrame.new(t.X * p[1], t.Y * p[2], front - 0.01), "Accent")
		end
	end
	if item.Crosses then
		cross(add, "UpperTorso", CFrame.new(0, -t.Y * 0.02, front - 0.02), t.Y * 0.5, "Accent")
	end
	if item.Sleeves == "Short" then
		for _, arm in ipairs({ "LeftUpperArm", "RightUpperArm" }) do
			local a = S(arm)
			add(arm, "Block", Vector3.new(a.X * 1.12 * bulk, a.Y * 0.6, a.Z * 1.12 * bulk), CFrame.new(0, a.Y * 0.2, 0), "Main")
		end
	elseif item.Sleeves == "Long" then
		for _, arm in ipairs({ "LeftUpperArm", "RightUpperArm" }) do
			local a = S(arm)
			add(arm, "Block", Vector3.new(a.X * 1.12 * bulk, a.Y * 1.04, a.Z * 1.12 * bulk), CFrame.new(), "Main")
		end
		for _, arm in ipairs({ "LeftLowerArm", "RightLowerArm" }) do
			local a = S(arm)
			add(arm, "Block", Vector3.new(a.X * 1.1 * bulk, a.Y * 0.9, a.Z * 1.1 * bulk), CFrame.new(0, a.Y * 0.05, 0), "Main")
		end
		-- krzyże wzdłuż rękawów, po zewnętrznej stronie
		if item.Crosses then
			for _, arm in ipairs({ "LeftUpperArm", "LeftLowerArm", "RightUpperArm", "RightLowerArm" }) do
				local a = S(arm)
				local side = 1
				if string.sub(arm, 1, 4) == "Left" then
					side = -1
				end
				cross(add, arm, CFrame.new(side * a.X * 0.58 * bulk, 0, 0) * FACE_SIDE, a.Y * 0.5, "Accent", 0.04)
			end
		end
	end
end

function BUILD.Pants(add, S, item)
	local l = S("LowerTorso")
	add("LowerTorso", "Block", Vector3.new(l.X * 1.1, l.Y * 1.1, l.Z * 1.14), CFrame.new(), "Main")
	add("LowerTorso", "Block", Vector3.new(l.X * 1.13, l.Y * 0.42, l.Z * 1.17), CFrame.new(0, l.Y * 0.3, 0), "Accent")
	for _, leg in ipairs({ "LeftUpperLeg", "RightUpperLeg" }) do
		local s = S(leg)
		add(leg, "Block", Vector3.new(s.X * 1.1, s.Y * 1.02, s.Z * 1.1), CFrame.new(), "Main")
	end
	if item.Long then
		for _, leg in ipairs({ "LeftLowerLeg", "RightLowerLeg" }) do
			local s = S(leg)
			add(leg, "Block", Vector3.new(s.X * 1.1, s.Y * 0.98, s.Z * 1.1), CFrame.new(0, s.Y * 0.02, 0), "Main")
		end
	end
	-- naszywki w krzyże z przodu nogawek
	if item.Crosses then
		local legs = { "LeftUpperLeg", "RightUpperLeg" }
		if item.Long then
			legs = { "LeftUpperLeg", "RightUpperLeg", "LeftLowerLeg", "RightLowerLeg" }
		end
		for _, leg in ipairs(legs) do
			local s = S(leg)
			cross(add, leg, CFrame.new(0, 0, -s.Z * 0.57), s.Y * 0.42, "Accent")
		end
	end
end

function BUILD.Shoes(add, S, item)
	for _, foot in ipairs({ "LeftFoot", "RightFoot" }) do
		local s = S(foot)
		if item.Flat then
			add(foot, "Block", Vector3.new(s.X * 1.1, s.Y * 0.35, s.Z * 1.2), CFrame.new(0, -s.Y * 0.38, -s.Z * 0.06), "Accent")
			add(foot, "Block", Vector3.new(s.X * 1.12, s.Y * 0.3, s.Z * 0.3), CFrame.new(0, -s.Y * 0.08, -s.Z * 0.22), "Main")
		else
			add(foot, "Block", Vector3.new(s.X * 1.14, s.Y * 1.15, s.Z * 1.2), CFrame.new(0, s.Y * 0.05, -s.Z * 0.06), "Main")
			add(foot, "Block", Vector3.new(s.X * 1.18, s.Y * 0.36, s.Z * 1.26), CFrame.new(0, -s.Y * 0.5, -s.Z * 0.08), "Accent")
			if item.Crosses then
				local side = 1
				if foot == "LeftFoot" then
					side = -1
				end
				cross(add, foot, CFrame.new(side * s.X * 0.59, s.Y * 0.12, -s.Z * 0.06) * FACE_SIDE, s.Y * 0.8, "Accent", 0.03)
			end
		end
	end
end

----------------------------------------------------------------- Części
local function look(item, level, role)
	local color = item[role] or item.Main
	local finish = item.Finish
	if role == "Accent" then
		-- drugi kolor ma to samo wykończenie, ale nie świeci (np. oprawka wizjera), chyba że
		-- ubranie mówi inaczej (AccentFinish, np. świecąca tarcza zegarka)
		finish = item.AccentFinish
		if finish == nil and item.Finish ~= "Neon" and item.Finish ~= "Fabric" then
			finish = item.Finish
		end
	end
	local material = FINISH[finish] or Enum.Material.SmoothPlastic
	local lvl = LEVEL_LOOK[level or 0]
	if lvl ~= nil then
		color = color:Lerp(lvl.color, lvl.mix)
		if material ~= Enum.Material.Neon then
			material = lvl.material
		end
	end
	return color, material
end

local SHAPE_TURN = {
	Disc = CFrame.Angles(0, math.rad(90), 0), -- walec ma oś X; obrót kładzie ją do przodu
}

local function makePart(shape, size, color, material)
	local part = Instance.new("Part")
	part.Name = "Cloth"
	part.Anchored = false
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Massless = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Color = color
	part.Material = material
	if material == Enum.Material.Glass then
		part.Reflectance = 0.15
	end
	if shape == "Ball" then
		part.Shape = Enum.PartType.Ball
		part.Size = size
	elseif shape == "Disc" or shape == "Ring" then
		part.Shape = Enum.PartType.Cylinder
		part.Size = size
	elseif shape == "Egg" then
		part.Size = size
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = part
	else
		part.Size = size
	end
	return part
end

local function buildWith(category, rarity, level, slot, sizeOf, place)
	local build = BUILD[category]
	if build == nil then
		return
	end
	local item = ClothesConfig.item(category, rarity)
	local function add(body, shape, size, offset, role)
		local color, material = look(item, level, role)
		local part = makePart(shape, size, color, material)
		place(part, body, offset * (SHAPE_TURN[shape] or CFrame.new()))
	end
	build(add, sizeOf, item, slot or 1)
end

----------------------------------------------------------------- Na postaci
-- Ukrywa włosy gracza, gdy nosi włosy z gry (i pokazuje je z powrotem).
local function setOwnHairHidden(character, hidden)
	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Accessory") and child.AccessoryType == Enum.AccessoryType.Hair then
			local handle = child:FindFirstChild("Handle")
			if handle ~= nil and handle:IsA("BasePart") then
				if hidden then
					if handle:GetAttribute("LarpHairShown") == nil then
						handle:SetAttribute("LarpHairShown", handle.Transparency)
					end
					handle.Transparency = 1
				elseif handle:GetAttribute("LarpHairShown") ~= nil then
					handle.Transparency = handle:GetAttribute("LarpHairShown")
					handle:SetAttribute("LarpHairShown", nil)
				end
			end
		end
	end
end
ClothModels.setOwnHairHidden = setOwnHairHidden

-- Zdejmuje ubrania z gry z postaci.
function ClothModels.undress(character)
	local old = character:FindFirstChild(ClothModels.FolderName)
	if old ~= nil then
		old:Destroy()
	end
	setOwnHairHidden(character, false)
end

-- Ubiera postać. items = lista { Category, Rarity, Level, Slot } (Slot 2 = drugi łańcuch albo
-- zegarek). Części są przyspawane do ciała, bez kolizji i bez masy.
function ClothModels.dress(character, items)
	ClothModels.undress(character)
	local folder = Instance.new("Folder")
	folder.Name = ClothModels.FolderName
	local hasHair = false
	for _, entry in ipairs(items) do
		if entry.Category == "Hair" then
			hasHair = true
		end
		local function sizeOf(name)
			local _, _, size = bodyPart(character, name)
			return size or (RIG[name] and RIG[name][2]) or Vector3.new(1, 1, 1)
		end
		buildWith(entry.Category, entry.Rarity, entry.Level, entry.Slot, sizeOf, function(part, body, offset)
			local base, baseOffset = bodyPart(character, body)
			if base == nil then
				part:Destroy()
				return
			end
			part.CFrame = base.CFrame * baseOffset * offset
			local weld = Instance.new("Weld")
			weld.Part0 = base
			weld.Part1 = part
			weld.C0 = baseOffset * offset
			weld.Parent = part
			part.Parent = folder
		end)
	end
	folder.Parent = character
	setOwnHairHidden(character, hasHair)
	return folder
end

----------------------------------------------------------------- Do okienek
-- Model ubrania do ViewportFrame (środek modelu w punkcie 0). Włosy i okulary dostają głowę
-- manekina, żeby było widać, co to jest.
function ClothModels.display(category, rarity, level)
	local model = Instance.new("Model")
	model.Name = ClothesConfig.name(category, rarity)
	if category == "Hair" or category == "Glasses" then
		local head = Instance.new("Part")
		head.Name = "Mannequin"
		head.Shape = Enum.PartType.Ball
		head.Size = RIG.Head[2]
		head.CFrame = RIG.Head[1]
		head.Color = MANNEQUIN
		head.Material = Enum.Material.SmoothPlastic
		head.Anchored = true
		head.Parent = model
	end
	local function sizeOf(name)
		return (RIG[name] and RIG[name][2]) or Vector3.new(1, 1, 1)
	end
	buildWith(category, rarity, level, 1, sizeOf, function(part, body, offset)
		local rig = RIG[body]
		part.Anchored = true
		part.CFrame = (rig and rig[1] or CFrame.new()) * offset
		part.Parent = model
	end)
	local box = model:GetBoundingBox()
	model.WorldPivot = CFrame.new(box.Position)
	return model
end

----------------------------------------------------------------- Mystery box
-- Pudełko prezentowe ze wstążką (stoisko w Mall i animacja otwierania). Dół na wysokości 0, środek
-- w osi Y. Części wieka mają atrybut Lid (w animacji wieko odlatuje).
function ClothModels.box(boxName)
	local look = ClothesConfig.Boxes[boxName] or ClothesConfig.Boxes.Street
	local model = Instance.new("Model")
	model.Name = look.Name or boxName
	local bodyMaterial = FINISH[look.Finish] or Enum.Material.SmoothPlastic
	local ribbonMaterial = FINISH[look.RibbonFinish] or Enum.Material.SmoothPlastic
	local function part(name, size, cframe, color, material, lid, shape)
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.Size = size
		p.CFrame = cframe
		p.Color = color
		p.Material = material
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		if material == Enum.Material.Glass then
			p.Reflectance = 0.15
		end
		if shape ~= nil then
			p.Shape = shape
		end
		if lid then
			p:SetAttribute("Lid", true)
		end
		p.Parent = model
		return p
	end
	part("Box", Vector3.new(3.6, 3, 3.6), CFrame.new(0, 1.5, 0), look.Color, bodyMaterial)
	part("RibbonX", Vector3.new(3.7, 3.02, 0.6), CFrame.new(0, 1.5, 0), look.Ribbon, ribbonMaterial)
	part("RibbonZ", Vector3.new(0.6, 3.02, 3.7), CFrame.new(0, 1.5, 0), look.Ribbon, ribbonMaterial)
	part("Lid", Vector3.new(4, 0.8, 4), CFrame.new(0, 3.4, 0), look.Color, bodyMaterial, true)
	part("LidRibbonX", Vector3.new(4.06, 0.84, 0.62), CFrame.new(0, 3.4, 0), look.Ribbon, ribbonMaterial, true)
	part("LidRibbonZ", Vector3.new(0.62, 0.84, 4.06), CFrame.new(0, 3.4, 0), look.Ribbon, ribbonMaterial, true)
	for _, side in ipairs({ -1, 1 }) do
		part("Bow", Vector3.new(1.2, 1.2, 1.2), CFrame.new(side * 0.55, 4.25, 0), look.Ribbon, ribbonMaterial, true, Enum.PartType.Ball)
	end
	model.WorldPivot = CFrame.new()
	return model
end

return ClothModels
