-- Budka z kodami po stronie gracza (Etap 11, część 1): stoisko w Downtown (CodesBooth, tag LarpCodes).
--   • nad budką napis „CODES”, a blisko duże E (klawisz albo kliknięcie),
--   • okno: pole na kod i REDEEM, pod nim wynik; karta bonusu za grupę (+5% LP, JOIN GROUP otwiera
--     okienko dołączania Robloxa) i karta bonusu za znajomych (+10% LP za każdego na serwerze,
--     najwyżej 3; INVITE otwiera okno zaproszeń Robloxa),
--   • komunikaty: nagrody z kodów (boosty; jajka i boxy otwierają Eggs.luau i Boxes.luau) i bonusy.
-- Kod sprawdza serwer (RewardsService, Logic/Rewards); tu jest tylko wygląd.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")
local GroupService = game:GetService("GroupService")
local SocialService = game:GetService("SocialService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared.Config.Economy)
local Net = require(Shared.Net)
local State = require(script.Parent.State)
local Theme = require(script.Parent.Ui.Theme)
local Kit = require(script.Parent.Ui.Kit)
local Icons = require(script.Parent.Ui.Icons)
local Sounds = require(script.Parent.Ui.Sounds)
local StandAnchor = require(script.Parent.StandAnchor)

local Codes = {}

local STAND_TAG = "LarpCodes" -- jak RewardsService.CodesTag na serwerze
local SHOW_DISTANCE = 8
local HIDE_DISTANCE = 12
-- Napis nad budką jak nad sklepem Aury (Kit.worldFrame): ok. 12 × 1,9 studs.
local LABEL_HEIGHT = 1.8
local LABEL_DESIGN = Vector2.new(360, 56)
local LABEL_PIXELS_PER_STUD = 30
local LABEL_DISTANCE = 70

-- Okno (piksele bazowe 1280×720): pole na kod, wynik, dwie karty bonusów i podpowiedź na dole.
local WINDOW_TOP, WINDOW_BOTTOM, PADDING = 44, 16, 28
local CONTENT_WIDTH = 584
local ENTRY_HEIGHT = 62
local REDEEM_WIDTH = 170
local CARD_HEIGHT = 112
local CARD_GAP = 14
local STATUS_Y = ENTRY_HEIGHT + 12
local CARDS_Y = STATUS_Y + 48
local FOOTER_Y = CARDS_Y + 2 * CARD_HEIGHT + CARD_GAP + 12
local CONTENT_HEIGHT = FOOTER_Y + 34
local WINDOW = Vector2.new(CONTENT_WIDTH + 2 * PADDING, WINDOW_TOP + CONTENT_HEIGHT + WINDOW_BOTTOM)

local TEXT = {
	Title = "Codes",
	Label = "CODES",
	Placeholder = "Enter code",
	Redeem = "REDEEM",
	Wait = "...",
	Redeemed = "Redeemed %s!",
	Unknown = "That code doesn't exist",
	Used = "You already used this code",
	Expired = "This code has expired",
	Invalid = "Type a code first",
	PetInventory = "No room for pets: sell or merge some first",
	ClothInventory = "No room for clothes: sell or merge some first",
	TooMany = "Too many tries, wait %d s",
	Cooldown = "Slow down a bit",
	NotLoaded = "Still loading, try again",
	BoostLP = "2x LP +%d min",
	BoostAutoSell = "Auto Sell +%d min",
	Pets = "+%d pets",
	Pet = "+1 pet",
	Items = "+%d clothes",
	Item = "+1 clothing item",
	GroupTitle = "group bonus",
	GroupValue = "+%d%% LP",
	GroupJoin = "Join %s",
	GroupActive = "You're in %s",
	GroupDefault = "our group",
	GroupNone = "No group for this game yet",
	Join = "JOIN GROUP",
	Active = "ACTIVE",
	Joined = "Joined! Your bonus turns on in a moment",
	JoinPending = "Join request sent",
	JoinFailed = "Couldn't open the group prompt",
	FriendsTitle = "per friend here",
	FriendsValue = "+%d%% LP",
	FriendsHere = "Friends here: %d/%d",
	FriendsNone = "Up to %d friends count",
	Invite = "INVITE",
	InviteFailed = "Invites aren't available right now",
	Footer = "Like the game for new codes at like goals!",
	ToastGroup = "Group bonus: +%d%% LP",
	ToastGroupJoined = "Thanks for joining! +%d%% LP",
	ToastFriend = "%s is here: +%d%% LP (%d/%d)",
	ToastFriendLeft = "%s left: friend bonus %d/%d",
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

local function percent(x)
	return math.floor(x * 100 + 0.5)
end

-- Krótki opis nagrody z odpowiedzi serwera (boosty, liczba petów i ubrań), np. „2x LP +15 min”.
local function rewardItems(result)
	local items = {}
	for _, boost in ipairs(result.Boosts or {}) do
		local format = TEXT.BoostLP
		if boost.Boost == "AutoSell" then
			format = TEXT.BoostAutoSell
		end
		table.insert(items, { icon = "Boost", size = 34 })
		table.insert(items, { text = string.format(format, boost.Minutes or 0), size = 24, colors = Theme.Gradients.Gold })
	end
	local pets = result.Pets or 0
	if pets > 0 then
		table.insert(items, { icon = "Pets", size = 34 })
		table.insert(items, { text = (pets == 1 and TEXT.Pet) or string.format(TEXT.Pets, pets), size = 24, colors = Theme.Gradients.Gold })
	end
	local clothes = result.Items or 0
	if clothes > 0 then
		table.insert(items, { icon = "Clothes", size = 34 })
		table.insert(items, { text = (clothes == 1 and TEXT.Item) or string.format(TEXT.Items, clothes), size = 24, colors = Theme.Gradients.Gold })
	end
	return items
end

function Codes.start(hud)
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	local stands = {}
	local current = nil

	------------------------------------------------------------- Napis nad budką
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
			Name = "CodesLabel",
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
				{ icon = "Code", size = 40 },
				{ text = TEXT.Label, size = 32, colors = Theme.Gradients.Pink },
			},
		})
		labels[stand] = { gui = gui }
		updateLabel(stand)
	end

	------------------------------------------------------------- Duże E
	local promptGui = Kit.new("BillboardGui", {
		Name = "CodesPrompt",
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

	------------------------------------------------------------- Okno
	local window = Kit.panel(hud.gui, {
		name = "CodesWindow",
		size = WINDOW,
		title = TEXT.Title,
		icon = "Code",
		padding = PADDING,
		top = WINDOW_TOP,
		bottom = WINDOW_BOTTOM,
	})
	hud.registerScale(window.holder)
	hud.addPopup(window)

	-- pole na kod: biała ramka z obrysem, w środku TextBox
	local entryFrame = Kit.new("Frame", {
		Name = "CodeEntry",
		Size = UDim2.fromOffset(CONTENT_WIDTH - REDEEM_WIDTH - 12, ENTRY_HEIGHT),
		BackgroundColor3 = Theme.White,
		BorderSizePixel = 0,
		ZIndex = 4,
		Parent = window.content,
	})
	Kit.corner(entryFrame, 18)
	Kit.stroke(entryFrame, 4, Enum.ApplyStrokeMode.Border)
	local box = Kit.new("TextBox", {
		Name = "Code",
		Position = UDim2.fromOffset(18, 8),
		Size = UDim2.new(1, -36, 1, -16),
		BackgroundTransparency = 1,
		ClearTextOnFocus = false,
		Font = Theme.Font,
		PlaceholderText = TEXT.Placeholder,
		PlaceholderColor3 = Theme.Muted,
		Text = "",
		TextColor3 = Theme.Dark,
		TextSize = 30,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 5,
		Parent = entryFrame,
	})
	local redeem = Kit.button(window.content, {
		name = "Redeem",
		size = Vector2.new(REDEEM_WIDTH, ENTRY_HEIGHT - 5),
		text = TEXT.Redeem,
		colors = Theme.Gradients.Green,
		anchor = Vector2.new(1, 0),
		position = UDim2.new(1, 0, 0, 0),
		textSize = 26,
	})
	redeem.holder.ZIndex = 4
	local status = Kit.line(window.content, {
		name = "Status",
		anchor = Vector2.new(0.5, 0.5),
		position = UDim2.new(0.5, 0, 0, STATUS_Y + 20),
		height = 40,
	})
	status.holder.ZIndex = 4
	local statusScale = Kit.new("UIScale", { Parent = status.holder })

	local function setStatus(items, pop)
		status.set(items)
		if pop then
			statusScale.Scale = 1.15
			TweenService:Create(statusScale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end
	end

	-- Karta bonusu: ikona, nazwa, ile daje, opis i przycisk po prawej.
	local function makeCard(order, icon, colors)
		local card = Kit.new("Frame", {
			Name = "Card" .. order,
			Position = UDim2.fromOffset(0, CARDS_Y + (order - 1) * (CARD_HEIGHT + CARD_GAP)),
			Size = UDim2.fromOffset(CONTENT_WIDTH, CARD_HEIGHT),
			BackgroundColor3 = Theme.White,
			BorderSizePixel = 0,
			ZIndex = 4,
			Parent = window.content,
		})
		Kit.corner(card, 18)
		Kit.stroke(card, 3, Enum.ApplyStrokeMode.Border)
		local band = Kit.new("Frame", {
			Name = "Band",
			Size = UDim2.new(0, 96, 1, 0),
			BackgroundColor3 = Theme.White,
			BorderSizePixel = 0,
			ZIndex = 4,
			Parent = card,
		})
		Kit.corner(band, 18)
		Kit.gradient(band, colors, 90)
		-- prawe rogi paska proste (zaokrąglone są tylko lewe, jak róg karty)
		local filler = Kit.new("Frame", {
			Position = UDim2.new(1, -18, 0, 0),
			Size = UDim2.new(0, 18, 1, 0),
			BackgroundColor3 = Theme.White,
			BorderSizePixel = 0,
			ZIndex = 4,
			Parent = band,
		})
		Kit.gradient(filler, colors, 90)
		Icons.make(icon, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(64, 64),
			ZIndex = 6,
			Parent = band,
		})
		local titleLine = Kit.line(card, {
			name = "Title",
			anchor = Vector2.new(0, 0.5),
			position = UDim2.fromOffset(112, 32),
			height = 40,
		})
		titleLine.holder.ZIndex = 5
		local caption = Kit.text(card, {
			Name = "Caption",
			Position = UDim2.fromOffset(112, 60),
			Size = UDim2.new(1, -112 - 214, 0, 34),
			Text = "",
			TextColor3 = Theme.Muted,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 5,
		}, { maxSize = 20, stroke = 0 })
		local button = Kit.button(card, {
			name = "Action",
			size = Vector2.new(190, 54),
			text = "",
			colors = Theme.Gradients.Cyan,
			anchor = Vector2.new(1, 0.5),
			position = UDim2.new(1, -14, 0.5, -2),
			textSize = 22,
		})
		button.holder.ZIndex = 5
		return { card = card, title = titleLine, caption = caption, button = button }
	end

	local groupCard = makeCard(1, "Group", Theme.Gradients.Premium)
	local friendsCard = makeCard(2, "Friends", Theme.Gradients.CardPink)
	friendsCard.button.setText(TEXT.Invite)
	friendsCard.button.setColors(Theme.Gradients.Pink)

	local footer = Kit.line(window.content, {
		name = "Footer",
		anchor = Vector2.new(0.5, 0.5),
		position = UDim2.new(0.5, 0, 0, FOOTER_Y + 17),
		height = 34,
		items = {
			{ icon = "Like", size = 30 },
			{ text = TEXT.Footer, size = 20, color = Theme.Muted, stroke = 0 },
		},
	})
	footer.holder.ZIndex = 4

	------------------------------------------------------------- Grupa i znajomi
	local groupName = nil -- nazwa grupy z Robloxa (raz na grę)
	local groupNameFor = nil
	local function fetchGroupName(groupId)
		if groupNameFor == groupId then
			return
		end
		groupNameFor = groupId
		task.spawn(function()
			local ok, info = pcall(function()
				return GroupService:GetGroupInfoAsync(groupId)
			end)
			if ok and type(info) == "table" and type(info.Name) == "string" then
				groupName = info.Name
				if window.isOpen() then
					Codes.render()
				end
			end
		end)
	end

	local renderedKey = nil
	local function renderCards()
		local view = State.view or {}
		local B = Economy.Bonuses
		local groupId = view.GroupId or 0
		if groupId > 0 then
			fetchGroupName(groupId)
		end
		local name = groupName or TEXT.GroupDefault
		-- stan przychodzi często (np. z Auto-Click), a karty zmieniają się rzadko
		local key = table.concat({ tostring(groupId), tostring(view.InGroup), tostring(view.FriendsHere), name }, "|")
		if key == renderedKey then
			return
		end
		renderedKey = key
		groupCard.title.set({
			{ text = string.format(TEXT.GroupValue, percent(B.Group)), size = 30, colors = Theme.Gradients.Gold },
			{ text = TEXT.GroupTitle, size = 22 },
		})
		if view.InGroup then
			groupCard.caption.Text = string.format(TEXT.GroupActive, name)
			groupCard.button.setText(TEXT.Active)
			groupCard.button.setColors(Theme.Gradients.Owned)
		elseif groupId <= 0 then
			groupCard.caption.Text = TEXT.GroupNone
			groupCard.button.setText(TEXT.Join)
			groupCard.button.setColors(Theme.Gradients.Gray)
		else
			groupCard.caption.Text = string.format(TEXT.GroupJoin, name)
			groupCard.button.setText(TEXT.Join)
			groupCard.button.setColors(Theme.Gradients.Premium)
		end
		local here = math.min(view.FriendsHere or 0, B.FriendMax)
		friendsCard.title.set({
			{ text = string.format(TEXT.FriendsValue, percent(B.FriendEach)), size = 30, colors = Theme.Gradients.Gold },
			{ text = TEXT.FriendsTitle, size = 22 },
		})
		if here > 0 then
			friendsCard.caption.Text = string.format(TEXT.FriendsHere, here, B.FriendMax)
		else
			friendsCard.caption.Text = string.format(TEXT.FriendsNone, B.FriendMax)
		end
	end

	function Codes.render()
		renderCards()
	end

	local joining = false
	groupCard.button.Activated:Connect(function()
		local view = State.view or {}
		local groupId = view.GroupId or 0
		if view.InGroup or joining then
			return
		end
		if groupId <= 0 then
			Sounds.play("NotEnough")
			setStatus({ { text = TEXT.GroupNone, size = 24, colors = Theme.Gradients.Red } }, true)
			return
		end
		joining = true
		local ok, result = pcall(function()
			return GroupService:PromptJoinAsync(groupId)
		end)
		joining = false
		if not ok then
			setStatus({ { text = TEXT.JoinFailed, size = 24, colors = Theme.Gradients.Red } }, true)
			return
		end
		if result == Enum.GroupMembershipStatus.Joined or result == Enum.GroupMembershipStatus.AlreadyMember then
			-- serwer sprawdzi sam (IsInGroupAsync); bonus włącza się po chwili
			Net.event("GroupJoined"):FireServer()
			Sounds.play("Unlock", { volume = 0.6 })
			setStatus({ { icon = "Group", size = 34 }, { text = TEXT.Joined, size = 24, colors = Theme.Gradients.Green } }, true)
		elseif result == Enum.GroupMembershipStatus.JoinRequestPending then
			setStatus({ { text = TEXT.JoinPending, size = 24, colors = Theme.Gradients.Gold } }, true)
		end
	end)

	friendsCard.button.Activated:Connect(function()
		local ok, can = pcall(function()
			return SocialService:CanSendGameInviteAsync(player)
		end)
		if ok and can then
			pcall(function()
				SocialService:PromptGameInvite(player)
			end)
		else
			Sounds.play("NotEnough")
			setStatus({ { text = TEXT.InviteFailed, size = 24, colors = Theme.Gradients.Red } }, true)
		end
	end)

	------------------------------------------------------------- Kod
	local requesting = false
	local function redeemNow()
		if requesting then
			return
		end
		local text = box.Text
		if string.gsub(text, "%s", "") == "" then
			Sounds.play("NotEnough")
			Kit.shake(redeem.holder)
			setStatus({ { text = TEXT.Invalid, size = 24, colors = Theme.Gradients.Red } }, true)
			return
		end
		requesting = true
		redeem.setText(TEXT.Wait)
		local ok, result = pcall(function()
			return Net.func("RedeemCode"):InvokeServer(text)
		end)
		requesting = false
		redeem.setText(TEXT.Redeem)
		if not ok or type(result) ~= "table" then
			return
		end
		if result.Ok then
			box.Text = ""
			Sounds.play("Unlock", { volume = 0.7 })
			local items = { { icon = "Code", size = 34 }, { text = string.format(TEXT.Redeemed, tostring(result.Code)), size = 26, colors = Theme.Gradients.Green } }
			for _, item in ipairs(rewardItems(result)) do
				table.insert(items, item)
			end
			setStatus(items, true)
			hud.toast(items)
			if (result.Pets or 0) > 0 or (result.Items or 0) > 0 then
				-- jajka i boxy otwierają się na całym ekranie (Eggs.luau i Boxes.luau)
				window.hide()
			end
			return
		end
		local reason = result.Reason
		local message = TEXT[reason] or TEXT.Unknown
		if reason == "TooMany" then
			message = string.format(TEXT.TooMany, result.Wait or 30)
		end
		Sounds.play("NotEnough")
		Kit.shake(redeem.holder)
		setStatus({ { text = message, size = 24, colors = Theme.Gradients.Red } }, true)
	end

	-- kody są krótkie (Logic/Rewards.CodeMaxLength), więc dłuższego tekstu nie da się wpisać
	box:GetPropertyChangedSignal("Text"):Connect(function()
		if #box.Text > 30 then
			box.Text = string.sub(box.Text, 1, 30)
		end
	end)
	redeem.Activated:Connect(redeemNow)
	box.FocusLost:Connect(function(enterPressed)
		if enterPressed then
			redeemNow()
		end
	end)

	local function openWindow()
		if current == nil or State.busy then
			return
		end
		renderCards()
		setStatus({})
		promptGui.Enabled = false
		window.open()
	end

	promptButton.Activated:Connect(function()
		Sounds.play("Button")
		openWindow()
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		-- processed = true też wtedy, gdy gracz pisze w polu na kod (E to wtedy litera)
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

	------------------------------------------------------------- Komunikaty z serwera
	State.onNotify(function(payload)
		if payload.Kind == "Bonus" then
			local B = Economy.Bonuses
			local text
			local icon = "Friends"
			if payload.What == "Group" then
				icon = "Group"
				text = string.format((payload.Joined and TEXT.ToastGroupJoined) or TEXT.ToastGroup, percent(B.Group))
				if payload.Joined then
					Sounds.play("Unlock", { volume = 0.7 })
				end
			elseif payload.What == "Friend" then
				text = string.format(TEXT.ToastFriend, tostring(payload.Name), percent(B.FriendEach), payload.Friends or 0, B.FriendMax)
			elseif payload.What == "FriendLeft" then
				text = string.format(TEXT.ToastFriendLeft, tostring(payload.Name), payload.Friends or 0, B.FriendMax)
			end
			if text ~= nil then
				hud.toast({ { icon = icon, size = 40 }, { text = text, size = 26, colors = Theme.Gradients.Gold } }, "Bonus" .. tostring(payload.What) .. tostring(payload.Name))
			end
			if window.isOpen() then
				renderCards()
			end
		end
	end)

	------------------------------------------------------------- Budki i najbliższa
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
			box:ReleaseFocus()
			window.hide()
		end
		promptGui.Enabled = current ~= nil and not window.isOpen()
	end)

	local lastBusy = nil
	State.onChange(function()
		if State.busy ~= lastBusy then
			lastBusy = State.busy
			for stand in pairs(labels) do
				updateLabel(stand)
			end
		end
		if window.isOpen() then
			renderCards()
		end
	end)

	for _, stand in ipairs(CollectionService:GetTagged(STAND_TAG)) do
		onStandAdded(stand)
	end
	CollectionService:GetInstanceAddedSignal(STAND_TAG):Connect(onStandAdded)
	CollectionService:GetInstanceRemovedSignal(STAND_TAG):Connect(onStandRemoved)
end

return Codes
