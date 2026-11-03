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
	Aura = "🔮",
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
	elseif sheetId ~= nil then
		local index = INDEX[name] or 0
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
