-- Wzór w tle okien: siatka małych szarych ikon „inwestowania” (słupki, linia wykresu i strzałka w górę),
-- jak delikatny wzór w tle okien w Pet Simulator 99. Rysowany z kształtów, więc nie trzeba nic wgrywać.
-- Gdy Settings.Ui.Pattern ma ID obrazka, zamiast kształtów jest kafelkowany obrazek.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Settings = require(ReplicatedStorage:WaitForChild("Shared").Config.Settings)
local Theme = require(script.Parent.Theme)

local Pattern = {}

-- Ikona w polu 60×60 (piksele bazowe przed skalą).
local BOX = 60
local THICK = 5
local BASE = { 4, 54, 52, 5 }
local BARS = {
	{ 10, 38, 10, 14 },
	{ 24, 31, 10, 21 },
	{ 38, 24, 10, 28 },
}
local LINE = { { 4, 30 }, { 16, 30 }, { 28, 18 }, { 38, 18 }, { 52, 4 } }
local HEAD_LENGTH = 11
local HEAD_SPREAD = 38

local function corner(frame, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = frame
end

-- style: { color, transparency, extend } — extend = o ile wydłużyć odcinki linii, żeby łączyły się
-- bez szczelin (przy półprzezroczystym wzorze 0, bo nakładki byłyby jaśniejsze).
local function rect(parent, x, y, w, h, s, style)
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.BackgroundColor3 = style.color
	f.BackgroundTransparency = style.transparency
	f.Position = UDim2.fromOffset(x * s, y * s)
	f.Size = UDim2.fromOffset(w * s, h * s)
	corner(f, math.max(1, math.floor(2 * s + 0.5)))
	f.Parent = parent
end

local function segment(parent, x1, y1, x2, y2, s, style)
	local dx, dy = x2 - x1, y2 - y1
	local length = math.sqrt(dx * dx + dy * dy) + style.extend
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.BackgroundColor3 = style.color
	f.BackgroundTransparency = style.transparency
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromOffset((x1 + x2) / 2 * s, (y1 + y2) / 2 * s)
	f.Size = UDim2.fromOffset(length * s, THICK * s)
	f.Rotation = math.deg(math.atan2(dy, dx))
	corner(f, math.max(1, math.floor(THICK * s / 2 + 0.5)))
	f.Parent = parent
end

local function icon(parent, x, y, s, style)
	local holder = Instance.new("Frame")
	holder.BackgroundTransparency = 1
	holder.Position = UDim2.fromOffset(x, y)
	holder.Size = UDim2.fromOffset(BOX * s, BOX * s)
	holder.Parent = parent
	rect(holder, BASE[1], BASE[2], BASE[3], BASE[4], s, style)
	for _, b in ipairs(BARS) do
		rect(holder, b[1], b[2], b[3], b[4], s, style)
	end
	for i = 1, #LINE - 1 do
		segment(holder, LINE[i][1], LINE[i][2], LINE[i + 1][1], LINE[i + 1][2], s, style)
	end
	local tip = LINE[#LINE]
	local prev = LINE[#LINE - 1]
	local back = math.atan2(prev[2] - tip[2], prev[1] - tip[1])
	for _, side in ipairs({ -1, 1 }) do
		local a = back + side * math.rad(HEAD_SPREAD)
		segment(holder, tip[1], tip[2], tip[1] + math.cos(a) * HEAD_LENGTH, tip[2] + math.sin(a) * HEAD_LENGTH, s, style)
	end
end

-- Czy ikona (lewy górny róg x, y, bok box) zachodzi na zaokrąglony róg ramki o promieniu radius.
-- Ramka przycina ikony tylko prostokątnie, więc w rogach ikon nie stawiamy.
local function inCorner(x, y, box, size, radius)
	if radius <= 0 then
		return false
	end
	local left = x < radius
	local right = x + box > size.X - radius
	local top = y < radius
	local bottom = y + box > size.Y - radius
	return (left or right) and (top or bottom)
end

-- Wypełnia całą ramkę wzorem (jak tapeta): ikony na brzegach są przycięte, a środkowa ikona
-- stoi na środku ramki. size: rozmiar ramki (Vector2, piksele bazowe).
-- opts: scale (wielkość ikon), stepX, stepY (odstępy), color, transparency (0 = pełny kolor,
-- np. 0.86 = biały prześwit na kolorowej karcie), radius (zaokrąglenie rogów ramki), zIndex.
function Pattern.fill(parent, size, opts)
	opts = opts or {}
	local holder = Instance.new("Frame")
	holder.Name = "Pattern"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromScale(1, 1)
	holder.ClipsDescendants = true
	holder.ZIndex = opts.zIndex or 1
	holder.Parent = parent

	local image = Settings.Ui and Settings.Ui.Pattern
	if type(image) == "string" and image ~= "" then
		local tile = Instance.new("ImageLabel")
		tile.BackgroundTransparency = 1
		tile.Size = UDim2.fromScale(1, 1)
		tile.Image = image
		tile.ScaleType = Enum.ScaleType.Tile
		tile.TileSize = UDim2.fromOffset(opts.tile or 128, opts.tile or 128)
		tile.ImageColor3 = opts.color or Theme.PatternColor
		tile.ImageTransparency = opts.transparency or 0
		corner(tile, opts.radius or 0)
		tile.Parent = holder
		return holder
	end

	local scale = opts.scale or 0.7
	local stepX = opts.stepX or 92
	local stepY = opts.stepY or 76
	local radius = opts.radius or 0
	local transparency = opts.transparency or 0
	local style = {
		color = opts.color or Theme.PatternColor,
		transparency = transparency,
		extend = (transparency > 0) and 0 or THICK,
	}
	local box = BOX * scale
	-- pierwsza kolumna i rząd tuż poza ramką, tak żeby jedna ikona wypadła dokładnie na środku
	local startX = ((size.X - box) / 2) % stepX - stepX
	local startY = ((size.Y - box) / 2) % (2 * stepY) - 2 * stepY
	local row = 0
	local y = startY
	while y < size.Y do
		local x = startX
		if row % 2 == 1 then
			x = x + stepX / 2
		end
		while x < size.X do
			local visible = x + box > 0 and y + box > 0
			if visible and not inCorner(x, y, box, size, radius) then
				icon(holder, x, y, scale, style)
			end
			x = x + stepX
		end
		y = y + stepY
		row = row + 1
	end
	return holder
end

return Pattern
