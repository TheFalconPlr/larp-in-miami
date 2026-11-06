-- Tytuł Rebirth i Aura Level nad głową każdego gracza oraz poświata wokół awatara (Etap 9).
-- Serwer ustawia atrybuty gracza (LarpRebirth = poziom Rebirth, LarpAuraLevel = Aura Level), a każdy
-- klient rysuje u siebie napis i iskry. Poświata jest od Aura Level 10, w kolorze progu: biała, niebieska,
-- fioletowa, złota, czerwona, tęczowa (Economy.Aura.Glow, kolory w Theme.GlowColors).
-- Napis ma rozmiar w studs (Kit.worldFrame), więc z daleka jest mały, i widać go tylko z bliska. Tytuł
-- ma gradient z jaśniejszą górą, cień pod literami i (od Rebirth 1) przesuwający się połysk, a Aura Level
-- jest w fioletowej plakietce z ogniem. Nad innymi graczami pod tytułem jest ich nick, a zwykły napis
-- Roblox z nickiem znika (inaczej oba napisy wchodziłyby na siebie nad głową).
-- W czasie aktywności (State.busy) napisy są schowane, a poświata innych graczy też (inni gracze
-- i tak znikają na czas sceny).

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Formulas = require(Shared.Formulas)
local Rebirth = require(Shared.Logic.Rebirth)
local State = require(script.Parent.State)
local Theme = require(script.Parent.Ui.Theme)
local Kit = require(script.Parent.Ui.Kit)
local Icons = require(script.Parent.Ui.Icons)

local Nametags = {}

local LEVEL_ATTRIBUTE = "LarpRebirth" -- jak RebirthService.LevelAttribute
local AURA_ATTRIBUTE = "LarpAuraLevel" -- jak RebirthService.AuraLevelAttribute
local SPARKLES = "rbxasset://textures/particles/sparkles_main.dds" -- iskry wbudowane w Roblox

-- Wygląd napisu (piksele bazowe w ramce Kit.worldFrame)
local PIXELS_PER_STUD = 80 -- rząd z tytułem (60 px) ma 0,75 studs
local WIDTH = 560
local TITLE_ROW = 60
local NAME_ROW = 34 -- nick innego gracza pod tytułem
local TITLE_SIZE = 40
local NAME_SIZE = 27
local BADGE_HEIGHT = 44
local BADGE_TEXT = 30
local GAP = 10 -- między tytułem a plakietką
local HEAD_GAP = 0.6 -- odstęp dołu napisu od czubka głowy (studs)
local MAX_DISTANCE = 40 -- napis widać z tylu studs od kamery
local SHINE_FROM = 1 -- połysk na tytule od tego poziomu Rebirth

local SHADOW = Color3.fromRGB(20, 12, 34)
local SHINE = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(0.4, 1),
	NumberSequenceKeypoint.new(0.5, 0.35),
	NumberSequenceKeypoint.new(0.6, 1),
	NumberSequenceKeypoint.new(1, 1),
})

local function glowSequence(glow)
	if glow == "Rainbow" then
		local points = {}
		local n = #Theme.Rainbow
		for i, color in ipairs(Theme.Rainbow) do
			table.insert(points, ColorSequenceKeypoint.new((i - 1) / (n - 1), color))
		end
		return ColorSequence.new(points)
	end
	return ColorSequence.new(Theme.GlowColors[glow] or Theme.White)
end

-- Gradient tytułu z góry na dół: rozjaśniona góra, kolor tytułu, przyciemniony dół.
local function titleColors(level)
	local colors = Theme.TitleColors[level] or Theme.TitleColors[Rebirth.Cap]
	return {
		colors[1]:Lerp(Theme.White, 0.45),
		colors[1]:Lerp(colors[2], 0.5),
		colors[2]:Lerp(Color3.new(0, 0, 0), 0.15),
	}
end

local function textLabel(parent, text, size, x, y, zIndex)
	local bounds = Kit.measure(text, size)
	return Kit.new("TextLabel", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(bounds.X + 2, bounds.Y),
		BackgroundTransparency = 1,
		Font = Theme.Font,
		Text = text,
		TextSize = size,
		TextColor3 = Theme.White,
		ZIndex = zIndex,
		Parent = parent,
	}), bounds.X + 2
end

function Nametags.start(hud)
	local localPlayer = Players.LocalPlayer
	local playerGui = localPlayer:WaitForChild("PlayerGui")
	local entries = {} -- [gracz] = { gui, frame, height, key, shine, emitter, light, glow }

	local function clearGlow(entry)
		if entry.emitter ~= nil then
			entry.emitter:Destroy()
			entry.emitter = nil
		end
		if entry.light ~= nil then
			entry.light:Destroy()
			entry.light = nil
		end
		entry.glow = nil
	end

	-- Treść napisu: tytuł (cień, gradient, połysk), plakietka Aura Level i nick (nad innymi graczami).
	local function build(entry, player, level, auraLevel)
		for _, child in ipairs(entry.frame:GetChildren()) do
			if child:GetAttribute("TagItem") then
				child:Destroy()
			end
		end
		if entry.shine ~= nil then
			entry.shine:Cancel()
			entry.shine = nil
		end
		local row = Kit.new("Frame", {
			Name = "Row",
			Size = UDim2.fromOffset(WIDTH, TITLE_ROW),
			BackgroundTransparency = 1,
			Parent = entry.frame,
		})
		row:SetAttribute("TagItem", true)
		local title = Rebirth.title(level)
		local titleWidth = Kit.measure(title, TITLE_SIZE).X + 2
		local badgeText = tostring(auraLevel)
		local badgeWidth = 0
		if auraLevel > 0 then
			badgeWidth = 12 + 34 + 4 + Kit.measure(badgeText, BADGE_TEXT).X + 14
		end
		local total = titleWidth
		if badgeWidth > 0 then
			total = total + GAP + badgeWidth
		end
		local x = math.floor((WIDTH - total) / 2)
		local y = TITLE_ROW / 2

		-- tytuł: ciemny cień pod spodem, na nim napis z gradientem i grubym obrysem
		local shadow = textLabel(row, title, TITLE_SIZE, x, y + 4, 2)
		shadow.TextColor3 = SHADOW
		Kit.stroke(shadow, 5, nil, SHADOW)
		local label = textLabel(row, title, TITLE_SIZE, x, y, 3)
		Kit.stroke(label, 4.5)
		Kit.gradient(label, titleColors(level), 90)
		if level >= SHINE_FROM then
			-- połysk: biały pasek przesuwa się po tytule co kilka sekund
			local gloss = textLabel(row, title, TITLE_SIZE, x, y, 4)
			local gradient = Kit.new("UIGradient", { Transparency = SHINE, Rotation = 20, Offset = Vector2.new(-1, 0), Parent = gloss })
			entry.shine = TweenService:Create(
				gradient,
				TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, false, 2.2),
				{ Offset = Vector2.new(1, 0) }
			)
			entry.shine:Play()
		end

		-- Aura Level: fioletowa plakietka z krawędzią, ogień i liczba
		if badgeWidth > 0 then
			local bx = x + titleWidth + GAP
			local edge = Kit.new("Frame", {
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.fromOffset(bx, y + 4),
				Size = UDim2.fromOffset(badgeWidth, BADGE_HEIGHT),
				BackgroundColor3 = SHADOW,
				BorderSizePixel = 0,
				ZIndex = 2,
				Parent = row,
			})
			Kit.corner(edge, BADGE_HEIGHT / 2)
			local badge = Kit.new("Frame", {
				Name = "AuraBadge",
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.fromOffset(bx, y),
				Size = UDim2.fromOffset(badgeWidth, BADGE_HEIGHT),
				BackgroundColor3 = Theme.White,
				BorderSizePixel = 0,
				ZIndex = 3,
				Parent = row,
			})
			Kit.corner(badge, BADGE_HEIGHT / 2)
			Kit.stroke(badge, 3.5, Enum.ApplyStrokeMode.Border)
			Kit.gradient(badge, { Theme.Gradients.Aura[1]:Lerp(Theme.White, 0.25), Theme.Gradients.Aura[1], Theme.Gradients.Aura[2] }, 90)
			Icons.make("Aura", {
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, 10, 0.5, -1),
				Size = UDim2.fromOffset(34, 34),
				ZIndex = 4,
				Parent = badge,
			})
			local number = textLabel(badge, badgeText, BADGE_TEXT, 12 + 34 + 4, BADGE_HEIGHT / 2, 4)
			Kit.stroke(number, 3.5)
		end

		-- nick innego gracza pod tytułem (zwykły napis Roblox jest schowany)
		if player ~= localPlayer then
			local name = player.DisplayName
			local width = Kit.measure(name, NAME_SIZE).X + 2
			local nameLabel = textLabel(entry.frame, name, NAME_SIZE, math.floor((WIDTH - width) / 2), TITLE_ROW + NAME_ROW / 2, 3)
			nameLabel:SetAttribute("TagItem", true)
			Kit.stroke(nameLabel, 3.5)
		end
	end

	local function refresh(player)
		local entry = entries[player]
		if entry == nil then
			return
		end
		local character = player.Character
		local head = character and character:FindFirstChild("Head")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local level = player:GetAttribute(LEVEL_ATTRIBUTE)
		local auraLevel = player:GetAttribute(AURA_ATTRIBUTE) or 0
		local busy = State.busy
		local mine = player == localPlayer
		local ready = head ~= nil and type(level) == "number"

		-- napis tuż nad głową (środek napisu = czubek głowy + odstęp + pół wysokości napisu)
		entry.gui.Adornee = head
		if head ~= nil and head:IsA("BasePart") then
			entry.gui.StudsOffset = Vector3.new(0, head.Size.Y / 2 + HEAD_GAP + entry.height / PIXELS_PER_STUD / 2, 0)
		end
		if ready then
			local key = tostring(level) .. ":" .. tostring(auraLevel) .. ":" .. player.DisplayName
			if entry.key ~= key then
				entry.key = key
				build(entry, player, level, auraLevel)
			end
			if not mine and humanoid ~= nil then
				humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			end
		end
		entry.gui.Enabled = ready and not busy

		-- poświata: iskry wokół postaci i światło w kolorze progu Aura Level
		local glow = Formulas.glowFor(auraLevel)
		local show = glow ~= nil and root ~= nil and (mine or not busy)
		if not show then
			clearGlow(entry)
			return
		end
		if entry.emitter == nil or entry.emitter.Parent ~= root or entry.glow ~= glow then
			clearGlow(entry)
			local emitter = Instance.new("ParticleEmitter")
			emitter.Name = "LarpAuraGlow"
			emitter.Texture = SPARKLES
			emitter.Color = glowSequence(glow)
			emitter.LightEmission = 1
			emitter.LightInfluence = 0
			emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 0) })
			emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 1) })
			emitter.Lifetime = NumberRange.new(0.8, 1.4)
			emitter.Rate = (glow == "Rainbow" and 24) or 14
			emitter.Speed = NumberRange.new(1.5, 3)
			emitter.SpreadAngle = Vector2.new(30, 30)
			emitter.EmissionDirection = Enum.NormalId.Top
			emitter.Acceleration = Vector3.new(0, 1.5, 0)
			-- iskry idą razem z postacią: przy szybkim chodzeniu nie zostaje za nią smuga
			emitter.LockedToPart = true
			emitter.Parent = root
			local light = Instance.new("PointLight")
			light.Name = "LarpAuraLight"
			light.Color = Theme.GlowColors[glow] or Theme.Rainbow[5]
			light.Range = 9
			light.Brightness = 1.2
			light.Shadows = false
			light.Parent = root
			entry.emitter = emitter
			entry.light = light
			entry.glow = glow
		end
	end

	local function add(player)
		if entries[player] ~= nil then
			return
		end
		local height = TITLE_ROW
		if player ~= localPlayer then
			height = TITLE_ROW + NAME_ROW
		end
		local gui = Kit.new("BillboardGui", {
			Name = "Nametag_" .. tostring(player.UserId),
			LightInfluence = 0,
			AlwaysOnTop = true, -- inaczej za półprzezroczystym neonem (portal Rebirth) napis blednie
			MaxDistance = MAX_DISTANCE,
			ResetOnSpawn = false,
			Enabled = false,
			Parent = playerGui,
		})
		local frame = Kit.worldFrame(gui, Vector2.new(WIDTH, height), PIXELS_PER_STUD)
		local entry = { gui = gui, frame = frame, height = height }
		entries[player] = entry
		player:GetAttributeChangedSignal(LEVEL_ATTRIBUTE):Connect(function()
			refresh(player)
		end)
		player:GetAttributeChangedSignal(AURA_ATTRIBUTE):Connect(function()
			refresh(player)
		end)
		player.CharacterAdded:Connect(function(character)
			-- głowa, HumanoidRootPart i Humanoid dochodzą chwilę po postaci
			task.spawn(function()
				character:WaitForChild("Head", 10)
				character:WaitForChild("HumanoidRootPart", 10)
				character:WaitForChild("Humanoid", 10)
				refresh(player)
			end)
		end)
		refresh(player)
	end

	local function remove(player)
		local entry = entries[player]
		if entry == nil then
			return
		end
		clearGlow(entry)
		if entry.shine ~= nil then
			entry.shine:Cancel()
		end
		entry.gui:Destroy()
		entries[player] = nil
	end

	for _, player in ipairs(Players:GetPlayers()) do
		add(player)
	end
	Players.PlayerAdded:Connect(add)
	Players.PlayerRemoving:Connect(remove)

	-- początek i koniec aktywności (State.busy) chowa i pokazuje napisy
	local lastBusy = nil
	State.onChange(function()
		if State.busy ~= lastBusy then
			lastBusy = State.busy
			for player in pairs(entries) do
				refresh(player)
			end
		end
	end)
	task.spawn(function()
		-- State.busy zmienia się też bez Sync (np. start aktywności), więc sprawdzamy co chwilę
		while true do
			task.wait(0.5)
			if State.busy ~= lastBusy then
				lastBusy = State.busy
				for player in pairs(entries) do
					refresh(player)
				end
			end
		end
	end)
end

return Nametags
