-- Aktywności po stronie gracza (strefy 2–5): zdjęcia z autem, wywiad w telewizji, impreza na jachcie
-- i lot odrzutowcem. Na miejscu gracz widzi tylko model ze swojego tieru (Car1 … Car5, Yacht1 … Yacht5,
-- Jet1 … Jet3; inne są u niego niewidoczne). Nad miejscem wisi tablica, a przy nim otwiera się okno:
-- start sesji, nagroda i kupno lepszego modelu (przy wywiadzie szanse ocen).
-- Sesja: zaciemnienie z napisem, kamera (krąży wokół auta i jachtu, przełącza ujęcia w studiu albo
-- leci za samolotem), efekty (flesze ze zdjęciami, muzyka, światła imprezy i konfetti, pytania
-- i odpowiedzi w wywiadzie z czatem i licznikiem wyświetleń, start i lot wśród chmur), pasek czasu,
-- inni gracze i tablice są ukryci, kliknięcia nie działają, a na końcu jest nagroda (przy wywiadzie
-- najpierw ocena). Start i nagrodę sprawdza serwer (ActivityService), a program wywiadu prowadzi
-- InterviewShow.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared.Config.Economy)
local Format = require(Shared.Format)
local Net = require(Shared.Net)
local Stand = require(Shared.Stand)
local State = require(script.Parent.State)
local Theme = require(script.Parent.Ui.Theme)
local Kit = require(script.Parent.Ui.Kit)
local Sounds = require(script.Parent.Ui.Sounds)
local LocalHide = require(script.Parent.LocalHide)
local InterviewShow = require(script.Parent.InterviewShow)

local Activities = {}

local SPOT_TAG = "LarpActivity" -- ten sam tag co ActivityService.SpotTag na serwerze
local OPEN_DISTANCE = 5.5 -- okno otwiera się, gdy stoisz przy modelu albo przy miejscu Pose
local CLOSE_DISTANCE = 10 -- tak daleko okno się zamyka
local FLASH_EVERY = 1.6 -- co tyle sekund błyska flesz (zdjęcia)
local PARTY_EVERY = 0.9 -- co tyle sekund zmienia się kolor świateł (jacht)
local SHOT_SECONDS = 4.2 -- przez tyle sekund kamera w studiu powoli się zbliża (wywiad)
local PARTY_PHOTO_GAP = { 2, 3.6 } -- odstęp między zdjęciami na imprezie (s, losowy)
local YACHT_SHOT = 3.8 -- tyle trwa jedno ujęcie na jachcie (potem przebitka)
local JET_RUNWAY_PHOTOS = { 2.2, 3.6, 4.8, 5.9, 6.9, 7.8 } -- zdjęcia, gdy samolot rusza i startuje (s)
local JET_FLIGHT_PHOTO_GAP = { 3.6, 5.8 } -- zdjęcia w locie (s, losowo)
local JET_CRUISE = 140 -- wysokość lotu nad pasem (studs)

-- Chmury w locie (tylko u gracza), w trzech warstwach wokół trasy: pod samolotem, po bokach na
-- wysokości lotu i kilka na samej trasie (samolot przez nie przelatuje). Liczby w studs:
-- puffs = ile kul w chmurze, width/height = wielkość kuli, spread = jak szeroko leżą kule,
-- lateral = odległość w bok od trasy, altitude = wysokość względem wysokości lotu, from = najbliżej
-- przed samolotem na starcie.
local CLOUD_KINDS = {
	{ count = 26, puffs = { 5, 8 }, width = { 34, 64 }, height = { 12, 20 }, spread = 46, lateral = { 0, 380 }, altitude = { -85, -45 }, from = 520 },
	{ count = 32, puffs = { 3, 6 }, width = { 18, 36 }, height = { 12, 22 }, spread = 22, lateral = { 70, 280 }, altitude = { -25, 35 }, from = 260 },
	{ count = 5, puffs = { 3, 5 }, width = { 22, 34 }, height = { 14, 22 }, spread = 14, lateral = { 0, 30 }, altitude = { -8, 12 }, from = 420, path = true },
}
local CLOUD_AHEAD = 1700 -- na starcie chmury stoją najdalej tyle przed samolotem
local CLOUD_RESPAWN = { 1250, 1700 } -- chmura, która została za samolotem, przeskakuje tak daleko do przodu
local CLOUD_BEHIND = 220 -- tak daleko za samolotem chmura przeskakuje do przodu
local CLOUD_WIDE = 470 -- tak daleko w bok (np. po zakręcie) też przeskakuje do przodu

local TEXT = {
	Reward = "Reward:",
	Start = "START",
	Upgrade = "UPGRADE",
	Buy = "BUY",
	Maxed = "MAXED",
	Next = "Next:",
	BagFull = "Bag full! Sell first",
	BagLimit = "(Bag limit)", -- nagroda większa niż wolne miejsce w Bag
	Views = "views",
	LiveIn = "LIVE IN %d",
	OnAir = "ON AIR",
	FirstFrom = "First one: %s L$",
}

-- Wygląd i napisy każdej aktywności (napisy w grze po angielsku). names = modele z tierów z arkusza;
-- zmień je tu, gdy wybierzesz prawdziwe auta, jachty i odrzutowce.
local KINDS = {
	Car = {
		prefix = "Car",
		title = "Car Photoshoot",
		sign = "CAR PHOTOSHOOT",
		per = "per photoshoot",
		names = { "Rental Compact", "German Sedan", "Muscle Car", "Italian Supercar", "Hypercar" },
		busy = "PHOTOSHOOT",
		boarding = "Getting ready...",
		done = "Photoshoot done!",
		newItem = "New car:",
		best = "Best car unlocked!",
		tooFar = "Get closer to the car",
		emote = "wave",
		signHeight = 13,
	},
	Interview = {
		title = "Celebrity Interview",
		sign = "LIVE INTERVIEW",
		per = "per interview",
		about = "Answer questions live on TV",
		busy = "LIVE INTERVIEW",
		done = "Interview done!",
		tooFar = "Get closer to the studio",
		emote = "wave",
		signHeight = 15,
	},
	Yacht = {
		prefix = "Yacht",
		title = "Yacht Party",
		sign = "YACHT PARTY",
		per = "per party",
		names = { "Small Motorboat", "Motor Yacht", "Large Yacht", "Superyacht", "Mega Yacht" },
		busy = "YACHT PARTY",
		boarding = "Boarding the yacht...",
		done = "Yacht party done!",
		newItem = "New yacht:",
		best = "Best yacht unlocked!",
		tooFar = "Get closer to the yacht",
		emote = "dance",
		signHeight = 16,
	},
	Jet = {
		prefix = "Jet",
		title = "Private Jet",
		sign = "PRIVATE JET",
		per = "per flight",
		names = { "Light Jet", "Midsize Jet", "Ultra Long Range" },
		busy = "IN FLIGHT",
		boarding = "Boarding your jet...",
		done = "Flight landed!",
		newItem = "New jet:",
		best = "Best jet unlocked!",
		noItem = "No jet yet",
		buyFirst = "Buy a jet first!",
		tooFar = "Get closer to the jet",
		signHeight = 14,
		hidePlayer = true, -- gracz siedzi w samolocie
	},
}

-- Oceny wywiadu (kolejność jak w arkuszu: Flop, Solid, Viral, Mega viral).
local GRADES = {
	{ text = "FLOP", colors = Theme.Gradients.Gray, tint = Color3.fromRGB(201, 198, 211), views = 3000 },
	{ text = "SOLID", colors = Theme.Gradients.Green, tint = Color3.fromRGB(134, 232, 62), views = 45000 },
	{ text = "VIRAL!", colors = Theme.Gradients.Cyan, tint = Color3.fromRGB(79, 211, 255), views = 650000 },
	{ text = "MEGA VIRAL!", colors = Theme.Gradients.Gold, tint = Color3.fromRGB(255, 200, 40), views = 4800000 },
}

local PARTY_COLORS = {
	Color3.fromRGB(255, 79, 163),
	Color3.fromRGB(56, 217, 255),
	Color3.fromRGB(176, 96, 255),
	Color3.fromRGB(255, 214, 61),
}

local tiers = {} -- [rodzaj] = tier gracza (ze stanu od serwera)

local function shownTier(kind)
	return math.max(1, tiers[kind] or 1) -- bez odrzutowca widać pierwszy (do kupienia)
end

local function itemName(kind, tier)
	local names = KINDS[kind].names
	return (names and names[tier]) or (kind .. " " .. tier)
end

local function itemMultiplier(kind, tier)
	local list = Economy.Activities[kind].Tiers
	local info = list and list[tier]
	return "×" .. Format.small((info and info.Multiplier) or 0)
end

local function pivotOf(spot)
	if spot:IsA("Model") then
		return spot:GetPivot()
	end
	return spot.CFrame
end

local function smooth(x)
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

local function between(range)
	return range[1] + math.random() * (range[2] - range[1])
end

----------------------------------------------------------------- Modele według tieru
-- Numer modelu, do którego należy część (przodek „Car3”, „Yacht2” …), albo nil.
local function itemNumber(part, spot, prefix)
	if prefix == nil then
		return nil
	end
	local node = part
	while node ~= nil and node ~= spot do
		local n = tonumber(string.match(node.Name, "^" .. prefix .. "(%d+)$"))
		if n ~= nil then
			return n
		end
		node = node.Parent
	end
	return nil
end

local function itemModel(spot, kind, tier)
	local prefix = KINDS[kind].prefix
	if prefix == nil then
		return nil
	end
	local model = spot:FindFirstChild(prefix .. tostring(tier), true)
	if model ~= nil and model:IsA("Model") then
		return model
	end
	return nil
end

local function applyItems(spot)
	local kind = spot:GetAttribute("Activity")
	local cfg = KINDS[kind]
	if cfg == nil or cfg.prefix == nil then
		return
	end
	local show = shownTier(kind)
	for _, d in ipairs(spot:GetDescendants()) do
		if d:IsA("BasePart") then
			local n = itemNumber(d, spot, cfg.prefix)
			if n ~= nil then
				LocalHide.set(d, n ~= show)
			end
		end
	end
end

-- Część „Pose” miejsca (nie z modelu tieru), np. gość w studiu.
local function spotPose(spot, kind)
	local prefix = KINDS[kind].prefix
	for _, d in ipairs(spot:GetDescendants()) do
		if d.Name == "Pose" and d:IsA("BasePart") and itemNumber(d, spot, prefix) == nil then
			return d
		end
	end
	return nil
end

local function distanceToBox(part, position)
	local p = part.CFrame:PointToObjectSpace(position)
	local half = part.Size / 2
	local dx = math.max(math.abs(p.X) - half.X, 0)
	local dy = math.max(math.abs(p.Y) - half.Y, 0)
	local dz = math.max(math.abs(p.Z) - half.Z, 0)
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- Odległość do widocznego modelu z tieru albo do Pose (bliższe z nich). Gdy nie ma żadnego
-- (np. jeszcze się nie wczytały), liczy się całe miejsce.
local function distanceToSpot(spot, position)
	local kind = spot:GetAttribute("Activity")
	local prefix = KINDS[kind] and KINDS[kind].prefix
	local parts = { spot }
	if not spot:IsA("BasePart") then
		parts = spot:GetDescendants()
	end
	local show = shownTier(kind)
	local near, any = math.huge, math.huge
	for _, part in ipairs(parts) do
		if part:IsA("BasePart") then
			local d = distanceToBox(part, position)
			local n = itemNumber(part, spot, prefix)
			if n == show or (n == nil and part.Name == "Pose") then
				near = math.min(near, d)
			end
			if n == nil then
				any = math.min(any, d)
			end
		end
	end
	if near < math.huge then
		return near
	end
	return any
end

----------------------------------------------------------------- Start
function Activities.start(hud)
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	local spots = {} -- lista miejsc (Model albo część z tagiem i atrybutem Activity)

	local function zoneUnlocked(kind)
		local view = State.view
		return view ~= nil and (view.ZonesUnlocked or 1) >= Economy.Activities[kind].Zone
	end

	------------------------------------------------------------- Tablice nad miejscami
	local signs = {} -- [miejsce] = { gui, reward }
	local signsHidden = false -- w czasie sesji tablice znikają (nachodziłyby na napisy sesji)
	-- Tablica wisi nad częścią „SignAnchor” (gdy jest), a bez niej nad największą częścią miejsca.
	local function biggestPart(spot)
		if spot:IsA("BasePart") then
			return spot
		end
		local anchor = spot:FindFirstChild("SignAnchor", true)
		if anchor ~= nil and anchor:IsA("BasePart") then
			return anchor
		end
		local kind = spot:GetAttribute("Activity")
		local prefix = KINDS[kind] and KINDS[kind].prefix
		local best, bestSize = nil, -1
		for _, d in ipairs(spot:GetDescendants()) do
			if d:IsA("BasePart") and itemNumber(d, spot, prefix) == nil then
				local size = d.Size.X * d.Size.Z
				if size > bestSize then
					best, bestSize = d, size
				end
			end
		end
		return best
	end

	local function signText(kind, info)
		local cfg = KINDS[kind]
		if info == nil then
			return ""
		end
		if info.MinReward ~= nil then
			return "+" .. Format.number(info.MinReward) .. "–" .. Format.number(info.MaxReward) .. " LP " .. cfg.per
		end
		if (info.Tier or 0) < 1 then
			if info.NextCost ~= nil then
				return string.format(TEXT.FirstFrom, Format.number(info.NextCost))
			end
			return cfg.noItem or ""
		end
		return "+" .. Format.number(info.Reward) .. " LP " .. cfg.per
	end

	local function updateSign(spot)
		local sign = signs[spot]
		if sign == nil then
			return
		end
		local kind = spot:GetAttribute("Activity")
		local view = State.view
		local adornee = biggestPart(spot)
		sign.gui.Adornee = adornee
		sign.gui.Enabled = adornee ~= nil and zoneUnlocked(kind) and not signsHidden
		local info = view and view.Activities and view.Activities[kind]
		sign.reward.Text = signText(kind, info)
	end

	local function setSignsHidden(hidden)
		signsHidden = hidden
		for spot in pairs(signs) do
			updateSign(spot)
		end
	end

	local function makeSign(spot)
		local kind = spot:GetAttribute("Activity")
		local cfg = KINDS[kind]
		local gui = Kit.new("BillboardGui", {
			Name = "ActivitySign",
			Size = UDim2.fromScale(18, 5),
			StudsOffsetWorldSpace = Vector3.new(0, cfg.signHeight or 13, 0),
			LightInfluence = 0,
			MaxDistance = 160,
			ResetOnSpawn = false,
			Enabled = false,
			Parent = playerGui,
		})
		Kit.text(gui, { Size = UDim2.fromScale(1, 0.6), Text = cfg.sign }, { maxSize = 100, stroke = 3.5 })
		local reward = Kit.text(gui, {
			Position = UDim2.fromScale(0, 0.6),
			Size = UDim2.fromScale(1, 0.4),
			Text = "",
		}, { maxSize = 60, stroke = 3, gradient = Theme.Gradients.LP })
		signs[spot] = { gui = gui, reward = reward }
		updateSign(spot)
	end

	local function onSpotAdded(spot)
		if KINDS[spot:GetAttribute("Activity")] == nil then
			return
		end
		for _, existing in ipairs(spots) do
			if existing == spot then
				return
			end
		end
		table.insert(spots, spot)
		applyItems(spot)
		makeSign(spot)
		-- przy StreamingEnabled części modeli mogą dojść później
		spot.DescendantAdded:Connect(function(d)
			if d:IsA("BasePart") then
				applyItems(spot)
				updateSign(spot)
			end
		end)
	end

	local function onSpotRemoved(spot)
		for i = #spots, 1, -1 do
			if spots[i] == spot then
				table.remove(spots, i)
			end
		end
		local sign = signs[spot]
		if sign ~= nil then
			sign.gui:Destroy()
			signs[spot] = nil
		end
	end

	-- Najbliższe miejsce (wszystkie rodzaje albo tylko jeden) w odblokowanej strefie.
	local function nearestSpot(position, onlyKind)
		local best, bestDistance = nil, math.huge
		for _, spot in ipairs(spots) do
			local kind = spot:GetAttribute("Activity")
			if spot.Parent ~= nil and (onlyKind == nil or kind == onlyKind) and zoneUnlocked(kind) then
				local d = distanceToSpot(spot, position)
				if d < bestDistance then
					best, bestDistance = spot, d
				end
			end
		end
		return best, bestDistance
	end

	------------------------------------------------------------- Okno przy miejscu
	local popup = Kit.panel(hud.gui, {
		name = "ActivityPanel",
		size = Vector2.new(560, 380),
		title = "",
		padding = 30,
		top = 52,
		bottom = 26,
	})
	hud.registerScale(popup.holder)
	hud.addPopup(popup)
	local content = popup.content
	local itemLine = Kit.line(content, { anchor = Vector2.new(0.5, 0), position = UDim2.new(0.5, 0, 0, 0), height = 46 })
	local rewardLine = Kit.line(content, { anchor = Vector2.new(0.5, 0), position = UDim2.new(0.5, 0, 0, 46), height = 42 })
	local startButton = Kit.button(content, {
		name = "Start",
		size = Vector2.new(220, 60),
		text = TEXT.Start,
		colors = Theme.Gradients.Green,
		anchor = Vector2.new(0.5, 0),
		position = UDim2.new(0.5, 0, 0, 96),
		textSize = 30,
	})
	Kit.new("Frame", {
		Name = "Divider",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 176),
		Size = UDim2.new(1, -40, 0, 4),
		BackgroundColor3 = Theme.PatternColor,
		BorderSizePixel = 0,
		Parent = content,
	})
	local nextLine = Kit.line(content, { anchor = Vector2.new(0.5, 0), position = UDim2.new(0.5, 0, 0, 186), height = 40 })
	local priceLine = Kit.line(content, { anchor = Vector2.new(1, 0), position = UDim2.new(0.5, -12, 0, 234), height = 54 })
	local upgradeButton = Kit.button(content, {
		name = "Upgrade",
		size = Vector2.new(170, 54),
		text = TEXT.Upgrade,
		colors = Theme.Gradients.Yellow,
		anchor = Vector2.new(0, 0),
		position = UDim2.new(0.5, 12, 0, 233),
		textSize = 26,
	})
	-- szanse ocen wywiadu (zamiast ulepszeń)
	local gradesRow = Kit.new("Frame", {
		Name = "Grades",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 194),
		Size = UDim2.new(1, 0, 0, 96),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = content,
	})
	Kit.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = gradesRow,
	})
	for i, grade in ipairs(Economy.Activities.Interview.Grades) do
		local style = GRADES[i] or GRADES[#GRADES]
		local chip = Kit.new("Frame", {
			Name = grade.Name,
			LayoutOrder = i,
			Size = UDim2.fromOffset(112, 92),
			BackgroundColor3 = style.tint:Lerp(Theme.White, 0.55),
			BorderSizePixel = 0,
			Parent = gradesRow,
		})
		Kit.corner(chip, 16)
		Kit.stroke(chip, 3, Enum.ApplyStrokeMode.Border)
		Kit.text(chip, { Position = UDim2.fromOffset(4, 4), Size = UDim2.new(1, -8, 0, 30), Text = string.upper(grade.Name) }, {
			maxSize = 20,
			stroke = 2.5,
			gradient = style.colors,
		})
		Kit.text(chip, { Position = UDim2.fromOffset(4, 34), Size = UDim2.new(1, -8, 0, 28), Text = "×" .. Format.small(grade.Multiplier) }, {
			maxSize = 24,
			stroke = 2.5,
			gradient = Theme.Gradients.Gold,
		})
		Kit.text(chip, { Position = UDim2.fromOffset(4, 62), Size = UDim2.new(1, -8, 0, 24), Text = Format.percent(grade.Chance) }, {
			maxSize = 20,
			stroke = 2.5,
		})
	end
	local current = nil -- { spot, kind }: miejsce, przy którym jest otwarte okno
	local dismissed = false

	local function renderPopup()
		local kind = current and current.kind
		local cfg = KINDS[kind]
		local view = State.view
		local info = view and view.Activities and view.Activities[kind]
		if cfg == nil or info == nil then
			return
		end
		popup.title.Text = cfg.title
		local tier = info.Tier or 0
		if cfg.prefix == nil then
			itemLine.set({ { text = cfg.about, size = 30 } })
		elseif tier < 1 then
			itemLine.set({ { text = cfg.noItem, size = 30 } })
		else
			itemLine.set({
				{ text = itemName(kind, tier), size = 32 },
				{ text = itemMultiplier(kind, tier), size = 32, colors = Theme.Gradients.Gold },
			})
		end
		-- nagroda, która zmieści się teraz w Bag (reszta by przepadła, więc pokazujemy limit)
		if tier < 1 then
			rewardLine.set({ { text = cfg.buyFirst, size = 26, colors = Theme.Gradients.Red } })
		elseif info.MinReward ~= nil then
			local items = {
				{ text = TEXT.Reward, size = 26 },
				{ text = "+" .. Format.number(info.MinReward) .. "–" .. Format.number(info.MaxReward) .. " LP", size = 28, colors = Theme.Gradients.LP },
			}
			if (info.RewardFits or info.MaxReward) < info.MaxReward then
				table.insert(items, { text = TEXT.BagLimit, size = 22, colors = Theme.Gradients.Red })
			end
			rewardLine.set(items)
		else
			local fits = info.RewardFits or info.Reward
			local items = {
				{ text = TEXT.Reward, size = 26 },
				{ text = "+" .. Format.number(fits) .. " LP", size = 28, colors = Theme.Gradients.LP },
			}
			if fits < info.Reward then
				table.insert(items, { text = TEXT.BagLimit, size = 22, colors = Theme.Gradients.Red })
			end
			rewardLine.set(items)
		end
		if view.BagFull or tier < 1 then
			startButton.setColors(Theme.Gradients.Gray)
		else
			startButton.setColors(Theme.Gradients.Green)
		end
		-- dół okna: ulepszenia (auto, jacht, odrzutowiec) albo szanse ocen (wywiad)
		local hasTiers = cfg.prefix ~= nil
		gradesRow.Visible = not hasTiers
		nextLine.holder.Visible = hasTiers
		upgradeButton.holder.Visible = hasTiers
		priceLine.holder.Visible = hasTiers
		if not hasTiers then
			return
		end
		if info.NextCost ~= nil then
			local nextTier = tier + 1
			nextLine.set({
				{ text = TEXT.Next, size = 26 },
				{ text = itemName(kind, nextTier), size = 26 },
				{ text = itemMultiplier(kind, nextTier), size = 26, colors = Theme.Gradients.Gold },
			})
			priceLine.set({
				{ icon = "Cash", size = 46 },
				{ text = Format.number(info.NextCost), size = 36, colors = Theme.Gradients.Gold },
			})
			upgradeButton.holder.AnchorPoint = Vector2.new(0, 0)
			upgradeButton.holder.Position = UDim2.new(0.5, 12, 0, 233)
			if tier < 1 then
				upgradeButton.setText(TEXT.Buy)
			else
				upgradeButton.setText(TEXT.Upgrade)
			end
			if view.Cash >= info.NextCost then
				upgradeButton.setColors(Theme.Gradients.Yellow)
			else
				upgradeButton.setColors(Theme.Gradients.Gray)
			end
		else
			-- najlepszy model: szary przycisk MAXED na środku, bez ceny
			nextLine.set({ { text = cfg.best, size = 28, colors = Theme.Gradients.Gold } })
			priceLine.holder.Visible = false
			upgradeButton.holder.AnchorPoint = Vector2.new(0.5, 0)
			upgradeButton.holder.Position = UDim2.new(0.5, 0, 0, 233)
			upgradeButton.setText(TEXT.Maxed)
			upgradeButton.setColors(Theme.Gradients.Gray)
		end
	end

	popup.close.Activated:Connect(function()
		dismissed = true
	end)

	local requesting = false
	startButton.Activated:Connect(function()
		if requesting or State.busy or current == nil then
			return
		end
		local kind = current.kind
		local cfg = KINDS[kind]
		requesting = true
		local ok, result = pcall(function()
			return Net.func("StartActivity"):InvokeServer(kind)
		end)
		requesting = false
		if not ok or type(result) ~= "table" then
			return
		end
		if result.Ok then
			popup.hide()
		elseif result.Reason == "BagFull" then
			Sounds.play("NotEnough")
			hud.toast({ { text = TEXT.BagFull, size = 26, colors = Theme.Gradients.Red } }, "ActivityBagFull")
			Kit.shake(startButton.holder)
		elseif result.Reason == "Tier" then
			Sounds.play("NotEnough")
			hud.toast({ { text = cfg.buyFirst or cfg.tooFar, size = 26, colors = Theme.Gradients.Red } }, "ActivityTier")
			Kit.shake(startButton.holder)
		elseif result.Reason == "TooFar" then
			hud.toast({ { text = cfg.tooFar, size = 26, colors = Theme.Gradients.Red } }, "ActivityTooFar")
		end
	end)

	upgradeButton.Activated:Connect(function()
		if requesting or current == nil then
			return
		end
		local kind = current.kind
		local view = State.view
		local info = view and view.Activities and view.Activities[kind]
		if info == nil or info.NextCost == nil then
			return -- MAXED: nie ma czego kupić
		end
		requesting = true
		local ok, result = pcall(function()
			return Net.func("BuyActivityTier"):InvokeServer(kind)
		end)
		requesting = false
		if not ok or type(result) ~= "table" then
			return
		end
		if result.Ok then
			Sounds.play("Unlock")
			hud.toast({
				{ text = KINDS[kind].newItem, size = 28 },
				{ text = itemName(kind, result.Tier), size = 30, colors = Theme.Gradients.Gold },
			})
		elseif result.Reason == "NotEnough" then
			hud.notEnough(upgradeButton)
		end
	end)

	------------------------------------------------------------- Ekran sesji
	local cinemaGui = Kit.new("ScreenGui", {
		Name = "LarpActivity",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 15,
		Parent = playerGui,
	})
	local blackout = Kit.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 2,
		Parent = cinemaGui,
	})
	local flashFrame = Kit.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 1,
		Parent = cinemaGui,
	})
	-- napis na czarnym ekranie w czasie przejścia (np. „Boarding your jet...”, odliczanie przed wywiadem)
	local captionHolder = Kit.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(700, 80),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 3,
		Parent = cinemaGui,
	})
	hud.registerScale(captionHolder)
	local caption = Kit.line(captionHolder, { anchor = Vector2.new(0.5, 0.5), position = UDim2.fromScale(0.5, 0.5), height = 70 })
	caption.holder.ZIndex = 3
	-- ocena wywiadu na koniec (wielki napis na środku)
	local verdictHolder = Kit.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromOffset(800, 120),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 4,
		Parent = cinemaGui,
	})
	hud.registerScale(verdictHolder)
	local verdict = Kit.line(verdictHolder, { anchor = Vector2.new(0.5, 0.5), position = UDim2.fromScale(0.5, 0.5), height = 110 })
	verdict.holder.ZIndex = 4
	local verdictScale = Kit.new("UIScale", { Parent = verdict.holder })
	-- konfetti na jachcie
	local confettiLayer = Kit.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 1,
		Parent = cinemaGui,
	})
	-- biała mgła, gdy kamera przelatuje przez chmurę (odrzutowiec)
	local fogFrame = Kit.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(245, 248, 255),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 1,
		Parent = cinemaGui,
	})
	-- emoji w wywiadzie (serduszka i reakcje lecą z prawego dolnego rogu)
	local reactionLayer = Kit.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 1,
		Parent = cinemaGui,
	})

	-- pasek czasu sesji u góry ekranu (pod nim licznik wyświetleń w czasie wywiadu)
	local timerHolder = Kit.new("Frame", {
		Name = "ActivityTimer",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 70),
		Size = UDim2.fromOffset(420, 130),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = hud.gui,
	})
	hud.registerScale(timerHolder)
	local timerTitle = Kit.text(timerHolder, { Size = UDim2.new(1, 0, 0, 48), Text = "" }, { maxSize = 44, stroke = 4 })
	local timerTrack = Kit.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 56),
		Size = UDim2.fromOffset(360, 26),
		BackgroundColor3 = Theme.White,
		BorderSizePixel = 0,
		Parent = timerHolder,
	})
	Kit.corner(timerTrack, 13)
	Kit.stroke(timerTrack, 4, Enum.ApplyStrokeMode.Border)
	local timerFill = Kit.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.White,
		BorderSizePixel = 0,
		Parent = timerTrack,
	})
	Kit.corner(timerFill, 13)
	Kit.gradient(timerFill, Theme.Gradients.LP, 90)
	local viewsLine = Kit.line(timerHolder, { anchor = Vector2.new(0.5, 0), position = UDim2.new(0.5, 0, 0, 90), height = 36 })

	-- ON AIR na lewo od paska czasu (wywiad); w rogu ekranu zasłaniał przycisk SELL
	local onAir = Kit.new("Frame", {
		Name = "OnAir",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(0, 20, 0, 69),
		Size = UDim2.fromOffset(150, 46),
		BackgroundColor3 = Color3.fromRGB(220, 30, 45),
		BorderSizePixel = 0,
		Visible = false,
		Parent = timerHolder,
	})
	Kit.corner(onAir, 23)
	Kit.stroke(onAir, 4, Enum.ApplyStrokeMode.Border)
	local onAirDot = Kit.new("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 14, 0.5, 0),
		Size = UDim2.fromOffset(16, 16),
		BackgroundColor3 = Theme.White,
		BorderSizePixel = 0,
		Parent = onAir,
	})
	Kit.corner(onAirDot, 8)
	Kit.text(onAir, {
		Position = UDim2.fromOffset(38, 6),
		Size = UDim2.new(1, -46, 1, -12),
		Text = TEXT.OnAir,
	}, { maxSize = 26, stroke = 2.5 })

	-- program wywiadu: okienko z pytaniami, odpowiedzi, czat i emoji (InterviewShow)
	local interviewShow = InterviewShow.create(hud, reactionLayer)

	-- Na czas sesji bez skoku i bez spadania: zakotwiczony gracz nad pokładem bez kolizji (np. jacht
	-- z siatki bez CanCollide) wpadał w stan Freefall i miał animację spadania, jakby wisiał w powietrzu.
	local function setSessionStates(humanoid, enabled)
		pcall(function()
			humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, enabled)
			humanoid:SetStateEnabled(Enum.HumanoidStateType.Freefall, enabled)
		end)
	end

	local function playEmote(name)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid ~= nil then
			task.spawn(function()
				pcall(function()
					humanoid:PlayEmote(name)
				end)
			end)
		end
	end

	local function fadeTo(transparency, seconds)
		blackout.Visible = true
		local tween = TweenService:Create(blackout, TweenInfo.new(seconds), { BackgroundTransparency = transparency })
		tween:Play()
		tween.Completed:Connect(function()
			if blackout.BackgroundTransparency >= 0.99 then
				blackout.Visible = false
			end
		end)
	end

	local function flash()
		flashFrame.BackgroundColor3 = Color3.new(1, 1, 1)
		flashFrame.BackgroundTransparency = 0.15
		TweenService:Create(flashFrame, TweenInfo.new(0.35), { BackgroundTransparency = 1 }):Play()
		Sounds.play("Photo")
	end

	local function partyFlash(color)
		flashFrame.BackgroundColor3 = color
		flashFrame.BackgroundTransparency = 0.72
		TweenService:Create(flashFrame, TweenInfo.new(0.6), { BackgroundTransparency = 1 }):Play()
	end

	-- Konfetti: kolorowe paski spadają z góry ekranu i się obracają.
	local confetti = {}
	local function spawnConfetti()
		local size = confettiLayer.AbsoluteSize
		if size.X <= 0 then
			return
		end
		local piece = Kit.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(math.random() * size.X, -20),
			Size = UDim2.fromOffset(math.random(8, 12), math.random(14, 22)),
			BackgroundColor3 = PARTY_COLORS[math.random(1, #PARTY_COLORS)],
			BorderSizePixel = 0,
			Rotation = math.random(0, 180),
			Parent = confettiLayer,
		})
		table.insert(confetti, {
			frame = piece,
			x = piece.Position.X.Offset,
			y = -20,
			speed = math.random(160, 260),
			sway = math.random() * 6.28,
			spin = math.random(-240, 240),
		})
	end

	local function updateConfetti(dt)
		local height = confettiLayer.AbsoluteSize.Y
		for i = #confetti, 1, -1 do
			local c = confetti[i]
			c.y = c.y + c.speed * dt
			c.sway = c.sway + dt * 2.4
			if c.y > height + 30 then
				c.frame:Destroy()
				table.remove(confetti, i)
			else
				c.frame.Position = UDim2.fromOffset(c.x + math.sin(c.sway) * 26, c.y)
				c.frame.Rotation = c.frame.Rotation + c.spin * dt
			end
		end
	end

	local function clearConfetti()
		for _, c in ipairs(confetti) do
			c.frame:Destroy()
		end
		confetti = {}
	end

	-- Inni gracze znikają u nas na czas sesji (aktywność jest „tylko twoja”).
	local hiddenCharacters = {}
	local function hideOthers(hidden)
		if hidden then
			for _, other in ipairs(Players:GetPlayers()) do
				local character = other.Character
				if other ~= player and character ~= nil then
					LocalHide.setAll(character, true, { collide = false })
					local humanoid = character:FindFirstChildOfClass("Humanoid")
					if humanoid ~= nil then
						humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
					end
					table.insert(hiddenCharacters, character)
				end
			end
		else
			for _, character in ipairs(hiddenCharacters) do
				if character.Parent ~= nil then
					LocalHide.setAll(character, false, { collide = false })
					local humanoid = character:FindFirstChildOfClass("Humanoid")
					if humanoid ~= nil then
						humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
					end
				end
			end
			hiddenCharacters = {}
		end
	end

	------------------------------------------------------------- Sceny: kamera i efekty każdej aktywności
	-- Każda scena zwraca { update(dt, elapsed, t) → CFrame kamery, stop() }. t = 0…1 przez całą sesję.
	local SCENES = {}

	-- Zdjęcia: kamera krąży wokół auta, co chwilę flesz z migawką.
	SCENES.Car = function(spot, duration)
		local frame = pivotOf(spot)
		local center = frame.Position + Vector3.new(0, 2.5, 0)
		local nextFlash = FLASH_EVERY
		return {
			update = function(_, elapsed, t)
				if elapsed >= nextFlash and elapsed < duration - 0.5 then
					nextFlash = nextFlash + FLASH_EVERY
					flash()
				end
				local angle = math.rad(-35 + 110 * t)
				local offset = Vector3.new(math.cos(angle) * 19, 5.5 - 1.5 * t, math.sin(angle) * 19)
				return CFrame.lookAt(frame:PointToWorldSpace(offset), center)
			end,
			stop = function() end,
		}
	end

	-- Jacht: przebitki jak w teledysku z imprezy (plan ogólny, gracz tańczy z bliska, nisko od wody,
	-- zza pleców gracza w stronę lądu, z drona i jazda wzdłuż burty). Jacht lekko się kołysze, a gracz
	-- razem z nim, gra muzyka, migają kolorowe światła, spada konfetti i co kilka sekund jest zdjęcie.
	-- Kamera zawsze stoi po stronie lądu (tam, skąd gracz przyszedł), więc nie wylatuje poza mapę.
	-- Na sam koniec trąbka i wybuch konfetti, a po zaciemnieniu oklaski (Reward).
	SCENES.Yacht = function(spot, duration, payload)
		local frame = pivotOf(spot)
		local model = itemModel(spot, "Yacht", shownTier("Yacht"))
		local original = model and model:GetPivot()
		-- kołysanie wokół środka jachtu (bez względu na to, gdzie jest jego punkt obrotu)
		local center, size, pivotOffset = frame, Vector3.new(10, 6, 24), nil
		if model ~= nil then
			center, size = model:GetBoundingBox()
			pivotOffset = center:ToObjectSpace(original)
		end
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		-- gracz stoi na pokładzie pod Pose jachtu dokładnie tak jak na serwerze (Shared/Stand: widoczna
		-- podłoga pod znacznikiem i wysokość według awatara) i kołysze się z jachtem
		local poseFrame = nil
		local posePart = model and model:FindFirstChild("Pose", true)
		if posePart ~= nil and posePart:IsA("BasePart") then
			poseFrame = Stand.at(posePart, character)
		end
		local ride = nil
		if poseFrame ~= nil and root ~= nil and model ~= nil then
			ride = center:ToObjectSpace(poseFrame)
			root.CFrame = poseFrame
		end
		local guest = (poseFrame and poseFrame.Position) or (root and root.Position) or (center.Position + Vector3.new(0, size.Y / 2 + 3, 0))

		-- oś jachtu (dłuższy bok w poziomie), dziób tam, gdzie stoi gracz, i strona lądu
		local up = Vector3.new(0, 1, 0)
		local along = center.LookVector
		local length, width = size.Z, size.X
		if size.X > size.Z then
			along = center.RightVector
			length, width = size.X, size.Z
		end
		along = Vector3.new(along.X, 0, along.Z)
		if along.Magnitude < 0.01 then
			along = Vector3.new(0, 0, -1)
		end
		along = along.Unit
		local mid = center.Position
		local base = Vector3.new(mid.X, 0, mid.Z)
		local bow = along
		if (guest - base):Dot(along) < 0 then
			bow = -along
		end
		local side = bow:Cross(up)
		local viewFrom = payload and payload.ViewFrom
		if typeof(viewFrom) == "Vector3" then
			local toView = viewFrom - mid
			if side:Dot(Vector3.new(toView.X, 0, toView.Z)) < 0 then
				side = -side
			end
		end
		local deckY = guest.Y - Stand.height(character)
		local topY = mid.Y + size.Y / 2
		local half = width / 2
		local guestAlong = (guest - base):Dot(bow)
		local guestSide = (guest - base):Dot(side)
		local head = guest + Vector3.new(0, 1.6, 0)
		local function at(a, s, y)
			return base + bow * a + side * s + Vector3.new(0, y, 0)
		end
		-- każde ujęcie: kamera jedzie od from[1] do from[2] i patrzy od look[1] do look[2]
		local shots = {
			wide = {
				from = { at(-length * 0.3, half + 22, topY + 6), at(length * 0.15, half + 22, topY + 6) },
				look = { at(-length * 0.05, 0, deckY + 1), at(length * 0.05, 0, deckY + 1) },
			},
			dancer = {
				from = {
					at(guestAlong + 2, math.max(guestSide + 7, half + 3), deckY + 3.4),
					at(guestAlong + 1, math.max(guestSide + 5.5, half + 2.5), deckY + 3.8),
				},
				look = { head, head },
			},
			low = {
				from = { at(length / 2 + 7, half + 6, deckY - 0.6), at(length / 2 + 5, half + 4.5, deckY - 0.3) },
				look = { head + up, head + up },
			},
			shoulder = {
				from = { guest - side * 2.2 - bow * 1.6 + up * 2.4, guest - side * 1.8 - bow * 1.2 + up * 2.6 },
				look = { guest + side * 14 + bow * 2 + up * 0.5, guest + side * 14 - bow * 2 + up * 0.5 },
			},
			drone = {
				from = { at(-length * 0.2, half + 10, topY + length * 0.6 + 10), at(length * 0.15, half + 6, topY + length * 0.6 + 12) },
				look = { at(0, 0, deckY), at(0, 0, deckY) },
			},
			dolly = {
				from = { at(-length * 0.55, half + 9, deckY + 2), at(length * 0.45, half + 9, deckY + 2.5) },
				look = { at(-length * 0.2, 0, deckY + 1.5), at(length * 0.3, 0, deckY + 1.5) },
			},
		}
		local order = { "wide", "dancer", "low", "shoulder", "drone", "dancer", "dolly", "wide", "low", "dancer", "drone", "shoulder", "dancer" }

		local nextParty = PARTY_EVERY
		local colorIndex = 0
		local nextConfetti = 0
		local nextPhoto = 1.4
		local hornAt = math.max(3, duration - 0.9) -- trąbka na sam koniec (serwer kończy sesję po duration)
		local horned = false
		local music = Sounds.start("PartyMusic")
		return {
			update = function(dt, elapsed)
				if model ~= nil then
					local heave = math.sin(elapsed * 1.3) * 0.12
					local roll = math.rad(math.sin(elapsed * 1.1) * 1.2)
					local pitch = math.rad(math.sin(elapsed * 0.8) * 0.8)
					local rock = center * CFrame.new(0, heave, 0) * CFrame.Angles(pitch, 0, roll)
					model:PivotTo(rock * pivotOffset)
					if ride ~= nil and root.Parent ~= nil then
						root.CFrame = rock * ride
					end
				end
				if elapsed >= nextParty and elapsed < duration - 0.5 then
					nextParty = nextParty + PARTY_EVERY
					colorIndex = colorIndex % #PARTY_COLORS + 1
					partyFlash(PARTY_COLORS[colorIndex])
				end
				-- zdjęcia na imprezie: flesz z migawką co kilka sekund, czasem dwa szybko po sobie
				if elapsed >= nextPhoto and elapsed < hornAt - 0.4 then
					nextPhoto = elapsed + between(PARTY_PHOTO_GAP)
					flash()
					if math.random() < 0.4 then
						task.delay(0.24, flash)
					end
				end
				if not horned and elapsed >= hornAt then
					horned = true
					music.setVolume(0.35, 0.5) -- muzyka ciszej, żeby trąbka i oklaski było dobrze słychać
					Sounds.play("PartyHorn")
					partyFlash(Color3.fromRGB(255, 214, 61))
					for _ = 1, 40 do
						spawnConfetti()
					end
				end
				if elapsed >= nextConfetti and elapsed < duration - 1 then
					nextConfetti = elapsed + 0.12
					spawnConfetti()
				end
				updateConfetti(dt)
				-- przebitki: co YACHT_SHOT sekund inne ujęcie, a w każdym kamera powoli jedzie
				local index = math.floor(elapsed / YACHT_SHOT)
				local shot = shots[order[index % #order + 1]]
				local p = smooth((elapsed - index * YACHT_SHOT) / YACHT_SHOT)
				return CFrame.lookAt(shot.from[1]:Lerp(shot.from[2], p), shot.look[1]:Lerp(shot.look[2], p))
			end,
			stop = function()
				music.stop()
				if model ~= nil and original ~= nil then
					model:PivotTo(original)
				end
				if ride ~= nil and root.Parent ~= nil then
					root.CFrame = center * ride -- z powrotem dokładnie tam, gdzie postawił serwer
				end
				clearConfetti()
			end,
		}
	end

	-- Wywiad: prowadzący pyta, gracz wybiera głupią odpowiedź, studio reaguje (program prowadzi
	-- InterviewShow). Ujęcia jak w telewizji: plan ogólny, gość, prowadzący, z boku i dramatyczne
	-- zbliżenie na prowadzącego. Licznik wyświetleń skacze po odpowiedziach i na koniec dobija do
	-- wartości zależnej od oceny (ocenę zna już serwer).
	SCENES.Interview = function(spot, duration, payload)
		local frame = pivotOf(spot)
		local pose = spotPose(spot, "Interview")
		local posePosition = (pose and pose.Position) or frame.Position
		local front = frame.LookVector
		local function at(x, y, z)
			return frame:PointToWorldSpace(Vector3.new(x, y, z))
		end
		local shots = {
			wide = { from = at(0, 7, -22), to = at(0, 4, 1) }, -- cały plan
			guest = { from = posePosition + front * 7 + frame.RightVector * 1.5 + Vector3.new(0, 4.6, 0), to = posePosition + Vector3.new(0, 4.3, 0) },
			host = { from = at(8, 5, -7), to = at(4, 4.6, 1.2) }, -- prowadzący
			side = { from = at(-13, 5.5, -8), to = at(1, 4, 1) }, -- z boku
		}
		local grade = payload.Grade or 2
		local style = GRADES[grade] or GRADES[2]
		local show = interviewShow.begin({
			duration = duration,
			grade = grade,
			target = style.views * (0.85 + math.random() * 0.3),
			onEmote = playEmote,
		})
		local shown = 0
		local nextLabel = 0
		onAir.Visible = true
		viewsLine.set({})
		return {
			update = function(dt, elapsed)
				local state = show.state
				local since = os.clock() - state.shotAt
				local from, to
				if state.shot == "hostZoom" then
					-- szybki najazd na twarz prowadzącego (jak w memach) z krótkim drżeniem
					local shot = shots.host
					from = shot.from:Lerp(shot.to, 0.62 * smooth(since / 0.16))
					to = shot.to
					local shake = math.max(0, 1 - since / 0.45) * 0.18
					from = from + Vector3.new((math.random() - 0.5) * shake, (math.random() - 0.5) * shake, (math.random() - 0.5) * shake)
				else
					local shot = shots[state.shot] or shots.wide
					local push = 0.08
					if state.shot == "guest" then
						push = 0.16 -- gracz myśli nad odpowiedzią, a kamera powoli się zbliża
					end
					from = shot.from:Lerp(shot.to, push * math.min(1, since / SHOT_SECONDS))
					to = shot.to
				end
				shown = shown + (state.views - shown) * math.min(1, dt * 3.5)
				if elapsed >= nextLabel then
					nextLabel = elapsed + 0.1
					viewsLine.set({ { text = Format.number(math.floor(shown + 0.5)) .. " " .. TEXT.Views, size = 28, colors = Theme.Gradients.LP } })
					onAirDot.Visible = math.floor(elapsed * 2) % 2 == 0 -- kropka miga
				end
				return CFrame.lookAt(from, to)
			end,
			stop = function()
				show.stop()
				onAir.Visible = false
				viewsLine.set({})
			end,
		}
	end

	-- Chmura do lotu (tylko u gracza): kilka spłaszczonych kul (elipsoid), punkt obrotu w środku.
	local function makeCloud(parent, kind)
		local model = Instance.new("Model")
		model.Name = "Cloud"
		local radius = 0
		for _ = 1, math.random(kind.puffs[1], kind.puffs[2]) do
			local part = Instance.new("Part")
			local width = between(kind.width)
			local height = between(kind.height)
			part.Size = Vector3.new(width, height, width * (0.7 + math.random() * 0.5))
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.Sphere
			mesh.Parent = part
			local offset = Vector3.new(
				(math.random() - 0.5) * 2 * kind.spread,
				(math.random() - 0.5) * height * 0.6,
				(math.random() - 0.5) * 1.4 * kind.spread
			)
			part.CFrame = CFrame.new(offset)
			radius = math.max(radius, offset.Magnitude + width * 0.5)
			part.Color = Color3.fromRGB(250, 252, 255)
			part.Material = Enum.Material.SmoothPlastic
			part.Transparency = 0.06
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.CastShadow = false
			part.Parent = model
		end
		model.WorldPivot = CFrame.new() -- punkt obrotu w środku chmury (do przesuwania)
		model.Parent = parent
		return { model = model, kind = kind, radius = radius, center = Vector3.new() }
	end

	-- Stawia chmurę przed samolotem: ahead studs do przodu, w bok i w górę według jej warstwy.
	local function placeCloud(cloud, origin, dir, ahead)
		local kind = cloud.kind
		local right = dir:Cross(Vector3.new(0, 1, 0))
		local lateral = between(kind.lateral)
		if math.random() < 0.5 then
			lateral = -lateral
		end
		local position = origin + dir * ahead + right * lateral + Vector3.new(0, between(kind.altitude), 0)
		cloud.model:PivotTo(CFrame.new(position) * CFrame.Angles(0, math.random() * 6.28, 0))
		cloud.center = position
	end

	-- Lot: samolot rozpędza się na pasie (seria zdjęć przy starcie), startuje i leci wśród chmur
	-- lekkimi łukami, a w locie co kilka sekund jest zdjęcie. Silnik rozkręca się razem z samolotem.
	-- Kamera najpierw z boku pasa, potem za samolotem.
	-- Leci lokalna kopia samolotu (tylko u gracza), a prawdziwy jest w tym czasie ukryty: przy
	-- StreamingEnabled Roblox usuwa u gracza części z serwera, które są daleko od jego postaci, więc
	-- prawdziwy samolot znikał po kilkuset studs lotu. Kopii to nie dotyczy.
	SCENES.Jet = function(spot, duration)
		local original = itemModel(spot, "Jet", shownTier("Jet"))
		local frame0 = (original and original:GetPivot()) or pivotOf(spot)
		local folder = Instance.new("Folder")
		folder.Name = "LarpFlight"
		folder.Parent = Workspace
		local jet = nil
		if original ~= nil then
			local ok, copy = pcall(function()
				return original:Clone()
			end)
			if ok and copy ~= nil then
				for _, d in ipairs(copy:GetDescendants()) do
					if d:IsA("BasePart") then
						d.Anchored = true
						d.CanCollide = false
						d.CanQuery = false
						d.CanTouch = false
					elseif d:IsA("BaseScript") then
						d:Destroy()
					end
				end
				copy.Parent = folder
				copy:PivotTo(frame0)
				LocalHide.setAll(original, true, { collide = false })
				jet = copy
			else
				jet = original -- bez kopii (np. model z Archivable = false) leci prawdziwy
			end
		end
		local look = frame0.LookVector
		local forward0 = Vector3.new(look.X, 0, look.Z)
		if forward0.Magnitude < 0.01 then
			forward0 = Vector3.new(0, 0, -1)
		end
		forward0 = forward0.Unit
		local position = frame0.Position
		local baseY = position.Y
		local heading, roll = 0, 0
		local lastAltitude = 0
		local camera = nil
		local sideCamera = (frame0 * CFrame.new(24, 7, -12)).Position
		-- chmury od razu w całej okolicy trasy (samolot wznosi się między nimi), potem te, które
		-- zostały za samolotem, przeskakują do przodu według aktualnego kursu
		local clouds = {}
		local cruiseOrigin = Vector3.new(position.X, baseY + JET_CRUISE, position.Z)
		for _, kind in ipairs(CLOUD_KINDS) do
			for _ = 1, kind.count do
				local cloud = makeCloud(folder, kind)
				placeCloud(cloud, cruiseOrigin, forward0, kind.from + math.random() * (CLOUD_AHEAD - kind.from))
				table.insert(clouds, cloud)
			end
		end
		local nextRunwayPhoto = 1
		local nextFlightPhoto = 12 + math.random() * 2
		local engine = Sounds.start("JetEngine")
		local music = Sounds.start("JetMusic")
		Sounds.play("JetCabin")
		return {
			update = function(dt, elapsed)
				local speed
				if elapsed < 8 then
					speed = 2.2 * elapsed
				elseif elapsed < 18 then
					speed = 17.6 + (70 - 17.6) * smooth((elapsed - 8) / 10)
				else
					speed = 70
				end
				-- wznoszenie zaczyna się jeszcze na pasie, żeby samolot przeleciał nad ścianą na końcu strefy
				local altitude = 0
				if elapsed >= 20 then
					altitude = JET_CRUISE + math.sin((elapsed - 20) * 0.35) * 6
				elseif elapsed >= 7 then
					altitude = JET_CRUISE * smooth((elapsed - 7) / 13)
				end
				engine.setSpeed(0.86 + 0.16 * smooth(elapsed / 14)) -- silnik wchodzi na obroty razem z samolotem
				-- zdjęcia: seria, gdy samolot rusza i startuje, potem co kilka sekund w locie
				if nextRunwayPhoto <= #JET_RUNWAY_PHOTOS and elapsed >= JET_RUNWAY_PHOTOS[nextRunwayPhoto] then
					nextRunwayPhoto = nextRunwayPhoto + 1
					flash()
				end
				if elapsed >= nextFlightPhoto and elapsed < duration - 2 then
					nextFlightPhoto = elapsed + between(JET_FLIGHT_PHOTO_GAP)
					flash()
					if math.random() < 0.35 then
						task.delay(0.22, flash)
					end
				end
				-- w locie lekkie łuki w prawo i w lewo (samolot przechyla się w zakręcie)
				local turn = 0
				if elapsed > 20 then
					turn = math.cos((elapsed - 20) * 0.12) * 0.042
				end
				heading = heading + turn * dt
				local dir = CFrame.Angles(0, heading, 0) * forward0
				position = position + dir * speed * dt
				local climb = (altitude - lastAltitude) / math.max(dt, 0.001)
				lastAltitude = altitude
				local pitch = math.atan2(climb, math.max(speed, 1))
				roll = roll + (turn * 8 - roll) * math.min(1, dt * 2)
				local spot3 = Vector3.new(position.X, baseY + altitude, position.Z)
				local jetFrame = CFrame.lookAt(spot3, spot3 + dir) * CFrame.Angles(pitch, 0, roll)
				if jet ~= nil then
					jet:PivotTo(jetFrame)
				end
				-- chmury, które zostały za samolotem albo za daleko w bok (po zakręcie), przeskakują do
				-- przodu, więc wokół trasy zawsze jest ich tyle samo
				local origin = Vector3.new(position.X, baseY + JET_CRUISE, position.Z)
				for _, cloud in ipairs(clouds) do
					local offset = cloud.center - origin
					local along = offset:Dot(dir)
					local across = (Vector3.new(offset.X, 0, offset.Z) - dir * along).Magnitude
					if along < -CLOUD_BEHIND or across > CLOUD_WIDE then
						placeCloud(cloud, origin, dir, between(CLOUD_RESPAWN))
					end
				end
				local target
				if elapsed < 8 then
					target = CFrame.lookAt(sideCamera, spot3 + Vector3.new(0, 2, 0))
				else
					target = CFrame.lookAt((jetFrame * CFrame.new(10, 7, 36)).Position, (jetFrame * CFrame.new(0, 2, -12)).Position)
				end
				if camera == nil then
					camera = target
				else
					camera = camera:Lerp(target, math.min(1, dt * 2.5))
				end
				-- biała mgła, gdy kamera przelatuje przez chmurę na trasie
				local fog = 0
				local eye = camera.Position
				for _, cloud in ipairs(clouds) do
					if cloud.kind.path then
						local inside = 1 - (eye - cloud.center).Magnitude / (cloud.radius * 1.1)
						if inside > fog then
							fog = inside
						end
					end
				end
				fogFrame.BackgroundTransparency = 1 - 0.7 * math.clamp(fog, 0, 1)
				return camera
			end,
			stop = function()
				engine.stop()
				music.stop()
				fogFrame.BackgroundTransparency = 1
				if jet ~= nil and jet == original then
					jet:PivotTo(frame0)
				end
				if original ~= nil and jet ~= original then
					LocalHide.setAll(original, false, { collide = false })
				end
				folder:Destroy()
			end,
		}
	end

	------------------------------------------------------------- Sesja
	local session = nil
	local endPayload = nil

	local function showCaption(kind, seconds)
		captionHolder.Visible = true
		if kind == "Interview" then
			-- odliczanie przed wejściem na wizję
			task.spawn(function()
				local count = math.max(1, math.floor(seconds + 0.5))
				for n = count, 1, -1 do
					if not captionHolder.Visible then
						return
					end
					caption.set({ { text = string.format(TEXT.LiveIn, n), size = 56, colors = Theme.Gradients.Red } })
					task.wait(seconds / count)
				end
			end)
		else
			caption.set({ { text = KINDS[kind].boarding or "", size = 48 } })
		end
	end

	local function hideCaption()
		captionHolder.Visible = false
		caption.set({})
	end

	-- Ocena wywiadu: wielki napis (np. MEGA VIRAL! ×4) wyskakuje na środku ekranu.
	local function revealGrade(index)
		local style = GRADES[index]
		local info = Economy.Activities.Interview.Grades[index]
		if style == nil or info == nil then
			return
		end
		verdict.set({
			{ text = style.text, size = 84, colors = style.colors },
			{ text = "×" .. Format.small(info.Multiplier), size = 64, colors = Theme.Gradients.Gold },
		})
		verdictHolder.Visible = true
		verdictScale.Scale = 0.3
		TweenService:Create(verdictScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		if index >= 2 then
			Sounds.play("Reward")
		elseif Sounds.has("InterviewFlop") then
			Sounds.play("InterviewFlop")
		else
			Sounds.play("NotEnough")
		end
		task.wait(1.5)
		TweenService:Create(verdictScale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Scale = 0 }):Play()
		task.wait(0.22)
		verdictHolder.Visible = false
	end

	local function showResult(kind, payload)
		if payload == nil then
			return
		end
		if kind == "Interview" and payload.Grade ~= nil then
			revealGrade(payload.Grade)
		else
			Sounds.play("Reward")
		end
		local items = {
			{ text = KINDS[kind].done, size = 26 },
			{ text = "+" .. Format.number(payload.LP or 0) .. " LP", size = 30, colors = Theme.Gradients.LP },
		}
		if (payload.LP or 0) < (payload.Reward or 0) then
			table.insert(items, { text = TEXT.BagLimit, size = 24, colors = Theme.Gradients.Red })
		end
		hud.toast(items)
	end

	local sessionScene = nil -- scena i jej połączenie co klatkę (żeby po błędzie dało się posprzątać)
	local sessionConnection = nil

	local function stopScene()
		if sessionConnection ~= nil then
			sessionConnection:Disconnect()
			sessionConnection = nil
		end
		if sessionScene ~= nil then
			local scene = sessionScene
			sessionScene = nil
			scene.stop()
		end
	end

	local function runSession(payload)
		local kind = payload.Activity
		local cfg = KINDS[kind]
		local duration = payload.Duration or 8
		local half = (payload.Transition or 3) / 2
		local spot = payload.Spot
		if typeof(spot) ~= "Instance" or spot.Parent == nil then
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			spot = root and nearestSpot(root.Position, kind)
		end

		-- skąd gracz patrzył przed sesją (strona lądu: tam ustawiają się kamery na jachcie)
		local viewCamera = Workspace.CurrentCamera
		if viewCamera ~= nil then
			payload.ViewFrom = viewCamera.CFrame.Position
		end
		-- bez skakania w czasie sesji (skok w chwili, gdy serwer stawia gracza, zostawiał go w powietrzu)
		local sessionHumanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if sessionHumanoid ~= nil then
			setSessionStates(sessionHumanoid, false)
		end
		fadeTo(0, 0.3)
		showCaption(kind, half)
		setSignsHidden(true)
		task.wait(half + 0.1) -- serwer w tym czasie stawia gracza na miejscu
		hideCaption()
		local camera = Workspace.CurrentCamera
		local scene = nil
		if spot ~= nil and SCENES[kind] ~= nil then
			scene = SCENES[kind](spot, duration, payload)
		end
		sessionScene = scene
		if scene ~= nil and camera ~= nil then
			local startTime = os.clock()
			camera.CameraType = Enum.CameraType.Scriptable
			sessionConnection = RunService.RenderStepped:Connect(function(dt)
				local elapsed = os.clock() - startTime
				local frame = scene.update(dt, elapsed, math.clamp(elapsed / duration, 0, 1))
				if frame ~= nil then
					camera.CFrame = frame
				end
			end)
		end
		hideOthers(true)
		local character = player.Character
		if cfg.hidePlayer and character ~= nil then
			LocalHide.setAll(character, true, { collide = false })
			State.hidePets = true -- pety „siedzą” z graczem w samolocie
		end
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid ~= nil and cfg.emote ~= nil then
			pcall(function()
				humanoid:PlayEmote(cfg.emote)
			end)
		end
		timerTitle.Text = cfg.busy
		timerFill.Size = UDim2.fromScale(1, 1)
		timerHolder.Visible = true
		TweenService:Create(timerFill, TweenInfo.new(duration, Enum.EasingStyle.Linear), { Size = UDim2.fromScale(0, 1) }):Play()
		fadeTo(1, 0.35)

		-- koniec: nagroda od serwera albo limit czasu, gdyby jej nie było
		local deadline = os.clock() + duration + 2
		while endPayload == nil and os.clock() < deadline do
			task.wait(0.05)
		end
		fadeTo(0, 0.3)
		task.wait(0.32)
		stopScene()
		if camera ~= nil then
			camera.CameraType = Enum.CameraType.Custom
			local current = player.Character
			local currentHumanoid = current and current:FindFirstChildOfClass("Humanoid")
			if currentHumanoid ~= nil then
				camera.CameraSubject = currentHumanoid
			end
		end
		hideOthers(false)
		if cfg.hidePlayer and character ~= nil and character.Parent ~= nil then
			LocalHide.setAll(character, false, { collide = false })
		end
		State.hidePets = false
		setSignsHidden(false)
		if sessionHumanoid ~= nil and sessionHumanoid.Parent ~= nil then
			setSessionStates(sessionHumanoid, true)
		end
		timerHolder.Visible = false
		fadeTo(1, 0.35)
	end

	-- Cała sesja; po błędzie gracz i tak odzyskuje kamerę, klikanie i okna.
	local function startSession(payload)
		if session ~= nil or KINDS[payload.Activity] == nil then
			return
		end
		session = payload.Activity
		endPayload = nil
		State.busy = true
		popup.hide()
		local ok, err = pcall(runSession, payload)
		if not ok then
			warn("[Aktywności] sesja: " .. tostring(err))
			pcall(stopScene)
			hideCaption()
			fadeTo(1, 0.2)
			local camera = Workspace.CurrentCamera
			if camera ~= nil then
				camera.CameraType = Enum.CameraType.Custom
			end
			timerHolder.Visible = false
			onAir.Visible = false
			fogFrame.BackgroundTransparency = 1
			clearConfetti()
			hideOthers(false)
			local character = player.Character
			if KINDS[payload.Activity].hidePlayer and character ~= nil then
				LocalHide.setAll(character, false, { collide = false })
			end
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if humanoid ~= nil then
				setSessionStates(humanoid, true)
			end
			State.hidePets = false
			setSignsHidden(false)
		end
		State.busy = false
		local kind = session
		session = nil
		showResult(kind, endPayload)
	end

	State.onNotify(function(payload)
		if payload.Kind == "ActivityStart" then
			task.spawn(startSession, payload)
		elseif payload.Kind == "ActivityEnd" and payload.Activity == session then
			endPayload = payload
		end
	end)

	------------------------------------------------------------- Otwieranie okna przy miejscu
	local timer = 0
	RunService.Heartbeat:Connect(function(dt)
		timer = timer + dt
		if timer < 0.15 then
			return
		end
		timer = 0
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root == nil or State.view == nil or State.busy or hud.windowOpen() then
			if popup.isOpen() then
				popup.hide()
			end
			return
		end
		local spot, distance = nearestSpot(root.Position)
		if spot ~= nil and distance <= OPEN_DISTANCE then
			local kind = spot:GetAttribute("Activity")
			if not dismissed and (not popup.isOpen() or current == nil or current.spot ~= spot) then
				current = { spot = spot, kind = kind }
				renderPopup()
				hud.closeUpgrades()
				popup.open()
			end
		elseif distance >= CLOSE_DISTANCE then
			dismissed = false
			if popup.isOpen() then
				popup.hide()
			end
		end
	end)

	------------------------------------------------------------- Stan od serwera
	State.onChange(function(view)
		local activities = view.Activities or {}
		for kind, cfg in pairs(KINDS) do
			local info = activities[kind]
			if cfg.prefix ~= nil and info ~= nil and info.Tier ~= tiers[kind] then
				tiers[kind] = info.Tier
				for _, spot in ipairs(spots) do
					if spot:GetAttribute("Activity") == kind then
						applyItems(spot)
					end
				end
			end
		end
		for _, spot in ipairs(spots) do
			updateSign(spot)
		end
		if popup.isOpen() then
			renderPopup()
		end
	end)

	for _, spot in ipairs(CollectionService:GetTagged(SPOT_TAG)) do
		onSpotAdded(spot)
	end
	CollectionService:GetInstanceAddedSignal(SPOT_TAG):Connect(onSpotAdded)
	CollectionService:GetInstanceRemovedSignal(SPOT_TAG):Connect(onSpotRemoved)
end

return Activities
