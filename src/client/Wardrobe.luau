-- Okno CLOTHES (Etap 8): ubrania gracza. Po lewej 7 kategorii z tym, co masz na sobie (kliknij
-- kategorię, żeby zobaczyć tylko jej ubrania), po prawej wszystkie ubrania.
--   • zwykły widok: kliknij ubranie, żeby je założyć (zastępuje to z tej samej kategorii) albo zdjąć;
--     WEAR BEST zakłada najlepsze; AVATAR ON/OFF chowa ubrania z gry na postaci (bonus zostaje),
--   • SELL: jak u petów (10% ceny boxa, Golden ×5, Diamond ×25; DUPES i ALL),
--   • MERGE: 1–5 identycznych ubrań (kategoria, rzadkość, poziom) w wersję Golden albo Diamond
--     (okno i animacja w MergeWindow).
-- Liczy wszystko serwer (ClothesService); tu jest wygląd i podgląd (szansa, opłata, cena).

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared.Config.Economy)
local Format = require(Shared.Format)
local Formulas = require(Shared.Formulas)
local Net = require(Shared.Net)
local ClothesLogic = require(Shared.Logic.Clothes)
local ClothesConfig = require(Shared.Config.Clothes)
local ClothModels = require(Shared.ClothModels)
local PetsConfig = require(Shared.Config.Pets)
local State = require(script.Parent.State)
local Theme = require(script.Parent.Ui.Theme)
local Kit = require(script.Parent.Ui.Kit)
local Sounds = require(script.Parent.Ui.Sounds)
local Pets = require(script.Parent.Pets)
local MergeWindow = require(script.Parent.MergeWindow)

local Wardrobe = {}

local MAX_PIECES = Economy.Pets.Merge.MaxPieces

local TEXT = {
	Tile = "CLOTHES",
	Title = "Clothes",
	Wearing = "Wearing %d/%d",
	Bonus = "LP bonus",
	WearBest = "WEAR BEST",
	Empty = "No clothes yet! Open mystery boxes in the Mall.",
	On = "ON",
	BonusSuffix = "% LP",
	Count = "%d/%d",
	Sell = "SELL",
	Merge = "MERGE",
	Cancel = "CANCEL",
	All = "ALL",
	Dupes = "DUPES",
	Auto = "AUTO",
	SellCount = "SELL (%d)",
	SellHint = "Tap clothes to sell them",
	SellTotal = "You get",
	SoldOne = "Sold 1 item for",
	SoldMany = "Sold %d items for",
	NoDupes = "No duplicates to sell",
	UnwearSell = "Take it off first to sell it",
	MergeHint = "Pick 1 to 5 identical items",
	MergeInto = "Merge into",
	MergeEach = "Each item adds",
	MergeEachTail = "chance",
	MergeChance = "Chance",
	MergeFee = "Fee",
	MergeMax = "Diamond items can't be merged anymore",
	MergeFull = "You can merge up to 5 items at once",
	MergePremium = "Robux items merge only at 100%",
	MergeNone = "No identical items to merge yet",
	MergePick = "Pick items to merge first",
	AvatarOn = "AVATAR ON",
	AvatarOff = "AVATAR OFF",
	AvatarHidden = "Clothes hidden on your avatar (bonus still works)",
	AvatarShown = "Clothes visible on your avatar",
	SlotEmpty = "Empty",
	Wearing2 = "Wearing!",
	ConfirmTitle = "Sell an Ultra Secret?",
	ConfirmText = "You're selling an ULTRA SECRET: %s!",
	UltraName = "a chrome item",
	ConfirmYes = "SELL IT",
	ConfirmNo = "KEEP IT",
}

local PANEL_SIZE = Vector2.new(860, 520)
local PANEL_TOP = 34
local HEADER_LEFT = 54
local GRID_TOP = 58
local FOOTER = 62
local SIDE = 160 -- szerokość kolumny z kategoriami
local GREEN = Color3.fromRGB(70, 200, 60)
local RED = Color3.fromRGB(235, 50, 70)
local PURPLE = Color3.fromRGB(176, 70, 255)
local EMPTY = Color3.fromRGB(214, 216, 226)

local RANK = {}
for i, rarity in ipairs(Economy.Clothes.RarityOrder) do
	RANK[rarity] = i
end

local inventory = {} -- lista { Id, Category, Rarity, Level, Box, Worn } od serwera
local byId = {}
local worn = {} -- [id] = true

local function bonus(item)
	return Formulas.clothBonus(item.Rarity, item.Level or 0)
end

local function bonusText(item)
	return "+" .. Format.small(bonus(item) * 100) .. TEXT.BonusSuffix
end

local function sameKind(a, b)
	return a.Category == b.Category and a.Rarity == b.Rarity and (a.Level or 0) == (b.Level or 0)
end

local function kindKey(item)
	return string.format("%s:%s:%d", item.Category, item.Rarity, item.Level or 0)
end

local function showModel(view, model, distanceScale)
	for _, child in ipairs(view:GetChildren()) do
		if child:IsA("Model") or child:IsA("Camera") then
			child:Destroy()
		end
	end
	model:PivotTo(CFrame.new())
	model.Parent = view
	local camera = Instance.new("Camera")
	local size = model:GetExtentsSize().Magnitude
	camera.FieldOfView = 40
	camera.CFrame = CFrame.lookAt(Vector3.new(size * 0.35, size * 0.3, -size * (distanceScale or 1.45)), Vector3.new(0, 0, 0))
	camera.Parent = view
	view.CurrentCamera = camera
end
Wardrobe.showModel = showModel

local function itemModel(item)
	return ClothModels.display(item.Category, item.Rarity, item.Level or 0)
end
Wardrobe.itemModel = itemModel
Wardrobe.bonusText = bonusText

----------------------------------------------------------------- Kafelek CLOTHES dla innych modułów
local tileRef = nil
local tileScale = nil

function Wardrobe.tileCenter()
	if tileRef == nil then
		return nil
	end
	local holder = tileRef.holder
	return holder.AbsolutePosition + holder.AbsoluteSize / 2
end

function Wardrobe.bump()
	if tileScale == nil then
		return
	end
	tileScale.Scale = 1.22
	TweenService:Create(tileScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

----------------------------------------------------------------- Start
function Wardrobe.start(hud)
	local tile = hud.addTile({
		name = "Clothes",
		icon = "Clothes",
		text = TEXT.Tile,
		colors = Theme.Gradients.Yellow,
		order = 4,
		textSize = 22,
	})
	tileRef = tile
	tileScale = Kit.new("UIScale", { Parent = tile.body })
	local panel = Kit.panel(hud.gui, {
		name = "ClothesPanel",
		size = PANEL_SIZE,
		title = TEXT.Title,
		icon = "Clothes",
		padding = 30,
		top = PANEL_TOP,
		bottom = 26,
	})
	hud.registerScale(panel.holder)
	hud.addWindow(panel)
	local merger = MergeWindow.create(hud, {
		title = "Merge Clothes",
		icon = "Clothes",
		one = "item",
		many = "items",
		remote = "MergeClothes",
		model = itemModel,
		name = function(item)
			return ClothesConfig.fullName(item.Category, item.Rarity, item.Level)
		end,
		powerText = bonusText,
		rarityItem = Pets.rarityItem,
		fromInfo = function(info)
			return { Category = info.Category, Rarity = info.Rarity, Level = info.Level }
		end,
		fromReply = function(reply)
			return reply.Item or { Category = reply.Category, Rarity = reply.Rarity, Level = reply.Level }
		end,
		onText = TEXT.Wearing2,
		isOn = function(item)
			return item.Worn == true
		end,
		tileCenter = Wardrobe.tileCenter,
		bump = Wardrobe.bump,
	})

	local countLine = Kit.line(panel.title.Parent, {
		name = "ClothesCount",
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
		position = UDim2.new(0, SIDE + 12, 1, -26),
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
	local bestButton = button("WearBest", 190, TEXT.WearBest, Theme.Gradients.Green, TOP_RIGHT, UDim2.new(1, 0, 0, 0))
	local allButton = button("All", 100, TEXT.All, Theme.Gradients.Cyan, TOP_RIGHT, UDim2.new(1, 0, 0, 0))
	local dupesButton = button("Dupes", 130, TEXT.Dupes, Theme.Gradients.Cyan, TOP_RIGHT, UDim2.new(1, -112, 0, 0))
	local autoButton = button("Auto", 130, TEXT.Auto, Theme.Gradients.Cyan, TOP_RIGHT, UDim2.new(1, 0, 0, 0))
	local avatarButton = button("Avatar", SIDE, TEXT.AvatarOn, Theme.Gradients.Green, BOTTOM_LEFT, UDim2.new(0, 0, 1, 0))
	local sellButton = button("Sell", 140, TEXT.Sell, Theme.Gradients.Yellow, BOTTOM_RIGHT, UDim2.new(1, 0, 1, 0))
	local mergeButton = button("Merge", 160, TEXT.Merge, Theme.Gradients.Pink, BOTTOM_RIGHT, UDim2.new(1, -152, 1, 0))
	local confirmButton = button("Confirm", 190, "", Theme.Gradients.Gray, BOTTOM_RIGHT, UDim2.new(1, 0, 1, 0))
	local cancelButton = button("Cancel", 150, TEXT.Cancel, Theme.Gradients.Gray, BOTTOM_RIGHT, UDim2.new(1, -202, 1, 0))

	------------------------------------------------------------- Kategorie po lewej
	local side = Kit.new("Frame", {
		Name = "Outfit",
		Position = UDim2.fromOffset(0, GRID_TOP),
		Size = UDim2.new(0, SIDE, 1, -GRID_TOP - FOOTER),
		BackgroundTransparency = 1,
		ZIndex = 3,
		Parent = panel.content,
	})
	Kit.new("UIListLayout", {
		Padding = UDim.new(0, 4),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = side,
	})
	local filter = nil -- kategoria pokazana w siatce albo nil (wszystkie)
	local rows = {} -- [kategoria] = { button, stroke, view, tile, name, info }
	for i, category in ipairs(ClothesConfig.CategoryOrder) do
		local row = Kit.new("TextButton", {
			Name = category,
			LayoutOrder = i,
			Size = UDim2.new(1, 0, 0, 44),
			BackgroundColor3 = Theme.White,
			AutoButtonColor = false,
			Text = "",
			ZIndex = 4,
			Parent = side,
		})
		Kit.corner(row, 12)
		local stroke = Kit.stroke(row, 2.5, Enum.ApplyStrokeMode.Border)
		local tileFrame = Kit.new("Frame", {
			Position = UDim2.fromOffset(4, 4),
			Size = UDim2.fromOffset(36, 36),
			BackgroundColor3 = EMPTY,
			BorderSizePixel = 0,
			ZIndex = 4,
			Parent = row,
		})
		Kit.corner(tileFrame, 9)
		local view = Kit.new("ViewportFrame", {
			Position = UDim2.fromOffset(2, 2),
			Size = UDim2.fromOffset(40, 40),
			BackgroundTransparency = 1,
			Ambient = Color3.fromRGB(200, 200, 210),
			LightColor = Color3.new(1, 1, 1),
			ZIndex = 5,
			Parent = row,
		})
		local name = Kit.text(row, {
			Position = UDim2.fromOffset(46, 3),
			Size = UDim2.new(1, -50, 0, 20),
			Text = category,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 5,
		}, { maxSize = 17, stroke = 2.5 })
		local info = Kit.text(row, {
			Position = UDim2.fromOffset(46, 23),
			Size = UDim2.new(1, -50, 0, 17),
			Text = TEXT.SlotEmpty,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 5,
		}, { maxSize = 14, stroke = 2 })
		rows[category] = { button = row, stroke = stroke, view = view, tile = tileFrame, name = name, info = info, key = nil }
	end

	------------------------------------------------------------- Siatka
	local grid = Kit.new("ScrollingFrame", {
		Name = "Grid",
		Position = UDim2.fromOffset(SIDE + 10, GRID_TOP),
		Size = UDim2.new(1, -SIDE - 10, 1, -GRID_TOP - FOOTER),
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
		PaddingTop = UDim.new(0, 4),
		PaddingLeft = UDim.new(0, 4),
		PaddingRight = UDim.new(0, 12),
		PaddingBottom = UDim.new(0, 6),
		Parent = grid,
	})
	Kit.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(96, 128),
		CellPadding = UDim2.fromOffset(8, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = grid,
	})
	local emptyLabel = Kit.text(panel.content, {
		Name = "Empty",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, SIDE / 2, 0.5, 0),
		Size = UDim2.fromOffset(560, 40),
		Text = TEXT.Empty,
		Visible = false,
		ZIndex = 4,
	}, { maxSize = 26, stroke = 3 })

	------------------------------------------------------------- Potwierdzenie sprzedaży Ultra Secret
	local confirm = Kit.panel(hud.gui, {
		name = "SellUltra",
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
	local sellUltraButton = Kit.button(confirm.content, {
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
	local mode = "items" -- items, sell, merge
	local selected = {}
	local mergeOrder = {}
	local cards = {}

	local function clearSelection()
		selected = {}
		mergeOrder = {}
	end

	local function selectedIds()
		local ids = {}
		if mode == "merge" then
			for _, id in ipairs(mergeOrder) do
				table.insert(ids, id)
			end
			return ids
		end
		for _, item in ipairs(inventory) do
			if selected[item.Id] then
				table.insert(ids, item.Id)
			end
		end
		return ids
	end

	local function mergeInfo()
		if #mergeOrder == 0 then
			return nil, "None"
		end
		local view = State.view or {}
		local data = { Clothes = byId, AuraUpgrades = { MergeLuck = view.MergeLuck or 0 } }
		return ClothesLogic.mergeInfo(data, mergeOrder)
	end

	local function canJoin(item)
		if (item.Level or 0) >= 2 then
			return false
		end
		if #mergeOrder == 0 then
			return true
		end
		local first = byId[mergeOrder[1]]
		return first ~= nil and sameKind(first, item)
	end

	local function paintCard(id)
		local card = cards[id]
		if card == nil then
			return
		end
		local item = card.item
		local on = worn[id] == true
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
				dim = not canJoin(item)
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

	-- Kategorie po lewej: co jest założone (model, bonus) i która kategoria jest wybrana.
	local function renderRows()
		local view = State.view or {}
		local passes = view.Passes or {}
		for _, category in ipairs(ClothesConfig.CategoryOrder) do
			local row = rows[category]
			local slots = ClothesLogic.slots({ passes = passes }, category)
			local list = {}
			local total = 0
			for _, item in ipairs(inventory) do
				if item.Category == category and worn[item.Id] then
					table.insert(list, item)
					total = total + bonus(item)
				end
			end
			table.sort(list, function(a, b)
				return bonus(a) > bonus(b)
			end)
			local label = category
			if slots > 1 then
				label = string.format("%s %d/%d", category, #list, slots)
			end
			row.name.Text = label
			local best = list[1]
			local key = "none"
			if best ~= nil then
				key = kindKey(best)
				row.info.Text = "+" .. Format.small(total * 100) .. TEXT.BonusSuffix
				row.info.TextColor3 = Theme.GoldText
				row.tile.BackgroundColor3 = (PetsConfig.RarityColors[best.Rarity] or EMPTY):Lerp(Theme.White, 0.55)
			else
				row.info.Text = TEXT.SlotEmpty
				row.info.TextColor3 = Theme.White
				row.tile.BackgroundColor3 = EMPTY
			end
			if row.key ~= key then
				row.key = key
				if best ~= nil then
					showModel(row.view, itemModel(best), 1.25)
				else
					for _, child in ipairs(row.view:GetChildren()) do
						child:Destroy()
					end
				end
			end
			if filter == category then
				row.stroke.Color = PURPLE
				row.stroke.Thickness = 4
			else
				row.stroke.Color = Theme.Outline
				row.stroke.Thickness = 2.5
			end
		end
	end

	local function renderBars()
		local view = State.view or {}
		local inMode = mode == "sell" or mode == "merge"
		bestButton.holder.Visible = mode == "items"
		allButton.holder.Visible = mode == "sell"
		dupesButton.holder.Visible = mode == "sell"
		autoButton.holder.Visible = mode == "merge"
		sellButton.holder.Visible = mode == "items"
		mergeButton.holder.Visible = mode == "items"
		cancelButton.holder.Visible = inMode
		confirmButton.holder.Visible = inMode
		avatarButton.holder.Visible = mode == "items"
		emptyLabel.Visible = #inventory == 0

		local settings = view.Settings or {}
		if settings.ShowClothes == false then
			avatarButton.setText(TEXT.AvatarOff)
			avatarButton.setColors(Theme.Gradients.Gray)
		else
			avatarButton.setText(TEXT.AvatarOn)
			avatarButton.setColors(Theme.Gradients.Green)
		end

		if mode == "items" then
			local slots = 0
			for _, category in ipairs(ClothesConfig.CategoryOrder) do
				slots = slots + ClothesLogic.slots({ passes = view.Passes or {} }, category)
			end
			header.set({
				{ text = string.format(TEXT.Wearing, view.ClothesWorn or 0, slots), size = 26 },
				{ text = TEXT.Bonus, size = 24 },
				{ text = "×" .. Format.small(view.ClothLayer or 1), size = 28, colors = Theme.Gradients.Gold },
			})
			footer.set({})
		elseif mode == "sell" then
			local ids = selectedIds()
			local cash = 0
			for _, id in ipairs(ids) do
				cash = cash + ClothesLogic.sellValue(byId[id])
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
		else
			local info, reason = mergeInfo()
			confirmButton.setText(TEXT.Merge)
			if info ~= nil then
				confirmButton.setColors(Theme.Gradients.Pink)
				header.set({
					{ text = TEXT.MergeInto, size = 24 },
					{
						text = ClothesConfig.fullName(info.Category, info.Rarity, info.Level),
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
				header.set({ { text = TEXT.MergeHint, size = 24 } })
				if reason == "Premium" then
					footer.set({ { text = TEXT.MergePremium, size = 22, colors = Theme.Gradients.Red } })
				else
					footer.set({
						{ text = TEXT.MergeEach, size = 22 },
						{ text = Format.percent(merger.chancePerPiece()), size = 26, colors = Theme.Gradients.Gold },
						{ text = TEXT.MergeEachTail, size = 22 },
					})
				end
			end
		end

		local count = view.ClothesCount or #inventory
		local colors = Theme.Gradients.Gold
		if count >= ClothesConfig.MaxInventory then
			colors = Theme.Gradients.Red
		end
		countLine.set({ { text = string.format(TEXT.Count, count, ClothesConfig.MaxInventory), size = 30, colors = colors } })
		renderRows()
	end

	local function deny(text, key)
		Sounds.play("NotEnough")
		hud.toast({ { text = text, size = 26, colors = Theme.Gradients.Red } }, key)
	end

	local function setMode(newMode)
		mode = newMode
		clearSelection()
		paintAll()
		renderBars()
	end

	local function toggleWear(item)
		if busy then
			return
		end
		busy = true
		local ok, result = pcall(function()
			return Net.func("WearCloth"):InvokeServer(item.Id, not worn[item.Id])
		end)
		busy = false
		if ok and type(result) == "table" and result.Ok then
			Sounds.play("Button")
		end
	end

	local function onCardClicked(item)
		if mode == "items" then
			toggleWear(item)
			return
		end
		if mode == "sell" then
			if worn[item.Id] then
				deny(TEXT.UnwearSell, "ClothUnwearFirst")
				return
			end
			if selected[item.Id] then
				selected[item.Id] = nil
			else
				selected[item.Id] = true
			end
			Sounds.play("Button")
			paintCard(item.Id)
			renderBars()
			return
		end
		if (item.Level or 0) >= 2 then
			deny(TEXT.MergeMax, "ClothMergeMax")
			return
		end
		if selected[item.Id] then
			selected[item.Id] = nil
			for i = #mergeOrder, 1, -1 do
				if mergeOrder[i] == item.Id then
					table.remove(mergeOrder, i)
				end
			end
		else
			if not canJoin(item) then
				clearSelection()
			end
			if #mergeOrder >= MAX_PIECES then
				deny(TEXT.MergeFull, "ClothMergeFull")
				return
			end
			selected[item.Id] = true
			table.insert(mergeOrder, item.Id)
		end
		Sounds.play("Button")
		paintAll()
		renderBars()
	end

	local function makeCard(item, order)
		local level = item.Level or 0
		local card = Kit.new("TextButton", {
			Name = "Cloth" .. item.Id,
			LayoutOrder = order,
			BackgroundColor3 = Theme.White,
			AutoButtonColor = false,
			Text = "",
			ZIndex = 4,
			Parent = grid,
		})
		Kit.corner(card, 16)
		local stroke = Kit.stroke(card, 3, Enum.ApplyStrokeMode.Border)
		local color = PetsConfig.RarityColors[item.Rarity] or Theme.White
		local tileFrame = Kit.new("Frame", {
			Name = "RarityTile",
			Position = UDim2.fromOffset(7, 7),
			Size = UDim2.new(1, -14, 0, 58),
			BackgroundColor3 = color:Lerp(Theme.White, 0.65),
			BorderSizePixel = 0,
			ZIndex = 4,
			Parent = card,
		})
		Kit.corner(tileFrame, 12)
		local levelColors = PetsConfig.LevelColors[level]
		if levelColors ~= nil then
			tileFrame.BackgroundColor3 = Theme.White
			Kit.gradient(tileFrame, levelColors, 90)
		elseif item.Rarity == "UltraSecret" then
			-- chrom: srebrny kafelek, na którym czarne ubranie dobrze widać
			tileFrame.BackgroundColor3 = Theme.White
			Kit.gradient(tileFrame, Pets.ChromeColors, 90)
		end
		local view = Kit.new("ViewportFrame", {
			Position = UDim2.fromOffset(5, 3),
			Size = UDim2.new(1, -10, 0, 64),
			BackgroundTransparency = 1,
			Ambient = Color3.fromRGB(200, 200, 210),
			LightColor = Color3.new(1, 1, 1),
			ZIndex = 5,
			Parent = card,
		})
		showModel(view, itemModel(item), 1.3)
		if levelColors ~= nil then
			local ribbon = Kit.new("Frame", {
				Name = "Level",
				Position = UDim2.fromOffset(3, 3),
				Size = UDim2.fromOffset(54, 18), -- z „ON” po prawej (30 px) mieści się na karcie 96 px
				BackgroundColor3 = Theme.White,
				ZIndex = 6,
				Parent = card,
			})
			Kit.corner(ribbon, 9)
			Kit.stroke(ribbon, 2.5, Enum.ApplyStrokeMode.Border)
			Kit.gradient(ribbon, levelColors, 90)
			Kit.text(ribbon, {
				Size = UDim2.fromScale(1, 1),
				Text = string.upper(PetsConfig.LevelNames[level]),
				ZIndex = 7,
			}, { maxSize = 12, stroke = 2 })
		end
		Kit.text(card, {
			Position = UDim2.fromOffset(3, 67),
			Size = UDim2.new(1, -6, 0, 19),
			Text = ClothesConfig.name(item.Category, item.Rarity),
			ZIndex = 5,
		}, { maxSize = 15, stroke = 2.5 })
		local rarity = Pets.rarityItem(item.Rarity, 13)
		Kit.text(card, {
			Position = UDim2.fromOffset(3, 87),
			Size = UDim2.new(1, -6, 0, 15),
			Text = rarity.text,
			TextColor3 = rarity.color or Theme.White,
			ZIndex = 5,
		}, { maxSize = 13, stroke = 2.5, gradient = rarity.colors })
		local power = Kit.text(card, {
			Position = UDim2.fromOffset(3, 104),
			Size = UDim2.new(1, -6, 0, 18),
			Text = bonusText(item),
			ZIndex = 5,
		}, { maxSize = 15, stroke = 2.5, gradient = Theme.Gradients.Gold })
		local value = Kit.line(card, {
			anchor = Vector2.new(0.5, 0.5),
			position = UDim2.new(0.5, 0, 0, 113),
			height = 20,
			gap = 3,
			items = {
				{ icon = "Cash", size = 18 },
				{ text = Format.number(ClothesLogic.sellValue(item)), size = 15, colors = Theme.Gradients.Gold },
			},
		})
		value.holder.ZIndex = 5
		value.holder.Visible = false
		if worn[item.Id] then
			local badge = Kit.new("Frame", {
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -3, 0, 3),
				Size = UDim2.fromOffset(30, 20),
				BackgroundColor3 = GREEN,
				ZIndex = 6,
				Parent = card,
			})
			Kit.corner(badge, 10)
			Kit.stroke(badge, 2.5, Enum.ApplyStrokeMode.Border)
			Kit.text(badge, { Size = UDim2.fromScale(1, 1), Text = TEXT.On, ZIndex = 7 }, { maxSize = 13, stroke = 2 })
		end
		local mark = Kit.new("Frame", {
			Name = "Mark",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -3, 0, 3),
			Size = UDim2.fromOffset(26, 26),
			BackgroundColor3 = RED,
			Visible = false,
			ZIndex = 8,
			Parent = card,
		})
		Kit.corner(mark, 13)
		Kit.stroke(mark, 2.5, Enum.ApplyStrokeMode.Border)
		local markLabel = Kit.text(mark, { Size = UDim2.fromScale(1, 1), Text = "X", ZIndex = 9 }, { maxSize = 17, stroke = 2 })
		local dim = Kit.new("Frame", {
			Name = "Dim",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Theme.White,
			BackgroundTransparency = 0.4,
			Visible = false,
			ZIndex = 10,
			Parent = card,
		})
		Kit.corner(dim, 16)
		cards[item.Id] = {
			item = item,
			stroke = stroke,
			mark = mark,
			markLabel = markLabel,
			dim = dim,
			power = power,
			value = value,
		}
		paintCard(item.Id)
		card.Activated:Connect(function()
			onCardClicked(item)
		end)
	end

	local function pruneSelection()
		local still = {}
		for id in pairs(selected) do
			if byId[id] ~= nil and not (mode == "sell" and worn[id]) then
				still[id] = true
			end
		end
		selected = still
		local order = {}
		for _, id in ipairs(mergeOrder) do
			local item = byId[id]
			if still[id] and item ~= nil and (#order == 0 or sameKind(byId[order[1]], item)) then
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
		local sorted = {}
		for _, item in ipairs(inventory) do
			if filter == nil or item.Category == filter then
				table.insert(sorted, item)
			end
		end
		-- założone najpierw, potem od najlepszego; identyczne obok siebie
		table.sort(sorted, function(a, b)
			local wa, wb = worn[a.Id] == true, worn[b.Id] == true
			if wa ~= wb then
				return wa
			end
			local ba, bb = bonus(a), bonus(b)
			if ba ~= bb then
				return ba > bb
			end
			if a.Category ~= b.Category then
				return (ClothesLogic.categoryIndex(a.Category) or 0) < (ClothesLogic.categoryIndex(b.Category) or 0)
			end
			if a.Rarity ~= b.Rarity then
				return (RANK[a.Rarity] or 0) > (RANK[b.Rarity] or 0)
			end
			return (tonumber(a.Id) or 0) < (tonumber(b.Id) or 0)
		end)
		for i, item in ipairs(sorted) do
			makeCard(item, i)
		end
	end

	------------------------------------------------------------- Przyciski
	for category, row in pairs(rows) do
		row.button.Activated:Connect(function()
			Sounds.play("Button")
			if filter == category then
				filter = nil
			else
				filter = category
			end
			renderGrid()
			renderBars()
		end)
	end

	tile.Activated:Connect(function()
		if panel.isOpen() then
			panel.hide()
		else
			mode = "items"
			filter = nil
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
			Net.func("WearBest"):InvokeServer()
		end)
		busy = false
	end)

	avatarButton.Activated:Connect(function()
		local settings = (State.view and State.view.Settings) or {}
		local show = settings.ShowClothes == false
		Net.event("SetSetting"):FireServer("ShowClothes", show)
		if show then
			hud.toast({ { text = TEXT.AvatarShown, size = 24 } }, "ClothesAvatar")
		else
			hud.toast({ { text = TEXT.AvatarHidden, size = 24 } }, "ClothesAvatar")
		end
	end)

	sellButton.Activated:Connect(function()
		setMode("sell")
	end)
	mergeButton.Activated:Connect(function()
		setMode("merge")
	end)
	cancelButton.Activated:Connect(function()
		setMode("items")
	end)

	allButton.Activated:Connect(function()
		local all = {}
		local everything = true
		for _, item in ipairs(inventory) do
			if not worn[item.Id] and (filter == nil or item.Category == filter) then
				all[item.Id] = true
				if not selected[item.Id] then
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

	-- DUPES: z każdego rodzaju (kategoria, rzadkość, poziom) zostaje jedno ubranie (założone albo
	-- najstarsze), a pozostałe niezałożone idą do sprzedaży. Ultra Secret nigdy (jak sekretne pety).
	dupesButton.Activated:Connect(function()
		local groups = {}
		for _, item in ipairs(inventory) do
			local key = kindKey(item)
			if groups[key] == nil then
				groups[key] = {}
			end
			table.insert(groups[key], item)
		end
		selected = {}
		local any = false
		for _, list in pairs(groups) do
			if #list > 1 and list[1].Rarity ~= "UltraSecret" then
				local keep = nil
				for _, item in ipairs(list) do
					if worn[item.Id] then
						keep = item
					end
				end
				if keep == nil then
					table.sort(list, function(a, b)
						return (tonumber(a.Id) or 0) < (tonumber(b.Id) or 0)
					end)
					keep = list[1]
				end
				for _, item in ipairs(list) do
					if item ~= keep and not worn[item.Id] then
						selected[item.Id] = true
						any = true
					end
				end
			end
		end
		if not any then
			deny(TEXT.NoDupes, "ClothNoDupes")
		end
		paintAll()
		renderBars()
	end)

	-- AUTO: dobiera identyczne ubrania do 5 (najpierw niezałożone). Bez wyboru bierze rodzaj,
	-- którego gracz ma najwięcej sztuk.
	autoButton.Activated:Connect(function()
		local kind = nil
		if #mergeOrder > 0 then
			kind = byId[mergeOrder[1]]
		else
			local counts = {}
			for _, item in ipairs(inventory) do
				if (item.Level or 0) < 2 then
					local key = kindKey(item)
					counts[key] = (counts[key] or 0) + 1
				end
			end
			local best, bestCount = nil, 1
			for _, item in ipairs(inventory) do
				local n = counts[kindKey(item)]
				if n ~= nil and (n > bestCount or (n == bestCount and best ~= nil and bonus(item) > bonus(best))) then
					best, bestCount = item, n
				end
			end
			kind = best
		end
		if kind == nil then
			deny(TEXT.MergeNone, "ClothMergeNone")
			return
		end
		local candidates = {}
		for _, item in ipairs(inventory) do
			if sameKind(item, kind) and not selected[item.Id] then
				table.insert(candidates, item)
			end
		end
		table.sort(candidates, function(a, b)
			local wa, wb = worn[a.Id] == true, worn[b.Id] == true
			if wa ~= wb then
				return wb
			end
			return (tonumber(a.Id) or 0) < (tonumber(b.Id) or 0)
		end)
		for _, item in ipairs(candidates) do
			if #mergeOrder >= MAX_PIECES then
				break
			end
			selected[item.Id] = true
			table.insert(mergeOrder, item.Id)
		end
		paintAll()
		renderBars()
	end)

	-- Okienko „na pewno?” przed sprzedażą Ultra Secret. item może być nil (wtedy bez nazwy).
	local sell
	local function askUltra(item)
		local name = TEXT.UltraName
		if item ~= nil then
			name = ClothesConfig.fullName(item.Category, item.Rarity, item.Level)
		end
		confirmLine.set({ { text = string.format(TEXT.ConfirmText, name), size = 24 } })
		confirmSub.set({ { text = Format.oneIn(Economy.Clothes.UltraSecretChance), size = 26, colors = Pets.ChromeColors } })
		onConfirm = function()
			sell(true)
		end
		confirm.open()
	end

	-- Sprzedaż zaznaczonych. Ultra Secret: najpierw okienko „na pewno?”, potem serwer dostaje confirm.
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
				local item = byId[id]
				if item ~= nil and item.Rarity == "UltraSecret" then
					askUltra(item)
					return
				end
			end
		end
		busy = true
		local ok, result = pcall(function()
			return Net.func("SellClothes"):InvokeServer(ids, sure == true)
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
			askUltra(nil)
		end
	end

	keepButton.Activated:Connect(function()
		onConfirm = nil
		confirm.hide()
	end)
	sellUltraButton.Activated:Connect(function()
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
				deny(TEXT.MergePremium, "ClothMergePremium")
			else
				deny(TEXT.MergePick, "ClothMergePick")
			end
			return
		end
		local items = {}
		for _, id in ipairs(mergeOrder) do
			table.insert(items, byId[id])
		end
		merger.open(items, info, function(result)
			if result ~= nil and result.Ok then
				clearSelection()
			end
			pruneSelection()
			paintAll()
			renderBars()
		end)
	end)

	panel.close.Activated:Connect(function()
		mode = "items"
		clearSelection()
		confirm.hide()
	end)
	panel.holder:GetPropertyChangedSignal("Visible"):Connect(function()
		if not panel.holder.Visible then
			confirm.hide()
		end
	end)

	State.onNotify(function(payload)
		if payload.Kind ~= "Clothes" or type(payload.Clothes) ~= "table" then
			return
		end
		inventory = payload.Clothes
		byId = {}
		for _, item in ipairs(inventory) do
			byId[item.Id] = item
		end
		worn = {}
		for _, id in ipairs(payload.Worn or {}) do
			worn[id] = true
		end
		pruneSelection()
		if panel.isOpen() then
			renderGrid()
			renderBars()
		end
	end)

	State.onChange(function(view)
		if panel.isOpen() then
			renderBars()
		end
		-- czerwona kropka: masz ubranie w kategorii, w której nic nie nosisz
		local free = false
		local passes = view.Passes or {}
		for _, category in ipairs(ClothesConfig.CategoryOrder) do
			local count, have = 0, false
			for _, item in ipairs(inventory) do
				if item.Category == category then
					have = true
					if worn[item.Id] then
						count = count + 1
					end
				end
			end
			if have and count < ClothesLogic.slots({ passes = passes }, category) and count == 0 then
				free = true
			end
		end
		if free then
			tile.badge.set("!")
		else
			tile.badge.set(nil)
		end
	end)
end

return Wardrobe
