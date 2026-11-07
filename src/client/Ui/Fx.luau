-- Efekty i animacje UI (sklep za Robuxy, podziękowanie po zakupie, kafelki po prawej):
--   • Fx.bin: sprzątanie (tweeny, połączenia, obiekty) po zamknięciu okna albo końcu efektu,
--   • połysk (obrazek „Shine” z Settings.Ui.ShopArt przesuwany po karcie albo przycisku),
--   • promienie za przedmiotem, iskierki, fala z przycisku, wybuch małych ikon, konfetti,
--   • reakcje przycisków i kart na mysz (najechanie, wciśnięcie, puszczenie).
-- Ruch liczy TweenService (silnik), a tymczasowe obiekty znikają same po końcu animacji.
-- Rozmiary w pikselach bazowych (1280×720), chyba że opis mówi o pikselach ekranu.

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Settings = require(ReplicatedStorage:WaitForChild("Shared").Config.Settings)
local Theme = require(script.Parent.Theme)

local Fx = {}

local ART = (Settings.Ui and Settings.Ui.ShopArt) or {}

local Style = Enum.EasingStyle
local Dir = Enum.EasingDirection

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
Fx.new = new

-- Obrazek z Toolboxa (ID Decala albo obrazka) jako treść ImageLabel; nil, gdy brak ID.
function Fx.image(id)
	if type(id) == "number" and id > 0 then
		return "rbxthumb://type=Asset&id=" .. string.format("%d", id) .. "&w=420&h=420"
	elseif type(id) == "string" and id ~= "" then
		return id
	end
	return nil
end

----------------------------------------------------------------- Sprzątanie
-- Kosz na wszystko, co trzeba zatrzymać naraz: tweeny (Cancel), połączenia (Disconnect),
-- obiekty (Destroy), funkcje (wywołanie) i uchwyty z polem stop.
function Fx.bin()
	local items = {}
	local bin = {}
	function bin.add(x)
		if x ~= nil then
			table.insert(items, x)
		end
		return x
	end
	function bin.clean()
		for i = #items, 1, -1 do
			local x = items[i]
			items[i] = nil
			local kind = typeof(x)
			if kind == "Instance" then
				if x:IsA("Tween") then
					x:Cancel()
				else
					x:Destroy()
				end
			elseif kind == "function" then
				pcall(x)
			elseif kind == "RBXScriptConnection" then
				x:Disconnect()
			elseif kind == "table" then
				if x.stop ~= nil then
					x.stop()
				elseif x.Disconnect ~= nil then
					x:Disconnect()
				end
			end
		end
	end
	return bin
end

----------------------------------------------------------------- Tweeny
-- Krótszy zapis tweena; od razu gra. repeats = -1 bez końca, reverses = tam i z powrotem.
-- Uwaga: nowy tween tej samej właściwości tego samego obiektu od razu przejmuje ją od starego
-- (nawet z DelayTime), więc kolejne etapy jednej właściwości odpalamy dopiero po czasie (Fx.after).
function Fx.tween(obj, time, goals, style, dir, delay, repeats, reverses)
	local info = TweenInfo.new(time, style or Style.Quad, dir or Dir.Out, repeats or 0, reverses or false, delay or 0)
	local tween = TweenService:Create(obj, info, goals)
	tween:Play()
	return tween
end

-- Następny etap animacji po delay sekundach (task.delay).
function Fx.after(delay, fn)
	return task.delay(delay, fn)
end

-- Tam i z powrotem bez końca (unoszenie, pulsowanie, kołysanie). Zwraca tween (do bin).
function Fx.loop(obj, time, goals, style, delay)
	return Fx.tween(obj, time, goals, style or Style.Sine, Dir.InOut, delay or 0, -1, true)
end

-- Obrót bez końca (360° w period sekund, liniowo).
function Fx.spin(obj, period, clockwise)
	local start = obj.Rotation
	local target = start + 360
	if clockwise == false then
		target = start - 360
	end
	return Fx.tween(obj, period, { Rotation = target }, Style.Linear, Dir.InOut, 0, -1, false)
end

-- Wyskoczenie: UIScale od from do 1 (Back). uiScale = istniejący UIScale.
function Fx.pop(uiScale, from, time, delay)
	uiScale.Scale = from or 0
	return Fx.tween(uiScale, time or 0.35, { Scale = 1 }, Style.Back, Dir.Out, delay or 0)
end

-- Podskok: 1 → peak → 1 (np. kafelek, do którego coś doleciało albo coś się zmieniło).
function Fx.bump(uiScale, peak, time)
	uiScale.Scale = peak or 1.2
	return Fx.tween(uiScale, time or 0.35, { Scale = 1 }, Style.Back, Dir.Out)
end

-- UIScale obiektu (nowy, gdy go nie ma).
function Fx.scaleOf(obj)
	local s = obj:FindFirstChild("FxScale")
	if s == nil then
		s = new("UIScale", { Name = "FxScale", Parent = obj })
	end
	return s
end

----------------------------------------------------------------- Połysk
-- Jasny pas przesuwany ukośnie po ramce (jak odbicie światła na szkle). Obrazek „Shine”
-- (Settings.Ui.ShopArt.Shine) rozciągnięty w wysoki pas z miękkimi brzegami; bez ID biały pas.
-- Warstwa jest o inset pikseli mniejsza od ramki z każdej strony, bo Roblox obcina prostokątem,
-- a rogi kart są zaokrąglone. opts: inset, width (szerokość pasa), angle, strength (0–1), zIndex.
-- Zwraca { frame, play(time, delay) }.
local SHINE_FADE = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(0.3, 0.55),
	NumberSequenceKeypoint.new(0.5, 0),
	NumberSequenceKeypoint.new(0.7, 0.55),
	NumberSequenceKeypoint.new(1, 1),
})
function Fx.shine(parent, opts)
	opts = opts or {}
	local inset = opts.inset or 0
	local width = opts.width or 90
	local clip = new("Frame", {
		Name = "Shine",
		Position = UDim2.fromOffset(inset, inset + (opts.top or 0)),
		Size = UDim2.new(1, -2 * inset, 1, -2 * inset - (opts.top or 0) - (opts.bottom or 0)),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		ZIndex = opts.zIndex or 20,
		Parent = parent,
	})
	local strength = opts.strength or 0.75
	local image = Fx.image(ART.Shine)
	local band
	if image ~= nil then
		band = new("ImageLabel", {
			Name = "Band",
			Image = image,
			ScaleType = Enum.ScaleType.Stretch,
			ImageTransparency = 1 - strength,
			BackgroundTransparency = 1,
		})
	else
		band = new("Frame", {
			Name = "Band",
			BackgroundColor3 = Theme.White,
			BackgroundTransparency = 1 - strength * 0.7,
			BorderSizePixel = 0,
		})
	end
	band.AnchorPoint = Vector2.new(0.5, 0.5)
	band.Size = UDim2.new(0, width, 2.6, 0)
	band.Position = UDim2.new(0, -width, 0.5, 0)
	band.Rotation = opts.angle or 20
	band.Visible = false
	band.ZIndex = opts.zIndex or 20
	band.Parent = clip
	new("UIGradient", { Transparency = SHINE_FADE, Rotation = 0, Parent = band })
	local api = { frame = clip }
	local current = nil
	function api.play(time, delay)
		if current ~= nil then
			current:Cancel()
		end
		band.Position = UDim2.new(0, -width, 0.5, 0)
		band.Visible = true
		current = Fx.tween(band, time or 0.7, { Position = UDim2.new(1, width, 0.5, 0) }, Style.Sine, Dir.InOut, delay or 0)
		return current
	end
	function api.stop()
		if current ~= nil then
			current:Cancel()
			current = nil
		end
		band.Visible = false
	end
	return api
end

----------------------------------------------------------------- Promienie
-- Promienie za przedmiotem (jak w PS99): count pasów przez środek (każdy daje dwa promienie),
-- jasne w połowie długości i znikające na końcach. opts: count, width, length (połowa długości,
-- piksele), color, alpha (0–1), zIndex. Zwraca kontener (obracaj nim, np. Fx.spin).
function Fx.rays(parent, center, opts)
	opts = opts or {}
	local length = opts.length or 160
	local holder = new("Frame", {
		Name = "Rays",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = center,
		Size = UDim2.fromOffset(2 * length, 2 * length),
		BackgroundTransparency = 1,
		ZIndex = opts.zIndex or 1,
		Parent = parent,
	})
	local alpha = opts.alpha or 0.35
	local fade = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.22, 1 - alpha),
		NumberSequenceKeypoint.new(0.42, 1 - alpha * 0.5),
		NumberSequenceKeypoint.new(0.5, 1),
		NumberSequenceKeypoint.new(0.58, 1 - alpha * 0.5),
		NumberSequenceKeypoint.new(0.78, 1 - alpha),
		NumberSequenceKeypoint.new(1, 1),
	})
	local count = opts.count or 8
	for i = 1, count do
		local ray = new("Frame", {
			Name = "Ray",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(0, opts.width or 28, 1, 0),
			Rotation = (i - 1) * 180 / count,
			BackgroundColor3 = opts.color or Theme.White,
			BorderSizePixel = 0,
			ZIndex = opts.zIndex or 1,
			Parent = holder,
		})
		new("UIGradient", { Transparency = fade, Rotation = 90, Parent = ray })
	end
	return holder
end

-- Miękka poświata: kilka przezroczystych kół jedno na drugim (Roblox nie ma gradientu kołowego).
function Fx.glow(parent, center, size, color, alpha, zIndex)
	local holder = new("Frame", {
		Name = "Glow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = center,
		Size = UDim2.fromOffset(size, size),
		BackgroundTransparency = 1,
		ZIndex = zIndex or 1,
		Parent = parent,
	})
	for i, k in ipairs({ 1, 0.74, 0.5 }) do
		local disc = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(k, k),
			BackgroundColor3 = color or Theme.White,
			BackgroundTransparency = 1 - (alpha or 0.5) * (0.35 + 0.22 * i),
			BorderSizePixel = 0,
			ZIndex = zIndex or 1,
			Parent = holder,
		})
		new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = disc })
	end
	return holder
end

----------------------------------------------------------------- Iskierki
-- Czteroramienna gwiazdka: dwa wąskie paski z miękkimi końcami i jasny środek.
local GLINT_FADE = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(0.42, 0.2),
	NumberSequenceKeypoint.new(0.5, 0),
	NumberSequenceKeypoint.new(0.58, 0.2),
	NumberSequenceKeypoint.new(1, 1),
})
function Fx.glintShape(parent, size, color, zIndex)
	local holder = new("Frame", {
		Name = "Glint",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(size, size),
		BackgroundTransparency = 1,
		ZIndex = zIndex or 10,
		Parent = parent,
	})
	for _, vertical in ipairs({ false, true }) do
		local bar = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = vertical and UDim2.new(0.16, 0, 1, 0) or UDim2.new(1, 0, 0.16, 0),
			BackgroundColor3 = color or Theme.White,
			BorderSizePixel = 0,
			ZIndex = zIndex or 10,
			Parent = holder,
		})
		new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = bar })
		new("UIGradient", { Transparency = GLINT_FADE, Rotation = vertical and 90 or 0, Parent = bar })
	end
	local dot = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.3, 0.3),
		BackgroundColor3 = color or Theme.White,
		BorderSizePixel = 0,
		ZIndex = zIndex or 10,
		Parent = holder,
	})
	new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = dot })
	return holder
end

-- Jedno mrugnięcie gwiazdki w punkcie position (UDim2 w rodzicu): rośnie, obraca się, znika.
function Fx.sparkle(parent, position, size, color, delay, zIndex)
	local glint = Fx.glintShape(parent, size or 26, color, zIndex)
	glint.Position = position
	glint.Rotation = math.random(0, 30)
	local s = new("UIScale", { Scale = 0, Parent = glint })
	local t = 0.55 + math.random() * 0.25
	Fx.tween(s, t * 0.45, { Scale = 1 }, Style.Back, Dir.Out, delay or 0)
	Fx.tween(glint, t, { Rotation = glint.Rotation + 90 }, Style.Linear, Dir.Out, delay or 0)
	Fx.after((delay or 0) + t * 0.45, function()
		Fx.tween(s, t * 0.55, { Scale = 0 }, Style.Quad, Dir.In)
	end)
	task.delay((delay or 0) + t + 0.05, function()
		glint:Destroy()
	end)
	return glint
end

----------------------------------------------------------------- Fala, wybuch ikon, konfetti
-- Fala z punktu: biały okrąg rośnie i znika. position w rodzicu (UDim2), size w pikselach ekranu.
function Fx.ring(parent, position, fromSize, toSize, color, zIndex, time)
	local ring = new("Frame", {
		Name = "Ring",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = position,
		Size = UDim2.fromOffset(fromSize, fromSize),
		BackgroundTransparency = 1,
		ZIndex = zIndex or 30,
		Parent = parent,
	})
	new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = ring })
	local stroke = new("UIStroke", { Thickness = 5, Color = color or Theme.White, Transparency = 0.1, Parent = ring })
	time = time or 0.5
	Fx.tween(ring, time, { Size = UDim2.fromOffset(toSize, toSize) }, Style.Quad, Dir.Out)
	Fx.tween(stroke, time, { Transparency = 1, Thickness = 1 }, Style.Quad, Dir.In)
	task.delay(time + 0.05, function()
		ring:Destroy()
	end)
	return ring
end

-- Wybuch małych obiektów z punktu origin (piksele ekranu w layer): lecą na zewnątrz po łuku
-- (wachlarz wokół kąta angle, rozpiętość spread w stopniach), obracają się, maleją i znikają.
-- make(i) zwraca nowy GuiObject. opts: count, size, distance, angle, spread, scale (skala UI),
-- time, zIndex, gravity.
function Fx.burst(layer, origin, make, opts)
	opts = opts or {}
	local count = opts.count or 8
	local k = opts.scale or 1
	local size = (opts.size or 44) * k
	local time = opts.time or 0.75
	for i = 1, count do
		local item = make(i)
		item.AnchorPoint = Vector2.new(0.5, 0.5)
		item.Position = UDim2.fromOffset(origin.X, origin.Y)
		item.Size = UDim2.fromOffset(size, size)
		item.Rotation = math.random(-30, 30)
		item.ZIndex = opts.zIndex or 60
		item.Parent = layer
		local s = new("UIScale", { Scale = 0.2, Parent = item })
		local spread = math.rad(opts.spread or 140)
		local angle = math.rad(opts.angle or 180) + (((i - 0.5) / count) - 0.5) * spread + (math.random() - 0.5) * 0.25
		local d = (opts.distance or 180) * k * (0.75 + math.random() * 0.45)
		local mid = origin + Vector2.new(math.cos(angle), math.sin(angle)) * d
		local spin = math.random(140, 300)
		if math.random() < 0.5 then
			spin = -spin
		end
		local out = time * 0.55
		local rotation = item.Rotation
		Fx.tween(item, out, { Position = UDim2.fromOffset(mid.X, mid.Y), Rotation = rotation + spin * 0.6 }, Style.Quad, Dir.Out)
		Fx.tween(s, out * 0.6, { Scale = 1 }, Style.Back, Dir.Out)
		local fall = (opts.gravity or 70) * k
		Fx.after(out, function()
			Fx.tween(item, time - out, { Position = UDim2.fromOffset(mid.X + (mid.X - origin.X) * 0.15, mid.Y + fall), Rotation = rotation + spin }, Style.Quad, Dir.In)
			Fx.tween(s, time - out, { Scale = 0 }, Style.Quad, Dir.In)
		end)
		task.delay(time + 0.05, function()
			item:Destroy()
		end)
	end
end

-- Konfetti: kolorowe paski wylatują z punktu i opadają, kręcąc się. layer bez UIScale (piksele
-- ekranu), origin = Vector2 w layer, k = skala UI.
function Fx.confetti(layer, origin, count, k, zIndex)
	k = k or 1
	local colors = Theme.Rainbow
	for i = 1, count do
		local piece = new("Frame", {
			Name = "Confetti",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(origin.X, origin.Y),
			Size = UDim2.fromOffset(math.random(9, 14) * k, math.random(16, 24) * k),
			Rotation = math.random(0, 180),
			BackgroundColor3 = colors[(i % #colors) + 1],
			BorderSizePixel = 0,
			ZIndex = zIndex or 40,
			Parent = layer,
		})
		new("UICorner", { CornerRadius = UDim.new(0, 3 * k), Parent = piece })
		local angle = math.rad(math.random(195, 345))
		local d = math.random(160, 420) * k
		local mid = origin + Vector2.new(math.cos(angle) * d, math.sin(angle) * d * 0.8)
		local out = 0.35 + math.random() * 0.2
		local down = 1.1 + math.random() * 0.7
		local rotation = piece.Rotation
		Fx.tween(piece, out, { Position = UDim2.fromOffset(mid.X, mid.Y), Rotation = rotation + math.random(-200, 200) }, Style.Quad, Dir.Out)
		local endX = mid.X + math.random(-60, 60) * k
		local endY = mid.Y + math.random(260, 420) * k
		local endRotation = rotation + math.random(-540, 540)
		Fx.after(out, function()
			Fx.tween(piece, down, {
				Position = UDim2.fromOffset(endX, endY),
				Rotation = endRotation,
				BackgroundTransparency = 1,
			}, Style.Quad, Dir.In)
		end)
		task.delay(out + down + 0.05, function()
			piece:Destroy()
		end)
	end
end

----------------------------------------------------------------- Mysz
local function hasMouse()
	return UserInputService.MouseEnabled
end
Fx.hasMouse = hasMouse

-- Karta reaguje na mysz: najechanie powiększa (uiScale do scale) i wywołuje onEnter (np. połysk).
-- Na dotyku bez myszy nie ma najechania, więc nic się nie dzieje. Połączenia idą do bin (jeśli jest).
function Fx.hover(trigger, uiScale, scale, onEnter, bin)
	local a = trigger.MouseEnter:Connect(function()
		if not hasMouse() then
			return
		end
		Fx.tween(uiScale, 0.18, { Scale = scale or 1.04 }, Style.Quad, Dir.Out)
		if onEnter ~= nil then
			onEnter()
		end
	end)
	local b = trigger.MouseLeave:Connect(function()
		Fx.tween(uiScale, 0.22, { Scale = 1 }, Style.Quad, Dir.Out)
	end)
	if bin ~= nil then
		bin.add(a)
		bin.add(b)
	end
end

-- Przycisk z Kit.button: najechanie lekko powiększa, wciśnięcie zmniejsza, a puszczenie wraca
-- ze sprężynowaniem. Skala na button.body (rośnie od środka). Zwraca ten UIScale.
function Fx.button(button, hoverScale)
	local s = Fx.scaleOf(button.body)
	local over = false
	hoverScale = hoverScale or 1.06
	button.face.MouseEnter:Connect(function()
		if not hasMouse() then
			return
		end
		over = true
		Fx.tween(s, 0.16, { Scale = hoverScale }, Style.Back, Dir.Out)
	end)
	button.face.MouseLeave:Connect(function()
		over = false
		Fx.tween(s, 0.2, { Scale = 1 }, Style.Quad, Dir.Out)
	end)
	button.face.MouseButton1Down:Connect(function()
		Fx.tween(s, 0.08, { Scale = 0.92 }, Style.Quad, Dir.Out)
	end)
	button.face.MouseButton1Up:Connect(function()
		local target = 1
		if over then
			target = hoverScale
		end
		Fx.tween(s, 0.35, { Scale = target }, Style.Back, Dir.Out)
	end)
	return s
end

return Fx
