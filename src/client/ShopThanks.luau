-- Podziękowanie po zakupie za Robuxy. Pokazuje się tylko po potwierdzeniu zakupu przez serwer
-- (Notify „Purchase” po ProcessReceipt albo „PassBought” po PromptGamePassPurchaseFinished
-- z wasPurchased = true), więc anulowany albo nieudany zakup nic nie pokazuje.
--   • duże (gamepass, Starter Pack): świat ciemnieje, za grafiką produktu kręcą się złote promienie
--     i poświata, „THANK YOU!” na złotej wstędze z połyskiem, nazwa i co daje, konfetti i iskry;
--     znika samo po kilku sekundach albo po kliknięciu,
--   • małe (boost, Sell Now, premium jajko po animacji wyklucia): karta wjeżdża z góry i po chwili
--     odjeżdża; kolejne małe podmieniają treść, zamiast się piętrzyć.
-- Kolejne duże czekają w kolejce i trwają krócej, żeby kilka zakupów pod rząd nie męczyło.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local GuiService = game:GetService("GuiService")

local Theme = require(script.Parent.Ui.Theme)
local Kit = require(script.Parent.Ui.Kit)
local Sounds = require(script.Parent.Ui.Sounds)
local Fx = require(script.Parent.Ui.Fx)
local ShopArt = require(script.Parent.Ui.ShopArt)
local State = require(script.Parent.State)
local Catalog = require(script.Parent.ShopCatalog)

local ShopThanks = {}

local TEXT = Catalog.TEXT
local new = Fx.new
local Style = Enum.EasingStyle
local Dir = Enum.EasingDirection

local TIME = {
	Full = 4.2, -- duże podziękowanie samo znika po tylu sekundach
	FullQueued = 2.8, -- …a gdy czeka następne, po tylu
	Compact = 2.8, -- małe
	HintAfter = 1, -- napis „Tap to continue” po tylu sekundach
	BusyCalm = 0.5, -- premium jajko: tyle sekund bez animacji wyklucia przed pokazaniem
}

-- Położenia (piksele bazowe w ramce 900×640) dużego podziękowania: z rzędem rzeczy (Starter Pack)
-- grafika jest mniejsza i wszystko stoi wyżej, żeby „Tap to continue” nie wchodził na kafelki.
local LAYOUT = {
	Plain = { Art = 268, ArtSize = 240, Name = 436, Sub = 486, Hint = 552 },
	Items = { Art = 242, ArtSize = 196, Name = 386, Sub = 432, Items = 512, Hint = 606 },
}

local gui = nil
local hudRef = nil
local queue = {}
local pendingCompact = nil
local showingFull = false
local compact = nil -- aktualnie widoczna mała karta

-- Skala UI jak w HUD; fitSize (piksele bazowe) zmniejsza ją, gdy całość nie mieści się na ekranie
-- (niski ekran telefonu).
local function uiScale(fitSize)
	local camera = Workspace.CurrentCamera
	local view = (camera and camera.ViewportSize) or Theme.BaseSize
	local s = math.clamp(math.min(view.X / Theme.BaseSize.X, view.Y / Theme.BaseSize.Y), Theme.MinScale, Theme.MaxScale)
	if fitSize ~= nil then
		s = math.min(s, (view.X - 20) / fitSize.X, (view.Y - 20) / fitSize.Y)
	end
	return math.max(0.3, s)
end

local function screenCenter()
	return gui.AbsoluteSize / 2
end

-- Czekamy, aż skończy się animacja wyklucia (State.busy przez dłuższą chwilę false).
local function waitCalm()
	task.wait(0.4)
	local calm = 0
	while calm < TIME.BusyCalm do
		task.wait(0.1)
		if State.busy then
			calm = 0
		else
			calm = calm + 0.1
		end
	end
end

local function testTag(parent, position, z)
	local tag = new("Frame", {
		Name = "TestTag",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = position,
		Size = UDim2.fromOffset(190, 34),
		Rotation = 6,
		BackgroundColor3 = Theme.White,
		BorderSizePixel = 0,
		ZIndex = z,
		Parent = parent,
	})
	Kit.corner(tag, 17)
	Kit.stroke(tag, 3, Enum.ApplyStrokeMode.Border)
	Kit.gradient(tag, Theme.Gradients.Cyan, 90)
	Kit.text(tag, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.new(1, -16, 1, -8),
		Text = TEXT.ThanksTest,
		ZIndex = z + 1,
	}, { maxSize = 20, stroke = 2.5 })
	return tag
end

----------------------------------------------------------------- Duże podziękowanie
-- entry: { art, name, sub, items (Starter Pack: lista { art, label }), test }
local function playFull(entry, short)
	local bin = Fx.bin()
	local done = false
	local k = uiScale(Vector2.new(920, 700))
	local backdrop = bin.add(new("TextButton", {
		Name = "ThanksBackdrop",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		ZIndex = 1,
		Parent = gui,
	}))
	local group = bin.add(new("Frame", {
		Name = "Thanks",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(900, 640),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = gui,
	}))
	new("UIScale", { Name = "Fit", Scale = k, Parent = group })
	local inner = new("Frame", {
		Name = "Inner",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = group,
	})
	local pop = Fx.scaleOf(inner)
	group = inner
	local fxLayer = bin.add(new("Frame", {
		Name = "ThanksFx",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 5,
		Parent = gui,
	}))
	local spot = LAYOUT.Plain
	if entry.items ~= nil then
		spot = LAYOUT.Items
	end
	local artCenter = UDim2.fromOffset(450, spot.Art)
	local rays = Fx.rays(group, artCenter, { count = 10, width = 44, length = 330, color = Color3.fromRGB(255, 226, 140), alpha = 0.5, zIndex = 2 })
	local glow = Fx.glow(group, artCenter, 430, Color3.fromRGB(255, 214, 102), 0.65, 2)
	local art = ShopArt.make(entry.art or "Starter", spot.ArtSize, group, { Position = artCenter, ZIndex = 4 })
	-- złota wstęga z napisem THANK YOU! (końce wstęgi pod spodem)
	local banner = new("Frame", {
		Name = "Banner",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(450, 74),
		Size = UDim2.fromOffset(540, 100),
		BackgroundTransparency = 1,
		ZIndex = 6,
		Parent = group,
	})
	for _, side in ipairs({ -1, 1 }) do
		local tail = new("Frame", {
			Name = "Tail",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, side * 262, 0.5, 22),
			Size = UDim2.fromOffset(120, 70),
			Rotation = side * -8,
			BackgroundColor3 = Theme.White,
			BorderSizePixel = 0,
			ZIndex = 6,
			Parent = banner,
		})
		Kit.corner(tail, 16)
		Kit.stroke(tail, 5, Enum.ApplyStrokeMode.Border)
		Kit.gradient(tail, { Color3.fromRGB(255, 176, 30), Color3.fromRGB(214, 112, 0) }, 90)
	end
	local ribbon = new("Frame", {
		Name = "Ribbon",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.White,
		BorderSizePixel = 0,
		ZIndex = 7,
		Parent = banner,
	})
	Kit.corner(ribbon, 30)
	Kit.stroke(ribbon, 5.5, Enum.ApplyStrokeMode.Border)
	Kit.gradient(ribbon, Theme.Gradients.Gold, 90)
	local ribbonShine = Fx.shine(ribbon, { inset = 5, width = 120, strength = 0.85, zIndex = 8 })
	Kit.text(ribbon, {
		Name = "Title",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.new(1, -40, 1, -18),
		Text = TEXT.Thanks,
		ZIndex = 9,
	}, { maxSize = 70, stroke = 5.5 })
	local bannerScale = Fx.scaleOf(banner)
	local name = Kit.text(group, {
		Name = "ItemName",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(450, spot.Name),
		Size = UDim2.fromOffset(700, 62),
		Text = entry.name or "",
		ZIndex = 8,
	}, { maxSize = 56, stroke = 5 })
	local sub = Kit.text(group, {
		Name = "Sub",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(450, spot.Sub),
		Size = UDim2.fromOffset(700, 38),
		Text = entry.sub or "",
		ZIndex = 8,
	}, { maxSize = 34, stroke = 4, gradient = Theme.Gradients.Gold })
	local nameScale = Fx.scaleOf(name)
	local subScale = Fx.scaleOf(sub)
	local items = {}
	if entry.items ~= nil then
		local count = #entry.items
		for i, item in ipairs(entry.items) do
			local tile = new("Frame", {
				Name = "Item" .. i,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(450 + (i - (count + 1) / 2) * 128, spot.Items),
				Size = UDim2.fromOffset(112, 112),
				BackgroundColor3 = Theme.White,
				BorderSizePixel = 0,
				ZIndex = 8,
				Parent = group,
			})
			Kit.corner(tile, 20)
			Kit.stroke(tile, 4, Enum.ApplyStrokeMode.Border)
			Kit.gradient(tile, Theme.Gradients.Panel, 90)
			local a = ShopArt.make(item.art, 62, tile, { Position = UDim2.fromOffset(56, 40), ZIndex = 9 })
			Kit.text(tile, {
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, -5),
				Size = UDim2.new(1, -10, 0, 34),
				Text = item.label,
				TextColor3 = Theme.Dark,
				TextWrapped = true,
				ZIndex = 10,
			}, { maxSize = 17, stroke = 0 })
			table.insert(items, { tile = tile, scale = Fx.scaleOf(tile), art = a })
		end
	end
	local hint = Kit.text(group, {
		Name = "Hint",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(450, spot.Hint),
		Size = UDim2.fromOffset(400, 34),
		Text = TEXT.TapToContinue,
		TextTransparency = 1,
		ZIndex = 8,
	}, { maxSize = 26, stroke = 3 })
	local hintStroke = hint:FindFirstChildOfClass("UIStroke")
	if hintStroke ~= nil then
		hintStroke.Transparency = 1
	end
	if entry.test then
		-- na wstędze, żeby wjeżdżał razem z nią
		testTag(banner, UDim2.new(1, 0, 0, -2), 12)
	end

	-- wejście
	Sounds.play("Purchase")
	Fx.tween(backdrop, 0.3, { BackgroundTransparency = 0.42 }, Style.Quad, Dir.Out)
	pop.Scale = 1
	local raysScale = Fx.scaleOf(rays)
	raysScale.Scale = 0
	Fx.tween(raysScale, 0.55, { Scale = 1 }, Style.Back, Dir.Out)
	bin.add(Fx.spin(rays, 22))
	local glowScale = Fx.scaleOf(glow)
	glowScale.Scale = 0
	Fx.tween(glowScale, 0.45, { Scale = 1 }, Style.Back, Dir.Out, 0.05)
	local artScale = Fx.scaleOf(art.root)
	artScale.Scale = 0
	Fx.tween(artScale, 0.42, { Scale = 1.15 }, Style.Back, Dir.Out, 0.08)
	Fx.after(0.5, function()
		Fx.tween(artScale, 0.25, { Scale = 1 }, Style.Quad, Dir.InOut)
	end)
	art.play(bin)
	bin.add(Fx.loop(art.root, 1.3, { Position = artCenter + UDim2.fromOffset(0, -10) }, Style.Sine, 0.75))
	banner.Position = UDim2.fromOffset(450, -90)
	bannerScale.Scale = 0.6
	Fx.tween(banner, 0.5, { Position = UDim2.fromOffset(450, 74) }, Style.Back, Dir.Out, 0.12)
	Fx.tween(bannerScale, 0.5, { Scale = 1 }, Style.Back, Dir.Out, 0.12)
	nameScale.Scale = 0
	subScale.Scale = 0
	Fx.tween(nameScale, 0.35, { Scale = 1 }, Style.Back, Dir.Out, 0.38)
	Fx.tween(subScale, 0.35, { Scale = 1 }, Style.Back, Dir.Out, 0.48)
	for i, item in ipairs(items) do
		item.scale.Scale = 0
		Fx.tween(item.scale, 0.35, { Scale = 1 }, Style.Back, Dir.Out, 0.55 + i * 0.09)
		item.art.play(bin)
	end
	task.delay(0.28, function()
		if done then
			return
		end
		local center = screenCenter()
		Fx.confetti(fxLayer, center - Vector2.new(0, 40 * k), 40, k, 6)
		for i = 1, 8 do
			local a = math.rad(i * 45 + math.random(-12, 12))
			local d = (150 + math.random(0, 60))
			Fx.sparkle(group, artCenter + UDim2.fromOffset(math.cos(a) * d, math.sin(a) * d * 0.8), math.random(26, 42), Theme.White, i * 0.07, 9)
		end
	end)
	-- połysk wstęgi co chwilę
	task.spawn(function()
		task.wait(0.65)
		while not done do
			ribbonShine.play(0.7)
			task.wait(1.7)
		end
	end)
	task.delay(TIME.HintAfter, function()
		if done then
			return
		end
		Fx.tween(hint, 0.3, { TextTransparency = 0 }, Style.Quad, Dir.Out)
		if hintStroke ~= nil then
			Fx.tween(hintStroke, 0.3, { Transparency = 0 }, Style.Quad, Dir.Out)
		end
		bin.add(Fx.loop(Fx.scaleOf(hint), 0.7, { Scale = 1.08 }, Style.Sine))
	end)

	-- wyjście: po czasie albo po kliknięciu
	local closed = false
	local function close()
		if closed then
			return
		end
		closed = true
		done = true
		Fx.tween(pop, 0.2, { Scale = 0.82 }, Style.Quad, Dir.In)
		Fx.tween(backdrop, 0.24, { BackgroundTransparency = 1 }, Style.Quad, Dir.Out)
		Fx.tween(raysScale, 0.2, { Scale = 0 }, Style.Quad, Dir.In)
		task.wait(0.24)
		bin.clean()
	end
	backdrop.Activated:Connect(function()
		task.spawn(close)
	end)
	local limit = TIME.Full
	if short then
		limit = TIME.FullQueued
	end
	local t = 0
	while not closed and t < limit do
		task.wait(0.1)
		t = t + 0.1
	end
	if not closed then
		close()
	end
	while not done do
		task.wait(0.05)
	end
end

----------------------------------------------------------------- Małe podziękowanie
-- Karta stoi pod podpowiedzią u góry ekranu (w Hud ramka „Hint”: 10 px pod paskiem Robloxa,
-- 60 px wysokości w skali UI), żeby jej nie przykrywać do połowy; ta warstwa ignoruje pasek.
local function compactTop()
	return GuiService:GetGuiInset().Y + math.floor(26 + 60 * uiScale())
end

local function hideCompact(c)
	if c.hiding then
		return
	end
	c.hiding = true
	Fx.tween(c.holder, 0.25, { Position = UDim2.new(0.5, 0, 0, -160) }, Style.Quad, Dir.In)
	task.delay(0.27, function()
		c.bin.clean()
		if compact == c then
			compact = nil
		end
	end)
end

local function fillCompact(c, entry)
	if c.art ~= nil then
		c.art.root:Destroy()
	end
	c.art = ShopArt.make(entry.art or "Starter", 92, c.face, { Position = UDim2.fromOffset(66, 56), ZIndex = 6 })
	c.art.play(c.bin)
	c.line.Text = entry.name or ""
	c.sub.Text = entry.sub or ""
	c.test.Visible = entry.test == true
	c.until_ = os.clock() + TIME.Compact
end

local function showCompact(entry)
	if compact ~= nil and not compact.hiding then
		-- kolejny mały zakup: nowa treść w tej samej karcie i podskok
		fillCompact(compact, entry)
		Fx.bump(compact.scale, 1.08, 0.3)
		Sounds.play("PurchaseSmall")
		return
	end
	local c = { bin = Fx.bin() }
	local holder = c.bin.add(new("Frame", {
		Name = "ThanksCompact",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, -160),
		Size = UDim2.fromOffset(560, 118),
		BackgroundTransparency = 1,
		ZIndex = 20,
		Parent = gui,
	}))
	new("UIScale", { Name = "Fit", Scale = uiScale(Vector2.new(580, 300)), Parent = holder })
	c.holder = holder
	local body = new("Frame", {
		Name = "Body",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 20,
		Parent = holder,
	})
	c.scale = Fx.scaleOf(body)
	local edge = new("Frame", {
		Name = "Edge",
		Position = UDim2.fromOffset(0, 6),
		Size = UDim2.new(1, 0, 1, -6),
		BackgroundColor3 = Theme.Outline,
		BorderSizePixel = 0,
		ZIndex = 20,
		Parent = body,
	})
	Kit.corner(edge, 28)
	local face = new("Frame", {
		Name = "Face",
		Size = UDim2.new(1, 0, 1, -6),
		BackgroundColor3 = Theme.White,
		BorderSizePixel = 0,
		ZIndex = 21,
		Parent = body,
	})
	Kit.corner(face, 28)
	Kit.stroke(face, 4.5, Enum.ApplyStrokeMode.Border)
	Kit.gradient(face, Theme.Gradients.Gold, 90)
	c.face = face
	local shine = Fx.shine(face, { inset = 4, width = 120, strength = 0.85, zIndex = 30 })
	Kit.text(face, {
		Name = "Title",
		Position = UDim2.fromOffset(128, 10),
		Size = UDim2.fromOffset(400, 44),
		Text = TEXT.Thanks,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 24,
	}, { maxSize = 40, stroke = 4.5 })
	c.line = Kit.text(face, {
		Name = "Line",
		Position = UDim2.fromOffset(130, 54),
		Size = UDim2.fromOffset(300, 46),
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 24,
	}, { maxSize = 30, stroke = 3.5 })
	c.sub = Kit.text(face, {
		Name = "Sub",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -20, 0, 78),
		Size = UDim2.fromOffset(150, 40),
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 24,
	}, { maxSize = 34, stroke = 4, gradient = Theme.Gradients.LP })
	c.test = testTag(face, UDim2.new(1, -86, 0, 4), 26)
	fillCompact(c, entry)
	compact = c
	Sounds.play("PurchaseSmall")
	Fx.tween(holder, 0.45, { Position = UDim2.new(0.5, 0, 0, compactTop()) }, Style.Back, Dir.Out)
	task.delay(0.35, function()
		shine.play(0.7)
		for i = 1, 4 do
			Fx.sparkle(face, UDim2.fromScale(0.08 + math.random() * 0.84, 0.15 + math.random() * 0.7), math.random(18, 30), Theme.White, i * 0.08, 30)
		end
	end)
	task.spawn(function()
		while not c.hiding do
			task.wait(0.1)
			if os.clock() >= c.until_ or showingFull then
				hideCompact(c)
			end
		end
	end)
end

----------------------------------------------------------------- Kolejka
local function runQueue()
	if showingFull then
		return
	end
	showingFull = true
	if compact ~= nil then
		hideCompact(compact)
	end
	-- Na czas dużych podziękowań HUD znika (jak przy otwieraniu jajka): na niskim ekranie napisy
	-- wchodziły na pasek Bag. Własny powód „Thanks”, więc nie odkrywamy HUD w środku innej animacji.
	local hid = false
	while #queue > 0 do
		local entry = table.remove(queue, 1)
		if entry.waitCalm then
			waitCalm()
		end
		if not hid and hudRef ~= nil and hudRef.setVisible ~= nil then
			hid = true
			hudRef.setVisible(false, "Thanks")
		end
		local ok, err = pcall(playFull, entry, #queue > 0)
		if not ok then
			warn("[Sklep] podziękowanie: " .. tostring(err))
		end
	end
	if hid then
		hudRef.setVisible(true, "Thanks")
	end
	showingFull = false
	if pendingCompact ~= nil then
		local entry = pendingCompact
		pendingCompact = nil
		showCompact(entry)
	end
end

-- entry: { mode = "full" | "compact", art, name, sub, items, test, waitCalm }
function ShopThanks.show(entry)
	if gui == nil then
		return
	end
	if entry.mode == "full" then
		table.insert(queue, entry)
		task.spawn(runQueue)
		return
	end
	task.spawn(function()
		if entry.waitCalm then
			waitCalm()
		end
		if showingFull then
			pendingCompact = entry
		else
			showCompact(entry)
		end
	end)
end

function ShopThanks.start(hud)
	hudRef = hud
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	-- nad oknami, animacją jajek (16), Rebirth (17) i komunikatem o sekrecie (18)
	gui = Kit.new("ScreenGui", {
		Name = "LarpThanks",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 19,
		Parent = playerGui,
	})
end

return ShopThanks
