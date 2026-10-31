-- HUD gracza: L$, pasek Bag, przyciski SELL i UPGRADES, okno ulepszeń, podpowiedzi dla nowego gracza,
-- komunikaty i efekty kliknięć. Teksty w grze są po angielsku (TEXT), kolory i czcionka w STYLE.
-- Wszystkie liczby przychodzą z serwera (State). UI jest najpierw pod telefon, a na dużych
-- ekranach powiększa się (UIScale).

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared.Format)
local Loop = require(Shared.Logic.Loop)
local Settings = require(Shared.Config.Settings)
local Net = require(Shared.Net)
local State = require(script.Parent.State)

local Hud = {}

local STYLE = {
	Font = Enum.Font.FredokaOne,
	Panel = Color3.fromRGB(27, 21, 48),
	PanelTransparency = 0.12,
	Card = Color3.fromRGB(44, 35, 76),
	Text = Color3.fromRGB(255, 255, 255),
	Muted = Color3.fromRGB(196, 186, 228),
	Cash = Color3.fromRGB(255, 210, 74),
	Pink = Color3.fromRGB(255, 61, 139),
	Cyan = Color3.fromRGB(46, 230, 214),
	Green = Color3.fromRGB(39, 196, 106),
	Gray = Color3.fromRGB(92, 86, 112),
	Red = Color3.fromRGB(240, 70, 80),
	Stroke = Color3.fromRGB(12, 8, 24),
}

local TEXT = {
	Loading = "Loading...",
	Sell = "SELL",
	Upgrades = "UPGRADES",
	Close = "X",
	ClickTitle = "CLICK MULTIPLIER",
	BagTitle = "BAG",
	BuyOne = "BUY 1",
	BuyMax = "BUY MAX",
	MaxLevel = "MAX",
	PerClick = " LP / click",
	Capacity = " LP",
	HintFirstClick = "Click anywhere to earn LP!",
	HintBagFullFirst = "Your bag is full! Press SELL to turn LP into L$",
	HintBagFull = "Bag full! Press SELL",
	HintFirstUpgrade = "Buy an upgrade to earn more LP per click!",
	BagFullPop = "BAG FULL",
	Sold = "Sold %s LP for L$ %s",
	NotEnough = "Not enough L$",
	Upgraded = "%s → Lv %d",
	AutoSellTag = "  ·  AUTO SELL",
	TestMode = "TEST MODE · /cmds",
	AutoClickOn = "AUTO CLICK: ON",
	AutoClickOff = "AUTO CLICK: OFF",
	AutoSellOn = "AUTO SELL: ON",
	AutoSellOff = "AUTO SELL: OFF",
}

----------------------------------------------------------------- Pomocnicze
local function new(className, props)
	local inst = Instance.new(className)
	local parent = props.Parent
	props.Parent = nil
	for key, value in pairs(props) do
		inst[key] = value
	end
	if parent ~= nil then
		inst.Parent = parent
	end
	return inst
end

local function addCorner(parent, radius)
	return new("UICorner", { CornerRadius = UDim.new(0, radius), Parent = parent })
end

local function addStroke(parent, thickness, color, mode)
	return new("UIStroke", {
		Thickness = thickness,
		Color = color,
		ApplyStrokeMode = mode or Enum.ApplyStrokeMode.Contextual,
		Parent = parent,
	})
end

local function addTextLimit(parent, maxSize)
	return new("UITextSizeConstraint", { MaxTextSize = maxSize, MinTextSize = 8, Parent = parent })
end

local function makeLabel(parent, props, maxSize)
	props.BackgroundTransparency = 1
	props.Font = props.Font or STYLE.Font
	props.TextColor3 = props.TextColor3 or STYLE.Text
	props.TextScaled = true
	props.Parent = parent
	local label = new("TextLabel", props)
	addTextLimit(label, maxSize or 24)
	addStroke(label, 1.5, STYLE.Stroke)
	return label
end

local function makeButton(parent, props, maxSize)
	props.Font = STYLE.Font
	props.TextColor3 = STYLE.Text
	props.TextScaled = true
	props.AutoButtonColor = true
	props.BorderSizePixel = 0
	props.Parent = parent
	local button = new("TextButton", props)
	addCorner(button, 14)
	addTextLimit(button, maxSize or 26)
	addStroke(button, 2, STYLE.Stroke)
	new("UIPadding", {
		PaddingLeft = UDim.new(0, 6),
		PaddingRight = UDim.new(0, 6),
		PaddingTop = UDim.new(0, 4),
		PaddingBottom = UDim.new(0, 4),
		Parent = button,
	})
	return button
end

local function setEnabled(button, enabled)
	button.BackgroundColor3 = enabled and STYLE.Green or STYLE.Gray
	button.AutoButtonColor = enabled
end

-- Pulsowanie przycisku (podpowiedź, co kliknąć).
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

----------------------------------------------------------------- Skala UI
local scaleObjects = {}
local currentScale = 1

local function computeScale()
	local camera = Workspace.CurrentCamera
	local size = camera and camera.ViewportSize or Vector2.new(1280, 720)
	local s = math.min(size.X / 900, size.Y / 560)
	return math.clamp(s, 0.75, 1.6)
end

local function registerScale(guiObject)
	local uiScale = new("UIScale", { Scale = currentScale, Parent = guiObject })
	table.insert(scaleObjects, uiScale)
	return uiScale
end

local function updateScale()
	currentScale = computeScale()
	for _, uiScale in ipairs(scaleObjects) do
		uiScale.Scale = currentScale
	end
end

----------------------------------------------------------------- Karta ulepszenia
local function makeCard(parent, order, title, color)
	local card = new("Frame", {
		Name = title,
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, 108),
		BackgroundColor3 = STYLE.Card,
		BorderSizePixel = 0,
		Parent = parent,
	})
	addCorner(card, 14)
	local c = { frame = card }
	c.title = makeLabel(card, {
		Position = UDim2.fromOffset(14, 8),
		Size = UDim2.new(0.46, 0, 0, 28),
		Text = title,
		TextColor3 = color,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, 24)
	c.level = makeLabel(card, {
		Position = UDim2.fromOffset(14, 40),
		Size = UDim2.new(0.46, 0, 0, 24),
		Text = "",
		TextColor3 = STYLE.Muted,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, 18)
	c.effect = makeLabel(card, {
		Position = UDim2.fromOffset(14, 68),
		Size = UDim2.new(0.46, 0, 0, 28),
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
	}, 20)
	c.price = makeLabel(card, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 8),
		Size = UDim2.new(0.45, 0, 0, 32),
		Text = "",
		TextColor3 = STYLE.Cash,
		TextXAlignment = Enum.TextXAlignment.Right,
	}, 26)
	c.buyMax = makeButton(card, {
		Name = "BuyMax",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -12, 1, -10),
		Size = UDim2.fromOffset(104, 44),
		BackgroundColor3 = STYLE.Gray,
		Text = TEXT.BuyMax,
	}, 20)
	c.buyOne = makeButton(card, {
		Name = "BuyOne",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -124, 1, -10),
		Size = UDim2.fromOffset(96, 44),
		BackgroundColor3 = STYLE.Gray,
		Text = TEXT.BuyOne,
	}, 20)
	return c
end

local function renderCard(c, kind, level, cost, cash, effectText)
	c.effect.Text = effectText
	if cost == nil then
		c.level.Text = "Lv " .. level .. " · " .. TEXT.MaxLevel
		c.price.Text = TEXT.MaxLevel
		setEnabled(c.buyOne, false)
		setEnabled(c.buyMax, false)
		c.buyMax.Text = TEXT.BuyMax
		return
	end
	c.level.Text = "Lv " .. level .. " → " .. (level + 1)
	c.price.Text = "L$ " .. Format.number(cost)
	local count = Loop.affordable(kind, level, cash)
	setEnabled(c.buyOne, count >= 1)
	setEnabled(c.buyMax, count >= 1)
	if count >= 1 then
		c.buyMax.Text = "MAX (+" .. count .. ")"
	else
		c.buyMax.Text = TEXT.BuyMax
	end
end

----------------------------------------------------------------- Start
function Hud.start()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local gui = new("ScreenGui", {
		Name = "LarpHUD",
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 5,
		Parent = playerGui,
	})
	local popsGui = new("ScreenGui", {
		Name = "LarpPops",
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		DisplayOrder = 4,
		Parent = playerGui,
	})
	local fadeGui = new("ScreenGui", {
		Name = "LarpFade",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 20,
		Parent = playerGui,
	})

	----------------------------------------------------------------- Góra: L$, Bag, podpowiedź
	local top = new("Frame", {
		Name = "Top",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 6),
		Size = UDim2.fromOffset(360, 118),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	registerScale(top)

	local cashPill = new("Frame", {
		Name = "Cash",
		Size = UDim2.new(1, 0, 0, 46),
		BackgroundColor3 = STYLE.Panel,
		BackgroundTransparency = STYLE.PanelTransparency,
		BorderSizePixel = 0,
		Parent = top,
	})
	addCorner(cashPill, 23)
	local cashBounce = new("UIScale", { Parent = cashPill })
	local cashLabel = makeLabel(cashPill, {
		Position = UDim2.fromOffset(12, 4),
		Size = UDim2.new(1, -24, 1, -8),
		Text = TEXT.Loading,
		TextColor3 = STYLE.Cash,
	}, 34)

	local bagBar = new("Frame", {
		Name = "Bag",
		Position = UDim2.fromOffset(0, 52),
		Size = UDim2.new(1, 0, 0, 30),
		BackgroundColor3 = STYLE.Panel,
		BackgroundTransparency = STYLE.PanelTransparency,
		BorderSizePixel = 0,
		Parent = top,
	})
	addCorner(bagBar, 15)
	local bagFill = new("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = STYLE.Pink,
		BorderSizePixel = 0,
		Parent = bagBar,
	})
	addCorner(bagFill, 15)
	local bagLabel = makeLabel(bagBar, {
		Position = UDim2.fromOffset(8, 3),
		Size = UDim2.new(1, -16, 1, -6),
		Text = "",
		ZIndex = 2,
	}, 20)

	local hint = makeLabel(top, {
		Name = "Hint",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 88),
		Size = UDim2.new(1.5, 0, 0, 26),
		Text = "",
		TextColor3 = STYLE.Cyan,
		Visible = false,
	}, 22)
	TweenService:Create(
		hint,
		TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ TextTransparency = 0.35 }
	):Play()

	----------------------------------------------------------------- Lewa strona: przyciski
	local left = new("Frame", {
		Name = "Left",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 10, 0.42, 0),
		Size = UDim2.fromOffset(140, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = gui,
	})
	registerScale(left)
	new("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = left })

	local sellButton = makeButton(left, {
		Name = "Sell",
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, 56),
		BackgroundColor3 = STYLE.Green,
		Text = TEXT.Sell,
	}, 28)
	local sellPulse = makePulser(new("UIScale", { Parent = sellButton }))

	local upgradesButton = makeButton(left, {
		Name = "Upgrades",
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, 56),
		BackgroundColor3 = STYLE.Pink,
		Text = TEXT.Upgrades,
	}, 24)
	local upgradesPulse = makePulser(new("UIScale", { Parent = upgradesButton }))

	local autoClickButton = makeButton(left, {
		Name = "AutoClick",
		LayoutOrder = 3,
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundColor3 = STYLE.Gray,
		Text = TEXT.AutoClickOn,
		Visible = false,
	}, 18)
	local autoSellButton = makeButton(left, {
		Name = "AutoSell",
		LayoutOrder = 4,
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundColor3 = STYLE.Gray,
		Text = TEXT.AutoSellOn,
		Visible = false,
	}, 18)

	----------------------------------------------------------------- Okno ulepszeń
	local panel = new("Frame", {
		Name = "UpgradesPanel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromOffset(480, 310),
		BackgroundColor3 = STYLE.Panel,
		BackgroundTransparency = 0.05,
		BorderSizePixel = 0,
		Active = true,
		Visible = false,
		Parent = gui,
	})
	registerScale(panel)
	addCorner(panel, 18)
	addStroke(panel, 3, STYLE.Pink, Enum.ApplyStrokeMode.Border)
	makeLabel(panel, {
		Position = UDim2.fromOffset(60, 10),
		Size = UDim2.new(1, -120, 0, 40),
		Text = TEXT.Upgrades,
	}, 30)
	local closeButton = makeButton(panel, {
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 10),
		Size = UDim2.fromOffset(40, 40),
		BackgroundColor3 = STYLE.Red,
		Text = TEXT.Close,
	}, 24)
	local cards = new("Frame", {
		Name = "Cards",
		Position = UDim2.fromOffset(16, 62),
		Size = UDim2.new(1, -32, 1, -78),
		BackgroundTransparency = 1,
		Parent = panel,
	})
	new("UIListLayout", { Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder, Parent = cards })
	local clickCard = makeCard(cards, 1, TEXT.ClickTitle, STYLE.Pink)
	local bagCard = makeCard(cards, 2, TEXT.BagTitle, STYLE.Cyan)

	----------------------------------------------------------------- Komunikaty i tryb testowy
	local toasts = new("Frame", {
		Name = "Toasts",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -100),
		Size = UDim2.fromOffset(440, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = gui,
	})
	registerScale(toasts)
	new("UIListLayout", {
		Padding = UDim.new(0, 6),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = toasts,
	})

	local badge = makeLabel(gui, {
		Name = "TestMode",
		Position = UDim2.fromOffset(10, 8),
		Size = UDim2.fromOffset(200, 24),
		Text = TEXT.TestMode,
		TextColor3 = STYLE.Cash,
		TextXAlignment = Enum.TextXAlignment.Left,
		Visible = false,
	}, 18)

	local fade = new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Visible = false,
		Parent = fadeGui,
	})

	----------------------------------------------------------------- Efekty
	local toastCount = 0
	local function toast(text, color)
		toastCount = toastCount + 1
		local frame = new("Frame", {
			LayoutOrder = toastCount,
			Size = UDim2.new(1, 0, 0, 36),
			BackgroundColor3 = STYLE.Panel,
			BackgroundTransparency = STYLE.PanelTransparency,
			BorderSizePixel = 0,
			Parent = toasts,
		})
		addCorner(frame, 12)
		local label = makeLabel(frame, {
			Position = UDim2.fromOffset(8, 4),
			Size = UDim2.new(1, -16, 1, -8),
			Text = text,
			TextColor3 = color or STYLE.Text,
		}, 20)
		local frames = {}
		for _, child in ipairs(toasts:GetChildren()) do
			if child:IsA("Frame") then
				table.insert(frames, child)
			end
		end
		if #frames > 3 then
			table.sort(frames, function(a, b)
				return a.LayoutOrder < b.LayoutOrder
			end)
			frames[1]:Destroy()
		end
		task.delay(2.5, function()
			if frame.Parent == nil then
				return
			end
			local info = TweenInfo.new(0.4)
			TweenService:Create(frame, info, { BackgroundTransparency = 1 }):Play()
			TweenService:Create(label, info, { TextTransparency = 1 }):Play()
			local stroke = label:FindFirstChildOfClass("UIStroke")
			if stroke ~= nil then
				TweenService:Create(stroke, info, { Transparency = 1 }):Play()
			end
			task.wait(0.45)
			frame:Destroy()
		end)
	end

	local activePops = 0
	local function pop(screenPosition, text, color)
		if activePops >= 25 then
			return
		end
		activePops = activePops + 1
		local s = currentScale
		local label = new("TextLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(screenPosition.X + math.random(-18, 18), screenPosition.Y - 10),
			Size = UDim2.fromOffset(140 * s, 40 * s),
			BackgroundTransparency = 1,
			Font = STYLE.Font,
			Text = text,
			TextColor3 = color,
			TextScaled = true,
			Parent = popsGui,
		})
		local stroke = addStroke(label, 2, STYLE.Stroke)
		local info = TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(label, info, {
			Position = label.Position - UDim2.fromOffset(0, 70 * s),
			TextTransparency = 1,
		}):Play()
		TweenService:Create(stroke, info, { Transparency = 1 }):Play()
		task.delay(0.75, function()
			label:Destroy()
			activePops = activePops - 1
		end)
	end

	local function bounce(uiScale)
		uiScale.Scale = 1.12
		TweenService:Create(uiScale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
			:Play()
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

	----------------------------------------------------------------- Rysowanie stanu
	local lastView = nil

	local function updateHint(view)
		local text = nil
		local pulseUpgrades = false
		if view.Clicks == 0 and view.Bag <= 0 and view.Sells == 0 then
			text = TEXT.HintFirstClick
		elseif view.BagFull then
			if view.Sells == 0 then
				text = TEXT.HintBagFullFirst
			else
				text = TEXT.HintBagFull
			end
		elseif view.Sells >= 1 and view.ClickLevel == 0 and view.NextClickCost ~= nil and view.Cash >= view.NextClickCost then
			text = TEXT.HintFirstUpgrade
			pulseUpgrades = true
		end
		hint.Visible = text ~= nil
		if text ~= nil then
			hint.Text = text
		end
		upgradesPulse(pulseUpgrades)
		sellPulse(view.BagFull == true)
	end

	local function render(view)
		lastView = view
		cashLabel.Text = "L$ " .. Format.number(view.Cash)

		local capacity = view.BagCapacity or 0
		local fraction = 0
		if capacity > 0 then
			fraction = math.min(1, view.Bag / capacity)
		end
		TweenService:Create(bagFill, TweenInfo.new(0.12), { Size = UDim2.fromScale(fraction, 1) }):Play()
		bagFill.BackgroundColor3 = view.BagFull and STYLE.Red or STYLE.Pink
		local bagText = Format.number(view.Bag) .. " / " .. Format.number(capacity) .. " LP"
		if view.AutoSell then
			bagText = bagText .. TEXT.AutoSellTag
		end
		bagLabel.Text = bagText

		local clickEffect = Format.small(view.LPPerClick)
		if view.NextLPPerClick ~= nil then
			clickEffect = clickEffect .. " → " .. Format.small(view.NextLPPerClick)
		end
		renderCard(clickCard, "Click", view.ClickLevel, view.NextClickCost, view.Cash, clickEffect .. TEXT.PerClick)

		local bagEffect = Format.number(capacity)
		if view.NextBagCapacity ~= nil then
			bagEffect = bagEffect .. " → " .. Format.number(view.NextBagCapacity)
		end
		renderCard(bagCard, "Bag", view.BagLevel, view.NextBagCost, view.Cash, bagEffect .. TEXT.Capacity)

		local passes = view.Passes or {}
		local settings = view.Settings or {}
		autoClickButton.Visible = passes.AutoClick == true
		autoClickButton.Text = settings.AutoClick and TEXT.AutoClickOn or TEXT.AutoClickOff
		autoClickButton.BackgroundColor3 = settings.AutoClick and STYLE.Cyan or STYLE.Gray
		autoSellButton.Visible = passes.AutoSell == true
		autoSellButton.Text = settings.AutoSell and TEXT.AutoSellOn or TEXT.AutoSellOff
		autoSellButton.BackgroundColor3 = settings.AutoSell and STYLE.Cyan or STYLE.Gray

		badge.Visible = view.IsAdmin == true
		updateHint(view)
	end

	----------------------------------------------------------------- Przyciski
	local buying = false
	local function buy(kind, mode)
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
			local name = (kind == "Click") and "Click Multiplier" or "Bag"
			toast(string.format(TEXT.Upgraded, name, result.Level), STYLE.Green)
		elseif result.Reason == "NotEnough" then
			toast(TEXT.NotEnough, STYLE.Red)
		end
	end

	clickCard.buyOne.Activated:Connect(function()
		buy("Click", "One")
	end)
	clickCard.buyMax.Activated:Connect(function()
		buy("Click", "Max")
	end)
	bagCard.buyOne.Activated:Connect(function()
		buy("Bag", "One")
	end)
	bagCard.buyMax.Activated:Connect(function()
		buy("Bag", "Max")
	end)

	upgradesButton.Activated:Connect(function()
		panel.Visible = not panel.Visible
	end)
	closeButton.Activated:Connect(function()
		panel.Visible = false
	end)

	local lastSellPress = -math.huge
	sellButton.Activated:Connect(function()
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
			local center = cashPill.AbsolutePosition + cashPill.AbsoluteSize / 2
			pop(Vector2.new(center.X, center.Y + 30), "+L$ " .. Format.number(payload.Cash or 0), STYLE.Cash)
		else
			toast(string.format(TEXT.Sold, Format.number(payload.LP or 0), Format.number(payload.Cash or 0)), STYLE.Cash)
			bounce(cashBounce)
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

	----------------------------------------------------------------- Dla ClickInput
	local api = {}
	local lastFullPop = 0
	function api.clickFeedback(screenPosition, view)
		if view.BagFull then
			local now = os.clock()
			if now - lastFullPop > 0.5 then
				lastFullPop = now
				pop(screenPosition, TEXT.BagFullPop, STYLE.Red)
			end
			return
		end
		pop(screenPosition, "+" .. Format.small(view.LPPerClick), STYLE.Pink)
	end
	return api
end

return Hud
