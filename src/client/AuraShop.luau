-- Sklep Aury po stronie gracza (Etap 9): stoisko przy spawnie obok Sell, otwarte od Rebirth 1.
--   • nad stoiskiem napis „AURA SHOP” (przed pierwszym Rebirthem kłódka i „Rebirth to unlock”),
--     a blisko duże E (klawisz albo kliknięcie),
--   • okno: 4 karty (Click Boost, Luck, Aura Gain, Merge Luck) z poziomem, efektem teraz → po
--     zakupie, kosztem w Aurze i przyciskami BUY 1 / BUY MAX; na dole Aura Level i poświata.
-- Zakupy robi serwer (RebirthService, Logic/Rebirth); tu jest tylko wygląd.

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

local AuraShop = {}

local STAND_TAG = "LarpAuraShop" -- jak RebirthService.ShopTag na serwerze
local SHOW_DISTANCE = 8
local HIDE_DISTANCE = 12
local LABEL_HEIGHT = 1.2

local WINDOW = Vector2.new(820, 560)
local CARD = Vector2.new(372, 206)
local CARD_GAP = Vector2.new(16, 14)

local TEXT = {
	Title = "Aura Shop",
	Label = "AURA SHOP",
	Locked = "Rebirth to unlock",
	LockedToast = "Rebirth once at the Private Airport to open the Aura Shop",
	Level = "Lv %d",
	LevelMax = "Lv %d/%d",
	BuyOne = "BUY 1",
	BuyMax = "BUY MAX",
	Maxed = "MAXED",
	NotEnough = "Not enough Aura",
	Upgraded = "%s → Lv %d",
	AuraLevel = "Aura Level %d",
	Glow = "%s glow",
	NoGlow = "No glow yet",
	NextGlow = "next: %s at %d",
	TooFar = "Walk up to the Aura Shop",
}

-- Karty sklepu: nazwa, ikona, kolor paska, opis i jak pokazać efekt na danym poziomie.
local UPGRADES = {
	ClickBoost = {
		name = "Click Boost",
		icon = "Click",
		colors = Theme.Gradients.CardPink,
		caption = "Click Multiplier for clicks and all activities",
		effect = function(level)
			return "×" .. Format.small(Rebirth.effect("ClickBoost", level))
		end,
	},
	Luck = {
		name = "Luck",
		icon = "Luck",
		colors = Theme.Gradients.Green,
		caption = "Luck in eggs and boxes bought with L$",
		effect = function(level)
			return "+" .. Format.small((Rebirth.effect("Luck", level) - 1) * 100) .. "%"
		end,
	},
	AuraGain = {
		name = "Aura Gain",
		icon = "Aura",
		colors = Theme.Gradients.Aura,
		caption = "More Aura from Rebirths and the Aura bar",
		effect = function(level)
			return "+" .. Format.small((Rebirth.effect("AuraGain", level) - 1) * 100) .. "%"
		end,
	},
	MergeLuck = {
		name = "Merge Luck",
		icon = "Merge",
		colors = Theme.Gradients.CardBlue,
		caption = "Merge chance per pet or clothing item",
		effect = function(level)
			return Format.small(Rebirth.effect("MergeLuck", level) * 100) .. "%"
		end,
	},
}

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

local function nextGlow(auraLevel)
	for _, g in ipairs(Economy.Aura.Glow) do
		if auraLevel < g.Level then
			return g
		end
	end
	return nil
end

function AuraShop.start(hud)
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	local stands = {}
	local current = nil

	local function unlocked()
		local view = State.view
		return view ~= nil and view.AuraUnlocked == true
	end

	------------------------------------------------------------- Napis nad stoiskiem
	local labels = {}
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
		if unlocked() then
			entry.line.set({
				{ icon = "Aura", size = 40 },
				{ text = TEXT.Label, size = 32, colors = Theme.Gradients.Aura },
			})
		else
			entry.line.set({
				{ icon = "Lock", size = 34 },
				{ text = TEXT.Locked, size = 26, colors = Theme.Gradients.Gray },
			})
		end
		entry.gui.Enabled = part ~= nil and State.view ~= nil and not State.busy
	end

	local function makeLabel(stand)
		local gui = Kit.new("BillboardGui", {
			Name = "AuraShopLabel",
			Size = UDim2.fromOffset(420, 56),
			LightInfluence = 0,
			AlwaysOnTop = true,
			MaxDistance = 90,
			ResetOnSpawn = false,
			Enabled = false,
			Parent = playerGui,
		})
		local line = Kit.line(gui, { anchor = Vector2.new(0.5, 0.5), position = UDim2.fromScale(0.5, 0.5), height = 50 })
		labels[stand] = { gui = gui, line = line }
		updateLabel(stand)
	end

	------------------------------------------------------------- Duże E
	local promptGui = Kit.new("BillboardGui", {
		Name = "AuraShopPrompt",
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

	------------------------------------------------------------- Okno sklepu
	local window = Kit.panel(hud.gui, {
		name = "AuraShopWindow",
		size = WINDOW,
		title = TEXT.Title,
		icon = "Aura",
		padding = 30,
		top = 44,
		bottom = 26,
	})
	hud.registerScale(window.holder)
	hud.addPopup(window)
	local balanceLine = Kit.line(window.title.Parent, {
		name = "AuraBalance",
		anchor = Vector2.new(0, 0.5),
		position = UDim2.fromOffset(80 + Kit.measure(TEXT.Title, 56).X + 16, -2),
		height = 40,
	})
	balanceLine.holder.ZIndex = 6
	local grid = Kit.new("Frame", {
		Name = "Cards",
		Size = UDim2.new(1, 0, 0, 2 * CARD.Y + CARD_GAP.Y),
		BackgroundTransparency = 1,
		ZIndex = 3,
		Parent = window.content,
	})
	Kit.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(CARD.X, CARD.Y),
		CellPadding = UDim2.fromOffset(CARD_GAP.X, CARD_GAP.Y),
		FillDirectionMaxCells = 2,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = grid,
	})
	local footer = Kit.line(window.content, {
		name = "Footer",
		anchor = Vector2.new(0.5, 1),
		position = UDim2.new(0.5, 0, 1, -4),
		height = 36,
	})
	footer.holder.ZIndex = 4

	local cards = {}
	local busy = false

	local function deny(button, text, key)
		Sounds.play("NotEnough")
		hud.toast({ { text = text, size = 26, colors = Theme.Gradients.Red } }, key)
		if button ~= nil then
			Kit.shake(button.holder)
		end
	end

	local function buy(key, mode, button)
		if busy then
			return
		end
		local def = UPGRADES[key]
		busy = true
		local ok, result = pcall(function()
			return Net.func("BuyAuraUpgrade"):InvokeServer(key, mode)
		end)
		busy = false
		if not ok or type(result) ~= "table" then
			return
		end
		if result.Ok then
			Sounds.play("Unlock", { volume = 0.6 })
			hud.toast({ { icon = def.icon, size = 40 }, { text = string.format(TEXT.Upgraded, def.name, result.Level or 0), size = 26, colors = Theme.Gradients.Aura } }, "AuraUp")
			local card = cards[key]
			if card ~= nil then
				card.bump.Scale = 1.06
				TweenService:Create(card.bump, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
			end
		elseif result.Reason == "NotEnough" then
			deny(button, TEXT.NotEnough, "AuraNotEnough")
		elseif result.Reason == "TooFar" then
			deny(nil, TEXT.TooFar, "AuraFar")
		elseif result.Reason == "Locked" then
			deny(nil, TEXT.LockedToast, "AuraLocked")
		end
	end

	-- Karta: kolorowy pasek z ikoną, nazwą i poziomem; efekt teraz → po zakupie; opis; koszt i przyciski.
	local function makeCard(key, order)
		local def = UPGRADES[key]
		local holder = Kit.new("Frame", {
			Name = key,
			LayoutOrder = order,
			BackgroundTransparency = 1,
			ZIndex = 3,
			Parent = grid,
		})
		local inner = Kit.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Theme.White,
			BorderSizePixel = 0,
			ZIndex = 3,
			Parent = holder,
		})
		local bump = Kit.new("UIScale", { Parent = inner })
		Kit.corner(inner, 18)
		Kit.stroke(inner, 3, Enum.ApplyStrokeMode.Border)
		local band = Kit.new("Frame", {
			Name = "Band",
			Size = UDim2.new(1, 0, 0, 54),
			BackgroundColor3 = Theme.White,
			BorderSizePixel = 0,
			ZIndex = 4,
			Parent = inner,
		})
		Kit.corner(band, 18)
		Kit.gradient(band, def.colors, 90)
		-- dolne rogi paska proste (zaokrąglone są tylko górne, jak róg karty)
		local filler = Kit.new("Frame", {
			Position = UDim2.new(0, 0, 1, -18),
			Size = UDim2.new(1, 0, 0, 18),
			BackgroundColor3 = Theme.White,
			BorderSizePixel = 0,
			ZIndex = 4,
			Parent = band,
		})
		Kit.gradient(filler, { def.colors[2], def.colors[2] }, 90)
		Icons.make(def.icon, {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 10, 0.5, 0),
			Size = UDim2.fromOffset(44, 44),
			ZIndex = 6,
			Parent = band,
		})
		Kit.text(band, {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 62, 0.5, 0),
			Size = UDim2.new(1, -170, 0, 36),
			Text = def.name,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 6,
		}, { maxSize = 30, stroke = 3.5 })
		local levelLabel = Kit.text(band, {
			Name = "Level",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -14, 0.5, 0),
			Size = UDim2.fromOffset(100, 30),
			Text = "",
			TextXAlignment = Enum.TextXAlignment.Right,
			ZIndex = 6,
		}, { maxSize = 26, stroke = 3 })
		local effectLine = Kit.line(inner, {
			name = "Effect",
			anchor = Vector2.new(0, 0.5),
			position = UDim2.new(0, 16, 0, 82),
			height = 38,
		})
		effectLine.holder.ZIndex = 5
		local captionLabel = Kit.text(inner, {
			Name = "Caption",
			Position = UDim2.fromOffset(16, 104),
			Size = UDim2.new(1, -32, 0, 22),
			Text = def.caption,
			TextColor3 = Theme.Muted,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 5,
		}, { maxSize = 17, stroke = 0 })
		local costLine = Kit.line(inner, {
			name = "Cost",
			anchor = Vector2.new(0, 0.5),
			position = UDim2.new(0, 16, 1, -32),
			height = 40,
		})
		costLine.holder.ZIndex = 5
		local buyOne = Kit.button(inner, {
			name = "BuyOne",
			size = Vector2.new(96, 44),
			text = TEXT.BuyOne,
			colors = Theme.Gradients.Green,
			anchor = Vector2.new(1, 1),
			position = UDim2.new(1, -124, 1, -10),
			textSize = 20,
		})
		local buyMax = Kit.button(inner, {
			name = "BuyMax",
			size = Vector2.new(104, 44),
			text = TEXT.BuyMax,
			colors = Theme.Gradients.Aura,
			anchor = Vector2.new(1, 1),
			position = UDim2.new(1, -12, 1, -10),
			textSize = 20,
		})
		local maxed = Kit.button(inner, {
			name = "Maxed",
			size = Vector2.new(212, 44),
			text = TEXT.Maxed,
			colors = Theme.Gradients.Gray,
			anchor = Vector2.new(1, 1),
			position = UDim2.new(1, -12, 1, -10),
			textSize = 22,
			sound = false,
		})
		for _, b in ipairs({ buyOne, buyMax, maxed }) do
			b.holder.ZIndex = 5
		end
		buyOne.Activated:Connect(function()
			buy(key, "One", buyOne)
		end)
		buyMax.Activated:Connect(function()
			buy(key, "Max", buyMax)
		end)
		cards[key] = {
			bump = bump,
			level = levelLabel,
			effect = effectLine,
			caption = captionLabel,
			cost = costLine,
			buyOne = buyOne,
			buyMax = buyMax,
			maxed = maxed,
		}
	end

	for i, key in ipairs(Rebirth.UpgradeOrder) do
		makeCard(key, i)
	end

	local function renderWindow()
		local view = State.view
		if view == nil then
			return
		end
		local aura = view.Aura or 0
		local levels = view.AuraUpgrades or {}
		balanceLine.set({
			{ icon = "Aura", size = 38 },
			{ text = Format.number(math.floor(aura + 1e-9)), size = 32, colors = Theme.Gradients.Aura },
		})
		for _, key in ipairs(Rebirth.UpgradeOrder) do
			local def = UPGRADES[key]
			local card = cards[key]
			local level = levels[key] or 0
			local max = Rebirth.maxLevel(key)
			if max ~= nil then
				card.level.Text = string.format(TEXT.LevelMax, level, max)
			else
				card.level.Text = string.format(TEXT.Level, level)
			end
			local cost = Formulas.auraUpgradeCost(key, level + 1)
			if cost == nil then
				card.effect.set({ { text = def.effect(level), size = 30, colors = Theme.Gradients.Gold } })
				card.cost.set({})
				card.buyOne.holder.Visible = false
				card.buyMax.holder.Visible = false
				card.maxed.holder.Visible = true
			else
				card.effect.set({
					{ text = def.effect(level), size = 26 },
					{ text = "→", size = 26 },
					{ text = def.effect(level + 1), size = 30, colors = Theme.Gradients.Gold },
				})
				card.cost.set({
					{ icon = "Aura", size = 32 },
					{ text = Format.number(cost), size = 28, colors = Theme.Gradients.Aura },
				})
				card.buyOne.holder.Visible = true
				card.buyMax.holder.Visible = true
				card.maxed.holder.Visible = false
				local colorsOne, colorsMax = Theme.Gradients.Green, Theme.Gradients.Aura
				if aura + 1e-9 < cost then
					colorsOne, colorsMax = Theme.Gradients.Gray, Theme.Gradients.Gray
				end
				card.buyOne.setColors(colorsOne)
				card.buyMax.setColors(colorsMax)
			end
		end
		local auraLevel = view.AuraLevel or 0
		local glow = Formulas.glowFor(auraLevel)
		local items = { { text = string.format(TEXT.AuraLevel, auraLevel), size = 24, colors = Theme.Gradients.Gold } }
		if glow ~= nil then
			table.insert(items, { text = string.format(TEXT.Glow, glow), size = 22, color = Theme.GlowColors[glow] or Theme.White })
		else
			table.insert(items, { text = TEXT.NoGlow, size = 22, color = Theme.Muted, stroke = 0 })
		end
		local upcoming = nextGlow(auraLevel)
		if upcoming ~= nil then
			table.insert(items, { text = string.format(TEXT.NextGlow, upcoming.Color, upcoming.Level), size = 20, color = Theme.Muted, stroke = 0 })
		end
		footer.set(items)
	end

	local function openWindow()
		if current == nil or State.busy then
			return
		end
		if not unlocked() then
			deny(nil, TEXT.LockedToast, "AuraLocked")
			return
		end
		renderWindow()
		promptGui.Enabled = false
		window.open()
	end

	promptButton.Activated:Connect(function()
		Sounds.play("Button")
		openWindow()
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or input.KeyCode ~= Enum.KeyCode.E then
			return
		end
		if window.isOpen() then
			window.hide()
		elseif promptGui.Enabled then
			Sounds.play("Button")
			openWindow()
		end
	end)

	------------------------------------------------------------- Stoiska i najbliższe
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
		-- przed pierwszym Rebirthem nie ma E (napis nad stoiskiem mówi, jak je otworzyć)
		promptGui.Enabled = current ~= nil and unlocked() and not window.isOpen()
	end)

	local lastKey = nil
	State.onChange(function(view)
		local key = tostring(view.AuraUnlocked) .. ":" .. tostring(State.busy)
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

return AuraShop
