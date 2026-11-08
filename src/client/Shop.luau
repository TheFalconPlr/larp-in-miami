-- Sklep za Robuxy (Etap 10) po stronie gracza:
--   • po prawej stronie ekranu duży kafelek SHOP (koszyk; przy kliknięciu wylatują z niego małe
--     koszyki), TELEPORT i Starter Pack z zegarem do końca oferty,
--   • w prawym dolnym rogu małe ikonki aktywnych boostów (2x LP, AUTO SELL), bez tła; po najechaniu
--     (na telefonie po dotknięciu) nazwa i pozostały czas,
--   • okno SHOP (ShopWindow.luau) i okno TELEPORT (odblokowane strefy, gamepass Teleport),
--   • ceny z MarketplaceService:GetProductInfoAsync (ceny regionalne gracza); zanim przyjdą, z Economy,
--   • po potwierdzonym zakupie podziękowanie (ShopThanks.luau), po końcu boosta komunikat.
-- Zakup zawsze sprawdza i robi serwer (ShopService, Net „Buy”); tu jest tylko wygląd. Pety z premium
-- jajek pokazuje animacja w Eggs.luau.

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared.Config.Economy)
local Format = require(Shared.Format)
local Net = require(Shared.Net)
local Robux = require(Shared.Robux)
local State = require(script.Parent.State)
local Theme = require(script.Parent.Ui.Theme)
local Kit = require(script.Parent.Ui.Kit)
local Icons = require(script.Parent.Ui.Icons)
local Sounds = require(script.Parent.Ui.Sounds)
local Fx = require(script.Parent.Ui.Fx)
local ShopArt = require(script.Parent.Ui.ShopArt)
local Catalog = require(script.Parent.ShopCatalog)
local ShopWindow = require(script.Parent.ShopWindow)
local ShopThanks = require(script.Parent.ShopThanks)

local Shop = {}

local ROBUX = "\238\128\130" -- znak Robux (U+E002)
local TEXT = Catalog.TEXT
local Style = Enum.EasingStyle
local Dir = Enum.EasingDirection

-- Kafelki po prawej i napisy boostów (piksele bazowe).
local SIDE = {
	ShopTile = Vector2.new(118, 118),
	ShopIcon = 136,
	TeleportIcon = 92,
	StarterButton = Vector2.new(176, 64),
	BoostIcon = 60, -- ikonki aktywnych boostów w prawym dolnym rogu
	BoostIconTouch = 50, -- …na telefonie (obok przycisku skoku)
	TipSize = 28, -- napis z nazwą i czasem po najechaniu na ikonkę
	TipSizeTouch = 24,
	TipTouchTime = 2.5, -- na telefonie napis po dotknięciu znika po tylu sekundach
	ShortScreen = 560, -- niższy ekran (telefon poziomo): kolumna po prawej od góry, ciaśniej
	ColumnGap = 22, -- odstęp kafelków w kolumnie (napisy SHOP i TELEPORT wystają ok. 13 px w dół)
	-- Góra kolumny: nad nią lista zadań dziennych (QuestTracker: 10 + 236) i koszyk, który wystaje
	-- nad kafelek SHOP (24 px, a przy unoszeniu 30). Gdy kolumna się nie mieści (np. z przyciskiem
	-- Starter Pack na niskim ekranie), stoi tuż nad rzędem boostów, a lista zadań jest trochę mniejsza.
	ColumnTop = 282,
	ColumnAboveBoosts = 78, -- najniżej: dół kolumny tyle nad dolną krawędzią rzędu boostów (ikonka 60 + miejsce)
	BurstCount = 14, -- małe koszyki wylatujące dookoła kafelka SHOP
	IdleEvery = 5,
}
Shop.ShortScreen = SIDE.ShortScreen -- QuestTracker: na niskim ekranie lista stoi na lewo od kolumny

----------------------------------------------------------------- Ceny
local prices = {} -- ["Pass:TwoXLP"] = cena z GetProductInfoAsync
local priceListeners = {} -- ["Pass:TwoXLP"] = { fn, ... }

local function priceKey(kind, key)
	return kind .. ":" .. key
end

-- Cena w Robuxach: regionalna z GetProductInfoAsync, a zanim przyjdzie (albo bez ID) z Economy.
function Shop.price(kind, key)
	return prices[priceKey(kind, key)] or Robux.basePrice(kind, key) or 0
end

function Shop.priceText(kind, key)
	return ROBUX .. " " .. Format.number(Shop.price(kind, key))
end

-- fn(cena) od razu i po każdej zmianie ceny (gdy przyjdzie cena regionalna).
function Shop.onPrice(kind, key, fn)
	local k = priceKey(kind, key)
	priceListeners[k] = priceListeners[k] or {}
	table.insert(priceListeners[k], fn)
	fn(Shop.price(kind, key))
end

local function fetchPrice(kind, key)
	local id = Robux.id(kind, key)
	if id == nil then
		return
	end
	local infoType = Enum.InfoType.Product
	if kind == "Pass" then
		infoType = Enum.InfoType.GamePass
	end
	task.spawn(function()
		local ok, info = pcall(MarketplaceService.GetProductInfoAsync, MarketplaceService, id, infoType)
		if ok and type(info) == "table" and type(info.PriceInRobux) == "number" then
			local k = priceKey(kind, key)
			prices[k] = info.PriceInRobux
			for _, fn in ipairs(priceListeners[k] or {}) do
				task.spawn(fn, info.PriceInRobux)
			end
		end
	end)
end

----------------------------------------------------------------- Zakup
local hudRef = nil

local function toast(text, colors, key, icon)
	if hudRef == nil then
		return
	end
	local items = {}
	if icon ~= nil then
		table.insert(items, { icon = icon, size = 40 })
	end
	table.insert(items, { text = text, size = 26, colors = colors })
	hudRef.toast(items, key)
end

-- Prosi serwer o okno zakupu. kind: "Pass" albo "Product"; opts.Zone = strefa premium jajka.
-- Zwraca odpowiedź serwera ({ Ok, Reason, Test }) albo nil. Podziękowanie pokazuje dopiero
-- potwierdzenie zakupu z serwera (Notify), nie ta odpowiedź.
function Shop.buy(kind, key, opts, button)
	local ok, result = pcall(function()
		return Net.func("Buy"):InvokeServer(kind, key, opts)
	end)
	if not ok or type(result) ~= "table" then
		return nil
	end
	if result.Ok then
		return result
	end
	local reason = TEXT.Reasons[result.Reason]
	if reason ~= nil then
		Sounds.play("NotEnough")
		local colors = Theme.Gradients.Red
		if result.Reason == "Soon" then
			colors = Theme.Gradients.Gold
		end
		toast(reason, colors, "Buy" .. tostring(result.Reason))
		if button ~= nil then
			Kit.shake(button.body or button.holder)
		end
	end
	return result
end

local function timeText(seconds)
	seconds = math.max(0, math.floor(seconds))
	local h = math.floor(seconds / 3600)
	local m = math.floor((seconds % 3600) / 60)
	local s = seconds % 60
	if h > 0 then
		return string.format("%d:%02d:%02d", h, m, s)
	end
	return string.format("%d:%02d", m, s)
end
Shop.timeText = timeText

-- Skala HUD (jak Hud.computeScale) do efektów liczonych w pikselach ekranu.
local function hudScale()
	local camera = Workspace.CurrentCamera
	local view = (camera and camera.ViewportSize) or Theme.BaseSize
	return math.clamp(math.min(view.X / Theme.BaseSize.X, view.Y / Theme.BaseSize.Y), Theme.MinScale, Theme.MaxScale)
end

----------------------------------------------------------------- Kafelki po prawej
-- Duży kafelek SHOP: koszyk wystaje nad kafelek, połysk i podskok co kilka sekund.
local function makeShopTile(root)
	local tile = Kit.button(root, {
		name = "Shop",
		size = SIDE.ShopTile,
		colors = Theme.Gradients.Premium,
		radius = 30,
		edge = 7,
		order = 1,
		sound = false, -- otwarcie sklepu ma własne dźwięki (ShopWindow)
	})
	local icon = Icons.make("Shop", {
		Name = "ShopIcon",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, 44),
		Size = UDim2.fromOffset(SIDE.ShopIcon, SIDE.ShopIcon),
		Rotation = -6,
		ZIndex = 6,
		Parent = tile.face,
	})
	Kit.text(tile.face, {
		Name = "Label",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, 20),
		Size = UDim2.new(1, 30, 0, 36),
		Text = TEXT.Shop,
		ZIndex = 7,
	}, { maxSize = 30, stroke = 4 })
	tile.icon = icon
	tile.iconScale = Fx.scaleOf(icon)
	tile.shine = Fx.shine(tile.face, { inset = 4, width = 60, strength = 0.8, zIndex = 5 })
	Fx.button(tile, 1.08)
	-- unoszenie koszyka bez końca
	Fx.loop(icon, 1.3, { Position = UDim2.new(0.5, 0, 0, 38) }, Style.Sine)
	return tile
end

local function makeTeleportTile(root)
	local tile = Kit.tile(root, {
		name = "Teleport",
		icon = "Teleport",
		iconSize = SIDE.TeleportIcon,
		text = TEXT.Teleport,
		colors = Theme.Gradients.Portal,
		order = 2,
		textSize = 21,
	})
	Fx.button(tile, 1.08)
	local icon = tile.face:FindFirstChild("TeleportIcon")
	if icon ~= nil then
		icon.Rotation = -8
		Fx.loop(icon, 1.6, { Rotation = 8 }, Style.Sine)
	end
	tile.lock = Icons.make("Lock", {
		Name = "PassLock",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -8, 0, 8),
		Size = UDim2.fromOffset(30, 30),
		Rotation = 10,
		ZIndex = 8,
		Parent = tile.face,
	})
	return tile
end

-- Starter Pack: prezent, napis i zegar; lekko się unosi i co chwilę błyszczy.
local function makeStarterButton(root)
	local button = Kit.button(root, {
		name = "StarterPack",
		size = SIDE.StarterButton,
		colors = Theme.Gradients.Starter,
		radius = 20,
		order = 3,
		sound = false, -- otwiera sklep, który ma własne dźwięki
	})
	Icons.make("Gift", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, 22, 0.5, -2),
		Size = UDim2.fromOffset(58, 58),
		Rotation = -12,
		ZIndex = 6,
		Parent = button.face,
	})
	Kit.text(button.face, {
		Name = "Title",
		Position = UDim2.fromOffset(46, 4),
		Size = UDim2.new(1, -52, 0, 28),
		Text = TEXT.Starter,
		ZIndex = 5,
	}, { maxSize = 22, stroke = 3 })
	button.timer = Kit.text(button.face, {
		Name = "Timer",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 46, 1, -4),
		Size = UDim2.new(1, -52, 0, 26),
		Text = "",
		ZIndex = 5,
	}, { maxSize = 22, stroke = 3, gradient = Theme.Gradients.Gold })
	button.shine = Fx.shine(button.face, { inset = 3, width = 56, strength = 0.85, zIndex = 4 })
	Fx.button(button, 1.06)
	Fx.loop(button.body, 0.9, { Position = UDim2.new(0.5, 0, 0.5, -5) }, Style.Sine)
	button.holder.Visible = false
	return button
end

----------------------------------------------------------------- Boosty w prawym dolnym rogu
-- Same małe ikonki aktywnych boostów (2x LP i Auto Sell z zegarkiem, jak na kartach w sklepie), bez tła.
-- Po najechaniu myszą (na telefonie po dotknięciu) nad ikonką pokazuje się nazwa i pozostały czas: sam
-- napis z obrysem. Czas ma miejsce o stałej szerokości (cyfry zamienione na najszerszą), więc zmiana cyfr
-- co sekundę niczego nie przesuwa. Ostatnie 30 s: ikonka pulsuje, a czas jest czerwony.
local BOOST_ICONS = {
	LP = { art = "Boost2xLP", text = "BoostLP", colors = "LP" },
	AutoSell = { art = "BoostAutoSell", text = "BoostAutoSell", colors = "Money" },
}

local wideDigit = { size = 0, char = "0" }
local function slotText(text, size)
	if wideDigit.size ~= size then
		wideDigit.size = size
		local best = -1
		for d = 0, 9 do
			local w = Kit.measure(tostring(d), size).X
			if w > best then
				best = w
				wideDigit.char = tostring(d)
			end
		end
	end
	return (string.gsub(text, "%d", wideDigit.char))
end

local function layer(parent, name)
	return Kit.new("Frame", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = parent,
	})
end

local function boostIcon(parent, kind, order)
	local info = BOOST_ICONS[kind]
	local holder = Kit.new("Frame", {
		Name = kind,
		LayoutOrder = order,
		Size = UDim2.fromOffset(SIDE.BoostIcon, SIDE.BoostIcon),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = parent,
	})
	-- warstwy z osobnymi UIScale: body (wyskoczenie, podskok), hover (najechanie), warn (pulsowanie)
	local body = layer(holder, "Body")
	local hover = layer(body, "Hover")
	local warn = layer(hover, "Warn")
	local art = ShopArt.make(info.art, SIDE.BoostIcon, warn, { Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1) })
	local hit = Kit.new("TextButton", {
		Name = "Hit",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		ZIndex = 8,
		Parent = holder,
	})
	-- napis nad ikonką, przy jej prawym brzegu (rośnie w lewo, więc nie wychodzi za ekran)
	local tip = Kit.new("Frame", {
		Name = "Tip",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, 6, 0, -2),
		Size = UDim2.fromOffset(200, 36),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 9,
		Parent = holder,
	})
	local label = Kit.text(tip, {
		Name = "Name",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromOffset(120, 36),
		Text = TEXT[info.text],
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 9,
	}, { maxSize = SIDE.TipSize, stroke = 4, gradient = Theme.Gradients[info.colors] })
	local time = Kit.text(tip, {
		Name = "Time",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 130, 0.5, 0),
		Size = UDim2.fromOffset(100, 36),
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 9,
	}, { maxSize = SIDE.TipSize, stroke = 4, gradient = Theme.Gradients.Gold })
	local icon = {
		holder = holder,
		art = art,
		time = time,
		tip = tip,
		scale = Fx.scaleOf(body),
		hoverScale = Fx.scaleOf(hover),
		warnScale = Fx.scaleOf(warn),
		tipScale = Fx.scaleOf(tip),
		gradient = time:FindFirstChildOfClass("UIGradient"),
		animBin = Fx.bin(),
		size = SIDE.TipSize,
		slot = "",
		last = 0,
		on = false,
		tipOn = false,
		warnOn = false,
		touchToken = 0,
	}
	-- szerokości napisu: nazwa z treści, czas ze wzoru cyfr (size = nowy rozmiar napisu)
	function icon.layoutTip(size)
		local slot = slotText(time.Text, size or icon.size)
		if size == nil and slot == icon.slot then
			return
		end
		icon.size = size or icon.size
		icon.slot = slot
		local h = math.floor(icon.size * 1.25)
		for _, text in ipairs({ time, label }) do
			local limit = text:FindFirstChildOfClass("UITextSizeConstraint")
			if limit ~= nil then
				limit.MaxTextSize = icon.size
			end
		end
		local lw = Kit.measure(label.Text, icon.size).X + 8
		local gap = math.floor(icon.size * 0.35)
		local tw = Kit.measure(slot, icon.size).X + 8
		label.Size = UDim2.fromOffset(lw, h)
		time.Position = UDim2.new(0, lw + gap, 0.5, 0)
		time.Size = UDim2.fromOffset(tw, h)
		tip.Size = UDim2.fromOffset(lw + gap + tw, h)
	end
	-- napis z nazwą i czasem: wyskakuje z ikonki, a ikonka rośnie i rusza się jak na karcie w sklepie
	function icon.showTip(on)
		if on == icon.tipOn then
			return
		end
		icon.tipOn = on
		if on then
			tip.Visible = true
			Fx.pop(icon.tipScale, 0.6, 0.2)
			Fx.tween(icon.hoverScale, 0.18, { Scale = 1.15 }, Style.Back, Dir.Out)
			art.play(icon.animBin)
		else
			icon.animBin.clean()
			Fx.tween(icon.hoverScale, 0.15, { Scale = 1 }, Style.Quad, Dir.Out)
			Fx.tween(icon.tipScale, 0.1, { Scale = 0.6 }, Style.Quad, Dir.In)
			Fx.after(0.1, function()
				if not icon.tipOn then
					tip.Visible = false
				end
			end)
		end
	end
	-- ostatnie pół minuty: ikonka pulsuje, czas w napisie na czerwono
	function icon.setWarn(on)
		if on == icon.warnOn then
			return
		end
		icon.warnOn = on
		if icon.warnTween ~= nil then
			icon.warnTween:Cancel()
			icon.warnTween = nil
		end
		icon.warnScale.Scale = 1
		if on then
			icon.warnTween = Fx.loop(icon.warnScale, 0.35, { Scale = 1.18 }, Style.Sine)
		end
		if icon.gradient ~= nil then
			local colors = Theme.Gradients.Gold
			if on then
				colors = Theme.Gradients.Red
			end
			icon.gradient.Color = ColorSequence.new(colors[1], colors[2])
		end
	end
	hit.MouseEnter:Connect(function()
		icon.showTip(true)
	end)
	hit.MouseLeave:Connect(function()
		icon.showTip(false)
	end)
	-- dotyk (bez myszy nie ma najechania): napis na chwilę, drugie dotknięcie go chowa
	hit.Activated:Connect(function(input)
		if input ~= nil and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		icon.touchToken = icon.touchToken + 1
		local token = icon.touchToken
		if icon.tipOn then
			icon.showTip(false)
			return
		end
		icon.showTip(true)
		task.delay(SIDE.TipTouchTime, function()
			if icon.touchToken == token then
				icon.showTip(false)
			end
		end)
	end)
	return icon
end

----------------------------------------------------------------- Start
function Shop.start(hud)
	hudRef = hud
	ShopThanks.start(hud)

	------------------------------------------------------------- Kafelki po prawej
	local root = Kit.new("Frame", {
		Name = "ShopRoot",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -24, 0.46, 0),
		Size = UDim2.fromOffset(184, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = hud.gui,
	})
	hud.registerScale(root)
	hud.shopColumn = root -- lista zadań na ekranie (QuestTracker) stoi nad kolumną
	local rootList = Kit.new("UIListLayout", {
		Padding = UDim.new(0, SIDE.ColumnGap),
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = root,
	})
	-- Kolumna stoi niżej niż kiedyś, bo nad nią są zadania dzienne (QuestTracker): góra na ColumnTop,
	-- ale najniżej tuż nad prawym dolnym rogiem (rząd ikonek boostów, a na ekranie dotykowym przycisk
	-- skoku). Niski ekran (telefon poziomo): kolumna od góry i ciaśniej, a zadania na lewo od niej.
	local function placeColumn()
		local camera = Workspace.CurrentCamera
		local viewY = (camera and camera.ViewportSize.Y) or Theme.BaseSize.Y
		if viewY < SIDE.ShortScreen then
			root.AnchorPoint = Vector2.new(1, 0)
			root.Position = UDim2.new(1, -18, 0, 4)
			rootList.Padding = UDim.new(0, 14)
			return
		end
		rootList.Padding = UDim.new(0, SIDE.ColumnGap)
		local k = hudScale()
		local height = hud.gui.AbsoluteSize.Y
		local bottom = 14 + SIDE.ColumnAboveBoosts * k -- rząd boostów: 14 px od dołu, ikonki w skali UI
		local playerGui = Players.LocalPlayer:FindFirstChild("PlayerGui")
		local touchGui = playerGui and playerGui:FindFirstChild("TouchGui")
		local jump = touchGui and touchGui:FindFirstChild("JumpButton", true)
		if touchGui ~= nil and touchGui:IsA("ScreenGui") and touchGui.Enabled and jump ~= nil and jump:IsA("GuiObject") and jump.Visible and height > 0 then
			bottom = math.max(bottom, height - jump.AbsolutePosition.Y + 12 * k)
		end
		local top = SIDE.ColumnTop * k
		if height > 0 and top + root.AbsoluteSize.Y > height - bottom then
			root.AnchorPoint = Vector2.new(1, 1)
			root.Position = UDim2.new(1, -24, 1, -math.floor(bottom + 0.5))
		else
			root.AnchorPoint = Vector2.new(1, 0)
			root.Position = UDim2.new(1, -24, 0, math.floor(top + 0.5))
		end
	end
	Shop.placeColumn = placeColumn
	placeColumn()
	if Workspace.CurrentCamera ~= nil then
		Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(placeColumn)
	end
	hud.gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(placeColumn)
	-- przycisk Starter Pack znika po 72 h: kolumna jest niższa
	root:GetPropertyChangedSignal("AbsoluteSize"):Connect(placeColumn)
	local shopTile = makeShopTile(root)
	local tpTile = makeTeleportTile(root)
	local starterButton = makeStarterButton(root)

	-- boosty: ikonki w prawym dolnym rogu (na telefonie na lewo od przycisku skoku), w jednym rzędzie
	local timers = Kit.new("Frame", {
		Name = "BoostTimers",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -22, 1, -14),
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		BackgroundTransparency = 1,
		ZIndex = 6,
		Parent = hud.gui,
	})
	hud.registerScale(timers)
	Kit.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 10),
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = timers,
	})
	local boostIcons = {
		LP = boostIcon(timers, "LP", 1),
		AutoSell = boostIcon(timers, "AutoSell", 2),
	}
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	-- Na telefonie w prawym dolnym rogu jest przycisk skoku: ikonki stoją wtedy tuż na lewo od niego
	-- (w tym samym rogu, mniejsze), bo nad nim jest kolumna SHOP / TELEPORT / Starter Pack.
	local iconSize = SIDE.BoostIcon
	local function placeTimers()
		local right, bottom, size, tipSize = 22, 14, SIDE.BoostIcon, SIDE.TipSize
		local touchGui = playerGui:FindFirstChild("TouchGui")
		local jump = touchGui and touchGui:FindFirstChild("JumpButton", true)
		if touchGui ~= nil and touchGui:IsA("ScreenGui") and touchGui.Enabled and jump ~= nil and jump:IsA("GuiObject") and jump.Visible then
			local camera = Workspace.CurrentCamera
			local view = (camera and camera.ViewportSize) or Theme.BaseSize
			right = math.max(right, view.X - jump.AbsolutePosition.X + 10)
			bottom = 10
			size = SIDE.BoostIconTouch
			tipSize = SIDE.TipSizeTouch
		end
		timers.Position = UDim2.new(1, -right, 1, -bottom)
		if size ~= iconSize then
			iconSize = size
			for _, icon in pairs(boostIcons) do
				icon.holder.Size = UDim2.fromOffset(size, size)
				icon.layoutTip(tipSize)
			end
		end
	end

	-- czasy liczymy u siebie od ostatniego stanu z serwera (serwer odlicza tylko w grze)
	local boostEnds = { LP = 0, AutoSell = 0 }
	local starterEnds = 0
	local function readTimers(view)
		local now = os.clock()
		local boosts = view.Boosts or {}
		boostEnds.LP = now + (boosts.LP or 0)
		boostEnds.AutoSell = now + (boosts.AutoSell or 0)
		starterEnds = now + (view.StarterLeft or 0)
	end

	------------------------------------------------------------- Okno SHOP
	local shopWindow, win = ShopWindow.create(hud, Shop)
	hud.addWindow(shopWindow)

	-- reklama za nagrodę: tylko gdy Roblox ma reklamę dla gracza (albo tester bez ID produktu)
	local adAvailable = false
	local adWatching = false
	local function renderAd()
		local view = State.view
		if view == nil then
			return
		end
		local tester = view.IsAdmin == true and Robux.productId(Robux.AdReward) == nil
		local reward = Robux.Products[Robux.AdReward]
		win.setAd({
			show = view.AdsReady == true and (adAvailable or tester),
			left = view.AdsLeft or 0,
			max = Economy.Bonuses.RewardedVideoDailyMax,
			minutes = (reward and reward.Minutes) or 0,
			tester = tester,
			waiting = adWatching,
		})
	end
	-- GetAdAvailabilityNowAsync tuż przed pokazaniem przycisku (jedna dostępność = jedna reklama)
	local function checkAd()
		local ok, available = pcall(function()
			local result = game:GetService("AdService"):GetAdAvailabilityNowAsync(Enum.AdFormat.RewardedVideo)
			return result.AdAvailabilityResult == Enum.AdAvailabilityResult.IsAvailable
		end)
		adAvailable = ok and available == true
		renderAd()
	end
	win.ad.button.Activated:Connect(function()
		if win.ad.used or adWatching then
			return
		end
		Sounds.play("Button")
		adWatching = true
		renderAd()
		local ok, result = pcall(function()
			return Net.func("WatchAd"):InvokeServer()
		end)
		adWatching = false
		if ok and type(result) == "table" and not result.Ok then
			local reason = TEXT.Reasons[result.Reason]
			if reason ~= nil then
				toast(reason, Theme.Gradients.Red, "AdReason")
			end
		end
		-- jedna dostępność = jedna reklama: sprawdzamy znowu
		task.spawn(checkAd)
	end)

	------------------------------------------------------------- Okno TELEPORT
	local tpPanel = Kit.panel(hud.gui, {
		name = "TeleportPanel",
		size = Vector2.new(560, 520),
		title = TEXT.TeleportTitle,
		icon = "Teleport",
		padding = 30,
		top = 58,
		bottom = 24,
	})
	hud.registerScale(tpPanel.holder)
	hud.addWindow(tpPanel)
	local zoneButtons = {}
	for n, zone in ipairs(Economy.Zones) do
		local b = Kit.button(tpPanel.content, {
			name = "TeleportZone" .. n,
			size = Vector2.new(500, 58),
			text = string.format(TEXT.ZoneButton, n, zone.Name),
			colors = Theme.Gradients.Portal,
			textSize = 28,
			anchor = Vector2.new(0.5, 0),
			position = UDim2.new(0.5, 0, 0, (n - 1) * 70),
			sound = false,
		})
		Fx.button(b, 1.03)
		b.lock = Icons.make("Lock", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(1, -24, 0.5, -2),
			Size = UDim2.fromOffset(34, 34),
			ZIndex = 6,
			Parent = b.face,
		})
		zoneButtons[n] = b
	end
	local tpNote = Kit.line(tpPanel.content, {
		anchor = Vector2.new(0.5, 0),
		position = UDim2.new(0.5, 0, 0, #Economy.Zones * 70 + 2),
		height = 34,
		items = { { icon = "Teleport", size = 30 }, { text = TEXT.TeleportNote, size = 22 } },
	})
	local tpBuy = Kit.button(tpPanel.content, {
		name = "BuyTeleport",
		size = Vector2.new(300, 56),
		text = TEXT.TeleportBuy,
		colors = Theme.Gradients.Green,
		textSize = 28,
		anchor = Vector2.new(0.5, 1),
		position = UDim2.new(0.5, 0, 1, 0),
		sound = false,
	})
	Fx.button(tpBuy)

	local function renderTeleport()
		local view = State.view
		if view == nil then
			return
		end
		local owns = (view.Passes or {}).Teleport == true
		local unlocked = view.ZonesUnlocked or 1
		for n, b in ipairs(zoneButtons) do
			local open = n <= unlocked
			b.lock.Visible = not open
			if open and owns then
				b.setColors(Theme.Gradients.Portal)
			else
				b.setColors(Theme.Gradients.Gray)
			end
		end
		tpNote.holder.Visible = not owns
		tpBuy.holder.Visible = not owns
		tpTile.lock.Visible = not owns
	end

	for n, b in ipairs(zoneButtons) do
		b.Activated:Connect(function()
			local view = State.view
			if view == nil then
				return
			end
			if (view.Passes or {}).Teleport ~= true then
				Sounds.play("Button")
				Shop.buy("Pass", "Teleport", nil, tpBuy)
				return
			end
			if n > (view.ZonesUnlocked or 1) then
				Sounds.play("NotEnough")
				Kit.shake(b.body)
				toast(TEXT.Reasons.Locked, Theme.Gradients.Red, "TpLocked")
				return
			end
			Sounds.play("Button")
			tpPanel.hide()
			if hud.fadeFlash ~= nil then
				hud.fadeFlash()
			end
			task.delay(0.15, function()
				local ok, result = pcall(function()
					return Net.func("TeleportToZone"):InvokeServer(n)
				end)
				if ok and type(result) == "table" and not result.Ok then
					local reason = TEXT.Reasons[result.Reason]
					if reason ~= nil then
						toast(reason, Theme.Gradients.Red, "TpReason")
					end
				end
			end)
		end)
	end
	tpBuy.Activated:Connect(function()
		Sounds.play("Button")
		Shop.buy("Pass", "Teleport", nil, tpBuy)
	end)

	------------------------------------------------------------- Stan
	local function render(view)
		readTimers(view)
		local passes = view.Passes or {}
		for key in pairs(Catalog.PASSES) do
			win.setOwned(key, passes[key] == true)
		end
		local starterOn = (view.StarterLeft or 0) > 0
		starterButton.holder.Visible = starterOn
		win.setStarter(view.StarterLeft or 0)
		renderAd()
		renderTeleport()
	end
	State.onChange(render)

	-- zegary (Starter Pack i boosty) co ćwierć sekundy; miejsce napisów co 2 s
	task.spawn(function()
		local tick = 0
		while true do
			local now = os.clock()
			for kind, icon in pairs(boostIcons) do
				local left = boostEnds[kind] - now
				local on = left > 0
				if on ~= icon.on then
					icon.on = on
					if on then
						icon.holder.Visible = true
						icon.time.Text = timeText(left)
						icon.layoutTip()
						Fx.pop(icon.scale, 0, 0.4)
					else
						-- koniec boosta: ikonka maleje i znika
						icon.showTip(false)
						icon.setWarn(false)
						Fx.tween(icon.scale, 0.18, { Scale = 0 }, Style.Quad, Dir.In)
						Fx.after(0.2, function()
							if not icon.on then
								icon.holder.Visible = false
							end
						end)
					end
				end
				if on then
					local text = timeText(left)
					if text ~= icon.time.Text then
						icon.time.Text = text
						icon.layoutTip()
					end
					-- dokupiony czas: podskok
					if left > icon.last + 5 and icon.last > 0 then
						Fx.bump(icon.scale, 1.3, 0.45)
					end
					icon.setWarn(left < 30)
				end
				icon.last = math.max(0, left)
			end
			local starterLeft = starterEnds - now
			if starterLeft > 0 then
				starterButton.timer.Text = timeText(starterLeft)
				win.setStarter(starterLeft)
			elseif starterButton.holder.Visible then
				starterButton.holder.Visible = false
				win.setStarter(0)
			end
			tick = tick + 1
			if tick % 8 == 1 then
				placeTimers()
				placeColumn() -- przycisk skoku pojawia się dopiero z postacią
			end
			-- kafelek SHOP: co kilka sekund połysk i podskok koszyka, Starter Pack: połysk
			if tick % (SIDE.IdleEvery * 4) == 0 and not shopWindow.isOpen() then
				shopTile.shine.play(0.6)
				Fx.bump(shopTile.iconScale, 1.15, 0.45)
				if starterButton.holder.Visible then
					task.delay(0.4, function()
						starterButton.shine.play(0.55)
					end)
				end
			end
			task.wait(0.25)
		end
	end)

	------------------------------------------------------------- Otwieranie okien
	-- Kliknięcie SHOP: z kafelka wylatują małe koszyki, rozchodzi się fala, okno wyskakuje.
	local function shopBurst(face)
		local center = face.AbsolutePosition + face.AbsoluteSize / 2
		local k = hudScale()
		Fx.ring(hud.gui, UDim2.fromOffset(center.X, center.Y), 50 * k, 260 * k, Theme.White, 58, 0.5)
		-- dookoła, od losowego kąta (część może wylecieć za ekran)
		Fx.burst(hud.gui, center, function()
			return ShopArt.mini("Shop")
		end, { count = SIDE.BurstCount, size = 48, distance = 230, angle = math.random(0, 359), spread = 360, scale = k, time = 0.85, zIndex = 60 })
	end
	local function openShop(face)
		if shopWindow.isOpen() then
			shopWindow.hide()
			return
		end
		shopBurst(face or shopTile.face)
		hud.openWindow(shopWindow)
		task.spawn(checkAd)
	end
	Shop.open = openShop
	shopTile.Activated:Connect(function()
		openShop(shopTile.face)
	end)
	starterButton.Activated:Connect(function()
		if not shopWindow.isOpen() then
			openShop(starterButton.face)
		end
	end)
	tpTile.Activated:Connect(function()
		if tpPanel.isOpen() then
			tpPanel.hide()
			return
		end
		renderTeleport()
		hud.openWindow(tpPanel)
	end)

	-- przyciski gamepassów w innych miejscach (Auto Click, Auto Sell, Buy 3 przy jajkach i boxach)
	hud.passPrompt = function(key, button)
		Sounds.play("Button")
		Shop.buy("Pass", key, nil, button)
	end

	------------------------------------------------------------- Podziękowania i komunikaty
	local function boostName(boost)
		if boost == "AutoSell" then
			return Catalog.PRODUCTS.BoostAutoSell15.name, "BoostAutoSell"
		end
		return Catalog.PRODUCTS.Boost2xLP5.name, "Boost2xLP"
	end
	State.onNotify(function(payload)
		if payload.Kind == "Purchase" then
			if payload.Result == "Boost" then
				if payload.Daily then
					Sounds.play("Unlock", { volume = 0.5 })
					toast(string.format(TEXT.BoostDaily, payload.Minutes or 0), Theme.Gradients.Cyan, "BoostDaily", "Verified")
				elseif payload.Ad then
					Sounds.play("Unlock", { volume = 0.5 })
					toast(string.format(TEXT.BoostAd, payload.Minutes or 0), Theme.Gradients.LP, "BoostAd", "Boost")
				else
					local name, art = boostName(payload.Boost)
					ShopThanks.show({ mode = "compact", art = art, name = name, sub = string.format(TEXT.ThanksBoost, payload.Minutes or 0), test = payload.Test })
				end
			elseif payload.Result == "Starter" then
				ShopThanks.show({ mode = "full", art = "Starter", name = Catalog.PRODUCTS.StarterPack.name, sub = TEXT.ThanksStarter, items = Catalog.STARTER_ITEMS, test = payload.Test })
			elseif payload.Result == "Pets" then
				local info = Catalog.PRODUCTS[payload.Key] or Catalog.PRODUCTS.PremiumEgg1
				local count = (type(payload.Pets) == "table" and #payload.Pets) or 1
				ShopThanks.show({ mode = "compact", art = info.art, name = info.name, sub = "x" .. count, test = payload.Test, waitCalm = true })
			elseif payload.Result == "Sell" then
				ShopThanks.show({ mode = "compact", art = "SellNow", name = Catalog.PRODUCTS.SellNow.name, sub = TEXT.ThanksSell, test = payload.Test })
			end
		elseif payload.Kind == "PassBought" then
			local info = Catalog.PASSES[payload.Key]
			if info ~= nil then
				ShopThanks.show({ mode = "full", art = info.art, name = info.name, sub = TEXT.ThanksPass, test = payload.Test })
			end
		elseif payload.Kind == "BoostEnded" then
			local name = TEXT.BoostLP
			if payload.Boost == "AutoSell" then
				name = TEXT.BoostAutoSell
			end
			toast(string.format(TEXT.BoostEnded, name), Theme.Gradients.Gray, "BoostEnded" .. tostring(payload.Boost))
		end
	end)

	-- ceny regionalne
	for key in pairs(Robux.Gamepasses) do
		fetchPrice("Pass", key)
	end
	for key in pairs(Robux.Products) do
		fetchPrice("Product", key)
	end
end

return Shop
