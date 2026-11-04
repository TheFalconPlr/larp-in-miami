-- Tytuł Rebirth i Aura Level nad głową każdego gracza oraz poświata wokół awatara (Etap 9).
-- Serwer ustawia atrybuty gracza (LarpRebirth = poziom Rebirth, LarpAuraLevel = Aura Level), a każdy
-- klient rysuje u siebie napis i iskry. Poświata jest od Aura Level 10, w kolorze progu: biała, niebieska,
-- fioletowa, złota, czerwona, tęczowa (Economy.Aura.Glow, kolory w Theme.GlowColors).
-- W czasie aktywności (State.busy) napisy są schowane, a poświata innych graczy też (inni gracze
-- i tak znikają na czas sceny).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Formulas = require(Shared.Formulas)
local Rebirth = require(Shared.Logic.Rebirth)
local State = require(script.Parent.State)
local Theme = require(script.Parent.Ui.Theme)
local Kit = require(script.Parent.Ui.Kit)

local Nametags = {}

local LEVEL_ATTRIBUTE = "LarpRebirth" -- jak RebirthService.LevelAttribute
local AURA_ATTRIBUTE = "LarpAuraLevel" -- jak RebirthService.AuraLevelAttribute
local SPARKLES = "rbxasset://textures/particles/sparkles_main.dds" -- iskry wbudowane w Roblox

local function glowSequence(glow)
	if glow == "Rainbow" then
		local points = {}
		local n = #Theme.Rainbow
		for i, color in ipairs(Theme.Rainbow) do
			table.insert(points, ColorSequenceKeypoint.new((i - 1) / (n - 1), color))
		end
		return ColorSequence.new(points)
	end
	return ColorSequence.new(Theme.GlowColors[glow] or Theme.White)
end

function Nametags.start(hud)
	local localPlayer = Players.LocalPlayer
	local playerGui = localPlayer:WaitForChild("PlayerGui")
	local entries = {} -- [gracz] = { gui, line, emitter, light, glow }

	local function clearGlow(entry)
		if entry.emitter ~= nil then
			entry.emitter:Destroy()
			entry.emitter = nil
		end
		if entry.light ~= nil then
			entry.light:Destroy()
			entry.light = nil
		end
		entry.glow = nil
	end

	local function refresh(player)
		local entry = entries[player]
		if entry == nil then
			return
		end
		local character = player.Character
		local head = character and character:FindFirstChild("Head")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local level = player:GetAttribute(LEVEL_ATTRIBUTE)
		local auraLevel = player:GetAttribute(AURA_ATTRIBUTE) or 0
		local busy = State.busy
		local mine = player == localPlayer

		-- napis: tytuł w kolorze poziomu i Aura Level (gdy jest)
		entry.gui.Adornee = head
		if type(level) == "number" then
			local items = {
				{ text = Rebirth.title(level), size = 24, colors = Theme.TitleColors[level] or Theme.TitleColors[Rebirth.Cap] },
			}
			if auraLevel > 0 then
				table.insert(items, { icon = "Aura", size = 24 })
				table.insert(items, { text = tostring(auraLevel), size = 22, colors = Theme.Gradients.Aura })
			end
			entry.line.set(items)
		end
		entry.gui.Enabled = head ~= nil and type(level) == "number" and not busy

		-- poświata: iskry wokół postaci i światło w kolorze progu Aura Level
		local glow = Formulas.glowFor(auraLevel)
		local show = glow ~= nil and root ~= nil and (mine or not busy)
		if not show then
			clearGlow(entry)
			return
		end
		if entry.emitter == nil or entry.emitter.Parent ~= root or entry.glow ~= glow then
			clearGlow(entry)
			local emitter = Instance.new("ParticleEmitter")
			emitter.Name = "LarpAuraGlow"
			emitter.Texture = SPARKLES
			emitter.Color = glowSequence(glow)
			emitter.LightEmission = 1
			emitter.LightInfluence = 0
			emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 0) })
			emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 1) })
			emitter.Lifetime = NumberRange.new(0.8, 1.4)
			emitter.Rate = (glow == "Rainbow" and 24) or 14
			emitter.Speed = NumberRange.new(1.5, 3)
			emitter.SpreadAngle = Vector2.new(30, 30)
			emitter.EmissionDirection = Enum.NormalId.Top
			emitter.Acceleration = Vector3.new(0, 1.5, 0)
			emitter.Parent = root
			local light = Instance.new("PointLight")
			light.Name = "LarpAuraLight"
			light.Color = Theme.GlowColors[glow] or Theme.Rainbow[5]
			light.Range = 9
			light.Brightness = 1.2
			light.Shadows = false
			light.Parent = root
			entry.emitter = emitter
			entry.light = light
			entry.glow = glow
		end
	end

	local function add(player)
		if entries[player] ~= nil then
			return
		end
		local gui = Kit.new("BillboardGui", {
			Name = "Nametag_" .. tostring(player.UserId),
			Size = UDim2.fromOffset(360, 40),
			StudsOffset = Vector3.new(0, 2.6, 0),
			LightInfluence = 0,
			AlwaysOnTop = false,
			MaxDistance = 70,
			ResetOnSpawn = false,
			Enabled = false,
			Parent = playerGui,
		})
		local holder = Kit.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Parent = gui,
		})
		hud.registerScale(holder)
		local line = Kit.line(holder, { anchor = Vector2.new(0.5, 0.5), position = UDim2.fromScale(0.5, 0.5), height = 36 })
		local entry = { gui = gui, line = line }
		entries[player] = entry
		player:GetAttributeChangedSignal(LEVEL_ATTRIBUTE):Connect(function()
			refresh(player)
		end)
		player:GetAttributeChangedSignal(AURA_ATTRIBUTE):Connect(function()
			refresh(player)
		end)
		player.CharacterAdded:Connect(function(character)
			-- głowa i HumanoidRootPart dochodzą chwilę po postaci
			task.spawn(function()
				character:WaitForChild("Head", 10)
				character:WaitForChild("HumanoidRootPart", 10)
				refresh(player)
			end)
		end)
		refresh(player)
	end

	local function remove(player)
		local entry = entries[player]
		if entry == nil then
			return
		end
		clearGlow(entry)
		entry.gui:Destroy()
		entries[player] = nil
	end

	for _, player in ipairs(Players:GetPlayers()) do
		add(player)
	end
	Players.PlayerAdded:Connect(add)
	Players.PlayerRemoving:Connect(remove)

	-- początek i koniec aktywności (State.busy) chowa i pokazuje napisy
	local lastBusy = nil
	State.onChange(function()
		if State.busy ~= lastBusy then
			lastBusy = State.busy
			for player in pairs(entries) do
				refresh(player)
			end
		end
	end)
	task.spawn(function()
		-- State.busy zmienia się też bez Sync (np. start aktywności), więc sprawdzamy co chwilę
		while true do
			task.wait(0.5)
			if State.busy ~= lastBusy then
				lastBusy = State.busy
				for player in pairs(entries) do
					refresh(player)
				end
			end
		end
	end)
end

return Nametags
