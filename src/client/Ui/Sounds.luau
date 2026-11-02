-- Dźwięki UI po stronie gracza (słyszy je tylko on). Nazwy i ID w Settings.Sounds.
-- Każdy dźwięk ma kilka kopii, żeby szybkie kliknięcia mogły na siebie nachodzić.

local SoundService = game:GetService("SoundService")
local ContentProvider = game:GetService("ContentProvider")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Settings = require(ReplicatedStorage:WaitForChild("Shared").Config.Settings)

local Sounds = {}

local POOL_SIZE = 6
local pools = {}
local lastPlayed = {}
local playTokens = {} -- [dźwięk] = numer odtworzenia (żeby stare wyciszanie nie ruszało nowego)
local fades = {} -- [dźwięk] = trwające wyciszanie
local streaks = {} -- [nazwa] = { count, time }: ile razy pod rząd (dla dźwięku, który rośnie)

-- Dźwięk z ustawieniem Rise idzie w górę przy każdym kolejnym odtworzeniu pod rząd
-- (jak nuty w Peggle): o Step półtonów, najwyżej o Max półtonów (12 = oktawa, 2× szybciej).
-- Po Reset sekundach przerwy wraca do zwykłej wysokości.
local function risingPitch(name, rise, now)
	local streak = streaks[name]
	if streak == nil then
		streak = { count = 0, time = -math.huge }
		streaks[name] = streak
	end
	local step = rise.Step or 1
	if now - streak.time > (rise.Reset or 0.8) then
		streak.count = 0
	else
		streak.count = math.min(streak.count + 1, math.floor((rise.Max or 12) / step))
	end
	streak.time = now
	return 2 ^ (streak.count * step / 12)
end

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

-- opts: volume (mnożnik głośności), pitch (prędkość; domyślnie lekko losowa albo rosnąca, gdy
-- dźwięk ma w Settings ustawienie Rise)
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
	if fades[sound] ~= nil then
		fades[sound]:Cancel()
		fades[sound] = nil
	end
	local volume = p.info.Volume or 0.5
	if opts ~= nil and opts.volume ~= nil then
		volume = volume * opts.volume
	end
	sound.Volume = volume
	if opts ~= nil and opts.pitch ~= nil then
		sound.PlaybackSpeed = opts.pitch
	elseif p.info.Rise ~= nil then
		sound.PlaybackSpeed = risingPitch(name, p.info.Rise, now)
	else
		sound.PlaybackSpeed = 0.96 + math.random() * 0.08
	end
	sound.TimePosition = 0
	sound:Play()

	-- Length: dźwięk gra najwyżej tyle sekund, a przez ostatnie FadeOut sekund powoli cichnie.
	local length = p.info.Length
	if length ~= nil then
		local token = (playTokens[sound] or 0) + 1
		playTokens[sound] = token
		local fade = p.info.FadeOut or 0
		if fade > 0 then
			task.delay(math.max(0, length - fade), function()
				if playTokens[sound] == token then
					local tween = TweenService:Create(sound, TweenInfo.new(fade, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Volume = 0 })
					fades[sound] = tween
					tween:Play()
				end
			end)
		end
		task.delay(length, function()
			if playTokens[sound] == token then
				sound:Stop()
				fades[sound] = nil
			end
		end)
	end
end

return Sounds
