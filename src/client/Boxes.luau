-- Mystery boxy z ubraniami po stronie gracza (Etap 8), jak jajka w Eggs.luau:
--   • przy każdym boxie pigułka z ceną (albo kłódka i strefa, którą trzeba najpierw odblokować),
--   • nad najbliższym panel z szansami rzadkości i bonusem do LP, a przed boxem duże E;
--     E (klawisz albo kliknięcie) otwiera okno kupna,
--   • animacja: box drży 3 razy, wieko odlatuje, a ze środka wyskakuje ubranie z promieniami
--     w kolorze rzadkości; napisy wskakują po kolei, a na koniec ubranie leci do kafelka CLOTHES.
-- Kupno i losowanie robi serwer (ClothesService); tu jest tylko wygląd.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared.Config.Economy)
local Format = require(Shared.Format)
local Formulas = require(Shared.Formulas)
local Net = require(Shared.Net)
local PetsConfig = require(Shared.Config.Pets)
local ClothesConfig = require(Shared.Config.Clothes)
local ClothModels = require(Shared.ClothModels)
local State = require(script.Parent.State)
local Theme = require(script.Parent.Ui.Theme)
local Kit = require(script.Parent.Ui.Kit)
local Icons = require(script.Parent.Ui.Icons)
local Sounds = require(script.Parent.Ui.Sounds)
local Pets = require(script.Parent.Pets)
local Wardrobe = require(script.Parent.Wardrobe)

local Boxes = {}

local BOX_TAG = "LarpBox" -- jak ClothesService.BoxTag na serwerze
local SHOW_DISTANCE = 8
local HIDE_DISTANCE = 12
local BIG_RARITY = { Legendary = true, Mythic = true }

local PILL_SIZE = Vector2.new(4.6, 1.4)
local PILL_HEIGHT = 1.7
local PANEL_CARD = 2.1
local PANEL_PAD = 0.35
local PANEL_BODY = 2.7
local PANEL_TIP = 0.45
local PANEL_LIFT = 0.6
local PANEL_EDGE = Color3.fromRGB(205, 210, 222)

local STAGE_SIZE = Vector2.new(1200, 700)
local SLOT = 420
local BEATS = { 0.27, 0.42, 0.57 } -- drgnięcia (część czasu otwierania)
local BURST_AT = 0.66 -- wieko odlatuje
local GRAVITY = 1100
local RAY_FADE = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(0.32, 0.8),
	NumberSequenceKeypoint.new(0.5, 0.5),
	NumberSequenceKeypoint.new(0.68, 0.8),
	NumberSequenceKeypoint.new(1, 1),
})

local TEXT = {
	Question = "Would you like to buy a\n%s?",
	Buy = "Buy",
	Random = "1 random item from 7 categories",
	Range = "%s to %s LP",
	Locked = "Unlock %s first",
	Inventory = "Not enough room for more clothes",
	New = "NEW %s!",
	Rare = "%s ITEM!",
	Wearing = "Wearing!",
}

local function boxInfo(box)
	local info = Economy.Clothes.Boxes[box]
	if info == nil or info.Price == nil then
		return nil
	end
	return info
end

local function boxName(box)
	local look = ClothesConfig.Boxes[box]
	return (look and look.Name) or (box .. " Box")
end

local function raritiesOf(info)
	local list = {}
	for _, rarity in ipairs(Economy.Pets.RarityOrder) do
		if info.Odds[rarity] ~= nil then
			table.insert(list, rarity)
		end
	end
	return list
end

local function rarityColors(rarity)
	local item = Pets.rarityItem(rarity, 20)
	if item.colors ~= nil then
		return item.colors
	end
	local color = item.color or Theme.White
	return { color:Lerp(Theme.White, 0.35), color }
end

local function percentText(bonus)
	return "+" .. Format.small(bonus * 100) .. "%"
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

local function standBounds(stand)
	local part = biggestPart(stand)
	if part == nil then
		return nil, 0, 0
	end
	local top = part.Position.Y + part.Size.Y / 2
	local bottom = part.Position.Y - part.Size.Y / 2
	if stand:IsA("Model") then
		local box, size = stand:GetBoundingBox()
		top = box.Position.Y + size.Y / 2
		bottom = box.Position.Y - size.Y / 2
	end
	return part, top - part.Position.Y, bottom - part.Position.Y
end

local function showModel(view, model, distanceScale)
	Wardrobe.showModel(view, model, distanceScale)
end

-- Box do okienek: punkt obrotu na środku pudełka (ClothModels.box ma go na dole, pod stoisko).
local function boxForView(box)
	local model = ClothModels.box(box)
	model.WorldPivot = CFrame.new(0, 2.4, 0)
	return model
end

function Boxes.start(hud)
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	local stands = {}
	local current = nil -- najbliższy box: { stand, box }
	local opening = false

	local function standVisible(stand)
		local view = State.view
		local zone = stand:GetAttribute("Zone") or 3
		return view ~= nil and (view.ZonesUnlocked or 1) >= zone
	end

	local function unlocked(box)
		local info = boxInfo(box)
		local view = State.view
		return info ~= nil and view ~= nil and (view.ZonesUnlocked or 1) >= info.RequiresZone
	end

	------------------------------------------------------------- Cena przy każdym boxie
	local pills = {} -- [stoisko] = { gui, render }
	local pillsHidden = false

	local function updatePill(stand)
		local entry = pills[stand]
		if entry == nil then
			return
		end
		local part, _, bottom = standBounds(stand)
		entry.gui.Adornee = part
		if part ~= nil then
			entry.gui.StudsOffsetWorldSpace = Vector3.new(0, bottom + PILL_HEIGHT, 0)
		end
		entry.render()
		entry.gui.Enabled = part ~= nil and standVisible(stand) and not pillsHidden
	end

	local function makePill(stand)
		local box = stand:GetAttribute("Box")
		local info = boxInfo(box)
		if info == nil then
			return
		end
		local gui = Kit.new("BillboardGui", {
			Name = "BoxPrice",
			Size = UDim2.fromScale(PILL_SIZE.X, PILL_SIZE.Y),
			LightInfluence = 0,
			AlwaysOnTop = true,
			MaxDistance = 70,
			ResetOnSpawn = false,
			Enabled = false,
			Parent = playerGui,
		})
		local face = Kit.new("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Theme.White,
			BorderSizePixel = 0,
			Parent = gui,
		})
		Kit.new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = face })
		local gradient = Kit.gradient(face, Theme.Gradients.Yellow, 90)
		Kit.stroke(face, 3, Enum.ApplyStrokeMode.Border)
		local holder = Kit.new("Frame", {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromScale(0.05, 0.5),
			Size = UDim2.fromScale(0.26, 0.9),
			BackgroundTransparency = 1,
			ZIndex = 2,
			Parent = face,
		})
		Kit.new("UIAspectRatioConstraint", { AspectRatio = 1, Parent = holder })
		local label = Kit.text(face, {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromScale(0.34, 0.5),
			Size = UDim2.fromScale(0.6, 0.74),
			Text = Format.number(info.Price),
			ZIndex = 2,
		}, { maxSize = 60, stroke = 3 })
		local iconName = nil
		local function setIcon(name)
			if iconName == name then
				return
			end
			iconName = name
			for _, child in ipairs(holder:GetChildren()) do
				child:Destroy()
			end
			Icons.make(name, { Size = UDim2.fromScale(1, 1), ZIndex = 2, Parent = holder })
		end
		-- zablokowany box: kłódka i nazwa strefy, którą trzeba odblokować
		local function render()
			if unlocked(box) then
				setIcon("Cash")
				label.Text = Format.number(info.Price)
				gradient.Color = ColorSequence.new(Theme.Gradients.Yellow[1], Theme.Gradients.Yellow[2])
			else
				setIcon("Lock")
				local zone = Economy.Zones[info.RequiresZone]
				label.Text = (zone and zone.Name) or ("Zone " .. info.RequiresZone)
				gradient.Color = ColorSequence.new(Theme.Gradients.Gray[1], Theme.Gradients.Gray[2])
			end
		end
		pills[stand] = { gui = gui, render = render }
		updatePill(stand)
	end

	------------------------------------------------------------- Panel z szansami nad boxem
	local panelGui = Kit.new("BillboardGui", {
		Name = "BoxChances",
		Size = UDim2.fromScale(10, PANEL_BODY + PANEL_TIP),
		LightInfluence = 0,
		AlwaysOnTop = true,
		MaxDistance = 80,
		ResetOnSpawn = false,
		Enabled = false,
		Parent = playerGui,
	})
	local panelKey = nil

	local function renderPanel(box)
		for _, child in ipairs(panelGui:GetChildren()) do
			child:Destroy()
		end
		local info = boxInfo(box)
		if info == nil then
			return
		end
		local list = raritiesOf(info)
		local width = #list * PANEL_CARD + 2 * PANEL_PAD
		local height = PANEL_BODY + PANEL_TIP
		local bodyHeight = PANEL_BODY / height
		panelGui.Size = UDim2.fromScale(width, height)
		local body = Kit.new("Frame", {
			Name = "Body",
			Size = UDim2.fromScale(1, bodyHeight),
			BackgroundColor3 = Theme.White,
			BorderSizePixel = 0,
			ZIndex = 2,
			Parent = panelGui,
		})
		Kit.new("UICorner", { CornerRadius = UDim.new(0.2, 0), Parent = body })
		Kit.stroke(body, 2, Enum.ApplyStrokeMode.Border, PANEL_EDGE)
		local tip = PANEL_TIP * 1.4
		Kit.new("Frame", {
			Name = "Tip",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, bodyHeight - 0.03),
			Size = UDim2.fromScale(tip / width, tip / height),
			Rotation = 45,
			BackgroundColor3 = Theme.White,
			BorderSizePixel = 0,
			ZIndex = 3,
			Parent = panelGui,
		})
		for i, rarity in ipairs(list) do
			local color = PetsConfig.RarityColors[rarity] or Theme.White
			local card = Kit.new("Frame", {
				Name = rarity,
				Position = UDim2.fromScale((PANEL_PAD + (i - 1) * PANEL_CARD) / width, 0),
				Size = UDim2.fromScale(PANEL_CARD / width, 1),
				BackgroundTransparency = 1,
				ZIndex = 4,
				Parent = body,
			})
			local tileFrame = Kit.new("Frame", {
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.fromScale(0.5, 0.94),
				Size = UDim2.fromScale(0.88, 0.64),
				BackgroundColor3 = color:Lerp(Theme.White, 0.25),
				BorderSizePixel = 0,
				ZIndex = 4,
				Parent = card,
			})
			Kit.new("UICorner", { CornerRadius = UDim.new(0.22, 0), Parent = tileFrame })
			Kit.text(tileFrame, {
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.fromScale(0.5, 0.08),
				Size = UDim2.fromScale(0.9, 0.42),
				Text = rarity,
				ZIndex = 5,
			}, { maxSize = 40, stroke = 2.5 })
			Kit.text(tileFrame, {
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.fromScale(0.5, 0.52),
				Size = UDim2.fromScale(0.9, 0.4),
				Text = percentText(Formulas.clothBonus(rarity, 0)) .. " LP",
				ZIndex = 5,
			}, { maxSize = 40, stroke = 2.5, gradient = Theme.Gradients.Gold })
			local item = Pets.rarityItem(rarity, 20)
			Kit.text(card, {
				Position = UDim2.fromScale(0, 0.03),
				Size = UDim2.fromScale(1, 0.27),
				Text = Format.percent(info.Odds[rarity]),
				TextColor3 = item.color or Theme.White,
				ZIndex = 6,
			}, { maxSize = 60, stroke = 2.5, gradient = item.colors })
		end
	end

	------------------------------------------------------------- Duże E przed boxem
	local promptGui = Kit.new("BillboardGui", {
		Name = "BoxPrompt",
		Size = UDim2.fromOffset(190, 190),
		LightInfluence = 0,
		AlwaysOnTop = true,
		Active = true,
		MaxDistance = 80,
		ResetOnSpawn = false,
		Enabled = false,
		Parent = playerGui,
	})
	local promptHolder = Kit.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(92, 92),
		BackgroundTransparency = 1,
		Parent = promptGui,
	})
	hud.registerScale(promptHolder)
	local promptInner = Kit.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = promptHolder,
	})
	local promptBob = Kit.new("UIScale", { Parent = promptInner })
	local promptEdge = Kit.new("Frame", {
		Position = UDim2.fromOffset(0, 6),
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Outline,
		BorderSizePixel = 0,
		ZIndex = 1,
		Parent = promptInner,
	})
	Kit.corner(promptEdge, 24)
	local promptButton = Kit.new("TextButton", {
		Name = "E",
		Active = true,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.White,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Font = Theme.Font,
		Text = "E",
		TextColor3 = Theme.Dark,
		TextScaled = true,
		ZIndex = 2,
		Parent = promptInner,
	})
	Kit.corner(promptButton, 24)
	Kit.stroke(promptButton, 4, Enum.ApplyStrokeMode.Border)
	Kit.new("UIPadding", {
		PaddingTop = UDim.new(0, 12),
		PaddingBottom = UDim.new(0, 12),
		PaddingLeft = UDim.new(0, 12),
		PaddingRight = UDim.new(0, 12),
		Parent = promptButton,
	})
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		promptButton.Text = ""
		Icons.make("Click", { Size = UDim2.fromScale(1, 1), ZIndex = 3, Parent = promptButton })
	end
	TweenService:Create(promptBob, TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = 1.07 }):Play()

	local function placePrompt(stand)
		local part, top, bottom = standBounds(stand)
		panelGui.Adornee = part
		promptGui.Adornee = part
		if part ~= nil then
			panelGui.StudsOffsetWorldSpace = Vector3.new(0, top + PANEL_LIFT + (PANEL_BODY + PANEL_TIP) / 2, 0)
			promptGui.StudsOffsetWorldSpace = Vector3.new(0, (top + bottom) / 2 + 0.4, 0)
		end
	end

	------------------------------------------------------------- Stoiska
	local function onStandAdded(stand)
		for _, existing in ipairs(stands) do
			if existing == stand then
				return
			end
		end
		table.insert(stands, stand)
		makePill(stand)
		stand.DescendantAdded:Connect(function(d)
			if d:IsA("BasePart") then
				updatePill(stand)
				if current ~= nil and current.stand == stand then
					placePrompt(stand)
				end
			end
		end)
	end

	local function onStandRemoved(stand)
		for i = #stands, 1, -1 do
			if stands[i] == stand then
				table.remove(stands, i)
			end
		end
		if pills[stand] ~= nil then
			pills[stand].gui:Destroy()
			pills[stand] = nil
		end
	end

	------------------------------------------------------------- Okno kupna
	local dialog = Kit.panel(hud.gui, {
		name = "BoxBuy",
		size = Vector2.new(620, 460),
		title = "",
		padding = 30,
		top = 28,
		bottom = 26,
	})
	hud.registerScale(dialog.holder)
	hud.addPopup(dialog)
	local question = Kit.text(dialog.content, {
		Name = "Question",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 0),
		Size = UDim2.new(1, 0, 0, 104),
		Text = "",
		TextColor3 = Theme.Dark,
		TextWrapped = true,
		ZIndex = 4,
	}, { maxSize = 44, stroke = 0 })
	local boxView = Kit.new("ViewportFrame", {
		Name = "Box",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 106),
		Size = UDim2.fromOffset(200, 140),
		BackgroundTransparency = 1,
		Ambient = Color3.fromRGB(205, 205, 215),
		LightColor = Color3.new(1, 1, 1),
		ZIndex = 4,
		Parent = dialog.content,
	})
	local infoLine = Kit.line(dialog.content, {
		anchor = Vector2.new(0.5, 0.5),
		position = UDim2.new(0.5, 0, 0, 266),
		height = 30,
	})
	infoLine.holder.ZIndex = 4
	local rangeLine = Kit.line(dialog.content, {
		anchor = Vector2.new(0.5, 0.5),
		position = UDim2.new(0.5, 0, 0, 298),
		height = 30,
	})
	rangeLine.holder.ZIndex = 4
	local priceLine = Kit.line(dialog.content, {
		anchor = Vector2.new(0.5, 1),
		position = UDim2.new(0.5, 0, 1, -76),
		height = 44,
	})
	priceLine.holder.ZIndex = 4
	local buyButton = Kit.button(dialog.content, {
		name = "Buy",
		size = Vector2.new(260, 66),
		text = TEXT.Buy,
		colors = Theme.Gradients.Green,
		anchor = Vector2.new(0.5, 1),
		position = UDim2.new(0.5, 0, 1, 0),
		textSize = 36,
	})
	local dialogBox = nil
	local dialogBoxKind = nil

	local function renderDialog()
		local info = current and boxInfo(current.box)
		local view = State.view
		if info == nil or view == nil then
			return
		end
		question.Text = string.format(TEXT.Question, boxName(current.box))
		infoLine.set({ { text = TEXT.Random, size = 22, color = Theme.Dark, stroke = 0 } })
		local list = raritiesOf(info)
		rangeLine.set({
			{ text = percentText(Formulas.clothBonus(list[1], 0)), size = 24, colors = Theme.Gradients.Gold },
			{ text = "to", size = 22 },
			{ text = percentText(Formulas.clothBonus(list[#list], 0)) .. " LP", size = 24, colors = Theme.Gradients.Gold },
		})
		if unlocked(current.box) then
			priceLine.set({
				{ icon = "Cash", size = 40 },
				{ text = Format.number(info.Price), size = 32, colors = Theme.Gradients.Gold },
			})
			if view.Cash >= info.Price then
				buyButton.setColors(Theme.Gradients.Green)
			else
				buyButton.setColors(Theme.Gradients.Gray)
			end
		else
			local zone = Economy.Zones[info.RequiresZone]
			priceLine.set({
				{ icon = "Lock", size = 36 },
				{ text = string.format(TEXT.Locked, (zone and zone.Name) or ("zone " .. info.RequiresZone)), size = 26 },
			})
			buyButton.setColors(Theme.Gradients.Gray)
		end
	end

	local function openDialog()
		if current == nil or opening or State.busy then
			return
		end
		if dialogBoxKind ~= current.box then
			dialogBoxKind = current.box
			dialogBox = boxForView(current.box)
			showModel(boxView, dialogBox, 1.2)
		end
		renderDialog()
		panelGui.Enabled = false
		promptGui.Enabled = false
		dialog.open()
	end

	RunService.RenderStepped:Connect(function()
		if dialogBox ~= nil and dialog.isOpen() then
			dialogBox:PivotTo(CFrame.Angles(0, math.sin(os.clock() * 1.3) * 0.4, 0))
		end
	end)

	------------------------------------------------------------- Animacja otwierania
	local openGui = Kit.new("ScreenGui", {
		Name = "LarpBoxOpen",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 16,
		Enabled = false,
		Parent = playerGui,
	})
	local dim = Kit.new("Frame", {
		Name = "Dim",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = openGui,
	})
	local stage = Kit.new("Frame", {
		Name = "Stage",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(STAGE_SIZE.X, STAGE_SIZE.Y),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = openGui,
	})
	hud.registerScale(stage)
	local fx = Kit.new("Frame", { Name = "Fx", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 9, Parent = stage })
	local flash = Kit.new("Frame", {
		Name = "Flash",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 20,
		Parent = openGui,
	})
	local function stageLine(y, height)
		local l = Kit.line(stage, { anchor = Vector2.new(0.5, 0.5), position = UDim2.new(0.5, 0, 0, y), height = height })
		l.holder.ZIndex = 8
		l.scale = Kit.new("UIScale", { Scale = 0, Parent = l.holder })
		return l
	end
	local center = Vector2.new(STAGE_SIZE.X / 2, STAGE_SIZE.Y / 2 - 20)
	local banner = stageLine(center.Y - SLOT / 2 - 44, 60)
	local nameLine = stageLine(center.Y + SLOT / 2 + 24, 52)
	local infoLine2 = stageLine(center.Y + SLOT / 2 + 66, 40)
	local wornLine = stageLine(center.Y + SLOT / 2 + 102, 34)

	local holder = Kit.new("Frame", {
		Name = "Slot",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(center.X, center.Y),
		Size = UDim2.fromOffset(SLOT, SLOT),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = stage,
	})
	local holderScale = Kit.new("UIScale", { Parent = holder })
	local rays = Kit.new("Frame", {
		Name = "Rays",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(SLOT * 1.55, SLOT * 1.55),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 2,
		Parent = holder,
	})
	local raysScale = Kit.new("UIScale", { Parent = rays })
	local bars = {}
	for i = 1, 8 do
		local bar = Kit.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(0, math.floor(SLOT * 0.15), 1, 0),
			BorderSizePixel = 0,
			Rotation = (i - 1) * 22.5,
			ZIndex = 2,
			Parent = rays,
		})
		Kit.new("UIGradient", { Rotation = 90, Transparency = RAY_FADE, Parent = bar })
		bars[i] = bar
	end
	local glow = Kit.new("Frame", {
		Name = "Glow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(SLOT * 0.84, SLOT * 0.84),
		BackgroundTransparency = 0.5,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 3,
		Parent = holder,
	})
	Kit.new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = glow })
	local glowStroke = Kit.stroke(glow, 8, Enum.ApplyStrokeMode.Border)
	glowStroke.Transparency = 0.3
	local glowScale = Kit.new("UIScale", { Parent = glow })
	local jolt = Kit.new("Frame", {
		Name = "Jolt",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 4,
		Parent = holder,
	})
	local joltScale = Kit.new("UIScale", { Parent = jolt })
	local view = Kit.new("ViewportFrame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Ambient = Color3.fromRGB(210, 210, 220),
		LightColor = Color3.new(1, 1, 1),
		ZIndex = 4,
		Parent = jolt,
	})
	local pop = Kit.new("UIScale", { Parent = view })

	local particles = {}
	local function spawnParticle(kind, position, velocity, color, size, life)
		local frame = Kit.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(position.X, position.Y),
			Size = UDim2.fromOffset(size, size),
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			Rotation = math.random(0, 90),
			ZIndex = 9,
			Parent = fx,
		})
		local stroke = nil
		if kind == "chip" then
			stroke = Kit.stroke(frame, 2, Enum.ApplyStrokeMode.Border)
		else
			Kit.new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = frame })
		end
		table.insert(particles, {
			kind = kind,
			frame = frame,
			stroke = stroke,
			position = position,
			velocity = velocity,
			size = size,
			life = life,
			age = 0,
			spin = math.random(-360, 360),
		})
	end

	local function updateParticles(dt)
		for i = #particles, 1, -1 do
			local p = particles[i]
			p.age = p.age + dt
			if p.age >= p.life then
				p.frame:Destroy()
				table.remove(particles, i)
			else
				local k = p.age / p.life
				if p.kind == "chip" then
					p.velocity = p.velocity + Vector2.new(0, GRAVITY * dt)
					p.frame.Rotation = p.frame.Rotation + p.spin * dt
					local fade = math.clamp((k - 0.55) / 0.45, 0, 1)
					p.frame.BackgroundTransparency = fade
					p.stroke.Transparency = fade
				else
					local s = math.sin(k * math.pi)
					p.frame.Size = UDim2.fromOffset(p.size * s, p.size * s)
				end
				p.position = p.position + p.velocity * dt
				p.frame.Position = UDim2.fromOffset(p.position.X, p.position.Y)
			end
		end
	end

	local phase = "idle" -- idle, shake, reveal, exit
	local shakeStart, shakeLength = 0, 1
	local kickTime, kickDir = -math.huge, 1
	local shakeUntil = 0
	local revealStart = 0
	local boxModel = nil
	local itemModel = nil
	local lidParts = {}
	local lidCenter = Vector3.new()
	local nextSpark = 0
	local revealItem = nil
	local connection = nil

	local function animate(dt)
		local now = os.clock()
		if phase == "shake" and boxModel ~= nil then
			local e = now - shakeStart
			local progress = math.clamp(e / shakeLength, 0, 1)
			local impulse = math.exp(-(now - kickTime) * 9)
			local angle = math.sin(e * (11 + 16 * progress)) * math.rad(3 + 8 * progress) + kickDir * impulse * math.rad(12)
			boxModel:PivotTo(CFrame.Angles(0, math.rad(25), angle))
			jolt.Position = UDim2.new(0.5, 0, 0.5, -20 * impulse)
			joltScale.Scale = 1 + 0.1 * impulse
		elseif phase == "lid" then
			-- wieko odlatuje w górę, kręcąc się wokół swojego środka (wszystkie części razem)
			local e = now - revealStart
			local k = math.min(1, e / 0.45)
			local turn = CFrame.new(0, k * 6, 0) * CFrame.new(lidCenter) * CFrame.Angles(k * 1.4, 0, k * 0.9) * CFrame.new(-lidCenter)
			for _, entry in ipairs(lidParts) do
				entry.part.CFrame = turn * entry.base
				entry.part.Transparency = k
			end
		elseif phase == "reveal" or phase == "exit" then
			local e = now - revealStart
			if itemModel ~= nil then
				local yaw
				if e < 0.6 then
					yaw = -2 * math.pi * (1 - e / 0.6) ^ 3
				else
					yaw = math.sin((e - 0.6) * 1.6) * 0.35
				end
				itemModel:PivotTo(CFrame.new(0, math.sin(e * 3) * 0.08, 0) * CFrame.Angles(0, yaw, 0))
			end
			for i, bar in ipairs(bars) do
				bar.Rotation = (i - 1) * 22.5 + e * 28
			end
			if phase == "reveal" and e > 0.45 then
				glowScale.Scale = 1 + math.sin(e * 4) * 0.04
			end
			if phase == "reveal" and revealItem ~= nil and BIG_RARITY[revealItem.Rarity] and now >= nextSpark then
				nextSpark = now + 0.07
				local angle = math.random() * math.pi * 2
				local radius = SLOT * (0.2 + math.random() * 0.32)
				local position = center + Vector2.new(math.cos(angle), math.sin(angle)) * radius
				local color = Theme.White
				if math.random() < 0.5 then
					color = rarityColors(revealItem.Rarity)[1]
				end
				spawnParticle("spark", position, Vector2.new(0, -40), color, math.random(16, 28), 0.6)
			end
		end
		updateParticles(dt)
		if now < shakeUntil then
			stage.Position = UDim2.new(0.5, math.random(-7, 7), 0.5, math.random(-7, 7))
		else
			stage.Position = UDim2.fromScale(0.5, 0.5)
		end
	end

	local function popIn(l, delay, time)
		l.scale.Scale = 0
		task.delay(delay, function()
			TweenService:Create(l.scale, TweenInfo.new(time or 0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end)
	end

	local function clearOpen()
		for _, p in ipairs(particles) do
			p.frame:Destroy()
		end
		particles = {}
		for _, child in ipairs(view:GetChildren()) do
			child:Destroy()
		end
		for _, l in ipairs({ banner, nameLine, infoLine2, wornLine }) do
			l.set({})
			l.scale.Scale = 0
		end
		boxModel, itemModel, revealItem = nil, nil, nil
		lidParts = {}
		rays.Visible = false
		glow.Visible = false
		holderScale.Scale = 1
		view.Visible = true
		view.Parent = jolt
		view.AnchorPoint = Vector2.new(0.5, 0.5)
		view.Position = UDim2.fromScale(0.5, 0.5)
		view.Size = UDim2.fromScale(1, 1)
		view.ZIndex = 4
		jolt.Position = UDim2.fromScale(0.5, 0.5)
		joltScale.Scale = 1
		shakeUntil = 0
	end

	local function waitUntil(t)
		local d = t - os.clock()
		if d > 0 then
			task.wait(d)
		end
	end

	local function runOpen(box, item, total)
		clearOpen()
		boxModel = boxForView(box)
		showModel(view, boxModel, 1.35)
		lidParts = {}
		for _, part in ipairs(boxModel:GetChildren()) do
			if part:IsA("BasePart") and part:GetAttribute("Lid") then
				table.insert(lidParts, { part = part, base = part.CFrame })
			end
		end
		pop.Scale = 0.35
		TweenService:Create(pop, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		dim.BackgroundTransparency = 1
		openGui.Enabled = true
		TweenService:Create(dim, TweenInfo.new(0.25), { BackgroundTransparency = 0.3 }):Play()
		local start = os.clock()
		phase = "shake"
		shakeStart = start
		shakeLength = total * BURST_AT
		kickTime = -math.huge
		connection = RunService.RenderStepped:Connect(animate)
		local boxColor = (ClothesConfig.Boxes[box] or ClothesConfig.Boxes.Street).Color
		for k, at in ipairs(BEATS) do
			waitUntil(start + at * total)
			Sounds.play("Crack", { pitch = 0.8 + 0.1 * (k - 1), volume = 0.9 })
			kickTime = os.clock()
			kickDir = -kickDir
			for _ = 1, 2 + k do
				local angle = math.rad(math.random(200, 340))
				local dir = Vector2.new(math.cos(angle), math.sin(angle))
				spawnParticle("chip", center + dir * SLOT * 0.25, dir * math.random(200, 360), boxColor, math.random(7, 12), 0.7)
			end
		end
		waitUntil(start + BURST_AT * total)

		-- wieko odlatuje (box jest już przekręcony, więc liczymy od tego położenia)
		local sum = Vector3.new()
		for _, entry in ipairs(lidParts) do
			entry.base = entry.part.CFrame
			sum = sum + entry.base.Position
		end
		if #lidParts > 0 then
			lidCenter = sum / #lidParts
		end
		phase = "lid"
		revealStart = os.clock()
		Sounds.play("Crack", { pitch = 0.75, volume = 1.2 })
		flash.BackgroundTransparency = 0.2
		TweenService:Create(flash, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 }):Play()
		task.wait(0.32)

		-- ubranie wyskakuje z promieniami w kolorze rzadkości
		local color = PetsConfig.RarityColors[item.Rarity] or Theme.White
		for _, bar in ipairs(bars) do
			bar.BackgroundColor3 = color
		end
		glow.BackgroundColor3 = color
		glowStroke.Color = color
		revealItem = item
		phase = "reveal"
		revealStart = os.clock()
		Sounds.play("Hatch")
		if BIG_RARITY[item.Rarity] then
			shakeUntil = os.clock() + 0.45
			task.delay(0.2, function()
				Sounds.play("Reward")
			end)
		end
		flash.BackgroundTransparency = 0
		TweenService:Create(flash, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 }):Play()
		for n = 1, 14 do
			local angle = math.rad(n * (360 / 14) + math.random(-10, 10))
			local dir = Vector2.new(math.cos(angle), math.sin(angle))
			spawnParticle("chip", center + dir * SLOT * 0.15, dir * math.random(300, 520), boxColor, math.random(9, 16), 0.9)
		end
		itemModel = ClothModels.display(item.Category, item.Rarity, item.Level or 0)
		showModel(view, itemModel, 1.6)
		boxModel = nil
		pop.Scale = 0.15
		TweenService:Create(pop, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		glow.Visible = true
		glowScale.Scale = 0.3
		TweenService:Create(glowScale, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		rays.Visible = true
		raysScale.Scale = 0
		TweenService:Create(raysScale, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		local text = string.format(TEXT.New, string.upper(item.Category))
		local colors = Theme.Gradients.Gold
		if BIG_RARITY[item.Rarity] then
			text = string.format(TEXT.Rare, string.upper(item.Rarity))
			colors = rarityColors(item.Rarity)
		end
		banner.set({ { text = text, size = 46, colors = colors } })
		popIn(banner, 0, 0.35)
		nameLine.set({ { text = ClothesConfig.fullName(item.Category, item.Rarity, item.Level), size = 44 } })
		popIn(nameLine, 0.1)
		infoLine2.set({
			Pets.rarityItem(item.Rarity, 30),
			{ text = Wardrobe.bonusText(item), size = 28, colors = Theme.Gradients.Gold },
		})
		popIn(infoLine2, 0.22)
		if item.Worn then
			wornLine.set({ { text = TEXT.Wearing, size = 24, colors = Theme.Gradients.Green } })
			popIn(wornLine, 0.34)
		end
		task.wait(math.max(1.2, total * 0.55))

		-- koniec: HUD wraca, a ubranie leci do kafelka CLOTHES
		phase = "exit"
		hud.setVisible(true)
		TweenService:Create(dim, TweenInfo.new(0.35), { BackgroundTransparency = 1 }):Play()
		for _, l in ipairs({ banner, nameLine, infoLine2, wornLine }) do
			TweenService:Create(l.scale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Scale = 0 }):Play()
		end
		local target = Wardrobe.tileCenter()
		if target ~= nil then
			local position, size = view.AbsolutePosition, view.AbsoluteSize
			view.AnchorPoint = Vector2.new(0.5, 0.5)
			view.Position = UDim2.fromOffset(position.X + size.X / 2, position.Y + size.Y / 2)
			view.Size = UDim2.fromOffset(size.X, size.Y)
			view.ZIndex = 12
			view.Parent = openGui
			local goal = target + GuiService:GetGuiInset()
			TweenService:Create(view, TweenInfo.new(0.42, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Position = UDim2.fromOffset(goal.X, goal.Y),
				Size = UDim2.fromOffset(40, 40),
			}):Play()
			task.delay(0.42, function()
				view.Visible = false
				Wardrobe.bump()
			end)
		end
		TweenService:Create(holderScale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Scale = 0 }):Play()
		task.wait(0.6)
	end

	local function open(box, item, total)
		opening = true
		State.busy = true
		panelGui.Enabled = false
		promptGui.Enabled = false
		hud.setVisible(false)
		local ok, err = pcall(runOpen, box, item, total)
		if not ok then
			warn("[Boxy] animacja otwierania: " .. tostring(err))
		end
		if connection ~= nil then
			connection:Disconnect()
			connection = nil
		end
		phase = "idle"
		clearOpen()
		openGui.Enabled = false
		hud.setVisible(true)
		State.busy = false
		opening = false
	end

	------------------------------------------------------------- Kupno
	local requesting = false
	buyButton.Activated:Connect(function()
		if requesting or opening or current == nil then
			return
		end
		local box = current.box
		if not unlocked(box) then
			local info = boxInfo(box)
			local zone = info and Economy.Zones[info.RequiresZone]
			Sounds.play("NotEnough")
			hud.toast({ { icon = "Lock", size = 40 }, { text = string.format(TEXT.Locked, (zone and zone.Name) or "zone"), size = 26 } }, "BoxLocked")
			return
		end
		requesting = true
		local ok, result = pcall(function()
			return Net.func("BuyBox"):InvokeServer(box)
		end)
		requesting = false
		if not ok or type(result) ~= "table" then
			return
		end
		if result.Ok and type(result.Item) == "table" then
			dialog.hide()
			open(box, result.Item, result.OpenTime or Economy.OpenTimeSeconds)
		elseif result.Reason == "NotEnough" then
			hud.notEnough(buyButton)
		elseif result.Reason == "Inventory" then
			Sounds.play("NotEnough")
			hud.toast({ { text = TEXT.Inventory, size = 26, colors = Theme.Gradients.Red } }, "ClothInventory")
		end
	end)

	promptButton.Activated:Connect(function()
		Sounds.play("Button")
		openDialog()
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or input.KeyCode ~= Enum.KeyCode.E or opening then
			return
		end
		if dialog.isOpen() then
			dialog.hide()
		elseif promptGui.Enabled then
			Sounds.play("Button")
			openDialog()
		end
	end)

	------------------------------------------------------------- Najbliższy box
	local function setCurrent(stand)
		if stand == nil then
			current = nil
			if dialog.isOpen() then
				dialog.hide()
			end
			return
		end
		current = { stand = stand, box = stand:GetAttribute("Box") }
		placePrompt(stand)
		if panelKey ~= current.box then
			panelKey = current.box
			renderPanel(current.box)
		end
	end

	local function nearestStand(position)
		local best, bestDistance = nil, math.huge
		for _, stand in ipairs(stands) do
			if stand.Parent ~= nil and standVisible(stand) then
				local d = distanceToStand(stand, position)
				if d < bestDistance then
					best, bestDistance = stand, d
				end
			end
		end
		return best, bestDistance
	end

	local timer = 0
	RunService.Heartbeat:Connect(function(dt)
		timer = timer + dt
		if timer < 0.1 then
			return
		end
		timer = 0
		local hide = opening or State.busy
		if hide ~= pillsHidden then
			pillsHidden = hide
			for _, stand in ipairs(stands) do
				updatePill(stand)
			end
		end
		if opening then
			return
		end
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root == nil or State.view == nil or State.busy or hud.windowOpen() then
			setCurrent(nil)
		else
			local position = root.Position
			if current ~= nil then
				local d = math.huge
				if current.stand.Parent ~= nil and standVisible(current.stand) then
					d = distanceToStand(current.stand, position)
				end
				if d > HIDE_DISTANCE then
					setCurrent(nil)
				end
			end
			local best, bestDistance = nearestStand(position)
			if best ~= nil and bestDistance <= SHOW_DISTANCE then
				if current == nil or (best ~= current.stand and not dialog.isOpen()) then
					setCurrent(best)
				end
			end
		end
		local show = current ~= nil and not dialog.isOpen()
		panelGui.Enabled = show
		promptGui.Enabled = show
	end)

	local lastUnlocked = nil
	State.onChange(function(v)
		if v.ZonesUnlocked ~= lastUnlocked then
			lastUnlocked = v.ZonesUnlocked
			for _, stand in ipairs(stands) do
				updatePill(stand)
			end
		end
		if dialog.isOpen() then
			renderDialog()
		end
	end)

	for _, stand in ipairs(CollectionService:GetTagged(BOX_TAG)) do
		onStandAdded(stand)
	end
	CollectionService:GetInstanceAddedSignal(BOX_TAG):Connect(onStandAdded)
	CollectionService:GetInstanceRemovedSignal(BOX_TAG):Connect(onStandRemoved)
end

return Boxes
