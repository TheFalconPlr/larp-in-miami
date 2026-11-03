-- Jajka po stronie gracza (jak w Pet Simulator 99):
--   • przy każdym jajku żółta pigułka z ceną,
--   • nad najbliższym jajkiem biały panel z petami, które mogą wypaść, i ich szansami, a przed jajkiem
--     duże „E”. E (klawisz albo kliknięcie) otwiera okno kupna „Would you like to buy a … Egg?”
--     z Buy 1 i Buy 3 (Buy 3 z gamepassem Triple Open),
--   • animacja: 3 pęknięcia (dźwięk, rysy i odpryski), skorupka pęka, pet wkręca się i odbija, za nim
--     promienie i poświata w kolorze rzadkości (przy rzadkich iskry, drżenie i oklaski), napisy
--     wskakują po kolei, a na koniec pet leci do kafelka PETS. W tym czasie HUD jest schowany.
-- Kupno i losowanie robi serwer (PetService); tu jest tylko wygląd.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")
local MarketplaceService = game:GetService("MarketplaceService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared.Config.Economy)
local Format = require(Shared.Format)
local Net = require(Shared.Net)
local PetsConfig = require(Shared.Config.Pets)
local State = require(script.Parent.State)
local Theme = require(script.Parent.Ui.Theme)
local Kit = require(script.Parent.Ui.Kit)
local Icons = require(script.Parent.Ui.Icons)
local Sounds = require(script.Parent.Ui.Sounds)
local PetModels = require(script.Parent.PetModels)
local Pets = require(script.Parent.Pets)

local Eggs = {}

local EGG_TAG = "LarpEgg" -- jak PetService.EggTag na serwerze
local SHOW_DISTANCE = 8 -- panel z petami i E pokazują się, gdy stoisz tak blisko jajka (studs od stoiska)
local HIDE_DISTANCE = 12 -- znikają (razem z oknem kupna), gdy odejdziesz dalej
local TRIPLE = Economy.Robux.Gamepasses.TripleOpen.OpenCount
local BIG_RARITY = { Legendary = true, Mythic = true, Secret = true } -- iskry, drżenie i oklaski

-- Wygląd przy jajku (studs)
local PILL_SIZE = Vector2.new(4.6, 1.4)
local PILL_HEIGHT = 1.7 -- środek pigułki z ceną nad spodem stoiska, na osi jajka
local PANEL_CARD = 2.1 -- miejsce na jednego peta w panelu
local PANEL_PAD = 0.35
local PANEL_BODY = 2.7
local PANEL_TIP = 0.45 -- dzióbek pod panelem
local PANEL_LIFT = 0.6 -- odstęp panelu od czubka jajka
local PANEL_EDGE = Color3.fromRGB(205, 210, 222)

-- Animacja (piksele bazowe 1280×720). Jajka i pety stoją na środku ekranu, napisy pod nimi.
local STAGE_SIZE = Vector2.new(1200, 700)
local STAGE_Y = 0.5
local SLOT_BIG = 420 -- jedno jajko
local SLOT_SMALL = 330 -- trzy jajka obok siebie
local SLOT_SPACING = 370
local BEATS = { 0.27, 0.42, 0.57 } -- pęknięcia (jako część czasu otwierania)
local BURST_AT = 0.66 -- skorupka pęka
local GRAVITY = 1100
local RAY_FADE = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(0.32, 0.8),
	NumberSequenceKeypoint.new(0.5, 0.5),
	NumberSequenceKeypoint.new(0.68, 0.8),
	NumberSequenceKeypoint.new(1, 1),
})

local TEXT = {
	Question = "Would you like to buy a\n%s?",
	Buy = "Buy %d",
	Gamepass = "Gamepass",
	NoPass = "Buy 3 needs the Triple Open gamepass",
	PassSoon = "Triple Open gamepass is coming soon!",
	Inventory = "Not enough room in your pet inventory",
	NewPet = "NEW PET!",
	NewPets = "NEW PETS!",
	RarePet = "%s PET!",
	Equipped = "Equipped!",
}

local RANK = {}
for i, rarity in ipairs(Economy.Pets.RarityOrder) do
	RANK[rarity] = i
end

local function eggName(zone, egg)
	return string.format(PetsConfig.EggNames[egg] or "%s Egg", Economy.Zones[zone].Name)
end

local function eggInfo(zone, egg)
	local list = Economy.Pets.Eggs[zone]
	local info = list and list[egg]
	if info == nil or info.Price == nil then
		return nil
	end
	return info
end

local function raritiesOf(info)
	local list = {}
	for _, rarity in ipairs(Economy.Pets.RarityOrder) do
		if info.Odds[rarity] ~= nil then
			table.insert(list, rarity)
		end
	end
	return list
end

-- Gradient w kolorze rzadkości (sekret: biało-fioletowy, bo jego kolor jest ciemny).
local function rarityColors(rarity)
	local item = Pets.rarityItem(rarity, 20)
	if item.colors ~= nil then
		return item.colors
	end
	local color = item.color or Theme.White
	return { color:Lerp(Theme.White, 0.35), color }
end

local function distanceToPart(part, position)
	local p = part.CFrame:PointToObjectSpace(position)
	local half = part.Size / 2
	local dx = math.max(math.abs(p.X) - half.X, 0)
	local dy = math.max(math.abs(p.Y) - half.Y, 0)
	local dz = math.max(math.abs(p.Z) - half.Z, 0)
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function distanceToStand(stand, position)
	if stand:IsA("BasePart") then
		return distanceToPart(stand, position)
	end
	local best = math.huge
	for _, part in ipairs(stand:GetDescendants()) do
		if part:IsA("BasePart") then
			best = math.min(best, distanceToPart(part, position))
		end
	end
	return best
end

local function biggestPart(stand)
	if stand:IsA("BasePart") then
		return stand
	end
	local best, bestSize = nil, -1
	for _, d in ipairs(stand:GetDescendants()) do
		if d:IsA("BasePart") then
			local size = d.Size.X * d.Size.Y * d.Size.Z
			if size > bestSize then
				best, bestSize = d, size
			end
		end
	end
	return best
end

-- Część, do której przypinamy napisy, oraz góra i dół stoiska względem jej środka (studs).
local function standBounds(stand)
	local part = biggestPart(stand)
	if part == nil then
		return nil, 0, 0
	end
	local top = part.Position.Y + part.Size.Y / 2
	local bottom = part.Position.Y - part.Size.Y / 2
	if stand:IsA("Model") then
		local box, size = stand:GetBoundingBox()
		top = box.Position.Y + size.Y / 2
		bottom = box.Position.Y - size.Y / 2
	end
	return part, top - part.Position.Y, bottom - part.Position.Y
end

function Eggs.start(hud)
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	local stands = {}
	local current = nil -- najbliższe jajko: { stand, zone, egg, key }
	local hatching = false

	local function zoneUnlocked(zone)
		local view = State.view
		return view ~= nil and type(zone) == "number" and (view.ZonesUnlocked or 1) >= zone
	end

	------------------------------------------------------------- Cena przy każdym jajku
	local pills = {} -- [stoisko] = BillboardGui

	local function updatePill(stand)
		local gui = pills[stand]
		if gui == nil then
			return
		end
		local part, _, bottom = standBounds(stand)
		gui.Adornee = part
		if part ~= nil then
			gui.StudsOffsetWorldSpace = Vector3.new(0, bottom + PILL_HEIGHT, 0)
		end
		gui.Enabled = part ~= nil and zoneUnlocked(stand:GetAttribute("Zone"))
	end

	local function makePill(stand)
		local info = eggInfo(stand:GetAttribute("Zone"), stand:GetAttribute("Egg"))
		if info == nil then
			return
		end
		-- zawsze na wierzchu i bez przesunięcia od kamery: pigułka stoi w tym samym miejscu przy jajku
		-- z każdej strony (wcześniej przesuwała się zależnie od kąta kamery i chowała za jajkiem)
		local gui = Kit.new("BillboardGui", {
			Name = "EggPrice",
			Size = UDim2.fromScale(PILL_SIZE.X, PILL_SIZE.Y),
			LightInfluence = 0,
			AlwaysOnTop = true,
			MaxDistance = 70,
			ResetOnSpawn = false,
			Enabled = false,
			Parent = playerGui,
		})
		local face = Kit.new("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Theme.White,
			BorderSizePixel = 0,
			Parent = gui,
		})
		Kit.new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = face })
		Kit.gradient(face, Theme.Gradients.Yellow, 90)
		Kit.stroke(face, 3, Enum.ApplyStrokeMode.Border)
		local coin = Icons.make("Cash", {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromScale(0.05, 0.5),
			Size = UDim2.fromScale(0.26, 0.9),
			ZIndex = 2,
			Parent = face,
		})
		Kit.new("UIAspectRatioConstraint", { AspectRatio = 1, Parent = coin })
		Kit.text(face, {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromScale(0.34, 0.5),
			Size = UDim2.fromScale(0.6, 0.74),
			Text = Format.number(info.Price),
			ZIndex = 2,
		}, { maxSize = 60, stroke = 3 })
		pills[stand] = gui
		updatePill(stand)
	end

	------------------------------------------------------------- Panel z petami nad jajkiem
	local panelGui = Kit.new("BillboardGui", {
		Name = "EggChances",
		Size = UDim2.fromScale(10, PANEL_BODY + PANEL_TIP),
		LightInfluence = 0,
		AlwaysOnTop = true,
		MaxDistance = 80,
		ResetOnSpawn = false,
		Enabled = false,
		Parent = playerGui,
	})
	local panelKey = nil

	local function renderPanel(zone, egg)
		for _, child in ipairs(panelGui:GetChildren()) do
			child:Destroy()
		end
		local info = eggInfo(zone, egg)
		if info == nil then
			return
		end
		local list = raritiesOf(info)
		local width = #list * PANEL_CARD + 2 * PANEL_PAD
		local height = PANEL_BODY + PANEL_TIP
		local bodyHeight = PANEL_BODY / height
		panelGui.Size = UDim2.fromScale(width, height)
		local body = Kit.new("Frame", {
			Name = "Body",
			Size = UDim2.fromScale(1, bodyHeight),
			BackgroundColor3 = Theme.White,
			BorderSizePixel = 0,
			ZIndex = 2,
			Parent = panelGui,
		})
		Kit.new("UICorner", { CornerRadius = UDim.new(0.2, 0), Parent = body })
		Kit.stroke(body, 2, Enum.ApplyStrokeMode.Border, PANEL_EDGE)
		-- dzióbek: obrócony kwadrat, którego górna połowa chowa się w panelu
		local tip = PANEL_TIP * 1.4
		Kit.new("Frame", {
			Name = "Tip",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, bodyHeight - 0.03),
			Size = UDim2.fromScale(tip / width, tip / height),
			Rotation = 45,
			BackgroundColor3 = Theme.White,
			BorderSizePixel = 0,
			ZIndex = 3,
			Parent = panelGui,
		})
		for i, rarity in ipairs(list) do
			local color = PetsConfig.RarityColors[rarity] or Theme.White
			local card = Kit.new("Frame", {
				Name = rarity,
				Position = UDim2.fromScale((PANEL_PAD + (i - 1) * PANEL_CARD) / width, 0),
				Size = UDim2.fromScale(PANEL_CARD / width, 1),
				BackgroundTransparency = 1,
				ZIndex = 4,
				Parent = body,
			})
			local tile = Kit.new("Frame", {
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.fromScale(0.5, 0.94),
				Size = UDim2.fromScale(0.88, 0.64),
				BackgroundColor3 = color:Lerp(Theme.White, 0.7),
				BorderSizePixel = 0,
				ZIndex = 4,
				Parent = card,
			})
			Kit.new("UICorner", { CornerRadius = UDim.new(0.22, 0), Parent = tile })
			local viewport = Kit.new("ViewportFrame", {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Ambient = Color3.fromRGB(200, 200, 210),
				LightColor = Color3.new(1, 1, 1),
				ZIndex = 5,
				Parent = tile,
			})
			PetModels.show(viewport, PetModels.pet(zone, rarity), 1.3)
			local item = Pets.rarityItem(rarity, 20)
			Kit.text(card, {
				Position = UDim2.fromScale(0, 0.03),
				Size = UDim2.fromScale(1, 0.27),
				Text = Format.percent(info.Odds[rarity]),
				TextColor3 = item.color or Theme.White,
				ZIndex = 6,
			}, { maxSize = 60, stroke = 2.5, gradient = item.colors })
		end
	end

	------------------------------------------------------------- Duże E przed jajkiem
	local promptGui = Kit.new("BillboardGui", {
		Name = "EggPrompt",
		Size = UDim2.fromOffset(190, 190),
		LightInfluence = 0,
		AlwaysOnTop = true,
		Active = true,
		MaxDistance = 80,
		ResetOnSpawn = false,
		Enabled = false,
		Parent = playerGui,
	})
	local promptHolder = Kit.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(92, 92),
		BackgroundTransparency = 1,
		Parent = promptGui,
	})
	hud.registerScale(promptHolder)
	-- środek w środku: pulsowanie E rośnie od środka, a nie od lewego górnego rogu
	local promptInner = Kit.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = promptHolder,
	})
	local promptBob = Kit.new("UIScale", { Parent = promptInner })
	local promptEdge = Kit.new("Frame", {
		Position = UDim2.fromOffset(0, 6),
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Outline,
		BorderSizePixel = 0,
		ZIndex = 1,
		Parent = promptInner,
	})
	Kit.corner(promptEdge, 24)
	local promptButton = Kit.new("TextButton", {
		Name = "E",
		Active = true, -- w BillboardGui przycisk działa tylko, gdy Active mają i okno, i przycisk
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.White,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Font = Theme.Font,
		Text = "E",
		TextColor3 = Theme.Dark,
		TextScaled = true,
		ZIndex = 2,
		Parent = promptInner,
	})
	Kit.corner(promptButton, 24)
	Kit.stroke(promptButton, 4, Enum.ApplyStrokeMode.Border)
	Kit.new("UIPadding", {
		PaddingTop = UDim.new(0, 12),
		PaddingBottom = UDim.new(0, 12),
		PaddingLeft = UDim.new(0, 12),
		PaddingRight = UDim.new(0, 12),
		Parent = promptButton,
	})
	-- na telefonie (bez klawiatury) zamiast litery jest ikona kliknięcia
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		promptButton.Text = ""
		Icons.make("Click", {
			Size = UDim2.fromScale(1, 1),
			ZIndex = 3,
			Parent = promptButton,
		})
	end
	TweenService:Create(promptBob, TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = 1.07 }):Play()

	-- Panel nad czubkiem jajka, E na środku jajka.
	local function placePrompt(stand)
		local part, top, bottom = standBounds(stand)
		panelGui.Adornee = part
		promptGui.Adornee = part
		if part ~= nil then
			panelGui.StudsOffsetWorldSpace = Vector3.new(0, top + PANEL_LIFT + (PANEL_BODY + PANEL_TIP) / 2, 0)
			promptGui.StudsOffsetWorldSpace = Vector3.new(0, (top + bottom) / 2 + 0.4, 0)
		end
	end

	------------------------------------------------------------- Stoiska
	local function onStandAdded(stand)
		for _, existing in ipairs(stands) do
			if existing == stand then
				return
			end
		end
		table.insert(stands, stand)
		makePill(stand)
		-- przy StreamingEnabled części stoiska mogą dojść później
		stand.DescendantAdded:Connect(function(d)
			if d:IsA("BasePart") then
				updatePill(stand)
				if current ~= nil and current.stand == stand then
					placePrompt(stand)
				end
			end
		end)
	end

	local function onStandRemoved(stand)
		for i = #stands, 1, -1 do
			if stands[i] == stand then
				table.remove(stands, i)
			end
		end
		if pills[stand] ~= nil then
			pills[stand]:Destroy()
			pills[stand] = nil
		end
	end

	------------------------------------------------------------- Okno kupna
	local dialog = Kit.panel(hud.gui, {
		name = "EggBuy",
		size = Vector2.new(620, 440),
		title = "",
		padding = 30,
		top = 28,
		bottom = 26,
	})
	hud.registerScale(dialog.holder)
	hud.addPopup(dialog)
	local question = Kit.text(dialog.content, {
		Name = "Question",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 0),
		Size = UDim2.new(1, 0, 0, 104),
		Text = "",
		TextColor3 = Theme.Dark,
		TextWrapped = true,
		ZIndex = 4,
	}, { maxSize = 44, stroke = 0 })
	local eggView = Kit.new("ViewportFrame", {
		Name = "Egg",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 108),
		Size = UDim2.fromOffset(210, 150),
		BackgroundTransparency = 1,
		Ambient = Color3.fromRGB(205, 205, 215),
		LightColor = Color3.new(1, 1, 1),
		ZIndex = 4,
		Parent = dialog.content,
	})
	local columns = {}
	for i, count in ipairs({ 1, TRIPLE }) do
		local x = 0.26
		if i == 2 then
			x = 0.74
		end
		local priceLine = Kit.line(dialog.content, {
			anchor = Vector2.new(0.5, 1),
			position = UDim2.new(x, 0, 1, -78),
			height = 44,
		})
		priceLine.holder.ZIndex = 4
		local button = Kit.button(dialog.content, {
			name = "Buy" .. count,
			size = Vector2.new(230, 68),
			text = string.format(TEXT.Buy, count),
			colors = Theme.Gradients.Green,
			anchor = Vector2.new(0.5, 1),
			position = UDim2.new(x, 0, 1, 0),
			textSize = 36,
		})
		columns[i] = { count = count, price = priceLine, button = button }
	end
	local dialogEgg = nil
	local dialogEggKind = nil

	local function renderDialog()
		local info = current and eggInfo(current.zone, current.egg)
		local view = State.view
		if info == nil or view == nil then
			return
		end
		question.Text = string.format(TEXT.Question, eggName(current.zone, current.egg))
		local passes = view.Passes or {}
		for _, column in ipairs(columns) do
			local total = info.Price * column.count
			if column.count > 1 and not passes.TripleOpen then
				column.price.set({ { icon = "Lock", size = 36 }, { text = TEXT.Gamepass, size = 28 } })
				column.button.setColors(Theme.Gradients.Gray)
			else
				column.price.set({
					{ icon = "Cash", size = 40 },
					{ text = Format.number(total), size = 32, colors = Theme.Gradients.Gold },
				})
				if view.Cash >= total then
					column.button.setColors(Theme.Gradients.Green)
				else
					column.button.setColors(Theme.Gradients.Gray)
				end
			end
		end
	end

	local function openDialog()
		if current == nil or hatching or State.busy then
			return
		end
		if dialogEggKind ~= current.egg then
			dialogEggKind = current.egg
			dialogEgg = PetModels.eggWithCoins(current.egg)
			PetModels.show(eggView, dialogEgg, 1.05)
		end
		renderDialog()
		panelGui.Enabled = false
		promptGui.Enabled = false
		dialog.open()
	end

	-- jajko w oknie lekko się kołysze
	RunService.RenderStepped:Connect(function()
		if dialogEgg ~= nil and dialog.isOpen() then
			dialogEgg:PivotTo(CFrame.Angles(0, math.sin(os.clock() * 1.3) * 0.4, 0))
		end
	end)

	------------------------------------------------------------- Animacja otwierania
	local hatchGui = Kit.new("ScreenGui", {
		Name = "LarpHatch",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 16,
		Enabled = false,
		Parent = playerGui,
	})
	local dim = Kit.new("Frame", {
		Name = "Dim",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = hatchGui,
	})
	local stage = Kit.new("Frame", {
		Name = "Stage",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, STAGE_Y),
		Size = UDim2.fromOffset(STAGE_SIZE.X, STAGE_SIZE.Y),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = hatchGui,
	})
	hud.registerScale(stage)
	local fx = Kit.new("Frame", {
		Name = "Fx",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 9,
		Parent = stage,
	})
	local flash = Kit.new("Frame", {
		Name = "Flash",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 20,
		Parent = hatchGui,
	})
	local banner = Kit.line(stage, { name = "Banner", anchor = Vector2.new(0.5, 0.5), position = UDim2.new(0.5, 0, 0, 96), height = 60 })
	banner.holder.ZIndex = 8
	local bannerScale = Kit.new("UIScale", { Scale = 0, Parent = banner.holder })

	local slots = {}
	local particles = {}
	local phase = "idle" -- idle, shake, reveal, exit
	local shakeStart, shakeLength = 0, 1
	local kickTime, kickDir = -math.huge, 1
	local shakeUntil = 0
	local animConnection = nil

	local function popIn(uiScale, delay, time)
		uiScale.Scale = 0
		task.delay(delay, function()
			TweenService:Create(uiScale, TweenInfo.new(time or 0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end)
	end

	-- Odprysk skorupki („chip”, spada) albo iskra („spark”, krzyżyk, który rośnie i znika).
	-- Pozycja i prędkość w pikselach sceny.
	local function spawnParticle(kind, position, velocity, color, size, life)
		local frame = Kit.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(position.X, position.Y),
			Size = UDim2.fromOffset(size, size),
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			Rotation = math.random(0, 90),
			ZIndex = 9,
			Parent = fx,
		})
		local stroke = nil
		if kind == "chip" then
			stroke = Kit.stroke(frame, 2, Enum.ApplyStrokeMode.Border)
		else
			frame.BackgroundTransparency = 1
			for _, bar in ipairs({ UDim2.fromScale(1, 0.22), UDim2.fromScale(0.22, 1) }) do
				local piece = Kit.new("Frame", {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(0.5, 0.5),
					Size = bar,
					BackgroundColor3 = color,
					BorderSizePixel = 0,
					ZIndex = 9,
					Parent = frame,
				})
				Kit.new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = piece })
			end
		end
		table.insert(particles, {
			kind = kind,
			frame = frame,
			stroke = stroke,
			position = position,
			velocity = velocity,
			size = size,
			life = life,
			age = 0,
			spin = math.random(-360, 360),
		})
	end

	local function updateParticles(dt)
		for i = #particles, 1, -1 do
			local p = particles[i]
			p.age = p.age + dt
			if p.age >= p.life then
				p.frame:Destroy()
				table.remove(particles, i)
			else
				local k = p.age / p.life
				if p.kind == "chip" then
					p.velocity = p.velocity + Vector2.new(0, GRAVITY * dt)
					p.position = p.position + p.velocity * dt
					p.frame.Rotation = p.frame.Rotation + p.spin * dt
					local fade = math.clamp((k - 0.55) / 0.45, 0, 1)
					p.frame.BackgroundTransparency = fade
					p.stroke.Transparency = fade
				else
					p.position = p.position + p.velocity * dt
					local s = math.sin(k * math.pi)
					p.frame.Size = UDim2.fromOffset(p.size * s, p.size * s)
					p.frame.Rotation = p.frame.Rotation + 90 * dt
				end
				p.frame.Position = UDim2.fromOffset(p.position.X, p.position.Y)
			end
		end
	end

	-- Miejsce na jedno jajko i peta (1 na środku albo 3 obok siebie). Wszystko skaluje się od środka.
	local function makeSlot(index, count, pet)
		local big = count == 1
		local size, spacing = SLOT_SMALL, SLOT_SPACING
		if big then
			size, spacing = SLOT_BIG, 0
		end
		local x = (index - (count + 1) / 2) * spacing
		local color = PetsConfig.RarityColors[pet.Rarity] or Theme.White
		local holder = Kit.new("Frame", {
			Name = "Slot" .. index,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, x, 0.5, 0),
			Size = UDim2.fromOffset(size, size),
			BackgroundTransparency = 1,
			ZIndex = 2,
			Parent = stage,
		})
		local holderScale = Kit.new("UIScale", { Parent = holder })
		-- promienie: 8 pasków przez środek, czyli 16 promieni
		local rayLength = size * 1.55
		local rays = Kit.new("Frame", {
			Name = "Rays",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(rayLength, rayLength),
			BackgroundTransparency = 1,
			Visible = false,
			ZIndex = 2,
			Parent = holder,
		})
		local raysScale = Kit.new("UIScale", { Parent = rays })
		local bars = {}
		for i = 1, 8 do
			local bar = Kit.new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.new(0, math.floor(size * 0.15), 1, 0),
				BackgroundColor3 = color,
				BorderSizePixel = 0,
				Rotation = (i - 1) * 22.5,
				ZIndex = 2,
				Parent = rays,
			})
			Kit.new("UIGradient", { Rotation = 90, Transparency = RAY_FADE, Parent = bar })
			bars[i] = bar
		end
		-- poświata w kolorze rzadkości
		local glow = Kit.new("Frame", {
			Name = "Glow",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(size * 0.84, size * 0.84),
			BackgroundColor3 = color,
			BackgroundTransparency = 0.5,
			BorderSizePixel = 0,
			Visible = false,
			ZIndex = 3,
			Parent = holder,
		})
		Kit.new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = glow })
		local glowStroke = Kit.stroke(glow, 8, Enum.ApplyStrokeMode.Border, color)
		glowStroke.Transparency = 0.3
		local glowScale = Kit.new("UIScale", { Parent = glow })
		-- jajko, a potem pet (jolt = podskok przy pęknięciu, pop = pojawienie się)
		local jolt = Kit.new("Frame", {
			Name = "Jolt",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ZIndex = 4,
			Parent = holder,
		})
		local joltScale = Kit.new("UIScale", { Parent = jolt })
		local viewport = Kit.new("ViewportFrame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Ambient = Color3.fromRGB(210, 210, 220),
			LightColor = Color3.new(1, 1, 1),
			ZIndex = 4,
			Parent = jolt,
		})
		local pop = Kit.new("UIScale", { Parent = viewport })
		-- napisy pod jajkiem (poza ramką slotu), każdy wskakuje od swojego środka
		local function line(y, height)
			local l = Kit.line(holder, {
				anchor = Vector2.new(0.5, 0.5),
				position = UDim2.new(0.5, 0, 0, y + height / 2),
				height = height,
			})
			l.holder.ZIndex = 6
			l.scale = Kit.new("UIScale", { Scale = 0, Parent = l.holder })
			return l
		end
		local nameH, infoH, equippedH = 38, 32, 28
		if big then
			nameH, infoH, equippedH = 52, 40, 34
		end
		return {
			big = big,
			size = size,
			pet = pet,
			color = color,
			sparkColor = rarityColors(pet.Rarity)[1],
			center = Vector2.new(STAGE_SIZE.X / 2 + x, STAGE_SIZE.Y / 2),
			holder = holder,
			holderScale = holderScale,
			rays = rays,
			raysScale = raysScale,
			bars = bars,
			glow = glow,
			glowScale = glowScale,
			jolt = jolt,
			joltScale = joltScale,
			viewport = viewport,
			pop = pop,
			nameLine = line(size + 4, nameH),
			infoLine = line(size + 4 + nameH, infoH),
			equippedLine = line(size + 6 + nameH + infoH, equippedH),
			wobble = math.random() * 6.28,
			nextSpark = 0,
		}
	end

	local function animate(dt)
		local now = os.clock()
		if phase == "shake" then
			local e = now - shakeStart
			local progress = math.clamp(e / shakeLength, 0, 1)
			local impulse = math.exp(-(now - kickTime) * 9)
			for _, slot in ipairs(slots) do
				if slot.eggModel ~= nil then
					local angle = math.sin(e * (11 + 16 * progress) + slot.wobble) * math.rad(3 + 9 * progress)
						+ kickDir * impulse * math.rad(13)
					slot.eggModel:PivotTo(CFrame.Angles(0, 0, angle))
				end
				slot.jolt.Position = UDim2.new(0.5, 0, 0.5, -20 * impulse)
				slot.joltScale.Scale = 1 + 0.1 * impulse
			end
		elseif phase == "reveal" or phase == "exit" then
			for _, slot in ipairs(slots) do
				local e = now - (slot.revealStart or now)
				if slot.petModel ~= nil then
					-- pet wkręca się (cały obrót, coraz wolniej), potem lekko się kołysze i unosi
					local yaw
					if e < 0.6 then
						yaw = -2 * math.pi * (1 - e / 0.6) ^ 3
					else
						yaw = math.sin((e - 0.6) * 1.6) * 0.3
					end
					local bob = math.sin(e * 3) * (slot.petSize or 3) * 0.03
					slot.petModel:PivotTo(CFrame.new(0, bob, 0) * CFrame.Angles(0, yaw, 0))
				end
				for i, bar in ipairs(slot.bars) do
					bar.Rotation = (i - 1) * 22.5 + e * 28
				end
				if phase == "reveal" and e > 0.45 then
					slot.glowScale.Scale = 1 + math.sin(e * 4) * 0.04
				end
				if phase == "reveal" and BIG_RARITY[slot.pet.Rarity] and now >= slot.nextSpark then
					slot.nextSpark = now + 0.07
					local angle = math.random() * math.pi * 2
					local radius = slot.size * (0.2 + math.random() * 0.32)
					local position = slot.center + Vector2.new(math.cos(angle), math.sin(angle)) * radius
					local color = Theme.White
					if math.random() < 0.5 then
						color = slot.sparkColor
					end
					spawnParticle("spark", position, Vector2.new(0, -40), color, math.random(16, 28), 0.6)
				end
			end
		end
		updateParticles(dt)
		if now < shakeUntil then
			stage.Position = UDim2.new(0.5, math.random(-7, 7), STAGE_Y, math.random(-7, 7))
		else
			stage.Position = UDim2.fromScale(0.5, STAGE_Y)
		end
	end

	-- Pęknięcie k (1–3): dźwięk coraz wyżej, rysy na jajku, odpryski i podskok.
	local function crackBeat(k, egg)
		local eggColor = PetModels.eggColor(egg)
		for _, slot in ipairs(slots) do
			if slot.eggModel ~= nil then
				PetModels.crack(slot.eggModel, k)
			end
			for _ = 1, 2 + k do
				local angle = math.rad(math.random(200, 340))
				local dir = Vector2.new(math.cos(angle), math.sin(angle))
				spawnParticle("chip", slot.center + dir * slot.size * 0.3, dir * math.random(220, 400), eggColor, math.random(7, 13), 0.75)
			end
		end
		Sounds.play("Crack", { pitch = 1 + 0.12 * (k - 1) + math.random() * 0.04 })
		kickTime = os.clock()
		kickDir = -kickDir
	end

	-- Skorupka pęka: błysk, odłamki, pet, promienie, poświata i napisy po kolei.
	local function burst(egg)
		local now = os.clock()
		local eggColor = PetModels.eggColor(egg)
		phase = "reveal"
		flash.BackgroundTransparency = 0
		TweenService:Create(flash, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 }):Play()
		-- rozbicie: dwa pęknięcia naraz (niskie i wysokie) i dźwięk nowego peta
		Sounds.play("Crack", { pitch = 0.82, volume = 1.3 })
		task.delay(0.05, function()
			Sounds.play("Crack", { pitch = 1.3, volume = 0.8 })
		end)
		Sounds.play("Hatch")
		local best = nil
		for _, slot in ipairs(slots) do
			if best == nil or RANK[slot.pet.Rarity] > RANK[best] then
				best = slot.pet.Rarity
			end
		end
		if BIG_RARITY[best] then
			shakeUntil = now + 0.45
			task.delay(0.2, function()
				Sounds.play("Reward")
			end)
		end
		for i, slot in ipairs(slots) do
			slot.jolt.Position = UDim2.fromScale(0.5, 0.5)
			slot.joltScale.Scale = 1
			for n = 1, 12 do
				local angle = math.rad(n * 30 + math.random(-12, 12))
				local dir = Vector2.new(math.cos(angle), math.sin(angle))
				spawnParticle("chip", slot.center + dir * slot.size * 0.18, dir * math.random(320, 560), eggColor, math.random(10, 18), 0.95)
			end
			local pet = slot.pet
			slot.eggModel = nil
			slot.petModel = PetModels.pet(pet.Zone, pet.Rarity)
			PetModels.show(slot.viewport, slot.petModel, 1.55)
			slot.petSize = slot.petModel:GetExtentsSize().Magnitude
			slot.revealStart = now
			slot.pop.Scale = 0.15
			TweenService:Create(slot.pop, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
			slot.glow.Visible = true
			slot.glowScale.Scale = 0.3
			TweenService:Create(slot.glowScale, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
			slot.rays.Visible = true
			slot.raysScale.Scale = 0
			TweenService:Create(slot.raysScale, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1 }):Play()
			local delay = 0.1 + (i - 1) * 0.06
			local nameSize, infoSize, powerSize, equippedSize = 30, 22, 21, 19
			if slot.big then
				nameSize, infoSize, powerSize, equippedSize = 44, 30, 28, 24
			end
			slot.nameLine.set({ { text = PetsConfig.name(pet.Zone, pet.Rarity), size = nameSize } })
			popIn(slot.nameLine.scale, delay)
			slot.infoLine.set({
				Pets.rarityItem(pet.Rarity, infoSize),
				{ text = Pets.powerText(pet), size = powerSize, colors = Theme.Gradients.Gold },
			})
			popIn(slot.infoLine.scale, delay + 0.12)
			if pet.Equipped then
				slot.equippedLine.set({ { text = TEXT.Equipped, size = equippedSize, colors = Theme.Gradients.Green } })
				popIn(slot.equippedLine.scale, delay + 0.24)
			end
		end
		local text = TEXT.NewPet
		if #slots > 1 then
			text = TEXT.NewPets
		end
		local colors = Theme.Gradients.Gold
		if BIG_RARITY[best] then
			text = string.format(TEXT.RarePet, string.upper(best))
			colors = rarityColors(best)
		end
		banner.set({ { text = text, size = 46, colors = colors } })
		popIn(bannerScale, 0, 0.35)
	end

	-- Koniec: HUD wraca, a pety lecą do kafelka PETS (kafelek podskakuje).
	local function exit()
		phase = "exit"
		hud.setVisible(true)
		TweenService:Create(dim, TweenInfo.new(0.35), { BackgroundTransparency = 1 }):Play()
		TweenService:Create(bannerScale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Scale = 0 }):Play()
		local target = Pets.tileCenter()
		local inset = GuiService:GetGuiInset()
		for i, slot in ipairs(slots) do
			if target ~= nil then
				-- pet wychodzi ze sceny na wierzch ekranu i leci do kafelka (HUD liczy pozycje bez górnego paska)
				local viewport = slot.viewport
				local position, size = viewport.AbsolutePosition, viewport.AbsoluteSize
				viewport.AnchorPoint = Vector2.new(0.5, 0.5)
				viewport.Position = UDim2.fromOffset(position.X + size.X / 2, position.Y + size.Y / 2)
				viewport.Size = UDim2.fromOffset(size.X, size.Y)
				viewport.ZIndex = 12
				viewport.Parent = hatchGui
				local goal = target + inset
				local fly = TweenService:Create(viewport, TweenInfo.new(0.42, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
					Position = UDim2.fromOffset(goal.X, goal.Y),
					Size = UDim2.fromOffset(40, 40),
				})
				local delay = (i - 1) * 0.07
				task.delay(delay, function()
					fly:Play()
				end)
				task.delay(delay + 0.42, function()
					viewport.Visible = false
					Pets.bump()
				end)
			end
			TweenService:Create(slot.holderScale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Scale = 0 }):Play()
		end
	end

	local function clearHatch()
		for _, p in ipairs(particles) do
			p.frame:Destroy()
		end
		particles = {}
		for _, slot in ipairs(slots) do
			slot.holder:Destroy()
			slot.viewport:Destroy()
		end
		slots = {}
	end

	local function waitUntil(t)
		local d = t - os.clock()
		if d > 0 then
			task.wait(d)
		end
	end

	local function runHatch(egg, pets, total)
		clearHatch()
		for i, pet in ipairs(pets) do
			local slot = makeSlot(i, #pets, pet)
			slot.eggModel = PetModels.egg(egg)
			PetModels.show(slot.viewport, slot.eggModel, 1.3)
			slot.pop.Scale = 0.35
			TweenService:Create(slot.pop, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
			slots[i] = slot
		end
		banner.set({})
		bannerScale.Scale = 0
		local slotSize = SLOT_SMALL
		if #pets == 1 then
			slotSize = SLOT_BIG
		end
		banner.holder.Position = UDim2.new(0.5, 0, 0, STAGE_SIZE.Y / 2 - slotSize / 2 - 44)
		stage.Position = UDim2.fromScale(0.5, STAGE_Y)
		dim.BackgroundTransparency = 1
		hatchGui.Enabled = true
		TweenService:Create(dim, TweenInfo.new(0.25), { BackgroundTransparency = 0.3 }):Play()
		local start = os.clock()
		phase = "shake"
		shakeStart = start
		shakeLength = total * BURST_AT
		kickTime = -math.huge
		animConnection = RunService.RenderStepped:Connect(animate)
		for k, at in ipairs(BEATS) do
			waitUntil(start + at * total)
			crackBeat(k, egg)
		end
		waitUntil(start + BURST_AT * total)
		burst(egg)
		task.wait(math.max(0.9, total * 0.5))
		exit()
		task.wait(0.6)
	end

	-- Cała animacja; State.busy blokuje w tym czasie klikanie i okna. Po błędzie stan i tak wraca.
	local function hatch(egg, pets, total)
		hatching = true
		State.busy = true
		panelGui.Enabled = false
		promptGui.Enabled = false
		hud.setVisible(false)
		local ok, err = pcall(runHatch, egg, pets, total)
		if not ok then
			warn("[Jajka] animacja otwierania: " .. tostring(err))
		end
		if animConnection ~= nil then
			animConnection:Disconnect()
			animConnection = nil
		end
		phase = "idle"
		shakeUntil = 0
		clearHatch()
		hatchGui.Enabled = false
		hud.setVisible(true)
		State.busy = false
		hatching = false
	end

	------------------------------------------------------------- Kupno
	local requesting = false
	local function buy(column)
		if requesting or hatching or current == nil then
			return
		end
		local view = State.view
		local passes = (view and view.Passes) or {}
		if column.count > 1 and not passes.TripleOpen then
			local id = Economy.Robux.Gamepasses.TripleOpen.Id
			if type(id) == "number" and id > 0 then
				pcall(function()
					MarketplaceService:PromptGamePassPurchase(player, id)
				end)
			else
				Sounds.play("NotEnough")
				hud.toast({ { text = TEXT.PassSoon, size = 26, colors = Theme.Gradients.Gold } }, "TripleOpen")
			end
			return
		end
		requesting = true
		local zone, egg = current.zone, current.egg
		local ok, result = pcall(function()
			return Net.func("BuyEgg"):InvokeServer(zone, egg, column.count)
		end)
		requesting = false
		if not ok or type(result) ~= "table" then
			return
		end
		if result.Ok and type(result.Pets) == "table" and #result.Pets > 0 then
			dialog.hide()
			hatch(egg, result.Pets, result.OpenTime or Economy.OpenTimeSeconds)
		elseif result.Reason == "NotEnough" then
			hud.notEnough(column.button)
		elseif result.Reason == "Inventory" then
			Sounds.play("NotEnough")
			hud.toast({ { text = TEXT.Inventory, size = 26, colors = Theme.Gradients.Red } }, "PetInventory")
		elseif result.Reason == "NoPass" then
			Sounds.play("NotEnough")
			hud.toast({ { text = TEXT.NoPass, size = 26, colors = Theme.Gradients.Red } }, "TripleOpen")
		end
	end

	for _, column in ipairs(columns) do
		column.button.Activated:Connect(function()
			buy(column)
		end)
	end

	promptButton.Activated:Connect(function()
		Sounds.play("Button")
		openDialog()
	end)
	-- klawisz E: otwiera okno kupna przy jajku, a drugie E je zamyka
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or input.KeyCode ~= Enum.KeyCode.E or hatching then
			return
		end
		if dialog.isOpen() then
			dialog.hide()
		elseif promptGui.Enabled then
			Sounds.play("Button")
			openDialog()
		end
	end)

	------------------------------------------------------------- Najbliższe jajko
	local function setCurrent(stand)
		if stand == nil then
			current = nil
			if dialog.isOpen() then
				dialog.hide()
			end
			return
		end
		local zone, egg = stand:GetAttribute("Zone"), stand:GetAttribute("Egg")
		current = { stand = stand, zone = zone, egg = egg, key = tostring(zone) .. tostring(egg) }
		placePrompt(stand)
		if panelKey ~= current.key then
			panelKey = current.key
			renderPanel(zone, egg)
		end
	end

	local function nearestStand(position)
		local best, bestDistance = nil, math.huge
		for _, stand in ipairs(stands) do
			if stand.Parent ~= nil and zoneUnlocked(stand:GetAttribute("Zone")) then
				local d = distanceToStand(stand, position)
				if d < bestDistance then
					best, bestDistance = stand, d
				end
			end
		end
		return best, bestDistance
	end

	local timer = 0
	RunService.Heartbeat:Connect(function(dt)
		timer = timer + dt
		if timer < 0.1 then
			return
		end
		timer = 0
		if hatching then
			return
		end
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root == nil or State.view == nil or State.busy or hud.windowOpen() then
			setCurrent(nil)
		else
			local position = root.Position
			if current ~= nil then
				local d = math.huge
				if current.stand.Parent ~= nil and zoneUnlocked(current.zone) then
					d = distanceToStand(current.stand, position)
				end
				if d > HIDE_DISTANCE then
					setCurrent(nil)
				end
			end
			local best, bestDistance = nearestStand(position)
			if best ~= nil and bestDistance <= SHOW_DISTANCE then
				if current == nil or (best ~= current.stand and not dialog.isOpen()) then
					setCurrent(best)
				end
			end
		end
		local show = current ~= nil and not dialog.isOpen()
		panelGui.Enabled = show
		promptGui.Enabled = show
	end)

	local lastUnlocked = nil
	State.onChange(function(view)
		if view.ZonesUnlocked ~= lastUnlocked then
			lastUnlocked = view.ZonesUnlocked
			for _, stand in ipairs(stands) do
				updatePill(stand)
			end
		end
		if dialog.isOpen() then
			renderDialog()
		end
	end)

	for _, stand in ipairs(CollectionService:GetTagged(EGG_TAG)) do
		onStandAdded(stand)
	end
	CollectionService:GetInstanceAddedSignal(EGG_TAG):Connect(onStandAdded)
	CollectionService:GetInstanceRemovedSignal(EGG_TAG):Connect(onStandRemoved)
end

return Eggs
