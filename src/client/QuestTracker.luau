-- Zadania dzienne na ekranie (Etap 11, część 3), jak lista zadań w Pet Simulator 99, ale po swojemu:
--   • po prawej u góry, pod paskiem Robloxa, bez tła: nagłówek „Daily Quests 1/3” z cienką kreską,
--     a pod nim 3 zadania wyrównane do prawej (cel białym napisem, pod nim postęp, ikona nagrody
--     i ikona Aury od Rebirth 1). Gotowe do odebrania: złote CLAIM! i całe zadanie pulsuje; odebrane:
--     szary cel i zielone DONE!; po odebraniu wszystkich lista zwija się do czasu do nowych zadań,
--   • pod listą zielony przycisk REWARDS z kropką „!” (okno nagrody dziennej i zadań, Daily.luau),
--     a klik w nagłówek otwiera to okno na zakładce QUESTS. Same zadania nie łapią kliknięć, więc
--     klikanie po LP w tym miejscu działa jak wcześniej,
--   • przycisk „>” na lewo od listy chowa ją za prawą krawędź (zostaje „<”), jak menu po lewej;
--     wybór jest w zapisie gracza (Settings.HideQuests, z zapisu tylko przy pierwszym stanie),
--   • lista stoi nad kolumną SHOP / TELEPORT / Starter Pack (Shop.luau, hud.shopColumn); gdy miejsca
--     jest mniej (np. z przyciskiem Starter Pack na niskim ekranie), jest trochę mniejsza. Na niskim
--     ekranie (telefon poziomo) stoi na lewo od kolumny,
--   • w czasie aktywności i animacji (State.busy, np. czat wywiadu jest po prawej) i przy otwartym
--     oknie lista się chowa.
-- Postęp liczy serwer (RewardsService); stan przychodzi w view.Quests.

local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared.Config.Economy)
local Format = require(Shared.Format)
local Net = require(Shared.Net)
local State = require(script.Parent.State)
local Theme = require(script.Parent.Ui.Theme)
local Kit = require(script.Parent.Ui.Kit)
local Icons = require(script.Parent.Ui.Icons)
local Sounds = require(script.Parent.Ui.Sounds)
local ShopArt = require(script.Parent.Ui.ShopArt)
local Fx = require(script.Parent.Ui.Fx)
local Quests = require(script.Parent.Quests)
local Daily = require(script.Parent.Daily)
local Shop = require(script.Parent.Shop)

local QuestTracker = {}

-- Piksele bazowe (1280×720, jak reszta HUD).
local L = {
	Right = 22, -- prawa krawędź listy (kolumna SHOP stoi 24 px od krawędzi)
	Top = 10, -- odstęp od paska Robloxa
	TitleH = 30,
	TitleSize = 25,
	TitleIcon = 30,
	DividerY = 32, -- cienka kreska pod nagłówkiem
	RowsY = 40, -- pierwsze zadanie
	LineH = 21, -- linia celu i linia postępu
	TextSize = 19,
	RowGap = 8, -- odstęp między zadaniami
	Icon = 26, -- ikona nagrody (jajko, box, boost)
	AuraIcon = 22,
	IconGap = 4,
	ButtonGap = 8,
	Button = Vector2.new(176, 42),
	ButtonEdge = 4,
	ToggleW = 36,
	ToggleH = 64,
	ToggleGap = 8,
	HiddenEdge = 6, -- schowana lista: „<” tyle pikseli od krawędzi ekranu
	ColumnClear = 36, -- nad kolumną SHOP (koszyk wystaje nad kafelek do 30 px; Shop: ColumnTop = 10 + 236 + 36)
	ShortGap = 12, -- niski ekran: odstęp listy od kolumny
	ShortReserve = 90, -- niski ekran: dół zostaje dla boostów i przycisku skoku
	MinFit = 0.6,
	Pop = 1.25, -- podskok postępu
}

local TEXT = {
	Title = "Daily Quests",
	Count = "%d/%d",
	Claim = "CLAIM!",
	Done = "DONE!",
	AllDone = "All done! New in %s",
	Rewards = "REWARDS",
}

local EGG_B = Color3.fromRGB(255, 208, 90) -- złote jajko (B), jak w ShopArt

local function hudScale(viewport)
	return math.clamp(math.min(viewport.X / Theme.BaseSize.X, viewport.Y / Theme.BaseSize.Y), Theme.MinScale, Theme.MaxScale)
end

local function clock(seconds)
	seconds = math.max(0, math.floor(seconds))
	return string.format("%02d:%02d:%02d", math.floor(seconds / 3600), math.floor(seconds % 3600 / 60), seconds % 60)
end

-- Otwiera okno nagrody dziennej (tab = "Quests" albo nil: zakładka sama), a otwarte zamyka.
local function toggleDaily(tab)
	if Daily.toggle ~= nil then
		Daily.toggle(tab)
	end
end

function QuestTracker.start(hud)
	local root = Kit.new("Frame", {
		Name = "QuestTracker",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -L.Right, 0, L.Top),
		Size = UDim2.fromOffset(300, 220),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = hud.gui,
	})
	local rootScale = Kit.new("UIScale", { Parent = root })
	local list = Kit.new("Frame", {
		Name = "List",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(260, 220),
		BackgroundTransparency = 1,
		ZIndex = 3,
		Parent = root,
	})

	------------------------------------------------------------- Nagłówek
	local title = Kit.line(list, { name = "Title", anchor = Vector2.new(1, 0.5), position = UDim2.new(1, 0, 0, L.TitleH / 2), height = L.TitleH })
	title.holder.ZIndex = 4
	local titleScale = Kit.new("UIScale", { Parent = title.holder })
	-- cienka kreska, która znika w lewo
	local divider = Kit.new("Frame", {
		Name = "Divider",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, L.DividerY),
		Size = UDim2.new(1, 0, 0, 3),
		BackgroundColor3 = Theme.GoldText,
		BorderSizePixel = 0,
		ZIndex = 4,
		Parent = list,
	})
	Kit.corner(divider, 2)
	Kit.new("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0.45),
			NumberSequenceKeypoint.new(1, 0.05),
		}),
		Parent = divider,
	})
	-- klik w nagłówek: okno na zakładce QUESTS (same zadania nie łapią kliknięć)
	local titleHit = Kit.new("TextButton", {
		Name = "TitleHit",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(1, 0, 0, L.TitleH),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "",
		ZIndex = 9,
		Parent = list,
	})
	titleHit.MouseEnter:Connect(function()
		TweenService:Create(titleScale, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1.06 }):Play()
	end)
	titleHit.MouseLeave:Connect(function()
		TweenService:Create(titleScale, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end)
	titleHit.Activated:Connect(function()
		Sounds.play("Button")
		toggleDaily("Quests")
	end)

	------------------------------------------------------------- Zadania
	local rows = {}
	for i = 1, Economy.Rewards.QuestsPerDay do
		local frame = Kit.new("Frame", {
			Name = "Quest" .. i,
			AnchorPoint = Vector2.new(1, 0.5), -- CLAIM! pulsuje od prawej krawędzi
			Position = UDim2.new(1, 0, 0, L.RowsY + (i - 1) * (2 * L.LineH + L.RowGap) + L.LineH),
			Size = UDim2.new(1, 0, 0, 2 * L.LineH),
			BackgroundTransparency = 1,
			Visible = false,
			ZIndex = 4,
			Parent = list,
		})
		local goal = Kit.line(frame, { name = "Goal", anchor = Vector2.new(1, 0), position = UDim2.fromScale(1, 0), height = L.LineH })
		goal.holder.ZIndex = 5
		local progress = Kit.line(frame, { name = "Progress", anchor = Vector2.new(1, 0.5), position = UDim2.new(1, 0, 0, L.LineH * 1.5), height = L.LineH })
		progress.holder.ZIndex = 5
		rows[i] = {
			frame = frame,
			goal = goal,
			progress = progress,
			pop = Kit.new("UIScale", { Parent = progress.holder }), -- podskok postępu
			pulse = Kit.new("UIScale", { Parent = frame }), -- CLAIM!: całe zadanie pulsuje
			aura = Icons.make("Aura", {
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -(L.Icon + L.IconGap), 0, L.LineH * 1.5),
				Size = UDim2.fromOffset(L.AuraIcon, L.AuraIcon),
				Visible = false,
				ZIndex = 5,
				Parent = frame,
			}),
			iconsW = 0,
		}
	end

	-- po odebraniu wszystkich: jedna linia z czasem do nowych zadań
	local doneLine = Kit.line(list, { name = "AllDone", anchor = Vector2.new(1, 0), position = UDim2.new(1, 0, 0, L.RowsY), height = L.LineH + 4 })
	doneLine.holder.ZIndex = 5
	doneLine.holder.Visible = false

	------------------------------------------------------------- REWARDS
	local button = Kit.button(list, {
		name = "Rewards",
		size = L.Button,
		colors = Theme.Gradients.Green,
		radius = 16,
		edge = L.ButtonEdge,
		anchor = Vector2.new(1, 0),
		position = UDim2.new(1, 0, 0, 0),
	})
	button.holder.ZIndex = 6
	Icons.make("Gift", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, 28, 0.5, -1),
		Size = UDim2.fromOffset(40, 40),
		Rotation = -10,
		ZIndex = 6,
		Parent = button.face,
	})
	Kit.text(button.face, {
		Name = "Label",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 52, 0.5, 1),
		Size = UDim2.new(1, -66, 0, 30), -- prawy róg zostaje dla kropki „!”
		Text = TEXT.Rewards,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 6,
	}, { maxSize = 25, stroke = 3.5 })
	local badge = Kit.badge(button.body, { Position = UDim2.new(1, 4, 0, -2) })
	Fx.button(button, 1.06)
	button.Activated:Connect(function()
		toggleDaily(nil)
	end)

	------------------------------------------------------------- Przycisk chowania (jak menu po lewej)
	local toggleHolder = Kit.new("Frame", {
		Name = "QuestsToggle",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromOffset(0, 100),
		Size = UDim2.fromOffset(L.ToggleW, L.ToggleH),
		BackgroundTransparency = 1,
		ZIndex = 6,
		Parent = root,
	})
	local toggle = Kit.new("TextButton", {
		Name = "Body",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Font = Theme.Font,
		Text = ">",
		TextSize = 48,
		TextColor3 = Theme.White,
		ZIndex = 6,
		Parent = toggleHolder,
	})
	Kit.stroke(toggle, 4.5)
	local toggleScale = Kit.new("UIScale", { Parent = toggle })
	toggle.MouseEnter:Connect(function()
		toggle.TextColor3 = Theme.GoldText
	end)
	toggle.MouseLeave:Connect(function()
		toggle.TextColor3 = Theme.White
	end)

	------------------------------------------------------------- Układ
	local state = { has = false, allDone = false, count = 0, hidden = false, settingLoaded = false }
	local placeTween = nil

	-- Lista jest na ekranie, gdy są zadania, gracz nie jest w aktywności ani animacji (State.busy)
	-- i nie ma otwartego okna (sklep, pety, nagroda dzienna…).
	local function shouldShow()
		return state.has and not State.busy and not hud.windowOpen()
	end

	local function contentWidth()
		local w = title.holder.Size.X.Offset
		if state.allDone then
			w = math.max(w, doneLine.holder.Size.X.Offset)
		else
			for _, row in ipairs(rows) do
				if row.frame.Visible then
					w = math.max(w, row.goal.holder.Size.X.Offset, row.iconsW + row.progress.holder.Size.X.Offset)
				end
			end
		end
		return math.max(w, L.Button.X)
	end

	-- Rozmiar i miejsce listy: nad kolumną SHOP (na niskim ekranie na lewo od niej), w skali HUD,
	-- a gdy miejsca brakuje, trochę mniejsza (fit). Schowana: zostaje sam „<” przy krawędzi.
	local function relayout(animate)
		local camera = Workspace.CurrentCamera
		local viewport = (camera and camera.ViewportSize) or Theme.BaseSize
		local s = hudScale(viewport)
		local short = viewport.Y < Shop.ShortScreen
		local contentBottom = L.RowsY + state.count * (2 * L.LineH + L.RowGap) - L.RowGap
		if state.allDone or state.count == 0 then
			contentBottom = L.RowsY + L.LineH + 4
		end
		local buttonY = contentBottom + L.ButtonGap
		button.holder.Position = UDim2.new(1, 0, 0, buttonY)
		local height = buttonY + L.Button.Y + L.ButtonEdge
		local width = contentWidth()
		list.Size = UDim2.fromOffset(width, height)
		root.Size = UDim2.fromOffset(L.ToggleW + L.ToggleGap + width, height)
		toggleHolder.Position = UDim2.fromOffset(0, contentBottom / 2)

		local top = L.Top * s
		local column = hud.shopColumn
		local x = -L.Right
		local fit = 1
		if short then
			local columnWidth = (column and column.AbsoluteSize.X) or 184 * s
			x = -(18 + columnWidth + L.ShortGap * s)
			fit = (hud.gui.AbsoluteSize.Y - top - L.ShortReserve * s) / (height * s)
		elseif column ~= nil and column.AbsoluteSize.Y > 0 then
			fit = (column.AbsolutePosition.Y - L.ColumnClear * s - top) / (height * s)
		end
		fit = math.clamp(fit, L.MinFit, 1)
		local k = s * fit
		rootScale.Scale = k

		local goalX = x
		if state.hidden then
			if short then
				goalX = x + (L.ToggleGap + width) * k -- „<” przy kolumnie
			else
				goalX = -L.HiddenEdge + (L.ToggleGap + width) * k -- „<” przy krawędzi ekranu
			end
		end
		local goal = UDim2.new(1, math.floor(goalX + 0.5), 0, math.floor(top + 0.5))
		if placeTween ~= nil then
			placeTween:Cancel()
			placeTween = nil
		end
		toggle.Text = (state.hidden and "<") or ">"
		if animate and not short then
			-- lista wyjeżdża za prawą krawędź (i wraca); po schowaniu jest niewidoczna
			list.Visible = true
			local tween = TweenService:Create(root, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = goal })
			placeTween = tween
			tween.Completed:Connect(function(playbackState)
				if playbackState == Enum.PlaybackState.Completed and placeTween == tween then
					placeTween = nil
					list.Visible = not state.hidden
				end
			end)
			tween:Play()
		else
			root.Position = goal
			list.Visible = not state.hidden
		end
	end

	local function setHidden(hidden, animate)
		state.hidden = hidden
		relayout(animate)
	end
	toggle.Activated:Connect(function()
		Sounds.play("Button")
		Fx.bump(toggleScale, 1.25, 0.3)
		setHidden(not state.hidden, true)
		Net.event("SetSetting"):FireServer("HideQuests", state.hidden)
	end)

	------------------------------------------------------------- Rysowanie
	local function setRewardIcon(row, key)
		if row.icon ~= nil then
			row.icon:Destroy()
			row.icon = nil
		end
		local info = Quests.questInfo(key)
		local item = info and info.Reward.Items[1]
		local kind = "Starter"
		if item ~= nil and Daily.artFor ~= nil then
			kind = Daily.artFor(item)
		end
		local icon = ShopArt.mini(kind)
		icon.AnchorPoint = Vector2.new(1, 0.5)
		icon.Position = UDim2.new(1, 0, 0, L.LineH * 1.5)
		icon.Size = UDim2.fromOffset(L.Icon, L.Icon)
		icon.ZIndex = 5
		if item ~= nil and item.Kind == "Egg" and item.Egg == "B" and icon:IsA("ImageLabel") then
			icon.ImageColor3 = EGG_B
		end
		icon.Parent = row.frame
		row.icon = icon
	end

	local function setPulse(row, on)
		if on and row.pulseTween == nil then
			row.pulse.Scale = 1
			row.pulseTween = TweenService:Create(row.pulse, TweenInfo.new(0.55, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = 1.06 })
			row.pulseTween:Play()
		elseif not on and row.pulseTween ~= nil then
			row.pulseTween:Cancel()
			row.pulseTween = nil
			row.pulse.Scale = 1
		end
	end

	local secondsLeft, receivedAt = 0, os.clock()
	local doneText = nil
	local function updateDoneLine()
		if not state.allDone then
			return false
		end
		local left = math.max(0, secondsLeft - (os.clock() - receivedAt))
		local text = string.format(TEXT.AllDone, clock(left))
		if text == doneText then
			return false
		end
		doneText = text
		doneLine.set({ { icon = "Clock", size = 22 }, { text = text, size = 18, colors = Theme.Gradients.LP } })
		return true
	end

	local titleKey = nil
	local function render(view)
		local quests = view.Quests
		local listData = (quests and quests.List) or {}
		local claimed = 0
		for _, quest in ipairs(listData) do
			if quest.Claimed then
				claimed = claimed + 1
			end
		end
		state.has = #listData > 0
		state.count = #listData
		state.allDone = state.has and claimed >= #listData
		if quests ~= nil then
			secondsLeft = quests.SecondsLeft or 0
			receivedAt = os.clock()
		end
		local aura = (quests and quests.Aura) or 0

		local key = claimed .. "/" .. #listData .. tostring(state.allDone)
		if key ~= titleKey then
			titleKey = key
			title.set({
				{ icon = "Quest", size = L.TitleIcon },
				{ text = TEXT.Title, size = L.TitleSize, colors = (state.allDone and Theme.Gradients.Green) or Theme.Gradients.Gold },
				{ text = string.format(TEXT.Count, claimed, #listData), size = L.TitleSize },
			})
		end

		for i, row in ipairs(rows) do
			local quest = listData[i]
			local show = quest ~= nil and not state.allDone
			row.frame.Visible = show
			if not show then
				setPulse(row, false)
			else
				local target = math.max(1, quest.Target or 1)
				local progress = math.min(target, quest.Progress or 0)
				local kind = "Normal"
				if quest.Claimed then
					kind = "Done"
				elseif progress >= target then
					kind = "Ready"
				end
				local rowKey = table.concat({ tostring(quest.Key), tostring(progress), kind, tostring(aura > 0) }, "|")
				if row.key ~= rowKey then
					local grew = row.quest == quest.Key and progress > (row.value or 0)
					row.key = rowKey
					if row.quest ~= quest.Key then
						row.quest = quest.Key
						setRewardIcon(row, quest.Key)
					end
					row.value = progress
					local goalItem = { text = Quests.goalText(quest.Key, target, true), size = L.TextSize }
					if kind == "Done" then
						goalItem.colors = Theme.Gradients.Gray
					end
					row.goal.set({ goalItem })
					if kind == "Done" then
						row.progress.set({ { icon = "Check", size = L.AuraIcon }, { text = TEXT.Done, size = L.TextSize, colors = Theme.Gradients.Green } })
						row.icon.Visible = false
						row.aura.Visible = false
						row.iconsW = 0
					else
						local text = Format.number(progress) .. "/" .. Format.number(target)
						local colors = Theme.Gradients.LP
						if kind == "Ready" then
							text = TEXT.Claim
							colors = Theme.Gradients.Gold
						end
						row.progress.set({ { text = text, size = L.TextSize, colors = colors } })
						row.icon.Visible = true
						row.aura.Visible = aura > 0
						row.iconsW = L.Icon + L.IconGap
						if aura > 0 then
							row.iconsW = row.iconsW + L.AuraIcon + L.IconGap
						end
					end
					row.progress.holder.Position = UDim2.new(1, -row.iconsW, 0, L.LineH * 1.5)
					setPulse(row, kind == "Ready")
					if grew then
						Fx.bump(row.pop, (kind == "Normal" and L.Pop) or 1.4, 0.35)
					end
				end
			end
		end

		doneLine.holder.Visible = state.allDone
		if state.allDone then
			doneText = nil
			updateDoneLine()
		end
		local daily = view.Daily
		badge.set(((daily ~= nil and daily.CanClaim) or Quests.claimable(view) > 0) and "!" or nil)

		-- schowana lista z zapisu tylko przy wejściu; potem decyduje przycisk (bez czekania na serwer)
		if not state.settingLoaded and view.Settings ~= nil then
			state.settingLoaded = true
			state.hidden = view.Settings.HideQuests == true
		end
		if placeTween == nil then
			relayout(false) -- w czasie wysuwania układ policzy się po animacji
		end
		root.Visible = shouldShow()
	end

	State.onChange(function(view)
		render(view)
	end)

	-- miejsce zmienia ekran i kolumna SHOP (np. przycisk Starter Pack znika po 72 h)
	local function onLayoutChange()
		if placeTween == nil then
			relayout(false)
		end
	end
	hud.gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(onLayoutChange)
	if Workspace.CurrentCamera ~= nil then
		Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(onLayoutChange)
	end
	local column = hud.shopColumn
	if column ~= nil then
		column:GetPropertyChangedSignal("AbsolutePosition"):Connect(onLayoutChange)
		column:GetPropertyChangedSignal("AbsoluteSize"):Connect(onLayoutChange)
	end

	-- w czasie aktywności, animacji i przy otwartym oknie lista się chowa; po odebraniu wszystkich
	-- zadań odlicza czas do nowych
	task.spawn(function()
		local timer = 0
		while true do
			task.wait(0.2)
			local visible = shouldShow()
			if root.Visible ~= visible then
				root.Visible = visible
			end
			timer = timer + 0.2
			if timer >= 1 then
				timer = 0
				if visible then
					-- tylko napis (szerokość listy liczy się przy zmianie stanu, więc „>” nie skacze co sekundę)
					updateDoneLine()
				end
			end
		end
	end)
end

return QuestTracker
