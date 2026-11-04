-- Mystery boxy z ubraniami po stronie gracza (Etap 8), tak jak jajka w Eggs.luau:
--   • przy każdym boxie pigułka z ceną (albo kłódka i strefa, którą trzeba najpierw odblokować),
--   • nad najbliższym panel z szansami rzadkości i bonusem do LP, a na boxie duże E;
--     E (klawisz albo kliknięcie) otwiera okno kupna z Buy 1 i Buy 3 (Buy 3 z gamepassem
--     Triple Open, tym samym co przy jajkach),
--   • animacja: boxy drżą 3 razy, wieka odlatują, a ze środka wyskakują ubrania z promieniami
--     w kolorze rzadkości; napisy wskakują po kolei, a na koniec ubrania lecą do kafelka CLOTHES.
--     Ultra Secret (ubrania „chrome” z boxa Iced, 1 na 250 000) ma osobną animację: czarno-srebrne
--     promienie, srebrny błysk, „vine boom”, mocniejsze drżenie i dłuższy pokaz.
-- Kupno i losowanie robi serwer (ClothesService); tu jest tylko wygląd.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")
local MarketplaceService = game:GetService("MarketplaceService")
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
local StandAnchor = require(script.Parent.StandAnchor)

local Boxes = {}

local BOX_TAG = "LarpBox" -- jak ClothesService.BoxTag na serwerze
local SHOW_DISTANCE = 8 -- panel i E pokazują się, gdy stoisz tak blisko boxa (studs od stoiska)
local HIDE_DISTANCE = 12
local TRIPLE = Economy.Robux.Gamepasses.TripleOpen.OpenCount
local BIG_RARITY = { Legendary = true, Mythic = true, UltraSecret = true } -- iskry, drżenie i oklaski

-- Wygląd przy boxie (studs), jak przy jajkach
local PILL_SIZE = Vector2.new(4.6, 1.4)
local PILL_HEIGHT = 1.7
local PANEL_CARD = 2.1
local PANEL_PAD = 0.35
local PANEL_BODY = 2.7
local PANEL_TIP = 0.45
local PANEL_LIFT = 0.6
local PANEL_EDGE = Color3.fromRGB(205, 210, 222)

-- Animacja (piksele bazowe 1280×720)
local STAGE_SIZE = Vector2.new(1200, 700)
local STAGE_Y = 0.5
local SLOT_BIG = 420 -- jeden box
local SLOT_SMALL = 330 -- trzy boxy obok siebie
local SLOT_SPACING = 370
local BEATS = { 0.27, 0.42, 0.57 } -- drgnięcia (część czasu otwierania)
local BURST_AT = 0.66 -- wieka odlatują
local LID_TIME = 0.32
local GRAVITY = 1100
local RAY_FADE = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(0.32, 0.8),
	NumberSequenceKeypoint.new(0.5, 0.5),
	NumberSequenceKeypoint.new(0.68, 0.8),
	NumberSequenceKeypoint.new(1, 1),
})

-- Ultra Secret: czarno-srebrne promienie, srebrny błysk, dłuższy pokaz
local ULTRA_RAYS = { Color3.fromRGB(28, 28, 34), Color3.fromRGB(222, 228, 238) }
local ULTRA_FLASH = Color3.fromRGB(236, 240, 248)
local ULTRA_HOLD = 2.2

local TEXT = {
	Question = "Would you like to buy a\n%s?",
	Buy = "Buy %d",
	Random = "1 random item from 7 categories",
	To = "to",
	Locked = "Unlock %s first",
	Gamepass = "Gamepass",
	NoPass = "Buy 3 needs the Triple Open gamepass",
	PassSoon = "Triple Open gamepass is coming soon!",
	Inventory = "Not enough room for more clothes",
	NewOne = "NEW %s!",
	NewMany = "NEW CLOTHES!",
	Rare = "%s ITEM!",
	Ultra = "ULTRA SECRET!",
	Wearing = "Wearing!",
}

local RANK = {}
for i, rarity in ipairs(Economy.Clothes.RarityOrder) do
	RANK[rarity] = i
end

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
	for _, rarity in ipairs(Economy.Clothes.RarityOrder) do
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

-- Mniejszy napis, gdy się nie mieści (przy trzech boxach długie nazwy wchodziły na sąsiednie).
local function fitSize(text, size, maxWidth)
	while size > 16 and Kit.measure(text, size).X > maxWidth do
		size = size - 2
	end
	return size
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

	local function zoneName(info)
		local zone = info and Economy.Zones[info.RequiresZone]
		return (zone and zone.Name) or "zone"
	end

	------------------------------------------------------------- Cena przy każdym boxie
	local pills = {} -- [stoisko] = { gui, render }
	local pillsHidden = false

	local function updatePill(stand)
		local entry = pills[stand]
		if entry == nil then
			return
		end
		local part, _, bottom = StandAnchor.get(stand)
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
		local iconHolder = Kit.new("Frame", {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromScale(0.05, 0.5),
			Size = UDim2.fromScale(0.26, 0.9),
			BackgroundTransparency = 1,
			ZIndex = 2,
			Parent = face,
		})
		Kit.new("UIAspectRatioConstraint", { AspectRatio = 1, Parent = iconHolder })
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
			for _, child in ipairs(iconHolder:GetChildren()) do
				child:Destroy()
			end
			Icons.make(name, { Size = UDim2.fromScale(1, 1), ZIndex = 2, Parent = iconHolder })
		end
		-- zablokowany box: kłódka i nazwa strefy, którą trzeba odblokować
		local function render()
			if unlocked(box) then
				setIcon("Cash")
				label.Text = Format.number(info.Price)
				gradient.Color = ColorSequence.new(Theme.Gradients.Yellow[1], Theme.Gradients.Yellow[2])
			else
				setIcon("Lock")
				label.Text = zoneName(info)
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
			if rarity == "UltraSecret" then
				-- chrom: srebrny kafelek, jak w oknie CLOTHES
				tileFrame.BackgroundColor3 = Theme.White
				Kit.gradient(tileFrame, Pets.ChromeColors, 90)
			end
			Kit.text(tileFrame, {
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.fromScale(0.5, 0.08),
				Size = UDim2.fromScale(0.9, 0.42),
				Text = PetsConfig.rarityName(rarity),
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

	------------------------------------------------------------- Duże E na boxie
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

	-- Panel nad boxem, E na środku boxa (jak przy jajkach).
	local function placePrompt(stand)
		local part, top, bottom = StandAnchor.get(stand)
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
		StandAnchor.forget(stand)
	end

	------------------------------------------------------------- Okno kupna
	local dialog = Kit.panel(hud.gui, {
		name = "BoxBuy",
		size = Vector2.new(620, 500),
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
		Position = UDim2.new(0.5, 0, 0, 104),
		Size = UDim2.fromOffset(200, 128),
		BackgroundTransparency = 1,
		Ambient = Color3.fromRGB(205, 205, 215),
		LightColor = Color3.new(1, 1, 1),
		ZIndex = 4,
		Parent = dialog.content,
	})
	local infoLine = Kit.line(dialog.content, {
		anchor = Vector2.new(0.5, 0.5),
		position = UDim2.new(0.5, 0, 0, 250),
		height = 30,
	})
	infoLine.holder.ZIndex = 4
	local rangeLine = Kit.line(dialog.content, {
		anchor = Vector2.new(0.5, 0.5),
		position = UDim2.new(0.5, 0, 0, 284),
		height = 32,
	})
	rangeLine.holder.ZIndex = 4
	local columns = {}
	for i, count in ipairs({ 1, TRIPLE }) do
		local x = 0.26
		if i == 2 then
			x = 0.74
		end
		local priceLine = Kit.line(dialog.content, {
			anchor = Vector2.new(0.5, 1),
			position = UDim2.new(x, 0, 1, -78),
			height = 44,
		})
		priceLine.holder.ZIndex = 4
		local button = Kit.button(dialog.content, {
			name = "Buy" .. count,
			size = Vector2.new(230, 66),
			text = string.format(TEXT.Buy, count),
			colors = Theme.Gradients.Green,
			anchor = Vector2.new(0.5, 1),
			position = UDim2.new(x, 0, 1, 0),
			textSize = 36,
		})
		columns[i] = { count = count, price = priceLine, button = button }
	end
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
			{ text = TEXT.To, size = 22 },
			{ text = percentText(Formulas.clothBonus(list[#list], 0)) .. " LP", size = 24, colors = Theme.Gradients.Gold },
		})
		local passes = view.Passes or {}
		local open = unlocked(current.box)
		for _, column in ipairs(columns) do
			local total = info.Price * column.count
			if not open then
				column.price.set({ { icon = "Lock", size = 32 }, { text = zoneName(info), size = 24 } })
				column.button.setColors(Theme.Gradients.Gray)
			elseif column.count > 1 and not passes.TripleOpen then
				column.price.set({ { icon = "Lock", size = 36 }, { text = TEXT.Gamepass, size = 28 } })
				column.button.setColors(Theme.Gradients.Gray)
			else
				column.price.set({
					{ icon = "Cash", size = 40 },
					{ text = Format.number(total), size = 32, colors = Theme.Gradients.Gold },
				})
				if view.Cash >= total then
					column.button.setColors(Theme.Gradients.Green)
				else
					column.button.setColors(Theme.Gradients.Gray)
				end
			end
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

	-- box w oknie lekko się kołysze
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
		Position = UDim2.fromScale(0.5, STAGE_Y),
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
	local banner = Kit.line(stage, { name = "Banner", anchor = Vector2.new(0.5, 0.5), position = UDim2.new(0.5, 0, 0, 96), height = 60 })
	banner.holder.ZIndex = 8
	local bannerScale = Kit.new("UIScale", { Scale = 0, Parent = banner.holder })
	local subBanner = Kit.line(stage, { name = "SubBanner", anchor = Vector2.new(0.5, 0.5), position = UDim2.new(0.5, 0, 0, 140), height = 40 })
	subBanner.holder.ZIndex = 8
	local subBannerScale = Kit.new("UIScale", { Scale = 0, Parent = subBanner.holder })

	local slots = {}
	local particles = {}
	local phase = "idle" -- idle, shake, lid, reveal, exit
	local shakeStart, shakeLength = 0, 1
	local kickTime, kickDir = -math.huge, 1
	local shakeUntil = 0
	local lidStart = 0
	local connection = nil

	local function popIn(uiScale, delay, time)
		uiScale.Scale = 0
		task.delay(delay, function()
			TweenService:Create(uiScale, TweenInfo.new(time or 0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end)
	end

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

	-- Miejsce na jeden box i ubranie (1 na środku albo 3 obok siebie).
	local function makeSlot(index, count, item)
		local big = count == 1
		local size, spacing = SLOT_SMALL, SLOT_SPACING
		if big then
			size, spacing = SLOT_BIG, 0
		end
		local x = (index - (count + 1) / 2) * spacing
		local ultra = item.Rarity == "UltraSecret"
		local color = PetsConfig.RarityColors[item.Rarity] or Theme.White
		if ultra then
			color = ULTRA_RAYS[2]
		end
		local holder = Kit.new("Frame", {
			Name = "Slot" .. index,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, x, 0.5, 0),
			Size = UDim2.fromOffset(size, size),
			BackgroundTransparency = 1,
			ZIndex = 2,
			Parent = stage,
		})
		local holderScale = Kit.new("UIScale", { Parent = holder })
		local rays = Kit.new("Frame", {
			Name = "Rays",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(size * 1.55, size * 1.55),
			BackgroundTransparency = 1,
			Visible = false,
			ZIndex = 2,
			Parent = holder,
		})
		local raysScale = Kit.new("UIScale", { Parent = rays })
		local bars = {}
		for i = 1, 8 do
			local barColor = color
			if ultra then
				barColor = ULTRA_RAYS[(i % 2) + 1]
			end
			local bar = Kit.new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.new(0, math.floor(size * 0.15), 1, 0),
				BackgroundColor3 = barColor,
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
			Size = UDim2.fromOffset(size * 0.84, size * 0.84),
			BackgroundColor3 = color,
			BackgroundTransparency = 0.5,
			BorderSizePixel = 0,
			Visible = false,
			ZIndex = 3,
			Parent = holder,
		})
		Kit.new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = glow })
		local glowStroke = Kit.stroke(glow, 8, Enum.ApplyStrokeMode.Border, color)
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
		local viewport = Kit.new("ViewportFrame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Ambient = Color3.fromRGB(210, 210, 220),
			LightColor = Color3.new(1, 1, 1),
			ZIndex = 4,
			Parent = jolt,
		})
		local pop = Kit.new("UIScale", { Parent = viewport })
		local function line(y, height)
			local l = Kit.line(holder, {
				anchor = Vector2.new(0.5, 0.5),
				position = UDim2.new(0.5, 0, 0, y + height / 2),
				height = height,
			})
			l.holder.ZIndex = 6
			l.scale = Kit.new("UIScale", { Scale = 0, Parent = l.holder })
			return l
		end
		local nameH, infoH, wornH = 38, 32, 28
		if big then
			nameH, infoH, wornH = 52, 40, 34
		end
		local sparkColor = rarityColors(item.Rarity)[1]
		if ultra then
			sparkColor = ULTRA_RAYS[2]
		end
		return {
			big = big,
			size = size,
			item = item,
			ultra = ultra,
			center = Vector2.new(STAGE_SIZE.X / 2 + x, STAGE_SIZE.Y / 2),
			holder = holder,
			holderScale = holderScale,
			rays = rays,
			raysScale = raysScale,
			bars = bars,
			glow = glow,
			glowScale = glowScale,
			jolt = jolt,
			joltScale = joltScale,
			viewport = viewport,
			pop = pop,
			nameLine = line(size + 4, nameH),
			infoLine = line(size + 4 + nameH, infoH),
			wornLine = line(size + 6 + nameH + infoH, wornH),
			sparkColor = sparkColor,
			wobble = math.random() * 6.28,
			nextSpark = 0,
			lidParts = {},
			lidCenter = Vector3.new(),
		}
	end

	local function animate(dt)
		local now = os.clock()
		if phase == "shake" then
			local e = now - shakeStart
			local progress = math.clamp(e / shakeLength, 0, 1)
			local impulse = math.exp(-(now - kickTime) * 9)
			for _, slot in ipairs(slots) do
				if slot.boxModel ~= nil then
					local angle = math.sin(e * (11 + 16 * progress) + slot.wobble) * math.rad(3 + 8 * progress)
						+ kickDir * impulse * math.rad(12)
					slot.boxModel:PivotTo(CFrame.Angles(0, math.rad(25), angle))
				end
				slot.jolt.Position = UDim2.new(0.5, 0, 0.5, -20 * impulse)
				slot.joltScale.Scale = 1 + 0.1 * impulse
			end
		elseif phase == "lid" then
			-- wieka odlatują w górę, kręcąc się wokół swojego środka (wszystkie części razem)
			local k = math.min(1, (now - lidStart) / 0.45)
			for _, slot in ipairs(slots) do
				local turn = CFrame.new(0, k * 6, 0) * CFrame.new(slot.lidCenter) * CFrame.Angles(k * 1.4, 0, k * 0.9) * CFrame.new(-slot.lidCenter)
				for _, entry in ipairs(slot.lidParts) do
					entry.part.CFrame = turn * entry.base
					entry.part.Transparency = k
				end
			end
		elseif phase == "reveal" or phase == "exit" then
			for _, slot in ipairs(slots) do
				local e = now - (slot.revealStart or now)
				if slot.itemModel ~= nil then
					local yaw
					if e < 0.6 then
						yaw = -2 * math.pi * (1 - e / 0.6) ^ 3
					else
						yaw = math.sin((e - 0.6) * 1.6) * 0.35
					end
					slot.itemModel:PivotTo(CFrame.new(0, math.sin(e * 3) * 0.08, 0) * CFrame.Angles(0, yaw, 0))
				end
				for i, bar in ipairs(slot.bars) do
					bar.Rotation = (i - 1) * 22.5 + e * 28
				end
				if phase == "reveal" and e > 0.45 then
					slot.glowScale.Scale = 1 + math.sin(e * 4) * 0.04
				end
				if phase == "reveal" and BIG_RARITY[slot.item.Rarity] and now >= slot.nextSpark then
					local gap = 0.07
					if slot.ultra then
						gap = 0.03
					end
					slot.nextSpark = now + gap
					local angle = math.random() * math.pi * 2
					local radius = slot.size * (0.2 + math.random() * 0.32)
					local position = slot.center + Vector2.new(math.cos(angle), math.sin(angle)) * radius
					local color = Theme.White
					local roll = math.random()
					if slot.ultra and roll < 0.33 then
						color = ULTRA_RAYS[1]
					elseif roll < 0.5 then
						color = slot.sparkColor
					end
					spawnParticle("spark", position, Vector2.new(0, -40), color, math.random(16, 28), 0.6)
				end
			end
		end
		updateParticles(dt)
		if now < shakeUntil then
			stage.Position = UDim2.new(0.5, math.random(-7, 7), STAGE_Y, math.random(-7, 7))
		else
			stage.Position = UDim2.fromScale(0.5, STAGE_Y)
		end
	end

	local function clearOpen()
		for _, p in ipairs(particles) do
			p.frame:Destroy()
		end
		particles = {}
		for _, slot in ipairs(slots) do
			slot.holder:Destroy()
			slot.viewport:Destroy()
		end
		slots = {}
		banner.set({})
		bannerScale.Scale = 0
		subBanner.set({})
		subBannerScale.Scale = 0
		shakeUntil = 0
	end

	local function waitUntil(t)
		local d = t - os.clock()
		if d > 0 then
			task.wait(d)
		end
	end

	-- Wieka odlatują, a ubrania wyskakują z promieniami. Zwraca true przy Ultra Secret.
	local function burst(box)
		local boxColor = (ClothesConfig.Boxes[box] or ClothesConfig.Boxes.Street).Color
		local best = nil
		for _, slot in ipairs(slots) do
			if best == nil or (RANK[slot.item.Rarity] or 0) > (RANK[best] or 0) then
				best = slot.item.Rarity
			end
		end
		local ultra = best == "UltraSecret"
		local now = os.clock()
		if ultra then
			flash.BackgroundColor3 = ULTRA_FLASH
			TweenService:Create(dim, TweenInfo.new(0.4), { BackgroundTransparency = 0.08 }):Play()
		else
			flash.BackgroundColor3 = Color3.new(1, 1, 1)
		end
		flash.BackgroundTransparency = 0
		TweenService:Create(flash, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 }):Play()
		Sounds.play("Hatch")
		if ultra then
			Sounds.play("SecretReveal")
			shakeUntil = now + 1
			task.delay(0.35, function()
				Sounds.play("Reward")
			end)
		elseif BIG_RARITY[best] then
			shakeUntil = now + 0.45
			task.delay(0.2, function()
				Sounds.play("Reward")
			end)
		end
		for i, slot in ipairs(slots) do
			local item = slot.item
			slot.jolt.Position = UDim2.fromScale(0.5, 0.5)
			slot.joltScale.Scale = 1
			for n = 1, 12 do
				local angle = math.rad(n * 30 + math.random(-12, 12))
				local dir = Vector2.new(math.cos(angle), math.sin(angle))
				spawnParticle("chip", slot.center + dir * slot.size * 0.15, dir * math.random(300, 520), boxColor, math.random(9, 16), 0.9)
			end
			slot.boxModel = nil
			slot.itemModel = ClothModels.display(item.Category, item.Rarity, item.Level or 0)
			showModel(slot.viewport, slot.itemModel, 1.6)
			slot.revealStart = now
			slot.pop.Scale = 0.15
			TweenService:Create(slot.pop, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
			slot.glow.Visible = true
			slot.glowScale.Scale = 0.3
			TweenService:Create(slot.glowScale, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
			slot.rays.Visible = true
			slot.raysScale.Scale = 0
			TweenService:Create(slot.raysScale, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1 }):Play()
			local delay = 0.1 + (i - 1) * 0.06
			local nameSize, infoSize, bonusSize, wornSize = 30, 22, 21, 19
			local maxWidth = SLOT_SPACING - 24
			if slot.big then
				nameSize, infoSize, bonusSize, wornSize = 44, 30, 28, 24
				maxWidth = STAGE_SIZE.X - 80
			end
			local name = ClothesConfig.fullName(item.Category, item.Rarity, item.Level)
			slot.nameLine.set({ { text = name, size = fitSize(name, nameSize, maxWidth) } })
			popIn(slot.nameLine.scale, delay)
			slot.infoLine.set({
				Pets.rarityItem(item.Rarity, infoSize),
				{ text = Wardrobe.bonusText(item), size = bonusSize, colors = Theme.Gradients.Gold },
			})
			popIn(slot.infoLine.scale, delay + 0.12)
			if item.Worn then
				slot.wornLine.set({ { text = TEXT.Wearing, size = wornSize, colors = Theme.Gradients.Green } })
				popIn(slot.wornLine.scale, delay + 0.24)
			end
		end
		local text = TEXT.NewMany
		if #slots == 1 then
			text = string.format(TEXT.NewOne, string.upper(slots[1].item.Category))
		end
		local colors = Theme.Gradients.Gold
		local bannerSize = 46
		if ultra then
			text = TEXT.Ultra
			colors = Pets.ChromeColors
			bannerSize = 58
		elseif BIG_RARITY[best] then
			text = string.format(TEXT.Rare, string.upper(PetsConfig.rarityName(best)))
			colors = rarityColors(best)
		end
		banner.set({ { text = text, size = bannerSize, colors = colors } })
		popIn(bannerScale, 0, 0.35)
		if ultra then
			subBanner.set({ { text = Format.oneIn(Economy.Clothes.UltraSecretChance), size = 32, colors = Theme.Gradients.Gold } })
			popIn(subBannerScale, 0.25, 0.35)
		end
		return ultra
	end

	-- Koniec: HUD wraca, a ubrania lecą do kafelka CLOTHES (kafelek podskakuje).
	local function exit()
		phase = "exit"
		hud.setVisible(true)
		TweenService:Create(dim, TweenInfo.new(0.35), { BackgroundTransparency = 1 }):Play()
		TweenService:Create(bannerScale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Scale = 0 }):Play()
		TweenService:Create(subBannerScale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Scale = 0 }):Play()
		local target = Wardrobe.tileCenter()
		local inset = GuiService:GetGuiInset()
		for i, slot in ipairs(slots) do
			if target ~= nil then
				local viewport = slot.viewport
				local position, size = viewport.AbsolutePosition, viewport.AbsoluteSize
				viewport.AnchorPoint = Vector2.new(0.5, 0.5)
				viewport.Position = UDim2.fromOffset(position.X + size.X / 2, position.Y + size.Y / 2)
				viewport.Size = UDim2.fromOffset(size.X, size.Y)
				viewport.ZIndex = 12
				viewport.Parent = openGui
				local goal = target + inset
				local fly = TweenService:Create(viewport, TweenInfo.new(0.42, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
					Position = UDim2.fromOffset(goal.X, goal.Y),
					Size = UDim2.fromOffset(40, 40),
				})
				local delay = (i - 1) * 0.07
				task.delay(delay, function()
					fly:Play()
				end)
				task.delay(delay + 0.42, function()
					viewport.Visible = false
					Wardrobe.bump()
				end)
			end
			TweenService:Create(slot.holderScale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Scale = 0 }):Play()
		end
	end

	local function runOpen(box, items, total)
		clearOpen()
		for i, item in ipairs(items) do
			local slot = makeSlot(i, #items, item)
			slot.boxModel = boxForView(box)
			showModel(slot.viewport, slot.boxModel, 1.35)
			for _, part in ipairs(slot.boxModel:GetChildren()) do
				if part:IsA("BasePart") and part:GetAttribute("Lid") then
					table.insert(slot.lidParts, { part = part, base = part.CFrame })
				end
			end
			slot.pop.Scale = 0.35
			TweenService:Create(slot.pop, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
			slots[i] = slot
		end
		local slotSize = SLOT_SMALL
		if #items == 1 then
			slotSize = SLOT_BIG
		end
		banner.holder.Position = UDim2.new(0.5, 0, 0, STAGE_SIZE.Y / 2 - slotSize / 2 - 44)
		subBanner.holder.Position = UDim2.new(0.5, 0, 0, STAGE_SIZE.Y / 2 - slotSize / 2 + 4)
		stage.Position = UDim2.fromScale(0.5, STAGE_Y)
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
			for _, slot in ipairs(slots) do
				for _ = 1, 2 + k do
					local angle = math.rad(math.random(200, 340))
					local dir = Vector2.new(math.cos(angle), math.sin(angle))
					spawnParticle("chip", slot.center + dir * slot.size * 0.25, dir * math.random(200, 360), boxColor, math.random(7, 12), 0.7)
				end
			end
		end
		waitUntil(start + BURST_AT * total)

		-- wieka odlatują (boxy są już przekręcone, więc liczymy od tego położenia)
		for _, slot in ipairs(slots) do
			local sum = Vector3.new()
			for _, entry in ipairs(slot.lidParts) do
				entry.base = entry.part.CFrame
				sum = sum + entry.base.Position
			end
			if #slot.lidParts > 0 then
				slot.lidCenter = sum / #slot.lidParts
			end
		end
		phase = "lid"
		lidStart = os.clock()
		Sounds.play("Crack", { pitch = 0.75, volume = 1.2 })
		task.wait(LID_TIME)

		phase = "reveal"
		local hold = math.max(1.2, total * 0.55)
		if burst(box) then
			hold = hold + ULTRA_HOLD
		end
		task.wait(hold)
		exit()
		task.wait(0.6)
	end

	-- Cała animacja; State.busy blokuje w tym czasie klikanie i okna. Po błędzie stan i tak wraca.
	local function open(box, items, total)
		opening = true
		State.busy = true
		panelGui.Enabled = false
		promptGui.Enabled = false
		hud.setVisible(false)
		local ok, err = pcall(runOpen, box, items, total)
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
	local function buy(column)
		if requesting or opening or current == nil then
			return
		end
		local box = current.box
		local info = boxInfo(box)
		if not unlocked(box) then
			Sounds.play("NotEnough")
			hud.toast({ { icon = "Lock", size = 40 }, { text = string.format(TEXT.Locked, zoneName(info)), size = 26 } }, "BoxLocked")
			return
		end
		local view = State.view
		local passes = (view and view.Passes) or {}
		if column.count > 1 and not passes.TripleOpen then
			local id = Economy.Robux.Gamepasses.TripleOpen.Id
			if type(id) == "number" and id > 0 then
				pcall(function()
					MarketplaceService:PromptGamePassPurchase(player, id)
				end)
			else
				Sounds.play("NotEnough")
				hud.toast({ { text = TEXT.PassSoon, size = 26, colors = Theme.Gradients.Gold } }, "TripleOpen")
			end
			return
		end
		requesting = true
		local ok, result = pcall(function()
			return Net.func("BuyBox"):InvokeServer(box, column.count)
		end)
		requesting = false
		if not ok or type(result) ~= "table" then
			return
		end
		if result.Ok and type(result.Items) == "table" and #result.Items > 0 then
			dialog.hide()
			open(box, result.Items, result.OpenTime or Economy.OpenTimeSeconds)
		elseif result.Reason == "NotEnough" then
			hud.notEnough(column.button)
		elseif result.Reason == "Inventory" then
			Sounds.play("NotEnough")
			hud.toast({ { text = TEXT.Inventory, size = 26, colors = Theme.Gradients.Red } }, "ClothInventory")
		elseif result.Reason == "NoPass" then
			Sounds.play("NotEnough")
			hud.toast({ { text = TEXT.NoPass, size = 26, colors = Theme.Gradients.Red } }, "TripleOpen")
		end
	end

	for _, column in ipairs(columns) do
		column.button.Activated:Connect(function()
			buy(column)
		end)
	end

	promptButton.Activated:Connect(function()
		Sounds.play("Button")
		openDialog()
	end)
	-- klawisz E: otwiera okno kupna przy boxie, a drugie E je zamyka
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
