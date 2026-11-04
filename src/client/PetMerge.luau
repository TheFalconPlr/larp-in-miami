-- Łączenie petów: okno przed losowaniem i animacja wyniku. Z dokumentu projektu: „Przed losowaniem
-- okno pokazuje szansę i pety, które można stracić. Wynik pokazuje krótka animacja.”
-- Okno otwiera tryb MERGE w oknie PETS (Pets.luau). Wynik losuje serwer (PetService → Loop.mergePets):
-- sukces daje wersję Golden (z Golden: Diamond), porażka zabiera wszystkie wrzucone pety, a opłata
-- przepada zawsze. W czasie animacji HUD jest schowany, a State.busy blokuje klikanie.
-- Ten moduł nie wymaga Pets.luau (Pets wymaga jego), więc to, czego potrzebuje z Pets, dostaje
-- w PetMerge.create(hud, helpers).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared.Format)
local Formulas = require(Shared.Formulas)
local Net = require(Shared.Net)
local PetsConfig = require(Shared.Config.Pets)
local State = require(script.Parent.State)
local Theme = require(script.Parent.Ui.Theme)
local Kit = require(script.Parent.Ui.Kit)
local Icons = require(script.Parent.Ui.Icons)
local Sounds = require(script.Parent.Ui.Sounds)
local PetModels = require(script.Parent.PetModels)

local PetMerge = {}

local TEXT = {
	Title = "Merge Pets",
	Put = "You put in",
	Get = "You get",
	Chance = "chance",
	Fee = "Fee",
	Safe = "100% chance, it can't fail!",
	Risk = "If it fails, you lose all %d pets!",
	RiskOne = "If it fails, you lose this pet!",
	Cancel = "CANCEL",
	Merge = "MERGE!",
	Success = "SUCCESS!",
	Failed = "MERGE FAILED",
	Lost = "You lost %d pets",
	LostOne = "You lost 1 pet",
	Equipped = "Equipped!",
	Gone = "Those pets are gone, pick them again",
	Premium = "Premium pets merge only at 100%",
	Error = "Merge didn't work, try again",
}

local CARD_SIZE = Vector2.new(660, 440)
local STAGE_SIZE = Vector2.new(1200, 700)
local SPIN_TIME = 1.7 -- pety krążą i zlatują się do środka (s)
local RESULT_TIME = 2.4 -- tyle widać wynik (s)
local SPIN_RADIUS = 250
local GRAVITY = 1100
local RAY_FADE = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(0.32, 0.8),
	NumberSequenceKeypoint.new(0.5, 0.5),
	NumberSequenceKeypoint.new(0.68, 0.8),
	NumberSequenceKeypoint.new(1, 1),
})
local FAIL_COLOR = Color3.fromRGB(150, 146, 165)

-- Kolor szansy: 100% zielony, od 50% złoty, mniej czerwony.
function PetMerge.chanceColors(chance)
	if chance >= 1 - 1e-9 then
		return Theme.Gradients.Green
	elseif chance >= 0.5 then
		return Theme.Gradients.Gold
	end
	return Theme.Gradients.Red
end

local function levelColors(level)
	return PetsConfig.LevelColors[level] or Theme.Gradients.Gold
end

local function viewport(parent, props)
	props.BackgroundTransparency = 1
	props.Ambient = Color3.fromRGB(205, 205, 215)
	props.LightColor = Color3.new(1, 1, 1)
	props.Parent = parent
	return Kit.new("ViewportFrame", props)
end

-- helpers: rarityItem(rarity, size), powerText(pet), tileCenter(), bump() z Pets.luau.
-- Zwraca { open(pets, info, onDone), isOpen() }. onDone(result) po animacji (result = odpowiedź
-- serwera) albo onDone(nil) po CANCEL.
function PetMerge.create(hud, helpers)
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	-- pod warstwą komunikatów HUD (DisplayOrder 7), żeby „Not enough L$” było widać nad oknem
	local gui = Kit.new("ScreenGui", {
		Name = "LarpMerge",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 6,
		Enabled = false,
		Parent = playerGui,
	})
	local dim = Kit.new("Frame", {
		Name = "Dim",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Active = true,
		Parent = gui,
	})

	------------------------------------------------------------- Okno przed losowaniem
	local card = Kit.panel(gui, {
		name = "MergeCard",
		size = CARD_SIZE,
		title = TEXT.Title,
		icon = "Pets",
		padding = 30,
		top = 40,
		bottom = 24,
	})
	card.holder.ZIndex = 2
	hud.registerScale(card.holder)
	local content = card.content -- 600 × 376

	local function label(text, x, width)
		return Kit.text(content, {
			Position = UDim2.fromOffset(x, 0),
			Size = UDim2.fromOffset(width, 24),
			Text = text,
			ZIndex = 4,
		}, { maxSize = 20, stroke = 2.5 })
	end
	label(TEXT.Put, 0, 380)
	label(TEXT.Get, 452, 148)

	local piecesBox = Kit.new("Frame", {
		Name = "Pieces",
		Position = UDim2.fromOffset(0, 28),
		Size = UDim2.fromOffset(380, 100),
		BackgroundColor3 = Theme.White,
		BorderSizePixel = 0,
		ZIndex = 4,
		Parent = content,
	})
	Kit.corner(piecesBox, 20)
	Kit.stroke(piecesBox, 3, Enum.ApplyStrokeMode.Border)
	Kit.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = piecesBox,
	})
	-- strzałka: ikona ulepszeń obrócona w prawo
	Icons.make("Upgrades", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(416, 78),
		Size = UDim2.fromOffset(52, 52),
		Rotation = 90,
		ZIndex = 5,
		Parent = content,
	})
	local resultTile = Kit.new("Frame", {
		Name = "Result",
		Position = UDim2.fromOffset(452, 28),
		Size = UDim2.fromOffset(148, 100),
		BackgroundColor3 = Theme.White,
		BorderSizePixel = 0,
		ZIndex = 4,
		Parent = content,
	})
	Kit.corner(resultTile, 20)
	Kit.stroke(resultTile, 4, Enum.ApplyStrokeMode.Border)
	local resultGradient = Kit.gradient(resultTile, levelColors(1), 90)
	local resultView = viewport(resultTile, {
		Position = UDim2.fromOffset(4, 2),
		Size = UDim2.new(1, -8, 1, -4),
		ZIndex = 5,
	})
	local resultModel = nil

	local function centered(y, height)
		return Kit.line(content, {
			anchor = Vector2.new(0.5, 0.5),
			position = UDim2.new(0.5, 0, 0, y),
			height = height,
		})
	end
	local nameLine = centered(150, 34)
	local chanceLine = centered(200, 64)
	local feeLine = centered(252, 40)
	local riskLine = centered(290, 32)

	local cancelButton = Kit.button(content, {
		name = "Cancel",
		size = Vector2.new(200, 52),
		text = TEXT.Cancel,
		colors = Theme.Gradients.Gray,
		anchor = Vector2.new(0.5, 1),
		position = UDim2.new(0.5, -120, 1, 0),
		textSize = 24,
	})
	local goButton = Kit.button(content, {
		name = "Go",
		size = Vector2.new(220, 52),
		text = TEXT.Merge,
		colors = Theme.Gradients.Pink,
		anchor = Vector2.new(0.5, 1),
		position = UDim2.new(0.5, 120, 1, 0),
		textSize = 26,
		sound = false,
	})

	------------------------------------------------------------- Scena animacji
	local stage = Kit.new("Frame", {
		Name = "Stage",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(STAGE_SIZE.X, STAGE_SIZE.Y),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 3,
		Parent = gui,
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
		Parent = gui,
	})
	local function stageLine(y, height)
		local l = Kit.line(stage, {
			anchor = Vector2.new(0.5, 0.5),
			position = UDim2.new(0.5, 0, 0, y),
			height = height,
		})
		l.holder.ZIndex = 8
		l.scale = Kit.new("UIScale", { Scale = 0, Parent = l.holder })
		return l
	end
	local banner = stageLine(96, 64)
	local resultName = stageLine(560, 52)
	local resultInfo = stageLine(606, 40)
	local resultExtra = stageLine(644, 32)

	-- wynik na środku: promienie, poświata i pet (jak przy jajku)
	local RESULT_SIZE = 400
	local center = Kit.new("Frame", {
		Name = "Center",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, -10),
		Size = UDim2.fromOffset(RESULT_SIZE, RESULT_SIZE),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 2,
		Parent = stage,
	})
	local centerScale = Kit.new("UIScale", { Parent = center })
	local rays = Kit.new("Frame", {
		Name = "Rays",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(RESULT_SIZE * 1.6, RESULT_SIZE * 1.6),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = center,
	})
	local bars = {}
	for i = 1, 8 do
		local bar = Kit.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(0, math.floor(RESULT_SIZE * 0.15), 1, 0),
			BorderSizePixel = 0,
			Rotation = (i - 1) * 22.5,
			ZIndex = 2,
			Parent = rays,
		})
		Kit.new("UIGradient", { Rotation = 90, Transparency = RAY_FADE, Parent = bar })
		bars[i] = bar
	end
	local glow = Kit.new("Frame", {
		Name = "Glow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(RESULT_SIZE * 0.84, RESULT_SIZE * 0.84),
		BackgroundTransparency = 0.5,
		BorderSizePixel = 0,
		ZIndex = 3,
		Parent = center,
	})
	Kit.new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = glow })
	local glowStroke = Kit.stroke(glow, 8, Enum.ApplyStrokeMode.Border)
	glowStroke.Transparency = 0.3
	local centerView = viewport(center, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		ZIndex = 4,
	})
	local centerPop = Kit.new("UIScale", { Parent = centerView })

	------------------------------------------------------------- Odpryski i iskry
	local particles = {}
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
			Kit.new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = frame })
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
					p.frame.Rotation = p.frame.Rotation + p.spin * dt
					local fade = math.clamp((k - 0.55) / 0.45, 0, 1)
					p.frame.BackgroundTransparency = fade
					p.stroke.Transparency = fade
				else
					local s = math.sin(k * math.pi)
					p.frame.Size = UDim2.fromOffset(p.size * s, p.size * s)
				end
				p.position = p.position + p.velocity * dt
				p.frame.Position = UDim2.fromOffset(p.position.X, p.position.Y)
			end
		end
	end

	------------------------------------------------------------- Stan
	local opened = nil -- { pets, info, onDone } otwartego okna
	local requesting = false
	local playing = false
	local spinners = {}
	local connection = nil
	local shakeUntil = 0

	local function clearPieces()
		for _, child in ipairs(piecesBox:GetChildren()) do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
	end

	local function fill(pets, info)
		clearPieces()
		for i, pet in ipairs(pets) do
			local cell = Kit.new("Frame", {
				Name = "Piece" .. i,
				LayoutOrder = i,
				Size = UDim2.fromOffset(66, 84),
				BackgroundColor3 = (PetsConfig.RarityColors[pet.Rarity] or Theme.White):Lerp(Theme.White, 0.6),
				BorderSizePixel = 0,
				ZIndex = 5,
				Parent = piecesBox,
			})
			Kit.corner(cell, 14)
			Kit.stroke(cell, 2.5, Enum.ApplyStrokeMode.Border)
			local view = viewport(cell, { Size = UDim2.fromScale(1, 1), ZIndex = 6 })
			PetModels.show(view, PetModels.pet(pet.Zone, pet.Rarity, pet.Level), 1.6)
		end
		resultGradient.Color = ColorSequence.new(levelColors(info.Level)[1], levelColors(info.Level)[2])
		resultModel = PetModels.pet(info.Zone, info.Rarity, info.Level)
		PetModels.show(resultView, resultModel, 1.6)
		local preview = { Zone = info.Zone, Rarity = info.Rarity, Level = info.Level }
		nameLine.set({
			{ text = PetsConfig.fullName(info.Zone, info.Rarity, info.Level), size = 28, colors = levelColors(info.Level) },
			{ text = helpers.powerText(preview), size = 24, colors = Theme.Gradients.Gold },
		})
		chanceLine.set({
			{ text = Format.percent(info.Chance), size = 58, colors = PetMerge.chanceColors(info.Chance) },
			{ text = TEXT.Chance, size = 28 },
		})
		local cash = (State.view and State.view.Cash) or 0
		local feeColors = Theme.Gradients.Gold
		if cash < info.Fee then
			feeColors = Theme.Gradients.Red
		end
		feeLine.set({
			{ text = TEXT.Fee, size = 24 },
			{ icon = "Cash", size = 34 },
			{ text = Format.number(info.Fee), size = 28, colors = feeColors },
		})
		if info.Chance >= 1 - 1e-9 then
			riskLine.set({ { text = TEXT.Safe, size = 22, colors = Theme.Gradients.Green } })
		elseif #pets == 1 then
			riskLine.set({ { text = TEXT.RiskOne, size = 22, colors = Theme.Gradients.Red } })
		else
			riskLine.set({ { text = string.format(TEXT.Risk, #pets), size = 22, colors = Theme.Gradients.Red } })
		end
	end

	local function closeCard(result)
		local done = opened and opened.onDone
		opened = nil
		card.hide()
		if not playing then
			gui.Enabled = false
			dim.BackgroundTransparency = 1
		end
		if done ~= nil then
			done(result)
		end
	end

	------------------------------------------------------------- Animacja
	local function animate(dt)
		local now = os.clock()
		for _, s in ipairs(spinners) do
			local e = now - s.start
			local k = math.clamp(e / SPIN_TIME, 0, 1)
			s.angle = s.angle + (2 + 11 * k) * dt
			local radius = SPIN_RADIUS * (1 - k ^ 1.7)
			local x = STAGE_SIZE.X / 2 + math.cos(s.angle) * radius
			local y = STAGE_SIZE.Y / 2 - 10 + math.sin(s.angle) * radius * 0.5
			s.view.Position = UDim2.fromOffset(x, y)
			s.scale.Scale = math.max(0.2, 1 - k * 0.55)
			s.model:PivotTo(CFrame.Angles(0, e * 7, 0))
		end
		if center.Visible then
			local e = now - center:GetAttribute("Start")
			for i, bar in ipairs(bars) do
				bar.Rotation = (i - 1) * 22.5 + e * 28
			end
			if resultModel ~= nil and resultModel.Parent == centerView then
				local yaw
				if e < 0.6 then
					yaw = -2 * math.pi * (1 - e / 0.6) ^ 3
				else
					yaw = math.sin((e - 0.6) * 1.6) * 0.3
				end
				resultModel:PivotTo(CFrame.new(0, math.sin(e * 3) * 0.12, 0) * CFrame.Angles(0, yaw, 0))
			end
		end
		updateParticles(dt)
		if now < shakeUntil then
			stage.Position = UDim2.new(0.5, math.random(-7, 7), 0.5, math.random(-7, 7))
		else
			stage.Position = UDim2.fromScale(0.5, 0.5)
		end
	end

	local function popIn(l, delay)
		l.scale.Scale = 0
		task.delay(delay, function()
			TweenService:Create(l.scale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end)
	end

	local function clearStage()
		for _, s in ipairs(spinners) do
			s.view:Destroy()
		end
		spinners = {}
		for _, p in ipairs(particles) do
			p.frame:Destroy()
		end
		particles = {}
		for _, l in ipairs({ banner, resultName, resultInfo, resultExtra }) do
			l.set({})
			l.scale.Scale = 0
		end
		center.Visible = false
		centerView.Visible = true
		centerView.Parent = center
		centerView.AnchorPoint = Vector2.new(0.5, 0.5)
		centerView.Position = UDim2.fromScale(0.5, 0.5)
		centerView.Size = UDim2.fromScale(1, 1)
		centerView.ZIndex = 4
		centerScale.Scale = 1
		shakeUntil = 0
	end

	local function sleep(seconds)
		if seconds > 0 then
			task.wait(seconds)
		end
	end

	local function runAnimation(pets, result)
		clearStage()
		stage.Visible = true
		TweenService:Create(dim, TweenInfo.new(0.25), { BackgroundTransparency = 0.3 }):Play()
		local start = os.clock()
		for i, pet in ipairs(pets) do
			local view = viewport(stage, {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(STAGE_SIZE.X / 2, STAGE_SIZE.Y / 2),
				Size = UDim2.fromOffset(170, 170),
				ZIndex = 4,
			})
			local model = PetModels.pet(pet.Zone, pet.Rarity, pet.Level)
			PetModels.show(view, model, 1.9)
			local scale = Kit.new("UIScale", { Scale = 0, Parent = view })
			TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
			table.insert(spinners, {
				view = view,
				model = model,
				scale = scale,
				angle = (i - 1) / #pets * math.pi * 2,
				start = start,
			})
		end
		connection = RunService.RenderStepped:Connect(animate)
		Sounds.play("ClipPosted")
		for k = 1, 3 do
			task.delay(SPIN_TIME * (0.25 + 0.22 * k), function()
				Sounds.play("Crack", { pitch = 1 + 0.12 * (k - 1), volume = 0.7 })
			end)
		end
		sleep(start + SPIN_TIME - os.clock())

		-- zlot do środka: błysk, pety znikają
		for _, s in ipairs(spinners) do
			s.view:Destroy()
		end
		spinners = {}
		flash.BackgroundTransparency = 0
		TweenService:Create(flash, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 }):Play()
		Sounds.play("Crack", { pitch = 0.82, volume = 1.2 })
		local middle = Vector2.new(STAGE_SIZE.X / 2, STAGE_SIZE.Y / 2 - 10)
		local now = os.clock()
		if result.Success then
			local pet = result.Pet or { Zone = result.Zone, Rarity = result.Rarity, Level = result.Level }
			local colors = levelColors(pet.Level)
			for _, bar in ipairs(bars) do
				bar.BackgroundColor3 = colors[2]
			end
			glow.BackgroundColor3 = colors[2]
			glowStroke.Color = colors[1]
			resultModel = PetModels.pet(pet.Zone, pet.Rarity, pet.Level)
			PetModels.show(centerView, resultModel, 2.1)
			center:SetAttribute("Start", now)
			center.Visible = true
			centerPop.Scale = 0.15
			TweenService:Create(centerPop, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
			Sounds.play("Hatch")
			task.delay(0.2, function()
				Sounds.play("Reward")
			end)
			shakeUntil = now + 0.35
			for n = 1, 26 do
				local angle = math.rad(n * (360 / 26) + math.random(-8, 8))
				local dir = Vector2.new(math.cos(angle), math.sin(angle))
				local color = colors[1]
				if n % 2 == 0 then
					color = Theme.White
				end
				spawnParticle("spark", middle + dir * 60, dir * math.random(260, 480), color, math.random(14, 24), 0.9)
			end
			banner.set({ { text = TEXT.Success, size = 54, colors = Theme.Gradients.Green } })
			popIn(banner, 0)
			resultName.set({ { text = PetsConfig.fullName(pet.Zone, pet.Rarity, pet.Level), size = 44, colors = colors } })
			popIn(resultName, 0.1)
			resultInfo.set({
				helpers.rarityItem(pet.Rarity, 28),
				{ text = helpers.powerText(pet), size = 28, colors = Theme.Gradients.Gold },
			})
			popIn(resultInfo, 0.22)
			if pet.Equipped then
				resultExtra.set({ { text = TEXT.Equipped, size = 24, colors = Theme.Gradients.Green } })
				popIn(resultExtra, 0.34)
			end
		else
			-- porażka: szare odłamki, drżenie i smutna trąbka
			shakeUntil = now + 0.5
			for n = 1, 30 do
				local angle = math.rad(n * 12 + math.random(-10, 10))
				local dir = Vector2.new(math.cos(angle), math.sin(angle))
				spawnParticle("chip", middle + dir * 30, dir * math.random(300, 560), FAIL_COLOR, math.random(10, 20), 1.1)
			end
			Sounds.play("MergeFail")
			banner.set({ { text = TEXT.Failed, size = 54, colors = Theme.Gradients.Red } })
			popIn(banner, 0)
			local lost = string.format(TEXT.Lost, #pets)
			if #pets == 1 then
				lost = TEXT.LostOne
			end
			resultName.set({ { text = lost, size = 36 } })
			popIn(resultName, 0.15)
		end
		sleep(now + RESULT_TIME - os.clock())

		-- koniec: pet leci do kafelka PETS, napisy i tło znikają
		local target = helpers.tileCenter()
		for _, l in ipairs({ banner, resultName, resultInfo, resultExtra }) do
			TweenService:Create(l.scale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Scale = 0 }):Play()
		end
		hud.setVisible(true)
		TweenService:Create(dim, TweenInfo.new(0.35), { BackgroundTransparency = 1 }):Play()
		if result.Success and target ~= nil then
			local position, size = centerView.AbsolutePosition, centerView.AbsoluteSize
			local inset = GuiService:GetGuiInset()
			centerView.Parent = gui
			centerView.AnchorPoint = Vector2.new(0.5, 0.5)
			centerView.Position = UDim2.fromOffset(position.X + size.X / 2, position.Y + size.Y / 2)
			centerView.Size = UDim2.fromOffset(size.X, size.Y)
			centerView.ZIndex = 12
			local goal = target + inset
			TweenService:Create(centerView, TweenInfo.new(0.42, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Position = UDim2.fromOffset(goal.X, goal.Y),
				Size = UDim2.fromOffset(40, 40),
			}):Play()
			task.delay(0.42, function()
				centerView.Visible = false
				helpers.bump()
			end)
		end
		TweenService:Create(centerScale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Scale = 0 }):Play()
		sleep(0.5)
	end

	local function play(pets, result)
		playing = true
		State.busy = true
		gui.Enabled = true
		hud.setVisible(false)
		local ok, err = pcall(runAnimation, pets, result)
		if not ok then
			warn("[Łączenie] animacja: " .. tostring(err))
		end
		if connection ~= nil then
			connection:Disconnect()
			connection = nil
		end
		clearStage()
		stage.Visible = false
		gui.Enabled = false
		dim.BackgroundTransparency = 1
		hud.setVisible(true)
		State.busy = false
		playing = false
	end

	------------------------------------------------------------- Przyciski
	cancelButton.Activated:Connect(function()
		if requesting then
			return
		end
		closeCard(nil)
	end)
	card.close.Activated:Connect(function()
		if requesting then
			return
		end
		closeCard(nil)
	end)

	goButton.Activated:Connect(function()
		if requesting or playing or opened == nil then
			return
		end
		local info = opened.info
		local cash = (State.view and State.view.Cash) or 0
		if cash < info.Fee then
			hud.notEnough(goButton)
			return
		end
		Sounds.play("Button")
		local pets = opened.pets
		local ids = {}
		for _, pet in ipairs(pets) do
			table.insert(ids, pet.Id)
		end
		requesting = true
		local ok, result = pcall(function()
			return Net.func("MergePets"):InvokeServer(ids)
		end)
		requesting = false
		if not ok or type(result) ~= "table" then
			Sounds.play("NotEnough")
			hud.toast({ { text = TEXT.Error, size = 26, colors = Theme.Gradients.Red } }, "MergeError")
			return
		end
		if not result.Ok then
			if result.Reason == "NotEnough" then
				hud.notEnough(goButton)
			else
				Sounds.play("NotEnough")
				local text = TEXT.Error
				if result.Reason == "Missing" or result.Reason == "NotSame" then
					text = TEXT.Gone
				elseif result.Reason == "Premium" then
					text = TEXT.Premium
				end
				hud.toast({ { text = text, size = 26, colors = Theme.Gradients.Red } }, "MergeError")
				closeCard(nil)
			end
			return
		end
		-- wynik jest już na serwerze: okno znika, a animacja pokazuje, co wypadło
		local done = opened.onDone
		opened = nil
		playing = true
		card.hide()
		play(pets, result)
		if done ~= nil then
			done(result)
		end
	end)

	------------------------------------------------------------- Dla Pets.luau
	local api = {}

	-- pets: lista petów { Id, Zone, Rarity, Level, Egg }, info: wynik Loop.mergeInfo.
	function api.open(pets, info, onDone)
		if playing or requesting then
			return
		end
		opened = { pets = pets, info = info, onDone = onDone }
		fill(pets, info)
		gui.Enabled = true
		dim.BackgroundTransparency = 0.45
		card.open()
	end

	function api.isOpen()
		return opened ~= nil or playing
	end

	-- Szansa za jednego peta (z Merge Luck), np. 0.2.
	function api.chancePerPiece()
		local luck = (State.view and State.view.MergeLuck) or 0
		return Formulas.mergeChancePerPiece(luck)
	end

	-- pet w podglądzie wyniku lekko się kołysze
	RunService.RenderStepped:Connect(function()
		if opened ~= nil and resultModel ~= nil and resultModel.Parent == resultView then
			resultModel:PivotTo(CFrame.Angles(0, math.sin(os.clock() * 1.4) * 0.45, 0))
		end
	end)

	-- okno (Kit.panel) chowa się samo krzyżykiem; pilnujemy tylko, żeby tło też zniknęło
	card.holder:GetPropertyChangedSignal("Visible"):Connect(function()
		if not card.holder.Visible and not playing and opened == nil then
			gui.Enabled = false
		end
	end)

	return api
end

return PetMerge
