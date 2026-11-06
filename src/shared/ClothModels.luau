-- Ubrania z klocków (dopóki nie ma rzeczy z katalogu Roblox). Te same kształty służą dwóm celom:
--   • ClothModels.dress(character, items): części przyspawane do ciała gracza (robi to serwer,
--     więc widzą je wszyscy); działa dla R15 i R6,
--   • ClothModels.display(category, rarity, level): model do okienek (okno CLOTHES, boxy).
-- Kolory i kształty są w Config/Clothes. Przód postaci to -Z (tam patrzy twarz), prawa ręka to +X.
--
-- Wygląd: zaokrąglone krawędzie (rbox: dwa klocki i cztery walce na rogach), elipsoidy na włosy
-- i pianki, lamówki, mankiety, kołnierzyki, guziki, sznurówki i podeszwy. Ubranie odstaje od ciała
-- o GAP, więc zakrywa też kanciaste części R15 (róg zaokrąglenia mieści się w odstępie).

local ClothesConfig = require(script.Parent.Config.Clothes)

local ClothModels = {}

ClothModels.FolderName = "LarpClothes"

local MANNEQUIN = Color3.fromRGB(233, 226, 216)
local BLACK = Color3.new(0, 0, 0)
local WHITE = Color3.new(1, 1, 1)
local SILVER = Color3.fromRGB(214, 220, 230)
local GOLD = Color3.fromRGB(255, 194, 56)
local GAP = 0.06 -- grubość materiału: tyle ubranie odstaje od ciała (studs)
local IDENTITY = CFrame.new()

-- Golden i Diamond: kolory przesunięte w złoto albo diament (jak u petów)
local LEVEL_LOOK = {
	[1] = { color = Color3.fromRGB(255, 196, 40), mix = 0.75, material = Enum.Material.Foil, reflectance = 0 },
	[2] = { color = Color3.fromRGB(150, 232, 255), mix = 0.72, material = Enum.Material.Glass, reflectance = 0.15 },
}

-- Wykończenie: materiał i połysk (Reflectance)
local FINISH = {
	Metal = { Enum.Material.Foil, 0 }, -- metal z połyskiem (biżuteria, klamry)
	Ice = { Enum.Material.Glass, 0.15 }, -- lód i diamenty
	Neon = { Enum.Material.Neon, 0 }, -- świeci
	Fabric = { Enum.Material.Fabric, 0 }, -- materiał
	Gloss = { Enum.Material.SmoothPlastic, 0.2 }, -- połysk (żel na włosach, lakierowana skóra)
	Satin = { Enum.Material.SmoothPlastic, 0.08 }, -- jedwab i satyna
}

----------------------------------------------------------------- Ciało
-- Części R15 i ich odpowiedniki w R6: { część R6, środek (część wysokości od środka), wysokość }.
-- Kawałki jednej części R6 stykają się (koszula i spodnie na R6 nie zostawiają paska skóry).
local R6 = {
	Head = { "Head", 0, 1 },
	UpperTorso = { "Torso", 0.1, 0.8 },
	LowerTorso = { "Torso", -0.4, 0.2 },
	LeftUpperArm = { "Left Arm", 0.275, 0.45 },
	LeftLowerArm = { "Left Arm", -0.175, 0.45 },
	LeftHand = { "Left Arm", -0.45, 0.1 },
	RightUpperArm = { "Right Arm", 0.275, 0.45 },
	RightLowerArm = { "Right Arm", -0.175, 0.45 },
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
	LeftLowerArm = { CFrame.new(-1.5, -0.75, 0), Vector3.new(1, 1.1, 1) },
	LeftHand = { CFrame.new(-1.5, -1.45, 0), Vector3.new(1, 0.3, 1) },
	RightUpperArm = { CFrame.new(1.5, 0.4, 0), Vector3.new(1, 1.2, 1) },
	RightLowerArm = { CFrame.new(1.5, -0.75, 0), Vector3.new(1, 1.1, 1) },
	RightHand = { CFrame.new(1.5, -1.45, 0), Vector3.new(1, 0.3, 1) },
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

----------------------------------------------------------------- Kolory i materiały
-- Role kolorów: Main, Accent, Detail (trzeci kolor, np. środek kwiatka), Dark i Light (główny
-- ciemniej i jaśniej: szwy, lamówki, cienie), Metal (srebrne dodatki), Gold, Lens (szkła okularów),
-- White (np. sznurówki).
local function roleColor(item, role)
	if role == "Accent" then
		return item.Accent or item.Main
	elseif role == "Detail" then
		return item.Detail or item.Accent or item.Main
	elseif role == "Dark" then
		return item.Main:Lerp(BLACK, 0.3)
	elseif role == "Light" then
		return item.Main:Lerp(WHITE, 0.4)
	elseif role == "Metal" then
		return item.Metal or SILVER
	elseif role == "Gold" then
		return GOLD
	elseif role == "Lens" then
		return item.Lens or item.Main
	elseif role == "White" then
		return WHITE
	end
	return item.Main
end

local function roleFinish(item, role)
	if role == "Main" or role == "Dark" or role == "Light" then
		return item.Finish
	elseif role == "Accent" then
		if item.AccentFinish ~= nil then
			return item.AccentFinish
		end
		if item.Finish ~= "Neon" and item.Finish ~= "Fabric" then
			return item.Finish
		end
		return nil
	elseif role == "Detail" then
		return item.DetailFinish or item.AccentFinish
	elseif role == "Metal" or role == "Gold" then
		return "Metal"
	elseif role == "Lens" then
		return item.LensFinish or "Ice"
	end
	return nil
end

local function look(item, level, role, finish)
	local color = roleColor(item, role)
	local f = FINISH[finish or roleFinish(item, role) or ""]
	local material, reflectance = Enum.Material.SmoothPlastic, 0
	if f ~= nil then
		material, reflectance = f[1], f[2]
	end
	local lvl = LEVEL_LOOK[level or 0]
	if lvl ~= nil then
		color = color:Lerp(lvl.color, lvl.mix)
		if material ~= Enum.Material.Neon then
			material, reflectance = lvl.material, lvl.reflectance
		end
	end
	return color, material, reflectance
end

----------------------------------------------------------------- Części
-- Kształty: Block, Ball (kula), Egg (elipsoida), Disc (walec osią do przodu), Ring (walec osią
-- w bok), Rod (walec pionowy), Wedge (klin: wysoki z tyłu, płaski z przodu).
-- Walec: Size.X to długość wzdłuż osi, Y i Z to średnica.
local SHAPE_TURN = {
	Disc = CFrame.Angles(0, math.rad(90), 0),
	Rod = CFrame.Angles(0, 0, math.rad(90)),
}

local function makePart(shape, size, color, material, reflectance)
	local part
	if shape == "Wedge" then
		part = Instance.new("WedgePart")
	else
		part = Instance.new("Part")
	end
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
	part.Reflectance = reflectance or 0
	if shape == "Ball" then
		part.Shape = Enum.PartType.Ball
	elseif shape == "Disc" or shape == "Ring" or shape == "Rod" then
		part.Shape = Enum.PartType.Cylinder
	elseif shape == "Egg" then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = part
	end
	part.Size = size
	return part
end

----------------------------------------------------------------- Pędzel
-- Każda kategoria rysuje „pędzlem” P w układzie części ciała (P.S(nazwa) = jej wymiary):
--   P.add(ciało, kształt, wymiary, położenie, rola, [wykończenie])
--   P.rbox(ciało, wymiary, położenie, rola, promień, [wykończenie])  klocek z zaokrąglonymi
--     pionowymi krawędziami (2 klocki i 4 walce); przy promieniu poniżej 0,06 (cienkie płytki,
--     kieszenie, języczki) zwykły klocek, bo takiego zaokrąglenia i tak nie widać, a to 5 części mniej
local function newBrush(item, level, sizeOf, place, ctx)
	local P = { S = sizeOf, item = item, ctx = ctx or {} }
	function P.add(body, shape, size, offset, role, finish)
		local color, material, reflectance
		if role == "Skin" then
			-- kolor skóry gracza (dekolt), bez złota i diamentu
			color, material, reflectance = P.ctx.skin or MANNEQUIN, Enum.Material.SmoothPlastic, 0
		else
			color, material, reflectance = look(item, level, role, finish)
		end
		local part = makePart(shape, size, color, material, reflectance)
		place(part, body, offset * (SHAPE_TURN[shape] or IDENTITY))
		return part
	end
	function P.rbox(body, size, offset, role, r, finish)
		r = math.min(r or 0.15, size.X / 2 - 0.005, size.Z / 2 - 0.005)
		if r < 0.06 then
			P.add(body, "Block", size, offset, role, finish)
			return
		end
		P.add(body, "Block", Vector3.new(size.X, size.Y, size.Z - 2 * r), offset, role, finish)
		P.add(body, "Block", Vector3.new(size.X - 2 * r, size.Y, size.Z), offset, role, finish)
		for _, sx in ipairs({ -1, 1 }) do
			for _, sz in ipairs({ -1, 1 }) do
				local corner = offset * CFrame.new(sx * (size.X / 2 - r), 0, sz * (size.Z / 2 - r))
				P.add(body, "Rod", Vector3.new(size.Y, 2 * r, 2 * r), corner, role, finish)
			end
		end
	end
	return P
end

-- Krzyż leżący płasko (cienki w osi Z). at = środek, h = wysokość. fancy: kulki na końcach.
local function cross(P, body, at, h, role, depth, fancy)
	local d = depth or 0.05
	local w = h * 0.2
	P.add(body, "Block", Vector3.new(w, h, d), at, role)
	P.add(body, "Block", Vector3.new(h * 0.66, w, d), at * CFrame.new(0, h * 0.17, 0), role)
	if fancy then
		local b = w * 1.7
		for _, p in ipairs({ { 0, h / 2 }, { 0, -h / 2 }, { -h * 0.33, h * 0.17 }, { h * 0.33, h * 0.17 } }) do
			P.add(body, "Ball", Vector3.new(b, b, b), at * CFrame.new(p[1], p[2], 0), role)
		end
	end
end

-- Kwiatek (koszula hawajska): dwa płatki na krzyż i środek. at = środek, k = wielkość.
local function flower(P, body, at, k)
	P.add(body, "Egg", Vector3.new(0.36 * k, 0.13 * k, 0.03), at, "Accent")
	P.add(body, "Egg", Vector3.new(0.13 * k, 0.36 * k, 0.03), at, "Accent")
	P.add(body, "Ball", Vector3.new(0.1 * k, 0.1 * k, 0.1 * k), at * CFrame.new(0, 0, -0.02), "Detail")
end

-- Pasek z rogów: klocek obrócony wokół osi Z o kąt a (stopnie). Do kołnierzyków i dekoltów.
local function slant(P, body, size, at, a, role)
	P.add(body, "Block", size, at * CFrame.Angles(0, 0, math.rad(a)), role)
end

-- Trójkąt prostokątny leżący płasko na przodzie (klin). Kąt prosty w punkcie at, jedna
-- przyprostokątna w bok (dir = -1 w lewo, 1 w prawo) o długości w, druga w dół o długości h.
local function triangle(P, body, at, w, h, dir, role, depth)
	local d = depth or 0.03
	local turn = CFrame.fromMatrix(Vector3.new(dir * w / 2, -h / 2, 0), Vector3.new(0, 0, -dir), Vector3.new(0, -1, 0), Vector3.new(-dir, 0, 0))
	P.add(body, "Wedge", Vector3.new(d, h, w), at * turn, role)
end

-- Dekolt w kształcie V od szyi (szerokość 2·w na górze) w dół na głębokość h: skóra w środku
-- i lamówka wzdłuż brzegów. Zwraca kąt brzegu (stopnie), żeby dołożyć do niego wyłogi.
local function vNeck(P, body, top, front, w, h, trimRole)
	for _, dir in ipairs({ -1, 1 }) do
		triangle(P, body, CFrame.new(0, top, front - 0.005), w, h, dir, "Skin", 0.02)
	end
	local len = math.sqrt(w * w + h * h)
	local a = math.deg(math.atan2(w, h))
	for _, side in ipairs({ -1, 1 }) do
		slant(P, body, Vector3.new(0.07, len + 0.04, 0.03), CFrame.new(side * w / 2, top - h / 2, front - 0.02), -side * a, trimRole)
	end
	return a
end

-- Cyfry jak na wyświetlaczu (7 odcinków): a góra, b prawa górna, c prawa dolna, d dół, e lewa dolna,
-- f lewa górna, g środek. Numer na koszulce koszykarskiej.
local DIGITS = {
	["0"] = "abcdef", ["1"] = "bc", ["2"] = "abged", ["3"] = "abgcd", ["4"] = "fgbc", ["5"] = "afgcd",
	["6"] = "afgedc", ["7"] = "abc", ["8"] = "abcdefg", ["9"] = "abcdfg",
}
local function number(P, body, at, text, h, role)
	local w = h * 0.55
	local t = h * 0.15
	local step = w + h * 0.22
	local x0 = -(string.len(text) - 1) * step / 2
	for i = 1, string.len(text) do
		local segs = DIGITS[string.sub(text, i, i)] or ""
		local cx = x0 + (i - 1) * step
		local function seg(name, x, y, sx, sy)
			if string.find(segs, name, 1, true) then
				P.add(body, "Block", Vector3.new(sx, sy, 0.03), at * CFrame.new(cx + x, y, 0), role)
			end
		end
		seg("a", 0, h / 2 - t / 2, w, t)
		seg("g", 0, 0, w, t)
		seg("d", 0, -h / 2 + t / 2, w, t)
		seg("f", -w / 2 + t / 2, h / 4, t, h / 2)
		seg("b", w / 2 - t / 2, h / 4, t, h / 2)
		seg("e", -w / 2 + t / 2, -h / 4, t, h / 2)
		seg("c", w / 2 - t / 2, -h / 4, t, h / 2)
	end
end

----------------------------------------------------------------- Kategorie
local BUILD = {}

--------------------------------------------------------------- Włosy
-- Style: Buzz (krótko), Fade (wysoko na górze, krótko po bokach), Slick (zaczesane do tyłu z żelem),
-- Curls (loki), Flow (długie do ramion), Beanie (czapka z wywiniętym brzegiem).
-- Każda fryzura to kilka elipsoid: tył i boki (do karku), kopuła na czubku i grzywka nad czołem
-- (bez niej przy czole widać łysy pasek). Linia włosów z przodu jest nad brwiami, więc oczy widać.
function BUILD.Hair(P, item)
	local s = P.S("Head")
	local x, y, z = s.X, s.Y, s.Z
	local style = item.Style or "Buzz"
	-- elipsoida: środek i średnice w częściach rozmiaru głowy
	local function egg(role, cx, cy, cz, dx, dy, dz, turn)
		local cf = CFrame.new(x * cx, y * cy, z * cz)
		if turn ~= nil then
			cf = cf * turn
		end
		P.add("Head", "Egg", Vector3.new(x * dx, y * dy, z * dz), cf, role)
	end
	local function ball(role, cx, cy, cz, d)
		P.add("Head", "Ball", Vector3.new(x * d, x * d, x * d), CFrame.new(x * cx, y * cy, z * cz), role)
	end
	if style == "Beanie" then
		egg("Main", 0, 0.3, 0.02, 1.16, 0.96, 1.18)
		P.add("Head", "Rod", Vector3.new(y * 0.2, x * 1.16, x * 1.16), CFrame.new(0, y * 0.26, z * 0.02), "Main")
		P.add("Head", "Rod", Vector3.new(y * 0.03, x * 1.18, x * 1.18), CFrame.new(0, y * 0.36, z * 0.02), "Dark")
		P.add("Head", "Rod", Vector3.new(y * 0.03, x * 1.18, x * 1.18), CFrame.new(0, y * 0.17, z * 0.02), "Dark")
		if item.Crosses then
			cross(P, "Head", CFrame.new(0, y * 0.26, -z * 0.585), y * 0.18, "Accent", 0.04, true)
		end
		return
	end
	local sides = "Main"
	if style == "Fade" then
		sides = "Dark"
	end
	-- czapka włosów: jedna elipsoida pochylona do przodu (z przodu linia włosów nad czołem,
	-- z tyłu aż do karku), więc nie ma schodka między czubkiem a tyłem głowy
	egg(sides, 0, 0.27, 0.07, 1.13, 0.88, 1.2, CFrame.Angles(math.rad(20), 0, 0))
	if style == "Buzz" then
		return
	end
	if style == "Fade" then
		-- wysoka góra (boki krótko, ciemniej) i równy przód
		egg("Main", 0, 0.5, 0.0, 1.02, 0.52, 1.04)
		egg("Main", 0, 0.5, -0.3, 0.94, 0.4, 0.5)
		return
	end
	if style == "Slick" then
		-- uniesiony przód zaczesany do tyłu i ciemniejsze pasma od grzebienia
		egg("Main", 0, 0.5, -0.18, 1.0, 0.46, 0.74, CFrame.Angles(math.rad(16), 0, 0))
		egg("Main", 0, 0.48, 0.14, 1.06, 0.4, 0.86)
		for _, px in ipairs({ -0.27, -0.09, 0.09, 0.27 }) do
			egg("Dark", px, 0.64, -0.02, 0.06, 0.06, 0.9, CFrame.Angles(math.rad(-4), 0, 0))
		end
		return
	end
	if style == "Curls" then
		-- loki: kulki w trzech rzędach na czapce (z przodu tylko wysoko, nad czołem)
		local rings = {
			{ lat = 72, n = 4, d = 0.3, from = 45 },
			{ lat = 36, n = 8, d = 0.3, from = 0 },
			{ lat = 4, n = 6, d = 0.3, from = 62, to = 298 },
		}
		local cy, ry, rx, rz = 0.34, 0.34, 0.6, 0.62
		for _, ring in ipairs(rings) do
			for i = 1, ring.n do
				local lon
				if ring.to ~= nil then
					lon = ring.from + (ring.to - ring.from) * (i - 1) / (ring.n - 1)
				else
					lon = ring.from + 360 * (i - 1) / ring.n
				end
				local la, lo = math.rad(ring.lat), math.rad(lon)
				ball("Main", math.cos(la) * math.sin(lo) * rx, cy + math.sin(la) * ry, -math.cos(la) * math.cos(lo) * rz + 0.04, ring.d)
			end
		end
		return
	end
	if style == "Flow" then
		-- długie: grzywka na bok, tył i boki aż za kark, pasma przy twarzy (wzdłuż zaokrąglenia głowy)
		egg("Main", 0.08, 0.42, -0.33, 1.0, 0.32, 0.46, CFrame.Angles(0, 0, math.rad(-10)))
		egg("Main", 0, -0.08, 0.16, 1.14, 1.36, 0.86)
		egg("Main", 0, -0.42, 0.3, 1.04, 0.8, 0.5)
		for _, side in ipairs({ -1, 1 }) do
			egg("Main", side * 0.43, -0.02, -0.28, 0.24, 1.12, 0.36, CFrame.Angles(0, math.rad(side * 32), 0))
		end
		return
	end
end

--------------------------------------------------------------- Okulary
-- Style: Square (kwadratowe oprawki), Aviator (łezki na cienkim metalu), Wrap (szyba dookoła
-- głowy), Visor (jedna świecąca szyba). Bold = grube oprawki, Studs = kamyczki na oprawce.
function BUILD.Glasses(P, item)
	local s = P.S("Head")
	local x, y, z = s.X, s.Y, s.Z
	local ey = y * 0.09 -- wysokość oczu
	local fz = -z * 0.5 - 0.035 -- przód oprawki
	local style = item.Style or "Square"
	local temple = function(role)
		for _, side in ipairs({ -1, 1 }) do
			P.add("Head", "Block", Vector3.new(0.05, 0.06, z * 0.62), CFrame.new(side * x * 0.5, ey + 0.04, fz + z * 0.31), role)
			if item.Crosses then
				cross(P, "Head", CFrame.new(side * (x * 0.5 + 0.03), ey + 0.04, fz + z * 0.3) * CFrame.Angles(0, math.rad(90), 0), 0.22, "Metal", 0.025)
			end
		end
	end
	if style == "Aviator" then
		for _, side in ipairs({ -1, 1 }) do
			local at = CFrame.new(side * x * 0.2, ey - 0.02, fz) * CFrame.Angles(0, 0, math.rad(side * 10))
			P.add("Head", "Egg", Vector3.new(x * 0.36, y * 0.31, 0.05), at * CFrame.new(0, 0, 0.01), "Accent")
			P.add("Head", "Egg", Vector3.new(x * 0.31, y * 0.26, 0.05), at * CFrame.new(0, 0, -0.01), "Lens")
		end
		P.add("Head", "Block", Vector3.new(x * 0.2, 0.035, 0.04), CFrame.new(0, ey + y * 0.1, fz), "Accent")
		P.add("Head", "Block", Vector3.new(x * 0.12, 0.03, 0.04), CFrame.new(0, ey + y * 0.03, fz), "Accent")
		temple("Accent")
		return
	end
	if style == "Wrap" then
		-- szyba z trzech części: środek i dwa skrzydła zagięte do tyłu
		P.add("Head", "Block", Vector3.new(x * 0.6, y * 0.22, 0.05), CFrame.new(0, ey, fz - 0.01), "Lens")
		for _, side in ipairs({ -1, 1 }) do
			P.add("Head", "Block", Vector3.new(x * 0.26, y * 0.2, 0.05), CFrame.new(side * x * 0.4, ey, fz + 0.06) * CFrame.Angles(0, math.rad(side * -38), 0), "Lens")
		end
		P.add("Head", "Block", Vector3.new(x * 0.66, 0.06, 0.07), CFrame.new(0, ey + y * 0.12, fz), "Accent")
		temple("Accent")
		return
	end
	if style == "Visor" then
		P.add("Head", "Block", Vector3.new(x * 0.94, y * 0.17, 0.06), CFrame.new(0, ey, fz - 0.01), "Main")
		P.add("Head", "Block", Vector3.new(x * 0.98, 0.06, 0.09), CFrame.new(0, ey + y * 0.11, fz), "Accent")
		P.add("Head", "Block", Vector3.new(x * 0.98, 0.05, 0.09), CFrame.new(0, ey - y * 0.105, fz), "Accent")
		P.add("Head", "Block", Vector3.new(x * 0.8, 0.02, 0.02), CFrame.new(0, ey + y * 0.03, fz - 0.045), "White", "Neon")
		temple("Accent")
		return
	end
	-- Square: oprawka z jednego klocka (mostek i obwódki), na niej dwa szkła
	local bold = 0
	if item.Bold then
		bold = 0.04
	end
	P.rbox("Head", Vector3.new(x * 0.9 + bold, y * 0.25 + bold, 0.07), CFrame.new(0, ey, fz), "Accent", 0.03)
	for _, side in ipairs({ -1, 1 }) do
		P.add("Head", "Block", Vector3.new(x * 0.34, y * 0.17, 0.04), CFrame.new(side * x * 0.215, ey - 0.005, fz - 0.03), "Lens")
		-- odblask na szkle
		P.add("Head", "Block", Vector3.new(x * 0.09, 0.025, 0.01), CFrame.new(side * x * 0.215 - x * 0.07, ey + y * 0.04, fz - 0.055) * CFrame.Angles(0, 0, math.rad(25)), "White", "Neon")
	end
	-- wycięcie na nos
	P.add("Head", "Block", Vector3.new(x * 0.1, y * 0.07, 0.072), CFrame.new(0, ey - y * 0.09, fz), "Dark")
	if item.Studs then
		for i = -3, 3 do
			local d = 0.075
			P.add("Head", "Ball", Vector3.new(d, d, d), CFrame.new(x * 0.065 * i * 2, ey + y * 0.125, fz - 0.035), "White", "Ice")
		end
	end
	if item.Bold then
		for _, side in ipairs({ -1, 1 }) do
			P.add("Head", "Ball", Vector3.new(0.1, 0.1, 0.1), CFrame.new(side * x * 0.43, ey + y * 0.08, fz - 0.04), "Gold")
		end
	end
	temple("Accent")
end

--------------------------------------------------------------- Łańcuch
-- Ogniwa idą od karku przez ramiona na pierś (krzywa w kształcie U). Rope = skręcone ogniwa,
-- Cuban = grube płaskie ogniwa, Links = wielkość ogniw, Pendant = zawieszka (Gem, Dollar, Cross).
local function chainPath(t, k, S, ctx)
	-- t od -1 (lewe ramię) do 1 (prawe); zwraca punkt na przodzie albo na górze tułowia
	local top = S.Y * 0.5
	local front = -S.Z * 0.5 - 0.05 - (ctx and ctx.chestOut or 0)
	local rx = S.X * 0.25 * k
	local ry = S.Y * 0.36 * k
	local a = t * math.pi / 2
	local px = math.sin(a) * rx
	local py = top - math.cos(a) * ry
	if py > top - 0.04 then
		py = top - 0.04
	end
	return px, py, front
end

function BUILD.Chain(P, item, slot)
	local S = P.S("UpperTorso")
	local k = 1
	if slot == 2 then
		k = 1.3 -- drugi łańcuch (Double Chain) wisi niżej
	end
	local size = 0.12 * (item.Links or 1)
	local n = item.Count or 17
	if item.Cuban then
		n = 13
	end
	local role = "Accent"
	-- ogniwa na ramionach (idą do tyłu po górze tułowia); pod futrzanym szalem ich nie widać
	local top = S.Y * 0.5
	local shoulders = { -1, 1 }
	if P.ctx.furCollar then
		shoulders = {}
	end
	for _, side in ipairs(shoulders) do
		for j = 0, 2 do
			local d = size * 0.95
			local px = side * (S.X * 0.25 * k + 0.02 - j * 0.04)
			P.add("UpperTorso", "Egg", Vector3.new(d * 0.9, d * 0.7, d * 1.5), CFrame.new(px, top + d * 0.2 + (P.ctx.topOut or 0), -S.Z * 0.36 + j * 0.2), role)
		end
	end
	for i = 1, n do
		local t = (i - 1) / (n - 1) * 2 - 1
		local px, py, pz = chainPath(t, k, S, P.ctx)
		local nx, ny = chainPath(math.min(1, t + 0.02), k, S, P.ctx)
		local bx, by = chainPath(math.max(-1, t - 0.02), k, S, P.ctx)
		local ang = math.atan2(ny - by, nx - bx) -- kierunek łańcucha w tym miejscu
		local at = CFrame.new(px, py, pz) * CFrame.Angles(0, 0, ang)
		if item.Cuban then
			-- grube płaskie ogniwa, na zmianę lekko przekrzywione
			local w = size * 1.9
			P.add("UpperTorso", "Egg", Vector3.new(w * 1.25, w * 0.95, w * 0.42), at * CFrame.Angles(0, 0, math.rad((i % 2) * 18 - 9)), role)
		elseif item.Rope then
			local w = size * 1.15
			P.add("UpperTorso", "Egg", Vector3.new(w * 1.5, w * 0.62, w * 0.62), at * CFrame.Angles(math.rad(45), 0, math.rad(((i % 2) * 2 - 1) * 35)), role)
		else
			local w = size
			if i % 2 == 0 then
				P.add("UpperTorso", "Egg", Vector3.new(w * 1.5, w * 0.95, w * 0.35), at, role)
			else
				P.add("UpperTorso", "Egg", Vector3.new(w * 1.5, w * 0.35, w * 0.95), at, role)
			end
		end
	end
	local _, bottom, front = chainPath(0, k, S, P.ctx)
	local hang = CFrame.new(0, bottom - size * 0.6, front - 0.02)
	if item.Pendant == "Gem" then
		-- kamień w złotej oprawie
		P.add("UpperTorso", "Ball", Vector3.new(0.1, 0.1, 0.1), hang * CFrame.new(0, 0.02, 0), "Accent")
		P.add("UpperTorso", "Disc", Vector3.new(0.06, 0.4, 0.4), hang * CFrame.new(0, -0.22, 0.01), "Accent")
		P.add("UpperTorso", "Ball", Vector3.new(0.3, 0.3, 0.3), hang * CFrame.new(0, -0.22, -0.06), "Main", "Ice")
		for _, a in ipairs({ 45, 135, 225, 315 }) do
			local r = math.rad(a)
			P.add("UpperTorso", "Ball", Vector3.new(0.07, 0.07, 0.07), hang * CFrame.new(math.cos(r) * 0.15, -0.22 + math.sin(r) * 0.15, -0.07), "Accent")
		end
	elseif item.Pendant == "Dollar" then
		-- zielona blaszka ze złotym „$”
		P.rbox("UpperTorso", Vector3.new(0.5, 0.06, 0.5), hang * CFrame.new(0, -0.28, 0) * CFrame.Angles(math.rad(90), 0, 0), "Main", 0.1)
		local d = hang * CFrame.new(0, -0.28, -0.05)
		P.add("UpperTorso", "Block", Vector3.new(0.05, 0.42, 0.03), d, "Accent")
		for _, py in ipairs({ 0.13, 0, -0.13 }) do
			P.add("UpperTorso", "Block", Vector3.new(0.24, 0.05, 0.03), d * CFrame.new(0, py, -0.005), "Accent")
		end
		-- „S” oglądane od przodu: górna pionowa kreska po lewej stronie patrzącego (+X postaci)
		P.add("UpperTorso", "Block", Vector3.new(0.05, 0.13, 0.03), d * CFrame.new(0.095, 0.065, -0.005), "Accent")
		P.add("UpperTorso", "Block", Vector3.new(0.05, 0.13, 0.03), d * CFrame.new(-0.095, -0.065, -0.005), "Accent")
	elseif item.Pendant == "Cross" then
		cross(P, "UpperTorso", hang * CFrame.new(0, -0.3, 0), 0.6, "Main", 0.08, true)
	end
end

--------------------------------------------------------------- Zegarek
-- Style: Analog (okrągła koperta z lunetą, tarczą i wskazówkami), Digital (prostokątny ekran).
-- Studs = kamyczki na lunecie, Chrono = trzy małe tarcze, Moon = księżyc na tarczy.
function BUILD.Watch(P, item, slot)
	local arm, side = "LeftLowerArm", -1
	if slot == 2 then
		arm, side = "RightLowerArm", 1 -- drugi zegarek (Double Wrist) na prawej ręce
	end
	local s = P.S(arm)
	local wy = -s.Y * 0.4
	local out = side * (s.X * 0.5 + GAP + 0.02) -- zewnętrzna strona nadgarstka
	P.rbox(arm, Vector3.new(s.X + 2 * GAP + 0.02, s.Y * 0.17, s.Z + 2 * GAP + 0.02), CFrame.new(0, wy, 0), "Main", 0.16)
	local face = CFrame.new(out, wy, 0) * CFrame.Angles(0, math.rad(-side * 90), 0) -- oś -Z patrzy na zewnątrz
	if item.Style == "Digital" then
		P.rbox(arm, Vector3.new(0.12, s.Y * 0.3, s.Z * 0.5), CFrame.new(out + side * 0.04, wy, 0), "Main", 0.06)
		P.add(arm, "Block", Vector3.new(0.02, s.Y * 0.2, s.Z * 0.36), CFrame.new(out + side * 0.1, wy, 0), "Accent", "Neon")
		for _, pz in ipairs({ -0.12, 0.12 }) do
			P.add(arm, "Block", Vector3.new(0.05, 0.05, 0.06), CFrame.new(out + side * 0.02, wy + s.Y * 0.16, pz), "Metal")
		end
		return
	end
	-- koperta, luneta, tarcza i wskazówki
	P.add(arm, "Ring", Vector3.new(0.12, 0.5, 0.5), CFrame.new(out + side * 0.05, wy, 0), "Metal")
	P.add(arm, "Ring", Vector3.new(0.04, 0.42, 0.42), CFrame.new(out + side * 0.1, wy, 0), "Accent", item.DialFinish)
	local dial = face * CFrame.new(0, 0, -0.13)
	P.add(arm, "Block", Vector3.new(0.025, 0.15, 0.015), dial * CFrame.new(0, 0.06, 0), "Dark")
	P.add(arm, "Block", Vector3.new(0.12, 0.025, 0.015), dial * CFrame.new(0.05, 0, 0), "Dark")
	for _, a in ipairs({ 0, 90, 180, 270 }) do
		local r = math.rad(a)
		P.add(arm, "Block", Vector3.new(0.03, 0.03, 0.012), dial * CFrame.new(math.cos(r) * 0.16, math.sin(r) * 0.16, 0), "White")
	end
	P.add(arm, "Rod", Vector3.new(0.08, 0.07, 0.07), CFrame.new(out + side * 0.05, wy - 0.27, 0), "Metal")
	if item.Studs then
		for i = 0, 9 do
			local r = math.rad(i * 36)
			P.add(arm, "Ball", Vector3.new(0.06, 0.06, 0.06), face * CFrame.new(math.cos(r) * 0.235, math.sin(r) * 0.235, -0.11), "White", "Ice")
		end
	end
	if item.Chrono then
		for _, p in ipairs({ { -0.09, -0.04 }, { 0.09, -0.04 }, { 0, -0.12 } }) do
			P.add(arm, "Disc", Vector3.new(0.01, 0.09, 0.09), dial * CFrame.new(p[1], p[2], -0.002), "White")
		end
	end
	if item.Moon then
		P.add(arm, "Ball", Vector3.new(0.09, 0.09, 0.09), dial * CFrame.new(-0.07, -0.08, -0.01), "Gold", "Neon")
	end
	if item.Crosses then
		cross(P, arm, dial * CFrame.new(0, -0.02, -0.006), 0.2, "Metal", 0.015)
	end
end

--------------------------------------------------------------- Koszula
-- Sleeves: None (koszulka koszykarska na ramiączkach), Short, Long. Collar: Crew (okrągły), V (dekolt),
-- Open (rozpięty z wyłogami), Fur (futrzany), High (stójka kurtki), None. Pocket, Buttons, Flowers,
-- Puffer (pikowane pasy), Zipper, Coat (płaszcz do pół uda), Fur (futrzane mankiety i obszycia),
-- Bulky (grubszy), Number (numer z przodu i z tyłu), Crosses (krzyże „chrome”).
local function sleeve(P, item, arm, from, to, g, cuffRole)
	-- rękaw od wysokości from do to (część wysokości ręki: 0.5 = góra, -0.5 = dół)
	local a = P.S(arm)
	local topY = from * a.Y
	if from >= 0.5 then
		topY = topY + 0.03 -- nad górą ręki, żeby jej górna ściana nie migała przez rękaw
	end
	local h = topY - to * a.Y
	local cy = topY - h / 2
	if item.Puffer then
		-- pikowane pasy na ciemniejszym rdzeniu (rdzeń to zwykły klocek: mniej części)
		local n = math.max(1, math.floor(h / 0.6 + 0.5))
		local bh = h / n
		P.add(arm, "Block", Vector3.new(a.X + 2 * g - 0.02, h, a.Z + 2 * g - 0.02), CFrame.new(0, cy, 0), "Dark")
		for i = 1, n do
			P.rbox(arm, Vector3.new(a.X + 2 * g + 0.08, bh * 0.84, a.Z + 2 * g + 0.08), CFrame.new(0, topY - bh * (i - 0.5), 0), "Main", 0.26)
		end
	else
		P.rbox(arm, Vector3.new(a.X + 2 * g, h, a.Z + 2 * g), CFrame.new(0, cy, 0), "Main", 0.2)
	end
	if cuffRole ~= nil then
		P.rbox(arm, Vector3.new(a.X + 2 * g + 0.05, 0.1, a.Z + 2 * g + 0.05), CFrame.new(0, to * a.Y + 0.05, 0), cuffRole, 0.22)
	end
end

-- Futro: kulki na łuku elipsy (kąty w stopniach, 0 = przód, 90 = prawy bok).
local function furArc(P, body, center, rx, rz, n, from, to, d)
	for i = 1, n do
		local a = math.rad(from + (to - from) * (i - 1) / math.max(1, n - 1))
		P.add(body, "Ball", Vector3.new(d, d, d), center * CFrame.new(math.sin(a) * rx, 0, -math.cos(a) * rz), "Accent")
	end
end

function BUILD.Shirt(P, item)
	local S = P.S
	local t, l = S("UpperTorso"), S("LowerTorso")
	local g = GAP
	if item.Bulky then
		g = GAP + 0.07
	end
	local W, D = t.X + 2 * g, t.Z + 2 * g
	local top = t.Y / 2 + 0.01
	local bottom = -t.Y / 2
	local front = -D / 2
	local back = D / 2
	local trim = item.TrimRole or "Dark"

	-- tułów
	if item.Sleeves == "None" then
		-- koszulka koszykarska: korpus do pach, szerokie ramiączka, lamówki dookoła
		local h = t.Y * 0.8
		P.rbox("UpperTorso", Vector3.new(W, h, D), CFrame.new(0, bottom + h / 2, 0), "Main", 0.22)
		for _, side in ipairs({ -1, 1 }) do
			P.rbox("UpperTorso", Vector3.new(t.X * 0.24, t.Y - h + 0.02, D), CFrame.new(side * t.X * 0.26, top - (t.Y - h) / 2, 0), "Main", 0.1)
			-- lamówka pachy: pasek na boku korpusu i na zewnętrznym brzegu ramiączka
			P.add("UpperTorso", "Block", Vector3.new(0.05, t.Y - h + 0.04, D + 0.02), CFrame.new(side * (t.X * 0.38 + 0.005), top - (t.Y - h) / 2, 0), trim)
			P.add("UpperTorso", "Block", Vector3.new(t.X * 0.12, 0.06, D + 0.02), CFrame.new(side * (t.X * 0.44), bottom + h + 0.01, 0), trim)
		end
		-- lamówka dekoltu z przodu i z tyłu
		for _, z in ipairs({ front - 0.012, back + 0.012 }) do
			P.add("UpperTorso", "Block", Vector3.new(t.X * 0.29, 0.06, 0.03), CFrame.new(0, bottom + h + 0.01, z), trim)
		end
	elseif item.Puffer then
		local n = 4
		local bh = (t.Y + 0.02) / n
		P.add("UpperTorso", "Block", Vector3.new(W - 0.02, t.Y + 0.02, D - 0.02), CFrame.new(0, 0.01, 0), "Dark")
		for i = 1, n do
			P.rbox("UpperTorso", Vector3.new(W + 0.12, bh * 0.84, D + 0.12), CFrame.new(0, top - bh * (i - 0.5), 0), "Main", 0.32)
		end
		front = front - 0.06
		back = back + 0.06
	else
		P.rbox("UpperTorso", Vector3.new(W, t.Y + 0.02, D), CFrame.new(0, 0.01, 0), "Main", 0.22)
	end

	-- dół: lamówka na dole koszuli (LowerTorso zakrywają spodnie); płaszcz schodzi do pół uda
	if item.Coat then
		local lw, ld = l.X + 2 * g, l.Z + 2 * g
		P.rbox("LowerTorso", Vector3.new(lw, l.Y + 0.04, ld), CFrame.new(0, 0, 0), "Main", 0.22)
		-- poły rozchodzą się w dół (jak w płaszczu), żeby nogi przy chodzeniu nie wychodziły przez nie
		local len = 0.66
		local flare = math.rad(14)
		local lowY = -l.Y / 2 + 0.02
		local push = len * math.sin(flare)
		local panels = {}
		for _, side in ipairs({ -1, 1 }) do
			local at = CFrame.new(side * lw / 4, lowY, -ld / 2 + 0.06) * CFrame.Angles(-flare, 0, 0) * CFrame.new(0, -len / 2, -0.06)
			P.add("LowerTorso", "Block", Vector3.new(lw / 2 - 0.02, len, 0.12), at, "Main")
			table.insert(panels, { at, lw / 2 + 0.04 })
			-- bok: prosta ścianka i dwa kliny, które domykają ją do pochylonych pół (trapez, bez „słupków”)
			local x = side * (lw / 2 - 0.06)
			P.add("LowerTorso", "Block", Vector3.new(0.12, len, ld), CFrame.new(x, lowY - len / 2, 0), "Main")
			P.add("LowerTorso", "Wedge", Vector3.new(0.12, len, push), CFrame.new(x, lowY - len / 2, -ld / 2 - push / 2), "Main")
			P.add("LowerTorso", "Wedge", Vector3.new(0.12, len, push), CFrame.new(x, lowY - len / 2, ld / 2 + push / 2) * CFrame.Angles(0, math.pi, 0), "Main")
		end
		local backAt = CFrame.new(0, lowY, ld / 2 - 0.06) * CFrame.Angles(flare, 0, 0) * CFrame.new(0, -len / 2, 0.06)
		P.add("LowerTorso", "Block", Vector3.new(lw, len, 0.12), backAt, "Main")
		table.insert(panels, { backAt, lw + 0.06 })
		if item.Fur then
			-- futro na dole: miękki wałek wzdłuż dołu każdej poły (pochylony razem z nią) i na bokach
			for _, panel in ipairs(panels) do
				P.rbox("LowerTorso", Vector3.new(panel[2] + 0.04, 0.24, 0.26), panel[1] * CFrame.new(0, -len / 2 + 0.06, 0), "Accent", 0.12)
			end
			-- boki (zwykłe klocki, zasłaniają je ręce): końce schowane w wałkach z przodu i z tyłu
			for _, side in ipairs({ -1, 1 }) do
				P.add("LowerTorso", "Block", Vector3.new(0.2, 0.22, ld + 2 * push - 0.06), CFrame.new(side * (lw / 2 - 0.07), lowY - len + 0.06, 0), "Accent")
			end
		end
		-- pasek w talii z klamrą
		P.rbox("LowerTorso", Vector3.new(lw + 0.04, 0.16, ld + 0.04), CFrame.new(0, l.Y / 2 - 0.04, 0), "Detail", 0.24)
		P.add("LowerTorso", "Block", Vector3.new(0.3, 0.24, 0.05), CFrame.new(0, l.Y / 2 - 0.04, -ld / 2 - 0.04), "Gold")
	elseif item.Puffer then
		P.rbox("UpperTorso", Vector3.new(W + 0.06, 0.12, D + 0.06), CFrame.new(0, bottom + 0.05, 0), "Dark", 0.3)
	else
		P.rbox("UpperTorso", Vector3.new(W + 0.05, 0.1, D + 0.05), CFrame.new(0, bottom + 0.04, 0), trim, 0.24)
	end

	-- kołnierzyk
	local collar = item.Collar or "Crew"
	if collar == "Crew" then
		-- ściągacz: pierścień dookoła szyi i łuk „U” z przodu (krótkie odcinki styczne do okręgu)
		P.add("UpperTorso", "Rod", Vector3.new(0.08, 1.02, 1.02), CFrame.new(0, top + 0.03, 0.02), trim)
		local r = 0.3
		for i = 0, 4 do
			local a = math.rad(-150 + i * 30) -- od lewej (−150°) do prawej (−30°) przez dół okręgu
			local at = CFrame.new(math.cos(a) * r, top + 0.08 + math.sin(a) * r, front - 0.012)
			P.add("UpperTorso", "Block", Vector3.new(0.17, 0.065, 0.03), at * CFrame.Angles(0, 0, a + math.rad(90)), trim)
		end
	elseif collar == "V" or collar == "Open" then
		local w, depth = 0.22, 0.6
		if collar == "Open" then
			w, depth = 0.26, 0.5
		end
		local a = vNeck(P, "UpperTorso", top, front, w, depth, trim)
		if collar == "Open" then
			-- wyłogi: płaskie paski wzdłuż brzegów dekoltu, odchylone na zewnątrz
			local r = math.rad(a)
			for _, side in ipairs({ -1, 1 }) do
				local along = 0.42
				local px = side * w * (1 - along) + side * 0.12 * math.cos(r)
				local py = top - depth * along - 0.12 * math.sin(r)
				slant(P, "UpperTorso", Vector3.new(0.2, depth * 0.86, 0.035), CFrame.new(px, py, front - 0.03), -side * (a + 6), "Light")
			end
		end
		P.add("UpperTorso", "Rod", Vector3.new(0.08, 1.02, 1.02), CFrame.new(0, top + 0.03, 0.02), trim)
		if item.Buttons then
			for i = 1, 3 do
				P.add("UpperTorso", "Disc", Vector3.new(0.04, 0.11, 0.11), CFrame.new(0, top - depth - 0.12 - (i - 1) * 0.26, front - 0.02), "Detail")
			end
		end
	elseif collar == "High" then
		P.add("UpperTorso", "Rod", Vector3.new(0.3, 1.32, 1.32), CFrame.new(0, top + 0.11, 0.04), "Main")
		P.add("UpperTorso", "Rod", Vector3.new(0.05, 1.36, 1.36), CFrame.new(0, top + 0.25, 0.04), trim)
	elseif collar == "Fur" then
		-- futrzany szal: wałek dookoła karku i boków szyi, z przodu wyłogi aż do pasa
		P.add("UpperTorso", "Egg", Vector3.new(1.5, 0.5, 0.56), CFrame.new(0, top + 0.08, back - 0.2), "Accent")
		for _, side in ipairs({ -1, 1 }) do
			P.add("UpperTorso", "Egg", Vector3.new(0.5, 0.5, 1.12), CFrame.new(side * 0.52, top + 0.07, 0.02), "Accent")
			P.add("UpperTorso", "Egg", Vector3.new(0.56, t.Y * 1.06, 0.26), CFrame.new(side * 0.26, 0.02, front - 0.05) * CFrame.Angles(0, 0, math.rad(-side * 6)), "Accent")
		end
	end

	-- dodatki z przodu i z tyłu
	if item.Pocket then
		P.rbox("UpperTorso", Vector3.new(0.36, 0.38, 0.04), CFrame.new(-0.5, 0.06, front - 0.015), trim, 0.06)
		P.add("UpperTorso", "Block", Vector3.new(0.38, 0.08, 0.05), CFrame.new(-0.5, 0.24, front - 0.02), trim)
	end
	if item.Number then
		-- napis budujemy w układzie postaci (+X = jej prawa ręka); od przodu oglądamy go z naprzeciwka,
		-- więc z przodu obracamy go o 180°, żeby czytał się dobrze
		number(P, "UpperTorso", CFrame.new(0, -0.18, front - 0.015) * CFrame.Angles(0, math.rad(180), 0), item.Number, 0.62, "Accent")
		number(P, "UpperTorso", CFrame.new(0, -0.12, back + 0.015), item.Number, 0.74, "Accent")
	end
	if item.Zipper then
		P.add("UpperTorso", "Block", Vector3.new(0.07, t.Y + 0.02, 0.03), CFrame.new(0, 0.01, front - 0.015), "Metal")
		P.add("UpperTorso", "Block", Vector3.new(0.09, 0.2, 0.03), CFrame.new(0, top - 0.36, front - 0.035), "Metal")
	end
	if item.Flowers then
		local spots = { { -0.62, 0.22, 1 }, { 0.6, 0.02, 1.1 }, { -0.42, -0.42, 0.9 }, { 0.5, -0.5, 0.8 } }
		for _, p in ipairs(spots) do
			flower(P, "UpperTorso", CFrame.new(p[1], p[2], front - 0.02) * CFrame.Angles(0, 0, math.rad(p[1] * 60)), p[3])
		end
		for _, p in ipairs({ { -0.4, 0.2, 1.1 }, { 0.45, -0.3, 1 } }) do
			flower(P, "UpperTorso", CFrame.new(p[1], p[2], back + 0.02) * CFrame.Angles(0, math.rad(180), math.rad(p[2] * 70)), p[3])
		end
	end
	if item.Crosses then
		cross(P, "UpperTorso", CFrame.new(0, -0.02, front - 0.02), t.Y * 0.58, "Accent", 0.04, true)
		cross(P, "UpperTorso", CFrame.new(0, 0.05, back + 0.02), t.Y * 0.45, "Accent", 0.04)
	end

	-- rękawy
	local cuff = item.CuffRole or trim
	if item.Sleeves == "Short" then
		for _, arm in ipairs({ "LeftUpperArm", "RightUpperArm" }) do
			sleeve(P, item, arm, 0.5, -0.08, g, cuff)
		end
	elseif item.Sleeves == "Long" then
		for _, arm in ipairs({ "LeftUpperArm", "RightUpperArm" }) do
			sleeve(P, item, arm, 0.5, -0.5, g, nil)
		end
		for _, arm in ipairs({ "LeftLowerArm", "RightLowerArm" }) do
			local a = S(arm)
			if item.Fur then
				sleeve(P, item, arm, 0.5, -0.2, g, nil)
				P.rbox(arm, Vector3.new(a.X + 2 * g + 0.16, 0.36, a.Z + 2 * g + 0.16), CFrame.new(0, -0.2 * a.Y - 0.02, 0), "Accent", 0.3)
			else
				sleeve(P, item, arm, 0.5, -0.26, g, cuff)
			end
		end
		if item.Crosses then
			for _, arm in ipairs({ "LeftUpperArm", "RightUpperArm", "LeftLowerArm", "RightLowerArm" }) do
				local a = S(arm)
				local side = 1
				if string.sub(arm, 1, 4) == "Left" then
					side = -1
				end
				cross(P, arm, CFrame.new(side * (a.X / 2 + g + 0.015), 0.04, 0) * CFrame.Angles(0, math.rad(side * 90), 0), a.Y * 0.4, "Accent", 0.03)
			end
		end
	end
end

--------------------------------------------------------------- Spodnie
-- Long = długie nogawki (bez tego szorty). Belt = pasek z klamrą, Drawstring = sznurek, Stripe =
-- lampas po boku, Cargo = kieszenie na udach, BackPockets, Rips = przetarcia na kolanach, Studs =
-- kamyczki na kieszeniach, Cuffs = podwinięte nogawki, Crosses = krzyże „chrome”.
function BUILD.Pants(P, item)
	local S = P.S
	local l = S("LowerTorso")
	local g = GAP + 0.012
	local front = -(l.Z / 2 + g)
	P.rbox("LowerTorso", Vector3.new(l.X + 2 * g, l.Y + 0.02, l.Z + 2 * g), CFrame.new(0, -0.01, 0), "Main", 0.22)
	if item.Belt then
		P.rbox("LowerTorso", Vector3.new(l.X + 2 * g + 0.04, 0.14, l.Z + 2 * g + 0.04), CFrame.new(0, l.Y / 2 - 0.08, 0), "Detail", 0.24)
		P.rbox("LowerTorso", Vector3.new(0.3, 0.2, 0.05), CFrame.new(0, l.Y / 2 - 0.08, front - 0.04), item.Buckle or "Gold", 0.04)
		P.add("LowerTorso", "Block", Vector3.new(0.16, 0.08, 0.06), CFrame.new(0, l.Y / 2 - 0.08, front - 0.045), "Dark")
	else
		P.rbox("LowerTorso", Vector3.new(l.X + 2 * g + 0.03, 0.12, l.Z + 2 * g + 0.03), CFrame.new(0, l.Y / 2 - 0.06, 0), "Accent", 0.24)
	end
	if item.Drawstring then
		for _, side in ipairs({ -1, 1 }) do
			slant(P, "LowerTorso", Vector3.new(0.035, 0.3, 0.035), CFrame.new(side * 0.07, l.Y / 2 - 0.22, front - 0.04), side * 8, "White")
			P.add("LowerTorso", "Ball", Vector3.new(0.06, 0.06, 0.06), CFrame.new(side * 0.09, l.Y / 2 - 0.37, front - 0.04), "White")
		end
	end
	for _, side in ipairs({ -1, 1 }) do
		local name = "Right"
		if side < 0 then
			name = "Left"
		end
		local leg = name .. "UpperLeg"
		local s = S(leg)
		local len = s.Y + 0.02
		if not item.Long then
			len = s.Y * 0.74
		end
		local legTop = s.Y / 2 + 0.01
		P.rbox(leg, Vector3.new(s.X + 2 * g, len, s.Z + 2 * g), CFrame.new(0, legTop - len / 2, 0), "Main", 0.2)
		local outer = side * (s.X / 2 + g)
		local legFront = -(s.Z / 2 + g)
		local legBack = s.Z / 2 + g
		if not item.Long then
			P.rbox(leg, Vector3.new(s.X + 2 * g + 0.04, 0.1, s.Z + 2 * g + 0.04), CFrame.new(0, legTop - len + 0.05, 0), "Dark", 0.22)
		end
		if item.Stripe then
			P.add(leg, "Block", Vector3.new(0.04, len, 0.14), CFrame.new(outer + side * 0.01, legTop - len / 2, 0), "Accent")
		end
		if item.Cargo then
			P.rbox(leg, Vector3.new(0.06, 0.4, 0.46), CFrame.new(outer + side * 0.025, legTop - len * 0.55, 0), "Dark", 0.04)
			P.add(leg, "Block", Vector3.new(0.08, 0.1, 0.5), CFrame.new(outer + side * 0.035, legTop - len * 0.55 + 0.17, 0), "Accent")
		end
		if item.BackPockets then
			P.rbox(leg, Vector3.new(0.4, 0.34, 0.04), CFrame.new(-side * 0.02, legTop - 0.26, legBack + 0.015), "Dark", 0.05)
			if item.Studs then
				for _, px in ipairs({ -0.14, 0, 0.14 }) do
					P.add(leg, "Ball", Vector3.new(0.06, 0.06, 0.06), CFrame.new(-side * 0.02 + px, legTop - 0.12, legBack + 0.035), "White", "Ice")
				end
			end
		end
		if item.Rips then
			P.add(leg, "Egg", Vector3.new(0.42, 0.14, 0.03), CFrame.new(0, legTop - len + 0.18, legFront - 0.01) * CFrame.Angles(0, 0, math.rad(side * 6)), "Light")
			P.add(leg, "Egg", Vector3.new(0.3, 0.09, 0.03), CFrame.new(0.02, legTop - len + 0.36, legFront - 0.01) * CFrame.Angles(0, 0, math.rad(-side * 8)), "Light")
		end
		if item.Crosses then
			cross(P, leg, CFrame.new(0, -0.05, legFront - 0.015), s.Y * 0.4, "Accent", 0.04)
		end
		if item.Long then
			local low = name .. "LowerLeg"
			local s2 = S(low)
			P.rbox(low, Vector3.new(s2.X + 2 * g, s2.Y * 0.98, s2.Z + 2 * g), CFrame.new(0, s2.Y * 0.01, 0), "Main", 0.2)
			if item.Stripe then
				P.add(low, "Block", Vector3.new(0.04, s2.Y * 0.98, 0.14), CFrame.new(side * (s2.X / 2 + g + 0.01), s2.Y * 0.01, 0), "Accent")
			end
			local cuffRole = "Dark"
			local cuffH = 0.12
			if item.Cuffs then
				cuffRole = "Light"
				cuffH = 0.2
			end
			P.rbox(low, Vector3.new(s2.X + 2 * g + 0.05, cuffH, s2.Z + 2 * g + 0.05), CFrame.new(0, -s2.Y / 2 + cuffH / 2 + 0.02, 0), cuffRole, 0.22)
			if item.Crosses then
				cross(P, low, CFrame.new(0, 0.05, -(s2.Z / 2 + g) - 0.015), s2.Y * 0.38, "Accent", 0.04)
			end
		end
	end
end

--------------------------------------------------------------- Buty
-- Style: Sneaker (podeszwa, cholewka, zaokrąglony nosek, sznurówki), HighTop (za kostkę), FlipFlop
-- (japonki z paskiem w Y), Slide (klapki z szerokim paskiem), Loafer (mokasyny z wędzidełkiem).
-- Cholewka zawsze zakrywa całą stopę (stopy R15 to klocki), nosek wystaje z przodu.
-- Chunky = gruba podeszwa, Studs = kamyczki z boku, Crosses = krzyże „chrome”.
function BUILD.Shoes(P, item)
	local S = P.S
	local style = item.Style or "Sneaker"
	for _, side in ipairs({ -1, 1 }) do
		local name = "Right"
		if side < 0 then
			name = "Left"
		end
		local foot = name .. "Foot"
		local s = S(foot)
		local bottom = -s.Y / 2
		local fz = -s.Z / 2 -- przód stopy
		local bz = s.Z / 2 -- pięta
		local outer = side * (s.X / 2 + 0.06)
		if style == "FlipFlop" or style == "Slide" then
			local th = 0.1
			if style == "Slide" then
				th = 0.16
			end
			local len = s.Z + 0.24
			P.rbox(foot, Vector3.new(s.X + 0.1, th, len), CFrame.new(0, bottom + th / 2 - 0.04, -0.08), "Main", 0.42)
			if style == "FlipFlop" then
				-- pasek w kształcie Y: od kołka między palcami do boków stopy
				P.add(foot, "Ball", Vector3.new(0.09, 0.09, 0.09), CFrame.new(0, bottom + th / 2, fz + 0.12), "Accent")
				for _, sx in ipairs({ -1, 1 }) do
					local from = Vector3.new(0, bottom + 0.04, fz + 0.12)
					local to = Vector3.new(sx * (s.X / 2 + 0.03), bottom + 0.02, 0.06)
					local mid = (from + to) / 2 + Vector3.new(0, s.Y * 0.45, 0)
					P.add(foot, "Block", Vector3.new(0.07, 0.07, (mid - from).Magnitude + 0.06), CFrame.lookAt(from:Lerp(mid, 0.5), mid), "Accent")
					P.add(foot, "Block", Vector3.new(0.07, 0.07, (to - mid).Magnitude + 0.06), CFrame.lookAt(mid:Lerp(to, 0.5), to), "Accent")
				end
			else
				-- szeroki pasek przez wierzch stopy (zakrywa przód stopy)
				P.rbox(foot, Vector3.new(s.X + 0.12, s.Y + 0.02, 0.46), CFrame.new(0, bottom + th + (s.Y + 0.02) / 2 - 0.05, fz + 0.27), "Accent", 0.14)
				P.add(foot, "Block", Vector3.new(s.X * 0.6, 0.05, 0.02), CFrame.new(0, bottom + th + s.Y * 0.55, fz + 0.03), "Main")
			end
		elseif style == "Loafer" then
			local len = s.Z + 0.2
			P.rbox(foot, Vector3.new(s.X + 0.1, 0.09, len), CFrame.new(0, bottom - 0.01, -0.06), "Accent", 0.4)
			P.rbox(foot, Vector3.new(s.X + 0.1, s.Y + 0.06, s.Z + 0.1), CFrame.new(0, 0, 0.02), "Main", 0.16)
			P.add(foot, "Egg", Vector3.new(s.X + 0.07, s.Y * 1.2, 0.56), CFrame.new(0, bottom + s.Y * 0.42, fz - 0.02), "Main")
			-- wędzidełko: złota sztabka z kulkami na wierzchu
			P.add(foot, "Rod", Vector3.new(s.X * 0.5, 0.06, 0.06), CFrame.new(0, s.Y / 2 + 0.05, fz + 0.24) * CFrame.Angles(0, 0, math.rad(90)), "Gold")
			for _, sx in ipairs({ -1, 1 }) do
				P.add(foot, "Ball", Vector3.new(0.1, 0.1, 0.1), CFrame.new(sx * s.X * 0.26, s.Y / 2 + 0.05, fz + 0.24), "Gold")
			end
		else
			-- Sneaker / HighTop: podeszwa (z przodu i z tyłu zaokrąglona), cholewka na całej stopie,
			-- nosek, sznurówki, języczek, zapiętek i pasek z boku
			local soleH = 0.13
			if item.Chunky then
				soleH = 0.24
			end
			local h = s.Y + 0.06
			if style == "HighTop" then
				h = s.Y + 0.4
			end
			local lift = soleH - 0.06 -- cholewka zaczyna się na podeszwie
			P.rbox(foot, Vector3.new(s.X + 0.13, soleH, s.Z + 0.3), CFrame.new(0, bottom + soleH / 2 - 0.06, -0.1), "Accent", 0.4)
			local upperH = lift + h - 0.02 -- od spodu stopy (pod podeszwą nic nie wystaje) do góry cholewki
			P.rbox(foot, Vector3.new(s.X + 0.1, upperH, s.Z + 0.1), CFrame.new(0, bottom - 0.02 + upperH / 2, 0.02), "Main", 0.16)
			P.add(foot, "Egg", Vector3.new(s.X + 0.08, s.Y * 1.25, 0.56), CFrame.new(0, bottom + lift + s.Y * 0.3, fz - 0.02), "Main")
			-- przyszwa (ciemniejsza) nad noskiem
			P.add(foot, "Egg", Vector3.new(s.X + 0.1, s.Y * 0.62, 0.44), CFrame.new(0, bottom + lift + s.Y * 0.16, fz - 0.07), "Accent")
			local topY = bottom + lift + h - 0.04
			-- sznurówki na przedniej części cholewki i języczek nad nimi
			for i = 0, 2 do
				P.add(foot, "Block", Vector3.new(s.X * 0.48, 0.045, 0.07), CFrame.new(0, topY + 0.02, fz + 0.18 + i * 0.13), "White")
			end
			P.rbox(foot, Vector3.new(s.X * 0.44, 0.12, 0.1), CFrame.new(0, topY + 0.05, fz + 0.58), "Light", 0.04)
			-- zapiętek
			P.rbox(foot, Vector3.new(s.X * 0.4, h * 0.7, 0.06), CFrame.new(0, bottom + lift + h * 0.4, bz + 0.07), "Accent", 0.03)
			-- pasek z boku (zwykły, bez logo)
			for _, sx in ipairs({ -1, 1 }) do
				P.add(foot, "Block", Vector3.new(0.03, h * 0.3, 0.5), CFrame.new(sx * (s.X / 2 + 0.06), bottom + lift + h * 0.42, 0.04) * CFrame.Angles(math.rad(-28), 0, 0), "Accent")
			end
			if item.Studs then
				for i = 0, 3 do
					P.add(foot, "Ball", Vector3.new(0.07, 0.07, 0.07), CFrame.new(outer + side * 0.01, bottom + lift + 0.06, fz + 0.12 + i * 0.22), "White", "Ice")
				end
			end
			if item.Crosses then
				cross(P, foot, CFrame.new(outer + side * 0.005, bottom + lift + h * 0.52, 0.02) * CFrame.Angles(0, math.rad(side * 90), 0), h * 0.56, "Metal", 0.03)
			end
		end
	end
end

----------------------------------------------------------------- Budowanie
local function buildWith(category, rarity, level, slot, sizeOf, place, ctx)
	local build = BUILD[category]
	if build == nil then
		return
	end
	local item = ClothesConfig.item(category, rarity)
	local P = newBrush(item, level, sizeOf, place, ctx)
	build(P, item, slot or 1)
end

-- Kontekst stroju: o ile koszula odstaje z przodu i na górze (łańcuch leży na niej, a nie w niej).
local function outfitContext(items)
	local ctx = { chestOut = 0, topOut = 0 }
	for _, entry in ipairs(items) do
		if entry.Category == "Shirt" then
			local item = ClothesConfig.item("Shirt", entry.Rarity)
			if item.Bulky then
				ctx.chestOut = ctx.chestOut + 0.07
				ctx.topOut = ctx.topOut + 0.02
			end
			if item.Puffer then
				ctx.chestOut = ctx.chestOut + 0.07
			end
			if item.Collar == "Fur" then
				ctx.chestOut = ctx.chestOut + 0.2
				ctx.furCollar = true
			end
		end
	end
	return ctx
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
	local function sizeOf(name)
		local _, _, size = bodyPart(character, name)
		return size or (RIG[name] and RIG[name][2]) or Vector3.new(1, 1, 1)
	end
	local function place(part, body, offset)
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
	end
	local ctx = outfitContext(items)
	-- skóra w dekolcie w kolorze tułowia gracza
	local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
	if torso ~= nil and torso:IsA("BasePart") then
		ctx.skin = torso.Color
	end
	for _, entry in ipairs(items) do
		if entry.Category == "Hair" then
			hasHair = true
		end
		buildWith(entry.Category, entry.Rarity, entry.Level, entry.Slot, sizeOf, place, ctx)
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
	local turn = CFrame.new()
	local function mannequin(size, cframe)
		local part = Instance.new("Part")
		part.Name = "Mannequin"
		part.Size = size
		part.CFrame = cframe
		part.Color = MANNEQUIN
		part.Material = Enum.Material.SmoothPlastic
		part.Anchored = true
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Parent = model
		return part
	end
	if category == "Hair" or category == "Glasses" then
		local head = mannequin(RIG.Head[2], RIG.Head[1])
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Head
		mesh.Scale = Vector3.new(1, 1, 1)
		mesh.Parent = head
	elseif category == "Watch" then
		-- kawałek nadgarstka, a całość obrócona tak, żeby tarcza (na zewnątrz lewej ręki) patrzyła w kamerę
		turn = CFrame.Angles(0, math.rad(-90), 0)
		local arm = RIG.LeftLowerArm
		mannequin(Vector3.new(arm[2].X, 0.8, arm[2].Z), turn * arm[1] * CFrame.new(0, -arm[2].Y * 0.4, 0))
	end
	local function sizeOf(name)
		return (RIG[name] and RIG[name][2]) or Vector3.new(1, 1, 1)
	end
	buildWith(category, rarity, level, 1, sizeOf, function(part, body, offset)
		local rig = RIG[body]
		part.Anchored = true
		part.CFrame = turn * (rig and rig[1] or CFrame.new()) * offset
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
	local spec = ClothesConfig.Boxes[boxName] or ClothesConfig.Boxes.Street
	local model = Instance.new("Model")
	model.Name = spec.Name or boxName
	local bodyFinish = FINISH[spec.Finish or ""]
	local ribbonFinish = FINISH[spec.RibbonFinish or ""]
	local bodyMaterial = (bodyFinish and bodyFinish[1]) or Enum.Material.SmoothPlastic
	local ribbonMaterial = (ribbonFinish and ribbonFinish[1]) or Enum.Material.SmoothPlastic
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
	part("Box", Vector3.new(3.6, 3, 3.6), CFrame.new(0, 1.5, 0), spec.Color, bodyMaterial)
	part("RibbonX", Vector3.new(3.7, 3.02, 0.6), CFrame.new(0, 1.5, 0), spec.Ribbon, ribbonMaterial)
	part("RibbonZ", Vector3.new(0.6, 3.02, 3.7), CFrame.new(0, 1.5, 0), spec.Ribbon, ribbonMaterial)
	part("Lid", Vector3.new(4, 0.8, 4), CFrame.new(0, 3.4, 0), spec.Color, bodyMaterial, true)
	part("LidRibbonX", Vector3.new(4.06, 0.84, 0.62), CFrame.new(0, 3.4, 0), spec.Ribbon, ribbonMaterial, true)
	part("LidRibbonZ", Vector3.new(0.62, 0.84, 4.06), CFrame.new(0, 3.4, 0), spec.Ribbon, ribbonMaterial, true)
	for _, side in ipairs({ -1, 1 }) do
		part("Bow", Vector3.new(1.2, 1.2, 1.2), CFrame.new(side * 0.55, 4.25, 0), spec.Ribbon, ribbonMaterial, true, Enum.PartType.Ball)
	end
	model.WorldPivot = CFrame.new()
	return model
end

return ClothModels
