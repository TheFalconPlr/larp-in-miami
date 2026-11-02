-- Aktywności po stronie gracza. Etap 4: sesja zdjęciowa z autem w Luxury Cars.
-- Na miejscu CarSpot gracz widzi tylko auto ze swojego tieru (Car1 … Car5, inne są u niego niewidoczne).
-- Nad miejscem wisi tablica, a przy aucie otwiera się okno: start sesji, nagroda i kupno lepszego auta.
-- Sesja: zaciemnienie, kamera krąży wokół auta, flesze, pasek czasu, inni gracze są ukryci,
-- kliknięcia nie działają, a na końcu jest nagroda. Start i nagrodę sprawdza serwer (ActivityService).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared.Config.Economy)
local Format = require(Shared.Format)
local Net = require(Shared.Net)
local State = require(script.Parent.State)
local Theme = require(script.Parent.Ui.Theme)
local Kit = require(script.Parent.Ui.Kit)
local Sounds = require(script.Parent.Ui.Sounds)
local LocalHide = require(script.Parent.LocalHide)

local Activities = {}

local SPOT_TAG = "LarpActivity" -- ten sam tag co ActivityService.SpotTag na serwerze
local OPEN_DISTANCE = 5.5 -- okno otwiera się, gdy stoisz przy aucie (tyle studs od auta albo bliżej)
local CLOSE_DISTANCE = 10 -- tak daleko od auta okno się zamyka
local FLASH_EVERY = 1.6 -- co tyle sekund błyska flesz

local TEXT = {
	Title = "Car Photoshoot",
	SignTitle = "CAR PHOTOSHOOT",
	-- nazwy aut w grze (tiery 1–5 z arkusza); zmień je tu, gdy wybierzesz prawdziwe auta
	CarNames = { "Rental Compact", "German Sedan", "Muscle Car", "Italian Supercar", "Hypercar" },
	Reward = "Reward:",
	PerShoot = "per photoshoot",
	Start = "START",
	Upgrade = "UPGRADE",
	Maxed = "MAXED",
	Next = "Next:",
	BestCar = "Best car unlocked!",
	Photoshoot = "PHOTOSHOOT",
	Done = "Photoshoot done!",
	BagFull = "Bag full! Sell first",
	BagLimit = "(Bag limit)", -- nagroda większa niż wolne miejsce w Bag
	TooFar = "Get closer to the car",
	NewCar = "New car:",
}

local spots = {} -- lista miejsc (Model albo część z tagiem i atrybutem Activity)
local carTier = 1 -- tier auta gracza (ze stanu od serwera)

local function carName(tier)
	return TEXT.CarNames[tier] or ("Car " .. tier)
end

local function carMultiplier(tier)
	local info = Economy.Activities.Car.Tiers[tier]
	return "×" .. Format.small((info and info.Multiplier) or 0)
end

local function pivotOf(spot)
	if spot:IsA("Model") then
		return spot:GetPivot()
	end
	return spot.CFrame
end

----------------------------------------------------------------- Auta według tieru
-- Numer auta, do którego należy część (przodek o nazwie CarN wewnątrz miejsca), albo nil.
local function carNumber(part, spot)
	local node = part
	while node ~= nil and node ~= spot do
		local n = tonumber(string.match(node.Name, "^Car(%d+)$"))
		if n ~= nil then
			return n
		end
		node = node.Parent
	end
	return nil
end

local function applyCars(spot)
	for _, d in ipairs(spot:GetDescendants()) do
		if d:IsA("BasePart") then
			local n = carNumber(d, spot)
			if n ~= nil then
				LocalHide.set(d, n ~= carTier)
			end
		end
	end
end

----------------------------------------------------------------- Start
function Activities.start(hud)
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	------------------------------------------------------------- Tablice nad miejscami
	local signs = {} -- [miejsce] = { gui, reward }
	local function biggestPart(spot)
		if spot:IsA("BasePart") then
			return spot
		end
		local best, bestSize = nil, -1
		for _, d in ipairs(spot:GetDescendants()) do
			if d:IsA("BasePart") and carNumber(d, spot) == nil then
				local size = d.Size.X * d.Size.Z
				if size > bestSize then
					best, bestSize = d, size
				end
			end
		end
		return best
	end

	local function updateSign(spot)
		local sign = signs[spot]
		local view = State.view
		if sign == nil then
			return
		end
		local adornee = biggestPart(spot)
		sign.gui.Adornee = adornee
		local unlocked = view ~= nil and (view.ZonesUnlocked or 1) >= Economy.Activities.Car.Zone
		sign.gui.Enabled = adornee ~= nil and unlocked
		local info = view and view.Activities and view.Activities.Car
		if info ~= nil then
			sign.reward.Text = "+" .. Format.number(info.Reward) .. " LP " .. TEXT.PerShoot
		end
	end

	local function makeSign(spot)
		local gui = Kit.new("BillboardGui", {
			Name = "PhotoshootSign",
			Size = UDim2.fromScale(18, 5),
			StudsOffsetWorldSpace = Vector3.new(0, 13, 0),
			LightInfluence = 0,
			MaxDistance = 160,
			ResetOnSpawn = false,
			Enabled = false,
			Parent = playerGui,
		})
		Kit.text(gui, { Size = UDim2.fromScale(1, 0.6), Text = TEXT.SignTitle }, { maxSize = 100, stroke = 3.5 })
		local reward = Kit.text(gui, {
			Position = UDim2.fromScale(0, 0.6),
			Size = UDim2.fromScale(1, 0.4),
			Text = "",
		}, { maxSize = 60, stroke = 3, gradient = Theme.Gradients.LP })
		signs[spot] = { gui = gui, reward = reward }
		updateSign(spot)
	end

	local function onSpotAdded(spot)
		if spot:GetAttribute("Activity") ~= "Car" then
			return
		end
		for _, existing in ipairs(spots) do
			if existing == spot then
				return
			end
		end
		table.insert(spots, spot)
		applyCars(spot)
		makeSign(spot)
		-- przy StreamingEnabled części aut mogą dojść później
		spot.DescendantAdded:Connect(function(d)
			if d:IsA("BasePart") then
				local n = carNumber(d, spot)
				if n ~= nil then
					LocalHide.set(d, n ~= carTier)
				end
				updateSign(spot)
			end
		end)
	end

	local function onSpotRemoved(spot)
		for i = #spots, 1, -1 do
			if spots[i] == spot then
				table.remove(spots, i)
			end
		end
		local sign = signs[spot]
		if sign ~= nil then
			sign.gui:Destroy()
			signs[spot] = nil
		end
	end

	local function distanceToBox(part, position)
		local p = part.CFrame:PointToObjectSpace(position)
		local half = part.Size / 2
		local dx = math.max(math.abs(p.X) - half.X, 0)
		local dy = math.max(math.abs(p.Y) - half.Y, 0)
		local dz = math.max(math.abs(p.Z) - half.Z, 0)
		return math.sqrt(dx * dx + dy * dy + dz * dz)
	end

	-- Odległość do auta gracza (auto z jego tieru) na tym miejscu. Gdy auta nie ma (np. jeszcze się
	-- nie wczytało), liczy się część Pose, a na końcu całe miejsce.
	local function distanceToSpot(spot, position)
		local parts = { spot }
		if not spot:IsA("BasePart") then
			parts = spot:GetDescendants()
		end
		local car, pose, any = math.huge, math.huge, math.huge
		for _, part in ipairs(parts) do
			if part:IsA("BasePart") then
				local d = distanceToBox(part, position)
				local n = carNumber(part, spot)
				if n == carTier then
					car = math.min(car, d)
				elseif n == nil then
					if part.Name == "Pose" then
						pose = math.min(pose, d)
					end
					any = math.min(any, d)
				end
			end
		end
		if car < math.huge then
			return car
		end
		if pose < math.huge then
			return pose
		end
		return any
	end

	local function nearestSpot(position)
		local best, bestDistance = nil, math.huge
		for _, spot in ipairs(spots) do
			if spot.Parent ~= nil then
				local d = distanceToSpot(spot, position)
				if d < bestDistance then
					best, bestDistance = spot, d
				end
			end
		end
		return best, bestDistance
	end

	------------------------------------------------------------- Okno przy aucie
	local popup = Kit.panel(hud.gui, {
		name = "PhotoshootPanel",
		size = Vector2.new(540, 370),
		title = TEXT.Title,
		padding = 30,
		top = 52,
		bottom = 26,
	})
	hud.registerScale(popup.holder)
	hud.addPopup(popup)
	local content = popup.content
	local carLine = Kit.line(content, { anchor = Vector2.new(0.5, 0), position = UDim2.new(0.5, 0, 0, 0), height = 46 })
	local rewardLine = Kit.line(content, { anchor = Vector2.new(0.5, 0), position = UDim2.new(0.5, 0, 0, 46), height = 42 })
	local startButton = Kit.button(content, {
		name = "Start",
		size = Vector2.new(220, 60),
		text = TEXT.Start,
		colors = Theme.Gradients.Green,
		anchor = Vector2.new(0.5, 0),
		position = UDim2.new(0.5, 0, 0, 96),
		textSize = 30,
	})
	Kit.new("Frame", {
		Name = "Divider",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 176),
		Size = UDim2.new(1, -40, 0, 4),
		BackgroundColor3 = Theme.PatternColor,
		BorderSizePixel = 0,
		Parent = content,
	})
	local nextLine = Kit.line(content, { anchor = Vector2.new(0.5, 0), position = UDim2.new(0.5, 0, 0, 186), height = 40 })
	local priceLine = Kit.line(content, { anchor = Vector2.new(1, 0), position = UDim2.new(0.5, -12, 0, 234), height = 54 })
	local upgradeButton = Kit.button(content, {
		name = "Upgrade",
		size = Vector2.new(170, 54),
		text = TEXT.Upgrade,
		colors = Theme.Gradients.Yellow,
		anchor = Vector2.new(0, 0),
		position = UDim2.new(0.5, 12, 0, 233),
		textSize = 26,
	})
	local dismissed = false

	local function renderPopup()
		local view = State.view
		local info = view and view.Activities and view.Activities.Car
		if info == nil then
			return
		end
		carLine.set({
			{ text = carName(info.Tier), size = 32 },
			{ text = carMultiplier(info.Tier), size = 32, colors = Theme.Gradients.Gold },
		})
		-- nagroda, która zmieści się teraz w Bag (reszta by przepadła, więc pokazujemy limit)
		local fits = info.RewardFits or info.Reward
		local rewardItems = {
			{ text = TEXT.Reward, size = 26 },
			{ text = "+" .. Format.number(fits) .. " LP", size = 28, colors = Theme.Gradients.LP },
		}
		if fits < info.Reward then
			table.insert(rewardItems, { text = TEXT.BagLimit, size = 22, colors = Theme.Gradients.Red })
		end
		rewardLine.set(rewardItems)
		if view.BagFull then
			startButton.setColors(Theme.Gradients.Gray)
		else
			startButton.setColors(Theme.Gradients.Green)
		end
		if info.NextCost ~= nil then
			local nextTier = info.Tier + 1
			nextLine.set({
				{ text = TEXT.Next, size = 26 },
				{ text = carName(nextTier), size = 26 },
				{ text = carMultiplier(nextTier), size = 26, colors = Theme.Gradients.Gold },
			})
			priceLine.set({
				{ icon = "Cash", size = 46 },
				{ text = Format.number(info.NextCost), size = 36, colors = Theme.Gradients.Gold },
			})
			priceLine.holder.Visible = true
			upgradeButton.holder.AnchorPoint = Vector2.new(0, 0)
			upgradeButton.holder.Position = UDim2.new(0.5, 12, 0, 233)
			upgradeButton.setText(TEXT.Upgrade)
			if view.Cash >= info.NextCost then
				upgradeButton.setColors(Theme.Gradients.Yellow)
			else
				upgradeButton.setColors(Theme.Gradients.Gray)
			end
		else
			-- najlepsze auto: szary przycisk MAXED na środku, bez ceny
			nextLine.set({ { text = TEXT.BestCar, size = 28, colors = Theme.Gradients.Gold } })
			priceLine.holder.Visible = false
			upgradeButton.holder.AnchorPoint = Vector2.new(0.5, 0)
			upgradeButton.holder.Position = UDim2.new(0.5, 0, 0, 233)
			upgradeButton.setText(TEXT.Maxed)
			upgradeButton.setColors(Theme.Gradients.Gray)
		end
	end

	popup.close.Activated:Connect(function()
		dismissed = true
	end)

	local requesting = false
	startButton.Activated:Connect(function()
		if requesting or State.busy then
			return
		end
		requesting = true
		local ok, result = pcall(function()
			return Net.func("StartActivity"):InvokeServer("Car")
		end)
		requesting = false
		if not ok or type(result) ~= "table" then
			return
		end
		if result.Ok then
			popup.hide()
		elseif result.Reason == "BagFull" then
			Sounds.play("NotEnough")
			hud.toast({ { text = TEXT.BagFull, size = 26, colors = Theme.Gradients.Red } }, "ActivityBagFull")
			Kit.shake(startButton.holder)
		elseif result.Reason == "TooFar" then
			hud.toast({ { text = TEXT.TooFar, size = 26, colors = Theme.Gradients.Red } }, "ActivityTooFar")
		end
	end)

	upgradeButton.Activated:Connect(function()
		local view = State.view
		local info = view and view.Activities and view.Activities.Car
		if requesting or info == nil or info.NextCost == nil then
			return -- MAXED: nie ma czego kupić
		end
		requesting = true
		local ok, result = pcall(function()
			return Net.func("BuyActivityTier"):InvokeServer("Car")
		end)
		requesting = false
		if not ok or type(result) ~= "table" then
			return
		end
		if result.Ok then
			Sounds.play("Unlock")
			hud.toast({
				{ text = TEXT.NewCar, size = 28 },
				{ text = carName(result.Tier), size = 30, colors = Theme.Gradients.Gold },
			})
		elseif result.Reason == "NotEnough" then
			hud.notEnough(upgradeButton)
		end
	end)

	------------------------------------------------------------- Sesja zdjęciowa
	local cinemaGui = Kit.new("ScreenGui", {
		Name = "LarpPhotoshoot",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 15,
		Parent = playerGui,
	})
	local blackout = Kit.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 2,
		Parent = cinemaGui,
	})
	local flashFrame = Kit.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 1,
		Parent = cinemaGui,
	})

	-- pasek czasu sesji u góry ekranu
	local timerHolder = Kit.new("Frame", {
		Name = "PhotoshootTimer",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 70),
		Size = UDim2.fromOffset(420, 96),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = hud.gui,
	})
	hud.registerScale(timerHolder)
	Kit.text(timerHolder, { Size = UDim2.new(1, 0, 0, 48), Text = TEXT.Photoshoot }, { maxSize = 44, stroke = 4 })
	local timerTrack = Kit.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 56),
		Size = UDim2.fromOffset(360, 26),
		BackgroundColor3 = Theme.White,
		BorderSizePixel = 0,
		Parent = timerHolder,
	})
	Kit.corner(timerTrack, 13)
	Kit.stroke(timerTrack, 4, Enum.ApplyStrokeMode.Border)
	local timerFill = Kit.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.White,
		BorderSizePixel = 0,
		Parent = timerTrack,
	})
	Kit.corner(timerFill, 13)
	Kit.gradient(timerFill, Theme.Gradients.LP, 90)

	local function fadeTo(transparency, seconds)
		blackout.Visible = true
		local tween = TweenService:Create(blackout, TweenInfo.new(seconds), { BackgroundTransparency = transparency })
		tween:Play()
		tween.Completed:Connect(function()
			if blackout.BackgroundTransparency >= 0.99 then
				blackout.Visible = false
			end
		end)
	end

	local function flash()
		flashFrame.BackgroundTransparency = 0.15
		TweenService:Create(flashFrame, TweenInfo.new(0.35), { BackgroundTransparency = 1 }):Play()
		Sounds.play("Photo")
	end

	-- Inni gracze znikają u nas na czas sesji (aktywność jest „tylko twoja”).
	local hiddenCharacters = {}
	local function hideOthers(hidden)
		if hidden then
			for _, other in ipairs(Players:GetPlayers()) do
				local character = other.Character
				if other ~= player and character ~= nil then
					LocalHide.setAll(character, true, { collide = false })
					local humanoid = character:FindFirstChildOfClass("Humanoid")
					if humanoid ~= nil then
						humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
					end
					table.insert(hiddenCharacters, character)
				end
			end
		else
			for _, character in ipairs(hiddenCharacters) do
				if character.Parent ~= nil then
					LocalHide.setAll(character, false, { collide = false })
					local humanoid = character:FindFirstChildOfClass("Humanoid")
					if humanoid ~= nil then
						humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
					end
				end
			end
			hiddenCharacters = {}
		end
	end

	local shooting = false
	local endPayload = nil

	local function runShoot(payload)
		if shooting then
			return
		end
		shooting = true
		endPayload = nil
		State.busy = true
		popup.hide()
		local duration = payload.Duration or 8
		local half = (payload.Transition or 3) / 2
		local spot = payload.Spot
		if typeof(spot) ~= "Instance" or spot.Parent == nil then
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			spot = root and nearestSpot(root.Position)
		end

		fadeTo(0, 0.3)
		task.wait(half + 0.1) -- serwer w tym czasie stawia gracza przy aucie
		local camera = Workspace.CurrentCamera
		local connection = nil
		if spot ~= nil and camera ~= nil then
			local frame = pivotOf(spot)
			local center = frame.Position + Vector3.new(0, 2.5, 0)
			local startTime = os.clock()
			camera.CameraType = Enum.CameraType.Scriptable
			connection = RunService.RenderStepped:Connect(function()
				local t = math.clamp((os.clock() - startTime) / duration, 0, 1)
				local angle = math.rad(-35 + 110 * t)
				local offset = Vector3.new(math.cos(angle) * 19, 5.5 - 1.5 * t, math.sin(angle) * 19)
				camera.CFrame = CFrame.lookAt(frame:PointToWorldSpace(offset), center)
			end)
		end
		hideOthers(true)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid ~= nil then
			pcall(function()
				humanoid:PlayEmote("wave")
			end)
		end
		timerFill.Size = UDim2.fromScale(1, 1)
		timerHolder.Visible = true
		TweenService:Create(timerFill, TweenInfo.new(duration, Enum.EasingStyle.Linear), { Size = UDim2.fromScale(0, 1) }):Play()
		fadeTo(1, 0.35)

		local flashes = math.floor(duration / FLASH_EVERY)
		task.spawn(function()
			for _ = 1, flashes do
				task.wait(FLASH_EVERY)
				if not shooting then
					return
				end
				flash()
			end
		end)

		-- koniec: nagroda od serwera albo limit czasu, gdyby jej nie było
		local deadline = os.clock() + duration + 2
		while endPayload == nil and os.clock() < deadline do
			task.wait(0.05)
		end
		fadeTo(0, 0.3)
		task.wait(0.32)
		if connection ~= nil then
			connection:Disconnect()
		end
		if camera ~= nil then
			camera.CameraType = Enum.CameraType.Custom
			local current = player.Character
			local currentHumanoid = current and current:FindFirstChildOfClass("Humanoid")
			if currentHumanoid ~= nil then
				camera.CameraSubject = currentHumanoid
			end
		end
		hideOthers(false)
		timerHolder.Visible = false
		fadeTo(1, 0.35)
		State.busy = false
		shooting = false
		if endPayload ~= nil then
			Sounds.play("Reward")
			local items = {
				{ text = TEXT.Done, size = 26 },
				{ text = "+" .. Format.number(endPayload.LP or 0) .. " LP", size = 30, colors = Theme.Gradients.LP },
			}
			if (endPayload.LP or 0) < (endPayload.Reward or 0) then
				table.insert(items, { text = TEXT.BagLimit, size = 24, colors = Theme.Gradients.Red })
			end
			hud.toast(items)
		end
	end

	State.onNotify(function(payload)
		if payload.Kind == "ActivityStart" and payload.Activity == "Car" then
			task.spawn(runShoot, payload)
		elseif payload.Kind == "ActivityEnd" and payload.Activity == "Car" then
			endPayload = payload
		end
	end)

	------------------------------------------------------------- Otwieranie okna przy aucie
	local timer = 0
	RunService.Heartbeat:Connect(function(dt)
		timer = timer + dt
		if timer < 0.15 then
			return
		end
		timer = 0
		local view = State.view
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local unlocked = view ~= nil and (view.ZonesUnlocked or 1) >= Economy.Activities.Car.Zone
		if root == nil or not unlocked or State.busy or hud.windowOpen() then
			if popup.isOpen() then
				popup.hide()
			end
			return
		end
		local _, distance = nearestSpot(root.Position)
		if distance <= OPEN_DISTANCE then
			if not dismissed and not popup.isOpen() then
				renderPopup()
				hud.closeUpgrades()
				popup.open()
			end
		elseif distance >= CLOSE_DISTANCE then
			dismissed = false
			if popup.isOpen() then
				popup.hide()
			end
		end
	end)

	------------------------------------------------------------- Stan od serwera
	State.onChange(function(view)
		local info = view.Activities and view.Activities.Car
		if info ~= nil and info.Tier ~= carTier then
			carTier = info.Tier
			for _, spot in ipairs(spots) do
				applyCars(spot)
			end
		end
		for _, spot in ipairs(spots) do
			updateSign(spot)
		end
		if popup.isOpen() then
			renderPopup()
		end
	end)

	for _, spot in ipairs(CollectionService:GetTagged(SPOT_TAG)) do
		onSpotAdded(spot)
	end
	CollectionService:GetInstanceAddedSignal(SPOT_TAG):Connect(onSpotAdded)
	CollectionService:GetInstanceRemovedSignal(SPOT_TAG):Connect(onSpotRemoved)
end

return Activities
