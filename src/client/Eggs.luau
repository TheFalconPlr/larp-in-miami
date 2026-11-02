-- Jajka po stronie gracza: tablice nad stoiskami (nazwa i cena), okno przy stoisku (pety z szansami,
-- cena, OPEN albo klawisz E) i animacja otwierania (jajko się trzęsie, błysk, pojawia się pet z
-- rzadkością i bonusem). Kupno i losowanie robi serwer (PetService); tu jest tylko wygląd.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared.Config.Economy)
local Format = require(Shared.Format)
local Net = require(Shared.Net)
local PetsConfig = require(Shared.Config.Pets)
local State = require(script.Parent.State)
local Theme = require(script.Parent.Ui.Theme)
local Kit = require(script.Parent.Ui.Kit)
local Icons = require(script.Parent.Ui.Icons)
local Sounds = require(script.Parent.Ui.Sounds)
local PetModels = require(script.Parent.PetModels)
local Pets = require(script.Parent.Pets)

local Eggs = {}

local EGG_TAG = "LarpEgg" -- jak PetService.EggTag na serwerze
local OPEN_DISTANCE = 7 -- okno otwiera się, gdy stoisz przy jajku (studs od części stoiska)
local CLOSE_DISTANCE = 12
local SIGN_LIFT = 3.2 -- środek tablicy tyle studów nad najwyższym punktem stoiska
local BIG_RARITY = { Legendary = true, Mythic = true, Secret = true } -- przy nich gra oklaski
local POPUP_SIZE = Vector2.new(560, 340)
local POPUP_PADDING = 30
local CONTENT_WIDTH = POPUP_SIZE.X - 2 * POPUP_PADDING
local CARD_HEIGHT = 116
local CARD_GAP = 10

local TEXT = {
	Open = "OPEN",
	Inventory = "Pet inventory is full",
	New = "NEW PET!",
	Equipped = "Equipped!",
}

local function eggName(zone, egg)
	return string.format(PetsConfig.EggNames[egg] or "%s Egg", Economy.Zones[zone].Name)
end

local function eggInfo(zone, egg)
	local list = Economy.Pets.Eggs[zone]
	local info = list and list[egg]
	if info == nil or info.Price == nil then
		return nil
	end
	return info
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
	for _, part in ipairs(stand:GetDescendants()) do
		if part:IsA("BasePart") then
			best = math.min(best, distanceToPart(part, position))
		end
	end
	return best
end

local function biggestPart(stand)
	if stand:IsA("BasePart") then
		return stand
	end
	local best, bestSize = nil, -1
	for _, d in ipairs(stand:GetDescendants()) do
		if d:IsA("BasePart") then
			local size = d.Size.X * d.Size.Y * d.Size.Z
			if size > bestSize then
				best, bestSize = d, size
			end
		end
	end
	return best
end

function Eggs.start(hud)
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	local stands = {}

	------------------------------------------------------------- Tablice nad stoiskami
	local signs = {} -- [stoisko] = BillboardGui

	local function zoneUnlocked(zone)
		local view = State.view
		return view ~= nil and type(zone) == "number" and (view.ZonesUnlocked or 1) >= zone
	end

	-- Tablica wisi nad najwyższym punktem stoiska; widać ją dopiero, gdy strefa jest odblokowana.
	local function updateSign(stand)
		local sign = signs[stand]
		if sign == nil then
			return
		end
		local part = biggestPart(stand)
		sign.Adornee = part
		if part ~= nil then
			local top = part.Position.Y + part.Size.Y / 2
			if stand:IsA("Model") then
				local box, size = stand:GetBoundingBox()
				top = box.Position.Y + size.Y / 2
			end
			sign.StudsOffsetWorldSpace = Vector3.new(0, top - part.Position.Y + SIGN_LIFT, 0)
		end
		sign.Enabled = part ~= nil and zoneUnlocked(stand:GetAttribute("Zone"))
	end

	local function makeSign(stand)
		local zone, egg = stand:GetAttribute("Zone"), stand:GetAttribute("Egg")
		local info = eggInfo(zone, egg)
		if info == nil then
			return
		end
		local sign = Kit.new("BillboardGui", {
			Name = "EggSign",
			Size = UDim2.fromScale(12, 5),
			LightInfluence = 0,
			MaxDistance = 120,
			ResetOnSpawn = false,
			Enabled = false,
			Parent = playerGui,
		})
		Kit.text(sign, { Size = UDim2.fromScale(1, 0.52), Text = eggName(zone, egg) }, { maxSize = 80, stroke = 3 })
		local coin = Icons.make("Cash", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.fromScale(0.4, 0.77),
			Size = UDim2.fromScale(0.2, 0.44),
			Parent = sign,
		})
		Kit.new("UIAspectRatioConstraint", { AspectRatio = 1, Parent = coin })
		Kit.text(sign, {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromScale(0.42, 0.77),
			Size = UDim2.fromScale(0.58, 0.44),
			Text = Format.number(info.Price),
			TextXAlignment = Enum.TextXAlignment.Left,
		}, { maxSize = 70, stroke = 3, gradient = Theme.Gradients.Gold })
		signs[stand] = sign
		updateSign(stand)
	end

	local function onStandAdded(stand)
		for _, existing in ipairs(stands) do
			if existing == stand then
				return
			end
		end
		table.insert(stands, stand)
		makeSign(stand)
		-- przy StreamingEnabled części stoiska mogą dojść później
		stand.DescendantAdded:Connect(function(d)
			if d:IsA("BasePart") then
				updateSign(stand)
			end
		end)
	end

	local function onStandRemoved(stand)
		for i = #stands, 1, -1 do
			if stands[i] == stand then
				table.remove(stands, i)
			end
		end
		if signs[stand] ~= nil then
			signs[stand]:Destroy()
			signs[stand] = nil
		end
	end

	------------------------------------------------------------- Okno przy stoisku
	local popup = Kit.panel(hud.gui, {
		name = "EggPanel",
		size = POPUP_SIZE,
		title = "",
		padding = POPUP_PADDING,
		top = 52,
		bottom = 26,
	})
	hud.registerScale(popup.holder)
	hud.addPopup(popup)
	-- pety, które mogą wypaść, z szansami (jak w Pet Simulator)
	local chances = Kit.new("Frame", {
		Name = "Chances",
		Size = UDim2.new(1, 0, 0, CARD_HEIGHT),
		BackgroundTransparency = 1,
		ZIndex = 3,
		Parent = popup.content,
	})
	Kit.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, CARD_GAP),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = chances,
	})
	local priceLine = Kit.line(popup.content, {
		anchor = Vector2.new(0.5, 0),
		position = UDim2.new(0.5, 0, 0, CARD_HEIGHT + 10),
		height = 54,
	})
	local openButton = Kit.button(popup.content, {
		name = "Open",
		size = Vector2.new(220, 60),
		text = TEXT.Open,
		colors = Theme.Gradients.Green,
		anchor = Vector2.new(0.5, 1),
		position = UDim2.new(0.5, 0, 1, 0),
		textSize = 30,
	})
	local current = nil -- { stand, zone, egg }
	local shownEgg = nil -- które jajko jest teraz narysowane w oknie
	local dismissed = false -- zamknięte X-em: nie otwieraj, dopóki gracz nie odejdzie
	local hatching = false

	local function makeChanceCard(zone, rarity, chance, width, order)
		local color = PetsConfig.RarityColors[rarity] or Theme.White
		local card = Kit.new("Frame", {
			Name = rarity,
			LayoutOrder = order,
			Size = UDim2.fromOffset(width, CARD_HEIGHT),
			BackgroundColor3 = Theme.White,
			BorderSizePixel = 0,
			ZIndex = 4,
			Parent = chances,
		})
		Kit.corner(card, 16)
		Kit.stroke(card, 3, Enum.ApplyStrokeMode.Border)
		Kit.gradient(card, { Theme.White, color:Lerp(Theme.White, 0.5) }, 90)
		local viewport = Kit.new("ViewportFrame", {
			Position = UDim2.fromOffset(4, 4),
			Size = UDim2.new(1, -8, 0, 64),
			BackgroundTransparency = 1,
			Ambient = Color3.fromRGB(200, 200, 210),
			LightColor = Color3.new(1, 1, 1),
			ZIndex = 5,
			Parent = card,
		})
		PetModels.show(viewport, PetModels.pet(zone, rarity))
		Kit.text(card, {
			Position = UDim2.fromOffset(2, 68),
			Size = UDim2.new(1, -4, 0, 26),
			Text = Format.percent(chance),
			ZIndex = 6,
		}, { maxSize = 22, stroke = 3 })
		local item = Pets.rarityItem(rarity, 15)
		Kit.text(card, {
			Position = UDim2.fromOffset(2, 94),
			Size = UDim2.new(1, -4, 0, 18),
			Text = rarity,
			TextColor3 = item.color or Theme.White,
			ZIndex = 6,
		}, { maxSize = 15, stroke = 2.5, gradient = item.colors })
	end

	local function updateButton()
		local info = current and eggInfo(current.zone, current.egg)
		local view = State.view
		if info == nil or view == nil then
			return
		end
		if view.Cash >= info.Price then
			openButton.setColors(Theme.Gradients.Green)
		else
			openButton.setColors(Theme.Gradients.Gray)
		end
	end

	local function renderPopup()
		local info = current and eggInfo(current.zone, current.egg)
		if info == nil then
			return
		end
		local key = current.zone .. current.egg
		if shownEgg ~= key then
			shownEgg = key
			popup.title.Text = eggName(current.zone, current.egg)
			for _, child in ipairs(chances:GetChildren()) do
				if child:IsA("GuiObject") then
					child:Destroy()
				end
			end
			local list = {}
			for _, rarity in ipairs(Economy.Pets.RarityOrder) do
				if info.Odds[rarity] ~= nil then
					table.insert(list, rarity)
				end
			end
			local count = math.max(1, #list)
			local width = math.min(96, math.floor((CONTENT_WIDTH - (count - 1) * CARD_GAP) / count))
			for i, rarity in ipairs(list) do
				makeChanceCard(current.zone, rarity, info.Odds[rarity], width, i)
			end
			priceLine.set({
				{ icon = "Cash", size = 48 },
				{ text = Format.number(info.Price), size = 40, colors = Theme.Gradients.Gold },
			})
		end
		updateButton()
	end

	popup.close.Activated:Connect(function()
		dismissed = true
	end)

	------------------------------------------------------------- Animacja otwierania
	local hatchGui = Kit.new("ScreenGui", {
		Name = "LarpHatch",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 16,
		Enabled = false,
		Parent = playerGui,
	})
	local dim = Kit.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = hatchGui,
	})
	local stage = Kit.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(520, 580),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = hatchGui,
	})
	hud.registerScale(stage)
	-- kolorowa poświata za petem (w kolorze rzadkości)
	local glow = Kit.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, 200),
		Size = UDim2.fromOffset(330, 330),
		BackgroundColor3 = Theme.White,
		BackgroundTransparency = 0.55,
		Visible = false,
		ZIndex = 2,
		Parent = stage,
	})
	Kit.new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = glow })
	local glowStroke = Kit.stroke(glow, 10, Enum.ApplyStrokeMode.Border, Theme.White)
	glowStroke.Transparency = 0.35
	local glowScale = Kit.new("UIScale", { Parent = glow })
	local viewport = Kit.new("ViewportFrame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 0),
		Size = UDim2.fromOffset(400, 400),
		BackgroundTransparency = 1,
		Ambient = Color3.fromRGB(210, 210, 220),
		LightColor = Color3.new(1, 1, 1),
		ZIndex = 3,
		Parent = stage,
	})
	local pop = Kit.new("UIScale", { Parent = viewport })
	local flash = Kit.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 10,
		Parent = hatchGui,
	})
	local function stageLine(y, height)
		return Kit.line(stage, { anchor = Vector2.new(0.5, 0), position = UDim2.new(0.5, 0, 0, y), height = height })
	end
	local newLine = stageLine(392, 40)
	local nameLine = stageLine(432, 56)
	local infoLine = stageLine(490, 44)
	local equippedLine = stageLine(536, 36)

	local function hatch(egg, pet, total, equipped)
		hatching = true
		State.busy = true
		local shakeTime = total * 0.55
		newLine.set({})
		nameLine.set({})
		infoLine.set({})
		equippedLine.set({})
		glow.Visible = false
		local eggModel = PetModels.egg(egg)
		PetModels.show(viewport, eggModel, 1.25)
		pop.Scale = 0.6
		hatchGui.Enabled = true
		TweenService:Create(dim, TweenInfo.new(0.2), { BackgroundTransparency = 0.35 }):Play()
		TweenService:Create(pop, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()

		-- jajko kołysze się coraz szybciej i mocniej
		local start = os.clock()
		local shaking = RunService.RenderStepped:Connect(function()
			local elapsed = os.clock() - start
			local t = math.clamp(elapsed / shakeTime, 0, 1)
			local angle = math.sin(elapsed * (10 + 26 * t)) * math.rad(6 + 16 * t)
			eggModel:PivotTo(CFrame.Angles(0, 0, angle))
		end)
		task.wait(shakeTime)
		shaking:Disconnect()

		-- błysk, poświata i pet
		local color = PetsConfig.RarityColors[pet.Rarity] or Theme.White
		flash.BackgroundTransparency = 0
		TweenService:Create(flash, TweenInfo.new(0.45), { BackgroundTransparency = 1 }):Play()
		local petModel = PetModels.pet(pet.Zone, pet.Rarity)
		PetModels.show(viewport, petModel, 1.6)
		pop.Scale = 0.3
		TweenService:Create(pop, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		glow.BackgroundColor3 = color
		glowStroke.Color = color
		glow.Visible = true
		glowScale.Scale = 0.3
		TweenService:Create(glowScale, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		local revealStart = os.clock()
		local spin = RunService.RenderStepped:Connect(function()
			petModel:PivotTo(CFrame.Angles(0, math.sin((os.clock() - revealStart) * 1.6) * 0.5, 0))
		end)
		newLine.set({ { text = TEXT.New, size = 30, colors = Theme.Gradients.Gold } })
		nameLine.set({ { text = PetsConfig.name(pet.Zone, pet.Rarity), size = 46 } })
		infoLine.set({
			Pets.rarityItem(pet.Rarity, 32),
			{ text = Pets.powerText(pet), size = 30, colors = Theme.Gradients.Gold },
		})
		if equipped then
			equippedLine.set({ { text = TEXT.Equipped, size = 26, colors = Theme.Gradients.Green } })
		end
		if BIG_RARITY[pet.Rarity] then
			Sounds.play("Reward") -- oklaski przy rzadkim pecie
		else
			Sounds.play("Hatch")
		end

		task.wait(math.max(1, total - shakeTime))
		TweenService:Create(dim, TweenInfo.new(0.25), { BackgroundTransparency = 1 }):Play()
		TweenService:Create(pop, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Scale = 0 }):Play()
		TweenService:Create(glowScale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Scale = 0 }):Play()
		task.wait(0.26)
		spin:Disconnect()
		hatchGui.Enabled = false
		State.busy = false
		hatching = false
	end

	local requesting = false
	local function tryOpen()
		if requesting or hatching or current == nil then
			return
		end
		requesting = true
		local zone, egg = current.zone, current.egg
		local ok, result = pcall(function()
			return Net.func("BuyEgg"):InvokeServer(zone, egg)
		end)
		requesting = false
		if not ok or type(result) ~= "table" then
			return
		end
		if result.Ok and type(result.Pet) == "table" then
			popup.hide()
			hatch(egg, result.Pet, result.OpenTime or Economy.OpenTimeSeconds, result.Equipped == true)
			dismissed = false -- jeśli dalej stoisz przy jajku, okno wróci
		elseif result.Reason == "NotEnough" then
			hud.notEnough(openButton)
		elseif result.Reason == "Inventory" then
			Sounds.play("NotEnough")
			hud.toast({ { text = TEXT.Inventory, size = 26, colors = Theme.Gradients.Red } }, "PetInventory")
		end
	end

	openButton.Activated:Connect(tryOpen)
	-- E przy otwartym oknie = OPEN (jak w innych grach z jajkami)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or input.KeyCode ~= Enum.KeyCode.E then
			return
		end
		if popup.isOpen() then
			Sounds.play("Button")
			tryOpen()
		end
	end)

	------------------------------------------------------------- Okno otwiera się samo przy stoisku
	local timer = 0
	RunService.Heartbeat:Connect(function(dt)
		timer = timer + dt
		if timer < 0.15 then
			return
		end
		timer = 0
		if hatching then
			return
		end
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root == nil or State.view == nil or State.busy or hud.windowOpen() then
			if popup.isOpen() then
				popup.hide()
			end
			return
		end
		local best, bestDistance = nil, math.huge
		for _, stand in ipairs(stands) do
			if stand.Parent ~= nil and zoneUnlocked(stand:GetAttribute("Zone")) then
				local d = distanceToStand(stand, root.Position)
				if d < bestDistance then
					best, bestDistance = stand, d
				end
			end
		end
		if best ~= nil and bestDistance <= OPEN_DISTANCE then
			if not dismissed and (not popup.isOpen() or current == nil or current.stand ~= best) then
				current = { stand = best, zone = best:GetAttribute("Zone"), egg = best:GetAttribute("Egg") }
				renderPopup()
				popup.open()
			end
		elseif bestDistance >= CLOSE_DISTANCE then
			dismissed = false
			if popup.isOpen() then
				popup.hide()
			end
		end
	end)

	local lastUnlocked = nil
	State.onChange(function(view)
		if view.ZonesUnlocked ~= lastUnlocked then
			lastUnlocked = view.ZonesUnlocked
			for _, stand in ipairs(stands) do
				updateSign(stand)
			end
		end
		if popup.isOpen() then
			updateButton()
		end
	end)

	for _, stand in ipairs(CollectionService:GetTagged(EGG_TAG)) do
		onStandAdded(stand)
	end
	CollectionService:GetInstanceAddedSignal(EGG_TAG):Connect(onStandAdded)
	CollectionService:GetInstanceRemovedSignal(EGG_TAG):Connect(onStandRemoved)
end

return Eggs
