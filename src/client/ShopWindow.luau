-- Okno SHOP (sklep za Robuxy) w stylu Pet Simulator 99:
--   • po lewej zakładki OFFERS / PASSES / BOOSTS (płynne przewijanie do części, aktywna zakładka
--     podąża za przewijaniem),
--   • OFFERS: duża karta Starter Packa (zegar, cztery rzeczy, BEST VALUE) i darmowy boost za reklamę,
--   • PASSES: dwa wyróżnione gamepassy na szerokich kartach i 9 kart w siatce 3×3,
--   • BOOSTS: 2x LP i Auto Sell z kilkoma czasami do wyboru (BEST DEAL liczy się z cen) i Sell Now.
-- Każda karta ma grafikę z ShopArt (animacja „w spoczynku”), promienie, spadające małe ikony w tle,
-- połysk i reakcję na mysz. Otwarcie: przyciemnienie i rozmycie świata, okno wyskakuje, karty
-- wjeżdżają po kolei. Animacje tła działają tylko przy otwartym oknie i tylko dla widocznych kart.
-- Zakup robi Shop.buy (serwer), tu jest tylko wygląd. ShopWindow.create zwraca okno dla hud.addWindow.

local Lighting = game:GetService("Lighting")
local GuiService = game:GetService("GuiService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Robux = require(Shared.Robux)
local Theme = require(script.Parent.Ui.Theme)
local Kit = require(script.Parent.Ui.Kit)
local Icons = require(script.Parent.Ui.Icons)
local Sounds = require(script.Parent.Ui.Sounds)
local Pattern = require(script.Parent.Ui.Pattern)
local Fx = require(script.Parent.Ui.Fx)
local ShopArt = require(script.Parent.Ui.ShopArt)
local Catalog = require(script.Parent.ShopCatalog)

local ShopWindow = {}

local TEXT = Catalog.TEXT
local new = Fx.new
local Style = Enum.EasingStyle
local Dir = Enum.EasingDirection

-- Wymiary w pikselach bazowych (ekran 1280×720).
local L = {
	Size = Vector2.new(1080, 600),
	Radius = 34,
	Fit = Vector2.new(1190, 700), -- okno z tytułem nad górną krawędzią i przyciskiem X (do dopasowania)
	RailX = 22,
	RailTop = 26,
	Tab = Vector2.new(150, 100),
	TabGap = 18,
	ScrollX = 192,
	ContentW = 840,
	Gap = 16,
	HeaderH = 58,
	HeroH = 244,
	AdH = 120,
	FeatureH = 262,
	Card = Vector2.new(269, 314),
	BoostH = 238,
	RowH = 226,
	Edge = 6,
	CardRadius = 24,
}

-- Ile naraz i jak często: małe ikony spadające w tle kart i połysk na kartach.
local AMBIENT = {
	Tick = 0.25,
	DropEvery = 0.5,
	MaxDrops = 14,
	MaxDropsPerCard = 3,
	ShineEvery = 1.6,
	BuyShineEvery = 3.2,
	Cascade = 6, -- tyle pierwszych kart wjeżdża po kolei przy otwarciu
	SparkleEvery = 1.1, -- iskierka przy grafice losowej widocznej karty
}

local TABS = {
	{ key = "Offers", text = TEXT.Offers, icon = "Gift", colors = Theme.Gradients.Starter },
	{ key = "Passes", text = TEXT.Passes, icon = "Crown", colors = Theme.Gradients.Premium },
	{ key = "Boosts", text = TEXT.Boosts, icon = "Boost", colors = Theme.Gradients.LP },
}

----------------------------------------------------------------- Klocki kart
-- Karta: ramka w układzie (holder), w niej body (środek; UIScale do najechania i wejścia), ciemna
-- krawędź pod spodem i kolorowa twarz z gradientem, jasną obwódką wewnątrz, warstwą spadających
-- ikon i połyskiem. Zwraca obiekt karty.
local function makeCard(win, parent, size, colors, opts)
	opts = opts or {}
	local holder = new("Frame", {
		Name = opts.name or "Card",
		LayoutOrder = opts.order or 0,
		Size = UDim2.fromOffset(size.X, size.Y),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	local body = new("Frame", {
		Name = "Body",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = holder,
	})
	local scale = Fx.scaleOf(body)
	local edge = new("Frame", {
		Name = "Edge",
		Position = UDim2.fromOffset(0, L.Edge),
		Size = UDim2.new(1, 0, 1, -L.Edge),
		BackgroundColor3 = Theme.Outline,
		BorderSizePixel = 0,
		ZIndex = 1,
		Parent = body,
	})
	Kit.corner(edge, L.CardRadius)
	local face = new("Frame", {
		Name = "Face",
		Size = UDim2.new(1, 0, 1, -L.Edge),
		BackgroundColor3 = Theme.White,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		ZIndex = 2,
		Parent = body,
	})
	Kit.corner(face, L.CardRadius)
	Kit.stroke(face, 4, Enum.ApplyStrokeMode.Border)
	Kit.gradient(face, colors, opts.gradientRotation or 90)
	local fall = new("Frame", {
		Name = "Fall",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = face,
	})
	local rim = new("Frame", {
		Name = "Rim",
		Position = UDim2.fromOffset(4, 4),
		Size = UDim2.new(1, -8, 1, -8),
		BackgroundTransparency = 1,
		ZIndex = 4,
		Parent = face,
	})
	Kit.corner(rim, L.CardRadius - 4)
	new("UIStroke", { Thickness = 2.5, Color = Theme.White, Transparency = 0.45, Parent = rim })
	local card = {
		holder = holder,
		body = body,
		face = face,
		fall = fall,
		scale = scale,
		kind = opts.kind,
		drops = 0,
		weight = opts.weight or 1,
	}
	card.shine = Fx.shine(body, { inset = 4, width = opts.shineWidth or 110, strength = 0.7, zIndex = 12, bottom = L.Edge })
	Fx.hover(face, scale, opts.hoverScale or 1.035, function()
		card.shine.play(0.6)
	end)
	table.insert(win.cards, card)
	return card
end

-- Grafika produktu na karcie (poza twarzą karty, więc może wystawać przy powiększeniu).
local function cardArt(card, kind, size, position, z)
	card.art = ShopArt.make(kind, size, card.body, { Position = position, ZIndex = z or 6 })
	card.artScale = Fx.scaleOf(card.art.root)
	return card.art
end

-- Promienie za grafiką (w twarzy karty, obcięte do jej prostokąta, gasną przed rogami).
local function cardRays(card, center, length, spinning)
	local rays = Fx.rays(card.face, center, { count = 8, width = 30, length = length, alpha = 0.32, zIndex = 1 })
	if spinning then
		card.rays = rays
	end
	return rays
end

local function cardText(parent, props, maxSize, stroke, gradient)
	props.ZIndex = props.ZIndex or 8
	return Kit.text(parent, props, { maxSize = maxSize, stroke = stroke or 4, gradient = gradient })
end

-- Przycisk z ceną (zielony) + połysk na nim. Zwraca przycisk Kit z polem shine.
local function priceButton(parent, size, opts)
	local button = Kit.button(parent, {
		name = opts.name or "Buy",
		size = size,
		text = "",
		colors = opts.colors or Theme.Gradients.Green,
		radius = opts.radius or 16,
		edge = 5,
		textSize = opts.textSize or 32,
		textStroke = 3.5,
		anchor = opts.anchor or Vector2.new(0.5, 1),
		position = opts.position,
		sound = false,
	})
	button.holder.ZIndex = opts.zIndex or 9
	Fx.button(button)
	button.shine = Fx.shine(button.face, { inset = 3, width = math.floor(size.Y * 1.1), strength = 0.8, zIndex = 6 })
	-- znak „kupione” (na razie schowany)
	button.check = Icons.make("Check", {
		Name = "CheckIcon",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 10, 0.5, 0),
		Size = UDim2.fromOffset(size.Y - 18, size.Y - 18),
		Visible = false,
		ZIndex = 7,
		Parent = button.face,
	})
	return button
end

local function setOwnedButton(button, owned, colors)
	-- napis OWNED stoi na prawo od znaczka (wyśrodkowany wchodził na niego w wąskich przyciskach)
	local label = button.label
	if owned then
		button.setColors(Theme.Gradients.Owned)
		button.setText(TEXT.Owned)
		button.check.Visible = true
		if label ~= nil then
			local left = button.check.Size.X.Offset + 14
			label.Position = UDim2.new(0.5, math.floor(left / 2), 0.52, 0)
			label.Size = UDim2.new(1, -14 - left, 1, -12)
		end
	else
		button.setColors(colors or Theme.Gradients.Green)
		button.check.Visible = false
		if label ~= nil then
			label.Position = UDim2.fromScale(0.5, 0.52)
			label.Size = UDim2.new(1, -14, 1, -12)
		end
	end
end

-- Mały napis-plakietka (np. FOREVER, BEST DEAL): złoty tekst na ciemnej pigułce.
local function ribbon(parent, text, size, position, rotation, colors, z)
	local holder = new("Frame", {
		Name = "Ribbon",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = position,
		Size = UDim2.fromOffset(size.X, size.Y),
		Rotation = rotation or 0,
		BackgroundColor3 = Theme.White,
		BorderSizePixel = 0,
		ZIndex = z or 10,
		Parent = parent,
	})
	Kit.corner(holder, math.floor(size.Y / 2))
	Kit.stroke(holder, 3, Enum.ApplyStrokeMode.Border)
	Kit.gradient(holder, colors or Theme.Gradients.Red, 90)
	Kit.text(holder, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.new(1, -14, 1, -8),
		Text = text,
		ZIndex = (z or 10) + 1,
	}, { maxSize = 22, stroke = 2.5 })
	return holder
end

----------------------------------------------------------------- Nagłówek części
local function sectionHeader(win, parent, key, text, icon, order)
	local holder = new("Frame", {
		Name = key .. "Header",
		LayoutOrder = order,
		Size = UDim2.fromOffset(L.ContentW, L.HeaderH),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	local line = Kit.line(holder, {
		anchor = Vector2.new(0.5, 0.5),
		position = UDim2.fromScale(0.5, 0.5),
		height = L.HeaderH,
		gap = 12,
		items = {
			{ icon = icon, size = 44 },
			{ text = text, size = 42, colors = Theme.Gradients.Gold },
			{ icon = icon, size = 44 },
		},
	})
	local scale = Fx.scaleOf(line.holder)
	win.sections[key] = { key = key, header = holder, scale = scale, visible = true }
	return holder
end

----------------------------------------------------------------- Karty gamepassów
local function passPrice(win, card, key)
	win.shop.onPrice("Pass", key, function()
		if not card.owned then
			card.button.setText(win.shop.priceText("Pass", key))
		end
	end)
	card.button.Activated:Connect(function()
		if card.owned then
			return
		end
		Sounds.play("Button")
		win.shop.buy("Pass", key, nil, card.button)
	end)
end

-- Karta w siatce 3×3: nazwa u góry, grafika, opis i cena.
local function gridPassCard(win, parent, key, order)
	local info = Catalog.PASSES[key]
	local card = makeCard(win, parent, L.Card, info.colors, { name = key, order = order, kind = info.art })
	local w, h = L.Card.X, L.Card.Y - L.Edge
	cardRays(card, UDim2.fromOffset(w / 2, 114), 150, false)
	cardText(card.body, {
		Name = "Title",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 12),
		Size = UDim2.new(1, -28, 0, 40),
		Text = info.name,
	}, 34, 4)
	cardArt(card, info.art, 126, UDim2.fromOffset(w / 2, 114))
	cardText(card.body, {
		Name = "Desc",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 180),
		Size = UDim2.new(1, -30, 0, 44),
		Text = info.desc,
		TextWrapped = true,
	}, 19, 3)
	card.button = priceButton(card.body, Vector2.new(222, 52), { position = UDim2.new(0.5, 0, 0, h - 12) })
	win.passCards[key] = card
	passPrice(win, card, key)
	return card
end

-- Szeroka karta wyróżnionego gamepassa: duża grafika po lewej, napisy i cena po prawej.
local function featurePassCard(win, parent, key, order)
	local info = Catalog.PASSES[key]
	local size = Vector2.new((L.ContentW - L.Gap) / 2, L.FeatureH)
	local card = makeCard(win, parent, size, info.colors, { name = key, order = order, kind = info.art, weight = 2, shineWidth = 140, hoverScale = 1.025 })
	local h = size.Y - L.Edge
	cardRays(card, UDim2.fromOffset(110, h / 2), 220, true)
	cardArt(card, info.art, 178, UDim2.fromOffset(110, h / 2))
	cardText(card.body, {
		Name = "Title",
		Position = UDim2.fromOffset(212, 24),
		Size = UDim2.fromOffset(size.X - 232, 52),
		Text = info.name,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, 46, 4.5)
	cardText(card.body, {
		Name = "Desc",
		Position = UDim2.fromOffset(214, 80),
		Size = UDim2.fromOffset(size.X - 236, 62),
		Text = info.desc,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
	}, 22, 3)
	card.button = priceButton(card.body, Vector2.new(188, 58), { anchor = Vector2.new(1, 1), position = UDim2.new(1, -18, 0, h - 14), textSize = 34 })
	ribbon(card.body, TEXT.Forever, Vector2.new(116, 34), UDim2.new(1, -60, 0, 6), 8, Theme.Gradients.Red, 11)
	win.passCards[key] = card
	passPrice(win, card, key)
	return card
end

----------------------------------------------------------------- Starter Pack
local function starterHero(win, parent, order)
	local size = Vector2.new(L.ContentW, L.HeroH)
	local card = makeCard(win, parent, size, Theme.Gradients.Starter, { name = "StarterCard", order = order, kind = "Starter", weight = 3, shineWidth = 180, hoverScale = 1.012, gradientRotation = 0 })
	local h = size.Y - L.Edge
	cardRays(card, UDim2.fromOffset(700, h / 2), 300, true)
	cardText(card.body, {
		Name = "Title",
		Position = UDim2.fromOffset(26, 12),
		Size = UDim2.fromOffset(460, 58),
		Text = TEXT.Starter,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, 54, 5, Theme.Gradients.Gold)
	Icons.make("Clock", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromOffset(28, 86),
		Size = UDim2.fromOffset(30, 30),
		ZIndex = 8,
		Parent = card.body,
	})
	local timer = cardText(card.body, {
		Name = "Timer",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromOffset(64, 86),
		Size = UDim2.fromOffset(230, 30),
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
	}, 25, 3)
	cardText(card.body, {
		Name = "OneTime",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromOffset(300, 86),
		Size = UDim2.fromOffset(240, 30),
		Text = TEXT.OneTime,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, 25, 3, Theme.Gradients.Gold)
	-- cztery rzeczy w paczce z plusami między nimi
	card.items = {}
	for i, item in ipairs(Catalog.STARTER_ITEMS) do
		local x = 26 + (i - 1) * 138
		local tile = new("Frame", {
			Name = "Item" .. i,
			Position = UDim2.fromOffset(x, 108),
			Size = UDim2.fromOffset(116, 116),
			BackgroundColor3 = Theme.White,
			BorderSizePixel = 0,
			ZIndex = 7,
			Parent = card.body,
		})
		Kit.corner(tile, 20)
		Kit.stroke(tile, 3.5, Enum.ApplyStrokeMode.Border)
		Kit.gradient(tile, Theme.Gradients.Panel, 90)
		local art = ShopArt.make(item.art, 66, tile, { Position = UDim2.fromOffset(58, 40), ZIndex = 8 })
		Kit.text(tile, {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -6),
			Size = UDim2.new(1, -10, 0, 36),
			Text = item.label,
			TextColor3 = Theme.Dark,
			TextWrapped = true,
			ZIndex = 9,
		}, { maxSize = 18, stroke = 0 })
		table.insert(card.items, { tile = tile, art = art })
		if i < #Catalog.STARTER_ITEMS then
			cardText(card.body, {
				Name = "Plus",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(x + 116 + 11, 166),
				Size = UDim2.fromOffset(30, 34),
				Text = "+",
			}, 34, 4, Theme.Gradients.Gold)
		end
	end
	local best = cardText(card.body, {
		Name = "Best",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(694, 58),
		Size = UDim2.fromOffset(236, 46),
		Rotation = 7,
		Text = TEXT.Best,
	}, 40, 4.5, Theme.Gradients.Gold)
	card.best = best
	card.button = priceButton(card.body, Vector2.new(240, 80), { position = UDim2.fromOffset(700, h - 18), textSize = 44, radius = 22 })
	card.timer = timer
	win.shop.onPrice("Product", "StarterPack", function()
		card.button.setText(win.shop.priceText("Product", "StarterPack"))
	end)
	card.button.Activated:Connect(function()
		Sounds.play("Button")
		win.shop.buy("Product", "StarterPack", nil, card.button)
	end)
	win.starter = card
	return card
end

----------------------------------------------------------------- Reklama za nagrodę
local function adCard(win, parent, order)
	local size = Vector2.new(L.ContentW, L.AdH)
	local card = makeCard(win, parent, size, Theme.Gradients.Ad, { name = "FreeBoost", order = order, kind = "Ad", shineWidth = 140, hoverScale = 1.015, gradientRotation = 0 })
	local h = size.Y - L.Edge
	cardArt(card, "Ad", 96, UDim2.fromOffset(78, h / 2))
	cardText(card.body, {
		Name = "FreeTag",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(46, 24),
		Size = UDim2.fromOffset(92, 36),
		Rotation = -14,
		Text = TEXT.FreeTag,
		ZIndex = 9,
	}, 32, 4, Theme.Gradients.Gold)
	cardText(card.body, {
		Name = "Title",
		Position = UDim2.fromOffset(146, 14),
		Size = UDim2.fromOffset(440, 48),
		Text = TEXT.Free,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, 44, 4.5)
	card.desc = cardText(card.body, {
		Name = "Desc",
		Position = UDim2.fromOffset(148, 64),
		Size = UDim2.fromOffset(450, 34),
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
	}, 23, 3)
	card.button = priceButton(card.body, Vector2.new(214, 62), { name = "Watch", anchor = Vector2.new(1, 0.5), position = UDim2.new(1, -24, 0, h / 2), colors = Theme.Gradients.Gold, textSize = 32 })
	card.holder.Visible = false
	win.ad = card
	return card
end

----------------------------------------------------------------- Boosty
-- Kafelek jednego czasu (np. 15 MIN) z ceną. Najlepsza cena za minutę (bestDeal) dostaje złote
-- tło, złotą obwódkę i wstążkę BEST DEAL na górnej krawędzi.
local OPTION_TOP = 112
local OPTION_H = 112
local function boostOption(win, card, option, x, width)
	local tile = new("Frame", {
		Name = option.key,
		Position = UDim2.fromOffset(x, OPTION_TOP),
		Size = UDim2.fromOffset(width, OPTION_H),
		BackgroundColor3 = Theme.White,
		BorderSizePixel = 0,
		ZIndex = 7,
		Parent = card.body,
	})
	Kit.corner(tile, 18)
	local stroke = Kit.stroke(tile, 3.5, Enum.ApplyStrokeMode.Border)
	local gradient = Kit.gradient(tile, Theme.Gradients.Panel, 90)
	Kit.text(tile, {
		Name = "Time",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 16),
		Size = UDim2.new(1, -16, 0, 32),
		Text = option.label,
		TextColor3 = Theme.Dark,
		ZIndex = 8,
	}, { maxSize = 28, stroke = 0 })
	local button = priceButton(tile, Vector2.new(width - 22, 46), { position = UDim2.new(0.5, 0, 1, -8), textSize = 28, radius = 14, zIndex = 9 })
	-- wstążka nad kafelkiem (w karcie, żeby była nad opisem i kafelkiem)
	local tag = ribbon(card.body, TEXT.BestDeal, Vector2.new(128, 30), UDim2.fromOffset(x + width / 2, OPTION_TOP), -3, Theme.Gradients.Red, 12)
	tag.Visible = false
	local entry = { option = option, button = button, tag = tag, tile = tile, stroke = stroke, gradient = gradient }
	win.shop.onPrice("Product", option.key, function()
		button.setText(win.shop.priceText("Product", option.key))
		if card.bestDeal ~= nil then
			card.bestDeal()
		end
	end)
	button.Activated:Connect(function()
		Sounds.play("Button")
		win.shop.buy("Product", option.key, nil, button)
	end)
	return entry
end

local function boostCard(win, parent, group, width, order)
	local size = Vector2.new(width, L.BoostH)
	local card = makeCard(win, parent, size, group.colors, { name = "Boost" .. group.name, order = order, kind = group.art, weight = 1.5, shineWidth = 140, hoverScale = 1.015 })
	local h = size.Y - L.Edge
	local artX = 96
	cardRays(card, UDim2.fromOffset(artX, h / 2), 170, false)
	cardArt(card, group.art, 150, UDim2.fromOffset(artX, h / 2))
	cardText(card.body, {
		Name = "Title",
		Position = UDim2.fromOffset(196, 12),
		Size = UDim2.fromOffset(width - 214, 46),
		Text = group.title,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, 42, 4.5)
	local desc = group.desc
	if group.note ~= nil then
		desc = desc .. " · " .. group.note
	end
	cardText(card.body, {
		Name = "Desc",
		Position = UDim2.fromOffset(198, 58),
		Size = UDim2.fromOffset(width - 218, 30),
		Text = desc,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, 21, 3)
	local count = #group.options
	local gap = 12
	local optionW = math.floor((width - 196 - 18 - gap * (count - 1)) / count)
	card.options = {}
	for i, option in ipairs(group.options) do
		table.insert(card.options, boostOption(win, card, option, 196 + (i - 1) * (optionW + gap), optionW))
	end
	-- BEST DEAL: najniższa cena za minutę (z cen regionalnych), tylko gdy wyraźnie najniższa
	function card.bestDeal()
		local bestIndex, bestValue, second = nil, math.huge, math.huge
		for i, entry in ipairs(card.options) do
			local value = win.shop.price("Product", entry.option.key) / entry.option.minutes
			if value < bestValue then
				second = bestValue
				bestValue = value
				bestIndex = i
			elseif value < second then
				second = value
			end
		end
		for i, entry in ipairs(card.options) do
			local best = (i == bestIndex and bestValue < second * 0.97)
			entry.tag.Visible = best
			local colors = Theme.Gradients.Panel
			if best then
				colors = { Color3.fromRGB(255, 246, 196), Color3.fromRGB(255, 214, 92) }
			end
			entry.gradient.Color = ColorSequence.new(colors[1], colors[2])
			entry.stroke.Color = best and Color3.fromRGB(120, 60, 0) or Theme.Outline
			entry.stroke.Thickness = best and 4.5 or 3.5
		end
	end
	card.bestDeal()
	return card
end

local function sellNowCard(win, parent, width, order)
	local info = Catalog.SELL_NOW
	local size = Vector2.new(width, L.BoostH)
	local card = makeCard(win, parent, size, info.colors, { name = info.key, order = order, kind = info.art })
	local h = size.Y - L.Edge
	cardRays(card, UDim2.fromOffset(width / 2, 56), 140, false)
	cardArt(card, info.art, 90, UDim2.fromOffset(width / 2, 56))
	cardText(card.body, {
		Name = "Title",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 100),
		Size = UDim2.new(1, -24, 0, 38),
		Text = info.name,
	}, 36, 4)
	cardText(card.body, {
		Name = "Desc",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 138),
		Size = UDim2.new(1, -24, 0, 22),
		Text = info.desc,
	}, 18, 3)
	card.button = priceButton(card.body, Vector2.new(width - 56, 48), { position = UDim2.new(0.5, 0, 0, h - 10), textSize = 28 })
	win.shop.onPrice("Product", info.key, function()
		card.button.setText(win.shop.priceText("Product", info.key))
	end)
	card.button.Activated:Connect(function()
		Sounds.play("Button")
		win.shop.buy("Product", info.key, nil, card.button)
	end)
	return card
end

----------------------------------------------------------------- Zakładki
local function makeTabs(win, parent)
	win.tabs = {}
	for i, tab in ipairs(TABS) do
		local button = Kit.button(parent, {
			name = "Tab" .. tab.key,
			size = L.Tab,
			colors = Theme.Gradients.Tab,
			radius = 24,
			edge = 6,
			position = UDim2.fromOffset(L.RailX, L.RailTop + (i - 1) * (L.Tab.Y + 6 + L.TabGap)),
			sound = false,
		})
		button.holder.ZIndex = 6
		Icons.make(tab.icon, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0, 38),
			Size = UDim2.fromOffset(56, 56),
			ZIndex = 5,
			Parent = button.face,
		})
		Kit.text(button.face, {
			Name = "Label",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -6),
			Size = UDim2.new(1, -16, 0, 30),
			Text = tab.text,
			ZIndex = 6,
		}, { maxSize = 26, stroke = 3.5 })
		local scale = Fx.button(button, 1.05)
		local entry = { key = tab.key, button = button, colors = tab.colors, scale = scale, active = false }
		win.tabs[tab.key] = entry
		button.Activated:Connect(function()
			Sounds.play("ShopTab")
			win.scrollTo(tab.key)
		end)
	end
end

----------------------------------------------------------------- Okno
function ShopWindow.create(hud, shop)
	local win = {
		hud = hud,
		shop = shop,
		cards = {},
		passCards = {},
		sections = {},
		bin = Fx.bin(),
		token = 0,
	}

	-- przyciemnienie świata (pod oknem), z winietą przy krawędziach; łapie kliknięcia w tle
	local backdrop = new("TextButton", {
		Name = "ShopBackdrop",
		Position = UDim2.fromOffset(0, -80),
		Size = UDim2.new(1, 0, 1, 80),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		Visible = false,
		ZIndex = 40,
		Parent = hud.gui,
	})
	win.vignette = {}
	for _, side in ipairs({ { 0, 90 }, { 1, 90 }, { 0, 0 }, { 1, 0 } }) do
		local vertical = side[2] == 90
		local strip = new("Frame", {
			Name = "Vignette",
			AnchorPoint = Vector2.new(vertical and 0 or side[1], vertical and side[1] or 0),
			Position = UDim2.fromScale(vertical and 0 or side[1], vertical and side[1] or 0),
			Size = vertical and UDim2.fromScale(1, 0.22) or UDim2.fromScale(0.16, 1),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = 40,
			Parent = backdrop,
		})
		table.insert(win.vignette, strip)
		local a, b = 0.45, 1
		if side[1] == 1 then
			a, b = 1, 0.45
		end
		new("UIGradient", { Transparency = NumberSequence.new(a, b), Rotation = side[2], Parent = strip })
	end
	win.backdrop = backdrop

	local holder = new("Frame", {
		Name = "ShopPanel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 24),
		Size = UDim2.fromOffset(L.Size.X, L.Size.Y),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 41,
		Parent = hud.gui,
	})
	local fit = new("UIScale", { Parent = holder })
	local inner = new("Frame", {
		Name = "Inner",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = holder,
	})
	local pop = new("UIScale", { Parent = inner })
	local shadow = new("Frame", {
		Name = "Edge",
		Position = UDim2.fromOffset(0, 10),
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Outline,
		BorderSizePixel = 0,
		ZIndex = 1,
		Parent = inner,
	})
	Kit.corner(shadow, L.Radius)
	local body = new("Frame", {
		Name = "Body",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.White,
		BorderSizePixel = 0,
		Active = true,
		ZIndex = 2,
		Parent = inner,
	})
	Kit.corner(body, L.Radius)
	Kit.stroke(body, 5, Enum.ApplyStrokeMode.Border)
	Kit.gradient(body, Theme.Gradients.Panel, 90)
	Pattern.fill(body, L.Size, { radius = L.Radius })
	-- szyna z zakładkami: lekko szare tło pod przyciskami
	local rail = new("Frame", {
		Name = "Rail",
		Position = UDim2.fromOffset(12, 14),
		Size = UDim2.new(0, L.Tab.X + 20, 1, -28),
		BackgroundColor3 = Color3.fromRGB(226, 231, 241),
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		ZIndex = 3,
		Parent = inner,
	})
	Kit.corner(rail, 26)
	local railLayer = new("Frame", {
		Name = "Tabs",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 4,
		Parent = inner,
	})
	-- tytuł: koszyk na lewym górnym rogu i napis
	local titleIcon = Icons.make("Shop", {
		Name = "TitleIcon",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(22, -14),
		Size = UDim2.fromOffset(136, 136),
		Rotation = -10,
		ZIndex = 8,
		Parent = inner,
	})
	local titleScale = Fx.scaleOf(titleIcon)
	local title = Kit.text(inner, {
		Name = "Title",
		Position = UDim2.fromOffset(96, -48),
		Size = UDim2.fromOffset(380, 80),
		Text = TEXT.Title,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 8,
	}, { maxSize = 70, stroke = 6 })
	local close = Kit.button(inner, {
		name = "Close",
		size = Vector2.new(70, 70),
		text = "X",
		colors = Theme.Gradients.Red,
		radius = 20,
		textSize = 40,
		textStroke = 4,
		anchor = Vector2.new(0.5, 0.5),
		position = UDim2.new(1, 8, 0, 8),
	})
	close.holder.ZIndex = 9
	Fx.button(close, 1.1)

	local scroll = new("ScrollingFrame", {
		Name = "Scroll",
		Position = UDim2.fromOffset(L.ScrollX, 16),
		Size = UDim2.new(1, -L.ScrollX - 10, 1, -32),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 9,
		ScrollBarImageColor3 = Theme.Muted,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ZIndex = 3,
		Parent = inner,
	})
	new("UIListLayout", {
		Padding = UDim.new(0, L.Gap),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = scroll,
	})
	new("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 24), PaddingRight = UDim.new(0, 12), Parent = scroll })
	win.holder = holder
	win.scroll = scroll

	-- OFFERS
	sectionHeader(win, scroll, "Offers", TEXT.OffersHeader, "Gift", 10)
	starterHero(win, scroll, 11)
	adCard(win, scroll, 12)
	-- PASSES: dwa wyróżnione i reszta w siatce 3×3
	sectionHeader(win, scroll, "Passes", TEXT.PassesHeader, "Crown", 20)
	local featured = new("Frame", {
		Name = "Featured",
		LayoutOrder = 21,
		Size = UDim2.fromOffset(L.ContentW, L.FeatureH),
		BackgroundTransparency = 1,
		Parent = scroll,
	})
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, L.Gap), SortOrder = Enum.SortOrder.LayoutOrder, Parent = featured })
	local passGrid = new("Frame", {
		Name = "Gamepasses",
		LayoutOrder = 22,
		Size = UDim2.fromOffset(L.ContentW, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = scroll,
	})
	new("UIGridLayout", {
		CellSize = UDim2.fromOffset(L.Card.X, L.Card.Y),
		CellPadding = UDim2.fromOffset(L.Gap, L.Gap),
		FillDirectionMaxCells = 3,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = passGrid,
	})
	for i, key in ipairs(Robux.PassOrder) do
		if Catalog.PASSES[key] ~= nil and Robux.Gamepasses[key] ~= nil then
			if Catalog.FEATURED[key] then
				featurePassCard(win, featured, key, i)
			else
				gridPassCard(win, passGrid, key, i)
			end
		end
	end
	-- BOOSTS
	sectionHeader(win, scroll, "Boosts", TEXT.BoostsHeader, "Boost", 30)
	local groups = Catalog.BOOST_GROUPS
	boostCard(win, scroll, groups[1], L.ContentW, 31)
	local row = new("Frame", {
		Name = "BoostRow",
		LayoutOrder = 32,
		Size = UDim2.fromOffset(L.ContentW, L.BoostH),
		BackgroundTransparency = 1,
		Parent = scroll,
	})
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, L.Gap), SortOrder = Enum.SortOrder.LayoutOrder, Parent = row })
	local sellW = 268
	boostCard(win, row, groups[2], L.ContentW - sellW - L.Gap, 1)
	sellNowCard(win, row, sellW, 2)
	makeTabs(win, railLayer)

	------------------------------------------------------------- Zakładki i przewijanie
	local order = { "Offers", "Passes", "Boosts" }
	-- Położenia z Absolute* są w pikselach ekranu, a CanvasPosition w pikselach płótna (bez UIScale okna).
	local function unit()
		local k = fit.Scale * pop.Scale
		if k <= 0 then
			return 1
		end
		return k
	end
	local function sectionTop(key)
		local section = win.sections[key]
		return (section.header.AbsolutePosition.Y - scroll.AbsolutePosition.Y) / unit() + scroll.CanvasPosition.Y
	end
	local function setActive(key, animate)
		for k, tab in pairs(win.tabs) do
			local on = k == key
			if on ~= tab.active then
				tab.active = on
				if on then
					tab.button.setColors(tab.colors)
					tab.button.holder.Position = UDim2.fromOffset(L.RailX + 8, tab.button.holder.Position.Y.Offset)
					if animate then
						Fx.bump(tab.scale, 1.14, 0.35)
					end
				else
					tab.button.setColors(Theme.Gradients.Tab)
					tab.button.holder.Position = UDim2.fromOffset(L.RailX, tab.button.holder.Position.Y.Offset)
				end
			end
		end
		win.activeTab = key
	end
	local scrolling = nil
	function win.scrollTo(key)
		local section = win.sections[key]
		if section == nil or not section.visible then
			return
		end
		local maxY = math.max(0, (scroll.AbsoluteCanvasSize.Y - scroll.AbsoluteWindowSize.Y) / unit())
		local y = math.clamp(sectionTop(key) - 6, 0, maxY)
		if scrolling ~= nil then
			scrolling:Cancel()
		end
		setActive(key, true)
		scrolling = Fx.tween(scroll, 0.5, { CanvasPosition = Vector2.new(0, y) }, Style.Quint, Dir.Out)
		Fx.bump(section.scale, 1.12, 0.4)
	end
	scroll:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
		if not holder.Visible then
			return
		end
		local current = order[1]
		for _, key in ipairs(order) do
			local section = win.sections[key]
			if section.visible and sectionTop(key) <= scroll.CanvasPosition.Y + 80 then
				current = key
			end
		end
		if current ~= win.activeTab then
			setActive(current, true)
		end
	end)

	------------------------------------------------------------- Dopasowanie do ekranu
	local function updateFit()
		local camera = Workspace.CurrentCamera
		local view = (camera and camera.ViewportSize) or Theme.BaseSize
		local inset = GuiService:GetGuiInset()
		local s = math.min((view.X - 24) / L.Fit.X, (view.Y - inset.Y - 12) / L.Fit.Y)
		local hudScale = math.min(view.X / Theme.BaseSize.X, view.Y / Theme.BaseSize.Y)
		s = math.min(s, math.clamp(hudScale, Theme.MinScale, Theme.MaxScale))
		fit.Scale = math.max(0.35, s)
		-- tytuł wystaje nad okno, więc okno stoi trochę niżej niż środek ekranu
		win.baseY = math.floor(30 * fit.Scale)
		if holder.Visible and not win.closing then
			holder.Position = UDim2.new(0.5, 0, 0.5, win.baseY)
		end
	end
	updateFit()
	if Workspace.CurrentCamera ~= nil then
		Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateFit)
	end

	------------------------------------------------------------- Ruch w tle (tylko przy otwartym oknie)
	local function visibleCard(card)
		if not card.holder.Visible then
			return false
		end
		local top = scroll.AbsolutePosition.Y
		local bottom = top + scroll.AbsoluteWindowSize.Y
		local y = card.holder.AbsolutePosition.Y
		return y + card.holder.AbsoluteSize.Y > top and y < bottom
	end
	local function dropMini(card)
		local mini = ShopArt.mini(card.kind)
		local size = math.random(24, 36)
		local x = 0.1 + math.random() * 0.8
		mini.AnchorPoint = Vector2.new(0.5, 0.5)
		mini.Size = UDim2.fromOffset(size, size)
		mini.Position = UDim2.new(x, 0, 0, -size)
		mini.Rotation = math.random(-40, 40)
		mini.ZIndex = 2
		ShopArt.setFade(mini, 1)
		mini.Parent = card.fall
		card.drops = card.drops + 1
		win.drops = win.drops + 1
		local t = 4.5 + math.random() * 2.5
		Fx.tween(mini, t, { Position = UDim2.new(x + (math.random() - 0.5) * 0.15, 0, 1, size), Rotation = mini.Rotation + math.random(-170, 170) }, Style.Linear, Dir.Out)
		local goal = { ImageTransparency = 0.55 }
		local hidden = { ImageTransparency = 1 }
		if mini:IsA("TextLabel") then
			goal = { TextTransparency = 0.55 }
			hidden = { TextTransparency = 1 }
		end
		Fx.tween(mini, 0.8, goal, Style.Quad, Dir.Out)
		Fx.after(t - 0.9, function()
			Fx.tween(mini, 0.9, hidden, Style.Quad, Dir.In)
		end)
		task.delay(t, function()
			card.drops = math.max(0, card.drops - 1)
			win.drops = math.max(0, win.drops - 1)
			mini:Destroy()
		end)
	end
	local function startAmbient(token)
		local bin = win.bin
		win.drops = 0
		for _, card in ipairs(win.cards) do
			if card.art ~= nil then
				card.art.play(bin)
			end
			if card.rays ~= nil then
				local base = card.rays.Rotation
				bin.add(function()
					card.rays.Rotation = base
				end)
				bin.add(Fx.spin(card.rays, 36))
			end
		end
		if win.starter ~= nil then
			for i, item in ipairs(win.starter.items) do
				item.art.play(bin)
				local base = item.tile.Position
				bin.add(function()
					item.tile.Position = base
				end)
				bin.add(Fx.loop(item.tile, 0.9, { Position = base + UDim2.fromOffset(0, -6) }, Style.Sine, (i - 1) * 0.22))
			end
			local bestScale = Fx.scaleOf(win.starter.best)
			bin.add(function()
				bestScale.Scale = 1
			end)
			bin.add(Fx.loop(bestScale, 0.6, { Scale = 1.08 }, Style.Sine))
		end
		local baseRot = titleIcon.Rotation
		bin.add(function()
			titleIcon.Rotation = baseRot
		end)
		titleIcon.Rotation = baseRot - 4
		bin.add(Fx.loop(titleIcon, 1.4, { Rotation = baseRot + 4 }, Style.Sine))
		bin.add(function()
			for _, card in ipairs(win.cards) do
				for _, child in ipairs(card.fall:GetChildren()) do
					child:Destroy()
				end
				card.drops = 0
			end
		end)
		-- jedna pętla na wszystko: spadające ikony, połysk kart po kolei, połysk ceny Starter Packa
		task.spawn(function()
			local t, nextDrop, nextShine, nextBuyShine, nextSparkle = 0, 0.6, 0.9, 1.4, 0.8
			local turn = 0
			while win.token == token and holder.Visible do
				t = t + AMBIENT.Tick
				if t >= nextDrop then
					nextDrop = t + AMBIENT.DropEvery
					if win.drops < AMBIENT.MaxDrops then
						local pool = {}
						for _, card in ipairs(win.cards) do
							if card.kind ~= nil and card.drops < AMBIENT.MaxDropsPerCard and visibleCard(card) then
								table.insert(pool, card)
							end
						end
						if #pool > 0 then
							dropMini(pool[math.random(1, #pool)])
						end
					end
				end
				if t >= nextShine then
					nextShine = t + AMBIENT.ShineEvery
					local pool = {}
					for _, card in ipairs(win.cards) do
						if visibleCard(card) then
							table.insert(pool, card)
						end
					end
					if #pool > 0 then
						turn = turn % #pool + 1
						pool[turn].shine.play(0.8)
					end
				end
				if t >= nextSparkle then
					nextSparkle = t + AMBIENT.SparkleEvery
					local pool = {}
					for _, card in ipairs(win.cards) do
						if card.art ~= nil and visibleCard(card) then
							table.insert(pool, card)
						end
					end
					if #pool > 0 then
						local card = pool[math.random(1, #pool)]
						local center = card.art.root.Position
						local spread = card.art.root.Size.X.Offset * 0.5
						Fx.sparkle(card.body, center + UDim2.fromOffset(math.random(-100, 100) / 100 * spread, math.random(-100, 100) / 100 * spread), math.random(18, 30), Theme.White, 0, 10)
					end
				end
				if t >= nextBuyShine then
					nextBuyShine = t + AMBIENT.BuyShineEvery
					if win.starter ~= nil and visibleCard(win.starter) then
						win.starter.button.shine.play(0.55)
					end
				end
				task.wait(AMBIENT.Tick)
			end
		end)
	end

	------------------------------------------------------------- Otwieranie i zamykanie
	local blur = Lighting:FindFirstChild("ShopBlur")
	if blur == nil then
		blur = new("BlurEffect", { Name = "ShopBlur", Size = 0, Parent = Lighting })
	end
	local api = { holder = holder }
	function api.isOpen()
		return holder.Visible
	end
	function api.open()
		if holder.Visible and win.closing ~= true then
			return
		end
		win.token = win.token + 1
		local token = win.token
		win.closing = false
		win.bin.clean()
		updateFit()
		scroll.CanvasPosition = Vector2.new(0, 0)
		holder.Visible = true
		backdrop.Visible = true
		Sounds.play("ShopOpen")
		-- świat ciemnieje i się rozmywa, okno wyskakuje z dołu
		backdrop.BackgroundTransparency = 1
		Fx.tween(backdrop, 0.28, { BackgroundTransparency = 0.5 }, Style.Quad, Dir.Out)
		for _, strip in ipairs(win.vignette) do
			strip.BackgroundTransparency = 1
			Fx.tween(strip, 0.4, { BackgroundTransparency = 0 }, Style.Quad, Dir.Out)
		end
		Fx.tween(blur, 0.35, { Size = 14 }, Style.Quad, Dir.Out)
		pop.Scale = 0.55
		Fx.tween(pop, 0.48, { Scale = 1 }, Style.Back, Dir.Out)
		holder.Position = UDim2.new(0.5, 0, 0.5, win.baseY + math.floor(60 * fit.Scale))
		Fx.tween(holder, 0.42, { Position = UDim2.new(0.5, 0, 0.5, win.baseY) }, Style.Quint, Dir.Out)
		titleScale.Scale = 0
		Fx.tween(titleScale, 0.55, { Scale = 1 }, Style.Back, Dir.Out, 0.16)
		local titleStart = title.Position
		title.Position = titleStart + UDim2.fromOffset(-40, 0)
		Fx.tween(title, 0.45, { Position = titleStart }, Style.Back, Dir.Out, 0.12)
		-- zakładki wjeżdżają z lewej (aktywna jest lekko wysunięta)
		setActive(win.firstSection(), false)
		for i, key in ipairs(order) do
			local tab = win.tabs[key]
			local target = tab.button.holder.Position
			tab.button.holder.Position = target + UDim2.fromOffset(-60, 0)
			Fx.tween(tab.button.holder, 0.4, { Position = target }, Style.Back, Dir.Out, 0.12 + i * 0.05)
		end
		-- karty na górze okna (przewinięcie od zera) wjeżdżają po kolei
		local n = 0
		for _, card in ipairs(win.cards) do
			if card.holder.Visible and n < AMBIENT.Cascade then
				n = n + 1
				card.scale.Scale = 0.8
				Fx.tween(card.scale, 0.4, { Scale = 1 }, Style.Back, Dir.Out, 0.12 + n * 0.05)
			end
		end
		for _, key in ipairs(order) do
			Fx.pop(win.sections[key].scale, 0.6, 0.4, 0.1)
		end
		task.delay(0.7, function()
			if win.token == token and holder.Visible then
				if win.starter ~= nil and visibleCard(win.starter) then
					win.starter.shine.play(0.9)
				end
			end
		end)
		startAmbient(token)
	end
	function api.hide()
		if not holder.Visible or win.closing then
			return
		end
		win.closing = true
		win.token = win.token + 1
		local token = win.token
		win.bin.clean()
		Fx.tween(pop, 0.16, { Scale = 0.86 }, Style.Quad, Dir.In)
		Fx.tween(backdrop, 0.22, { BackgroundTransparency = 1 }, Style.Quad, Dir.Out)
		for _, strip in ipairs(win.vignette) do
			Fx.tween(strip, 0.2, { BackgroundTransparency = 1 }, Style.Quad, Dir.Out)
		end
		Fx.tween(blur, 0.25, { Size = 0 }, Style.Quad, Dir.Out)
		task.delay(0.17, function()
			if win.token == token then
				holder.Visible = false
				backdrop.Visible = false
				win.closing = false
			end
		end)
	end
	close.Activated:Connect(api.hide)
	-- klik w przyciemnione tło obok okna też zamyka
	backdrop.Activated:Connect(api.hide)

	------------------------------------------------------------- Stan z Shop.luau
	-- Która część jest pierwsza (OFFERS bywa pusta, gdy nie ma oferty ani reklamy).
	function win.firstSection()
		for _, key in ipairs(order) do
			if win.sections[key].visible then
				return key
			end
		end
		return "Passes"
	end
	local function refreshSections()
		local offers = (win.starter ~= nil and win.starter.holder.Visible) or (win.ad ~= nil and win.ad.holder.Visible)
		win.sections.Offers.visible = offers
		win.sections.Offers.header.Visible = offers
		win.tabs.Offers.button.holder.Visible = offers
		-- zakładki zawsze od góry, bez dziur
		local y = L.RailTop
		for _, key in ipairs(order) do
			local tab = win.tabs[key]
			if tab.button.holder.Visible then
				local x = L.RailX
				if tab.active then
					x = L.RailX + 8
				end
				tab.button.holder.Position = UDim2.fromOffset(x, y)
				y = y + L.Tab.Y + 6 + L.TabGap
			end
		end
	end
	function win.setStarter(seconds)
		local on = seconds > 0
		if win.starter.holder.Visible ~= on then
			win.starter.holder.Visible = on
			refreshSections()
		end
		if on then
			win.starter.timer.Text = string.format(TEXT.StarterEnds, shop.timeText(seconds))
		end
	end
	-- state: { show, left, max, minutes, tester }
	function win.setAd(state)
		local card = win.ad
		if card.holder.Visible ~= state.show then
			card.holder.Visible = state.show
			refreshSections()
		end
		card.desc.Text = string.format(TEXT.FreeDesc, state.minutes or 0, state.left or 0, state.max or 0)
		card.waiting = state.waiting
		if (state.left or 0) <= 0 then
			card.button.setColors(Theme.Gradients.Gray)
			card.button.setText(TEXT.NoAds)
			card.used = true
		else
			card.used = false
			card.button.setColors(Theme.Gradients.Gold)
			if state.waiting then
				card.button.setText("...")
			elseif state.tester then
				card.button.setText(TEXT.WatchTest)
			else
				card.button.setText(TEXT.Watch)
			end
		end
	end
	-- Gamepass kupiony: przycisk OWNED; przy otwartym oknie karta podskakuje i sypie iskrami.
	function win.setOwned(key, owned)
		local card = win.passCards[key]
		if card == nil or card.owned == owned then
			return
		end
		local was = card.owned
		card.owned = owned
		setOwnedButton(card.button, owned, Theme.Gradients.Green)
		if not owned then
			card.button.setText(shop.priceText("Pass", key))
		elseif was == false and holder.Visible then
			Fx.bump(card.scale, 1.12, 0.45)
			for i = 1, 6 do
				Fx.sparkle(card.body, UDim2.fromScale(0.15 + math.random() * 0.7, 0.15 + math.random() * 0.6), math.random(20, 34), Theme.White, i * 0.06, 20)
			end
		end
	end
	function win.passCardOf(key)
		return win.passCards[key]
	end
	refreshSections()
	return api, win
end

return ShopWindow
