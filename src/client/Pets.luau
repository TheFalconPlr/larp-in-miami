-- Pety po stronie gracza: kafelek PETS z oknem ekwipunku i pety latające za graczami.
--   • zwykły widok: kliknij peta, żeby go założyć albo zdjąć; EQUIP BEST zakłada najmocniejsze,
--   • SELL: zaznacz pety i sprzedaj je za L$ (10% ceny jajka, Golden ×5, Diamond ×25). DUPES
--     zaznacza duplikaty (z każdego rodzaju jeden zostaje), ALL wszystkie niezałożone. Sprzedaż
--     sekreta trzeba potwierdzić (dokument projektu),
--   • MERGE: zaznacz 1–5 identycznych petów (każdy daje 20% szansy, więcej z Merge Luck) i połącz
--     je w wersję Golden (z Golden: Diamond). Okno z szansą i animację robi MergeWindow,
--   • INDEX: wszystkie pety z jajek, odkryte i „???”.
-- Pety wszystkich graczy rysuje każdy klient sam, z atrybutu gracza „LarpPets” (ustawia go serwer,
-- PetService). Liczy wszystko serwer; tu jest wygląd i podgląd (szansa, opłata, cena sprzedaży).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared.Config.Economy)
local Formulas = require(Shared.Formulas)
local Format = require(Shared.Format)
local Net = require(Shared.Net)
local Loop = require(Shared.Logic.Loop)
local PetsConfig = require(Shared.Config.Pets)
local State = require(script.Parent.State)
local Theme = require(script.Parent.Ui.Theme)
local Kit = require(script.Parent.Ui.Kit)
local Sounds = require(script.Parent.Ui.Sounds)
local LocalHide = require(script.Parent.LocalHide)
local PetModels = require(script.Parent.PetModels)
local MergeWindow = require(script.Parent.MergeWindow)

local Pets = {}

local ATTRIBUTE = "LarpPets" -- jak PetService.Attribute na serwerze
local MAX_PIECES = Economy.Pets.Merge.MaxPieces

local TEXT = {
	Tile = "PETS",
	Title = "Pets",
	Equipped = "Equipped %d/%d",
	Bonus = "L$ bonus",
	EquipBest = "EQUIP BEST",
	Empty = "No pets yet! Open eggs to get some.",
	On = "ON",
	SlotsFull = "All pet slots are full",
	PowerSuffix = "% L$",
	Count = "%d/%d",
	Index = "INDEX %d/%d",
	Sell = "SELL",
	Merge = "MERGE",
	Cancel = "CANCEL",
	Back = "BACK",
	All = "ALL",
	Dupes = "DUPES",
	Auto = "AUTO",
	SellCount = "SELL (%d)",
	SellHint = "Tap pets to sell them",
	SellTotal = "You get",
	SoldOne = "Sold 1 pet for",
	SoldMany = "Sold %d pets for",
	NoDupes = "No duplicates to sell",
	UnequipSell = "Unequip this pet first to sell it",
	MergeHint = "Pick 1 to 5 identical pets",
	MergeInto = "Merge into",
	MergeEach = "Each pet adds",
	MergeEachTail = "chance",
	MergeChance = "Chance",
	MergeFee = "Fee",
	MergeMax = "Diamond pets can't be merged anymore",
	MergeFull = "You can merge up to 5 pets at once",
	MergePremium = "Premium pets merge only at 100%",
	MergeNone = "No identical pets to merge yet",
	MergePick = "Pick pets to merge first",
	ConfirmTitle = "Sell a Secret?",
	ConfirmText = "You're selling a SECRET pet: %s!",
	SecretName = "a Secret",
	ConfirmYes = "SELL IT",
	ConfirmNo = "KEEP IT",
	IndexFound = "Found",
	Secrets = "Secrets",
	Unknown = "???",
}

local PANEL_SIZE = Vector2.new(860, 520)
local PANEL_TOP = 34 -- treść okna zaczyna się tak nisko pod górną krawędzią (nad nią jest łapka i tytuł)
local HEADER_LEFT = 54 -- napis w nagłówku zaczyna się za łapką, która wystaje do 50 px w dół
local GRID_TOP = 58
local FOOTER = 62 -- miejsce na przyciski na dole okna
local GREEN = Color3.fromRGB(70, 200, 60)
local RED = Color3.fromRGB(235, 50, 70)
local PURPLE = Color3.fromRGB(176, 70, 255)
local SECRET_COLORS = { Color3.fromRGB(255, 255, 255), Color3.fromRGB(200, 170, 255) }
local CHROME_COLORS = { Color3.fromRGB(255, 255, 255), Color3.fromRGB(140, 148, 166) } -- Ultra Secret (ubrania)

local RANK = {}
for i, rarity in ipairs(Economy.Pets.RarityOrder) do
	RANK[rarity] = i
end

local inventory = {} -- lista { Id, Zone, Rarity, Level, Egg } od serwera
local byId = {} -- [id] = pet
local equipped = {} -- [id] = true
local indexFound = {} -- [„strefa:rzadkość”] = true

local function power(pet)
	return Formulas.petPower(pet.Zone, pet.Rarity, pet.Level or 0)
end

local function powerText(pet)
	return "+" .. Format.small(power(pet) * 100) .. TEXT.PowerSuffix
end

-- Napis rzadkości w kolorze rzadkości (sekret: biało-fioletowy, bo kulka jest ciemna; Ultra Secret
-- z ubrań: srebrny jak chrom).
local function rarityItem(rarity, size)
	if rarity == "Secret" then
		return { text = rarity, size = size, colors = SECRET_COLORS }
	elseif rarity == "UltraSecret" then
		return { text = PetsConfig.rarityName(rarity), size = size, colors = CHROME_COLORS }
	end
	return { text = PetsConfig.rarityName(rarity), size = size, color = PetsConfig.RarityColors[rarity] }
end
Pets.rarityItem = rarityItem
Pets.ChromeColors = CHROME_COLORS
Pets.powerText = powerText

local function sameKind(a, b)
	return a.Zone == b.Zone and a.Rarity == b.Rarity and (a.Level or 0) == (b.Level or 0)
end

local function kindKey(pet)
	return string.format("%d:%s:%d", pet.Zone, pet.Rarity, pet.Level or 0)
end

----------------------------------------------------------------- Kafelek PETS dla innych modułów
local tileRef = nil
local tileScale = nil

-- Środek kafelka PETS (AbsolutePosition w HUD, bez wcięcia na górny pasek) albo nil.
function Pets.tileCenter()
	if tileRef == nil then
		return nil
	end
	local holder = tileRef.holder
	return holder.AbsolutePosition + holder.AbsoluteSize / 2
end

-- Kafelek PETS podskakuje (np. gdy nowy pet do niego wleci).
function Pets.bump()
	if tileScale == nil then
		return
	end
	tileScale.Scale = 1.22
	TweenService:Create(tileScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

----------------------------------------------------------------- Pety latające za graczami
local followers = {} -- [gracz] = { text, list = { { model, cframe, phase, hidden } } }
local folder = nil

local function clearFollowers(entry)
	for _, pet in ipairs(entry.list) do
		pet.model:Destroy()
	end
	entry.list = {}
end

local function rebuildFollowers(player)
	local entry = followers[player]
	if entry == nil then
		entry = { text = nil, list = {} }
		followers[player] = entry
	end
	local text = player:GetAttribute(ATTRIBUTE) or ""
	if text == entry.text then
		return
	end
	entry.text = text
	clearFollowers(entry)
	for item in string.gmatch(text, "[^,]+") do
		local zone, rarity, level = string.match(item, "^(%d+):(%a+):?(%d*)")
		if zone ~= nil then
			local model = PetModels.pet(tonumber(zone), rarity, tonumber(level) or 0)
			model.Parent = folder
			table.insert(entry.list, { model = model, cframe = nil, phase = math.random() * 6.28, hidden = false })
		end
	end
end

local function watchPlayer(player)
	rebuildFollowers(player)
	player:GetAttributeChangedSignal(ATTRIBUTE):Connect(function()
		rebuildFollowers(player)
	end)
end

-- Pety w łuku za graczem, na wysokości pasa, lekko unoszą się i płynnie doganiają gracza.
local function updateFollowers(dt)
	local now = os.clock()
	local me = Players.LocalPlayer
	for player, entry in pairs(followers) do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		-- w czasie aktywności pety innych graczy znikają razem z nimi, a w czasie lotu też nasze
		-- (lecą z nami w samolocie)
		local hidden = root == nil or (State.busy and player ~= me) or (player == me and State.hidePets)
		local count = #entry.list
		for i, pet in ipairs(entry.list) do
			if hidden ~= pet.hidden then
				pet.hidden = hidden
				LocalHide.setAll(pet.model, hidden, { collide = false })
			end
			if hidden then
				pet.cframe = nil -- po powrocie (np. po odrodzeniu) pet od razu stoi przy graczu
			else
				local look = root.CFrame.LookVector
				local flat = Vector3.new(look.X, 0, look.Z)
				if flat.Magnitude < 0.01 then
					flat = Vector3.new(0, 0, -1)
				end
				flat = flat.Unit
				local slot = i - (count + 1) / 2
				local base = CFrame.lookAt(root.Position, root.Position + flat)
				local spot = base * CFrame.Angles(0, slot * 0.7, 0) * CFrame.new(0, 0, 4.5 + math.abs(slot) * 0.6)
				local position = spot.Position + Vector3.new(0, -1.2 + math.sin(now * 3 + pet.phase) * 0.25, 0)
				local goal = CFrame.lookAt(position, position + flat)
				if pet.cframe == nil then
					pet.cframe = goal
				else
					pet.cframe = pet.cframe:Lerp(goal, math.min(1, dt * 8))
				end
				pet.model:PivotTo(pet.cframe)
			end
		end
	end
end

----------------------------------------------------------------- Start
function Pets.start(hud)
	folder = Instance.new("Folder")
	folder.Name = "LarpPetsLocal"
	folder.Parent = Workspace

	for _, player in ipairs(Players:GetPlayers()) do
		watchPlayer(player)
	end
	Players.PlayerAdded:Connect(watchPlayer)
	Players.PlayerRemoving:Connect(function(player)
		local entry = followers[player]
		if entry ~= nil then
			clearFollowers(entry)
			followers[player] = nil
		end
	end)
	RunService.RenderStepped:Connect(updateFollowers)

	------------------------------------------------------------- Okno ekwipunku
	local tile = hud.addTile({
		name = "Pets",
		icon = "Pets",
		text = TEXT.Tile,
		colors = Theme.Gradients.Cyan,
		order = 3,
	})
	tileRef = tile
	tileScale = Kit.new("UIScale", { Parent = tile.body })
	local panel = Kit.panel(hud.gui, {
		name = "PetsPanel",
		size = PANEL_SIZE,
		title = TEXT.Title,
		icon = "Pets",
		padding = 30,
		top = PANEL_TOP,
		bottom = 26,
	})
	hud.registerScale(panel.holder)
	hud.addWindow(panel)
	local merger = MergeWindow.create(hud, {
		title = "Merge Pets",
		icon = "Pets",
		one = "pet",
		many = "pets",
		remote = "MergePets",
		model = function(pet)
			return PetModels.pet(pet.Zone, pet.Rarity, pet.Level)
		end,
		name = function(pet)
			return PetsConfig.fullName(pet.Zone, pet.Rarity, pet.Level)
		end,
		powerText = powerText,
		rarityItem = rarityItem,
		fromInfo = function(info)
			return { Zone = info.Zone, Rarity = info.Rarity, Level = info.Level }
		end,
		fromReply = function(reply)
			return reply.Pet or { Zone = reply.Zone, Rarity = reply.Rarity, Level = reply.Level }
		end,
		onText = "Equipped!",
		isOn = function(pet)
			return pet.Equipped == true
		end,
		tileCenter = Pets.tileCenter,
		bump = Pets.bump,
	})
	-- licznik petów obok tytułu, np. 37/250
	local countLine = Kit.line(panel.title.Parent, {
		name = "PetCount",
		anchor = Vector2.new(0, 0.5),
		position = UDim2.fromOffset(80 + Kit.measure(TEXT.Title, 56).X + 16, -2),
		height = 40,
	})
	countLine.holder.ZIndex = 6
	local header = Kit.line(panel.content, {
		anchor = Vector2.new(0, 0),
		position = UDim2.fromOffset(HEADER_LEFT, 0),
		height = 46,
	})
	local footer = Kit.line(panel.content, {
		anchor = Vector2.new(0, 0.5),
		position = UDim2.new(0, 4, 1, -26),
		height = 46,
	})

	local function button(name, width, text, colors, anchor, position)
		return Kit.button(panel.content, {
			name = name,
			size = Vector2.new(width, 46),
			text = text,
			colors = colors,
			anchor = anchor,
			position = position,
			textSize = 22,
		})
	end
	local TOP_RIGHT, BOTTOM_RIGHT, BOTTOM_LEFT = Vector2.new(1, 0), Vector2.new(1, 1), Vector2.new(0, 1)
	-- nagłówek po prawej: EQUIP BEST, przy sprzedaży DUPES i ALL, przy łączeniu AUTO
	local bestButton = button("EquipBest", 190, TEXT.EquipBest, Theme.Gradients.Green, TOP_RIGHT, UDim2.new(1, 0, 0, 0))
	local allButton = button("All", 100, TEXT.All, Theme.Gradients.Cyan, TOP_RIGHT, UDim2.new(1, 0, 0, 0))
	local dupesButton = button("Dupes", 130, TEXT.Dupes, Theme.Gradients.Cyan, TOP_RIGHT, UDim2.new(1, -112, 0, 0))
	local autoButton = button("Auto", 130, TEXT.Auto, Theme.Gradients.Cyan, TOP_RIGHT, UDim2.new(1, 0, 0, 0))
	-- stopka: INDEX po lewej, MERGE i SELL po prawej; w trybach CANCEL i przycisk potwierdzenia
	local indexButton = button("Index", 200, string.format(TEXT.Index, 0, 0), Theme.Gradients.Cyan, BOTTOM_LEFT, UDim2.new(0, 0, 1, 0))
	local sellButton = button("Sell", 140, TEXT.Sell, Theme.Gradients.Yellow, BOTTOM_RIGHT, UDim2.new(1, 0, 1, 0))
	local mergeButton = button("Merge", 160, TEXT.Merge, Theme.Gradients.Pink, BOTTOM_RIGHT, UDim2.new(1, -152, 1, 0))
	local confirmButton = button("Confirm", 190, "", Theme.Gradients.Gray, BOTTOM_RIGHT, UDim2.new(1, 0, 1, 0))
	local cancelButton = button("Cancel", 150, TEXT.Cancel, Theme.Gradients.Gray, BOTTOM_RIGHT, UDim2.new(1, -202, 1, 0))
	local backButton = button("Back", 150, TEXT.Back, Theme.Gradients.Gray, BOTTOM_RIGHT, UDim2.new(1, 0, 1, 0))

	local function scroller(name)
		local frame = Kit.new("ScrollingFrame", {
			Name = name,
			Position = UDim2.fromOffset(0, GRID_TOP),
			Size = UDim2.new(1, 0, 1, -GRID_TOP - FOOTER),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ScrollBarThickness = 8,
			ScrollBarImageColor3 = Theme.Outline,
			ScrollingDirection = Enum.ScrollingDirection.Y,
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			CanvasSize = UDim2.new(0, 0, 0, 0),
			ZIndex = 3,
			Parent = panel.content,
		})
		Kit.new("UIPadding", {
			PaddingTop = UDim.new(0, 6),
			PaddingLeft = UDim.new(0, 6),
			PaddingRight = UDim.new(0, 12),
			PaddingBottom = UDim.new(0, 6),
			Parent = frame,
		})
		return frame
	end
	local grid = scroller("Grid")
	Kit.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(118, 150),
		CellPadding = UDim2.fromOffset(10, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = grid,
	})
	local indexFrame = scroller("Index")
	indexFrame.Visible = false
	Kit.new("UIListLayout", {
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = indexFrame,
	})
	local emptyLabel = Kit.text(panel.content, {
		Name = "Empty",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.fromOffset(560, 40),
		Text = TEXT.Empty,
		Visible = false,
		ZIndex = 4,
	}, { maxSize = 28, stroke = 3 })

	------------------------------------------------------------- Potwierdzenie sprzedaży sekreta
	local confirm = Kit.panel(hud.gui, {
		name = "SellSecret",
		size = Vector2.new(640, 270),
		title = TEXT.ConfirmTitle,
		padding = 30,
		top = 44,
		bottom = 24,
	})
	confirm.holder.ZIndex = 5
	hud.registerScale(confirm.holder)
	local confirmLine = Kit.line(confirm.content, {
		anchor = Vector2.new(0.5, 0.5),
		position = UDim2.new(0.5, 0, 0, 40),
		height = 40,
	})
	local confirmSub = Kit.line(confirm.content, {
		anchor = Vector2.new(0.5, 0.5),
		position = UDim2.new(0.5, 0, 0, 84),
		height = 36,
	})
	local keepButton = Kit.button(confirm.content, {
		name = "Keep",
		size = Vector2.new(200, 52),
		text = TEXT.ConfirmNo,
		colors = Theme.Gradients.Green,
		anchor = Vector2.new(0.5, 1),
		position = UDim2.new(0.5, -115, 1, 0),
		textSize = 24,
	})
	local sellSecretButton = Kit.button(confirm.content, {
		name = "SellIt",
		size = Vector2.new(200, 52),
		text = TEXT.ConfirmYes,
		colors = Theme.Gradients.Red,
		anchor = Vector2.new(0.5, 1),
		position = UDim2.new(0.5, 115, 1, 0),
		textSize = 24,
	})
	local onConfirm = nil

	------------------------------------------------------------- Stan okna
	local busy = false
	local mode = "pets" -- pets, sell, merge, index
	local selected = {} -- [id] = true (sprzedaż albo łączenie)
	local mergeOrder = {} -- id do łączenia w kolejności wybierania
	local cards = {} -- [id] = { pet, stroke, mark, markLabel, dim, power, value }

	local function selectedIds()
		local ids = {}
		if mode == "merge" then
			for _, id in ipairs(mergeOrder) do
				table.insert(ids, id)
			end
			return ids
		end
		for _, pet in ipairs(inventory) do
			if selected[pet.Id] then
				table.insert(ids, pet.Id)
			end
		end
		return ids
	end

	local function clearSelection()
		selected = {}
		mergeOrder = {}
	end

	-- Podgląd łączenia z danych klienta (serwer i tak liczy sam): { Chance, Fee, Level, … } albo nil i powód.
	local function mergeInfo()
		if #mergeOrder == 0 then
			return nil, "None"
		end
		local view = State.view or {}
		local data = { Pets = byId, AuraUpgrades = { MergeLuck = view.MergeLuck or 0 } }
		return Loop.mergeInfo(data, mergeOrder)
	end

	-- Czy peta można dodać do łączenia (Diamond już nie; z wybranymi musi być identyczny).
	local function canJoin(pet)
		if (pet.Level or 0) >= 2 then
			return false
		end
		if #mergeOrder == 0 then
			return true
		end
		local first = byId[mergeOrder[1]]
		return first ~= nil and sameKind(first, pet)
	end

	-- Wygląd karty: zielona ramka i ON (założony), czerwona ramka i X (do sprzedaży), fioletowa ramka
	-- i numer (do łączenia). Pety, których w danym trybie nie da się wybrać, są przygaszone.
	local function paintCard(id)
		local card = cards[id]
		if card == nil then
			return
		end
		local pet = card.pet
		local on = equipped[id] == true
		local color, thickness = Theme.Outline, 3
		local markColor, markText = nil, nil
		local dim = false
		if on then
			color, thickness = GREEN, 5
		end
		if mode == "sell" then
			dim = on
			if selected[id] then
				color, thickness = RED, 5
				markColor, markText = RED, "X"
			end
		elseif mode == "merge" then
			if selected[id] then
				color, thickness = PURPLE, 5
				markColor = PURPLE
				for i, other in ipairs(mergeOrder) do
					if other == id then
						markText = tostring(i)
					end
				end
			else
				dim = not canJoin(pet)
			end
		end
		card.stroke.Color = color
		card.stroke.Thickness = thickness
		card.mark.Visible = markText ~= nil
		if markText ~= nil then
			card.mark.BackgroundColor3 = markColor
			card.markLabel.Text = markText
		end
		card.dim.Visible = dim
		card.power.Visible = mode ~= "sell"
		card.value.holder.Visible = mode == "sell"
	end

	local function paintAll()
		for id in pairs(cards) do
			paintCard(id)
		end
	end

	-- tylko pety, które są w indeksie (bez Mythic, który jest tylko w jajkach premium)
	local function indexCount()
		return Loop.indexCount({ Index = indexFound })
	end

	local function secretsFound()
		local n, total = 0, 0
		for zone in ipairs(Economy.Pets.Eggs) do
			total = total + 1
			if indexFound[Loop.indexKey(zone, "Secret")] then
				n = n + 1
			end
		end
		return n, total
	end

	-- Nagłówek, stopka i przyciski dla obecnego trybu.
	local function renderBars()
		local view = State.view or {}
		local inMode = mode == "sell" or mode == "merge"
		bestButton.holder.Visible = mode == "pets"
		allButton.holder.Visible = mode == "sell"
		dupesButton.holder.Visible = mode == "sell"
		autoButton.holder.Visible = mode == "merge"
		indexButton.holder.Visible = mode == "pets"
		sellButton.holder.Visible = mode == "pets"
		mergeButton.holder.Visible = mode == "pets"
		cancelButton.holder.Visible = inMode
		confirmButton.holder.Visible = inMode
		backButton.holder.Visible = mode == "index"
		grid.Visible = mode ~= "index"
		indexFrame.Visible = mode == "index"
		emptyLabel.Visible = mode ~= "index" and #inventory == 0
		indexButton.setText(string.format(TEXT.Index, indexCount(), Loop.indexTotal()))

		if mode == "pets" then
			header.set({
				{ text = string.format(TEXT.Equipped, view.PetsEquipped or 0, view.PetSlots or 3), size = 26 },
				{ text = TEXT.Bonus, size = 24 },
				{ text = "×" .. Format.small(view.PetLayer or 1), size = 28, colors = Theme.Gradients.Gold },
			})
			footer.set({})
		elseif mode == "sell" then
			local ids = selectedIds()
			local cash = 0
			for _, id in ipairs(ids) do
				cash = cash + Loop.petSellValue(byId[id])
			end
			header.set({ { text = TEXT.SellHint, size = 24 } })
			footer.set({
				{ text = TEXT.SellTotal, size = 24 },
				{ icon = "Cash", size = 34 },
				{ text = Format.number(cash), size = 26, colors = Theme.Gradients.Gold },
			})
			confirmButton.setText(string.format(TEXT.SellCount, #ids))
			if #ids > 0 then
				confirmButton.setColors(Theme.Gradients.Green)
			else
				confirmButton.setColors(Theme.Gradients.Gray)
			end
		elseif mode == "merge" then
			local info, reason = mergeInfo()
			confirmButton.setText(TEXT.Merge)
			if info ~= nil then
				confirmButton.setColors(Theme.Gradients.Pink)
				header.set({
					{ text = TEXT.MergeInto, size = 24 },
					{
						text = PetsConfig.fullName(info.Zone, info.Rarity, info.Level),
						size = 26,
						colors = PetsConfig.LevelColors[info.Level] or Theme.Gradients.Gold,
					},
				})
				local feeColors = Theme.Gradients.Gold
				if (view.Cash or 0) < info.Fee then
					feeColors = Theme.Gradients.Red
				end
				footer.set({
					{ text = TEXT.MergeChance, size = 22 },
					{ text = Format.percent(info.Chance), size = 28, colors = MergeWindow.chanceColors(info.Chance) },
					{ text = TEXT.MergeFee, size = 22 },
					{ icon = "Cash", size = 32 },
					{ text = Format.number(info.Fee), size = 26, colors = feeColors },
				})
			else
				confirmButton.setColors(Theme.Gradients.Gray)
				if reason == "Premium" then
					header.set({ { text = TEXT.MergeHint, size = 24 } })
					footer.set({ { text = TEXT.MergePremium, size = 22, colors = Theme.Gradients.Red } })
				else
					header.set({ { text = TEXT.MergeHint, size = 24 } })
					footer.set({
						{ text = TEXT.MergeEach, size = 22 },
						{ text = Format.percent(merger.chancePerPiece()), size = 26, colors = Theme.Gradients.Gold },
						{ text = TEXT.MergeEachTail, size = 22 },
					})
				end
			end
		else
			local secrets, zones = secretsFound()
			header.set({
				{ text = TEXT.IndexFound, size = 26 },
				{ text = string.format(TEXT.Count, indexCount(), Loop.indexTotal()), size = 28, colors = Theme.Gradients.Gold },
			})
			footer.set({
				{ text = TEXT.Secrets, size = 24 },
				{ text = string.format(TEXT.Count, secrets, zones), size = 26, colors = SECRET_COLORS },
			})
		end

		local count = view.PetCount or #inventory
		local colors = Theme.Gradients.Gold
		if count >= PetsConfig.MaxInventory then
			colors = Theme.Gradients.Red
		end
		countLine.set({ { text = string.format(TEXT.Count, count, PetsConfig.MaxInventory), size = 30, colors = colors } })
	end

	local function setMode(newMode)
		mode = newMode
		clearSelection()
		confirm.hide()
		paintAll()
		renderBars()
	end

	local function deny(text, key)
		Sounds.play("NotEnough")
		hud.toast({ { text = text, size = 26, colors = Theme.Gradients.Red } }, key)
	end

	local function toggle(pet)
		if busy then
			return
		end
		busy = true
		local ok, result = pcall(function()
			return Net.func("EquipPet"):InvokeServer(pet.Id, not equipped[pet.Id])
		end)
		busy = false
		if ok and type(result) == "table" and not result.Ok and result.Reason == "SlotsFull" then
			deny(TEXT.SlotsFull, "PetSlotsFull")
		elseif ok and type(result) == "table" and result.Ok then
			Sounds.play("Button")
		end
	end

	local function onCardClicked(pet)
		if mode == "pets" then
			toggle(pet)
			return
		end
		if mode == "sell" then
			if equipped[pet.Id] then
				deny(TEXT.UnequipSell, "PetUnequipFirst")
				return
			end
			if selected[pet.Id] then
				selected[pet.Id] = nil
			else
				selected[pet.Id] = true
			end
			Sounds.play("Button")
			paintCard(pet.Id)
			renderBars()
			return
		end
		if mode ~= "merge" then
			return
		end
		if (pet.Level or 0) >= 2 then
			deny(TEXT.MergeMax, "MergeMax")
			return
		end
		if selected[pet.Id] then
			selected[pet.Id] = nil
			for i = #mergeOrder, 1, -1 do
				if mergeOrder[i] == pet.Id then
					table.remove(mergeOrder, i)
				end
			end
		else
			if not canJoin(pet) then
				-- inny rodzaj peta: zaczynamy wybierać od nowa
				clearSelection()
			end
			if #mergeOrder >= MAX_PIECES then
				deny(TEXT.MergeFull, "MergeFull")
				return
			end
			selected[pet.Id] = true
			table.insert(mergeOrder, pet.Id)
		end
		Sounds.play("Button")
		paintAll()
		renderBars()
	end

	local function makeCard(pet, order)
		local level = pet.Level or 0
		local card = Kit.new("TextButton", {
			Name = "Pet" .. pet.Id,
			LayoutOrder = order,
			BackgroundColor3 = Theme.White,
			AutoButtonColor = false,
			Text = "",
			ZIndex = 4,
			Parent = grid,
		})
		Kit.corner(card, 18)
		local stroke = Kit.stroke(card, 3, Enum.ApplyStrokeMode.Border)
		-- tło za petem w kolorze rzadkości (jak w panelu nad jajkiem), a Golden i Diamond w kolorze poziomu
		local color = PetsConfig.RarityColors[pet.Rarity] or Theme.White
		local tile = Kit.new("Frame", {
			Name = "RarityTile",
			Position = UDim2.fromOffset(8, 8),
			Size = UDim2.new(1, -16, 0, 72),
			BackgroundColor3 = color:Lerp(Theme.White, 0.65),
			BorderSizePixel = 0,
			ZIndex = 4,
			Parent = card,
		})
		Kit.corner(tile, 14)
		local levelColors = PetsConfig.LevelColors[level]
		if levelColors ~= nil then
			tile.BackgroundColor3 = Theme.White
			Kit.gradient(tile, levelColors, 90)
		end
		local viewport = Kit.new("ViewportFrame", {
			Position = UDim2.fromOffset(6, 4),
			Size = UDim2.new(1, -12, 0, 78),
			BackgroundTransparency = 1,
			Ambient = Color3.fromRGB(200, 200, 210),
			LightColor = Color3.new(1, 1, 1),
			ZIndex = 5,
			Parent = card,
		})
		PetModels.show(viewport, PetModels.pet(pet.Zone, pet.Rarity, level))
		-- wstążka GOLDEN / DIAMOND w lewym górnym rogu
		if levelColors ~= nil then
			local ribbon = Kit.new("Frame", {
				Name = "Level",
				Position = UDim2.fromOffset(4, 4),
				Size = UDim2.fromOffset(70, 20),
				BackgroundColor3 = Theme.White,
				ZIndex = 6,
				Parent = card,
			})
			Kit.corner(ribbon, 10)
			Kit.stroke(ribbon, 2.5, Enum.ApplyStrokeMode.Border)
			Kit.gradient(ribbon, levelColors, 90)
			Kit.text(ribbon, {
				Size = UDim2.fromScale(1, 1),
				Text = string.upper(PetsConfig.LevelNames[level]),
				ZIndex = 7,
			}, { maxSize = 13, stroke = 2 })
		end
		Kit.text(card, {
			Position = UDim2.fromOffset(4, 82),
			Size = UDim2.new(1, -8, 0, 22),
			Text = PetsConfig.name(pet.Zone, pet.Rarity),
			ZIndex = 5,
		}, { maxSize = 18, stroke = 2.5 })
		local rarity = rarityItem(pet.Rarity, 15)
		Kit.text(card, {
			Position = UDim2.fromOffset(4, 104),
			Size = UDim2.new(1, -8, 0, 18),
			Text = rarity.text,
			TextColor3 = rarity.color or Theme.White,
			ZIndex = 5,
		}, { maxSize = 15, stroke = 2.5, gradient = rarity.colors })
		local powerLabel = Kit.text(card, {
			Position = UDim2.fromOffset(4, 124),
			Size = UDim2.new(1, -8, 0, 20),
			Text = powerText(pet),
			ZIndex = 5,
		}, { maxSize = 16, stroke = 2.5, gradient = Theme.Gradients.Gold })
		-- w trybie SELL zamiast mocy: ile L$ za peta
		local value = Kit.line(card, {
			anchor = Vector2.new(0.5, 0.5),
			position = UDim2.new(0.5, 0, 0, 134),
			height = 22,
			gap = 3,
			items = {
				{ icon = "Cash", size = 20 },
				{ text = Format.number(Loop.petSellValue(pet)), size = 16, colors = Theme.Gradients.Gold },
			},
		})
		value.holder.ZIndex = 5
		value.holder.Visible = false
		if equipped[pet.Id] then
			local badge = Kit.new("Frame", {
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -4, 0, 4),
				Size = UDim2.fromOffset(38, 22),
				BackgroundColor3 = GREEN,
				ZIndex = 6,
				Parent = card,
			})
			Kit.corner(badge, 11)
			Kit.stroke(badge, 2.5, Enum.ApplyStrokeMode.Border)
			Kit.text(badge, { Size = UDim2.fromScale(1, 1), Text = TEXT.On, ZIndex = 7 }, { maxSize = 14, stroke = 2 })
		end
		-- znak wyboru: czerwony X (sprzedaż) albo fioletowy numer (łączenie)
		local mark = Kit.new("Frame", {
			Name = "Mark",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -4, 0, 4),
			Size = UDim2.fromOffset(28, 28),
			BackgroundColor3 = RED,
			Visible = false,
			ZIndex = 8,
			Parent = card,
		})
		Kit.corner(mark, 14)
		Kit.stroke(mark, 2.5, Enum.ApplyStrokeMode.Border)
		local markLabel = Kit.text(mark, { Size = UDim2.fromScale(1, 1), Text = "X", ZIndex = 9 }, { maxSize = 18, stroke = 2 })
		-- przygaszenie petów, których w tym trybie nie da się wybrać
		local dim = Kit.new("Frame", {
			Name = "Dim",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Theme.White,
			BackgroundTransparency = 0.4,
			Visible = false,
			ZIndex = 10,
			Parent = card,
		})
		Kit.corner(dim, 18)
		cards[pet.Id] = {
			pet = pet,
			stroke = stroke,
			mark = mark,
			markLabel = markLabel,
			dim = dim,
			power = powerLabel,
			value = value,
		}
		paintCard(pet.Id)
		card.Activated:Connect(function()
			onCardClicked(pet)
		end)
	end

	-- Wybór zostaje tylko dla petów, które dalej są w ekwipunku (i przy sprzedaży nie są założone).
	local function pruneSelection()
		local still = {}
		for id in pairs(selected) do
			if byId[id] ~= nil and not (mode == "sell" and equipped[id]) then
				still[id] = true
			end
		end
		selected = still
		local order = {}
		for _, id in ipairs(mergeOrder) do
			local pet = byId[id]
			if still[id] and pet ~= nil and (#order == 0 or sameKind(byId[order[1]], pet)) then
				table.insert(order, id)
			end
		end
		mergeOrder = order
		if mode == "merge" then
			selected = {}
			for _, id in ipairs(mergeOrder) do
				selected[id] = true
			end
		end
	end

	local function renderGrid()
		for _, child in ipairs(grid:GetChildren()) do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		cards = {}
		-- wyposażone najpierw, potem od najmocniejszego; identyczne pety obok siebie
		local sorted = {}
		for _, pet in ipairs(inventory) do
			table.insert(sorted, pet)
		end
		table.sort(sorted, function(a, b)
			local ea, eb = equipped[a.Id] == true, equipped[b.Id] == true
			if ea ~= eb then
				return ea
			end
			local pa, pb = power(a), power(b)
			if pa ~= pb then
				return pa > pb
			end
			if a.Zone ~= b.Zone then
				return a.Zone > b.Zone
			end
			if a.Rarity ~= b.Rarity then
				return (RANK[a.Rarity] or 0) > (RANK[b.Rarity] or 0)
			end
			if (a.Level or 0) ~= (b.Level or 0) then
				return (a.Level or 0) > (b.Level or 0)
			end
			return (tonumber(a.Id) or 0) < (tonumber(b.Id) or 0)
		end)
		for i, pet in ipairs(sorted) do
			makeCard(pet, i)
		end
	end

	------------------------------------------------------------- Indeks
	local function makeIndexCard(parent, zone, rarity, order)
		local found = indexFound[Loop.indexKey(zone, rarity)] == true
		local color = PetsConfig.RarityColors[rarity] or Theme.White
		local card = Kit.new("Frame", {
			Name = rarity,
			LayoutOrder = order,
			Size = UDim2.fromOffset(104, 118),
			BackgroundColor3 = Theme.White,
			BorderSizePixel = 0,
			ZIndex = 4,
			Parent = parent,
		})
		Kit.corner(card, 16)
		Kit.stroke(card, 3, Enum.ApplyStrokeMode.Border)
		local tile = Kit.new("Frame", {
			Position = UDim2.fromOffset(7, 7),
			Size = UDim2.new(1, -14, 0, 60),
			BackgroundColor3 = color:Lerp(Theme.White, 0.65),
			BorderSizePixel = 0,
			ZIndex = 4,
			Parent = card,
		})
		Kit.corner(tile, 12)
		local viewport = Kit.new("ViewportFrame", {
			Position = UDim2.fromOffset(6, 3),
			Size = UDim2.new(1, -12, 0, 66),
			BackgroundTransparency = 1,
			Ambient = Color3.fromRGB(200, 200, 210),
			LightColor = Color3.new(1, 1, 1),
			ZIndex = 5,
			Parent = card,
		})
		PetModels.show(viewport, PetModels.pet(zone, rarity, 0))
		local name = PetsConfig.name(zone, rarity)
		if not found then
			-- nieodkryty: czarna sylwetka i „???”
			tile.BackgroundColor3 = Color3.fromRGB(214, 216, 226)
			viewport.ImageColor3 = Color3.new(0, 0, 0)
			viewport.ImageTransparency = 0.1
			name = TEXT.Unknown
		end
		Kit.text(card, {
			Position = UDim2.fromOffset(4, 70),
			Size = UDim2.new(1, -8, 0, 22),
			Text = name,
			ZIndex = 5,
		}, { maxSize = 16, stroke = 2.5 })
		local item = rarityItem(rarity, 14)
		Kit.text(card, {
			Position = UDim2.fromOffset(4, 94),
			Size = UDim2.new(1, -8, 0, 17),
			Text = item.text,
			TextColor3 = item.color or Theme.White,
			ZIndex = 5,
		}, { maxSize = 14, stroke = 2.5, gradient = item.colors })
	end

	local function renderIndex()
		for _, child in ipairs(indexFrame:GetChildren()) do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		for zone in ipairs(Economy.Pets.Eggs) do
			local row = Kit.new("Frame", {
				Name = "Zone" .. zone,
				LayoutOrder = zone,
				Size = UDim2.new(1, 0, 0, 156),
				BackgroundTransparency = 1,
				Parent = indexFrame,
			})
			local zoneInfo = Economy.Zones[zone]
			local rarities = Loop.indexRarities(zone)
			local found = 0
			for _, rarity in ipairs(rarities) do
				if indexFound[Loop.indexKey(zone, rarity)] then
					found = found + 1
				end
			end
			Kit.line(row, {
				anchor = Vector2.new(0, 0.5),
				position = UDim2.fromOffset(4, 16),
				height = 32,
				items = {
					{ text = (zoneInfo and zoneInfo.Name) or ("Zone " .. zone), size = 24 },
					{ text = string.format(TEXT.Count, found, #rarities), size = 22, colors = Theme.Gradients.Gold },
				},
			})
			local cardsRow = Kit.new("Frame", {
				Position = UDim2.fromOffset(0, 34),
				Size = UDim2.new(1, 0, 0, 120),
				BackgroundTransparency = 1,
				Parent = row,
			})
			Kit.new("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				Padding = UDim.new(0, 7),
				SortOrder = Enum.SortOrder.LayoutOrder,
				Parent = cardsRow,
			})
			for i, rarity in ipairs(rarities) do
				makeIndexCard(cardsRow, zone, rarity, i)
			end
		end
	end

	------------------------------------------------------------- Przyciski
	tile.Activated:Connect(function()
		if panel.isOpen() then
			panel.hide()
			confirm.hide()
		else
			mode = "pets"
			clearSelection()
			renderGrid()
			renderBars()
			hud.openWindow(panel)
		end
	end)

	bestButton.Activated:Connect(function()
		if busy then
			return
		end
		busy = true
		pcall(function()
			Net.func("EquipBest"):InvokeServer()
		end)
		busy = false
	end)

	sellButton.Activated:Connect(function()
		setMode("sell")
	end)
	mergeButton.Activated:Connect(function()
		setMode("merge")
	end)
	cancelButton.Activated:Connect(function()
		setMode("pets")
	end)
	indexButton.Activated:Connect(function()
		setMode("index")
		renderIndex()
	end)
	backButton.Activated:Connect(function()
		setMode("pets")
	end)

	-- ALL: zaznacza wszystkie niezałożone pety (drugi raz odznacza)
	allButton.Activated:Connect(function()
		local all = {}
		local everything = true
		for _, pet in ipairs(inventory) do
			if not equipped[pet.Id] then
				all[pet.Id] = true
				if not selected[pet.Id] then
					everything = false
				end
			end
		end
		if everything then
			selected = {}
		else
			selected = all
		end
		paintAll()
		renderBars()
	end)

	-- DUPES: z każdego rodzaju (strefa, rzadkość, poziom) zostaje jeden pet (założony albo najstarszy),
	-- a pozostałe niezałożone idą do sprzedaży. Sekretów nie zaznacza.
	dupesButton.Activated:Connect(function()
		local groups = {}
		for _, pet in ipairs(inventory) do
			local key = kindKey(pet)
			if groups[key] == nil then
				groups[key] = {}
			end
			table.insert(groups[key], pet)
		end
		selected = {}
		local any = false
		for _, list in pairs(groups) do
			if #list > 1 and list[1].Rarity ~= "Secret" then
				local keep = nil
				for _, pet in ipairs(list) do
					if equipped[pet.Id] then
						keep = pet
					end
				end
				if keep == nil then
					table.sort(list, function(a, b)
						return (tonumber(a.Id) or 0) < (tonumber(b.Id) or 0)
					end)
					keep = list[1]
				end
				for _, pet in ipairs(list) do
					if pet ~= keep and not equipped[pet.Id] then
						selected[pet.Id] = true
						any = true
					end
				end
			end
		end
		if not any then
			deny(TEXT.NoDupes, "NoDupes")
		end
		paintAll()
		renderBars()
	end)

	-- AUTO: dobiera identyczne pety do 5 (najpierw niezałożone). Bez wyboru bierze rodzaj, którego
	-- gracz ma najwięcej sztuk.
	autoButton.Activated:Connect(function()
		local kind = nil
		if #mergeOrder > 0 then
			kind = byId[mergeOrder[1]]
		else
			local counts = {}
			for _, pet in ipairs(inventory) do
				if (pet.Level or 0) < 2 then
					local key = kindKey(pet)
					counts[key] = (counts[key] or 0) + 1
				end
			end
			local best, bestCount = nil, 1
			for _, pet in ipairs(inventory) do
				local n = counts[kindKey(pet)]
				if n ~= nil and (n > bestCount or (n == bestCount and best ~= nil and power(pet) > power(best))) then
					best, bestCount = pet, n
				end
			end
			kind = best
		end
		if kind == nil then
			deny(TEXT.MergeNone, "MergeNone")
			return
		end
		local candidates = {}
		for _, pet in ipairs(inventory) do
			if sameKind(pet, kind) and not selected[pet.Id] then
				table.insert(candidates, pet)
			end
		end
		table.sort(candidates, function(a, b)
			local ea, eb = equipped[a.Id] == true, equipped[b.Id] == true
			if ea ~= eb then
				return eb
			end
			return (tonumber(a.Id) or 0) < (tonumber(b.Id) or 0)
		end)
		for _, pet in ipairs(candidates) do
			if #mergeOrder >= MAX_PIECES then
				break
			end
			selected[pet.Id] = true
			table.insert(mergeOrder, pet.Id)
		end
		paintAll()
		renderBars()
	end)

	-- Okienko „na pewno?” przed sprzedażą sekreta. pet może być nil (wtedy bez nazwy).
	local sell
	local function askSecret(pet)
		local name = TEXT.SecretName
		if pet ~= nil then
			name = PetsConfig.fullName(pet.Zone, pet.Rarity, pet.Level)
		end
		confirmLine.set({ { text = string.format(TEXT.ConfirmText, name), size = 24 } })
		confirmSub.set({ { text = Format.oneIn(Economy.Pets.SecretChance), size = 26, colors = SECRET_COLORS } })
		onConfirm = function()
			sell(true)
		end
		confirm.open()
	end

	-- Sprzedaż zaznaczonych. Sekret: najpierw okienko „na pewno?”, potem serwer dostaje confirm.
	sell = function(sure)
		if busy then
			return
		end
		local ids = selectedIds()
		if #ids == 0 then
			Sounds.play("NotEnough")
			return
		end
		if not sure then
			for _, id in ipairs(ids) do
				local pet = byId[id]
				if pet ~= nil and pet.Rarity == "Secret" then
					askSecret(pet)
					return
				end
			end
		end
		busy = true
		local ok, result = pcall(function()
			return Net.func("SellPets"):InvokeServer(ids, sure == true)
		end)
		busy = false
		if not ok or type(result) ~= "table" then
			return
		end
		if result.Ok then
			Sounds.play("Sell")
			local text = string.format(TEXT.SoldMany, result.Count or #ids)
			if result.Count == 1 then
				text = TEXT.SoldOne
			end
			hud.toast({
				{ icon = "Sell", size = 44 },
				{ text = text, size = 26 },
				{ icon = "Cash", size = 38 },
				{ text = Format.number(result.Cash or 0), size = 28, colors = Theme.Gradients.Gold },
			})
			hud.cashGain(result.Cash or 0)
			clearSelection()
			paintAll()
			renderBars()
		elseif result.Reason == "ConfirmSecret" then
			askSecret(nil)
		end
	end

	keepButton.Activated:Connect(function()
		onConfirm = nil
		confirm.hide()
	end)
	sellSecretButton.Activated:Connect(function()
		local fn = onConfirm
		onConfirm = nil
		confirm.hide()
		if fn ~= nil then
			fn()
		end
	end)

	confirmButton.Activated:Connect(function()
		if mode == "sell" then
			sell(false)
			return
		end
		if mode ~= "merge" or merger.isOpen() then
			return
		end
		local info, reason = mergeInfo()
		if info == nil then
			if reason == "Premium" then
				deny(TEXT.MergePremium, "MergePremium")
			else
				deny(TEXT.MergePick, "MergePick")
			end
			return
		end
		local pets = {}
		for _, id in ipairs(mergeOrder) do
			table.insert(pets, byId[id])
		end
		merger.open(pets, info, function(result)
			if result ~= nil and result.Ok then
				clearSelection()
			end
			pruneSelection()
			paintAll()
			renderBars()
		end)
	end)

	panel.close.Activated:Connect(function()
		mode = "pets"
		clearSelection()
		confirm.hide()
	end)
	panel.holder:GetPropertyChangedSignal("Visible"):Connect(function()
		if not panel.holder.Visible then
			confirm.hide()
		end
	end)

	State.onNotify(function(payload)
		if payload.Kind ~= "Pets" or type(payload.Pets) ~= "table" then
			return
		end
		inventory = payload.Pets
		byId = {}
		for _, pet in ipairs(inventory) do
			byId[pet.Id] = pet
		end
		equipped = {}
		for _, id in ipairs(payload.Equipped or {}) do
			equipped[id] = true
		end
		if type(payload.Index) == "table" then
			indexFound = {}
			for _, key in ipairs(payload.Index) do
				indexFound[key] = true
			end
		end
		pruneSelection()
		if panel.isOpen() then
			if mode == "index" then
				renderIndex()
			else
				renderGrid()
			end
			renderBars()
		end
	end)

	State.onChange(function(view)
		if panel.isOpen() then
			renderBars()
		end
		-- czerwona kropka: wolny slot, a są pety do założenia
		local free = (view.PetSlots or 3) - (view.PetsEquipped or 0)
		if free > 0 and (view.PetCount or 0) > (view.PetsEquipped or 0) then
			tile.badge.set("!")
		else
			tile.badge.set(nil)
		end
	end)
end

return Pets
