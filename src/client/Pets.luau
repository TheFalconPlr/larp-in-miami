-- Pety po stronie gracza: kafelek PETS z oknem ekwipunku (kliknij peta, żeby go założyć albo zdjąć;
-- EQUIP BEST zakłada najmocniejsze) oraz pety latające za graczami. Pety wszystkich graczy rysuje
-- każdy klient sam, z atrybutu gracza „LarpPets” (ustawia go serwer, PetService).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Formulas = require(Shared.Formulas)
local Format = require(Shared.Format)
local Net = require(Shared.Net)
local PetsConfig = require(Shared.Config.Pets)
local State = require(script.Parent.State)
local Theme = require(script.Parent.Ui.Theme)
local Kit = require(script.Parent.Ui.Kit)
local Sounds = require(script.Parent.Ui.Sounds)
local LocalHide = require(script.Parent.LocalHide)
local PetModels = require(script.Parent.PetModels)

local Pets = {}

local ATTRIBUTE = "LarpPets" -- jak PetService.Attribute na serwerze

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
	Delete = "DELETE",
	Cancel = "CANCEL",
	All = "ALL",
	DeleteCount = "DELETE (%d)",
	SelectHint = "Tap pets to delete them",
	Unequip = "Unequip this pet first to delete it",
	DeletedOne = "Deleted 1 pet",
	DeletedMany = "Deleted %d pets",
	Count = "%d/%d",
}

local PANEL_SIZE = Vector2.new(860, 500)
local PANEL_TOP = 34 -- treść okna zaczyna się tak nisko pod górną krawędzią (nad nią jest łapka i tytuł)
local HEADER_LEFT = 54 -- napis w nagłówku zaczyna się za łapką, która wystaje do 50 px w dół
local GREEN = Color3.fromRGB(70, 200, 60)
local RED = Color3.fromRGB(235, 50, 70)

local inventory = {} -- lista { Id, Zone, Rarity, Level } od serwera
local equipped = {} -- [id] = true

local function power(pet)
	return Formulas.petPower(pet.Zone, pet.Rarity, pet.Level or 0)
end

local function powerText(pet)
	return "+" .. Format.small(power(pet) * 100) .. TEXT.PowerSuffix
end

-- Napis rzadkości w kolorze rzadkości (sekret: biało-fioletowy, bo kulka jest ciemna).
local function rarityItem(rarity, size)
	if rarity == "Secret" then
		return { text = rarity, size = size, colors = { Color3.fromRGB(255, 255, 255), Color3.fromRGB(200, 170, 255) } }
	end
	return { text = rarity, size = size, color = PetsConfig.RarityColors[rarity] }
end
Pets.rarityItem = rarityItem
Pets.powerText = powerText

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
		local zone, rarity = string.match(item, "^(%d+):(%a+)")
		if zone ~= nil then
			local model = PetModels.pet(tonumber(zone), rarity)
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
		-- w czasie aktywności pety innych graczy znikają razem z nimi
		local hidden = root == nil or (State.busy and player ~= me)
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
	-- przyciski po prawej: zwykle DELETE i EQUIP BEST, a przy usuwaniu ALL, CANCEL i DELETE (N)
	local function headerButton(name, width, text, colors, right)
		return Kit.button(panel.content, {
			name = name,
			size = Vector2.new(width, 46),
			text = text,
			colors = colors,
			anchor = Vector2.new(1, 0),
			position = UDim2.new(1, -right, 0, 0),
			textSize = 22,
		})
	end
	local bestButton = headerButton("EquipBest", 190, TEXT.EquipBest, Theme.Gradients.Green, 0)
	local confirmButton = headerButton("ConfirmDelete", 190, string.format(TEXT.DeleteCount, 0), Theme.Gradients.Gray, 0)
	local deleteButton = headerButton("Delete", 150, TEXT.Delete, Theme.Gradients.Red, 202)
	local allButton = headerButton("All", 90, TEXT.All, Theme.Gradients.Cyan, 364)
	confirmButton.holder.Visible = false
	allButton.holder.Visible = false
	local grid = Kit.new("ScrollingFrame", {
		Name = "Grid",
		Position = UDim2.fromOffset(0, 58),
		Size = UDim2.new(1, 0, 1, -58),
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
	Kit.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(118, 150),
		CellPadding = UDim2.fromOffset(10, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = grid,
	})
	Kit.new("UIPadding", {
		PaddingTop = UDim.new(0, 6),
		PaddingLeft = UDim.new(0, 6),
		PaddingRight = UDim.new(0, 12),
		PaddingBottom = UDim.new(0, 6),
		Parent = grid,
	})
	local emptyLabel = Kit.text(panel.content, {
		Name = "Empty",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.55, 0),
		Size = UDim2.fromOffset(560, 40),
		Text = TEXT.Empty,
		Visible = false,
		ZIndex = 4,
	}, { maxSize = 28, stroke = 3 })

	local busy = false
	local deleteMode = false
	local selected = {} -- [id] = true (zaznaczone do usunięcia)
	local cards = {} -- [id] = { stroke, mark, dim }

	local function selectedCount()
		local n = 0
		for _ in pairs(selected) do
			n = n + 1
		end
		return n
	end

	-- Wygląd karty: zielona ramka i ON (założony), czerwona ramka i X (do usunięcia),
	-- przy usuwaniu założone są przygaszone.
	local function paintCard(id)
		local card = cards[id]
		if card == nil then
			return
		end
		local on = equipped[id] == true
		local marked = deleteMode and selected[id] == true
		if marked then
			card.stroke.Color = RED
			card.stroke.Thickness = 5
		elseif on then
			card.stroke.Color = GREEN
			card.stroke.Thickness = 5
		else
			card.stroke.Color = Theme.Outline
			card.stroke.Thickness = 3
		end
		card.mark.Visible = marked
		card.dim.Visible = deleteMode and on
	end

	local function renderButtons()
		bestButton.holder.Visible = not deleteMode
		confirmButton.holder.Visible = deleteMode
		allButton.holder.Visible = deleteMode
		if deleteMode then
			local n = selectedCount()
			deleteButton.setText(TEXT.Cancel)
			deleteButton.setColors(Theme.Gradients.Gray)
			confirmButton.setText(string.format(TEXT.DeleteCount, n))
			if n > 0 then
				confirmButton.setColors(Theme.Gradients.Red)
			else
				confirmButton.setColors(Theme.Gradients.Gray)
			end
		else
			deleteButton.setText(TEXT.Delete)
			deleteButton.setColors(Theme.Gradients.Red)
		end
	end

	local function renderHeader()
		local view = State.view
		if view == nil then
			return
		end
		if deleteMode then
			header.set({ { text = TEXT.SelectHint, size = 24 } })
		else
			header.set({
				{ text = string.format(TEXT.Equipped, view.PetsEquipped or 0, view.PetSlots or 3), size = 26 },
				{ text = TEXT.Bonus, size = 24 },
				{ text = "×" .. Format.small(view.PetLayer or 1), size = 28, colors = Theme.Gradients.Gold },
			})
		end
		local count = view.PetCount or #inventory
		local colors = Theme.Gradients.Gold
		if count >= PetsConfig.MaxInventory then
			colors = Theme.Gradients.Red
		end
		countLine.set({ { text = string.format(TEXT.Count, count, PetsConfig.MaxInventory), size = 30, colors = colors } })
	end

	local function setDeleteMode(on)
		deleteMode = on
		selected = {}
		for id in pairs(cards) do
			paintCard(id)
		end
		renderButtons()
		renderHeader()
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
			Sounds.play("NotEnough")
			hud.toast({ { text = TEXT.SlotsFull, size = 26, colors = Theme.Gradients.Red } }, "PetSlotsFull")
		elseif ok and type(result) == "table" and result.Ok then
			Sounds.play("Button")
		end
	end

	local function onCardClicked(pet)
		if not deleteMode then
			toggle(pet)
			return
		end
		if equipped[pet.Id] then
			Sounds.play("NotEnough")
			hud.toast({ { text = TEXT.Unequip, size = 26, colors = Theme.Gradients.Red } }, "PetUnequipFirst")
			return
		end
		if selected[pet.Id] then
			selected[pet.Id] = nil
		else
			selected[pet.Id] = true
		end
		Sounds.play("Button")
		paintCard(pet.Id)
		renderButtons()
	end

	local function makeCard(pet, order)
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
		local viewport = Kit.new("ViewportFrame", {
			Position = UDim2.fromOffset(6, 4),
			Size = UDim2.new(1, -12, 0, 78),
			BackgroundTransparency = 1,
			Ambient = Color3.fromRGB(200, 200, 210),
			LightColor = Color3.new(1, 1, 1),
			ZIndex = 5,
			Parent = card,
		})
		PetModels.show(viewport, PetModels.pet(pet.Zone, pet.Rarity))
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
		Kit.text(card, {
			Position = UDim2.fromOffset(4, 124),
			Size = UDim2.new(1, -8, 0, 20),
			Text = powerText(pet),
			ZIndex = 5,
		}, { maxSize = 16, stroke = 2.5, gradient = Theme.Gradients.Gold })
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
		-- czerwony X: zaznaczony do usunięcia
		local mark = Kit.new("Frame", {
			Name = "DeleteMark",
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
		Kit.text(mark, { Size = UDim2.fromScale(1, 1), Text = "X", ZIndex = 9 }, { maxSize = 18, stroke = 2 })
		-- przygaszenie założonych w trybie usuwania (ich nie można usunąć)
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
		cards[pet.Id] = { stroke = stroke, mark = mark, dim = dim }
		paintCard(pet.Id)
		card.Activated:Connect(function()
			onCardClicked(pet)
		end)
	end

	local function renderGrid()
		for _, child in ipairs(grid:GetChildren()) do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		cards = {}
		-- zaznaczenie zostaje tylko dla petów, które dalej są w ekwipunku
		local still = {}
		for _, pet in ipairs(inventory) do
			if selected[pet.Id] and not equipped[pet.Id] then
				still[pet.Id] = true
			end
		end
		selected = still
		-- wyposażone najpierw, potem od najmocniejszego
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
			return (tonumber(a.Id) or 0) < (tonumber(b.Id) or 0)
		end)
		for i, pet in ipairs(sorted) do
			makeCard(pet, i)
		end
		emptyLabel.Visible = #sorted == 0
		renderButtons()
	end

	tile.Activated:Connect(function()
		if panel.isOpen() then
			panel.hide()
		else
			deleteMode = false
			selected = {}
			renderHeader()
			renderGrid()
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

	deleteButton.Activated:Connect(function()
		setDeleteMode(not deleteMode)
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
		for id in pairs(cards) do
			paintCard(id)
		end
		renderButtons()
	end)

	confirmButton.Activated:Connect(function()
		if busy then
			return
		end
		local ids = {}
		for id in pairs(selected) do
			table.insert(ids, id)
		end
		if #ids == 0 then
			Sounds.play("NotEnough")
			return
		end
		busy = true
		local ok, result = pcall(function()
			return Net.func("DeletePets"):InvokeServer(ids)
		end)
		busy = false
		if ok and type(result) == "table" and result.Ok then
			local text = string.format(TEXT.DeletedMany, result.Count or #ids)
			if result.Count == 1 then
				text = TEXT.DeletedOne
			end
			hud.toast({ { text = text, size = 26 } }, "PetsDeleted")
			setDeleteMode(false)
		end
	end)

	panel.close.Activated:Connect(function()
		deleteMode = false
		selected = {}
	end)

	State.onNotify(function(payload)
		if payload.Kind ~= "Pets" or type(payload.Pets) ~= "table" then
			return
		end
		inventory = payload.Pets
		equipped = {}
		for _, id in ipairs(payload.Equipped or {}) do
			equipped[id] = true
		end
		if panel.isOpen() then
			renderGrid()
			renderHeader()
		end
	end)

	State.onChange(function(view)
		if panel.isOpen() then
			renderHeader()
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
