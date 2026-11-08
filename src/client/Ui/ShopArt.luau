-- Grafiki produktów w sklepie za Robuxy: kompozycje z obrazków z Toolboxa (Settings.Ui.ShopArt)
-- i ikon gry, np. trzy jajka (Triple Open), jajko z błyskawicą i smugami (Fast Open), dwa łańcuchy
-- na zawiasach (Double Chain), dwa zegarki z tarczą z obrazka „Battleship Diepio”, złotą obręczą
-- i chodzącymi wskazówkami (Double Wrist). Każda grafika to przezroczysta ramka size×size:
--   ShopArt.make(kind, size) → { root, play(bin) }  play uruchamia animację „w spoczynku”
--                                                    (tweeny bez końca idą do bin i stają przy sprzątaniu)
--   ShopArt.mini(kind)       → mała ikona (GuiObject) do tła karty i wybuchów
-- Bez ID obrazka w Settings zamiast niego jest emoji z Icons.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Settings = require(ReplicatedStorage:WaitForChild("Shared").Config.Settings)
local Economy = require(ReplicatedStorage:WaitForChild("Shared").Config.Economy)
local Theme = require(script.Parent.Theme)
local Icons = require(script.Parent.Icons)
local Kit = require(script.Parent.Kit)
local Fx = require(script.Parent.Fx)

local ShopArt = {}

local ART = (Settings.Ui and Settings.Ui.ShopArt) or {}
local new = Fx.new
local Style = Enum.EasingStyle

-- Obrazek z ART (klucz) albo ikona gry/emoji (iconName), wyśrodkowany w punkcie pos (skala rodzica).
local function pic(parent, artKey, iconName, size, pos, rotation, z)
	local image = nil
	if artKey ~= nil then
		image = Fx.image(ART[artKey])
	end
	local obj
	if image ~= nil then
		obj = new("ImageLabel", { Image = image, ScaleType = Enum.ScaleType.Fit, BackgroundTransparency = 1 })
	else
		obj = Icons.make(iconName, {})
	end
	obj.Name = artKey or iconName
	obj.AnchorPoint = Vector2.new(0.5, 0.5)
	obj.Position = UDim2.fromScale(pos.X, pos.Y)
	obj.Size = UDim2.fromScale(size, size)
	obj.Rotation = rotation or 0
	obj.ZIndex = z or 3
	obj.Parent = parent
	return obj
end

local function frame(parent, name, size, pos, z)
	return new("Frame", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(pos.X, pos.Y),
		Size = UDim2.fromScale(size.X, size.Y),
		BackgroundTransparency = 1,
		ZIndex = z or 3,
		Parent = parent,
	})
end

local function circle(parent, name, size, pos, color, transparency, z)
	local c = new("Frame", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(pos.X, pos.Y),
		Size = UDim2.fromScale(size, size),
		BackgroundColor3 = color or Theme.White,
		BackgroundTransparency = transparency or 0,
		BorderSizePixel = 0,
		ZIndex = z or 3,
		Parent = parent,
	})
	new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = c })
	return c
end

-- Złoty napis („x3”, „+2”…) z obrysem, lekko obrócony.
local function badge(parent, text, size, pos, rotation, z, colors)
	return Kit.text(parent, {
		Name = "Badge",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(pos.X, pos.Y),
		Size = UDim2.fromScale(size.X, size.Y),
		Rotation = rotation or 0,
		Text = text,
		ZIndex = z or 6,
	}, { maxSize = 200, stroke = 4, gradient = colors or Theme.Gradients.Gold })
end

-- Wskazówka zegara obracana wokół środka tarczy: ramka-oś (środek = oś obrotu), a w niej pasek
-- od środka w górę. Zwraca oś (obracaj jej Rotation).
local function hand(parent, length, width, color, rotation, z)
	local axis = new("Frame", {
		Name = "Hand",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(2 * length, 2 * length),
		Rotation = rotation or 0,
		BackgroundTransparency = 1,
		ZIndex = z,
		Parent = parent,
	})
	local bar = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.56),
		Size = UDim2.new(width / (2 * length), 0, 0.56, 0),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		ZIndex = z,
		Parent = axis,
	})
	new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = bar })
	return axis
end

-- Zegarek z obrazka „Battleship Diepio”: obrazek obrócony tak, że szare kawałki są paskiem, na
-- niebieskiej tarczy złota obręcz, cztery kreski, dwie wskazówki i błysk. px = rozmiar w pikselach
-- bazowych (grubość obręczy). Zwraca { root, minute, hour }.
local function watch(parent, size, pos, rotation, z, px)
	local root = frame(parent, "Watch", Vector2.new(size, size), pos, z)
	root.Rotation = rotation or 0
	local image = Fx.image(ART.Watch)
	local face = ART.WatchFace or 0.56
	if image ~= nil then
		new("ImageLabel", {
			Name = "Strap",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			Rotation = ART.WatchRotation or 45,
			Image = image,
			ScaleType = Enum.ScaleType.Fit,
			BackgroundTransparency = 1,
			ZIndex = z,
			Parent = root,
		})
	else
		-- bez obrazka: pasek z dwóch ciemnych prostokątów i niebieska tarcza
		for _, y in ipairs({ 0.16, 0.84 }) do
			local strap = new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, y),
				Size = UDim2.fromScale(0.34, 0.36),
				BackgroundColor3 = Color3.fromRGB(120, 124, 136),
				BorderSizePixel = 0,
				ZIndex = z,
				Parent = root,
			})
			new("UICorner", { CornerRadius = UDim.new(0, 6), Parent = strap })
		end
		circle(root, "Face", face, Vector2.new(0.5, 0.5), Color3.fromRGB(40, 170, 230), 0, z)
	end
	local dial = circle(root, "Dial", face, Vector2.new(0.5, 0.5), Theme.White, 1, z)
	new("UIStroke", { Thickness = math.max(2, (px or 100) * size * 0.045), Color = Theme.GoldText, Parent = dial })
	for i = 0, 3 do
		local a = math.rad(i * 90)
		new("Frame", {
			Name = "Tick",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5 + math.sin(a) * 0.39, 0.5 - math.cos(a) * 0.39),
			Size = UDim2.fromScale(0.06, 0.06),
			BackgroundColor3 = Theme.White,
			BorderSizePixel = 0,
			ZIndex = z,
			Parent = dial,
		})
	end
	local hour = hand(dial, 0.26, 0.085, Theme.Outline, 60, z)
	local minute = hand(dial, 0.38, 0.06, Theme.Outline, 200, z)
	circle(dial, "Pin", 0.12, Vector2.new(0.5, 0.5), Theme.GoldText, 0, z)
	circle(dial, "Glare", 0.26, Vector2.new(0.33, 0.3), Theme.White, 0.55, z)
	return { root = root, minute = minute, hour = hour }
end

-- Zegar z chodzącą wskazówką: znak „na czas” przy boostach (biała tarcza z ciemnym obrysem).
local function clockBadge(parent, size, pos, z)
	local c = circle(parent, "Clock", size, pos, Theme.White, 0, z)
	new("UIStroke", { Thickness = 3.5, Color = Theme.Outline, Parent = c })
	hand(c, 0.26, 0.11, Theme.Outline, 300, z)
	local minute = hand(c, 0.36, 0.08, Theme.BadgeRed, 0, z)
	circle(c, "Pin", 0.16, Vector2.new(0.5, 0.5), Theme.Outline, 0, z)
	return minute
end

-- Kropki na okręgu (obracane razem): ruch „w kółko” przy Auto Sell i teleporcie.
local function orbit(parent, count, radius, dot, color, transparency, z)
	local holder = frame(parent, "Orbit", Vector2.new(1, 1), Vector2.new(0.5, 0.5), z)
	local ring = circle(holder, "Ring", radius * 2, Vector2.new(0.5, 0.5), color, 1, z)
	new("UIStroke", { Thickness = 3, Color = color or Theme.White, Transparency = 0.55, Parent = ring })
	for i = 1, count do
		local a = (i - 1) / count * math.pi * 2
		circle(holder, "Dot", dot * (0.7 + 0.3 * ((i % 3) / 2)), Vector2.new(0.5 + math.cos(a) * radius, 0.5 + math.sin(a) * radius), color, transparency, z)
	end
	return holder
end

----------------------------------------------------------------- Kompozycje
-- Każda funkcja dostaje (root, anim, px) i dokłada obrazki; anim(fn) dopisuje animację, która
-- dostaje bin i sama dodaje do niego reset (najpierw) i tweeny (potem).
local BUILD = {}

-- kołysanie wokół podstawowego obrotu: od base-amount do base+amount i z powrotem
local function rock(anim, obj, amount, period, delay)
	anim(function(bin)
		local base = obj.Rotation
		bin.add(function()
			obj.Rotation = base
		end)
		obj.Rotation = base - amount
		bin.add(Fx.loop(obj, period / 2, { Rotation = base + amount }, Style.Sine, delay))
	end)
end

local function pulse(anim, obj, amount, period, delay)
	anim(function(bin)
		local s = Fx.scaleOf(obj)
		bin.add(function()
			s.Scale = 1
		end)
		bin.add(Fx.loop(s, period / 2, { Scale = 1 + amount }, Style.Sine, delay))
	end)
end

local function bob(anim, obj, dy, period, delay)
	anim(function(bin)
		local base = obj.Position
		bin.add(function()
			obj.Position = base
		end)
		bin.add(Fx.loop(obj, period / 2, { Position = base + UDim2.fromScale(0, -dy) }, Style.Sine, delay))
	end)
end

local function spin(anim, obj, period, delay)
	anim(function(bin)
		local base = obj.Rotation
		bin.add(function()
			obj.Rotation = base
		end)
		bin.add(Fx.spin(obj, period))
	end)
end

function BUILD.TwoXLP(root, anim)
	Fx.glow(root, UDim2.fromScale(0.5, 0.5), 0, Theme.GoldText, 0.55, 1).Size = UDim2.fromScale(0.95, 0.95)
	local twoX = pic(root, "TwoX", "Boost", 0.9, Vector2.new(0.5, 0.5), -4, 3)
	pulse(anim, twoX, 0.06, 1.3)
	rock(anim, twoX, 5, 2.6)
end

function BUILD.Boost2xLP(root, anim)
	local twoX = pic(root, "TwoX", "Boost", 0.84, Vector2.new(0.45, 0.46), -6, 3)
	pulse(anim, twoX, 0.06, 1.1)
	local minute = clockBadge(root, 0.36, Vector2.new(0.79, 0.78), 5)
	spin(anim, minute, 3)
end

function BUILD.AutoSell(root, anim)
	local ring = orbit(root, 9, 0.44, 0.075, Theme.White, 0.25, 2)
	spin(anim, ring, 7)
	local cash = pic(root, nil, "Sell", 0.74, Vector2.new(0.5, 0.5), -8, 3)
	rock(anim, cash, 6, 1.8)
	pulse(anim, cash, 0.05, 1.2)
end

function BUILD.BoostAutoSell(root, anim)
	local cash = pic(root, nil, "Sell", 0.74, Vector2.new(0.45, 0.46), -8, 3)
	rock(anim, cash, 5, 1.8)
	local minute = clockBadge(root, 0.36, Vector2.new(0.79, 0.78), 5)
	spin(anim, minute, 3)
end

function BUILD.AutoClick(root, anim)
	-- czubek kursora (z lewej u góry obrazka) puszcza fale jak przy kliknięciu
	local tip = Vector2.new(0.36, 0.34)
	for i = 1, 2 do
		local ring = circle(root, "Ripple", 0.1, tip, Theme.White, 1, 2)
		local stroke = new("UIStroke", { Thickness = 4, Color = Theme.White, Transparency = 0, Parent = ring })
		anim(function(bin)
			bin.add(function()
				ring.Size = UDim2.fromScale(0.1, 0.1)
				stroke.Transparency = 0
			end)
			local delay = (i - 1) * 0.45
			bin.add(Fx.tween(ring, 0.9, { Size = UDim2.fromScale(0.62, 0.62) }, Style.Quad, Enum.EasingDirection.Out, delay, -1, false))
			bin.add(Fx.tween(stroke, 0.9, { Transparency = 1 }, Style.Quad, Enum.EasingDirection.In, delay, -1, false))
		end)
	end
	local cursor = pic(root, nil, "Click", 0.72, Vector2.new(0.56, 0.57), 0, 3)
	pulse(anim, cursor, -0.08, 0.45)
end

function BUILD.Verified(root, anim)
	Fx.glow(root, UDim2.fromScale(0.5, 0.5), 0, Theme.White, 0.6, 1).Size = UDim2.fromScale(0.95, 0.95)
	local check = pic(root, nil, "Verified", 0.82, Vector2.new(0.5, 0.5), 0, 3)
	rock(anim, check, 7, 2.2)
	pulse(anim, check, 0.05, 1.1)
	local b = badge(root, "+10%", Vector2.new(0.52, 0.28), Vector2.new(0.8, 0.16), 10, 6)
	pulse(anim, b, 0.1, 0.9)
end

function BUILD.PetSlots(root, anim)
	local paw = pic(root, nil, "Pets", 0.74, Vector2.new(0.44, 0.54), -6, 3)
	bob(anim, paw, 0.05, 1.2)
	rock(anim, paw, 5, 2.4)
	local b = badge(root, "+2", Vector2.new(0.46, 0.36), Vector2.new(0.8, 0.22), 10, 6)
	pulse(anim, b, 0.12, 0.8)
end

function BUILD.TripleOpen(root, anim)
	local left = pic(root, "Egg", "Egg", 0.5, Vector2.new(0.25, 0.46), -14, 2)
	local right = pic(root, "Egg", "Egg", 0.5, Vector2.new(0.75, 0.46), 14, 2)
	local mid = pic(root, "Egg", "Egg", 0.64, Vector2.new(0.5, 0.57), 0, 3)
	rock(anim, left, 7, 0.9, 0)
	rock(anim, mid, 7, 0.9, 0.3)
	rock(anim, right, 7, 0.9, 0.6)
	local b = badge(root, "x3", Vector2.new(0.4, 0.32), Vector2.new(0.84, 0.16), 12, 6)
	pulse(anim, b, 0.12, 0.8)
end

function BUILD.FastOpen(root, anim)
	-- smugi pędu z lewej strony jajka
	for i, y in ipairs({ 0.38, 0.52, 0.66 }) do
		local line = new("Frame", {
			Name = "Streak",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.2, y),
			Size = UDim2.fromScale(0.26 - 0.04 * (i % 2), 0.055),
			BackgroundColor3 = Theme.White,
			BackgroundTransparency = 0.15,
			BorderSizePixel = 0,
			ZIndex = 2,
			Parent = root,
		})
		new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = line })
		anim(function(bin)
			bin.add(function()
				line.Position = UDim2.fromScale(0.2, y)
				line.BackgroundTransparency = 0.15
			end)
			local delay = (i - 1) * 0.13
			bin.add(Fx.tween(line, 0.42, { Position = UDim2.fromScale(0.04, y), BackgroundTransparency = 1 }, Style.Linear, Enum.EasingDirection.Out, delay, -1, false))
		end)
	end
	local egg = pic(root, "Egg", "Egg", 0.64, Vector2.new(0.46, 0.5), -8, 3)
	rock(anim, egg, 5, 0.22)
	local bolt = pic(root, "Bolt", "Boost", 0.5, Vector2.new(0.74, 0.6), 14, 4)
	pulse(anim, bolt, 0.14, 0.5)
end

function BUILD.TwoXBag(root, anim)
	local bag = pic(root, nil, "Bag", 0.74, Vector2.new(0.44, 0.54), -6, 3)
	bob(anim, bag, 0.05, 1.3)
	local b = badge(root, "2x", Vector2.new(0.46, 0.36), Vector2.new(0.8, 0.22), 10, 6)
	pulse(anim, b, 0.12, 0.8)
end

function BUILD.Teleport(root, anim)
	Fx.glow(root, UDim2.fromScale(0.5, 0.5), 0, Color3.fromRGB(255, 120, 230), 0.7, 1).Size = UDim2.fromScale(1.02, 1.02)
	local ring = orbit(root, 10, 0.46, 0.07, Theme.White, 0.2, 2)
	spin(anim, ring, 4.5)
	local portal = pic(root, "Teleport", "Teleport", 0.8, Vector2.new(0.5, 0.5), 0, 3)
	pulse(anim, portal, 0.06, 0.9)
	rock(anim, portal, 8, 3)
end

-- łańcuch na zawiasie: oś obrotu w górnym końcu łańcucha (obraca się cała ramka-oś)
local function hangingChain(root, pivot, size, rotation, tint, z)
	local axis = frame(root, "ChainAxis", Vector2.new(2 * size, 2 * size), pivot, z)
	axis.Rotation = rotation
	local image = Fx.image(ART.Chain)
	local chain
	if image ~= nil then
		chain = new("ImageLabel", { Image = image, ScaleType = Enum.ScaleType.Fit, BackgroundTransparency = 1, ImageColor3 = tint })
	else
		chain = Icons.make("Chain", {})
	end
	chain.Name = "Chain"
	chain.AnchorPoint = Vector2.new(0.5, 0)
	chain.Position = UDim2.fromScale(0.5, 0.5)
	chain.Size = UDim2.fromScale(0.5, 0.5)
	chain.ZIndex = z
	chain.Parent = axis
	return axis
end

function BUILD.DoubleChain(root, anim)
	local back = hangingChain(root, Vector2.new(0.3, 0.04), 0.84, -14, Color3.fromRGB(215, 200, 170), 2)
	local front = hangingChain(root, Vector2.new(0.66, 0.08), 0.88, 10, Theme.White, 3)
	rock(anim, back, 6, 2.6, 0)
	rock(anim, front, 6, 2.2, 0.5)
	local b = badge(root, "x2", Vector2.new(0.4, 0.32), Vector2.new(0.9, 0.16), 10, 6)
	pulse(anim, b, 0.12, 0.8)
end

function BUILD.DoubleWrist(root, anim, px)
	local back = watch(root, 0.62, Vector2.new(0.28, 0.42), -16, 2, px)
	local front = watch(root, 0.74, Vector2.new(0.66, 0.58), 10, 3, px)
	for i, w in ipairs({ back, front }) do
		spin(anim, w.minute, 5 + i)
		spin(anim, w.hour, 60)
		rock(anim, w.root, 4, 2.4 + i * 0.3, i * 0.4)
	end
	local b = badge(root, "x2", Vector2.new(0.4, 0.32), Vector2.new(0.88, 0.16), 10, 6)
	pulse(anim, b, 0.12, 0.8)
end

function BUILD.StarterWatch(root, anim, px)
	local w = watch(root, 0.96, Vector2.new(0.5, 0.5), 8, 3, px)
	spin(anim, w.minute, 6)
	spin(anim, w.hour, 60)
end

function BUILD.StarterPet(root, anim)
	Fx.glow(root, UDim2.fromScale(0.5, 0.5), 0, Color3.fromRGB(190, 110, 255), 0.6, 1).Size = UDim2.fromScale(0.95, 0.95)
	local paw = pic(root, nil, "Pets", 0.82, Vector2.new(0.5, 0.52), -6, 3)
	rock(anim, paw, 5, 2.2)
end

function BUILD.SellNow(root, anim)
	Fx.glow(root, UDim2.fromScale(0.5, 0.5), 0, Theme.GoldText, 0.5, 1).Size = UDim2.fromScale(0.95, 0.95)
	local cash = pic(root, nil, "SellCash", 0.84, Vector2.new(0.5, 0.5), -6, 3)
	bob(anim, cash, 0.04, 1.1)
	rock(anim, cash, 5, 2.4)
end

function BUILD.Ad(root, anim)
	local tv = pic(root, nil, "Ad", 0.84, Vector2.new(0.5, 0.52), -4, 3)
	rock(anim, tv, 6, 1.6)
	pulse(anim, tv, 0.05, 1)
end

function BUILD.PremiumEgg(root, anim)
	Fx.glow(root, UDim2.fromScale(0.5, 0.5), 0, Color3.fromRGB(190, 120, 255), 0.7, 1).Size = UDim2.fromScale(1, 1)
	local egg = pic(root, "Egg", "Egg", 0.8, Vector2.new(0.5, 0.52), -6, 3)
	if egg:IsA("ImageLabel") then
		egg.ImageColor3 = Color3.fromRGB(205, 165, 255)
	end
	rock(anim, egg, 6, 1.2)
	pic(root, nil, "Premium", 0.34, Vector2.new(0.78, 0.22), 12, 5)
end

function BUILD.Starter(root, anim)
	Fx.glow(root, UDim2.fromScale(0.5, 0.5), 0, Theme.GoldText, 0.6, 1).Size = UDim2.fromScale(1, 1)
	local gift = pic(root, nil, "Gift", 0.84, Vector2.new(0.5, 0.52), -6, 3)
	rock(anim, gift, 6, 1.6)
	pulse(anim, gift, 0.06, 1)
end

----------------------------------------------------------------- Zakładka FREE (Etap 11)
local function percent(x)
	return string.format("+%d%%", math.floor(x * 100 + 0.5))
end

-- Klucz przy sekretnych kodach (jak w PS99): obrazek ART.Key, a bez niego klucz z ramek: fioletowe
-- ucho z jasnym oczkiem, trzon i dwa ząbki, z obrysem i połyskiem, przechylony.
function BUILD.Code(root, anim, px)
	Fx.glow(root, UDim2.fromScale(0.5, 0.5), 0, Color3.fromRGB(205, 140, 255), 0.65, 1).Size = UDim2.fromScale(1, 1)
	local key
	if Fx.image(ART.Key) ~= nil then
		key = pic(root, "Key", "Key", 0.92, Vector2.new(0.5, 0.5), -12, 3)
	else
		key = frame(root, "Key", Vector2.new(1, 1), Vector2.new(0.5, 0.5), 3)
		key.Rotation = -35
		local stroke = math.max(3, math.floor((px or 120) / 34))
		local purple = { Color3.fromRGB(222, 160, 255), Color3.fromRGB(122, 48, 236) }
		local function part(name, size, pos, radius, z, colors)
			local f = new("Frame", {
				Name = name,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(pos.X, pos.Y),
				Size = UDim2.fromScale(size.X, size.Y),
				BackgroundColor3 = Theme.White,
				BorderSizePixel = 0,
				ZIndex = z,
				Parent = key,
			})
			new("UICorner", { CornerRadius = radius, Parent = f })
			Kit.stroke(f, stroke, Enum.ApplyStrokeMode.Border)
			Kit.gradient(f, colors or purple, 90)
			return f
		end
		-- ząbki pod trzonem (trzon zakrywa ich górę), trzon pod uchem
		part("Tooth", Vector2.new(0.08, 0.17), Vector2.new(0.74, 0.6), UDim.new(0.3, 0), 3)
		part("Tooth", Vector2.new(0.08, 0.12), Vector2.new(0.87, 0.58), UDim.new(0.3, 0), 3)
		part("Shaft", Vector2.new(0.58, 0.13), Vector2.new(0.65, 0.5), UDim.new(0.5, 0), 4)
		part("Bow", Vector2.new(0.42, 0.42), Vector2.new(0.27, 0.5), UDim.new(0.5, 0), 5)
		part("Hole", Vector2.new(0.17, 0.17), Vector2.new(0.27, 0.5), UDim.new(0.5, 0), 6, { Color3.fromRGB(255, 246, 255), Color3.fromRGB(226, 196, 255) })
		local shine = new("Frame", {
			Name = "Shine",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.19, 0.37),
			Size = UDim2.fromScale(0.1, 0.05),
			Rotation = -42,
			BackgroundColor3 = Theme.White,
			BackgroundTransparency = 0.2,
			BorderSizePixel = 0,
			ZIndex = 7,
			Parent = key,
		})
		new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = shine })
	end
	rock(anim, key, 7, 2.4)
	pulse(anim, key, 0.05, 1.2)
end

function BUILD.Group(root, anim)
	Fx.glow(root, UDim2.fromScale(0.5, 0.5), 0, Color3.fromRGB(150, 220, 255), 0.6, 1).Size = UDim2.fromScale(0.95, 0.95)
	local people = pic(root, "Group", "Group", 0.78, Vector2.new(0.45, 0.55), -6, 3)
	bob(anim, people, 0.04, 1.3)
	rock(anim, people, 4, 2.6)
	local b = badge(root, percent(Economy.Bonuses.Group), Vector2.new(0.6, 0.32), Vector2.new(0.76, 0.18), 10, 6)
	pulse(anim, b, 0.12, 0.8)
end

function BUILD.Friends(root, anim)
	Fx.glow(root, UDim2.fromScale(0.5, 0.5), 0, Color3.fromRGB(255, 170, 220), 0.6, 1).Size = UDim2.fromScale(0.95, 0.95)
	local hands = pic(root, "Friends", "Friends", 0.78, Vector2.new(0.45, 0.55), -6, 3)
	rock(anim, hands, 7, 1.6)
	local b = badge(root, percent(Economy.Bonuses.FriendEach), Vector2.new(0.62, 0.32), Vector2.new(0.75, 0.18), 10, 6)
	pulse(anim, b, 0.12, 0.8)
end

-- Grafika produktu. size = rozmiar w pikselach bazowych; parent i props opcjonalnie (Position…).
function ShopArt.make(kind, size, parent, props)
	local root = new("Frame", {
		Name = "Art",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(size, size),
		BackgroundTransparency = 1,
		ZIndex = 3,
	})
	for key, value in pairs(props or {}) do
		root[key] = value
	end
	local anims = {}
	local function anim(fn)
		table.insert(anims, fn)
	end
	local build = BUILD[kind]
	if build ~= nil then
		build(root, anim, size)
	else
		pic(root, nil, "Gift", 0.8, Vector2.new(0.5, 0.5), 0, 3)
	end
	root.Parent = parent
	local api = { root = root }
	function api.play(bin)
		for _, fn in ipairs(anims) do
			fn(bin)
		end
	end
	return api
end

-- Mała ikona produktu (do tła kart i wybuchów); rozmiar i położenie ustawia wywołujący.
local MINI = {
	TwoXLP = { "TwoX", "Boost" },
	Boost2xLP = { "Bolt", "Boost" },
	AutoSell = { nil, "SellCash" },
	BoostAutoSell = { nil, "SellCash" },
	AutoClick = { nil, "Click" },
	Verified = { nil, "Verified" },
	PetSlots = { nil, "Pets" },
	TripleOpen = { "Egg", "Egg" },
	FastOpen = { "Bolt", "Boost" },
	TwoXBag = { nil, "Bag" },
	Teleport = { "Teleport", "Teleport" },
	DoubleChain = { "Chain", "Chain" },
	DoubleWrist = { nil, "Watch" },
	SellNow = { nil, "SellCash" },
	Starter = { nil, "Gift" },
	Ad = { nil, "Sparkles" },
	Shop = { nil, "Shop" },
	Code = { "Key", "Key" },
	Group = { "Group", "Group" },
	Friends = { "Friends", "Friends" },
}
function ShopArt.mini(kind)
	local entry = MINI[kind] or { nil, "Sparkles" }
	local image = nil
	if entry[1] ~= nil then
		image = Fx.image(ART[entry[1]])
	end
	local obj
	if image ~= nil then
		obj = new("ImageLabel", { Image = image, ScaleType = Enum.ScaleType.Fit, BackgroundTransparency = 1 })
	else
		obj = Icons.make(entry[2], {})
	end
	obj.Name = "Mini"
	return obj
end

-- Złoty Robux (Settings.Ui.ShopArt.Robux) do wybuchu z przycisku z ceną: kwadratowa ramka, a w niej
-- obrazek zwężony do RobuxAspect (obrazek jest rozciągnięty w poziomie). Bez ID znak Robux z czcionki.
local ROBUX_GLYPH = "\238\128\130" -- U+E002
function ShopArt.robux()
	local holder = new("Frame", { Name = "Robux", BackgroundTransparency = 1 })
	local image = Fx.image(ART.Robux)
	if image ~= nil then
		new("ImageLabel", {
			Name = "Image",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(ART.RobuxAspect or 1, 1),
			Image = image,
			ScaleType = Enum.ScaleType.Stretch,
			BackgroundTransparency = 1,
			Parent = holder,
		})
	else
		new("TextLabel", {
			Name = "Glyph",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Font = Theme.Font,
			Text = ROBUX_GLYPH,
			TextScaled = true,
			TextColor3 = Theme.GoldText,
			Parent = holder,
		})
	end
	return holder
end

-- Przezroczystość małej ikony (obrazek albo emoji).
function ShopArt.setFade(obj, transparency)
	if obj:IsA("ImageLabel") then
		obj.ImageTransparency = transparency
	elseif obj:IsA("TextLabel") then
		obj.TextTransparency = transparency
	end
end

return ShopArt
