-- Nagroda dzienna i zadania dzienne po stronie gracza (Etap 11, części 2 i 3):
--   • okno z dwiema zakładkami: REWARDS i QUESTS (treść zadań: Quests.luau); czerwona kropka „!” na
--     zakładce, gdy jest co odebrać,
--   • REWARDS: 7 dni z Economy.Rewards.DailyStreak (dzień, grafika, co daje), odebrane z zielonym
--     znaczkiem, dzisiejsza złota i pulsuje, dzień 7 fioletowy; seria nad dniami, a pod nimi CLAIM
--     albo czas do następnej nagrody,
--   • okno wyskakuje samo raz po wejściu, gdy jest co odebrać (gdy gracz niczego nie robi),
--   • tablica z nagrodą dzienną w Downtown (DailyBoard, tag LarpDaily): napis i duże E otwierają okno
--     (na REWARDS, gdy nagroda czeka, inaczej na QUESTS),
--   • o północy UTC komunikat o nagrodzie i nowych zadaniach (Notify DailyReady).
-- Odbiera serwer (RewardsService, Logic/Rewards); jajka i boxy z nagrody otwierają Eggs.luau
-- i Boxes.luau (Notify Reward), a komunikat o nagrodzie jest jeden, na dole ekranu.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared.Config.Economy)
local Net = require(Shared.Net)
local State = require(script.Parent.State)
local Theme = require(script.Parent.Ui.Theme)
local Kit = require(script.Parent.Ui.Kit)
local Icons = require(script.Parent.Ui.Icons)
local Sounds = require(script.Parent.Ui.Sounds)
local ShopArt = require(script.Parent.Ui.ShopArt)
local Fx = require(script.Parent.Ui.Fx)
local StandAnchor = require(script.Parent.StandAnchor)
local Codes = require(script.Parent.Codes)
local Quests = require(script.Parent.Quests)

local Daily = {}

local STAND_TAG = "LarpDaily" -- jak RewardsService.DailyTag na serwerze
local SHOW_DISTANCE = 9
local HIDE_DISTANCE = 13
local AUTO_OPEN_DELAY = 3 -- s po pierwszym stanie od serwera
local AUTO_OPEN_WAIT = 90 -- najdłużej tyle czekamy, aż gracz nie będzie zajęty (s)
-- Napis nad tablicą jak nad sklepem Aury (Kit.worldFrame).
local LABEL_HEIGHT = 1.6
local LABEL_DESIGN = Vector2.new(460, 56)
local LABEL_PIXELS_PER_STUD = 30
local LABEL_DISTANCE = 80

-- Okno (piksele bazowe 1280×720): zakładki, a pod nimi strona REWARDS (seria, rząd 7 dni, przycisk
-- i podpowiedź) albo QUESTS (Quests.luau) tej samej wielkości.
local L = {
	Tile = Vector2.new(112, 176),
	TileGap = 12,
	Band = 34,
	Padding = 28,
	Top = 44,
	Bottom = 16,
	HeaderH = 40,
	Button = Vector2.new(340, 62),
	Tab = Vector2.new(214, 52),
	TabGap = 18,
	PageGap = 12,
}
local DAYS = #Economy.Rewards.DailyStreak
L.RowW = DAYS * L.Tile.X + (DAYS - 1) * L.TileGap
L.RowY = L.HeaderH + 10
L.ButtonY = L.RowY + L.Tile.Y + 18
L.NoteY = L.ButtonY + L.Button.Y + 5 + 8
L.ContentH = L.NoteY + 26
L.PageTop = L.Tab.Y + 6 + L.PageGap -- 6 = krawędź przycisku Kit
L.Window = Vector2.new(L.RowW + 2 * L.Padding, L.Top + L.PageTop + L.ContentH + L.Bottom)

local TEXT = {
	Title = "Daily Rewards",
	QuestsTitle = "Daily Quests",
	TabRewards = "REWARDS",
	TabQuests = "QUESTS",
	Label = "DAILY REWARDS",
	Day = "DAY %d",
	Claim = "CLAIM DAY %d!",
	Next = "NEXT IN %s",
	NewDay = "NEW DAY!",
	ClaimedButton = "CLAIMED!",
	Streak = "Streak: %d days",
	StreakOne = "Streak: 1 day",
	StreakNew = "Come back every day for better rewards!",
	StreakLost = "Streak lost! Starting over",
	Note = "Miss a day and your streak starts over",
	Ready = "Your daily reward and new quests are ready!",
	ReadyQuests = "New daily quests are ready!",
	ClaimedToast = "Day %d claimed!",
	Claimed = "Already claimed today",
	PetInventory = "No room for pets: sell or merge some first",
	ClothInventory = "No room for clothes: sell or merge some first",
	Error = "Something went wrong, try again",
	BoostLP = "2x LP %d min",
	BoostAutoSell = "Auto Sell %d min",
	Egg = "%dx Egg",
	EggB = "%dx Golden Egg",
	Box = "%dx Box",
	Premium = "Premium Egg",
	PremiumMany = "%dx Premium Egg",
}

-- Kolory pasków: zwykły dzień, dzisiejszy, odebrany i dzień 7.
local COLORS = {
	Normal = Theme.Gradients.CardBlue,
	Today = Theme.Gradients.Gold,
	Done = Theme.Gradients.Owned,
	Big = Theme.Gradients.Premium,
}
local TILE_BG = {
	Normal = Theme.Gradients.Panel,
	Today = { Color3.fromRGB(255, 249, 214), Color3.fromRGB(255, 222, 120) },
	Done = { Color3.fromRGB(240, 255, 238), Color3.fromRGB(204, 240, 198) },
}

-- Grafika dnia (ShopArt) z pierwszej rzeczy nagrody i mała ikona drugiej rzeczy (np. Auto Sell).
local function artFor(item)
	if item.Kind == "Boost" then
		if item.Boost == "AutoSell" then
			return "BoostAutoSell", "SellCash"
		end
		return "Boost2xLP", "Boost"
	elseif item.Kind == "Egg" then
		if item.Egg == "B" then
			return "RewardEggB", "Egg"
		end
		return "RewardEggA", "Egg"
	elseif item.Kind == "Box" then
		return "RewardBox", "Clothes"
	elseif item.Kind == "PremiumEgg" then
		return "PremiumEgg", "Premium"
	end
	return "Starter", "Gift"
end

Daily.artFor = artFor -- też lista zadań na ekranie (QuestTracker)

local function itemText(item)
	local count = item.Count or 1
	if item.Kind == "Boost" then
		if item.Boost == "AutoSell" then
			return string.format(TEXT.BoostAutoSell, item.Minutes or 0)
		end
		return string.format(TEXT.BoostLP, item.Minutes or 0)
	elseif item.Kind == "Egg" then
		if item.Egg == "B" then
			return string.format(TEXT.EggB, count)
		end
		return string.format(TEXT.Egg, count)
	elseif item.Kind == "Box" then
		return string.format(TEXT.Box, count)
	elseif item.Kind == "PremiumEgg" then
		if count > 1 then
			return string.format(TEXT.PremiumMany, count)
		end
		return TEXT.Premium
	end
	return "?"
end

local function rewardText(reward)
	local lines = {}
	for i, item in ipairs(reward.Items) do
		local text = itemText(item)
		if i > 1 then
			text = "+" .. text
		end
		table.insert(lines, text)
	end
	return table.concat(lines, "\n")
end

local function clock(seconds)
	seconds = math.max(0, math.floor(seconds))
	return string.format("%02d:%02d:%02d", math.floor(seconds / 3600), math.floor(seconds % 3600 / 60), seconds % 60)
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

function Daily.start(hud)
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	local stands = {}
	local current = nil

	------------------------------------------------------------- Okno
	local window = Kit.panel(hud.gui, {
		name = "DailyWindow",
		size = L.Window,
		title = TEXT.Title,
		icon = "Gift",
		padding = L.Padding,
		top = L.Top,
		bottom = L.Bottom,
	})
	hud.registerScale(window.holder)
	hud.addWindow(window)

	-- strony pod zakładkami: REWARDS (7 dni) i QUESTS (Quests.luau)
	local function page(name)
		return Kit.new("Frame", {
			Name = name,
			Position = UDim2.fromOffset(0, L.PageTop),
			Size = UDim2.new(1, 0, 0, L.ContentH),
			BackgroundTransparency = 1,
			ZIndex = 4,
			Parent = window.content,
		})
	end
	local rewardsPage = page("RewardsPage")
	local questsPage = page("QuestsPage")
	questsPage.Visible = false

	local header = Kit.line(rewardsPage, {
		name = "Streak",
		anchor = Vector2.new(0.5, 0.5),
		position = UDim2.new(0.5, 0, 0, L.HeaderH / 2),
		height = L.HeaderH,
	})
	header.holder.ZIndex = 4

	-- Dzień: kafelek z paskiem „DAY n”, grafiką, napisem i znaczkiem odebranego.
	local tiles = {}
	for i, reward in ipairs(Economy.Rewards.DailyStreak) do
		local holder = Kit.new("Frame", {
			Name = "Day" .. i,
			Position = UDim2.fromOffset((i - 1) * (L.Tile.X + L.TileGap), L.RowY),
			Size = UDim2.fromOffset(L.Tile.X, L.Tile.Y),
			BackgroundTransparency = 1,
			ZIndex = 4,
			Parent = rewardsPage,
		})
		local inner = Kit.new("Frame", {
			Name = "Inner",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Theme.White,
			BorderSizePixel = 0,
			ZIndex = 4,
			Parent = holder,
		})
		local scale = Kit.new("UIScale", { Parent = inner })
		Kit.corner(inner, 18)
		local stroke = Kit.stroke(inner, 3.5, Enum.ApplyStrokeMode.Border)
		local background = Kit.gradient(inner, TILE_BG.Normal, 90)
		local band = Kit.new("Frame", {
			Name = "Band",
			Size = UDim2.new(1, 0, 0, L.Band),
			BackgroundColor3 = Theme.White,
			BorderSizePixel = 0,
			ZIndex = 5,
			Parent = inner,
		})
		Kit.corner(band, 18)
		local bandColor = Kit.gradient(band, COLORS.Normal, 90)
		-- dolne rogi paska proste (zaokrąglone są tylko górne, jak róg kafelka)
		local filler = Kit.new("Frame", {
			Position = UDim2.new(0, 0, 1, -16),
			Size = UDim2.new(1, 0, 0, 16),
			BackgroundColor3 = Theme.White,
			BorderSizePixel = 0,
			ZIndex = 5,
			Parent = band,
		})
		local fillerColor = Kit.gradient(filler, COLORS.Normal, 90)
		Kit.text(band, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, 1),
			Size = UDim2.new(1, -10, 0, 26),
			Text = string.format(TEXT.Day, i),
			ZIndex = 7,
		}, { maxSize = 22, stroke = 3 })
		local main = artFor(reward.Items[1])
		local art = ShopArt.make(main, 76, inner, { Position = UDim2.new(0.5, 0, 0, L.Band + 44), ZIndex = 6 })
		if reward.Items[2] ~= nil then
			local _, second = artFor(reward.Items[2])
			Icons.make(second, {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, 32, 0, L.Band + 68),
				Size = UDim2.fromOffset(34, 34),
				ZIndex = 8,
				Parent = inner,
			})
		end
		Kit.text(inner, {
			Name = "Reward",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -6),
			Size = UDim2.new(1, -10, 0, 44),
			Text = rewardText(reward),
			TextColor3 = Theme.Dark,
			TextWrapped = true,
			ZIndex = 7,
		}, { maxSize = 18, stroke = 0 })
		local check = Icons.make("Check", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0, L.Band + 44),
			Size = UDim2.fromOffset(60, 60),
			Visible = false,
			ZIndex = 9,
			Parent = inner,
		})
		local checkScale = Kit.new("UIScale", { Parent = check })
		tiles[i] = {
			scale = scale,
			stroke = stroke,
			background = background,
			bandColor = bandColor,
			fillerColor = fillerColor,
			art = art,
			check = check,
			checkScale = checkScale,
			big = i == DAYS,
		}
	end

	local claimButton = Kit.button(rewardsPage, {
		name = "Claim",
		size = L.Button,
		text = "",
		colors = Theme.Gradients.Green,
		anchor = Vector2.new(0.5, 0),
		position = UDim2.new(0.5, 0, 0, L.ButtonY),
		textSize = 30,
	})
	claimButton.holder.ZIndex = 4
	Kit.text(rewardsPage, {
		Name = "Note",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, L.NoteY),
		Size = UDim2.new(1, 0, 0, 24),
		Text = TEXT.Note,
		TextColor3 = Theme.Muted,
		ZIndex = 4,
	}, { maxSize = 19, stroke = 0 })

	------------------------------------------------------------- Zakładki REWARDS i QUESTS
	-- Jak zakładki sklepu: aktywna w swoim kolorze, druga biała; kropka „!”, gdy jest co odebrać.
	local TABS = {
		{ key = "Rewards", text = TEXT.TabRewards, icon = "Gift", colors = Theme.Gradients.Gold, title = TEXT.Title, page = rewardsPage },
		{ key = "Quests", text = TEXT.TabQuests, icon = "Quest", colors = Theme.Gradients.Cyan, title = TEXT.QuestsTitle, page = questsPage },
	}
	for i, tab in ipairs(TABS) do
		local offset = (i - (#TABS + 1) / 2) * (L.Tab.X + L.TabGap)
		tab.button = Kit.button(window.content, {
			name = "Tab" .. tab.key,
			size = L.Tab,
			colors = Theme.Gradients.Tab,
			radius = 20,
			edge = 6,
			anchor = Vector2.new(0.5, 0),
			position = UDim2.new(0.5, offset, 0, 0),
		})
		tab.button.holder.ZIndex = 5
		Icons.make(tab.icon, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0, 34, 0.5, 0),
			Size = UDim2.fromOffset(40, 40),
			ZIndex = 5,
			Parent = tab.button.face,
		})
		Kit.text(tab.button.face, {
			Name = "Label",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 62, 0.5, 1),
			Size = UDim2.new(1, -74, 0, 32),
			Text = tab.text,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 6,
		}, { maxSize = 26, stroke = 3.5 })
		tab.badge = Kit.badge(tab.button.body, { Position = UDim2.new(1, -6, 0, 4) })
	end

	-- treść zakładki QUESTS (karty zadań, komplet, czas do nowych zadań)
	local quests = Quests.create(hud, questsPage, {
		width = L.RowW,
		artFor = artFor,
		itemText = itemText,
		close = function()
			window.hide()
		end,
	})

	------------------------------------------------------------- Stan i rysowanie
	local activeTab = "Rewards"
	local secondsLeft, receivedAt = 0, os.clock()
	local pulse = nil
	local pulseDay = nil
	local claiming = false
	local waitView = false -- po odbiorze: przycisk czeka na nowy stan z serwera (bez mignięcia CLAIM)

	local function timeLeft()
		return math.max(0, secondsLeft - (os.clock() - receivedAt))
	end

	local function setPulse(day)
		if pulseDay == day then
			return
		end
		if pulse ~= nil then
			pulse:Cancel()
			pulse = nil
		end
		if pulseDay ~= nil and tiles[pulseDay] ~= nil then
			tiles[pulseDay].scale.Scale = 1
		end
		pulseDay = day
		if day ~= nil and tiles[day] ~= nil then
			tiles[day].scale.Scale = 1
			pulse = TweenService:Create(tiles[day].scale, TweenInfo.new(0.55, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = 1.07 })
			pulse:Play()
		end
	end

	local function setTile(tile, kind)
		local band = COLORS[kind] or COLORS.Normal
		if kind == "Normal" and tile.big then
			band = COLORS.Big
		end
		tile.bandColor.Color = ColorSequence.new(band[1], band[2])
		tile.fillerColor.Color = ColorSequence.new(band[2], band[2])
		local bg = TILE_BG[kind] or TILE_BG.Normal
		tile.background.Color = ColorSequence.new(bg[1], bg[2])
		tile.stroke.Thickness = (kind == "Today" and 5) or 3.5
		tile.stroke.Color = (kind == "Today" and Color3.fromRGB(120, 60, 0)) or Theme.Outline
		tile.check.Visible = kind == "Done"
	end

	local function updateButton(daily)
		if daily == nil then
			claimButton.setText("...")
			claimButton.setColors(Theme.Gradients.Gray)
		elseif daily.CanClaim then
			claimButton.setText(string.format(TEXT.Claim, daily.Day or 1))
			claimButton.setColors(Theme.Gradients.Green)
		elseif timeLeft() <= 0 then
			claimButton.setText(TEXT.NewDay)
			claimButton.setColors(Theme.Gradients.Gray)
		else
			claimButton.setText(string.format(TEXT.Next, clock(timeLeft())))
			claimButton.setColors(Theme.Gradients.Gray)
		end
	end

	local renderedKey = nil
	local function render(force)
		local daily = (State.view or {}).Daily
		if daily == nil then
			updateButton(nil)
			return
		end
		updateButton(daily)
		-- stan przychodzi często (np. z Auto-Click), a dni zmieniają się rzadko
		local key = table.concat({ tostring(daily.Day), tostring(daily.CanClaim), tostring(daily.Streak), tostring(daily.Lost) }, "|")
		if key == renderedKey and not force then
			return
		end
		renderedKey = key
		local day = daily.Day or 1
		for i, tile in ipairs(tiles) do
			local kind = "Normal"
			if i < day or (i == day and not daily.CanClaim) then
				kind = "Done"
			elseif i == day then
				kind = "Today"
			end
			setTile(tile, kind)
		end
		if daily.CanClaim and window.isOpen() and activeTab == "Rewards" then
			setPulse(day)
		else
			setPulse(nil)
		end
		local streak = daily.Streak or 0
		if daily.Lost then
			header.set({ { icon = "Trophy", size = 34 }, { text = TEXT.StreakLost, size = 26, colors = Theme.Gradients.Red } })
		elseif streak <= 0 then
			header.set({ { icon = "Trophy", size = 34 }, { text = TEXT.StreakNew, size = 26, colors = Theme.Gradients.Gold } })
		elseif streak == 1 then
			header.set({ { icon = "Trophy", size = 34 }, { text = TEXT.StreakOne, size = 28, colors = Theme.Gradients.Gold } })
		else
			header.set({ { icon = "Trophy", size = 34 }, { text = string.format(TEXT.Streak, streak), size = 28, colors = Theme.Gradients.Gold } })
		end
	end

	-- kropki „!” na zakładkach: nagroda dzienna do odebrania i zadania czekające na CLAIM
	local function updateBadges()
		local view = State.view or {}
		local daily = view.Daily
		TABS[1].badge.set((daily ~= nil and daily.CanClaim and "!") or nil)
		TABS[2].badge.set((Quests.claimable(view) > 0 and "!") or nil)
	end

	local function setTab(key)
		activeTab = key
		for _, tab in ipairs(TABS) do
			local on = tab.key == key
			tab.page.Visible = on
			if on then
				tab.button.setColors(tab.colors)
				window.title.Text = tab.title
			else
				tab.button.setColors(Theme.Gradients.Tab)
			end
		end
		render(true)
		quests.setActive(key == "Quests" and window.isOpen())
		updateBadges()
	end
	for _, tab in ipairs(TABS) do
		tab.button.Activated:Connect(function()
			if activeTab ~= tab.key then
				setTab(tab.key)
			end
		end)
	end

	-- animacje grafik i pulsowanie dzisiejszego dnia tylko przy otwartym oknie (sprząta Heartbeat).
	-- tab = "Rewards" albo "Quests"; bez niego REWARDS, gdy nagroda czeka, inaczej QUESTS.
	local bin = nil
	local function openWindow(tab)
		if State.busy then
			return
		end
		if tab == nil then
			local daily = (State.view or {}).Daily
			tab = (daily ~= nil and daily.CanClaim and "Rewards") or "Quests"
		end
		hud.openWindow(window)
		if bin ~= nil then
			bin.clean()
		end
		bin = Fx.bin()
		for _, tile in ipairs(tiles) do
			tile.art.play(bin)
		end
		quests.play(bin)
		setTab(tab)
	end
	Daily.open = openWindow
	-- Przycisk REWARDS i nagłówek listy zadań na ekranie (QuestTracker): otwiera albo zamyka okno.
	function Daily.toggle(tab)
		if window.isOpen() then
			window.hide()
		else
			openWindow(tab)
		end
	end

	-- odbiór: znaczek „wbija się” w kafelek, a komunikat o nagrodzie jest jeden, na dole ekranu
	local function stamp(day)
		local tile = tiles[day]
		if tile == nil then
			return
		end
		setPulse(nil)
		setTile(tile, "Done")
		tile.checkScale.Scale = 2.2
		TweenService:Create(tile.checkScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		tile.scale.Scale = 1.15
		TweenService:Create(tile.scale, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end

	local function claim()
		local daily = (State.view or {}).Daily
		if claiming or daily == nil then
			return
		end
		if not daily.CanClaim then
			Sounds.play("NotEnough")
			Kit.shake(claimButton.body)
			return
		end
		claiming = true
		claimButton.setText("...")
		local ok, result = pcall(function()
			return Net.func("ClaimDaily"):InvokeServer()
		end)
		claiming = false
		if not ok or type(result) ~= "table" then
			render(true)
			return
		end
		if result.Ok then
			Sounds.play("Unlock", { volume = 0.8 })
			local items = { { icon = "Gift", size = 36 }, { text = string.format(TEXT.ClaimedToast, result.Day or 1), size = 26, colors = Theme.Gradients.Gold } }
			for _, item in ipairs(Codes.rewardItems(result)) do
				table.insert(items, item)
			end
			hud.toast(items)
			stamp(result.Day)
			claimButton.setText(TEXT.ClaimedButton)
			claimButton.setColors(Theme.Gradients.Gray)
			-- nowy stan mógł przyjść przed odpowiedzią (wtedy od razu odliczanie), inaczej czekamy na niego
			local now = (State.view or {}).Daily
			waitView = now == nil or now.CanClaim == true
			if not waitView then
				task.delay(0.8, function()
					if not claiming and not waitView then
						render(true)
					end
				end)
			end
			if (result.Pets or 0) > 0 or (result.Items or 0) > 0 then
				-- jajka i boxy otwierają się na całym ekranie (Eggs.luau, Boxes.luau)
				window.hide()
			end
			return
		end
		Sounds.play("NotEnough")
		hud.toast({ { text = TEXT[result.Reason] or TEXT.Error, size = 26, colors = Theme.Gradients.Red } }, "DailyError")
		Kit.shake(claimButton.body)
		render(true)
	end
	claimButton.Activated:Connect(claim)

	------------------------------------------------------------- Tablica w Downtown
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
		entry.gui.Enabled = part ~= nil and State.view ~= nil and not State.busy
	end

	local function makeLabel(stand)
		local gui = Kit.new("BillboardGui", {
			Name = "DailyLabel",
			LightInfluence = 0,
			AlwaysOnTop = true,
			MaxDistance = LABEL_DISTANCE,
			ResetOnSpawn = false,
			Enabled = false,
			Parent = playerGui,
		})
		local frame = Kit.worldFrame(gui, LABEL_DESIGN, LABEL_PIXELS_PER_STUD)
		Kit.line(frame, {
			anchor = Vector2.new(0.5, 0.5),
			position = UDim2.fromScale(0.5, 0.5),
			height = 50,
			items = {
				{ icon = "Gift", size = 40 },
				{ text = TEXT.Label, size = 32, colors = Theme.Gradients.Gold },
			},
		})
		labels[stand] = { gui = gui }
		updateLabel(stand)
	end

	local promptGui = Kit.new("BillboardGui", {
		Name = "DailyPrompt",
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

	promptButton.Activated:Connect(function()
		Sounds.play("Button")
		openWindow()
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or input.KeyCode ~= Enum.KeyCode.E then
			return
		end
		-- E zamyka okno tylko przy tablicy (otwarte samo po wejściu zamyka X)
		if window.isOpen() and current ~= nil then
			window.hide()
		elseif promptGui.Enabled then
			Sounds.play("Button")
			openWindow()
		end
	end)

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
	local buttonTimer = 0
	RunService.Heartbeat:Connect(function(dt)
		timer = timer + dt
		buttonTimer = buttonTimer + dt
		if window.isOpen() and buttonTimer >= 0.5 then
			buttonTimer = 0
			if not claiming and not waitView then
				updateButton((State.view or {}).Daily)
			end
			if activeTab == "Quests" then
				quests.tick()
			end
		end
		if not window.isOpen() and bin ~= nil then
			bin.clean()
			bin = nil
			setPulse(nil)
			quests.play(nil)
			quests.setActive(false)
		end
		if timer < 0.1 then
			return
		end
		timer = 0
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root == nil or State.view == nil or State.busy then
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
					local part = StandAnchor.get(best)
					promptGui.Adornee = part
					promptGui.StudsOffsetWorldSpace = Vector3.new(0, 0.4, 0)
				end
			end
		end
		promptGui.Enabled = current ~= nil and not window.isOpen() and not hud.windowOpen()
	end)

	------------------------------------------------------------- Stan od serwera
	local autoShown = false
	local lastBusy = nil
	State.onChange(function(view)
		local daily = view.Daily
		if daily ~= nil then
			secondsLeft = daily.SecondsLeft or 0
			receivedAt = os.clock()
			if not daily.CanClaim then
				waitView = false
			end
		end
		if State.busy ~= lastBusy then
			lastBusy = State.busy
			for stand in pairs(labels) do
				updateLabel(stand)
			end
		end
		if window.isOpen() and not claiming and not waitView then
			render(false)
		end
		if window.isOpen() then
			quests.render(false)
		end
		updateBadges()
		-- raz po wejściu: okno samo, gdy jest co odebrać i gracz niczego nie robi
		if not autoShown and daily ~= nil then
			autoShown = true
			if daily.CanClaim then
				task.spawn(function()
					task.wait(AUTO_OPEN_DELAY)
					local waited = 0
					while (State.busy or hud.windowOpen()) and waited < AUTO_OPEN_WAIT do
						task.wait(1)
						waited = waited + 1
					end
					local now = (State.view or {}).Daily
					if now ~= nil and now.CanClaim and not State.busy and not hud.windowOpen() then
						openWindow()
					end
				end)
			end
		end
	end)

	State.onNotify(function(payload)
		if payload.Kind == "DailyReady" then
			-- Daily = false: nagroda dzienna już odebrana dziś (np. tuż przed północą), są tylko nowe zadania
			Sounds.play("Unlock", { volume = 0.5 })
			local text = TEXT.Ready
			local icon = "Gift"
			if payload.Daily == false then
				text = TEXT.ReadyQuests
				icon = "Quest"
			end
			hud.toast({ { icon = icon, size = 40 }, { text = text, size = 26, colors = Theme.Gradients.Gold } }, "DailyReady")
		end
	end)

	for _, stand in ipairs(CollectionService:GetTagged(STAND_TAG)) do
		onStandAdded(stand)
	end
	CollectionService:GetInstanceAddedSignal(STAND_TAG):Connect(onStandAdded)
	CollectionService:GetInstanceRemovedSignal(STAND_TAG):Connect(onStandRemoved)
end

return Daily
