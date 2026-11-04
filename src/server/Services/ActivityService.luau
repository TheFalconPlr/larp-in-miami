-- Aktywności w strefach: zdjęcia z autem (strefa 2, Etap 4), wywiad (3), impreza na jachcie (4)
-- i lot odrzutowcem (5) (Etap 6).
--
-- Jak oznaczyć miejsca w Studio (model albo część z taką nazwą w swojej strefie):
--   • „CarSpot”: auta „Car1” … „Car5” (po jednym na tier, w tym samym miejscu) i część „Pose”,
--   • „InterviewSpot”: studio (scena, fotele, tło) i część „Pose” (tu stoi gość). Punkt obrotu
--     (pivot) modelu na środku sceny, przodem (Front) do widowni: wokół niego ustawiają się kamery,
--   • „YachtSpot”: jachty „Yacht1” … „Yacht5” na wodzie; w każdym jachcie może być własna „Pose”
--     (gracz stoi na pokładzie), a bez niej liczy się „Pose” miejsca,
--   • „JetSpot”: odrzutowce „Jet1” … „Jet3” na pasie i „Pose” obok samolotu. Punkt obrotu każdego
--     odrzutowca przodem w stronę dziobu: w tę stronę samolot startuje (tylko u gracza).
-- Klient pokazuje tylko model z tieru gracza, a pozostałe są u niego niewidoczne i bez kolizji.
-- Gdy na mapie nie ma któregoś miejsca, serwer stawia tymczasowe z klocków w jego strefie.
--
-- Sesja: klient prosi o start (StartActivity) przy miejscu. Serwer sprawdza strefę, tier, Bag
-- i odległość, po połowie przejścia (TransitionSeconds z arkusza) stawia gracza w miejscu Pose
-- i go zatrzymuje, po DurationSeconds daje LP do Bag (Loop.finishActivity) i puszcza gracza, a po
-- drugiej połowie przejścia można zacząć kolejną sesję. Ocenę wywiadu losuje serwer na starcie.
-- W czasie sesji kliknięcia i teleport na Sell się nie liczą.

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared.Config.Economy)
local Loop = require(Shared.Logic.Loop)
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)
local LoopService = require(script.Parent.LoopService)
local ZoneService = require(script.Parent.ZoneService)

local ActivityService = {}

ActivityService.SpotTag = "LarpActivity" -- tag miejsc aktywności (klient szuka ich po tym tagu)
ActivityService.SpotNames = { Car = "CarSpot", Interview = "InterviewSpot", Yacht = "YachtSpot", Jet = "JetSpot" }
-- modele tierów w miejscu (Car1 … Car5, Yacht1 … Yacht5, Jet1 … Jet3); wywiad nie ma tierów
ActivityService.ItemPrefix = { Car = "Car", Yacht = "Yacht", Jet = "Jet" }

local MAX_DISTANCE = 20 -- tak blisko najbliższej części miejsca trzeba stać, żeby zacząć (studs)

local spots = {} -- [rodzaj] = { miejsca }
local sessions = {} -- [gracz] = { kind = rodzaj, grade = ocena }
local rng = Random.new()

function ActivityService.busy(player)
	return sessions[player] ~= nil
end

----------------------------------------------------------------- Miejsca na mapie
local function addSpot(inst, kind)
	local list = spots[kind]
	if list == nil then
		list = {}
		spots[kind] = list
	end
	for _, existing in ipairs(list) do
		if existing == inst then
			return
		end
	end
	inst:SetAttribute("Activity", kind)
	CollectionService:AddTag(inst, ActivityService.SpotTag)
	table.insert(list, inst)
end

local function scan()
	for _, inst in ipairs(Workspace:GetDescendants()) do
		if inst:IsA("Model") or inst:IsA("BasePart") then
			for kind, name in pairs(ActivityService.SpotNames) do
				if inst.Name == name then
					addSpot(inst, kind)
				end
			end
		end
	end
end

local function pivotOf(spot)
	if spot:IsA("Model") then
		return spot:GetPivot()
	end
	return spot.CFrame
end

-- Numer tieru modelu, do którego należy część (przodek „Car3”, „Yacht2” …), albo nil.
local function itemNumber(inst, spot, prefix)
	local node = inst
	while node ~= nil and node ~= spot do
		local n = tonumber(string.match(node.Name, "^" .. prefix .. "(%d+)$"))
		if n ~= nil then
			return n
		end
		node = node.Parent
	end
	return nil
end

-- Część „Pose”: najpierw w modelu z tieru gracza (np. na pokładzie jachtu), potem w samym miejscu.
local function findPose(spot, kind, tier)
	local prefix = ActivityService.ItemPrefix[kind]
	if prefix ~= nil then
		local item = spot:FindFirstChild(prefix .. tostring(tier), true)
		local pose = item and item:FindFirstChild("Pose", true)
		if pose ~= nil and pose:IsA("BasePart") then
			return pose
		end
	end
	if spot.Name == "Pose" and spot:IsA("BasePart") then
		return spot
	end
	for _, d in ipairs(spot:GetDescendants()) do
		if d.Name == "Pose" and d:IsA("BasePart") and (prefix == nil or itemNumber(d, spot, prefix) == nil) then
			return d
		end
	end
	return nil
end

-- Gdzie stoi gracz w czasie sesji: na części „Pose” albo 9 studs w bok od miejsca (na ziemi).
local function poseCFrame(spot, kind, tier)
	local pose = findPose(spot, kind, tier)
	local ground, look
	if pose ~= nil then
		ground = pose.Position + Vector3.new(0, pose.Size.Y / 2, 0)
		look = pose.CFrame.LookVector
	else
		local pivot = pivotOf(spot)
		local side = (pivot * CFrame.new(9, 0, 0)).Position
		ground = side
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		local ignore = { spot }
		for _, player in ipairs(Players:GetPlayers()) do
			if player.Character ~= nil then
				table.insert(ignore, player.Character)
			end
		end
		params.FilterDescendantsInstances = ignore
		local hit = Workspace:Raycast(side + Vector3.new(0, 10, 0), Vector3.new(0, -60, 0), params)
		if hit ~= nil then
			ground = hit.Position
		end
		look = pivot.RightVector
	end
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 0.1 then
		flat = Vector3.new(0, 0, -1)
	end
	local position = ground + Vector3.new(0, 3, 0)
	return CFrame.lookAt(position, position + flat.Unit)
end

local function distanceToPart(part, position)
	local p = part.CFrame:PointToObjectSpace(position)
	local half = part.Size / 2
	local dx = math.max(math.abs(p.X) - half.X, 0)
	local dy = math.max(math.abs(p.Y) - half.Y, 0)
	local dz = math.max(math.abs(p.Z) - half.Z, 0)
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function distanceToSpot(spot, position)
	if spot:IsA("BasePart") then
		return distanceToPart(spot, position)
	end
	local best = math.huge
	for _, d in ipairs(spot:GetDescendants()) do
		if d:IsA("BasePart") then
			best = math.min(best, distanceToPart(d, position))
		end
	end
	return best
end

local function nearestSpot(kind, position)
	local best, bestDistance = nil, MAX_DISTANCE
	for _, spot in ipairs(spots[kind] or {}) do
		if spot.Parent ~= nil then
			local distance = distanceToSpot(spot, position)
			if distance <= bestDistance then
				best, bestDistance = spot, distance
			end
		end
	end
	return best
end

----------------------------------------------------------------- Tymczasowe miejsce z autami
-- Proste auta z klocków, po jednym na tier (nazwy w grze są w Client/Activities).
local CAR_STYLES = {
	{ color = Color3.fromRGB(236, 240, 245), body = Vector3.new(7, 2.6, 13), cabin = Vector3.new(6.2, 2.2, 6.4), cabinZ = 0.6, wheel = 1.4 },
	{ color = Color3.fromRGB(32, 52, 92), body = Vector3.new(7.2, 2.4, 15), cabin = Vector3.new(6.4, 2, 7), cabinZ = 0.4, wheel = 1.45 },
	{ color = Color3.fromRGB(245, 130, 32), body = Vector3.new(7.6, 2.6, 15.5), cabin = Vector3.new(6.4, 1.8, 6), cabinZ = 1.2, wheel = 1.55 },
	{ color = Color3.fromRGB(220, 30, 45), body = Vector3.new(7.8, 2, 16), cabin = Vector3.new(6, 1.5, 6), cabinZ = 0, wheel = 1.5 },
	{
		color = Color3.fromRGB(25, 25, 30),
		body = Vector3.new(8, 1.8, 16.5),
		cabin = Vector3.new(5.6, 1.4, 5.6),
		cabinZ = 0.6,
		wheel = 1.55,
		trim = Color3.fromRGB(245, 190, 50),
	},
}

local function block(parent, name, size, cframe, color, material, transparency)
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.Transparency = transparency or 0
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

-- Auto stoi na ramce frame (środek na ziemi, przód w stronę -Z ramki).
local function buildCar(parent, n, style, frame)
	local model = Instance.new("Model")
	model.Name = "Car" .. n
	local r = style.wheel
	local body = style.body
	local bodyY = r * 0.6 + body.Y / 2
	local bodyPart = block(model, "Body", body, frame * CFrame.new(0, bodyY, 0), style.color)
	block(
		model,
		"Cabin",
		style.cabin,
		frame * CFrame.new(0, bodyY + body.Y / 2 + style.cabin.Y / 2, style.cabinZ),
		Color3.fromRGB(40, 55, 75),
		Enum.Material.Glass,
		0.15
	)
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			local wheel = block(
				model,
				"Wheel",
				Vector3.new(1.1, 2 * r, 2 * r),
				frame * CFrame.new(sx * (body.X / 2 - 0.35), r, sz * (body.Z / 2 - r - 0.9)),
				Color3.fromRGB(30, 30, 35)
			)
			wheel.Shape = Enum.PartType.Cylinder
		end
		block(
			model,
			"Headlight",
			Vector3.new(1.2, 0.5, 0.2),
			frame * CFrame.new(sx * (body.X / 2 - 1.2), bodyY + body.Y * 0.15, -body.Z / 2 - 0.05),
			Color3.fromRGB(255, 245, 210),
			Enum.Material.Neon
		)
		block(
			model,
			"Taillight",
			Vector3.new(1.2, 0.4, 0.2),
			frame * CFrame.new(sx * (body.X / 2 - 1.2), bodyY + body.Y * 0.15, body.Z / 2 + 0.05),
			Color3.fromRGB(255, 40, 60),
			Enum.Material.Neon
		)
	end
	if style.trim ~= nil then
		block(model, "Stripe", Vector3.new(0.8, 0.1, body.Z - 2), frame * CFrame.new(0, bodyY + body.Y / 2 + 0.05, 0), style.trim, Enum.Material.Neon)
		local wingY = bodyY + body.Y / 2 + 0.6
		block(model, "Spoiler", Vector3.new(body.X - 1, 0.25, 1.2), frame * CFrame.new(0, wingY, body.Z / 2 - 0.8), style.trim)
		for _, sx in ipairs({ -1, 1 }) do
			block(
				model,
				"SpoilerPost",
				Vector3.new(0.25, 0.6, 0.4),
				frame * CFrame.new(sx * (body.X / 2 - 1.5), wingY - 0.4, body.Z / 2 - 0.8),
				style.color
			)
		end
	end
	model.PrimaryPart = bodyPart
	model.Parent = parent
	return model
end

local function buildPlaceholderCarSpot()
	local floor = ZoneService.floorPart(Economy.Activities.Car.Zone)
	if floor == nil then
		warn("[Aktywności] Strefa 2 nie ma podłogi (Zone2), więc nie ma gdzie postawić CarSpot.")
		return
	end
	-- z boku ścieżki, na górze podłogi strefy
	local top = floor.CFrame * CFrame.new(0, floor.Size.Y / 2, 0)
	local side = math.min(25, math.max(0, floor.Size.X / 2 - 14))
	local frame = top * CFrame.new(-side, 0.6, 0)

	local spot = Instance.new("Model")
	spot.Name = ActivityService.SpotNames.Car
	local platform = Instance.new("Part")
	platform.Name = "Platform"
	platform.Anchored = true
	platform.Size = Vector3.new(24, 0.6, 32)
	platform.CFrame = frame * CFrame.new(0, -0.3, 0)
	platform.Color = Color3.fromRGB(55, 60, 72)
	platform.Material = Enum.Material.SmoothPlastic
	platform.TopSurface = Enum.SurfaceType.Smooth
	platform.Parent = spot
	for n, style in ipairs(CAR_STYLES) do
		if Economy.Activities.Car.Tiers[n] ~= nil then
			buildCar(spot, n, style, frame)
		end
	end
	-- gracz stoi obok auta, przodem do środka ścieżki (Pose to cienki, niewidoczny znacznik na podłodze)
	local posePosition = (frame * CFrame.new(8.5, 0.1, 2)).Position
	local pose = block(
		spot,
		"Pose",
		Vector3.new(2, 0.2, 2),
		CFrame.lookAt(posePosition, posePosition + frame.RightVector),
		Color3.new(1, 1, 1),
		Enum.Material.SmoothPlastic,
		1
	)
	pose.CanQuery = false
	spot.WorldPivot = frame -- środek platformy na jej górze (wokół niego kręci się kamera)
	spot.Parent = Workspace
	print("[Aktywności] Na mapie nie ma CarSpot, więc w strefie 2 stoi tymczasowe miejsce na zdjęcia z autem.")
end

----------------------------------------------------------------- Tymczasowe miejsca w strefach 3–5
local WHITE = Color3.fromRGB(245, 247, 250)
local DARK = Color3.fromRGB(40, 40, 46)

local function zoneTop(zone)
	local floor = ZoneService.floorPart(zone)
	if floor == nil then
		return nil, nil
	end
	return floor.CFrame * CFrame.new(0, floor.Size.Y / 2, 0), floor
end

-- Jak block, ale da się po tym chodzić (kolizje).
local function solid(parent, name, size, cframe, color, material, transparency)
	local part = block(parent, name, size, cframe, color, material, transparency)
	part.CanCollide = true
	return part
end

-- Niewidoczny znacznik miejsca gracza (przodem tam, gdzie patrzy cframe).
local function poseMarker(parent, cframe)
	local pose = block(parent, "Pose", Vector3.new(2, 0.2, 2), cframe, Color3.new(1, 1, 1), Enum.Material.SmoothPlastic, 1)
	pose.CanQuery = false
	return pose
end

local function facing(position, direction)
	return CFrame.lookAt(position, position + direction)
end

-- Wywiad: studio z tłem, biurkiem prowadzącego, kanapą, światłami i kamerą, przodem do ścieżki.
local function buildPlaceholderInterview()
	local zone = Economy.Activities.Interview.Zone
	local top, floor = zoneTop(zone)
	if top == nil then
		warn(string.format("[Aktywności] Strefa %d nie ma podłogi (Zone%d), więc nie ma gdzie postawić InterviewSpot.", zone, zone))
		return
	end
	local side = math.min(25, math.max(0, floor.Size.X / 2 - 14))
	local base = top * CFrame.new(-side, 0, 0)
	local set = facing(base.Position, base.RightVector) -- przód studia (-Z) w stronę ścieżki
	local spot = Instance.new("Model")
	spot.Name = ActivityService.SpotNames.Interview
	local floorY = 0.8
	solid(spot, "Stage", Vector3.new(22, floorY, 16), set * CFrame.new(0, floorY / 2, 2), Color3.fromRGB(42, 31, 61))
	solid(spot, "Step", Vector3.new(10, 0.4, 2), set * CFrame.new(0, 0.2, -7), Color3.fromRGB(60, 46, 88))
	-- tło z neonami i napisem ON AIR
	solid(spot, "Backdrop", Vector3.new(22, 12, 0.8), set * CFrame.new(0, floorY + 6, 9.6), Color3.fromRGB(59, 42, 107))
	block(spot, "NeonPink", Vector3.new(20, 0.4, 0.3), set * CFrame.new(0, floorY + 2.5, 9.1), Color3.fromRGB(255, 79, 163), Enum.Material.Neon)
	block(spot, "NeonCyan", Vector3.new(20, 0.4, 0.3), set * CFrame.new(0, floorY + 10.5, 9.1), Color3.fromRGB(56, 217, 255), Enum.Material.Neon)
	local sign = block(spot, "OnAir", Vector3.new(4.2, 1.4, 0.3), set * CFrame.new(-6.5, floorY + 8.6, 9), Color3.fromRGB(220, 30, 45), Enum.Material.Neon)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.LightInfluence = 0
	gui.Parent = sign
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.Text = "ON AIR"
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Parent = gui
	-- biurko i prowadzący (z klocków)
	local deskX, hostZ = 4, 3.2
	solid(spot, "Desk", Vector3.new(5, 2.6, 2.2), set * CFrame.new(deskX, floorY + 1.3, 1.5), WHITE)
	block(spot, "DeskTrim", Vector3.new(5.1, 0.3, 2.3), set * CFrame.new(deskX, floorY + 2.6, 1.5), Color3.fromRGB(255, 196, 60), Enum.Material.Neon)
	block(spot, "HostTorso", Vector3.new(2, 2, 1), set * CFrame.new(deskX, floorY + 3.2, hostZ), Color3.fromRGB(30, 30, 40))
	block(spot, "HostHead", Vector3.new(1.2, 1.2, 1.2), set * CFrame.new(deskX, floorY + 4.8, hostZ), Color3.fromRGB(255, 205, 160))
	for _, sx in ipairs({ -1, 1 }) do
		block(spot, "HostArm", Vector3.new(1, 2, 1), set * CFrame.new(deskX + sx * 1.5, floorY + 3.2, hostZ), Color3.fromRGB(30, 30, 40))
	end
	block(spot, "Mic", Vector3.new(0.2, 1, 0.2), set * CFrame.new(deskX - 1.2, floorY + 3.1, 1), DARK)
	-- kanapa za gościem
	solid(spot, "Sofa", Vector3.new(5, 1.2, 2.4), set * CFrame.new(-5, floorY + 0.6, 5.5), Color3.fromRGB(200, 40, 90))
	solid(spot, "SofaBack", Vector3.new(5, 2.2, 0.8), set * CFrame.new(-5, floorY + 1.6, 6.5), Color3.fromRGB(200, 40, 90))
	-- światła i kamera telewizyjna przed sceną
	for _, sx in ipairs({ -1, 1 }) do
		block(spot, "LightStand", Vector3.new(0.3, 7, 0.3), set * CFrame.new(sx * 10, 3.5, -6), DARK)
		block(spot, "LightBox", Vector3.new(1.6, 1.2, 1), set * CFrame.new(sx * 10, 7.2, -6) * CFrame.Angles(math.rad(-20), 0, 0), Color3.fromRGB(255, 250, 220), Enum.Material.Neon)
	end
	block(spot, "CameraBody", Vector3.new(1.4, 1.4, 2.2), set * CFrame.new(1, 5.2, -11), Color3.fromRGB(30, 30, 36))
	local lens = block(spot, "CameraLens", Vector3.new(0.9, 0.9, 0.9), set * CFrame.new(1, 5.2, -9.8), Color3.fromRGB(60, 120, 200), Enum.Material.Glass)
	lens.Shape = Enum.PartType.Ball
	for i = 1, 3 do
		local angle = (i - 1) * 2 * math.pi / 3
		block(
			spot,
			"TripodLeg",
			Vector3.new(0.2, 5, 0.2),
			set * CFrame.new(1 + math.cos(angle) * 0.8, 2.4, -11 + math.sin(angle) * 0.8) * CFrame.Angles(math.sin(angle) * 0.2, 0, -math.cos(angle) * 0.2),
			DARK
		)
	end
	-- gość stoi przy kanapie, przodem do widowni
	poseMarker(spot, facing((set * CFrame.new(-3.5, floorY + 0.1, 0.5)).Position, set.LookVector))
	spot.WorldPivot = set * CFrame.new(0, floorY, 2) -- środek sceny, przodem do widowni (kamery)
	spot.Parent = Workspace
	print("[Aktywności] Na mapie nie ma InterviewSpot, więc w strefie 3 stoi tymczasowe studio.")
end

-- Jachty z klocków: kadłub ze szpicem, pokład, piętra nadbudówki, na największym lądowisko.
local YACHT_STYLES = {
	{ length = 12, width = 5, hull = 1.6, decks = 1, color = WHITE, trim = Color3.fromRGB(40, 120, 220) },
	{ length = 18, width = 6.5, hull = 2, decks = 1, color = WHITE, trim = Color3.fromRGB(25, 45, 90) },
	{ length = 25, width = 8, hull = 2.4, decks = 2, color = WHITE, trim = Color3.fromRGB(25, 45, 90) },
	{ length = 32, width = 9.5, hull = 2.8, decks = 3, color = Color3.fromRGB(28, 34, 52), trim = Color3.fromRGB(255, 196, 60) },
	{ length = 40, width = 11, hull = 3.2, decks = 3, color = WHITE, trim = Color3.fromRGB(255, 196, 60), helipad = true },
}

-- Jacht na ramce frame (środek na wodzie, dziób w stronę -Z ramki). W jachcie jest jego „Pose” (dziób).
local function buildYacht(parent, n, style, frame)
	local model = Instance.new("Model")
	model.Name = "Yacht" .. n
	local L, W, H = style.length, style.width, style.hull
	local body = L - W * 0.7
	local bodyZ = W * 0.35
	local hullY = H * 0.15
	solid(model, "Hull", Vector3.new(W, H, body), frame * CFrame.new(0, hullY, bodyZ), style.color)
	local bowSide = W / math.sqrt(2)
	solid(model, "Bow", Vector3.new(bowSide, H, bowSide), frame * CFrame.new(0, hullY, bodyZ - body / 2) * CFrame.Angles(0, math.rad(45), 0), style.color)
	local deckY = hullY + H / 2
	solid(model, "Deck", Vector3.new(W - 0.6, 0.2, body - 0.6), frame * CFrame.new(0, deckY + 0.1, bodyZ), Color3.fromRGB(196, 150, 100), Enum.Material.WoodPlanks)
	block(model, "Stripe", Vector3.new(W + 0.06, 0.35, body), frame * CFrame.new(0, deckY - 0.5, bodyZ), style.trim)
	-- piętra nadbudówki, każde trochę mniejsze
	local cabinLength = body * 0.45
	local cabinZ = bodyZ + body * 0.08
	local y = deckY + 0.2
	for d = 1, style.decks do
		local shrink = (d - 1) * 0.18
		local cw = (W - 1.6) * (1 - shrink)
		local cl = cabinLength * (1 - shrink * 1.2)
		solid(model, "Cabin", Vector3.new(cw, 2.2, cl), frame * CFrame.new(0, y + 1.1, cabinZ), Color3.fromRGB(240, 242, 246))
		block(model, "Windows", Vector3.new(cw + 0.06, 0.7, cl * 0.85), frame * CFrame.new(0, y + 1.2, cabinZ), Color3.fromRGB(30, 40, 60), Enum.Material.Glass, 0.1)
		y = y + 2.2
	end
	if style.helipad then
		local padZ = bodyZ + body / 2 - W * 0.55
		local pad = solid(model, "Helipad", Vector3.new(0.3, W - 1.4, W - 1.4), frame * CFrame.new(0, deckY + 0.35, padZ) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(60, 60, 70))
		pad.Shape = Enum.PartType.Cylinder
		for _, piece in ipairs({ { -0.9, 0.5, 2.6 }, { 0.9, 0.5, 2.6 }, { 0, 1.8, 0.5 } }) do
			block(model, "HelipadH", Vector3.new(piece[2], 0.1, piece[3]), frame * CFrame.new(piece[1], deckY + 0.52, padZ), WHITE, Enum.Material.Neon)
		end
	end
	-- gracz stoi na dziobie, bokiem do pomostu (w stronę ścieżki)
	poseMarker(model, facing((frame * CFrame.new(0, deckY + 0.3, bodyZ - body / 2 + 2.6)).Position, frame.RightVector))
	model.WorldPivot = frame
	model.Parent = parent
	return model
end

-- Impreza na jachcie: basen z wodą, niski murek, pomost i 5 jachtów (każdy gracz widzi swój).
local function buildPlaceholderYacht()
	local zone = Economy.Activities.Yacht.Zone
	local top, floor = zoneTop(zone)
	if top == nil then
		warn(string.format("[Aktywności] Strefa %d nie ma podłogi (Zone%d), więc nie ma gdzie postawić YachtSpot.", zone, zone))
		return
	end
	local side = math.min(24, math.max(0, floor.Size.X / 2 - 16))
	local base = top * CFrame.new(-side, 0, 0)
	local spot = Instance.new("Model")
	spot.Name = ActivityService.SpotNames.Yacht
	local poolW, poolL = 30, math.min(58, floor.Size.Z - 8)
	block(spot, "Water", Vector3.new(poolW, 0.3, poolL), base * CFrame.new(0, 0.15, 0), Color3.fromRGB(40, 170, 230), Enum.Material.Glass, 0.3)
	for _, sx in ipairs({ -1, 1 }) do
		solid(spot, "Rim", Vector3.new(1, 0.5, poolL + 2), base * CFrame.new(sx * (poolW / 2 + 0.5), 0.25, 0), WHITE)
	end
	for _, sz in ipairs({ -1, 1 }) do
		solid(spot, "Rim", Vector3.new(poolW, 0.5, 1), base * CFrame.new(0, 0.25, sz * (poolL / 2 + 0.5)), WHITE)
	end
	solid(spot, "Pier", Vector3.new(5, 0.4, 22), base * CFrame.new(poolW / 2 - 2.5, 0.45, 0), Color3.fromRGB(170, 120, 75), Enum.Material.WoodPlanks)
	local frame = base * CFrame.new(0, 0.3, 0)
	for n, style in ipairs(YACHT_STYLES) do
		if Economy.Activities.Yacht.Tiers[n] ~= nil then
			buildYacht(spot, n, style, frame)
		end
	end
	-- zapasowe miejsce gracza na pomoście (gdy jacht nie ma swojej Pose)
	poseMarker(spot, facing((base * CFrame.new(poolW / 2 - 2.5, 0.7, -4)).Position, -base.RightVector))
	spot.WorldPivot = frame -- środek basenu na wodzie (wokół niego krąży kamera)
	spot.Parent = Workspace
	print("[Aktywności] Na mapie nie ma YachtSpot, więc w strefie 4 stoi tymczasowy basen z jachtami.")
end

-- Odrzutowce z klocków: kadłub, dziób, skrzydła, statecznik, silniki, okna i podwozie.
local JET_STYLES = {
	{ length = 22, diameter = 3, span = 18, color = WHITE, stripe = Color3.fromRGB(255, 196, 60) },
	{ length = 28, diameter = 3.6, span = 22, color = WHITE, stripe = Color3.fromRGB(25, 45, 90) },
	{ length = 36, diameter = 4.4, span = 28, color = Color3.fromRGB(28, 28, 34), stripe = Color3.fromRGB(255, 196, 60) },
}

-- Odrzutowiec na ramce frame (na ziemi, dziób w stronę -Z ramki). Punkt obrotu = frame: w tę stronę
-- samolot startuje u gracza.
local function buildJet(parent, n, style, frame)
	local model = Instance.new("Model")
	model.Name = "Jet" .. n
	local L, D = style.length, style.diameter
	local gear = 1.3
	local cy = gear + D / 2
	local body = L - D
	local fuselage = solid(model, "Fuselage", Vector3.new(body, D, D), frame * CFrame.new(0, cy, 0) * CFrame.Angles(0, math.rad(90), 0), style.color)
	fuselage.Shape = Enum.PartType.Cylinder
	local nose = solid(model, "Nose", Vector3.new(D, D, D), frame * CFrame.new(0, cy, -body / 2), style.color)
	nose.Shape = Enum.PartType.Ball
	local tail = solid(model, "TailCone", Vector3.new(D * 0.9, D * 0.9, D * 0.9), frame * CFrame.new(0, cy, body / 2), style.color)
	tail.Shape = Enum.PartType.Ball
	solid(model, "Wing", Vector3.new(style.span, 0.35, D * 1.7), frame * CFrame.new(0, cy - D * 0.25, D * 0.4), style.color)
	solid(model, "TailFin", Vector3.new(0.35, D * 1.4, D * 1.1), frame * CFrame.new(0, cy + D * 0.9, body / 2 - D * 0.3), style.color)
	solid(model, "Stabilizer", Vector3.new(style.span * 0.36, 0.3, D * 0.8), frame * CFrame.new(0, cy + D * 1.45, body / 2 - D * 0.3), style.color)
	for _, sx in ipairs({ -1, 1 }) do
		local engine = solid(
			model,
			"Engine",
			Vector3.new(D * 1.4, D * 0.55, D * 0.55),
			frame * CFrame.new(sx * D * 0.75, cy + D * 0.15, body / 2 - D * 1.3) * CFrame.Angles(0, math.rad(90), 0),
			Color3.fromRGB(70, 74, 86)
		)
		engine.Shape = Enum.PartType.Cylinder
	end
	block(model, "Stripe", Vector3.new(D + 0.06, 0.35, body * 0.9), frame * CFrame.new(0, cy - D * 0.1, 0), style.stripe)
	block(model, "Windows", Vector3.new(D + 0.04, 0.45, body * 0.55), frame * CFrame.new(0, cy + D * 0.18, -body * 0.08), Color3.fromRGB(30, 40, 60), Enum.Material.Glass)
	for _, offset in ipairs({ Vector3.new(0, 0, -body / 2 + D * 0.3), Vector3.new(-D * 0.9, 0, D * 0.5), Vector3.new(D * 0.9, 0, D * 0.5) }) do
		local wheel = solid(model, "Wheel", Vector3.new(0.6, 1.1, 1.1), frame * CFrame.new(offset.X, 0.55, offset.Z), Color3.fromRGB(30, 30, 35))
		wheel.Shape = Enum.PartType.Cylinder
		local leg = gear - 0.55 + D * 0.2
		block(model, "GearLeg", Vector3.new(0.25, leg, 0.25), frame * CFrame.new(offset.X, 0.55 + leg / 2, offset.Z), Color3.fromRGB(150, 150, 160))
	end
	model.WorldPivot = frame
	model.Parent = parent
	return model
end

-- Lot odrzutowcem: pas startowy z liniami i 3 odrzutowce (każdy gracz widzi swój).
local function buildPlaceholderJet()
	local zone = Economy.Activities.Jet.Zone
	local top, floor = zoneTop(zone)
	if top == nil then
		warn(string.format("[Aktywności] Strefa %d nie ma podłogi (Zone%d), więc nie ma gdzie postawić JetSpot.", zone, zone))
		return
	end
	local side = math.min(28, math.max(0, floor.Size.X / 2 - 12))
	local base = top * CFrame.new(-side, 0, 0)
	local spot = Instance.new("Model")
	spot.Name = ActivityService.SpotNames.Jet
	local runway = math.min(140, floor.Size.Z - 10)
	solid(spot, "Runway", Vector3.new(20, 0.3, runway), base * CFrame.new(0, 0.15, 0), Color3.fromRGB(45, 45, 52))
	for _, sx in ipairs({ -1, 1 }) do
		block(spot, "EdgeLine", Vector3.new(0.5, 0.05, runway - 2), base * CFrame.new(sx * 9.2, 0.32, 0), WHITE)
	end
	for i = 0, math.floor((runway - 10) / 10) do
		block(spot, "CenterLine", Vector3.new(0.6, 0.05, 5), base * CFrame.new(0, 0.32, -runway / 2 + 5 + i * 10), WHITE)
	end
	-- odrzutowce stoją przy początku pasa, dziobem w głąb strefy
	local frame = base * CFrame.new(0, 0.3, runway / 2 - 24)
	for n, style in ipairs(JET_STYLES) do
		if Economy.Activities.Jet.Tiers[n] ~= nil then
			buildJet(spot, n, style, frame)
		end
	end
	poseMarker(spot, facing((frame * CFrame.new(5.5, 0.1, -4)).Position, frame.RightVector))
	-- tablica nad samolotem, a nie nad środkiem pasa
	local anchor = block(spot, "SignAnchor", Vector3.new(1, 1, 1), frame * CFrame.new(0, 2, 0), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic, 1)
	anchor.CanQuery = false
	spot.WorldPivot = frame
	spot.Parent = Workspace
	print("[Aktywności] Na mapie nie ma JetSpot, więc w strefie 5 stoi tymczasowy pas z odrzutowcami.")
end

local PLACEHOLDERS = {
	Car = buildPlaceholderCarSpot,
	Interview = buildPlaceholderInterview,
	Yacht = buildPlaceholderYacht,
	Jet = buildPlaceholderJet,
}

----------------------------------------------------------------- Sesja
local function release(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root ~= nil then
		root.Anchored = false
	end
end

local function pose(player, spot, kind)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if character == nil or root == nil or spot.Parent == nil then
		return
	end
	local data = DataService.get(player)
	local tier = 1
	if data ~= nil then
		tier = Loop.activityTier(data, kind)
	end
	local target = poseCFrame(spot, kind, tier)
	-- Najpierw zatrzymanie, potem przestawienie. Odwrotnie (jak było) gracz, który akurat skakał albo
	-- spadał, zdążył się jeszcze u siebie podnieść, zanim doszło zatrzymanie, i wisiał w powietrzu
	-- przez całą sesję (postacią steruje jego komputer).
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	root.Anchored = true
	character:PivotTo(target)
	-- dla pewności jeszcze dwa razy po chwili (inna wartość niż poprzednio, bo taka sama by nie doszła)
	local session = sessions[player]
	task.delay(0.3, function()
		if sessions[player] == session and root.Parent ~= nil and root.Anchored then
			character:PivotTo(target * CFrame.new(0, 0.001, 0))
		end
	end)
	task.delay(1, function()
		if sessions[player] == session and root.Parent ~= nil and root.Anchored then
			character:PivotTo(target)
		end
	end)
end

local function finish(player, kind, grade)
	local data = DataService.get(player)
	if data == nil then
		return
	end
	local reward, added, sold = Loop.finishActivity(data, LoopService.contextFor(player), kind, grade)
	LoopService.markDirty(player)
	-- LP = ile naprawdę weszło do Bag (najwyżej do pełna), Reward = pełna nagroda za sesję
	LoopService.notify(player, { Kind = "ActivityEnd", Activity = kind, LP = added, Reward = reward, Grade = grade })
	if sold > 0 then
		LoopService.notify(player, { Kind = "Sold", Cash = sold, Auto = true })
	end
end

local function start(player, kind)
	if type(kind) ~= "string" or ActivityService.SpotNames[kind] == nil then
		return { Ok = false, Reason = "BadRequest" }
	end
	if sessions[player] ~= nil then
		return { Ok = false, Reason = "Busy" }
	end
	local data = DataService.get(player)
	if data == nil then
		return { Ok = false, Reason = "NotLoaded" }
	end
	local ok, reason = Loop.canStartActivity(data, LoopService.contextFor(player), kind)
	if not ok then
		return { Ok = false, Reason = reason }
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if humanoid == nil or root == nil or humanoid.Health <= 0 then
		return { Ok = false, Reason = "NoCharacter" }
	end
	local spot = nearestSpot(kind, root.Position)
	if spot == nil then
		return { Ok = false, Reason = "TooFar" }
	end

	local activity = Economy.Activities[kind]
	local half = activity.TransitionSeconds / 2
	-- ocenę wywiadu losujemy od razu, żeby klient mógł ją pokazać w trakcie (licznik wyświetleń)
	local grade = Loop.rollGrade(kind, function()
		return rng:NextNumber()
	end)
	local session = { kind = kind, grade = grade }
	sessions[player] = session
	LoopService.markDirty(player)
	LoopService.notify(player, {
		Kind = "ActivityStart",
		Activity = kind,
		Spot = spot,
		Duration = activity.DurationSeconds,
		Transition = activity.TransitionSeconds,
		Grade = grade,
	})
	task.spawn(function()
		task.wait(half)
		if sessions[player] ~= session then
			return
		end
		pose(player, spot, kind)
		task.wait(activity.DurationSeconds)
		if sessions[player] ~= session then
			return
		end
		release(player)
		finish(player, kind, session.grade)
		task.wait(half)
		if sessions[player] == session then
			sessions[player] = nil
			LoopService.markDirty(player)
		end
	end)
	return { Ok = true }
end

local function buyTier(player, kind)
	if type(kind) ~= "string" or ActivityService.SpotNames[kind] == nil then
		return { Ok = false, Reason = "BadRequest" }
	end
	local data = DataService.get(player)
	if data == nil then
		return { Ok = false, Reason = "NotLoaded" }
	end
	local ok, reason = Loop.buyActivityTier(data, kind)
	if not ok then
		return { Ok = false, Reason = reason }
	end
	LoopService.markDirty(player)
	return { Ok = true, Tier = Loop.activityTier(data, kind) }
end

----------------------------------------------------------------- Start
function ActivityService.start()
	scan()
	for kind, build in pairs(PLACEHOLDERS) do
		if spots[kind] == nil then
			build()
		end
	end
	scan()

	LoopService.addBusyCheck(ActivityService.busy)
	LoopService.addViewHook(function(player, view)
		local session = sessions[player]
		if session ~= nil then
			view.ActivityBusy = session.kind
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		sessions[player] = nil
	end)
	Net.func("StartActivity").OnServerInvoke = start
	Net.func("BuyActivityTier").OnServerInvoke = buyTier
end

return ActivityService
