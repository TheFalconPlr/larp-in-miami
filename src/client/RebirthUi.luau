-- Rebirth po stronie gracza (Etap 9): stoisko Rebirth na lotnisku (portal), okno Rebirth i animacja.
--   • nad portalem napis „REBIRTH” z następnym tytułem, a blisko duże E (klawisz albo kliknięcie),
--   • okno: tytuł teraz → po Rebirthie, co dostajesz (mnożnik LP, Aura, szybkość, slot na peta),
--     co się zeruje, a co zostaje, opłata i przycisk REBIRTH z potwierdzeniem,
--   • animacja po Rebirthie (także z komendy /rb): promienie, „REBIRTH!”, nowy tytuł, mnożnik LP
--     i „+X AURA”; ekran ciemnieje, gdy serwer przenosi gracza na spawn, i jaśnieje już w Downtown.
-- Rebirth robi serwer (RebirthService); tu jest tylko wygląd.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared.Config.Economy)
local Format = require(Shared.Format)
local Formulas = require(Shared.Formulas)
local Rebirth = require(Shared.Logic.Rebirth)
local Net = require(Shared.Net)
local State = require(script.Parent.State)
local Theme = require(script.Parent.Ui.Theme)
local Kit = require(script.Parent.Ui.Kit)
local Icons = require(script.Parent.Ui.Icons)
local Sounds = require(script.Parent.Ui.Sounds)
local StandAnchor = require(script.Parent.StandAnchor)

local RebirthUi = {}

local STAND_TAG = "LarpRebirth" -- jak RebirthService.RebirthTag na serwerze
local SHOW_DISTANCE = 10
local HIDE_DISTANCE = 14
-- Napis nad portalem: rozmiar w studs (Kit.worldFrame), więc z daleka maleje jak portal (wcześniej miał
-- stały rozmiar w pikselach i z daleka wyglądał na wielki).
local LABEL_HEIGHT = 2.1 -- środek napisu nad czubkiem portalu (studs)
local LABEL_DESIGN = Vector2.new(460, 60) -- piksele bazowe…
local LABEL_PIXELS_PER_STUD = 26 -- …i tyle na stud: napis ma ok. 18 × 2,3 studs
local LABEL_DISTANCE = 75 -- widać go z tylu studs od kamery
local RAYS = 12

local TEXT = {
	Title = "Rebirth",
	Label = "REBIRTH",
	Of = "Rebirth %d of %d",
	AfterCap = "Rebirth %d · max level",
	LP = "LP",
	Aura = "Aura",
	AuraShop = "· opens the Aura Shop",
	Speed = "+%s%% walk speed",
	PetSlot = "+%d pet slot",
	MaxLevel = "Max level: no new multiplier or title",
	Resets = "Resets:",
	ResetsList = "L$, Bag, upgrades, zones, cars, yachts and jets",
	Keeps = "Keeps:",
	KeepsList = "pets, clothes, Aura and Robux items",
	Locked = "Unlock %s first",
	Button = "REBIRTH",
	ConfirmTitle = "Rebirth now?",
	ConfirmText = "You keep pets, clothes and Aura,",
	ConfirmText2 = "but lose L$, upgrades and zones.",
	ConfirmYes = "REBIRTH!",
	ConfirmNo = "NOT YET",
	Big = "REBIRTH!",
	Level = "Rebirth %d",
	Multiplier = "LP ×%s",
	AuraGained = "+%s AURA",
	ShopOpen = "Aura Shop unlocked at spawn!",
	Slots = "+%d pet slot!",
	TooFar = "Walk up to the portal",
}

local function titleColors(level)
	return Theme.TitleColors[level] or Theme.TitleColors[Rebirth.Cap]
end

local function multiplierText(level)
	return Format.small(Economy.Rebirth.LPMultiplier[level] or 1)
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

function RebirthUi.start(hud)
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	local stands = {}
	local current = nil -- najbliższy portal
	local playing = false
	local window = nil -- okno Rebirth (niżej); przy otwartym oknie napis nad portalem jest schowany

	------------------------------------------------------------- Napis nad każdym portalem
	local labels = {} -- [stoisko] = { gui, line }
	local function updateLabel(stand)
		local entry = labels[stand]
		if entry == nil then
			return
		end
		local part, top = StandAnchor.get(stand)
		entry.gui.Adornee = part
		if part ~= nil then
			entry.gui.StudsOffsetWorldSpace = Vector3.new(0, top + LABEL_HEIGHT, 0)
		end
		local view = State.view
		local count = (view and view.RebirthCount) or 0
		local nextLevel = Formulas.rebirthLevel(count + 1)
		entry.line.set({
			{ icon = "Rebirth", size = 40 },
			{ text = TEXT.Label, size = 34, colors = Theme.Gradients.Gold },
			{ text = Rebirth.title(nextLevel), size = 30, colors = titleColors(nextLevel) },
		})
		local windowOpen = window ~= nil and window.isOpen()
		entry.gui.Enabled = part ~= nil and not playing and not State.busy and not windowOpen
	end

	local function makeLabel(stand)
		local gui = Kit.new("BillboardGui", {
			Name = "RebirthLabel",
			LightInfluence = 0,
			AlwaysOnTop = true,
			MaxDistance = LABEL_DISTANCE,
			ResetOnSpawn = false,
			Enabled = false,
			Parent = playerGui,
		})
		local frame = Kit.worldFrame(gui, LABEL_DESIGN, LABEL_PIXELS_PER_STUD)
		local line = Kit.line(frame, { anchor = Vector2.new(0.5, 0.5), position = UDim2.fromScale(0.5, 0.5), height = 52 })
		labels[stand] = { gui = gui, line = line }
		updateLabel(stand)
	end

	------------------------------------------------------------- Duże E w portalu
	local promptGui = Kit.new("BillboardGui", {
		Name = "RebirthPrompt",
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
		Active = true,
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
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		promptButton.Text = ""
		Icons.make("Click", { Size = UDim2.fromScale(1, 1), ZIndex = 3, Parent = promptButton })
	end
	TweenService:Create(promptBob, TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = 1.07 }):Play()

	local function placePrompt(stand)
		local part = StandAnchor.get(stand)
		promptGui.Adornee = part
		promptGui.StudsOffsetWorldSpace = Vector3.new(0, 0.4, 0)
	end

	------------------------------------------------------------- Okno Rebirth
	-- Wysokość okna zależy od liczby nagród (2–4 rzędy), więc nie ma pustego miejsca na dole.
	local WINDOW_WIDTH = 700
	local WINDOW_TOP, WINDOW_BOTTOM = 44, 26
	local REWARDS_TOP = 94 -- ramka z nagrodami (piksele od góry treści)
	local REWARD_FIRST, REWARD_STEP, REWARD_ROWS = 31, 46, 4
	local BELOW_REWARDS = 162 -- „Resets”, „Keeps”, opłata i przycisk pod ramką z nagrodami
	local function windowHeight(rows)
		local box = 2 * REWARD_FIRST + (rows - 1) * REWARD_STEP
		return WINDOW_TOP + REWARDS_TOP + box + BELOW_REWARDS + WINDOW_BOTTOM
	end
	window = Kit.panel(hud.gui, {
		name = "RebirthWindow",
		size = Vector2.new(WINDOW_WIDTH, windowHeight(REWARD_ROWS)),
		title = TEXT.Title,
		icon = "Rebirth",
		padding = 30,
		top = WINDOW_TOP,
		bottom = WINDOW_BOTTOM,
	})
	hud.registerScale(window.holder)
	hud.addPopup(window)
	local content = window.content
	local function line(y, height, anchorX, x)
		local l = Kit.line(content, {
			anchor = Vector2.new(anchorX or 0.5, 0.5),
			position = UDim2.new(x or 0.5, 0, 0, y),
			height = height,
		})
		l.holder.ZIndex = 4
		return l
	end
	local titleLine = line(28, 56)
	local stepLine = line(72, 30)
	local rewardsBox = Kit.new("Frame", {
		Name = "Rewards",
		Position = UDim2.fromOffset(0, REWARDS_TOP),
		Size = UDim2.new(1, 0, 0, 2 * REWARD_FIRST + (REWARD_ROWS - 1) * REWARD_STEP),
		BackgroundColor3 = Color3.fromRGB(243, 238, 255),
		BorderSizePixel = 0,
		ZIndex = 3,
		Parent = content,
	})
	Kit.corner(rewardsBox, 18)
	Kit.stroke(rewardsBox, 2.5, Enum.ApplyStrokeMode.Border, Color3.fromRGB(205, 190, 240))
	local rewardLines = {}
	for i = 1, REWARD_ROWS do
		local l = Kit.line(rewardsBox, {
			anchor = Vector2.new(0, 0.5),
			position = UDim2.new(0, 24, 0, REWARD_FIRST + (i - 1) * REWARD_STEP),
			height = 42,
		})
		l.holder.ZIndex = 4
		rewardLines[i] = l
	end
	local resetsLine = line(0, 30, 0, 0)
	local keepsLine = line(0, 30, 0, 0)
	-- ramka z nagrodami, „Resets”, „Keeps” i wysokość okna według liczby nagród
	local function fitRows(rows)
		rows = math.clamp(rows, 1, REWARD_ROWS)
		local box = 2 * REWARD_FIRST + (rows - 1) * REWARD_STEP
		rewardsBox.Size = UDim2.new(1, 0, 0, box)
		resetsLine.holder.Position = UDim2.new(0, 0, 0, REWARDS_TOP + box + 26)
		keepsLine.holder.Position = UDim2.new(0, 0, 0, REWARDS_TOP + box + 58)
		window.holder.Size = UDim2.fromOffset(WINDOW_WIDTH, windowHeight(rows))
	end
	local priceLine = Kit.line(content, {
		anchor = Vector2.new(0, 1),
		position = UDim2.new(0, 0, 1, -12),
		height = 46,
	})
	priceLine.holder.ZIndex = 4
	local rebirthButton = Kit.button(content, {
		name = "DoRebirth",
		size = Vector2.new(250, 66),
		text = TEXT.Button,
		colors = Theme.Gradients.Green,
		anchor = Vector2.new(1, 1),
		position = UDim2.new(1, 0, 1, 0),
		textSize = 38,
	})

	local function renderWindow()
		local view = State.view
		if view == nil then
			return
		end
		local count = view.RebirthCount or 0
		local level = view.RebirthLevel or 0
		local nextCount = count + 1
		local nextLevel = Formulas.rebirthLevel(nextCount)
		local levelUp = nextLevel > level
		titleLine.set({
			{ text = Rebirth.title(level), size = 30, colors = titleColors(level) },
			{ text = "→", size = 30 },
			{ text = Rebirth.title(nextLevel), size = 40, colors = titleColors(nextLevel) },
		})
		if levelUp then
			stepLine.set({ { text = string.format(TEXT.Of, nextCount, Rebirth.Cap), size = 22, color = Theme.Muted, stroke = 0 } })
		else
			stepLine.set({ { text = string.format(TEXT.AfterCap, nextCount), size = 22, color = Theme.Muted, stroke = 0 } })
		end
		local items = {}
		if levelUp then
			table.insert(items, {
				{ icon = "Click", size = 36 },
				{ text = TEXT.LP, size = 26 },
				{ text = "×" .. multiplierText(level), size = 26 },
				{ text = "→", size = 26 },
				{ text = "×" .. multiplierText(nextLevel), size = 30, colors = Theme.Gradients.Gold },
			})
		end
		local auraItem = {
			{ icon = "Aura", size = 36 },
			{ text = "+" .. Format.number(math.floor((view.NextRebirthAura or 0) + 1e-9)), size = 30, colors = Theme.Gradients.Aura },
			{ text = TEXT.Aura, size = 26 },
		}
		if count + 1 == Economy.Aura.UnlockAtRebirth then
			table.insert(auraItem, { text = TEXT.AuraShop, size = 22 })
		end
		table.insert(items, auraItem)
		if levelUp then
			table.insert(items, {
				{ icon = "Speed", size = 34 },
				{ text = string.format(TEXT.Speed, Format.small(Economy.Rebirth.WalkSpeedPerLevel * 100)), size = 24 },
			})
			local slots = Rebirth.petSlotsAt(nextLevel) - Rebirth.petSlotsAt(level)
			if slots > 0 then
				table.insert(items, {
					{ icon = "Pets", size = 34 },
					{ text = string.format(TEXT.PetSlot, slots), size = 24, colors = Theme.Gradients.Gold },
				})
			end
		else
			table.insert(items, { { text = TEXT.MaxLevel, size = 22, color = Theme.Muted, stroke = 0 } })
		end
		for i, l in ipairs(rewardLines) do
			l.set(items[i] or {})
		end
		fitRows(#items)
		resetsLine.set({
			{ text = TEXT.Resets, size = 22, colors = Theme.Gradients.Red },
			{ text = TEXT.ResetsList, size = 20, color = Theme.Dark, stroke = 0 },
		})
		keepsLine.set({
			{ text = TEXT.Keeps, size = 22, colors = Theme.Gradients.Green },
			{ text = TEXT.KeepsList, size = 20, color = Theme.Dark, stroke = 0 },
		})
		local zones = #Economy.Zones
		if (view.ZonesUnlocked or 1) < zones then
			priceLine.set({
				{ icon = "Lock", size = 36 },
				{ text = string.format(TEXT.Locked, Economy.Zones[zones].Name), size = 24 },
			})
			rebirthButton.setColors(Theme.Gradients.Gray)
		else
			local fee = view.NextRebirthFee or Formulas.rebirthFee(nextCount)
			priceLine.set({
				{ icon = "Cash", size = 42 },
				{ text = Format.number(fee), size = 36, colors = Theme.Gradients.Gold },
			})
			if view.CanRebirth then
				rebirthButton.setColors(Theme.Gradients.Green)
			else
				rebirthButton.setColors(Theme.Gradients.Gray)
			end
		end
	end

	------------------------------------------------------------- Potwierdzenie
	local confirm = Kit.panel(hud.gui, {
		name = "RebirthConfirm",
		size = Vector2.new(640, 258),
		title = TEXT.ConfirmTitle,
		padding = 30,
		top = 44,
		bottom = 24,
	})
	confirm.holder.ZIndex = 5
	hud.registerScale(confirm.holder)
	local confirmLine = Kit.line(confirm.content, { anchor = Vector2.new(0.5, 0.5), position = UDim2.new(0.5, 0, 0, 28), height = 36 })
	local confirmLine2 = Kit.line(confirm.content, { anchor = Vector2.new(0.5, 0.5), position = UDim2.new(0.5, 0, 0, 66), height = 36 })
	confirmLine.set({ { text = TEXT.ConfirmText, size = 24 } })
	confirmLine2.set({ { text = TEXT.ConfirmText2, size = 24, colors = Theme.Gradients.Red } })
	local noButton = Kit.button(confirm.content, {
		name = "NotYet",
		size = Vector2.new(200, 56),
		text = TEXT.ConfirmNo,
		colors = Theme.Gradients.Gray,
		anchor = Vector2.new(0.5, 1),
		position = UDim2.new(0.5, -115, 1, 0),
		textSize = 26,
	})
	local yesButton = Kit.button(confirm.content, {
		name = "Confirm",
		size = Vector2.new(200, 56),
		text = TEXT.ConfirmYes,
		colors = Theme.Gradients.Green,
		anchor = Vector2.new(0.5, 1),
		position = UDim2.new(0.5, 115, 1, 0),
		textSize = 26,
	})
	window.holder:GetPropertyChangedSignal("Visible"):Connect(function()
		if not window.holder.Visible then
			confirm.hide()
		end
		-- napis nad portalem wchodził na tytuł okna, więc przy otwartym oknie go nie ma
		for stand in pairs(labels) do
			updateLabel(stand)
		end
	end)

	local function openWindow()
		if current == nil or playing or State.busy then
			return
		end
		renderWindow()
		promptGui.Enabled = false
		window.open()
	end

	------------------------------------------------------------- Animacja po Rebirthie
	local animGui = Kit.new("ScreenGui", {
		Name = "LarpRebirth",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 17,
		Enabled = false,
		Parent = playerGui,
	})
	local dim = Kit.new("Frame", {
		Name = "Dim",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(20, 10, 40),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = animGui,
	})
	local stage = Kit.new("Frame", {
		Name = "Stage",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(1200, 700),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = animGui,
	})
	hud.registerScale(stage)
	local rays = Kit.new("Frame", {
		Name = "Rays",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, 250),
		Size = UDim2.fromOffset(900, 900),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = stage,
	})
	local raysScale = Kit.new("UIScale", { Scale = 0, Parent = rays })
	local rayFade = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.3, 0.75),
		NumberSequenceKeypoint.new(0.5, 0.45),
		NumberSequenceKeypoint.new(0.7, 0.75),
		NumberSequenceKeypoint.new(1, 1),
	})
	local bars = {}
	for i = 1, RAYS do
		local color = Color3.fromRGB(255, 200, 60)
		if i % 2 == 0 then
			color = Color3.fromRGB(176, 70, 255)
		end
		local bar = Kit.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(0, 120, 1, 0),
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			Rotation = (i - 1) * 180 / RAYS,
			ZIndex = 2,
			Parent = rays,
		})
		Kit.new("UIGradient", { Rotation = 90, Transparency = rayFade, Parent = bar })
		bars[i] = bar
	end
	local function stageLine(y, height)
		local l = Kit.line(stage, { anchor = Vector2.new(0.5, 0.5), position = UDim2.new(0.5, 0, 0, y), height = height })
		l.holder.ZIndex = 5
		l.scale = Kit.new("UIScale", { Scale = 0, Parent = l.holder })
		return l
	end
	local bigLine = stageLine(170, 110)
	local levelLine = stageLine(270, 64)
	local multiplierLine = stageLine(350, 56)
	local auraLine = stageLine(418, 56)
	local extraLine = stageLine(482, 44)
	local blackout = Kit.new("Frame", {
		Name = "Blackout",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 20,
		Parent = animGui,
	})
	local flash = Kit.new("Frame", {
		Name = "Flash",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 19,
		Parent = animGui,
	})

	local spin = nil
	local function popIn(l, delay)
		l.scale.Scale = 0
		task.delay(delay, function()
			TweenService:Create(l.scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end)
	end

	local function run(payload)
		local level = payload.Level or 0
		local teleport = payload.Teleport or 2.6
		bigLine.set({ { text = TEXT.Big, size = 96, colors = Theme.Gradients.Gold } })
		levelLine.set({
			{ text = string.format(TEXT.Level, payload.Count or level), size = 40 },
			{ text = payload.Title or Rebirth.title(level), size = 48, colors = titleColors(level) },
		})
		if payload.LevelUp then
			multiplierLine.set({ { icon = "Click", size = 44 }, { text = string.format(TEXT.Multiplier, multiplierText(level)), size = 40, colors = Theme.Gradients.Gold } })
		else
			multiplierLine.set({})
		end
		auraLine.set({ { icon = "Aura", size = 46 }, { text = string.format(TEXT.AuraGained, Format.number(math.floor((payload.Aura or 0) + 1e-9))), size = 42, colors = Theme.Gradients.Aura } })
		if payload.FirstAura then
			extraLine.set({ { text = TEXT.ShopOpen, size = 30 } })
		elseif (payload.PetSlots or 0) > 0 then
			extraLine.set({ { icon = "Pets", size = 36 }, { text = string.format(TEXT.Slots, payload.PetSlots), size = 30, colors = Theme.Gradients.Gold } })
		else
			extraLine.set({})
		end
		dim.BackgroundTransparency = 1
		blackout.BackgroundTransparency = 1
		raysScale.Scale = 0
		animGui.Enabled = true
		hud.setVisible(false)
		flash.BackgroundTransparency = 0
		TweenService:Create(flash, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 }):Play()
		TweenService:Create(dim, TweenInfo.new(0.35), { BackgroundTransparency = 0.25 }):Play()
		TweenService:Create(raysScale, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		spin = RunService.RenderStepped:Connect(function(dt)
			for _, bar in ipairs(bars) do
				bar.Rotation = bar.Rotation + dt * 24
			end
		end)
		Sounds.play("Rebirth")
		popIn(bigLine, 0.05)
		popIn(levelLine, 0.35)
		popIn(multiplierLine, 0.6)
		popIn(auraLine, 0.85)
		popIn(extraLine, 1.1)
		-- ekran ciemnieje przed teleportem na spawn i jaśnieje, gdy gracz już tam jest (z zapasem
		-- na opóźnienie sieci: teleport robi serwer, a pozycja postaci dochodzi chwilę później)
		task.wait(math.max(0.8, teleport - 0.6))
		TweenService:Create(blackout, TweenInfo.new(0.45), { BackgroundTransparency = 0 }):Play()
		task.wait(0.45 + 0.85)
		for _, l in ipairs({ bigLine, levelLine, multiplierLine, auraLine, extraLine }) do
			l.scale.Scale = 0
		end
		raysScale.Scale = 0
		dim.BackgroundTransparency = 1
		hud.setVisible(true)
		TweenService:Create(blackout, TweenInfo.new(0.5), { BackgroundTransparency = 1 }):Play()
		task.wait(0.55)
	end

	local function play(payload)
		if playing then
			return
		end
		playing = true
		State.busy = true
		window.hide()
		promptGui.Enabled = false
		for stand in pairs(labels) do
			updateLabel(stand)
		end
		local ok, err = pcall(run, payload)
		if not ok then
			warn("[Rebirth] animacja: " .. tostring(err))
		end
		if spin ~= nil then
			spin:Disconnect()
			spin = nil
		end
		animGui.Enabled = false
		blackout.BackgroundTransparency = 1
		hud.setVisible(true)
		State.busy = false
		playing = false
		for stand in pairs(labels) do
			updateLabel(stand)
		end
	end

	------------------------------------------------------------- Rebirth
	local requesting = false
	local function doRebirth()
		if requesting or playing then
			return
		end
		requesting = true
		local ok, result = pcall(function()
			return Net.func("Rebirth"):InvokeServer()
		end)
		requesting = false
		if not ok or type(result) ~= "table" then
			return
		end
		if not result.Ok then
			if result.Reason == "NotEnough" then
				hud.notEnough(rebirthButton)
			elseif result.Reason == "TooFar" then
				Sounds.play("NotEnough")
				hud.toast({ { text = TEXT.TooFar, size = 26 } }, "RebirthFar")
			else
				Sounds.play("NotEnough")
			end
		end
		-- animację włącza Notify „Rebirthed” (ten sam dla komendy /rb)
	end

	rebirthButton.Activated:Connect(function()
		local view = State.view
		if view == nil then
			return
		end
		if (view.ZonesUnlocked or 1) < #Economy.Zones then
			Sounds.play("NotEnough")
			hud.toast({ { icon = "Lock", size = 40 }, { text = string.format(TEXT.Locked, Economy.Zones[#Economy.Zones].Name), size = 26 } }, "RebirthLocked")
			return
		end
		if not view.CanRebirth then
			hud.notEnough(rebirthButton)
			return
		end
		confirm.open()
	end)
	noButton.Activated:Connect(function()
		confirm.hide()
	end)
	yesButton.Activated:Connect(function()
		confirm.hide()
		doRebirth()
	end)

	promptButton.Activated:Connect(function()
		Sounds.play("Button")
		openWindow()
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or input.KeyCode ~= Enum.KeyCode.E or playing then
			return
		end
		if window.isOpen() then
			window.hide()
		elseif promptGui.Enabled then
			Sounds.play("Button")
			openWindow()
		end
	end)

	State.onNotify(function(payload)
		if payload.Kind == "Rebirthed" then
			play(payload)
		end
	end)

	------------------------------------------------------------- Stoiska i najbliższy portal
	local function onStandAdded(stand)
		for _, existing in ipairs(stands) do
			if existing == stand then
				return
			end
		end
		table.insert(stands, stand)
		makeLabel(stand)
		stand.DescendantAdded:Connect(function(d)
			if d:IsA("BasePart") then
				updateLabel(stand)
			end
		end)
	end
	local function onStandRemoved(stand)
		for i = #stands, 1, -1 do
			if stands[i] == stand then
				table.remove(stands, i)
			end
		end
		if labels[stand] ~= nil then
			labels[stand].gui:Destroy()
			labels[stand] = nil
		end
		StandAnchor.forget(stand)
		if current == stand then
			current = nil
		end
	end

	local timer = 0
	RunService.Heartbeat:Connect(function(dt)
		timer = timer + dt
		if timer < 0.1 then
			return
		end
		timer = 0
		if playing then
			promptGui.Enabled = false
			return
		end
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root == nil or State.view == nil or State.busy or hud.windowOpen() then
			current = nil
		else
			local position = root.Position
			if current ~= nil and (current.Parent == nil or distanceToStand(current, position) > HIDE_DISTANCE) then
				current = nil
			end
			if current == nil then
				local best, bestDistance = nil, math.huge
				for _, stand in ipairs(stands) do
					if stand.Parent ~= nil then
						local d = distanceToStand(stand, position)
						if d < bestDistance then
							best, bestDistance = stand, d
						end
					end
				end
				if best ~= nil and bestDistance <= SHOW_DISTANCE then
					current = best
					placePrompt(best)
				end
			end
		end
		if current == nil and window.isOpen() then
			window.hide()
		end
		promptGui.Enabled = current ~= nil and not window.isOpen()
	end)

	local lastKey = nil
	State.onChange(function(view)
		local key = tostring(view.RebirthCount) .. ":" .. tostring(State.busy)
		if key ~= lastKey then
			lastKey = key
			for stand in pairs(labels) do
				updateLabel(stand)
			end
		end
		if window.isOpen() then
			renderWindow()
		end
	end)

	for _, stand in ipairs(CollectionService:GetTagged(STAND_TAG)) do
		onStandAdded(stand)
	end
	CollectionService:GetInstanceAddedSignal(STAND_TAG):Connect(onStandAdded)
	CollectionService:GetInstanceRemovedSignal(STAND_TAG):Connect(onStandRemoved)
end

return RebirthUi
