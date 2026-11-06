-- Sklep za Robuxy (Etap 10) po stronie gracza:
--   • po prawej stronie ekranu kafelki SHOP i TELEPORT, pod nimi Starter Pack (z zegarem do końca
--     oferty) i aktywne boosty z pozostałym czasem,
--   • okno SHOP: Starter Pack, 11 gamepassów, boosty, Sell Now i reklama za nagrodę,
--   • okno TELEPORT: odblokowane strefy (gamepass Teleport),
--   • ceny z MarketplaceService:GetProductInfoAsync (ceny regionalne gracza); zanim przyjdą, z Economy,
--   • komunikaty po zakupie (boost, Starter Pack, gamepass) i po końcu boosta.
-- Zakup zawsze sprawdza i robi serwer (ShopService, Net „Buy”); tu jest tylko wygląd. Pety z premium
-- jajek pokazuje animacja w Eggs.luau.

local TweenService = game:GetService("TweenService")
local MarketplaceService = game:GetService("MarketplaceService")
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

local Shop = {}

local ROBUX = "\238\128\130" -- znak Robux (U+E002)

local TEXT = {
	Shop = "SHOP",
	Teleport = "TELEPORT",
	Title = "Shop",
	Gamepasses = "GAMEPASSES",
	Boosts = "BOOSTS",
	Owned = "OWNED",
	Soon = "SOON",
	Starter = "STARTER PACK",
	StarterShort = "STARTER",
	StarterEnds = "Ends in %s · one time only!",
	StarterItems = { "Rare Watch", "Epic Pet", "2x LP\n30 min", "Auto Sell\n30 min" },
	Best = "BEST VALUE!",
	Free = "FREE 2x LP",
	FreeDesc = "Watch a video: %d min 2x LP · %d/%d left today", -- nagroda opisana przed reklamą (zasady Roblox)
	Watch = "WATCH",
	WatchTest = "WATCH (TEST)",
	NoAds = "NO ADS NOW",
	TeleportTitle = "Teleport",
	TeleportNote = "Teleport to any unlocked zone!",
	TeleportBuy = "GET TELEPORT",
	ZoneButton = "%d · %s",
	BoostLP = "2x LP",
	BoostAutoSell = "AUTO SELL",
	-- komunikaty
	Reasons = {
		Soon = "Coming soon!",
		Owned = "You already own this!",
		Expired = "This offer has ended",
		Zone = "Unlock this zone first!",
		Locked = "Unlock this zone first!",
		EmptyBag = "Your bag is empty!",
		Restricted = "Not available in your region",
		NotRestricted = "Buy the Premium Egg instead!",
		Limit = "No more free boosts today",
		NoPass = "You need the Teleport gamepass",
		Busy = "Finish what you're doing first",
		Error = "Something went wrong, try again",
	},
	TestBuy = "TEST PURCHASE",
	PassBought = "%s unlocked! Thank you!",
	BoostGot = "%s +%d min!",
	BoostDaily = "Verified bonus: 2x LP %d min!",
	BoostAd = "Thanks for watching! 2x LP +%d min",
	BoostEnded = "%s boost ended",
	StarterGot = "Starter Pack unlocked!",
}

-- Gamepassy: nazwa, opis i ikona w sklepie (kolejność: Robux.PassOrder).
local PASSES = {
	TwoXLP = { name = "2x LP", desc = "Double LP from clicks and activities", icon = "LP", colors = Theme.Gradients.LP },
	AutoSell = { name = "Auto Sell", desc = "Sell your Bag automatically, anywhere", icon = "Sell", colors = Theme.Gradients.Green },
	AutoClick = { name = "Auto Click", desc = "Clicks for you, 3 times a second", icon = "Click", colors = Theme.Gradients.Yellow },
	Verified = { name = "Verified", desc = "+10% LP, blue check and 15 min 2x LP daily", icon = "Verified", colors = Theme.Gradients.Cyan },
	PetSlots = { name = "+2 Pet Slots", desc = "Equip 2 more pets", icon = "Pets", colors = Theme.Gradients.Pink },
	TripleOpen = { name = "Triple Open", desc = "Open 3 eggs or boxes at once", icon = "Gift", colors = Theme.Gradients.Premium },
	FastOpen = { name = "Fast Open", desc = "Open eggs and boxes 3× faster", icon = "Clock", colors = Theme.Gradients.Red },
	TwoXBag = { name = "2x Bag", desc = "Double Bag capacity", icon = "Bag", colors = Theme.Gradients.Gold },
	Teleport = { name = "Teleport", desc = "Teleport to any unlocked zone", icon = "Teleport", colors = Theme.Gradients.Cyan },
	DoubleChain = { name = "Double Chain", desc = "Wear 2 chains at once", icon = "Chain", colors = Theme.Gradients.Gold },
	DoubleWrist = { name = "Double Wrist", desc = "Wear 2 watches at once", icon = "Watch", colors = Theme.Gradients.Pink },
}

-- Produkty w części BOOSTS.
local BOOSTS = {
	{ key = "Boost2xLP5", name = "2x LP · 5 min", desc = "Double LP for 5 minutes", icon = "Boost", colors = Theme.Gradients.LP },
	{ key = "Boost2xLP15", name = "2x LP · 15 min", desc = "Double LP for 15 minutes", icon = "Boost", colors = Theme.Gradients.LP },
	{ key = "Boost2xLP60", name = "2x LP · 1 hour", desc = "Double LP for 1 hour", icon = "Boost", colors = Theme.Gradients.LP },
	{ key = "BoostAutoSell15", name = "Auto Sell · 15 min", desc = "Auto Sell for 15 minutes", icon = "Sell", colors = Theme.Gradients.Green },
	{ key = "BoostAutoSell60", name = "Auto Sell · 1 hour", desc = "Auto Sell for 1 hour", icon = "Sell", colors = Theme.Gradients.Green },
	{ key = "SellNow", name = "Sell Now", desc = "Sell your Bag from anywhere", icon = "SellCash", colors = Theme.Gradients.Gold },
}

local CARD = Vector2.new(196, 206)
local CARD_GAP = 14
local PANEL_SIZE = Vector2.new(900, 560)

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
-- Zwraca odpowiedź serwera ({ Ok, Reason, Test }) albo nil.
function Shop.buy(kind, key, opts, button)
	local ok, result = pcall(function()
		return Net.func("Buy"):InvokeServer(kind, key, opts)
	end)
	if not ok or type(result) ~= "table" then
		return nil
	end
	if result.Ok then
		if result.Test then
			toast(TEXT.TestBuy, Theme.Gradients.Cyan, "TestBuy")
		end
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

----------------------------------------------------------------- Karta w sklepie
-- Kolorowy pasek z ikoną, nazwa, opis i przycisk z ceną. Zwraca { card, button, setOwned, setPrice }.
local function makeCard(parent, opts)
	local card = Kit.new("Frame", {
		Name = opts.name or "Card",
		LayoutOrder = opts.order or 0,
		Size = UDim2.fromOffset(CARD.X, CARD.Y),
		BackgroundColor3 = Theme.White,
		BorderSizePixel = 0,
		ZIndex = 4,
		Parent = parent,
	})
	Kit.corner(card, 20)
	Kit.stroke(card, 3.5, Enum.ApplyStrokeMode.Border)
	local band = Kit.new("Frame", {
		Name = "Band",
		Position = UDim2.fromOffset(7, 7),
		Size = UDim2.new(1, -14, 0, 92),
		BackgroundColor3 = Theme.White,
		BorderSizePixel = 0,
		ZIndex = 4,
		Parent = card,
	})
	Kit.corner(band, 15)
	Kit.gradient(band, opts.colors or Theme.Gradients.Cyan, 90)
	Icons.make(opts.icon or "Shop", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(70, 70),
		ZIndex = 5,
		Parent = band,
	})
	if opts.tag ~= nil then
		Kit.text(band, {
			Name = "Tag",
			AnchorPoint = Vector2.new(0, 0),
			Position = UDim2.fromOffset(6, 4),
			Size = UDim2.fromOffset(80, 26),
			Rotation = -8,
			Text = opts.tag,
			ZIndex = 6,
		}, { maxSize = 22, stroke = 3, gradient = Theme.Gradients.Gold })
	end
	Kit.text(card, {
		Name = "Title",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 102),
		Size = UDim2.new(1, -16, 0, 28),
		Text = opts.title or "",
		TextColor3 = Theme.Dark,
		ZIndex = 5,
	}, { maxSize = 23, stroke = 0 })
	local desc = Kit.text(card, {
		Name = "Desc",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 130),
		Size = UDim2.new(1, -18, 0, 30),
		Text = opts.desc or "",
		TextColor3 = Theme.Muted,
		TextWrapped = true,
		ZIndex = 5,
	}, { maxSize = 15, stroke = 0 })
	local button = Kit.button(card, {
		name = "Buy",
		size = Vector2.new(170, 38),
		text = "",
		colors = Theme.Gradients.Green,
		radius = 14,
		edge = 4,
		textSize = 22,
		anchor = Vector2.new(0.5, 1),
		position = UDim2.new(0.5, 0, 1, -7),
		sound = false,
	})
	button.holder.ZIndex = 5
	local api = { card = card, button = button, desc = desc, owned = false }
	function api.setOwned(owned, text)
		api.owned = owned
		if owned then
			button.setColors(Theme.Gradients.Gray)
			button.setText(text or TEXT.Owned)
		end
	end
	function api.setPrice(text)
		if not api.owned then
			button.setColors(opts.buttonColors or Theme.Gradients.Green)
			button.setText(text)
		end
	end
	return api
end

local function sectionHeader(parent, text, order)
	local holder = Kit.new("Frame", {
		Name = "Header" .. order,
		LayoutOrder = order,
		Size = UDim2.new(1, -12, 0, 40),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	Kit.line(holder, {
		anchor = Vector2.new(0, 0.5),
		position = UDim2.new(0, 6, 0.5, 0),
		height = 40,
		items = { { text = text, size = 30, colors = Theme.Gradients.Gold } },
	})
	return holder
end

local function grid(parent, name, order)
	local frame = Kit.new("Frame", {
		Name = name,
		LayoutOrder = order,
		Size = UDim2.fromOffset(4 * CARD.X + 3 * CARD_GAP, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = parent,
	})
	Kit.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(CARD.X, CARD.Y),
		CellPadding = UDim2.fromOffset(CARD_GAP, CARD_GAP),
		FillDirectionMaxCells = 4,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = frame,
	})
	return frame
end

----------------------------------------------------------------- Start
function Shop.start(hud)
	hudRef = hud

	------------------------------------------------------------- Kafelki po prawej
	local root = Kit.new("Frame", {
		Name = "ShopRoot",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -22, 0.46, 0),
		Size = UDim2.fromOffset(172, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = hud.gui,
	})
	hud.registerScale(root)
	Kit.new("UIListLayout", {
		Padding = UDim.new(0, 26),
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = root,
	})
	local shopTile = Kit.tile(root, {
		name = "Shop",
		icon = "Shop",
		text = TEXT.Shop,
		colors = Theme.Gradients.Premium,
		order = 1,
	})
	local tpTile = Kit.tile(root, {
		name = "Teleport",
		icon = "Teleport",
		text = TEXT.Teleport,
		colors = Theme.Gradients.Cyan,
		order = 2,
		textSize = 19,
	})
	local tpLock = Icons.make("Lock", {
		Name = "PassLock",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -8, 0, 8),
		Size = UDim2.fromOffset(30, 30),
		Rotation = 10,
		ZIndex = 8,
		Parent = tpTile.face,
	})
	-- Starter Pack: przycisk z napisem i zegarem (tylko dopóki oferta trwa)
	local starterButton = Kit.button(root, {
		name = "StarterPack",
		size = Vector2.new(168, 60),
		colors = Theme.Gradients.Starter,
		radius = 18,
		order = 3,
	})
	Kit.text(starterButton.face, {
		Name = "Title",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 4),
		Size = UDim2.new(1, -12, 0, 28),
		Text = TEXT.Starter,
		ZIndex = 4,
	}, { maxSize = 22, stroke = 3 })
	local starterTimer = Kit.text(starterButton.face, {
		Name = "Timer",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -3),
		Size = UDim2.new(1, -12, 0, 24),
		Text = "",
		ZIndex = 4,
	}, { maxSize = 20, stroke = 2.5, gradient = Theme.Gradients.Gold })
	local starterPulse = Kit.new("UIScale", { Parent = starterButton.body })
	TweenService:Create(starterPulse, TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = 1.06 }):Play()
	starterButton.holder.Visible = false

	-- aktywne boosty: pigułki z czasem
	local boostFrame = Kit.new("Frame", {
		Name = "Boosts",
		LayoutOrder = 4,
		Size = UDim2.fromOffset(172, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = root,
	})
	Kit.new("UIListLayout", {
		Padding = UDim.new(0, 8),
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = boostFrame,
	})
	local boostPills = {}
	local function boostPill(kind, name, icon, colors, order)
		local holder = Kit.new("Frame", {
			Name = kind,
			LayoutOrder = order,
			Size = UDim2.fromOffset(168, 42),
			BackgroundColor3 = Theme.White,
			BorderSizePixel = 0,
			Visible = false,
			Parent = boostFrame,
		})
		Kit.corner(holder, 21)
		Kit.stroke(holder, 3.5, Enum.ApplyStrokeMode.Border)
		Kit.gradient(holder, colors, 90)
		Icons.make(icon, {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 6, 0.5, 0),
			Size = UDim2.fromOffset(32, 32),
			ZIndex = 2,
			Parent = holder,
		})
		Kit.text(holder, {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 42, 0.5, -8),
			Size = UDim2.fromOffset(118, 18),
			Text = name,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 2,
		}, { maxSize = 16, stroke = 2 })
		local timer = Kit.text(holder, {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 42, 0.5, 9),
			Size = UDim2.fromOffset(118, 20),
			Text = "",
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 2,
		}, { maxSize = 19, stroke = 2.5, gradient = Theme.Gradients.Gold })
		boostPills[kind] = { holder = holder, timer = timer }
	end
	boostPill("LP", TEXT.BoostLP, "Boost", Theme.Gradients.LP, 1)
	boostPill("AutoSell", TEXT.BoostAutoSell, "Sell", Theme.Gradients.Green, 2)

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
	local panel = Kit.panel(hud.gui, {
		name = "ShopPanel",
		size = PANEL_SIZE,
		title = TEXT.Title,
		icon = "Shop",
		padding = 22,
		top = 52,
		bottom = 20,
	})
	hud.registerScale(panel.holder)
	hud.addWindow(panel)
	local scroll = Kit.new("ScrollingFrame", {
		Name = "Scroll",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = Theme.Muted,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ZIndex = 3,
		Parent = panel.content,
	})
	Kit.new("UIListLayout", {
		Padding = UDim.new(0, 12),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = scroll,
	})
	Kit.new("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 12), Parent = scroll })

	-- Starter Pack: szeroka karta na górze
	local starterCard = Kit.new("Frame", {
		Name = "StarterCard",
		LayoutOrder = 1,
		Size = UDim2.fromOffset(4 * CARD.X + 3 * CARD_GAP, 176),
		BackgroundColor3 = Theme.White,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 4,
		Parent = scroll,
	})
	Kit.corner(starterCard, 22)
	Kit.stroke(starterCard, 4, Enum.ApplyStrokeMode.Border)
	Kit.gradient(starterCard, Theme.Gradients.Starter, 90)
	Kit.text(starterCard, {
		Name = "Title",
		Position = UDim2.fromOffset(22, 8),
		Size = UDim2.fromOffset(330, 48),
		Text = TEXT.Starter,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 5,
	}, { maxSize = 42, stroke = 4, gradient = Theme.Gradients.Gold })
	local starterCardTimer = Kit.text(starterCard, {
		Name = "Timer",
		Position = UDim2.fromOffset(24, 54),
		Size = UDim2.fromOffset(420, 24),
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 5,
	}, { maxSize = 20, stroke = 2.5 })
	local sp = Economy.Robux.Products.StarterPack
	local starterIcons = { "Watch", "Pets", "Boost", "Sell" }
	local starterLabels = {
		sp.Watch .. " Watch",
		sp.PetRarity .. " Pet",
		string.format("2x LP\n%d min", sp.BoostMinutes),
		string.format("Auto Sell\n%d min", sp.AutoSellMinutes),
	}
	for i = 1, 4 do
		local tile = Kit.new("Frame", {
			Name = "Item" .. i,
			Position = UDim2.fromOffset(22 + (i - 1) * 122, 84),
			Size = UDim2.fromOffset(112, 82),
			BackgroundColor3 = Theme.White,
			BorderSizePixel = 0,
			ZIndex = 5,
			Parent = starterCard,
		})
		Kit.corner(tile, 14)
		Kit.stroke(tile, 3, Enum.ApplyStrokeMode.Border)
		Icons.make(starterIcons[i], {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 4),
			Size = UDim2.fromOffset(40, 40),
			ZIndex = 6,
			Parent = tile,
		})
		Kit.text(tile, {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -3),
			Size = UDim2.new(1, -8, 0, 34),
			Text = starterLabels[i],
			TextColor3 = Theme.Dark,
			TextWrapped = true,
			ZIndex = 6,
		}, { maxSize = 15, stroke = 0 })
	end
	Kit.text(starterCard, {
		Name = "Best",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -120, 0, 40),
		Size = UDim2.fromOffset(190, 38),
		Rotation = 6,
		Text = TEXT.Best,
		ZIndex = 6,
	}, { maxSize = 30, stroke = 3.5, gradient = Theme.Gradients.Gold })
	local starterBuy = Kit.button(starterCard, {
		name = "Buy",
		size = Vector2.new(220, 70),
		text = "",
		colors = Theme.Gradients.Green,
		textSize = 36,
		anchor = Vector2.new(1, 1),
		position = UDim2.new(1, -18, 1, -14),
		sound = false,
	})
	starterBuy.holder.ZIndex = 6
	Shop.onPrice("Product", "StarterPack", function()
		starterBuy.setText(Shop.priceText("Product", "StarterPack"))
	end)
	starterBuy.Activated:Connect(function()
		Sounds.play("Button")
		Shop.buy("Product", "StarterPack", nil, starterBuy)
	end)

	-- gamepassy
	sectionHeader(scroll, TEXT.Gamepasses, 2)
	local passGrid = grid(scroll, "Gamepasses", 3)
	local passCards = {}
	for i, key in ipairs(Robux.PassOrder) do
		local info = PASSES[key]
		if info ~= nil and Robux.Gamepasses[key] ~= nil then
			local card = makeCard(passGrid, {
				name = key,
				order = i,
				title = info.name,
				desc = info.desc,
				icon = info.icon,
				colors = info.colors,
			})
			passCards[key] = card
			Shop.onPrice("Pass", key, function()
				card.setPrice(Shop.priceText("Pass", key))
			end)
			card.button.Activated:Connect(function()
				if card.owned then
					return
				end
				Sounds.play("Button")
				Shop.buy("Pass", key, nil, card.button)
			end)
		end
	end

	-- boosty i reklama
	sectionHeader(scroll, TEXT.Boosts, 4)
	local boostGrid = grid(scroll, "BoostGrid", 5)
	local adCard = makeCard(boostGrid, {
		name = "FreeBoost",
		order = 0,
		title = TEXT.Free,
		desc = "",
		icon = "Ad",
		colors = Theme.Gradients.Pink,
		tag = "FREE",
		buttonColors = Theme.Gradients.Pink,
	})
	adCard.card.Visible = false
	for i, entry in ipairs(BOOSTS) do
		if Robux.Products[entry.key] ~= nil then
			local card = makeCard(boostGrid, {
				name = entry.key,
				order = i,
				title = entry.name,
				desc = entry.desc,
				icon = entry.icon,
				colors = entry.colors,
			})
			Shop.onPrice("Product", entry.key, function()
				card.setPrice(Shop.priceText("Product", entry.key))
			end)
			card.button.Activated:Connect(function()
				Sounds.play("Button")
				Shop.buy("Product", entry.key, nil, card.button)
			end)
		end
	end

	-- reklama za nagrodę: tylko gdy Roblox ma reklamę dla gracza (albo tester bez ID produktu)
	local adAvailable = false
	local adWatching = false
	local function renderAd()
		local view = State.view
		if view == nil then
			return
		end
		local left = view.AdsLeft or 0
		local tester = view.IsAdmin == true and Robux.productId(Robux.AdReward) == nil
		local show = view.AdsReady == true and (adAvailable or tester)
		adCard.card.Visible = show
		local reward = Robux.Products[Robux.AdReward]
		adCard.desc.Text = string.format(TEXT.FreeDesc, (reward and reward.Minutes) or 0, left, Economy.Bonuses.RewardedVideoDailyMax)
		if left <= 0 then
			adCard.setOwned(true, TEXT.NoAds)
		else
			adCard.owned = false
			if tester then
				adCard.setPrice(TEXT.WatchTest)
			else
				adCard.setPrice(TEXT.Watch)
			end
		end
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
	adCard.button.Activated:Connect(function()
		if adCard.owned or adWatching then
			return
		end
		Sounds.play("Button")
		adWatching = true
		adCard.setOwned(true, "...")
		local ok, result = pcall(function()
			return Net.func("WatchAd"):InvokeServer()
		end)
		adWatching = false
		adCard.owned = false
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
			colors = Theme.Gradients.Cyan,
			textSize = 28,
			anchor = Vector2.new(0.5, 0),
			position = UDim2.new(0.5, 0, 0, (n - 1) * 70),
			sound = false,
		})
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
				b.setColors(Theme.Gradients.Cyan)
			else
				b.setColors(Theme.Gradients.Gray)
			end
		end
		tpNote.holder.Visible = not owns
		tpBuy.holder.Visible = not owns
		tpLock.Visible = not owns
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
		for key, card in pairs(passCards) do
			if passes[key] then
				card.setOwned(true)
			elseif card.owned then
				card.owned = false
				card.setPrice(Shop.priceText("Pass", key))
			end
		end
		local starterOn = (view.StarterLeft or 0) > 0
		starterButton.holder.Visible = starterOn
		starterCard.Visible = starterOn
		renderAd()
		renderTeleport()
	end
	State.onChange(render)

	-- zegary (Starter Pack i boosty) co ćwierć sekundy
	task.spawn(function()
		while true do
			local now = os.clock()
			for kind, pill in pairs(boostPills) do
				local left = boostEnds[kind] - now
				pill.holder.Visible = left > 0
				if left > 0 then
					pill.timer.Text = timeText(left)
				end
			end
			local starterLeft = starterEnds - now
			if starterLeft > 0 then
				local text = timeText(starterLeft)
				starterTimer.Text = text
				starterCardTimer.Text = string.format(TEXT.StarterEnds, text)
			elseif starterButton.holder.Visible then
				starterButton.holder.Visible = false
				starterCard.Visible = false
			end
			task.wait(0.25)
		end
	end)

	------------------------------------------------------------- Otwieranie okien
	local function openShop()
		if panel.isOpen() then
			panel.hide()
			return
		end
		scroll.CanvasPosition = Vector2.new(0, 0)
		hud.openWindow(panel)
		task.spawn(checkAd)
	end
	shopTile.Activated:Connect(openShop)
	starterButton.Activated:Connect(function()
		if not panel.isOpen() then
			openShop()
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

	------------------------------------------------------------- Komunikaty
	State.onNotify(function(payload)
		if payload.Kind == "Purchase" then
			if payload.Result == "Boost" then
				Sounds.play("Unlock", { volume = 0.5 })
				if payload.Daily then
					toast(string.format(TEXT.BoostDaily, payload.Minutes or 0), Theme.Gradients.Cyan, "BoostDaily", "Verified")
				elseif payload.Ad then
					toast(string.format(TEXT.BoostAd, payload.Minutes or 0), Theme.Gradients.LP, "BoostAd", "Boost")
				else
					local name = TEXT.BoostLP
					local icon = "Boost"
					if payload.Boost == "AutoSell" then
						name = TEXT.BoostAutoSell
						icon = "Sell"
					end
					toast(string.format(TEXT.BoostGot, name, payload.Minutes or 0), Theme.Gradients.LP, "BoostGot" .. tostring(payload.Boost), icon)
				end
			elseif payload.Result == "Starter" then
				Sounds.play("Reward")
				toast(TEXT.StarterGot, Theme.Gradients.Gold, "StarterGot", "Gift")
			end
		elseif payload.Kind == "PassBought" then
			local info = PASSES[payload.Key]
			Sounds.play("Unlock")
			toast(string.format(TEXT.PassBought, (info and info.name) or tostring(payload.Key)), Theme.Gradients.Gold, "PassBought", (info and info.icon) or "Gift")
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
