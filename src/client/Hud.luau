-- HUD gracza według projektu „Larp in Miami — UI”: L$ i pasek Bag na dole, kafelki SELL i UPGRADES
-- po lewej, podpowiedzi u góry, okno ulepszeń, komunikaty i efekty (kliknięcia, monety po sprzedaży).
-- Wszystkie liczby przychodzą z serwera (State). Teksty w grze są po angielsku (TEXT), wygląd w Ui/Theme,
-- klocki w Ui/Kit. Rozmiary w pikselach bazowych 1280×720, UIScale dopasowuje je do ekranu.

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
local Theme = require(script.Parent.Ui.Theme)
local Kit = require(script.Parent.Ui.Kit)
local Icons = require(script.Parent.Ui.Icons)

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
	PerClick = " LP per click",
	Capacity = " LP",
	PerClickChip = "+%s / click",
	HintFirstClick = "Click anywhere to earn LP!",
	HintBagFullFirst = "Your bag is full! Press SELL to get L$",
	HintBagFull = "Bag full! Press SELL",
	HintFirstUpgrade = "Buy an upgrade to earn more LP!",
	BagFull = "BAG FULL!",
	BagFullPop = "BAG FULL",
	SoldPrefix = "Sold %s LP for",
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

	local iconBox = Kit.new("Frame", {
		Position = UDim2.fromOffset(18, 20),
		Size = UDim2.fromOffset(120, 120),
		BackgroundColor3 = Theme.White,
		BorderSizePixel = 0,
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
		Position = UDim2.fromOffset(158, 12),
		Size = UDim2.fromOffset(250, 40),
		Text = opts.title,
		TextColor3 = Theme.Dark,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, { maxSize = 31, stroke = 0 })

	local chip = Kit.new("Frame", {
		Position = UDim2.fromOffset(158, 58),
		Size = UDim2.fromOffset(118, 30),
		BackgroundColor3 = Theme.Dark,
		BorderSizePixel = 0,
		Parent = card,
	})
	Kit.corner(chip, 15)
	c.level = Kit.text(chip, {
		Position = UDim2.fromOffset(8, 3),
		Size = UDim2.new(1, -16, 1, -6),
		Text = "",
	}, { maxSize = 20, stroke = 0 })

	c.effect = Kit.text(card, {
		Position = UDim2.fromOffset(158, 98),
		Size = UDim2.fromOffset(250, 32),
		Text = "",
		TextColor3 = Theme.Muted,
		TextXAlignment = Enum.TextXAlignment.Left,
		RichText = true,
	}, { maxSize = 23, stroke = 0 })

	local priceRow = Kit.new("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 12),
		Size = UDim2.fromOffset(210, 46),
		BackgroundTransparency = 1,
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
		size = Vector2.new(124, 58),
		text = TEXT.BuyMax,
		colors = Theme.Gradients.Yellow,
		anchor = Vector2.new(1, 1),
		position = UDim2.new(1, -16, 1, -12),
		textSize = 25,
	})
	c.buyOne = Kit.button(card, {
		name = "BuyOne",
		size = Vector2.new(124, 58),
		text = TEXT.BuyOne,
		colors = Theme.Gradients.Green,
		anchor = Vector2.new(1, 1),
		position = UDim2.new(1, -150, 1, -12),
		textSize = 25,
	})
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
		text = TEXT.Sell,
		colors = Theme.Gradients.Green,
		order = 1,
	})
	local sellPulse = makePulser(Kit.new("UIScale", { Parent = sellTile.holder }))
	local upgradesTile = Kit.tile(left, {
		name = "Upgrades",
		icon = "Upgrades",
		text = TEXT.Upgrades,
		colors = Theme.Gradients.Pink,
		order = 2,
		textSize = 21,
	})
	local upgradesPulse = makePulser(Kit.new("UIScale", { Parent = upgradesTile.holder }))
	local autoClickButton = Kit.button(left, {
		name = "AutoClick",
		size = Vector2.new(116, 40),
		text = TEXT.AutoClickOn,
		colors = Theme.Gradients.Gray,
		radius = 14,
		edge = 4,
		textSize = 16,
		textStroke = 2.5,
		order = 3,
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
		order = 4,
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
	local cashInner = Kit.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = cashGroup })
	local cashBounce = Kit.new("UIScale", { Parent = cashInner })
	local cashIcon = Icons.make("Cash", { Size = UDim2.fromOffset(74, 74), Parent = cashInner })
	local cashLabel = Kit.text(cashInner, {
		Position = UDim2.fromOffset(82, 8),
		Size = UDim2.fromOffset(236, 60),
		Text = TEXT.Loading,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, { maxSize = 52, stroke = 5, gradient = Theme.Gradients.Gold })

	----------------------------------------------------------------- Pasek Bag na dole pośrodku
	local bagGroup = Kit.new("Frame", {
		Name = "Bag",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -30),
		Size = UDim2.fromOffset(520, 56),
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
		Position = UDim2.fromOffset(40, 4),
		Size = UDim2.new(1, -80, 0, 42),
		Text = "",
		ZIndex = 6,
	}, { maxSize = 30, stroke = 3.5 })
	local bagIcon = Icons.make("Bag", {
		Position = UDim2.fromOffset(-48, -30),
		Size = UDim2.fromOffset(96, 96),
		ZIndex = 7,
		Parent = bagInner,
	})
	local perClick = Kit.pill(bagInner, {
		name = "PerClick",
		anchor = Vector2.new(1, 1),
		position = UDim2.new(1, -8, 0, -4),
		height = 34,
		edge = 0,
		border = 3,
		padLeft = 4,
		padRight = 12,
		gap = 4,
	})
	perClick.holder.ZIndex = 7

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
	local hint = Kit.pill(hintHolder, {
		anchor = Vector2.new(0.5, 0),
		position = UDim2.new(0.5, 0, 0, 0),
		height = 52,
		padLeft = 8,
		padRight = 24,
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
		Position = UDim2.new(0.5, 0, 1, -112),
		Size = UDim2.fromOffset(800, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = gui,
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
	local panel = Kit.panel(gui, { name = "UpgradesPanel", size = Vector2.new(680, 450), title = TEXT.UpgradesTitle, icon = "Upgrades" })
	registerScale(panel.holder)
	Kit.new("UIListLayout", { Padding = UDim.new(0, 18), SortOrder = Enum.SortOrder.LayoutOrder, Parent = panel.content })
	local clickCard = makeCard(panel.content, 1, { name = "Click", title = TEXT.ClickTitle, icon = "Click", colors = Theme.Gradients.CardPink })
	local bagCard = makeCard(panel.content, 2, { name = "Bag", title = TEXT.BagTitle, icon = "Bag", colors = Theme.Gradients.CardAqua })

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
	local toastCount = 0
	local function toast(items)
		toastCount = toastCount + 1
		local group = Kit.new("CanvasGroup", {
			LayoutOrder = toastCount,
			Size = UDim2.fromOffset(800, 58),
			BackgroundTransparency = 1,
			Parent = toasts,
		})
		Kit.pill(group, {
			anchor = Vector2.new(0.5, 0),
			position = UDim2.fromScale(0.5, 0),
			height = 50,
			padLeft = 8,
			padRight = 22,
			items = items,
		})
		local groups = {}
		for _, child in ipairs(toasts:GetChildren()) do
			if child:IsA("CanvasGroup") then
				table.insert(groups, child)
			end
		end
		if #groups > 3 then
			table.sort(groups, function(a, b)
				return a.LayoutOrder < b.LayoutOrder
			end)
			groups[1]:Destroy()
		end
		task.delay(2.4, function()
			if group.Parent == nil then
				return
			end
			TweenService:Create(group, TweenInfo.new(0.35), { GroupTransparency = 1 }):Play()
			task.wait(0.4)
			group:Destroy()
		end)
	end

	local function textToast(text, color)
		toast({ { text = text, size = 24, color = color or Theme.Dark } })
	end

	local activePops = 0
	local function pop(screenPosition, text, colors)
		if activePops >= 25 then
			return
		end
		activePops = activePops + 1
		local s = currentScale
		local label = Kit.new("TextLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(screenPosition.X + math.random(-16, 16), screenPosition.Y - 14),
			Size = UDim2.fromOffset(220 * s, 54 * s),
			Rotation = math.random(-10, 10),
			BackgroundTransparency = 1,
			Font = Theme.Font,
			Text = text,
			TextColor3 = Theme.White,
			TextScaled = true,
			Parent = popsGui,
		})
		local stroke = Kit.stroke(label, 4 * s)
		Kit.gradient(label, colors, 90)
		local grow = Kit.new("UIScale", { Scale = 0.5, Parent = label })
		TweenService:Create(grow, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		local info = TweenInfo.new(0.75, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(label, info, {
			Position = label.Position - UDim2.fromOffset(0, 80 * s),
			TextTransparency = 1,
		}):Play()
		TweenService:Create(stroke, info, { Transparency = 1 }):Play()
		task.delay(0.8, function()
			label:Destroy()
			activePops = activePops - 1
		end)
	end

	local function bounce(uiScale)
		uiScale.Scale = 1.12
		TweenService:Create(uiScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end

	-- Monety lecą z Bag do licznika L$.
	local function flyCoins(count)
		local from = center(bagIcon)
		local to = center(cashIcon)
		local s = currentScale
		for i = 1, count do
			local coin = Icons.make("Cash", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(from.X + math.random(-40, 40) * s, from.Y + math.random(-20, 10) * s),
				Size = UDim2.fromOffset(44 * s, 44 * s),
				Parent = popsGui,
			})
			local delay = (i - 1) * 0.05
			task.delay(delay, function()
				local tween = TweenService:Create(
					coin,
					TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
					{ Position = UDim2.fromOffset(to.X, to.Y), Size = UDim2.fromOffset(30 * s, 30 * s) }
				)
				tween.Completed:Connect(function()
					coin:Destroy()
					bounce(cashBounce)
				end)
				tween:Play()
			end)
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
		if view.Clicks == 0 and view.Bag <= 0 and view.Sells == 0 then
			setHint("first", { { icon = "Click", size = 44 }, { text = TEXT.HintFirstClick, size = 25 } })
		elseif view.BagFull then
			if view.Sells == 0 then
				setHint("fullFirst", { { icon = "Sell", size = 44 }, { text = TEXT.HintBagFullFirst, size = 25 } })
			else
				setHint("full", { { icon = "Sell", size = 44 }, { text = TEXT.HintBagFull, size = 25 } })
			end
		elseif view.Sells >= 1 and view.ClickLevel == 0 and view.NextClickCost ~= nil and view.Cash >= view.NextClickCost then
			setHint("upgrade", { { icon = "Upgrades", size = 44 }, { text = TEXT.HintFirstUpgrade, size = 25 } })
			pulseUpgrades = true
		else
			setHint(nil, nil)
		end
		upgradesPulse(pulseUpgrades)
		sellPulse(view.BagFull == true)
	end

	local function render(view)
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
			bagFillGradient.Color = ColorSequence.new(Theme.Gradients.BagFull[1], Theme.Gradients.BagFull[2])
			bagLabel.Text = TEXT.BagFull
			if not wasFull then
				shake(bagInner)
			end
		else
			bagFillGradient.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Theme.BagFill[1]),
				ColorSequenceKeypoint.new(0.6, Theme.BagFill[2]),
				ColorSequenceKeypoint.new(1, Theme.BagFill[3]),
			})
			bagLabel.Text = Format.number(view.Bag) .. " / " .. Format.number(capacity) .. " LP"
		end
		wasFull = view.BagFull == true

		local chipText = string.format(TEXT.PerClickChip, Format.small(view.LPPerClick))
		if chipText ~= perClickText then
			perClickText = chipText
			perClick.set({ { icon = "LP", size = 30 }, { text = chipText, size = 18 } })
		end

		-- Okno Upgrades
		local clickEffect = Format.small(view.LPPerClick)
		if view.NextLPPerClick ~= nil then
			clickEffect = clickEffect .. ' → <font color="' .. Theme.Good .. '">' .. Format.small(view.NextLPPerClick) .. "</font>"
		end
		renderCard(clickCard, "Click", view.ClickLevel, view.NextClickCost, view.Cash, clickEffect .. TEXT.PerClick)
		local bagEffect = Format.number(capacity)
		if view.NextBagCapacity ~= nil then
			bagEffect = bagEffect .. ' → <font color="' .. Theme.Good .. '">' .. Format.number(view.NextBagCapacity) .. "</font>"
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
			local name = TEXT.BagTitle
			local icon = "Bag"
			if kind == "Click" then
				name = TEXT.ClickTitle
				icon = "Click"
			end
			toast({ { icon = icon, size = 40 }, { text = string.format(TEXT.Upgraded, name, result.Level), size = 24, color = Theme.Dark } })
		elseif result.Reason == "NotEnough" then
			textToast(TEXT.NotEnough, Theme.BadgeRed)
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

	upgradesTile.Activated:Connect(function()
		panel.toggle()
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
			pop(center(cashIcon) + Vector2.new(60 * currentScale, -40 * currentScale), "+" .. Format.number(payload.Cash or 0), Theme.Gradients.Gold)
		else
			toast({
				{ icon = "Sell", size = 40 },
				{ text = string.format(TEXT.SoldPrefix, Format.number(payload.LP or 0)), size = 22, color = Theme.Dark },
				{ icon = "Cash", size = 32 },
				{ text = Format.number(payload.Cash or 0), size = 24, color = Theme.GoldText, stroke = 2.5 },
			})
			flyCoins(7)
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
				pop(screenPosition, TEXT.BagFullPop, Theme.Gradients.BagFull)
			end
			return
		end
		pop(screenPosition, "+" .. Format.small(view.LPPerClick), Theme.Gradients.LP)
	end
	return api
end

return Hud
