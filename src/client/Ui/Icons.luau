-- Ikony z arkusza assets/icons/larp-icons.png (4×4 pola po 256 px, kolejność jak w tools/build_icons.py).
-- Dopóki arkusz nie jest wgrany do Roblox (Settings.Ui.IconSheet puste), w miejscu ikon są emoji.

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
}

local CELL = 256
local COLUMNS = 4

local INDEX = {}
for i, name in ipairs(ORDER) do
	INDEX[name] = i - 1
end

function Icons.hasSheet()
	local id = Settings.Ui and Settings.Ui.IconSheet
	return type(id) == "string" and id ~= ""
end

-- Ikona jako GuiObject: ImageLabel z wycinkiem arkusza albo TextLabel z emoji.
-- props to zwykłe właściwości (Size, Position, AnchorPoint, ZIndex, Parent…).
function Icons.make(name, props)
	local index = INDEX[name] or 0
	local icon
	if Icons.hasSheet() then
		icon = Instance.new("ImageLabel")
		icon.Image = Settings.Ui.IconSheet
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
