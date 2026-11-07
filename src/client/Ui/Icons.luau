-- Ikony. Kolejność wyboru dla każdej nazwy:
--   1. własna ikona z Settings.Ui.Icons (ID Decala albo obrazka z Toolboxa),
--   2. pole z arkusza assets/icons/larp-icons.png (Settings.Ui.IconSheet, 4×4 pola po 256 px),
--   3. emoji, dopóki nic z powyższych nie jest ustawione.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Settings = require(ReplicatedStorage:WaitForChild("Shared").Config.Settings)

local Icons = {}

local ORDER = {
	"Cash", "LP", "Bag", "Sell",
	"Upgrades", "Click", "Aura", "Rebirth",
	"Shop", "Gift", "Settings", "Pets",
	"Lock", "Trophy", "Clock", "Camera",
}

local EMOJI = {
	Cash = "💰",
	LP = "⭐",
	Bag = "👜",
	Sell = "💸",
	Upgrades = "⬆️",
	Click = "👆",
	Aura = "🔥",
	Rebirth = "🔄",
	Shop = "🛍️",
	Gift = "🎁",
	Settings = "⚙️",
	Pets = "🐾",
	Lock = "🔒",
	Trophy = "🏆",
	Clock = "⏱️",
	Camera = "📸",
	SellCash = "💵",
	Clothes = "👕",
	Luck = "🍀", -- sklep Aury: Luck
	Merge = "🧬", -- sklep Aury: Merge Luck
	Speed = "👟", -- Rebirth: szybsze chodzenie
	Teleport = "🌀", -- gamepass Teleport i okno teleportu
	Chain = "⛓️", -- gamepass Double Chain
	Watch = "⌚", -- gamepass Double Wrist, zegarek ze Starter Packa
	Boost = "⚡", -- boosty 2x LP
	Ad = "📺", -- reklama za nagrodę
	Premium = "💎", -- premium jajka
	Crown = "👑", -- zakładka i nagłówek gamepassów w sklepie
	Egg = "🥚", -- grafiki Triple Open i Fast Open, gdy brak obrazka jajka
	Check = "✅", -- kupiony gamepass (OWNED)
	Sparkles = "✨",
	-- Znaki Roblox (prywatne kody Unicode): ikona Robux (U+E002) i znaczek Verified (U+E000).
	-- Zapisane bajtami UTF-8, bo tak rozumie je też Lua 5.1 w testach.
	Robux = "\238\128\130",
	Verified = "\238\128\128",
}

-- Kolor znaków Roblox (ikona Robux jest jednokolorowa; Verified ma własny niebieski).
local GLYPH_COLORS = {
	Robux = Color3.fromRGB(255, 255, 255),
}

local CELL = 256
local COLUMNS = 4

local INDEX = {}
for i, name in ipairs(ORDER) do
	INDEX[name] = i - 1
end

local function sheet()
	local id = Settings.Ui and Settings.Ui.IconSheet
	if type(id) == "string" and id ~= "" then
		return id
	end
	return nil
end

-- Treść obrazka dla własnej ikony. Liczba = ID z Toolboxa: miniatura Roblox działa i dla Decali,
-- i dla obrazków. Tekst (np. "rbxassetid://…") zostaje bez zmian.
local function custom(name)
	local list = Settings.Ui and Settings.Ui.Icons
	local value = list and list[name]
	if type(value) == "number" then
		return "rbxthumb://type=Asset&id=" .. string.format("%d", value) .. "&w=420&h=420"
	elseif type(value) == "string" and value ~= "" then
		return value
	end
	return nil
end

-- Ikona jako GuiObject (ImageLabel albo TextLabel z emoji).
-- props to zwykłe właściwości (Size, Position, AnchorPoint, ZIndex, Parent…).
function Icons.make(name, props)
	local icon
	local own = custom(name)
	local sheetId = sheet()
	if own ~= nil then
		icon = Instance.new("ImageLabel")
		icon.Image = own
		icon.ScaleType = Enum.ScaleType.Fit
	elseif sheetId ~= nil and INDEX[name] ~= nil then
		-- arkusz ma tylko 16 ikon; reszta (np. Clothes) bez własnej ikony to emoji
		local index = INDEX[name]
		icon = Instance.new("ImageLabel")
		icon.Image = sheetId
		icon.ImageRectSize = Vector2.new(CELL, CELL)
		icon.ImageRectOffset = Vector2.new((index % COLUMNS) * CELL, math.floor(index / COLUMNS) * CELL)
		icon.ScaleType = Enum.ScaleType.Stretch
	else
		icon = Instance.new("TextLabel")
		icon.Text = EMOJI[name] or "?"
		icon.TextScaled = true
		icon.Font = Enum.Font.FredokaOne
		local glyph = GLYPH_COLORS[name]
		if glyph ~= nil then
			icon.TextColor3 = glyph
			local stroke = Instance.new("UIStroke")
			stroke.Thickness = 2
			stroke.Color = Color3.fromRGB(31, 21, 48)
			stroke.Parent = icon
		end
	end
	icon.Name = name .. "Icon"
	icon.BackgroundTransparency = 1
	icon.BorderSizePixel = 0
	local parent = nil
	for key, value in pairs(props or {}) do
		if key == "Parent" then
			parent = value
		else
			icon[key] = value
		end
	end
	if parent ~= nil then
		icon.Parent = parent
	end
	return icon
end

return Icons
