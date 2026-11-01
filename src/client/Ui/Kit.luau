-- Klocki UI w stylu gry (projekt na kanwie „Larp in Miami — UI”): napisy z obrysem, przyciski
-- z wypukłą krawędzią, kafelki menu z czerwoną kropką, białe „pigułki” na podpowiedzi i komunikaty
-- oraz okno z tytułem i przyciskiem X. Rozmiary w pikselach bazowych (ekran 1280×720).

local TweenService = game:GetService("TweenService")
local TextService = game:GetService("TextService")

local Theme = require(script.Parent.Theme)
local Icons = require(script.Parent.Icons)
local Sounds = require(script.Parent.Sounds)
local Pattern = require(script.Parent.Pattern)

local Kit = {}

local PRESS = TweenInfo.new(0.07, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

----------------------------------------------------------------- Podstawy
function Kit.new(className, props)
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

function Kit.corner(parent, radius)
	return Kit.new("UICorner", { CornerRadius = UDim.new(0, radius), Parent = parent })
end

-- Obrys. mode: Border (ramka) albo Contextual (domyślnie: obrys tekstu).
function Kit.stroke(parent, thickness, mode, color)
	return Kit.new("UIStroke", {
		Thickness = thickness,
		Color = color or Theme.Outline,
		ApplyStrokeMode = mode or Enum.ApplyStrokeMode.Contextual,
		LineJoinMode = Enum.LineJoinMode.Round,
		Parent = parent,
	})
end

-- Gradient: 2 kolory (góra → dół) albo 3 kolory (0, 0.6, 1). rotation 90 = pionowo, 0 = poziomo.
function Kit.gradient(parent, colors, rotation)
	local sequence
	if #colors >= 3 then
		sequence = ColorSequence.new({
			ColorSequenceKeypoint.new(0, colors[1]),
			ColorSequenceKeypoint.new(0.6, colors[2]),
			ColorSequenceKeypoint.new(1, colors[3]),
		})
	else
		sequence = ColorSequence.new(colors[1], colors[2])
	end
	return Kit.new("UIGradient", { Color = sequence, Rotation = rotation or 90, Parent = parent })
end

-- Napis dopasowany do ramki (TextScaled), domyślnie biały z obrysem.
-- opts: maxSize, stroke (0 = bez obrysu), gradient (kolory z Theme.Gradients).
function Kit.text(parent, props, opts)
	opts = opts or {}
	props.BackgroundTransparency = 1
	props.Font = Theme.Font
	props.TextColor3 = props.TextColor3 or Theme.White
	props.TextScaled = true
	props.Parent = parent
	local label = Kit.new("TextLabel", props)
	Kit.new("UITextSizeConstraint", { MaxTextSize = opts.maxSize or 28, MinTextSize = 6, Parent = label })
	local stroke = opts.stroke or 3
	if stroke > 0 then
		Kit.stroke(label, stroke)
	end
	if opts.gradient ~= nil then
		Kit.gradient(label, opts.gradient, 90)
	end
	return label
end

----------------------------------------------------------------- Przycisk z wypukłą krawędzią
-- opts: size (Vector2), text, colors, radius, edge, border, textSize, textStroke, name, order,
-- anchor, position, sound (nazwa z Settings.Sounds, domyślnie "Button"; false = bez dźwięku).
-- Zwraca { holder, face, label, Activated, setColors, setText }.
function Kit.button(parent, opts)
	local edge = opts.edge or 5
	local radius = opts.radius or 18
	local holder = Kit.new("Frame", {
		Name = opts.name or "Button",
		AnchorPoint = opts.anchor,
		Position = opts.position,
		Size = UDim2.fromOffset(opts.size.X, opts.size.Y + edge),
		BackgroundTransparency = 1,
		LayoutOrder = opts.order or 0,
		Parent = parent,
	})
	local shadow = Kit.new("Frame", {
		Name = "Edge",
		Position = UDim2.fromOffset(0, edge),
		Size = UDim2.new(1, 0, 1, -edge),
		BackgroundColor3 = Theme.Outline,
		BorderSizePixel = 0,
		ZIndex = 1,
		Parent = holder,
	})
	Kit.corner(shadow, radius)
	local face = Kit.new("TextButton", {
		Name = "Face",
		Size = UDim2.new(1, 0, 1, -edge),
		BackgroundColor3 = Theme.White,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		ZIndex = 2,
		Parent = holder,
	})
	Kit.corner(face, radius)
	Kit.stroke(face, opts.border or 4, Enum.ApplyStrokeMode.Border)
	local gradient = Kit.gradient(face, opts.colors or Theme.Gradients.Green, 90)
	local gloss = Kit.new("Frame", {
		Name = "Gloss",
		Position = UDim2.fromOffset(6, 4),
		Size = UDim2.new(1, -12, 0.34, 0),
		BackgroundColor3 = Theme.White,
		BackgroundTransparency = 0.72,
		BorderSizePixel = 0,
		ZIndex = 3,
		Parent = face,
	})
	Kit.corner(gloss, math.max(4, radius - 6))

	local label = nil
	if opts.text ~= nil then
		label = Kit.text(face, {
			Name = "Label",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.52),
			Size = UDim2.new(1, -14, 1, -12),
			Text = opts.text,
			ZIndex = 4,
		}, { maxSize = opts.textSize or 26, stroke = opts.textStroke or 3 })
	end

	-- Naciśnięcie: przycisk opada na swoją krawędź. Najechanie myszą: mocniejszy połysk.
	local pressed = false
	local function press(down)
		if down == pressed then
			return
		end
		pressed = down
		local y = 0
		if down then
			y = edge - 1
		end
		TweenService:Create(face, PRESS, { Position = UDim2.fromOffset(0, y) }):Play()
	end
	face.MouseButton1Down:Connect(function()
		press(true)
	end)
	face.MouseButton1Up:Connect(function()
		press(false)
	end)
	face.MouseEnter:Connect(function()
		gloss.BackgroundTransparency = 0.58
	end)
	face.MouseLeave:Connect(function()
		gloss.BackgroundTransparency = 0.72
		press(false)
	end)
	if opts.sound ~= false then
		local soundName = opts.sound or "Button"
		face.Activated:Connect(function()
			Sounds.play(soundName)
		end)
	end

	local api = { holder = holder, face = face, label = label, Activated = face.Activated }
	function api.setColors(colors)
		gradient.Color = ColorSequence.new(colors[1], colors[2])
	end
	function api.setText(text)
		if label ~= nil then
			label.Text = text
		end
	end
	return api
end

----------------------------------------------------------------- Czerwona kropka
function Kit.badge(parent, props)
	local frame = Kit.new("Frame", {
		Name = "Badge",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = props.Position,
		Size = UDim2.fromOffset(36, 36),
		BackgroundColor3 = Theme.BadgeRed,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 8,
		Parent = parent,
	})
	Kit.corner(frame, 18)
	Kit.stroke(frame, 4, Enum.ApplyStrokeMode.Border)
	local label = Kit.text(frame, {
		Position = UDim2.fromOffset(4, 3),
		Size = UDim2.new(1, -8, 1, -6),
		Text = "!",
		ZIndex = 9,
	}, { maxSize = 20, stroke = 2 })
	return {
		frame = frame,
		set = function(text)
			if text == nil then
				frame.Visible = false
			else
				label.Text = text
				frame.Visible = true
			end
		end,
	}
end

----------------------------------------------------------------- Kafelek menu
-- opts: name, icon, text, colors, order, textSize. Zwraca to co Kit.button oraz badge.
function Kit.tile(parent, opts)
	local b = Kit.button(parent, {
		name = opts.name,
		size = Vector2.new(104, 104),
		colors = opts.colors,
		radius = 26,
		edge = 6,
		order = opts.order,
	})
	Icons.make(opts.icon, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 2),
		Size = UDim2.fromOffset(80, 80),
		ZIndex = 5,
		Parent = b.face,
	})
	Kit.text(b.face, {
		Name = "Label",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, 18),
		Size = UDim2.new(1, 36, 0, 30),
		Text = opts.text,
		ZIndex = 6,
	}, { maxSize = opts.textSize or 25, stroke = 3.5 })
	b.badge = Kit.badge(b.face, { Position = UDim2.new(1, -4, 0, 4) })
	return b
end

----------------------------------------------------------------- Pigułka (podpowiedź, komunikat, chip)
-- Biała pigułka z obrysem i krawędzią. Treść to lista: { icon = "Cash", size = 32 } albo
-- { text = "...", size = 22, color = Color3, stroke = 3 }. Szerokość liczy się z treści.
function Kit.pill(parent, opts)
	local height = opts.height or 48
	local edge = opts.edge or 5
	local holder = Kit.new("Frame", {
		Name = opts.name or "Pill",
		AnchorPoint = opts.anchor,
		Position = opts.position,
		Size = UDim2.fromOffset(100, height + edge),
		BackgroundTransparency = 1,
		LayoutOrder = opts.order or 0,
		Parent = parent,
	})
	local shadow = Kit.new("Frame", {
		Name = "Edge",
		Position = UDim2.fromOffset(0, edge),
		Size = UDim2.new(1, 0, 0, height),
		BackgroundColor3 = Theme.Outline,
		BorderSizePixel = 0,
		ZIndex = 1,
		Parent = holder,
	})
	Kit.corner(shadow, math.floor(height / 2))
	local face = Kit.new("Frame", {
		Name = "Face",
		Size = UDim2.new(1, 0, 0, height),
		BackgroundColor3 = opts.color or Theme.White,
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = holder,
	})
	Kit.corner(face, math.floor(height / 2))
	Kit.stroke(face, opts.border or 4, Enum.ApplyStrokeMode.Border)

	local api = { holder = holder, face = face }
	function api.set(items)
		for _, child in ipairs(face:GetChildren()) do
			if child:GetAttribute("PillItem") then
				child:Destroy()
			end
		end
		local x = opts.padLeft or 10
		local gap = opts.gap or 8
		for i, item in ipairs(items) do
			if i > 1 then
				x = x + gap
			end
			if item.icon ~= nil then
				local size = item.size or (height - 8)
				local icon = Icons.make(item.icon, {
					AnchorPoint = Vector2.new(0, 0.5),
					Position = UDim2.new(0, x, 0.5, 0),
					Size = UDim2.fromOffset(size, size),
					ZIndex = 3,
					Parent = face,
				})
				icon:SetAttribute("PillItem", true)
				x = x + size
			else
				local textSize = item.size or math.floor(height * 0.5)
				local plain = string.gsub(item.text, "<[^>]+>", "")
				local bounds = TextService:GetTextSize(plain, textSize, Theme.Font, Vector2.new(4000, height))
				local label = Kit.new("TextLabel", {
					AnchorPoint = Vector2.new(0, 0.5),
					Position = UDim2.new(0, x, 0.5, 0),
					Size = UDim2.fromOffset(bounds.X + 4, height),
					BackgroundTransparency = 1,
					Font = Theme.Font,
					Text = item.text,
					TextSize = textSize,
					TextColor3 = item.color or Theme.Dark,
					RichText = item.rich == true,
					ZIndex = 3,
					Parent = face,
				})
				if item.stroke ~= nil then
					Kit.stroke(label, item.stroke)
				end
				label:SetAttribute("PillItem", true)
				x = x + bounds.X + 4
			end
		end
		x = x + (opts.padRight or 20)
		holder.Size = UDim2.fromOffset(x, height + edge)
	end
	if opts.items ~= nil then
		api.set(opts.items)
	end
	return api
end

----------------------------------------------------------------- Okno
-- Okno na środku ekranu: tytuł z ikoną nad lewym rogiem i czerwony X w prawym.
-- opts: name, size (Vector2), title, icon. Zwraca { holder, content, open, hide, toggle, isOpen }.
function Kit.panel(parent, opts)
	local holder = Kit.new("Frame", {
		Name = opts.name or "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 14),
		Size = UDim2.fromOffset(opts.size.X, opts.size.Y),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = parent,
	})
	local inner = Kit.new("Frame", {
		Name = "Inner",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = holder,
	})
	local pop = Kit.new("UIScale", { Parent = inner })
	local shadow = Kit.new("Frame", {
		Name = "Edge",
		Position = UDim2.fromOffset(0, 8),
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Outline,
		BorderSizePixel = 0,
		ZIndex = 1,
		Parent = inner,
	})
	Kit.corner(shadow, 30)
	local body = Kit.new("Frame", {
		Name = "Body",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.White,
		BorderSizePixel = 0,
		Active = true,
		ZIndex = 2,
		Parent = inner,
	})
	Kit.corner(body, 30)
	Kit.stroke(body, 5, Enum.ApplyStrokeMode.Border)
	Kit.gradient(body, Theme.Gradients.Panel, 90)
	Pattern.fill(body, opts.size, { radius = 30 })
	Icons.make(opts.icon, {
		Position = UDim2.fromOffset(-34, -58),
		Size = UDim2.fromOffset(108, 108),
		Rotation = -8,
		ZIndex = 6,
		Parent = inner,
	})
	Kit.text(inner, {
		Name = "Title",
		Position = UDim2.fromOffset(80, -38),
		Size = UDim2.fromOffset(opts.size.X - 200, 68),
		Text = opts.title,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 6,
	}, { maxSize = 56, stroke = 5 })
	local close = Kit.button(inner, {
		name = "Close",
		size = Vector2.new(64, 64),
		text = "X",
		colors = Theme.Gradients.Red,
		radius = 18,
		textSize = 36,
		textStroke = 3.5,
		anchor = Vector2.new(0.5, 0.5),
		position = UDim2.new(1, 10, 0, 10),
	})
	close.holder.ZIndex = 7
	local padding = opts.padding or 28
	local top = opts.top or 60
	local content = Kit.new("Frame", {
		Name = "Content",
		Position = UDim2.fromOffset(padding, top),
		Size = UDim2.new(1, -2 * padding, 1, -top - (opts.bottom or 20)),
		BackgroundTransparency = 1,
		ZIndex = 3,
		Parent = inner,
	})

	local api = { holder = holder, content = content, close = close }
	function api.isOpen()
		return holder.Visible
	end
	function api.open()
		holder.Visible = true
		pop.Scale = 0.85
		TweenService:Create(pop, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
	function api.hide()
		holder.Visible = false
	end
	function api.toggle()
		if holder.Visible then
			api.hide()
		else
			api.open()
		end
	end
	close.Activated:Connect(api.hide)
	return api
end

return Kit
