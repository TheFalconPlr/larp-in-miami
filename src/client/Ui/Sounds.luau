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

-- Czy dźwięk ma ID w Settings (bez ID nic nie gra, np. dźwięk, którego jeszcze nie wybraliśmy).
function Sounds.has(name)
	local info = Settings.Sounds and Settings.Sounds[name]
	return info ~= nil and info.Id ~= nil
end

-- Wczytuje dźwięki z góry, żeby pierwsze kliknięcie nie było ciche. Długich dźwięków w pętli (Looped,
-- np. muzyka) nie wczytujemy od razu: dochodzą przy starcie i nie spowalniają wejścia do gry.
function Sounds.preload()
	local list = {}
	for name, info in pairs(Settings.Sounds or {}) do
		local p = nil
		if not info.Looped then
			p = pool(name)
		end
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
	sound.TimePosition = p.info.Start or 0
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

-- Dźwięk na dłużej (muzyka imprezy, silnik odrzutowca): osobna kopia, która gra aż do stop().
-- Z Settings: Looped (gra w pętli), FadeIn (przez tyle sekund rośnie od ciszy do pełnej głośności,
-- jak rozkręcający się silnik), FadeOut (tyle trwa wyciszanie przy stop) i Start.
-- opts: volume (mnożnik), pitch (prędkość). Zwraca uchwyt { setSpeed(x), stop(fade) }; bez ID dźwięku
-- uchwyt też działa, tylko nic nie gra.
function Sounds.start(name, opts)
	opts = opts or {}
	local handle = {}
	function handle.setSpeed() end
	function handle.stop() end
	local info = Settings.Sounds and Settings.Sounds[name]
	if info == nil or info.Id == nil then
		return handle
	end
	local sound = Instance.new("Sound")
	sound.Name = "Larp" .. name .. "Long"
	sound.SoundId = "rbxassetid://" .. string.format("%d", info.Id)
	sound.Looped = info.Looped == true
	sound.PlaybackSpeed = opts.pitch or 1
	local volume = (info.Volume or 0.5) * (opts.volume or 1)
	local fadeIn = info.FadeIn or 0
	if fadeIn > 0 then
		sound.Volume = 0
	else
		sound.Volume = volume
	end
	sound.Parent = SoundService
	sound.TimePosition = info.Start or 0
	sound:Play()
	local tween = nil
	local function volumeTo(target, seconds, direction)
		if tween ~= nil then
			tween:Cancel()
		end
		tween = TweenService:Create(sound, TweenInfo.new(seconds, Enum.EasingStyle.Quad, direction), { Volume = target })
		tween:Play()
	end
	if fadeIn > 0 then
		-- Quad In: długo cicho, potem coraz szybciej głośniej
		volumeTo(volume, fadeIn, Enum.EasingDirection.In)
	end
	local stopped = false
	function handle.setSpeed(speed)
		if not stopped then
			sound.PlaybackSpeed = speed
		end
	end
	function handle.stop(fade)
		if stopped then
			return
		end
		stopped = true
		fade = fade or info.FadeOut or 0
		if fade > 0 then
			volumeTo(0, fade, Enum.EasingDirection.Out)
			task.delay(fade, function()
				sound:Destroy()
			end)
		else
			sound:Destroy()
		end
	end
	return handle
end

return Sounds
