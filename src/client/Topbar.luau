-- Przyciski gry w pasku Robloxa u góry ekranu, zaraz za koszykiem (jak w innych grach). Na razie
-- INVITE: okno zaproszeń Robloxa (+10% LP za każdego znajomego na serwerze, Codes.invite). Karta
-- INVITE w sklepie (zakładka FREE) też zostaje.
--
-- Wygląd jak przyciski Robloxa: ciemne kółko 44 px (kolor 18, 18, 21; przezroczystość 0,08 razy
-- GuiService.PreferredTransparency, czyli ustawienie gracza), ikona w środku, jaśniejsze po najechaniu,
-- po najechaniu myszą podpis pod spodem. Miejsce: ScreenGui z ScreenInsets = TopbarSafeInsets (wolna
-- część paska za przyciskami Robloxa, GuiService.TopbarInset), a odstępy jak w TopbarPlus: od lewej
-- GetGuiInset().Y − 50 (8 px przy pasku 58 px), przyciski przy dole paska (wysokość − 2 − 44, czyli
-- 12 px od góry przy 58 px). Gdy pasek ma wysokość 0 (schowany albo jeszcze się ładuje), przyciski znikają.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Economy = require(ReplicatedStorage:WaitForChild("Shared").Config.Economy)
local Icons = require(script.Parent.Ui.Icons)
local Sounds = require(script.Parent.Ui.Sounds)
local Codes = require(script.Parent.Codes)

local Topbar = {}

local SIZE = 44 -- jak przyciski Robloxa
local GAP = 12 -- między naszymi przyciskami
local BACKGROUND = Color3.fromRGB(18, 18, 21)
local BACKGROUND_ALPHA = 0.08
local ICON_SCALE = 0.72 -- ikona z obrazka ma trochę marginesu, więc większa niż białe ikony Robloxa (0,5)
local CAPTION_FONT = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold, Enum.FontStyle.Normal)

local TEXT = {
	Invite = "Invite Friends",
	InviteNote = "+%d%% LP for each friend here",
}

local function tween(obj, time, goals)
	TweenService:Create(obj, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goals):Play()
end

function Topbar.start()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local gui = Instance.new("ScreenGui")
	gui.Name = "LarpTopbar"
	gui.IgnoreGuiInset = true
	gui.ScreenInsets = Enum.ScreenInsets.TopbarSafeInsets
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 21
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui

	local buttons = {}

	-- Podpis pod przyciskiem po najechaniu myszą (jak dymki Robloxa: ciemna pigułka, biały tekst).
	local caption = Instance.new("Frame")
	caption.Name = "Caption"
	caption.AnchorPoint = Vector2.new(0.5, 0)
	caption.Size = UDim2.fromOffset(0, 0)
	caption.BackgroundColor3 = BACKGROUND
	caption.BackgroundTransparency = 0.08
	caption.BorderSizePixel = 0
	caption.Visible = false
	caption.ZIndex = 10
	caption.AutomaticSize = Enum.AutomaticSize.XY
	caption.Parent = gui
	local captionCorner = Instance.new("UICorner")
	captionCorner.CornerRadius = UDim.new(0, 10)
	captionCorner.Parent = caption
	local captionPadding = Instance.new("UIPadding")
	captionPadding.PaddingLeft = UDim.new(0, 12)
	captionPadding.PaddingRight = UDim.new(0, 12)
	captionPadding.PaddingTop = UDim.new(0, 6)
	captionPadding.PaddingBottom = UDim.new(0, 6)
	captionPadding.Parent = caption
	local captionList = Instance.new("UIListLayout")
	captionList.FillDirection = Enum.FillDirection.Vertical
	captionList.HorizontalAlignment = Enum.HorizontalAlignment.Center
	captionList.SortOrder = Enum.SortOrder.LayoutOrder
	captionList.Parent = caption
	local function captionLine(order, size, color)
		local label = Instance.new("TextLabel")
		label.LayoutOrder = order
		label.AutomaticSize = Enum.AutomaticSize.XY
		label.Size = UDim2.fromOffset(0, 0)
		label.BackgroundTransparency = 1
		label.FontFace = CAPTION_FONT
		label.TextSize = size
		label.TextColor3 = color
		label.ZIndex = 11
		label.Parent = caption
		return label
	end
	local captionTitle = captionLine(1, 16, Color3.fromRGB(255, 255, 255))
	local captionNote = captionLine(2, 13, Color3.fromRGB(255, 214, 90))

	local function layout()
		local inset = GuiService.TopbarInset
		local height = inset.Height
		gui.Enabled = height > 0
		if height <= 0 then
			return
		end
		local startX = GuiService:GetGuiInset().Y - 50
		local y = math.max(0, height - 2 - SIZE)
		for i, entry in ipairs(buttons) do
			entry.button.Position = UDim2.fromOffset(startX + (i - 1) * (SIZE + GAP), y)
		end
	end

	local function applyTransparency()
		local alpha = BACKGROUND_ALPHA * GuiService.PreferredTransparency
		for _, entry in ipairs(buttons) do
			entry.button.BackgroundTransparency = alpha
		end
		caption.BackgroundTransparency = alpha
	end

	-- Przycisk w pasku: ikona (Icons, np. obrazek z Settings.Ui.Icons), podpis i akcja po kliknięciu.
	local function addButton(name, icon, title, note, onClick)
		local button = Instance.new("TextButton")
		button.Name = name
		button.AutoButtonColor = false
		button.Text = ""
		button.Size = UDim2.fromOffset(SIZE, SIZE)
		button.BackgroundColor3 = BACKGROUND
		button.BorderSizePixel = 0
		button.Parent = gui
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = button
		-- jaśniejsza nakładka po najechaniu i przy wciśnięciu (jak u Robloxa)
		local overlay = Instance.new("Frame")
		overlay.Name = "Overlay"
		overlay.Size = UDim2.fromScale(1, 1)
		overlay.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		overlay.BackgroundTransparency = 1
		overlay.BorderSizePixel = 0
		overlay.ZIndex = 2
		overlay.Parent = button
		local overlayCorner = Instance.new("UICorner")
		overlayCorner.CornerRadius = UDim.new(1, 0)
		overlayCorner.Parent = overlay
		local image = Icons.make(icon, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(ICON_SCALE, ICON_SCALE),
			ZIndex = 3,
			Parent = button,
		})
		local imageScale = Instance.new("UIScale")
		imageScale.Parent = image

		local hovering = false
		local function showCaption()
			captionTitle.Text = title
			captionNote.Text = note or ""
			captionNote.Visible = note ~= nil and note ~= ""
			local position = button.Position
			caption.Position = UDim2.fromOffset(position.X.Offset + SIZE / 2, position.Y.Offset + SIZE + 8)
			caption.Visible = true
		end
		button.MouseEnter:Connect(function()
			if UserInputService.TouchEnabled and not UserInputService.MouseEnabled then
				return
			end
			hovering = true
			tween(overlay, 0.12, { BackgroundTransparency = 0.92 })
			showCaption()
		end)
		button.MouseLeave:Connect(function()
			hovering = false
			tween(overlay, 0.15, { BackgroundTransparency = 1 })
			tween(imageScale, 0.15, { Scale = 1 })
			caption.Visible = false
		end)
		button.MouseButton1Down:Connect(function()
			tween(overlay, 0.06, { BackgroundTransparency = 0.82 })
			tween(imageScale, 0.08, { Scale = 0.88 })
		end)
		button.MouseButton1Up:Connect(function()
			tween(overlay, 0.12, { BackgroundTransparency = (hovering and 0.92) or 1 })
			TweenService:Create(imageScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end)
		button.Activated:Connect(function()
			Sounds.play("Button")
			caption.Visible = false
			onClick()
		end)

		table.insert(buttons, { button = button, image = image })
		layout()
		applyTransparency()
		return button
	end

	addButton("Invite", "Friends", TEXT.Invite, string.format(TEXT.InviteNote, math.floor(Economy.Bonuses.FriendEach * 100 + 0.5)), function()
		Codes.invite()
	end)

	GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(layout)
	GuiService:GetPropertyChangedSignal("PreferredTransparency"):Connect(applyTransparency)
	-- Pasek może się ułożyć dopiero po chwili od wejścia
	task.delay(2, layout)
	task.delay(6, layout)
end

return Topbar
