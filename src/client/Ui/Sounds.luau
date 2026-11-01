-- Dźwięki UI po stronie gracza (słyszy je tylko on). Nazwy i ID w Settings.Sounds.
-- Każdy dźwięk ma kilka kopii, żeby szybkie kliknięcia mogły na siebie nachodzić.

local SoundService = game:GetService("SoundService")
local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Settings = require(ReplicatedStorage:WaitForChild("Shared").Config.Settings)

local Sounds = {}

local POOL_SIZE = 6
local pools = {}
local lastPlayed = {}

local function pool(name)
	local existing = pools[name]
	if existing ~= nil then
		return existing
	end
	local info = Settings.Sounds and Settings.Sounds[name]
	if info == nil or info.Id == nil then
		return nil
	end
	local created = { index = 0, list = {}, info = info }
	for i = 1, POOL_SIZE do
		local sound = Instance.new("Sound")
		sound.Name = "Larp" .. name .. i
		sound.SoundId = "rbxassetid://" .. string.format("%d", info.Id)
		sound.Volume = info.Volume or 0.5
		sound.Parent = SoundService
		table.insert(created.list, sound)
	end
	pools[name] = created
	return created
end

-- Wczytuje dźwięki z góry, żeby pierwsze kliknięcie nie było ciche.
function Sounds.preload()
	local list = {}
	for name in pairs(Settings.Sounds or {}) do
		local p = pool(name)
		if p ~= nil then
			table.insert(list, p.list[1])
		end
	end
	task.spawn(function()
		pcall(function()
			ContentProvider:PreloadAsync(list)
		end)
	end)
end

-- opts: volume (mnożnik głośności), pitch (prędkość; domyślnie lekko losowa)
function Sounds.play(name, opts)
	local p = pool(name)
	if p == nil then
		return
	end
	local now = os.clock()
	local gap = p.info.MinGap or 0
	if lastPlayed[name] ~= nil and now - lastPlayed[name] < gap then
		return
	end
	lastPlayed[name] = now
	p.index = p.index % #p.list + 1
	local sound = p.list[p.index]
	local volume = p.info.Volume or 0.5
	if opts ~= nil and opts.volume ~= nil then
		volume = volume * opts.volume
	end
	sound.Volume = volume
	if opts ~= nil and opts.pitch ~= nil then
		sound.PlaybackSpeed = opts.pitch
	else
		sound.PlaybackSpeed = 0.96 + math.random() * 0.08
	end
	sound.TimePosition = 0
	sound:Play()
end

return Sounds
