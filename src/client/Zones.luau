-- Strefy po stronie gracza: bramki (otwarte tylko u gracza, który kupił strefę), tablice z nazwą,
-- mnożnikiem i ceną nad zamkniętymi bramkami, okno „Unlock” przy następnej bramce i duży napis
-- z nazwą strefy po wejściu do niej. Zakup sprawdza serwer (BuyZone), a mnożnik liczy serwer
-- (ZoneService i Loop.effectiveZone); tu jest tylko wygląd.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
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
local LocalHide = require(script.Parent.LocalHide)

local Zones = {}

local GATE_TAG = "LarpGate" -- ten sam tag co ZoneService.GateTag na serwerze
local OPEN_DISTANCE = 12 -- tak blisko bramki otwiera się okno „Unlock” (studs)
local CLOSE_DISTANCE = 20 -- tak daleko okno się zamyka
local BANNER_COOLDOWN = 15 -- ta sama strefa pokazuje napis najwyżej raz na tyle sekund

local TEXT = {
	Perk = "LP per click",
	Earn = "Earn",
	Unlock = "UNLOCK",
	Unlocked = "unlocked!",
	Locked = "Unlock the previous zone first",
}

local function multiplierText(zone)
	return "×" .. Format.small(Economy.Zones[zone].ClickMultiplier)
end

----------------------------------------------------------------- Bramki
local gates = {} -- [strefa] = { parts = { części }, sign = BillboardGui }
local unlocked = 1 -- ostatnia kupiona strefa (ze stanu od serwera)
local playerGui = nil

local function gateOf(zone)
	local g = gates[zone]
	if g == nil then
		g = { parts = {} }
		gates[zone] = g
	end
	return g
end

-- Otwarta bramka u tego gracza: przezroczysta i bez kolizji (dla innych dalej stoi).
local function setPartOpen(part, open, animate)
	LocalHide.set(part, open, { animate = animate })
end

local function biggestPart(parts)
	local best, bestSize = nil, -1
	for _, part in ipairs(parts) do
		local size = part.Size.X * part.Size.Y * part.Size.Z
		if part.Parent ~= nil and size > bestSize then
			best, bestSize = part, size
		end
	end
	return best
end

-- Tablica nad zamkniętą bramką: nazwa strefy, mnożnik i cena (rozmiar w studs, maleje z odległością).
local function makeSign(zone)
	local info = Economy.Zones[zone]
	local sign = Kit.new("BillboardGui", {
		Name = "ZoneSign" .. zone,
		Size = UDim2.fromScale(26, 11),
		LightInfluence = 0,
		MaxDistance = 200,
		ResetOnSpawn = false,
		Parent = playerGui,
	})
	Kit.text(sign, {
		Name = "ZoneName",
		Size = UDim2.fromScale(1, 0.44),
		Text = string.upper(info.Name),
	}, { maxSize = 100, stroke = 3.5 })
	Kit.text(sign, {
		Name = "Perk",
		Position = UDim2.fromScale(0, 0.44),
		Size = UDim2.fromScale(1, 0.24),
		Text = multiplierText(zone) .. " " .. TEXT.Perk,
	}, { maxSize = 80, stroke = 3, gradient = Theme.Gradients.Gold })
	local coin = Icons.make("Cash", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(0.42, 0.85),
		Size = UDim2.fromScale(0.2, 0.3),
		Parent = sign,
	})
	Kit.new("UIAspectRatioConstraint", { AspectRatio = 1, Parent = coin })
	Kit.text(sign, {
		Name = "Price",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0.44, 0.85),
		Size = UDim2.fromScale(0.56, 0.3),
		Text = Format.number(info.Cost),
		TextXAlignment = Enum.TextXAlignment.Left,
	}, { maxSize = 100, stroke = 3, gradient = Theme.Gradients.Gold })
	return sign
end

local function refreshGate(zone, animate)
	local g = gates[zone]
	if g == nil then
		return
	end
	local open = zone <= unlocked
	for _, part in ipairs(g.parts) do
		setPartOpen(part, open, animate)
	end
	local main = biggestPart(g.parts)
	if not open and main ~= nil then
		if g.sign == nil then
			g.sign = makeSign(zone)
		end
		g.sign.Adornee = main
		g.sign.StudsOffsetWorldSpace = Vector3.new(0, main.Size.Y / 2 + 6.5, 0)
		g.sign.Enabled = true
	elseif g.sign ~= nil then
		g.sign.Enabled = false
	end
end

-- Części bramek przychodzą z serwera (przy StreamingEnabled także później, gdy podejdziesz bliżej).
local function onGateAdded(part)
	if not part:IsA("BasePart") then
		return
	end
	local zone = part:GetAttribute("Zone")
	if type(zone) ~= "number" or Economy.Zones[zone] == nil then
		return
	end
	local g = gateOf(zone)
	for _, existing in ipairs(g.parts) do
		if existing == part then
			return
		end
	end
	table.insert(g.parts, part)
	refreshGate(zone, false)
end

local function onGateRemoved(part)
	for zone, g in pairs(gates) do
		for i = #g.parts, 1, -1 do
			if g.parts[i] == part then
				table.remove(g.parts, i)
				refreshGate(zone, false)
			end
		end
	end
end

local function distanceToPart(part, position)
	local p = part.CFrame:PointToObjectSpace(position)
	local half = part.Size / 2
	local dx = math.max(math.abs(p.X) - half.X, 0)
	local dy = math.max(math.abs(p.Y) - half.Y, 0)
	local dz = math.max(math.abs(p.Z) - half.Z, 0)
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function gateDistance(zone, position)
	local g = gates[zone]
	local best = math.huge
	if g ~= nil then
		for _, part in ipairs(g.parts) do
			if part.Parent ~= nil then
				local d = distanceToPart(part, position)
				if d < best then
					best = d
				end
			end
		end
	end
	return best
end

----------------------------------------------------------------- Start
function Zones.start(hud)
	local player = Players.LocalPlayer
	playerGui = player:WaitForChild("PlayerGui")

	------------------------------------------------------------- Napis z nazwą strefy
	local bannerHolder = Kit.new("Frame", {
		Name = "ZoneBanner",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 78),
		Size = UDim2.fromOffset(900, 110),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = hud.gui,
	})
	hud.registerScale(bannerHolder)
	local bannerInner = Kit.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = bannerHolder })
	local bannerScale = Kit.new("UIScale", { Parent = bannerInner })
	local bannerName = Kit.line(bannerInner, {
		anchor = Vector2.new(0.5, 0),
		position = UDim2.new(0.5, 0, 0, 0),
		height = 62,
	})
	local bannerPerk = Kit.line(bannerInner, {
		anchor = Vector2.new(0.5, 0),
		position = UDim2.new(0.5, 0, 0, 62),
		height = 42,
	})
	local bannerToken = 0
	local lastBanner = {}

	local function banner(zone)
		local info = Economy.Zones[zone]
		if info == nil then
			return
		end
		local now = os.clock()
		if lastBanner[zone] ~= nil and now - lastBanner[zone] < BANNER_COOLDOWN then
			return
		end
		lastBanner[zone] = now
		bannerName.set({ { text = string.upper(info.Name), size = 50 } })
		if info.ClickMultiplier > 1 then
			bannerPerk.set({
				{ text = multiplierText(zone), size = 30, colors = Theme.Gradients.Gold },
				{ text = TEXT.Perk, size = 30 },
			})
		else
			bannerPerk.set({})
		end
		bannerToken = bannerToken + 1
		local token = bannerToken
		bannerHolder.Visible = true
		bannerScale.Scale = 0.5
		TweenService:Create(bannerScale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		task.delay(2.2, function()
			if token ~= bannerToken then
				return
			end
			local shrink = TweenService:Create(bannerScale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Scale = 0 })
			shrink:Play()
			shrink.Completed:Wait()
			if token == bannerToken then
				bannerHolder.Visible = false
			end
		end)
	end

	------------------------------------------------------------- Okno „Unlock”
	local popup = Kit.panel(hud.gui, {
		name = "ZoneUnlock",
		size = Vector2.new(470, 270),
		title = "",
		padding = 30,
		top = 52,
		bottom = 28,
	})
	hud.registerScale(popup.holder)
	local perkLine = Kit.line(popup.content, {
		anchor = Vector2.new(0.5, 0),
		position = UDim2.new(0.5, 0, 0, 0),
		height = 44,
	})
	local priceLine = Kit.line(popup.content, {
		anchor = Vector2.new(0.5, 0),
		position = UDim2.new(0.5, 0, 0, 50),
		height = 54,
	})
	local unlockButton = Kit.button(popup.content, {
		name = "Unlock",
		size = Vector2.new(220, 62),
		text = TEXT.Unlock,
		colors = Theme.Gradients.Green,
		anchor = Vector2.new(0.5, 1),
		position = UDim2.new(0.5, 0, 1, 0),
		textSize = 30,
	})
	local popupZone = nil
	local dismissed = false -- zamknięte X-em: nie otwieraj, dopóki gracz nie odejdzie od bramki
	local boughtAt = {} -- [strefa] = czas zakupu (zanim przyjdzie nowy stan, okno nie wraca)

	local function updateButton()
		local view = State.view
		local info = popupZone and Economy.Zones[popupZone]
		if view == nil or info == nil then
			return
		end
		if view.Cash >= info.Cost then
			unlockButton.setColors(Theme.Gradients.Green)
		else
			unlockButton.setColors(Theme.Gradients.Gray)
		end
	end

	local function openPopup(zone)
		local info = Economy.Zones[zone]
		popupZone = zone
		popup.title.Text = info.Name
		perkLine.set({
			{ text = TEXT.Earn, size = 28 },
			{ text = multiplierText(zone), size = 30, colors = Theme.Gradients.Gold },
			{ text = TEXT.Perk .. "!", size = 28 },
		})
		priceLine.set({
			{ icon = "Cash", size = 50 },
			{ text = Format.number(info.Cost), size = 42, colors = Theme.Gradients.Gold },
		})
		updateButton()
		hud.closeUpgrades()
		popup.open()
	end

	popup.close.Activated:Connect(function()
		dismissed = true
	end)

	local buying = false
	unlockButton.Activated:Connect(function()
		if buying or popupZone == nil then
			return
		end
		buying = true
		local zone = popupZone
		local ok, result = pcall(function()
			return Net.func("BuyZone"):InvokeServer(zone)
		end)
		buying = false
		if not ok or type(result) ~= "table" then
			return
		end
		if result.Ok then
			boughtAt[zone] = os.clock()
			popup.hide()
			-- bramka otworzy się i pojawi się komunikat, gdy przyjdzie nowy stan z serwera
		elseif result.Reason == "NotEnough" then
			hud.notEnough(unlockButton)
		elseif result.Reason == "Locked" then
			hud.toast({ { text = TEXT.Locked, size = 26, colors = Theme.Gradients.Red } }, "ZoneLocked")
		end
	end)

	-- Okno otwiera się samo przy następnej bramce i zamyka, gdy odejdziesz.
	local timer = 0
	RunService.Heartbeat:Connect(function(dt)
		timer = timer + dt
		if timer < 0.15 then
			return
		end
		timer = 0
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local nextZone = unlocked + 1
		if root == nil or Economy.Zones[nextZone] == nil or State.busy then
			if popup.isOpen() then
				popup.hide()
			end
			return
		end
		local distance = gateDistance(nextZone, root.Position)
		local justBought = boughtAt[nextZone] ~= nil and os.clock() - boughtAt[nextZone] < 2
		if distance <= OPEN_DISTANCE then
			if not dismissed and not justBought and (not popup.isOpen() or popupZone ~= nextZone) then
				openPopup(nextZone)
			end
		elseif distance >= CLOSE_DISTANCE then
			dismissed = false
			if popup.isOpen() then
				popup.hide()
			end
		end
	end)

	------------------------------------------------------------- Stan od serwera
	State.onChange(function(view, old)
		local newUnlocked = view.ZonesUnlocked or 1
		if newUnlocked ~= unlocked then
			local before = unlocked
			unlocked = newUnlocked
			for zone in pairs(gates) do
				-- nowo kupiona bramka znika powoli, reszta od razu (np. po wczytaniu zapisu)
				refreshGate(zone, old ~= nil and zone > before and zone <= newUnlocked)
			end
			if old ~= nil and newUnlocked > before then
				Sounds.play("Unlock")
				hud.toast({
					{ text = Economy.Zones[newUnlocked].Name, size = 30, colors = Theme.Gradients.Gold },
					{ text = TEXT.Unlocked, size = 30 },
				})
			end
		end
		if old ~= nil and view.Zone ~= old.Zone then
			banner(view.Zone)
		end
		if popup.isOpen() then
			updateButton()
		end
	end)

	for _, part in ipairs(CollectionService:GetTagged(GATE_TAG)) do
		onGateAdded(part)
	end
	CollectionService:GetInstanceAddedSignal(GATE_TAG):Connect(onGateAdded)
	CollectionService:GetInstanceRemovedSignal(GATE_TAG):Connect(onGateRemoved)
end

return Zones
