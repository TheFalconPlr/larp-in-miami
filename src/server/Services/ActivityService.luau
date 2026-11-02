-- Aktywności w strefach. Etap 4: sesja zdjęciowa z autem w Luxury Cars (strefa 2).
--
-- Jak oznaczyć miejsce w Studio:
--   Model (albo część) o nazwie „CarSpot” w strefie 2. W modelu mogą być:
--     • auta „Car1” … „Car5” (po jednym na tier, w tym samym miejscu): klient pokazuje tylko auto
--       z tieru gracza, a pozostałe są u niego niewidoczne i bez kolizji,
--     • część „Pose”: tu stoi gracz w czasie sesji (przodem tam, gdzie patrzy przód części).
--   Gdy na mapie nie ma CarSpot, serwer stawia tymczasowe (platforma i 5 prostych aut) w strefie 2.
--
-- Sesja: klient prosi o start (StartActivity) przy aucie. Serwer sprawdza strefę, tier, Bag i odległość,
-- po połowie przejścia (TransitionSeconds z arkusza) stawia gracza w miejscu Pose i go zatrzymuje,
-- po DurationSeconds daje LP do Bag (Loop.finishActivity) i puszcza gracza, a po drugiej połowie
-- przejścia można zacząć kolejną sesję. W czasie sesji kliknięcia i teleport na Sell się nie liczą.

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
ActivityService.SpotNames = { Car = "CarSpot" }

local MAX_DISTANCE = 30 -- tak blisko środka miejsca trzeba stać, żeby zacząć (studs)

local spots = {} -- [rodzaj] = { miejsca }
local sessions = {} -- [gracz] = { kind = rodzaj }

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

-- Gdzie stoi gracz w czasie sesji: na części „Pose” albo 9 studs w bok od miejsca (na ziemi).
local function poseCFrame(spot)
	local pose = spot:FindFirstChild("Pose", true)
	local ground, look
	if pose ~= nil and pose:IsA("BasePart") then
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

local function nearestSpot(kind, position)
	local best, bestDistance = nil, MAX_DISTANCE
	for _, spot in ipairs(spots[kind] or {}) do
		if spot.Parent ~= nil then
			local distance = (pivotOf(spot).Position - position).Magnitude
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

----------------------------------------------------------------- Sesja
local function release(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root ~= nil then
		root.Anchored = false
	end
end

local function pose(player, spot)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if character == nil or root == nil or spot.Parent == nil then
		return
	end
	character:PivotTo(poseCFrame(spot))
	root.Anchored = true
end

local function finish(player, kind)
	local data = DataService.get(player)
	if data == nil then
		return
	end
	local reward, _, sold = Loop.finishActivity(data, LoopService.contextFor(player), kind)
	LoopService.markDirty(player)
	LoopService.notify(player, { Kind = "ActivityEnd", Activity = kind, LP = reward })
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
	local session = { kind = kind }
	sessions[player] = session
	LoopService.markDirty(player)
	LoopService.notify(player, {
		Kind = "ActivityStart",
		Activity = kind,
		Spot = spot,
		Duration = activity.DurationSeconds,
		Transition = activity.TransitionSeconds,
	})
	task.spawn(function()
		task.wait(half)
		if sessions[player] ~= session then
			return
		end
		pose(player, spot)
		task.wait(activity.DurationSeconds)
		if sessions[player] ~= session then
			return
		end
		release(player)
		finish(player, kind)
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
	if spots.Car == nil then
		buildPlaceholderCarSpot()
		scan()
	end

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
