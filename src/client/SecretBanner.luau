-- Komunikat o sekrecie u góry ekranu (dokument projektu: „komunikat na wszystkich serwerach gry:
-- nick, pet i 1 na 25 000”). Serwer (PetService.announceSecret) wysyła wszystkim graczom Notify
-- „SecretHatched”; tu jest tylko wygląd: ciemny pasek z głową awatara, nickiem i petem albo
-- ubraniem. Sekretny pet ma fioletowo-złotą ramkę, a ubranie Ultra Secret (chrome z boxa Iced)
-- srebrną. Kilka komunikatów naraz czeka w kolejce.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared.Config.Economy)
local Format = require(Shared.Format)
local PetsConfig = require(Shared.Config.Pets)
local ClothesConfig = require(Shared.Config.Clothes)
local State = require(script.Parent.State)
local Theme = require(script.Parent.Ui.Theme)
local Kit = require(script.Parent.Ui.Kit)
local Sounds = require(script.Parent.Ui.Sounds)

local SecretBanner = {}

local TEXT = {
	Hatched = "hatched a",
	Unboxed = "unboxed an",
	You = "You",
	Secret = "SECRET",
	Ultra = "ULTRA SECRET",
}

local SHOW_TIME = 6 -- tyle sekund widać jeden komunikat
local HEIGHT = 96

-- wygląd paska: sekretny pet i ubranie Ultra Secret
local LOOKS = {
	Pet = {
		colors = { Color3.fromRGB(255, 255, 255), Color3.fromRGB(200, 170, 255) },
		edge = { Color3.fromRGB(176, 70, 255), Color3.fromRGB(255, 200, 60) },
		avatar = Color3.fromRGB(60, 46, 86),
		avatarEdge = Color3.fromRGB(200, 170, 255),
	},
	Cloth = {
		colors = { Color3.fromRGB(255, 255, 255), Color3.fromRGB(140, 148, 166) }, -- jak Pets.ChromeColors
		edge = { Color3.fromRGB(120, 128, 146), Color3.fromRGB(255, 255, 255) },
		avatar = Color3.fromRGB(38, 40, 48),
		avatarEdge = Color3.fromRGB(214, 220, 230),
	},
}

local function edgeSequence(look)
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, look.edge[1]),
		ColorSequenceKeypoint.new(0.5, look.edge[2]),
		ColorSequenceKeypoint.new(1, look.edge[1]),
	})
end

function SecretBanner.start(hud)
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	-- nad animacją jajka i boxa (16), żeby komunikat było widać także w czasie otwierania
	local gui = Kit.new("ScreenGui", {
		Name = "LarpSecretBanner",
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 18,
		Parent = playerGui,
	})
	local holder = Kit.new("Frame", {
		Name = "Banner",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 12),
		Size = UDim2.fromOffset(600, HEIGHT),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = gui,
	})
	hud.registerScale(holder)
	-- środek w środku holdera: wjazd z góry i podskok rosną od środka
	local inner = Kit.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = holder,
	})
	local pop = Kit.new("UIScale", { Parent = inner })
	local body = Kit.new("Frame", {
		Name = "Body",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Outline,
		BackgroundTransparency = 0.08,
		BorderSizePixel = 0,
		ZIndex = 1,
		Parent = inner,
	})
	Kit.corner(body, 28)
	local edge = Kit.stroke(body, 5, Enum.ApplyStrokeMode.Border, Color3.new(1, 1, 1))
	local edgeGradient = Kit.new("UIGradient", { Color = edgeSequence(LOOKS.Pet), Parent = edge })
	local avatar = Kit.new("ImageLabel", {
		Name = "Avatar",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 12, 0.5, 0),
		Size = UDim2.fromOffset(HEIGHT - 20, HEIGHT - 20),
		BackgroundColor3 = LOOKS.Pet.avatar,
		ZIndex = 2,
		Parent = inner,
	})
	Kit.corner(avatar, 20)
	local avatarEdge = Kit.stroke(avatar, 3, Enum.ApplyStrokeMode.Border, LOOKS.Pet.avatarEdge)
	local top = Kit.line(inner, {
		name = "Top",
		anchor = Vector2.new(0, 0.5),
		position = UDim2.fromOffset(HEIGHT, 30),
		height = 36,
	})
	top.holder.ZIndex = 2
	local bottom = Kit.line(inner, {
		name = "Bottom",
		anchor = Vector2.new(0, 0.5),
		position = UDim2.fromOffset(HEIGHT, 66),
		height = 36,
	})
	bottom.holder.ZIndex = 2

	local queue = {}
	local showing = false

	local function show(message)
		local name = message.Name
		if message.Mine then
			name = TEXT.You
		end
		local level = message.Level or 0
		local cloth = message.Item == "Cloth"
		local look = LOOKS.Pet
		if cloth then
			look = LOOKS.Cloth
			top.set({
				{ text = name, size = 28, colors = Theme.Gradients.Gold },
				{ text = TEXT.Unboxed, size = 24 },
				{ text = TEXT.Ultra, size = 28, colors = look.colors },
			})
			bottom.set({
				{ text = ClothesConfig.fullName(message.Category, "UltraSecret", level), size = 28, colors = look.colors },
				{ text = Format.oneIn(Economy.Clothes.UltraSecretChance), size = 22, colors = Theme.Gradients.Gold },
			})
		else
			top.set({
				{ text = name, size = 28, colors = Theme.Gradients.Gold },
				{ text = TEXT.Hatched, size = 24 },
				{ text = TEXT.Secret, size = 28, colors = look.colors },
			})
			bottom.set({
				{ text = PetsConfig.fullName(message.Zone, "Secret", level), size = 28, colors = look.colors },
				{ text = Format.oneIn(Economy.Pets.SecretChance), size = 22, colors = Theme.Gradients.Gold },
			})
		end
		edgeGradient.Color = edgeSequence(look)
		avatar.BackgroundColor3 = look.avatar
		avatarEdge.Color = look.avatarEdge
		local width = math.max(top.holder.Size.X.Offset, bottom.holder.Size.X.Offset)
		holder.Size = UDim2.fromOffset(HEIGHT + width + 26, HEIGHT)
		avatar.Image = ""
		if type(message.UserId) == "number" and message.UserId > 0 then
			avatar.Image = string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150", message.UserId)
		end
		holder.Visible = true
		holder.Position = UDim2.new(0.5, 0, 0, -HEIGHT - 20)
		pop.Scale = 0.8
		Sounds.play("SecretAnnounce")
		TweenService:Create(holder, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Position = UDim2.new(0.5, 0, 0, 12),
		}):Play()
		TweenService:Create(pop, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		-- ramka mieni się kolorami (fiolet i złoto albo srebro)
		local spin = TweenService:Create(edgeGradient, TweenInfo.new(1.6, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1), {
			Rotation = 360,
		})
		edgeGradient.Rotation = 0
		spin:Play()
		task.wait(SHOW_TIME)
		local out = TweenService:Create(holder, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
			Position = UDim2.new(0.5, 0, 0, -HEIGHT - 20),
		})
		out:Play()
		out.Completed:Wait()
		spin:Cancel()
		holder.Visible = false
	end

	local function run()
		showing = true
		while #queue > 0 do
			local message = table.remove(queue, 1)
			local ok, err = pcall(show, message)
			if not ok then
				warn("[Sekret] komunikat: " .. tostring(err))
				holder.Visible = false
			end
		end
		showing = false
	end

	local function valid(payload)
		if payload.Kind ~= "SecretHatched" or type(payload.Name) ~= "string" then
			return false
		end
		if payload.Item == "Cloth" then
			return type(payload.Category) == "string"
		end
		return type(payload.Zone) == "number"
	end

	State.onNotify(function(payload)
		if not valid(payload) then
			return
		end
		if #queue >= 5 then
			return -- przy zalewie komunikatów (np. testy) nie trzymamy ich bez końca
		end
		table.insert(queue, payload)
		if not showing then
			run()
		end
	end)
end

return SecretBanner
