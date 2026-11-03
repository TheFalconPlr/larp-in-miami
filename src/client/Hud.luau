-- HUD gracza według projektu „Larp in Miami — UI”: L$ i pasek Bag na dole, kafelki SELL i UPGRADES
-- po lewej, podpowiedzi u góry, okno ulepszeń, komunikaty i efekty (kliknięcia, monety po sprzedaży).
-- Wszystkie liczby przychodzą z serwera (State). Teksty w grze są po angielsku (TEXT), wygląd w Ui/Theme,
-- klocki w Ui/Kit. Rozmiary w pikselach bazowych 1280×720, UIScale dopasowuje je do ekranu.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared.Config.Economy)
local Format = require(Shared.Format)
local Loop = require(Shared.Logic.Loop)
local Settings = require(Shared.Config.Settings)
local Net = require(Shared.Net)
local State = require(script.Parent.State)
local Theme = require(script.Parent.Ui.Theme)
local Kit = require(script.Parent.Ui.Kit)
local Icons = require(script.Parent.Ui.Icons)
local Sounds = require(script.Parent.Ui.Sounds)
local Pattern = require(script.Parent.Ui.Pattern)

local Hud = {}

local TEXT = {
	Loading = "...",
	Sell = "SELL",
	Upgrades = "UPGRADES",
	UpgradesTitle = "Upgrades!",
	ClickTitle = "Click Multiplier",
	BagTitle = "Bag",
	BuyOne = "Buy 1",
	BuyMax = "Max",
	BuyMaxCount = "Max ×%d",
	MaxLevel = "MAX",
	PerClick = " LP / click",
	Capacity = " LP",
	PerClickChip = "+%s / click",
	HintFirstClick = "Click anywhere to earn LP!",
	HintBagFullFirst = "Your bag is full! Press", -- potem zielone SELL i HintBagFullFirstEnd
	HintBagFullFirstEnd = "to get L$",
	HintBagFull = "Bag full! Press", -- potem zielone SELL
	HintFirstUpgrade = "Buy an upgrade to earn more LP!",
	HintZone = "Unlock", -- potem złota nazwa strefy 2 i HintZoneEnd
	HintZoneEnd = "at the gate!",
	BagFull = "BAG FULL!",
	BagFullPop = "BAG FULL",
	LarpPop = "Larp", -- napis wylatujący znad paska Bag przy każdym kliknięciu
	Sold = "Sold", -- „Sold 34.35K LP for 💵 34.35K”: liczba LP na zielono, kwota L$ na złoto
	SoldFor = "LP for",
	NotEnough = "Not enough L$",
	Upgraded = "%s → Lv %d",
	TestMode = "TEST MODE · /cmds",
	AutoClickOn = "AUTO CLICK",
	AutoSellOn = "AUTO SELL",
}

----------------------------------------------------------------- Skala UI
local scaleObjects = {}
local currentScale = 1

local function computeScale()
	local camera = Workspace.CurrentCamera
	local size = camera and camera.ViewportSize or Theme.BaseSize
	local s = math.min(size.X / Theme.BaseSize.X, size.Y / Theme.BaseSize.Y)
	return math.clamp(s, Theme.MinScale, Theme.MaxScale)
end

local function registerScale(guiObject)
	local uiScale = Kit.new("UIScale", { Scale = currentScale, Parent = guiObject })
	table.insert(scaleObjects, uiScale)
	return uiScale
end

local function updateScale()
	currentScale = computeScale()
	for _, uiScale in ipairs(scaleObjects) do
		uiScale.Scale = currentScale
	end
end

-- Pulsowanie (podpowiedź, co kliknąć).
local function makePulser(uiScale)
	local tween = nil
	return function(on)
		if on and tween == nil then
			tween = TweenService:Create(
				uiScale,
				TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
				{ Scale = 1.08 }
			)
			tween:Play()
		elseif not on and tween ~= nil then
			tween:Cancel()
			tween = nil
			uiScale.Scale = 1
		end
	end
end

local function center(guiObject)
	return guiObject.AbsolutePosition + guiObject.AbsoluteSize / 2
end

----------------------------------------------------------------- Karta ulepszenia
local function makeCard(parent, order, opts)
	local card = Kit.new("Frame", {
		Name = opts.name,
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, 168),
		BackgroundColor3 = Theme.White,
		BorderSizePixel = 0,
		Parent = parent,
	})
	Kit.corner(card, 24)
	Kit.stroke(card, 4, Enum.ApplyStrokeMode.Border)
	Kit.gradient(card, opts.colors, 90)
	-- wzór na karcie: białe, półprzezroczyste ikony inwestowania (pod resztą karty)
	Pattern.fill(card, Vector2.new(600, 168), {
		color = Theme.White,
		transparency = 0.86,
		scale = 0.6,
		stepX = 78,
		stepY = 62,
		radius = 24,
		zIndex = 1,
	})

	local iconBox = Kit.new("Frame", {
		Position = UDim2.fromOffset(18, 20),
		Size = UDim2.fromOffset(120, 120),
		BackgroundColor3 = Theme.White,
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = card,
	})
	Kit.corner(iconBox, 28)
	Kit.stroke(iconBox, 4, Enum.ApplyStrokeMode.Border)
	Icons.make(opts.icon, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.47),
		Size = UDim2.fromOffset(96, 96),
		Parent = iconBox,
	})

	local c = { frame = card }
	Kit.text(card, {
		Position = UDim2.fromOffset(156, 10),
		Size = UDim2.fromOffset(214, 42),
		Text = opts.title,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 2,
	}, { maxSize = 31, stroke = 3 })

	local chip = Kit.new("Frame", {
		Position = UDim2.fromOffset(156, 58),
		Size = UDim2.fromOffset(118, 30),
		BackgroundColor3 = Theme.Dark,
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = card,
	})
	Kit.corner(chip, 15)
	c.level = Kit.text(chip, {
		Position = UDim2.fromOffset(8, 3),
		Size = UDim2.new(1, -16, 1, -6),
		Text = "",
	}, { maxSize = 20, stroke = 0 })

	c.effect = Kit.text(card, {
		Position = UDim2.fromOffset(156, 98),
		Size = UDim2.fromOffset(178, 32),
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
		RichText = true,
		ZIndex = 2,
	}, { maxSize = 23, stroke = 2.5 })

	local priceRow = Kit.new("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 12),
		Size = UDim2.fromOffset(210, 46),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = card,
	})
	Kit.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = priceRow,
	})
	c.coin = Icons.make("Cash", { Size = UDim2.fromOffset(42, 42), LayoutOrder = 1, Parent = priceRow })
	c.price = Kit.new("TextLabel", {
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 46),
		BackgroundTransparency = 1,
		Font = Theme.Font,
		Text = "",
		TextSize = 34,
		TextColor3 = Theme.GoldText,
		LayoutOrder = 2,
		Parent = priceRow,
	})
	Kit.stroke(c.price, 3.5)

	c.buyMax = Kit.button(card, {
		name = "BuyMax",
		size = Vector2.new(116, 56),
		text = TEXT.BuyMax,
		colors = Theme.Gradients.Yellow,
		anchor = Vector2.new(1, 1),
		position = UDim2.new(1, -16, 1, -12),
		textSize = 24,
	})
	c.buyOne = Kit.button(card, {
		name = "BuyOne",
		size = Vector2.new(116, 56),
		text = TEXT.BuyOne,
		colors = Theme.Gradients.Green,
		anchor = Vector2.new(1, 1),
		position = UDim2.new(1, -142, 1, -12),
		textSize = 24,
	})
	c.buyMax.holder.ZIndex = 2
	c.buyOne.holder.ZIndex = 2
	return c
end

local function renderCard(c, kind, level, cost, cash, effectText)
	c.effect.Text = effectText
	if cost == nil then
		c.level.Text = "Lv " .. level
		c.coin.Visible = false
		c.price.Text = TEXT.MaxLevel
		c.buyOne.holder.Visible = false
		c.buyMax.holder.Visible = false
		return
	end
	c.level.Text = "Lv " .. level .. " → " .. (level + 1)
	c.coin.Visible = true
	c.price.Text = Format.number(cost)
	c.buyOne.holder.Visible = true
	c.buyMax.holder.Visible = true
	local count = Loop.affordable(kind, level, cash)
	if count >= 1 then
		c.buyOne.setColors(Theme.Gradients.Green)
		c.buyMax.setColors(Theme.Gradients.Yellow)
		c.buyMax.setText(string.format(TEXT.BuyMaxCount, count))
	else
		c.buyOne.setColors(Theme.Gradients.Gray)
		c.buyMax.setColors(Theme.Gradients.Gray)
		c.buyMax.setText(TEXT.BuyMax)
	end
end

----------------------------------------------------------------- Start
function Hud.start()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local api = {} -- to, co HUD daje innym modułom (wypełniane na końcu)

	local gui = Kit.new("ScreenGui", {
		Name = "LarpHUD",
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 5,
		Parent = playerGui,
	})
	local popsGui = Kit.new("ScreenGui", {
		Name = "LarpPops",
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 6,
		Parent = playerGui,
	})
	-- komunikaty mają własną warstwę nad oknami (Upgrades, Unlock), żeby nic ich nie zasłaniało
	local toastGui = Kit.new("ScreenGui", {
		Name = "LarpToasts",
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 7,
		Parent = playerGui,
	})
	local topGui = Kit.new("ScreenGui", {
		Name = "LarpTop",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 20,
		Parent = playerGui,
	})

	----------------------------------------------------------------- Kafelki po lewej
	local left = Kit.new("Frame", {
		Name = "Menu",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 22, 0.48, 0),
		Size = UDim2.fromOffset(104, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = gui,
	})
	registerScale(left)
	Kit.new("UIListLayout", {
		Padding = UDim.new(0, 28),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = left,
	})
	local sellTile = Kit.tile(left, {
		name = "Sell",
		icon = "Sell",
		iconSize = 92, -- banknot ma w obrazku pusty margines, więc trochę większy
		text = TEXT.Sell,
		colors = Theme.Gradients.Green,
		order = 1,
	})
	local sellPulse = makePulser(Kit.new("UIScale", { Parent = sellTile.body }))
	local upgradesTile = Kit.tile(left, {
		name = "Upgrades",
		icon = "Upgrades",
		text = TEXT.Upgrades,
		colors = Theme.Gradients.Pink,
		order = 2,
		textSize = 21,
	})
	local upgradesPulse = makePulser(Kit.new("UIScale", { Parent = upgradesTile.body }))
	local autoClickButton = Kit.button(left, {
		name = "AutoClick",
		size = Vector2.new(116, 40),
		text = TEXT.AutoClickOn,
		colors = Theme.Gradients.Gray,
		radius = 14,
		edge = 4,
		textSize = 16,
		textStroke = 2.5,
		order = 10,
	})
	autoClickButton.holder.Visible = false
	local autoSellButton = Kit.button(left, {
		name = "AutoSell",
		size = Vector2.new(116, 40),
		text = TEXT.AutoSellOn,
		colors = Theme.Gradients.Gray,
		radius = 14,
		edge = 4,
		textSize = 16,
		textStroke = 2.5,
		order = 11,
	})
	autoSellButton.holder.Visible = false

	----------------------------------------------------------------- L$ na dole po lewej
	local cashGroup = Kit.new("Frame", {
		Name = "Cash",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 24, 1, -28),
		Size = UDim2.fromOffset(320, 74),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	registerScale(cashGroup)
	-- środek po lewej na wysokości ikony: podskok licznika rośnie od ikony, a nie od rogu
	local cashInner = Kit.new("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = cashGroup,
	})
	local cashBounce = Kit.new("UIScale", { Parent = cashInner })
	local cashIcon = Icons.make("Cash", { Size = UDim2.fromOffset(74, 74), Parent = cashInner })
	local cashLabel = Kit.text(cashInner, {
		Position = UDim2.fromOffset(82, 8),
		Size = UDim2.fromOffset(236, 60),
		Text = TEXT.Loading,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, { maxSize = 52, stroke = 5, gradient = Theme.Gradients.Gold })

	----------------------------------------------------------------- Pasek Bag na dole pośrodku
	-- W pasku: zapełnienie Bag na środku wolnego miejsca i „+X / click” przy prawym końcu.
	local BAR_WIDTH = 520
	local BAR_TEXT_LEFT = 50 -- tu kończy się ikona Bag
	local PER_CLICK_SIZE = 20
	local PER_CLICK_RIGHT = 20 -- odstęp „+X / click” od prawego końca paska
	local bagGroup = Kit.new("Frame", {
		Name = "Bag",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -30),
		Size = UDim2.fromOffset(BAR_WIDTH, 56),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	registerScale(bagGroup)
	local bagInner = Kit.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = bagGroup })
	local bagEdge = Kit.new("Frame", {
		Position = UDim2.fromOffset(0, 6),
		Size = UDim2.new(1, 0, 0, 50),
		BackgroundColor3 = Theme.Outline,
		BorderSizePixel = 0,
		ZIndex = 1,
		Parent = bagInner,
	})
	Kit.corner(bagEdge, 25)
	local bagTrack = Kit.new("Frame", {
		Size = UDim2.new(1, 0, 0, 50),
		BackgroundColor3 = Theme.White,
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = bagInner,
	})
	Kit.corner(bagTrack, 25)
	Kit.stroke(bagTrack, 4, Enum.ApplyStrokeMode.Border)
	local bagFill = Kit.new("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Theme.White,
		BorderSizePixel = 0,
		ZIndex = 3,
		Parent = bagTrack,
	})
	Kit.corner(bagFill, 25)
	local bagFillGradient = Kit.gradient(bagFill, Theme.BagFill, 0)
	local bagGloss = Kit.new("Frame", {
		Position = UDim2.fromOffset(14, 6),
		Size = UDim2.new(1, -28, 0, 9),
		BackgroundColor3 = Theme.White,
		BackgroundTransparency = 0.5,
		BorderSizePixel = 0,
		ZIndex = 4,
		Parent = bagTrack,
	})
	Kit.corner(bagGloss, 5)
	local bagLabel = Kit.text(bagInner, {
		Position = UDim2.fromOffset(BAR_TEXT_LEFT, 4),
		Size = UDim2.fromOffset(BAR_WIDTH - 2 * BAR_TEXT_LEFT, 42),
		Text = "",
		ZIndex = 6,
	}, { maxSize = 30, stroke = 3.5 })
	local bagIcon = Icons.make("Bag", {
		Position = UDim2.fromOffset(-48, -30),
		Size = UDim2.fromOffset(96, 96),
		ZIndex = 7,
		Parent = bagInner,
	})
	local perClickLabel = Kit.new("TextLabel", {
		Name = "PerClick",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -PER_CLICK_RIGHT, 0, 25),
		Size = UDim2.fromOffset(0, 30),
		BackgroundTransparency = 1,
		Font = Theme.Font,
		Text = "",
		TextSize = PER_CLICK_SIZE,
		TextColor3 = Theme.White,
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 6,
		Parent = bagInner,
	})
	Kit.stroke(perClickLabel, 3)

	----------------------------------------------------------------- Podpowiedź u góry
	local hintHolder = Kit.new("Frame", {
		Name = "Hint",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 10),
		Size = UDim2.fromOffset(1000, 60),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = gui,
	})
	registerScale(hintHolder)
	local hint = Kit.line(hintHolder, {
		name = "HintLine",
		anchor = Vector2.new(0.5, 0),
		position = UDim2.new(0.5, 0, 0, 0),
		height = 56,
		gap = 8,
	})
	TweenService:Create(
		hint.holder,
		TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Position = UDim2.new(0.5, 0, 0, 4) }
	):Play()
	local hintKey = nil

	----------------------------------------------------------------- Komunikaty nad paskiem Bag
	local toasts = Kit.new("Frame", {
		Name = "Toasts",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -128),
		Size = UDim2.fromOffset(800, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = toastGui,
	})
	registerScale(toasts)
	Kit.new("UIListLayout", {
		Padding = UDim.new(0, 8),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = toasts,
	})

	----------------------------------------------------------------- Okno Upgrades
	local panel = Kit.panel(gui, {
		name = "UpgradesPanel",
		size = Vector2.new(680, 460),
		title = TEXT.UpgradesTitle,
		icon = "Upgrades",
		padding = 40,
		top = 64,
		bottom = 38,
	})
	registerScale(panel.holder)
	Kit.new("UIListLayout", { Padding = UDim.new(0, 22), SortOrder = Enum.SortOrder.LayoutOrder, Parent = panel.content })
	local clickCard = makeCard(panel.content, 1, { name = "Click", title = TEXT.ClickTitle, icon = "Click", colors = Theme.Gradients.CardPink })
	local bagCard = makeCard(panel.content, 2, { name = "Bag", title = TEXT.BagTitle, icon = "Bag", colors = Theme.Gradients.CardBlue })

	----------------------------------------------------------------- Tryb testowy i zaciemnienie
	local testHolder = Kit.new("Frame", {
		Name = "TestMode",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 12),
		Size = UDim2.fromOffset(400, 36),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = topGui,
	})
	registerScale(testHolder)
	Kit.pill(testHolder, {
		anchor = Vector2.new(0.5, 0),
		position = UDim2.fromScale(0.5, 0),
		height = 30,
		edge = 0,
		border = 3,
		color = Theme.TestYellow,
		padLeft = 14,
		padRight = 14,
		items = { { text = TEXT.TestMode, size = 16 } },
	})
	local fade = Kit.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 10,
		Parent = topGui,
	})

	----------------------------------------------------------------- Efekty
	-- Komunikat: sam tekst z obrysem i ikonami (bez tła), na własnej warstwie nad oknami.
	-- Wyskakuje, wisi chwilę i znika przez zmniejszenie (bez CanvasGroup, który przy UIScale ucinał
	-- komunikaty). Naraz najwyżej 3. Komunikat z kluczem (np. "NotEnough") się nie powtarza:
	-- drugi raz tylko odświeża ten, który już wisi.
	local toastCount = 0
	local toastByKey = {}

	local function hideToastLater(entry)
		entry.token = entry.token + 1
		local token = entry.token
		task.delay(2.4, function()
			if entry.token ~= token or entry.row.Parent == nil then
				return
			end
			TweenService:Create(entry.grow, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Scale = 0 }):Play()
			task.wait(0.22)
			if entry.token == token then
				entry.row:Destroy()
				if entry.key ~= nil and toastByKey[entry.key] == entry then
					toastByKey[entry.key] = nil
				end
			end
		end)
	end

	local function toast(items, key)
		local existing = key and toastByKey[key]
		if existing and existing.row.Parent ~= nil then
			existing.grow.Scale = 1.18
			TweenService:Create(existing.grow, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
			hideToastLater(existing)
			return
		end
		toastCount = toastCount + 1
		local row = Kit.new("Frame", {
			Name = "Toast",
			LayoutOrder = toastCount,
			Size = UDim2.fromOffset(800, 54),
			BackgroundTransparency = 1,
			Parent = toasts,
		})
		local line = Kit.line(row, {
			name = "ToastLine",
			anchor = Vector2.new(0.5, 0),
			position = UDim2.fromScale(0.5, 0),
			height = 50,
			items = items,
		})
		local grow = Kit.new("UIScale", { Scale = 0.6, Parent = line.holder })
		TweenService:Create(grow, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		local rows = {}
		for _, child in ipairs(toasts:GetChildren()) do
			if child:IsA("Frame") then
				table.insert(rows, child)
			end
		end
		if #rows > 3 then
			table.sort(rows, function(a, b)
				return a.LayoutOrder < b.LayoutOrder
			end)
			rows[1]:Destroy()
		end
		local entry = { row = row, grow = grow, token = 0, key = key }
		if key ~= nil then
			toastByKey[key] = entry
		end
		hideToastLater(entry)
	end

	local function textToast(text, colors, key)
		toast({ { text = text, size = 26, colors = colors } }, key)
	end

	-- Wyskakujący napis (np. „Larp” przy kursorze, „+X” nad paskiem Bag, „+L$” przy licznika L$).
	-- Każdy rodzaj ma swój limit, żeby napisy nie zasłoniły ekranu przy szybkim klikaniu.
	-- opts: kind (cursor, bar, other), size (Vector2, piksele bazowe), rise, driftX, duration,
	-- rotation (najwyżej tyle stopni w lewo albo w prawo), stroke.
	local POP_LIMIT = { cursor = 8, bar = 8, other = 12 }
	local activePops = { cursor = 0, bar = 0, other = 0 }
	local function pop(screenPosition, text, colors, opts)
		opts = opts or {}
		local kind = opts.kind or "other"
		if activePops[kind] >= POP_LIMIT[kind] then
			return
		end
		activePops[kind] = activePops[kind] + 1
		local s = currentScale
		local size = opts.size or Vector2.new(220, 54)
		local rotation = opts.rotation or 10
		local duration = opts.duration or 0.75
		local label = Kit.new("TextLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(screenPosition.X, screenPosition.Y),
			Size = UDim2.fromOffset(size.X * s, size.Y * s),
			Rotation = math.random(-rotation, rotation),
			BackgroundTransparency = 1,
			Font = Theme.Font,
			Text = text,
			TextColor3 = Theme.White,
			TextScaled = true,
			Parent = popsGui,
		})
		local stroke = Kit.stroke(label, (opts.stroke or 4) * s)
		Kit.gradient(label, colors, 90)
		local grow = Kit.new("UIScale", { Scale = 0.5, Parent = label })
		TweenService:Create(grow, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		local info = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(label, info, {
			Position = label.Position + UDim2.fromOffset((opts.driftX or 0) * s, -(opts.rise or 80) * s),
			TextTransparency = 1,
		}):Play()
		TweenService:Create(stroke, info, { Transparency = 1 }):Play()
		task.delay(duration + 0.05, function()
			label:Destroy()
			activePops[kind] = activePops[kind] - 1
		end)
	end

	local function bounce(uiScale)
		uiScale.Scale = 1.12
		TweenService:Create(uiScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end

	-- Sprzedaż: banknoty wyskakują z paska Bag (jak napis „Larp”), a potem lecą łukiem do licznika L$.
	-- Lot liczymy co klatkę (krzywa Béziera), a licznik podskakuje przy każdym banknocie.
	local flying = {}
	RunService.RenderStepped:Connect(function()
		if #flying == 0 then
			return
		end
		local now = os.clock()
		for i = #flying, 1, -1 do
			local f = flying[i]
			local t = (now - f.start) / f.duration
			if t >= 1 then
				f.icon:Destroy()
				table.remove(flying, i)
				bounce(cashBounce)
			elseif t >= 0 then
				local k = t * t -- przyspiesza w drodze do licznika
				local a = f.from:Lerp(f.control, k)
				local b = f.control:Lerp(f.to, k)
				local p = a:Lerp(b, k)
				local size = f.size0 + (f.size1 - f.size0) * k
				f.icon.Position = UDim2.fromOffset(p.X, p.Y)
				f.icon.Size = UDim2.fromOffset(size, size)
			end
		end
	end)

	local lastFly = 0
	local function flyCash(count)
		local now = os.clock()
		if now - lastFly < 0.35 then
			return
		end
		lastFly = now
		local s = currentScale
		local barPosition, barSize = bagTrack.AbsolutePosition, bagTrack.AbsoluteSize
		local to = center(cashIcon)
		for i = 1, count do
			local start = Vector2.new(barPosition.X + barSize.X * (0.1 + math.random() * 0.82), barPosition.Y + barSize.Y * 0.3)
			local risen = start + Vector2.new(math.random(-18, 18) * s, -math.random(46, 84) * s)
			local size = 46 * s
			local icon = Icons.make("SellCash", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(start.X, start.Y),
				Size = UDim2.fromOffset(0, 0),
				Rotation = math.random(-15, 15),
				ZIndex = 5,
				Parent = popsGui,
			})
			local delay = (i - 1) * 0.04
			task.delay(delay, function()
				TweenService:Create(icon, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
					Position = UDim2.fromOffset(risen.X, risen.Y),
					Size = UDim2.fromOffset(size, size),
				}):Play()
			end)
			-- łuk: punkt kontrolny wysoko nad drogą do licznika (jak strzałka na szkicu)
			table.insert(flying, {
				icon = icon,
				from = risen,
				control = Vector2.new((risen.X + to.X) / 2, math.min(risen.Y, to.Y) - 120 * s),
				to = to,
				start = now + delay + 0.34 + math.random() * 0.14,
				duration = 0.55 + math.random() * 0.15,
				size0 = size,
				size1 = 30 * s,
			})
		end
	end

	local function shake(frame)
		local steps = { -10, 9, -7, 5, -3, 0 }
		task.spawn(function()
			for _, x in ipairs(steps) do
				frame.Position = UDim2.fromOffset(x, 0)
				task.wait(0.035)
			end
		end)
	end

	local function fadeFlash()
		fade.BackgroundTransparency = 1
		fade.Visible = true
		TweenService:Create(fade, TweenInfo.new(0.15), { BackgroundTransparency = 0 }):Play()
		task.delay(0.35, function()
			TweenService:Create(fade, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
			task.wait(0.32)
			fade.Visible = false
		end)
	end

	----------------------------------------------------------------- L$ z animacją licznika
	local cashValue = Kit.new("NumberValue", { Value = 0 })
	local cashTween = nil
	local cashShown = false
	cashValue.Changed:Connect(function(value)
		cashLabel.Text = Format.number(value)
	end)
	local function setCash(target)
		if cashTween ~= nil then
			cashTween:Cancel()
			cashTween = nil
		end
		if not cashShown or math.abs(target - cashValue.Value) < 1 then
			cashShown = true
			cashValue.Value = target
			cashLabel.Text = Format.number(target)
			return
		end
		cashTween = TweenService:Create(cashValue, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Value = target })
		cashTween:Play()
	end

	----------------------------------------------------------------- Rysowanie stanu
	local lastView = nil
	local wasFull = false
	local bagBlink = nil -- tween migania pełnego Bag (false = brak, nil = jeszcze nie ustawiony kolor)
	local perClickText = nil

	local function setHint(key, items)
		if key == hintKey then
			return
		end
		hintKey = key
		hintHolder.Visible = key ~= nil
		if items ~= nil then
			hint.set(items)
		end
	end

	local function updateHint(view)
		local pulseUpgrades = false
		-- SELL w podpowiedziach jest zielone jak przycisk SELL
		local sellWord = { text = TEXT.Sell, size = 27, colors = Theme.Gradients.Green }
		if view.Clicks == 0 and view.Bag <= 0 and view.Sells == 0 then
			setHint("first", { { icon = "Click", size = 46 }, { text = TEXT.HintFirstClick, size = 27 } })
		elseif view.BagFull then
			if view.Sells == 0 then
				setHint("fullFirst", {
					{ icon = "Sell", size = 46 },
					{ text = TEXT.HintBagFullFirst, size = 27 },
					sellWord,
					{ text = TEXT.HintBagFullFirstEnd, size = 27 },
				})
			else
				setHint("full", { { icon = "Sell", size = 46 }, { text = TEXT.HintBagFull, size = 27 }, sellWord })
			end
		elseif view.Sells >= 1 and view.ClickLevel == 0 and view.NextClickCost ~= nil and view.Cash >= view.NextClickCost then
			setHint("upgrade", { { icon = "Upgrades", size = 46 }, { text = TEXT.HintFirstUpgrade, size = 27 } })
			pulseUpgrades = true
		elseif view.ZonesUnlocked == 1 and view.Sells >= 1 and view.Cash >= Economy.Zones[2].Cost then
			-- pierwsza strefa do kupienia: podpowiedź, gdzie ją kupić
			setHint("zone", {
				{ text = TEXT.HintZone, size = 27 },
				{ text = Economy.Zones[2].Name, size = 27, colors = Theme.Gradients.Gold },
				{ text = TEXT.HintZoneEnd, size = 27 },
			})
		else
			setHint(nil, nil)
		end
		upgradesPulse(pulseUpgrades)
		sellPulse(view.BagFull == true)
	end

	local function render(view)
		local firstRender = lastView == nil
		lastView = view
		setCash(view.Cash)

		-- Bag
		local capacity = view.BagCapacity or 0
		local fraction = 0
		if capacity > 0 then
			fraction = math.min(1, view.Bag / capacity)
		end
		TweenService:Create(bagFill, TweenInfo.new(0.12), { Size = UDim2.fromScale(fraction, 1) }):Play()
		if view.BagFull then
			bagLabel.Text = TEXT.BagFull
			if not wasFull then
				if not firstRender then
					Sounds.play("BagFull") -- Bag właśnie się zapełnił
				end
				bagFillGradient.Color = ColorSequence.new(Theme.Gradients.BagFull[1], Theme.Gradients.BagFull[2])
				shake(bagInner)
				-- pełny Bag miga: kolor paska przygasa i wraca
				bagBlink = TweenService:Create(
					bagFill,
					TweenInfo.new(0.45, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
					{ BackgroundColor3 = Color3.fromRGB(255, 170, 170) }
				)
				bagBlink:Play()
			end
		else
			if wasFull or bagBlink == nil then
				if bagBlink then
					bagBlink:Cancel()
				end
				bagBlink = false
				bagFill.BackgroundColor3 = Theme.White
				bagFillGradient.Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, Theme.BagFill[1]),
					ColorSequenceKeypoint.new(0.6, Theme.BagFill[2]),
					ColorSequenceKeypoint.new(1, Theme.BagFill[3]),
				})
			end
			bagLabel.Text = Format.number(view.Bag) .. " / " .. Format.number(capacity) .. " LP"
		end
		wasFull = view.BagFull == true

		local chipText = string.format(TEXT.PerClickChip, Format.small(view.LPPerClick))
		if chipText ~= perClickText then
			perClickText = chipText
			local width = Kit.measure(chipText, PER_CLICK_SIZE).X + 4
			perClickLabel.Text = chipText
			perClickLabel.Size = UDim2.fromOffset(width, 30)
			-- zapełnienie Bag dostaje miejsce od ikony Bag do „+X / click” (długie liczby się zmniejszą)
			local right = BAR_WIDTH - PER_CLICK_RIGHT - width - 10
			bagLabel.Size = UDim2.fromOffset(math.max(120, right - BAR_TEXT_LEFT), 42)
		end

		-- Okno Upgrades
		local clickEffect = Format.small(view.LPPerClick)
		if view.NextLPPerClick ~= nil then
			clickEffect = clickEffect .. ' → <font color="' .. Theme.NextValue .. '">' .. Format.small(view.NextLPPerClick) .. "</font>"
		end
		renderCard(clickCard, "Click", view.ClickLevel, view.NextClickCost, view.Cash, clickEffect .. TEXT.PerClick)
		local bagEffect = Format.number(capacity)
		if view.NextBagCapacity ~= nil then
			bagEffect = bagEffect .. ' → <font color="' .. Theme.NextValue .. '">' .. Format.number(view.NextBagCapacity) .. "</font>"
		end
		renderCard(bagCard, "Bag", view.BagLevel, view.NextBagCost, view.Cash, bagEffect .. TEXT.Capacity)

		-- Czerwone kropki: pełny Bag i ulepszenia, na które cię stać
		if view.BagFull then
			sellTile.badge.set("!")
		else
			sellTile.badge.set(nil)
		end
		local affordableKinds = 0
		if view.NextClickCost ~= nil and view.Cash >= view.NextClickCost then
			affordableKinds = affordableKinds + 1
		end
		if view.NextBagCost ~= nil and view.Cash >= view.NextBagCost then
			affordableKinds = affordableKinds + 1
		end
		if affordableKinds > 0 then
			upgradesTile.badge.set(tostring(affordableKinds))
		else
			upgradesTile.badge.set(nil)
		end

		-- Przełączniki gamepassów
		local passes = view.Passes or {}
		local settings = view.Settings or {}
		autoClickButton.holder.Visible = passes.AutoClick == true
		autoClickButton.setColors(settings.AutoClick and Theme.Gradients.Cyan or Theme.Gradients.Gray)
		autoSellButton.holder.Visible = passes.AutoSell == true
		autoSellButton.setColors(settings.AutoSell and Theme.Gradients.Cyan or Theme.Gradients.Gray)

		testHolder.Visible = view.IsAdmin == true
		updateHint(view)
	end

	----------------------------------------------------------------- Przyciski
	local buying = false
	local function buy(kind, mode, button)
		if buying then
			return
		end
		buying = true
		local ok, result = pcall(function()
			return Net.func("BuyUpgrade"):InvokeServer(kind, mode)
		end)
		buying = false
		if not ok or type(result) ~= "table" then
			return
		end
		if result.Ok then
			local name = TEXT.BagTitle
			local icon = "Bag"
			if kind == "Click" then
				name = TEXT.ClickTitle
				icon = "Click"
			end
			toast({ { icon = icon, size = 44 }, { text = string.format(TEXT.Upgraded, name, result.Level), size = 26 } })
		elseif result.Reason == "NotEnough" then
			api.notEnough(button)
		end
	end

	clickCard.buyOne.Activated:Connect(function()
		buy("Click", "One", clickCard.buyOne)
	end)
	clickCard.buyMax.Activated:Connect(function()
		buy("Click", "Max", clickCard.buyMax)
	end)
	bagCard.buyOne.Activated:Connect(function()
		buy("Bag", "One", bagCard.buyOne)
	end)
	bagCard.buyMax.Activated:Connect(function()
		buy("Bag", "Max", bagCard.buyMax)
	end)

	upgradesTile.Activated:Connect(function()
		if panel.isOpen() then
			panel.hide()
		else
			api.openWindow(panel)
		end
	end)

	local lastSellPress = -math.huge
	sellTile.Activated:Connect(function()
		local now = os.clock()
		if now - lastSellPress < Settings.Sell.TeleportCooldown then
			return
		end
		lastSellPress = now
		fadeFlash()
		task.delay(0.15, function()
			Net.event("TeleportToSell"):FireServer()
		end)
	end)

	autoClickButton.Activated:Connect(function()
		local settings = lastView and lastView.Settings
		if settings ~= nil then
			Net.event("SetSetting"):FireServer("AutoClick", not settings.AutoClick)
		end
	end)
	autoSellButton.Activated:Connect(function()
		local settings = lastView and lastView.Settings
		if settings ~= nil then
			Net.event("SetSetting"):FireServer("AutoSell", not settings.AutoSell)
		end
	end)

	----------------------------------------------------------------- Zdarzenia
	State.onChange(render)
	State.onNotify(function(payload)
		if payload.Kind ~= "Sold" then
			return
		end
		if payload.Auto then
			Sounds.play("Sell", { volume = 0.4 })
			pop(center(cashIcon) + Vector2.new(60 * currentScale, -54 * currentScale), "+" .. Format.number(payload.Cash or 0), Theme.Gradients.Gold)
			flyCash(4)
		else
			Sounds.play("Sell")
			toast({
				{ icon = "Sell", size = 44 },
				{ text = TEXT.Sold, size = 26 },
				{ text = Format.number(payload.LP or 0), size = 26, colors = Theme.Gradients.Money },
				{ text = TEXT.SoldFor, size = 26 },
				{ icon = "Cash", size = 38 },
				{ text = Format.number(payload.Cash or 0), size = 28, colors = Theme.Gradients.Gold },
			})
			flyCash(10)
		end
	end)

	local function watchCamera()
		local camera = Workspace.CurrentCamera
		if camera ~= nil then
			camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
		end
		updateScale()
	end
	Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchCamera)
	watchCamera()

	----------------------------------------------------------------- Dla ClickInput i innych modułów
	-- (api jest zadeklarowane wyżej, bo używa go też buy)
	api.gui = gui
	api.registerScale = registerScale
	api.toast = toast
	-- Chowa cały HUD (np. na czas otwierania jajka, jak w Pet Simulator 99).
	function api.setVisible(visible)
		gui.Enabled = visible
	end
	-- Inne okna (np. odblokowanie strefy) zamykają okno Upgrades, żeby się nie nakładały.
	function api.closeUpgrades()
		panel.hide()
	end

	-- Okna. Główne (Upgrades, Pets) otwiera kafelek, a okienka przy obiektach (bramka, auto, jajko)
	-- otwierają się same, gdy podejdziesz. Otwarte główne okno ma pierwszeństwo: okienka przy
	-- obiektach chowają się i nie otwierają, dopóki go nie zamkniesz (windowOpen).
	local mainWindows = { panel }
	local popups = {}
	function api.addWindow(window)
		table.insert(mainWindows, window)
	end
	function api.addPopup(popup)
		table.insert(popups, popup)
	end
	function api.windowOpen()
		for _, window in ipairs(mainWindows) do
			if window.isOpen() then
				return true
			end
		end
		return false
	end
	-- Otwiera główne okno i chowa wszystkie inne okna.
	function api.openWindow(window)
		for _, other in ipairs(mainWindows) do
			if other ~= window and other.isOpen() then
				other.hide()
			end
		end
		for _, popup in ipairs(popups) do
			if popup.isOpen() then
				popup.hide()
			end
		end
		window.open()
	end

	-- Kafelek w menu po lewej (pod SELL i UPGRADES), np. PETS. opts jak Kit.tile; order od 3.
	function api.addTile(opts)
		return Kit.tile(left, opts)
	end

	-- Brak L$ na zakup: dźwięk, czerwony komunikat (jeden, nie kilka naraz) i potrząśnięty przycisk.
	function api.notEnough(button)
		Sounds.play("NotEnough")
		textToast(TEXT.NotEnough, Theme.Gradients.Red, "NotEnough")
		if button ~= nil then
			Kit.shake(button.holder)
		end
	end

	-- Klik: biały napis „+X” przy kursorze, a „Larp” wylatuje znad paska Bag (widać, że LP wpadają
	-- do Bag). Z pełnym Bag jest napis „BAG FULL” i dźwięk pełnego Bag, razem, najwyżej co 0,5 s.
	local lastFullPop = 0
	function api.clickFeedback(screenPosition, view)
		if view.BagFull then
			local now = os.clock()
			if now - lastFullPop > 0.5 then
				lastFullPop = now
				Sounds.play("BagFullClick")
				pop(screenPosition + Vector2.new(math.random(-16, 16), -14), TEXT.BagFullPop, Theme.Gradients.BagFull)
			end
			return
		end
		Sounds.play("Click")
		local s = currentScale
		pop(screenPosition + Vector2.new(math.random(-10, 10), -12 * s), "+" .. Format.small(view.LPPerClick), Theme.Gradients.ClickPop, {
			kind = "cursor",
			size = Vector2.new(120, 36),
			rise = 50,
			duration = 0.55,
			rotation = 8,
			stroke = 3,
		})
		local barPosition = bagTrack.AbsolutePosition
		local barSize = bagTrack.AbsoluteSize
		local x = barPosition.X + barSize.X * (0.12 + math.random() * 0.8)
		pop(Vector2.new(x, barPosition.Y - 4 * s), TEXT.LarpPop, Theme.Gradients.ClickPop, {
			kind = "bar",
			size = Vector2.new(120, 34),
			rise = 46,
			driftX = math.random(-24, 24),
			duration = 0.7,
			rotation = 6,
			stroke = 3,
		})
	end
	return api
end

return Hud
