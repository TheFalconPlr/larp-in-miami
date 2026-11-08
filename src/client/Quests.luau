-- Zadania dzienne po stronie gracza (Etap 11, część 3): zakładka QUESTS w oknie nagrody dziennej
-- (okno i zakładki buduje Daily.luau, tu jest treść zakładki i komunikaty):
--   • 3 karty: co zrobić, nagroda (i Aura od Rebirth 1), pasek postępu; odebrane zielone ze znaczkiem,
--     a czekające na miejsce w ekwipunku złote z przyciskiem CLAIM (pulsują tylko przy otwartej zakładce),
--   • nad kartami komplet (+20 Aury za wszystkie 3), pod nimi czas do nowych zadań (północ UTC),
--   • gotowe zadanie serwer odbiera sam (Notify „Reward” z Source = "Quest"): komunikat „Quest complete!”
--     pokazujemy po animacji jajek i boxów (Eggs.luau, Boxes.luau), a „+10 AURA” przy liczniku
--     przez State.emit; bez miejsca w ekwipunku Notify „QuestReady” mówi, gdzie odebrać nagrodę.
-- Postęp liczy i nagrody daje serwer (RewardsService, Logic/Rewards).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

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
local Codes = require(script.Parent.Codes)

local Quests = {}

-- Zakładka w pikselach bazowych (1280×720): nagłówek, rząd 3 kart i stopka z czasem.
local L = {
	Card = Vector2.new(270, 236),
	CardGap = 23,
	Band = 40,
	HeaderH = 40,
	FooterH = 34,
	Art = 62,
	Bar = Vector2.new(232, 32),
	Button = Vector2.new(190, 40),
	BusyCalm = 0.6, -- komunikat po tylu sekundach bez animacji (jajka i boxy z nagrody)
}
L.RowY = L.HeaderH + 10
L.FooterY = L.RowY + L.Card.Y + 12
L.ContentH = L.FooterY + L.FooterH

local TEXT = {
	Header = "Complete quests for free rewards!",
	HeaderAura = "Complete all %d quests: +%s Aura",
	HeaderCount = "(%d/%d)",
	AllDone = "All quests done! Come back tomorrow",
	AllDoneAura = "All quests done! +%s Aura",
	Loading = "Loading quests...",
	New = "New quests in %s",
	NewSoon = "New quests any second!",
	Claim = "CLAIM!",
	Completed = "COMPLETED!",
	Aura = "+%s Aura",
	Toast = "Quest complete!",
	ToastAll = "All daily quests done!",
	MakeRoom = "Make room, then claim it at the Daily board",
	PetInventory = "No room for pets: sell or merge some first",
	ClothInventory = "No room for clothes: sell or merge some first",
	Claimed = "Already claimed",
	NotDone = "Finish the quest first",
	Error = "Something went wrong, try again",
}

-- Wygląd i napisy zadań (klucze jak w Economy.Rewards.DailyQuests). goal = cel (%s = liczba),
-- one = cel 1 (np. Merges); short i shortOne = krótsze napisy do listy na ekranie (QuestTracker).
local QUESTS = {
	CarPhotos = { icon = "Camera", title = "CAR PHOTOS", goal = "Do %s car photoshoots", one = "Do a car photoshoot", short = "Do %s photoshoots", shortOne = "Do a photoshoot" },
	Interviews = { icon = "Interview", title = "INTERVIEWS", goal = "Give %s live interviews", one = "Give a live interview", short = "Give %s interviews", shortOne = "Give an interview" },
	YachtSessions = { icon = "Yacht", title = "YACHT PARTIES", goal = "Throw %s yacht parties", one = "Throw a yacht party", short = "Throw %s yacht parties", shortOne = "Throw a yacht party" },
	JetRentals = { icon = "Jet", title = "JET FLIGHTS", goal = "Take %s private jet flights", one = "Take a private jet flight", short = "Take %s jet flights", shortOne = "Take a jet flight" },
	Sells = { icon = "Sell", title = "SELL", goal = "Sell your Bag %s times on the Sell pad", one = "Sell your Bag on the Sell pad", short = "Sell your Bag %s times", shortOne = "Sell your Bag" },
	EggsOpened = { icon = "Egg", title = "EGGS", goal = "Open %s eggs", one = "Open an egg", short = "Open %s eggs", shortOne = "Open an egg" },
	Clicks = { icon = "Click", title = "CLICKS", goal = "Click %s times", one = "Click once", short = "Click %s times", shortOne = "Click once" },
	Merges = { icon = "Merge", title = "MERGE", goal = "Merge pets or clothes %s times", one = "Merge pets or clothes once", short = "Merge %s times", shortOne = "Merge pets or clothes" },
	PlayMinutes = { icon = "Clock", title = "PLAY TIME", goal = "Play for %s minutes", one = "Play for a minute", short = "Play %s minutes", shortOne = "Play a minute" },
	BoxesOpened = { icon = "Clothes", title = "BOXES", goal = "Open %s mystery boxes", one = "Open a mystery box", short = "Open %s boxes", shortOne = "Open a box" },
	Upgrades = { icon = "Upgrades", title = "UPGRADES", goal = "Buy %s upgrades (Click or Bag)", one = "Buy an upgrade", short = "Buy %s upgrades", shortOne = "Buy an upgrade" },
	SellPets = { icon = "Pets", title = "SELL PETS", goal = "Sell %s pets", one = "Sell a pet", short = "Sell %s pets", shortOne = "Sell a pet" },
	Activities = { icon = "Trophy", title = "ACTIVITIES", goal = "Do %s activities of any kind", one = "Do an activity", short = "Do %s activities", shortOne = "Do an activity" },
	ViralInterviews = { icon = "Interview", title = "GO VIRAL", goal = "Go viral in %s interviews", one = "Go viral in an interview", short = "Go viral %s times", shortOne = "Go viral once" },
	GoldenEggs = { icon = "Egg", title = "GOLDEN EGGS", goal = "Open %s golden eggs", one = "Open a golden egg", short = "Open %s golden eggs", shortOne = "Open a golden egg" },
	AuraBar = { icon = "Aura", title = "AURA BAR", goal = "Fill the Aura bar %s times", one = "Fill the Aura bar", short = "Fill the Aura bar %s times", shortOne = "Fill the Aura bar" },
	MergeWins = { icon = "Merge", title = "LUCKY MERGE", goal = "Win %s merges", one = "Merge into Golden or Diamond", short = "Win %s merges", shortOne = "Win a merge" },
}
Quests.Info = QUESTS

-- Pasek na górze karty: zadanie w toku, gotowe do odebrania i odebrane (jak dni w nagrodzie dziennej).
local COLORS = {
	Normal = Theme.Gradients.CardBlue,
	Ready = Theme.Gradients.Gold,
	Done = Theme.Gradients.Owned,
}
local CARD_BG = {
	Normal = Theme.Gradients.Panel,
	Ready = { Color3.fromRGB(255, 249, 214), Color3.fromRGB(255, 222, 120) },
	Done = { Color3.fromRGB(240, 255, 238), Color3.fromRGB(204, 240, 198) },
}

local function questInfo(key)
	for _, quest in ipairs(Economy.Rewards.DailyQuests) do
		if quest.Key == key then
			return quest
		end
	end
	return nil
end

-- Cel zadania jako napis; short = krótsza wersja do listy na ekranie.
local function goalText(key, target, short)
	local look = QUESTS[key]
	if look == nil then
		return key
	end
	local one, many = look.one, look.goal
	if short then
		one, many = look.shortOne or one, look.short or many
	end
	if target == 1 and one ~= nil then
		return one
	end
	return string.format(many, Format.number(target))
end
Quests.goalText = goalText
Quests.questInfo = questInfo

local function clock(seconds)
	seconds = math.max(0, math.floor(seconds))
	return string.format("%02d:%02d:%02d", math.floor(seconds / 3600), math.floor(seconds % 3600 / 60), seconds % 60)
end

-- Czekamy, aż skończą się animacje nagrody (State.busy): komunikat nie ginie pod jajkiem albo boxem.
local function waitCalm()
	task.wait(0.4)
	local calm = 0
	while calm < L.BusyCalm do
		task.wait(0.1)
		if State.busy then
			calm = 0
		else
			calm = calm + 0.1
		end
	end
end

-- Ile zadań czeka na CLAIM (skończone, nieodebrane), dla kropki na zakładce.
function Quests.claimable(view)
	local quests = view and view.Quests
	local n = 0
	for _, quest in ipairs((quests and quests.List) or {}) do
		if not quest.Claimed and (quest.Progress or 0) >= (quest.Target or 1) then
			n = n + 1
		end
	end
	return n
end

-- Treść zakładki w ramce parent. helpers: width (szerokość ramki w pikselach bazowych), artFor(item)
-- i itemText(item) z Daily.luau, close() zamyka okno (gdy nagroda to jajka albo boxy).
-- Zwraca { render(force), play(bin), tick(), setActive(on) }.
function Quests.create(hud, parent, helpers)
	local count = Economy.Rewards.QuestsPerDay
	local rowW = count * L.Card.X + (count - 1) * L.CardGap
	local rowX = math.floor(((helpers.width or rowW) - rowW) / 2)

	local header = Kit.line(parent, {
		name = "QuestsHeader",
		anchor = Vector2.new(0.5, 0.5),
		position = UDim2.new(0.5, 0, 0, L.HeaderH / 2),
		height = L.HeaderH,
	})
	header.holder.ZIndex = 4
	local footer = Kit.line(parent, {
		name = "QuestsFooter",
		anchor = Vector2.new(0.5, 0.5),
		position = UDim2.new(0.5, 0, 0, L.FooterY + L.FooterH / 2),
		height = L.FooterH,
	})
	footer.holder.ZIndex = 4

	------------------------------------------------------------- Karty
	local cards = {}
	local claiming = false
	local active = false
	local renderedKey = nil
	local render -- niżej (CLAIM odświeża karty po błędzie)

	local function claim(card)
		if claiming or card.index == nil then
			return
		end
		claiming = true
		card.button.setText("...")
		local ok, result = pcall(function()
			return Net.func("ClaimQuest"):InvokeServer(card.index)
		end)
		claiming = false
		if ok and type(result) == "table" and result.Ok then
			-- komunikat przyjdzie z Notify „Reward” (po animacji); jajka i boxy grają na całym ekranie
			if ((result.Pets or 0) > 0 or (result.Items or 0) > 0) and helpers.close ~= nil then
				helpers.close()
			end
			return
		end
		Sounds.play("NotEnough")
		local reason = type(result) == "table" and result.Reason or nil
		hud.toast({ { text = TEXT[reason] or TEXT.Error, size = 26, colors = Theme.Gradients.Red } }, "QuestError")
		Kit.shake(card.button.body)
		render(true)
	end

	for i = 1, count do
		local holder = Kit.new("Frame", {
			Name = "Quest" .. i,
			Position = UDim2.fromOffset(rowX + (i - 1) * (L.Card.X + L.CardGap), L.RowY),
			Size = UDim2.fromOffset(L.Card.X, L.Card.Y),
			BackgroundTransparency = 1,
			Visible = false,
			ZIndex = 4,
			Parent = parent,
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
		local background = Kit.gradient(inner, CARD_BG.Normal, 90)
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
		-- dolne rogi paska proste (zaokrąglone są tylko górne, jak róg karty)
		local filler = Kit.new("Frame", {
			Position = UDim2.new(0, 0, 1, -16),
			Size = UDim2.new(1, 0, 0, 16),
			BackgroundColor3 = Theme.White,
			BorderSizePixel = 0,
			ZIndex = 5,
			Parent = band,
		})
		local fillerColor = Kit.gradient(filler, COLORS.Normal, 90)
		local card = {
			holder = holder,
			inner = inner,
			scale = scale,
			stroke = stroke,
			background = background,
			bandColor = bandColor,
			fillerColor = fillerColor,
			band = band,
			key = nil,
			index = nil,
		}
		card.title = Kit.text(band, {
			Name = "Title",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 50, 0.5, 1),
			Size = UDim2.new(1, -92, 0, 26),
			Text = "",
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 7,
		}, { maxSize = 22, stroke = 3 })
		card.goal = Kit.text(inner, {
			Name = "Goal",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, L.Band + 8),
			Size = UDim2.new(1, -20, 0, 46),
			Text = "",
			TextColor3 = Theme.Dark,
			TextWrapped = true,
			ZIndex = 6,
		}, { maxSize = 22, stroke = 0 })
		card.reward = Kit.text(inner, {
			Name = "Reward",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 96, 0, 118),
			Size = UDim2.new(1, -106, 0, 28),
			Text = "",
			TextColor3 = Theme.Dark,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 7,
		}, { maxSize = 24, stroke = 0 })
		card.aura = Kit.line(inner, {
			name = "Aura",
			anchor = Vector2.new(0, 0.5),
			position = UDim2.new(0, 96, 0, 148),
			height = 28,
		})
		card.aura.holder.ZIndex = 7
		-- pasek postępu (w toku i odebrane) albo CLAIM (skończone, czeka na miejsce)
		local bar = Kit.new("Frame", {
			Name = "Bar",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 182),
			Size = UDim2.fromOffset(L.Bar.X, L.Bar.Y),
			BackgroundColor3 = Color3.fromRGB(214, 218, 230),
			BorderSizePixel = 0,
			ZIndex = 6,
			Parent = inner,
		})
		Kit.corner(bar, 12)
		Kit.stroke(bar, 3, Enum.ApplyStrokeMode.Border)
		local fill = Kit.new("Frame", {
			Name = "Fill",
			Size = UDim2.fromScale(0, 1),
			BackgroundColor3 = Theme.White,
			BorderSizePixel = 0,
			Visible = false,
			ZIndex = 7,
			Parent = bar,
		})
		Kit.corner(fill, 12)
		Kit.gradient(fill, Theme.Gradients.Green, 90)
		card.bar = bar
		card.fill = fill
		card.barText = Kit.text(bar, {
			Name = "Progress",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, -16, 1, -6),
			Text = "",
			ZIndex = 8,
		}, { maxSize = 22, stroke = 3 })
		card.button = Kit.button(inner, {
			name = "Claim",
			size = L.Button,
			text = TEXT.Claim,
			colors = Theme.Gradients.Gold,
			anchor = Vector2.new(0.5, 0),
			position = UDim2.new(0.5, 0, 0, 178),
			textSize = 24,
		})
		card.button.holder.ZIndex = 8
		card.button.holder.Visible = false
		card.button.Activated:Connect(function()
			claim(card)
		end)
		card.check = Icons.make("Check", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(1, -24, 0.5, 0),
			Size = UDim2.fromOffset(30, 30),
			Visible = false,
			ZIndex = 8,
			Parent = band,
		})
		cards[i] = card
	end

	------------------------------------------------------------- Rysowanie
	-- Karta z CLAIM pulsuje, gdy zakładka jest widoczna (ten sam tween przez kolejne odświeżenia).
	local function updatePulses()
		for _, card in ipairs(cards) do
			local want = active and card.state == "Ready" and card.holder.Visible
			if want and card.pulse == nil then
				card.scale.Scale = 1
				card.pulse = TweenService:Create(card.scale, TweenInfo.new(0.55, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = 1.05 })
				card.pulse:Play()
			elseif not want and card.pulse ~= nil then
				card.pulse:Cancel()
				card.pulse = nil
				card.scale.Scale = 1
			end
		end
	end

	-- Ikona zadania i grafika nagrody zmieniają się tylko z nowym zadaniem (nowy dzień, po Rebirthie).
	local function setQuest(card, key)
		if card.key == key then
			return
		end
		card.key = key
		if card.icon ~= nil then
			card.icon:Destroy()
		end
		local look = QUESTS[key] or {}
		card.icon = Icons.make(look.icon or "Quest", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0, 28, 0.5, 0),
			Size = UDim2.fromOffset(34, 34),
			ZIndex = 7,
			Parent = card.band,
		})
		card.title.Text = look.title or key
		if card.art ~= nil then
			card.art.root:Destroy()
			card.art = nil
		end
		local info = questInfo(key)
		local item = info and info.Reward.Items[1]
		if item ~= nil then
			local kind = helpers.artFor(item)
			card.art = ShopArt.make(kind, L.Art, card.inner, { Position = UDim2.new(0, 52, 0, 132), ZIndex = 6 })
			if card.bin ~= nil then
				card.art.play(card.bin)
			end
		end
	end

	local function setState(card, state)
		card.state = state
		local band = COLORS[state] or COLORS.Normal
		card.bandColor.Color = ColorSequence.new(band[1], band[2])
		card.fillerColor.Color = ColorSequence.new(band[2], band[2])
		local bg = CARD_BG[state] or CARD_BG.Normal
		card.background.Color = ColorSequence.new(bg[1], bg[2])
		card.stroke.Thickness = (state == "Ready" and 5) or 3.5
		card.stroke.Color = (state == "Ready" and Color3.fromRGB(120, 60, 0)) or Theme.Outline
		card.check.Visible = state == "Done"
		card.bar.Visible = state ~= "Ready"
		card.button.holder.Visible = state == "Ready"
		if state == "Ready" and not claiming then
			card.button.setText(TEXT.Claim)
		end
	end

	local function renderHeader(quests)
		local list = (quests and quests.List) or {}
		if #list == 0 then
			header.set({ { icon = "Quest", size = 34 }, { text = TEXT.Loading, size = 26, colors = Theme.Gradients.Gold } })
			return
		end
		local claimed = 0
		for _, quest in ipairs(list) do
			if quest.Claimed then
				claimed = claimed + 1
			end
		end
		local bonus = quests.BonusAura or 0
		if claimed >= #list then
			if bonus > 0 and quests.Bonus then
				header.set({ { icon = "Check", size = 34 }, { text = string.format(TEXT.AllDoneAura, Format.small(bonus)), size = 26, colors = Theme.Gradients.Green } })
			else
				header.set({ { icon = "Check", size = 34 }, { text = TEXT.AllDone, size = 26, colors = Theme.Gradients.Green } })
			end
		elseif bonus > 0 then
			header.set({
				{ icon = "Aura", size = 34 },
				{ text = string.format(TEXT.HeaderAura, #list, Format.small(bonus)), size = 26, colors = Theme.Gradients.Aura },
				{ text = string.format(TEXT.HeaderCount, claimed, #list), size = 26 },
			})
		else
			header.set({ { icon = "Quest", size = 34 }, { text = TEXT.Header, size = 26, colors = Theme.Gradients.Gold } })
		end
	end

	local footerText = nil
	local secondsLeft, receivedAt = 0, os.clock()
	local function tick()
		local left = math.max(0, secondsLeft - (os.clock() - receivedAt))
		local text = TEXT.NewSoon
		if left >= 1 then
			text = string.format(TEXT.New, clock(left))
		end
		if text ~= footerText then
			footerText = text
			footer.set({ { icon = "Clock", size = 28 }, { text = text, size = 22 } })
		end
	end

	render = function(force)
		local quests = (State.view or {}).Quests
		if quests ~= nil then
			secondsLeft = quests.SecondsLeft or 0
			receivedAt = os.clock()
		end
		local parts = { tostring(quests ~= nil and quests.Bonus), tostring(quests and quests.Aura), tostring(quests and quests.BonusAura), tostring(claiming) }
		for _, quest in ipairs((quests and quests.List) or {}) do
			table.insert(parts, table.concat({ tostring(quest.Index), tostring(quest.Key), tostring(quest.Progress), tostring(quest.Claimed) }, ":"))
		end
		local key = table.concat(parts, "|")
		if key == renderedKey and not force then
			return
		end
		renderedKey = key
		renderHeader(quests)
		local list = (quests and quests.List) or {}
		local aura = (quests and quests.Aura) or 0
		for i, card in ipairs(cards) do
			local quest = list[i]
			card.holder.Visible = quest ~= nil
			if quest ~= nil then
				card.index = quest.Index
				setQuest(card, quest.Key)
				local target = math.max(1, quest.Target or 1)
				local progress = math.min(target, quest.Progress or 0)
				local state = "Normal"
				if quest.Claimed then
					state = "Done"
				elseif progress >= target then
					state = "Ready"
				end
				card.goal.Text = goalText(quest.Key, target)
				local info = questInfo(quest.Key)
				local item = info and info.Reward.Items[1]
				card.reward.Text = (item and helpers.itemText(item)) or ""
				if aura > 0 then
					card.aura.set({ { icon = "Aura", size = 26 }, { text = string.format(TEXT.Aura, Format.small(aura)), size = 22, colors = Theme.Gradients.Aura } })
					card.aura.holder.Visible = true
					card.reward.Position = UDim2.new(0, 96, 0, 116)
				else
					card.aura.holder.Visible = false
					card.reward.Position = UDim2.new(0, 96, 0, 132)
				end
				if state == "Done" then
					card.fill.Size = UDim2.fromScale(1, 1)
					card.fill.Visible = true
					card.barText.Text = TEXT.Completed
				else
					card.fill.Size = UDim2.fromScale(progress / target, 1)
					card.fill.Visible = progress > 0
					card.barText.Text = Format.number(progress) .. "/" .. Format.number(target)
				end
				setState(card, state)
			end
		end
		updatePulses()
		tick()
	end

	------------------------------------------------------------- Komunikaty
	local function auraItems(amount)
		return { { icon = "Aura", size = 36 }, { text = string.format(TEXT.Aura, Format.small(amount)), size = 26, colors = Theme.Gradients.Aura } }
	end

	local function showDone(payload)
		local pets, clothes = 0, 0
		for _, group in ipairs(payload.Eggs or {}) do
			pets = pets + #(group.Pets or {})
		end
		for _, group in ipairs(payload.Boxes or {}) do
			clothes = clothes + #(group.Items or {})
		end
		local items = { { icon = (QUESTS[payload.Key] or {}).icon or "Quest", size = 38 }, { text = TEXT.Toast, size = 26, colors = Theme.Gradients.Gold } }
		for _, item in ipairs(Codes.rewardItems({ Boosts = payload.Boosts, Pets = pets, Items = clothes })) do
			table.insert(items, item)
		end
		local aura = payload.Aura or 0
		local bonus = payload.BonusAura or 0
		if aura > 0 then
			for _, item in ipairs(auraItems(aura)) do
				table.insert(items, item)
			end
		end
		hud.toast(items)
		if aura + bonus > 0 then
			-- „+X AURA” przy liczniku Aury (HUD gra wtedy swój dźwięk)
			State.emit({ Kind = "Aura", Amount = aura + bonus, Source = "Quest" })
		else
			Sounds.play("Unlock", { volume = 0.6 })
		end
		if payload.AllDone then
			task.delay(0.7, function()
				local all = { { icon = "Trophy", size = 38 }, { text = TEXT.ToastAll, size = 26, colors = Theme.Gradients.Gold } }
				if bonus > 0 then
					for _, item in ipairs(auraItems(bonus)) do
						table.insert(all, item)
					end
				end
				hud.toast(all, "QuestsAll")
			end)
		end
	end

	State.onNotify(function(payload)
		if payload.Kind == "Reward" and payload.Source == "Quest" then
			task.spawn(function()
				waitCalm()
				showDone(payload)
			end)
		elseif payload.Kind == "QuestReady" then
			-- zadanie skończone, ale nagroda się nie mieści: czeka na CLAIM w oknie nagrody dziennej
			Sounds.play("NotEnough")
			hud.toast({
				{ icon = (QUESTS[payload.Key] or {}).icon or "Quest", size = 38 },
				{ text = TEXT.Toast, size = 26, colors = Theme.Gradients.Gold },
				{ text = TEXT.MakeRoom, size = 22, colors = Theme.Gradients.Red },
			}, "QuestReady")
		end
	end)

	------------------------------------------------------------- Dla Daily.luau
	local api = {}
	api.render = render
	api.tick = tick
	-- animacje grafik nagród przy otwartym oknie (bin sprząta Daily.luau; nil = okno zamknięte)
	function api.play(bin)
		for _, card in ipairs(cards) do
			card.bin = bin
			if card.art ~= nil and bin ~= nil then
				card.art.play(bin)
			end
		end
	end
	-- zakładka widoczna (true) albo schowana: pulsują tylko widoczne karty z CLAIM
	function api.setActive(on)
		active = on
		if on then
			render(true)
		else
			updatePulses()
		end
	end
	render(true)
	return api
end

return Quests
