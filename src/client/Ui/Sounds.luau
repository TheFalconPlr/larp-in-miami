-- Dźwięki UI po stronie gracza (słyszy je tylko on). Nazwy i ID w Settings.Sounds.
-- Każdy dźwięk ma kilka kopii, żeby szybkie kliknięcia mogły na siebie nachodzić.
-- Muzyka gry gra przez SoundGroup „Music” (Settings.Music), którą można płynnie ściszyć, np. na czas
-- muzyki sklepu (Sounds.track + Sounds.duckMusic).

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

-- ID dźwięku: Id albo kilka wersji w Ids (np. 3 różne śmiechy; gra losowa, inna niż poprzednio).
local function soundIds(info)
	if type(info.Ids) == "table" and #info.Ids > 0 then
		return info.Ids
	end
	if info.Id ~= nil then
		return { info.Id }
	end
	return nil
end

local function assetId(id)
	return "rbxassetid://" .. string.format("%d", id)
end

local function pool(name)
	local existing = pools[name]
	if existing ~= nil then
		return existing
	end
	local info = Settings.Sounds and Settings.Sounds[name]
	local ids = info and soundIds(info)
	if ids == nil then
		return nil
	end
	-- każda wersja ma swoje kopie (żeby szybkie odtworzenia mogły na siebie nachodzić)
	local created = { info = info, variants = {}, last = 0 }
	local copies = math.max(2, math.ceil(POOL_SIZE / #ids))
	for v, id in ipairs(ids) do
		local variant = { index = 0, list = {} }
		for i = 1, copies do
			local sound = Instance.new("Sound")
			sound.Name = "Larp" .. name .. v .. "_" .. i
			sound.SoundId = assetId(id)
			sound.Volume = info.Volume or 0.5
			sound.Parent = SoundService
			table.insert(variant.list, sound)
		end
		created.variants[v] = variant
	end
	pools[name] = created
	return created
end

-- Następna kopia dźwięku: z losowej wersji (innej niż ostatnio, gdy jest ich kilka).
local function nextSound(p)
	local count = #p.variants
	local v = 1
	if count > 1 then
		if p.last == 0 then
			v = math.random(1, count)
		else
			v = math.random(1, count - 1)
			if v >= p.last then
				v = v + 1
			end
		end
	end
	p.last = v
	local variant = p.variants[v]
	variant.index = variant.index % #variant.list + 1
	return variant.list[variant.index]
end

-- Czy dźwięk ma ID w Settings (bez ID nic nie gra, np. dźwięk, którego jeszcze nie wybraliśmy).
function Sounds.has(name)
	local info = Settings.Sounds and Settings.Sounds[name]
	return info ~= nil and soundIds(info) ~= nil
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
			for _, variant in ipairs(p.variants) do
				table.insert(list, variant.list[1])
			end
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
	local sound = nextSound(p)
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

-- Dźwięk na dłużej (muzyka, silnik odrzutowca, tykanie zegara): osobna kopia, która gra aż do stop().
-- Z Settings: Looped (gra w pętli), FadeIn (przez tyle sekund rośnie do pełnej głośności, jak
-- rozkręcający się silnik), FadeFrom (od jakiej części głośności zaczyna: 0 = od ciszy, 0.3 = od 30%),
-- FadeOut (tyle trwa wyciszanie przy stop) i Start. opts: volume (mnożnik), pitch (prędkość).
-- Zwraca uchwyt { setSpeed(x), setVolume(mnożnik, sekundy), stop(sekundy) }; bez ID dźwięku uchwyt
-- też działa, tylko nic nie gra.
function Sounds.start(name, opts)
	opts = opts or {}
	local handle = {}
	function handle.setSpeed() end
	function handle.setVolume() end
	function handle.stop() end
	local info = Settings.Sounds and Settings.Sounds[name]
	local ids = info and soundIds(info)
	if ids == nil then
		return handle
	end
	local sound = Instance.new("Sound")
	sound.Name = "Larp" .. name .. "Long"
	sound.SoundId = assetId(ids[math.random(1, #ids)])
	sound.Looped = info.Looped == true
	sound.PlaybackSpeed = opts.pitch or 1
	local volume = (info.Volume or 0.5) * (opts.volume or 1)
	local fadeIn = info.FadeIn or 0
	if fadeIn > 0 then
		sound.Volume = volume * (info.FadeFrom or 0)
	else
		sound.Volume = volume
	end
	if info.Music == true then
		sound.SoundGroup = Sounds.musicGroup()
	end
	sound.Parent = SoundService
	sound.TimePosition = info.Start or 0
	sound:Play()
	local tween = nil
	local function volumeTo(target, seconds)
		if tween ~= nil then
			tween:Cancel()
		end
		tween = TweenService:Create(sound, TweenInfo.new(seconds, Enum.EasingStyle.Linear), { Volume = target })
		tween:Play()
	end
	if fadeIn > 0 then
		volumeTo(volume, fadeIn)
	end
	local stopped = false
	function handle.setSpeed(speed)
		if not stopped then
			sound.PlaybackSpeed = speed
		end
	end
	-- np. ściszenie muzyki na chwilę, żeby było słychać śmiech publiczności (1 = normalnie)
	function handle.setVolume(multiplier, seconds)
		if not stopped then
			volumeTo(volume * multiplier, seconds or 0.3)
		end
	end
	function handle.stop(fade)
		if stopped then
			return
		end
		stopped = true
		fade = fade or info.FadeOut or 0
		if fade > 0 then
			volumeTo(0, fade)
			task.delay(fade, function()
				sound:Destroy()
			end)
		else
			sound:Destroy()
		end
	end
	return handle
end

----------------------------------------------------------------- Muzyka gry i muzyka sklepu
local MUSIC = Settings.Music or {}
local musicGroup = nil
local musicBase = 1 -- głośność grupy ustawiona w Studio (do niej wraca po ściszeniu)
local duckReasons = {}
local duckTween = nil

-- SoundGroup muzyki gry (z SoundService albo nowa). Dźwięki włożone do niej w Studio (też później)
-- dostają SoundGroup = ta grupa, więc grają przez nią i cichną razem z nią.
function Sounds.musicGroup()
	if musicGroup ~= nil and musicGroup.Parent ~= nil then
		return musicGroup
	end
	local name = MUSIC.Group or "Music"
	local group = SoundService:FindFirstChild(name)
	if group == nil or not group:IsA("SoundGroup") then
		group = Instance.new("SoundGroup")
		group.Name = name
		group.Volume = 1
		group.Parent = SoundService
	end
	musicGroup = group
	musicBase = group.Volume
	local function route(item)
		if item:IsA("Sound") then
			item.SoundGroup = group
		end
	end
	for _, item in ipairs(group:GetDescendants()) do
		route(item)
	end
	group.DescendantAdded:Connect(route)
	return group
end

-- Ściszenie muzyki gry z powodu reason (np. "Shop"); wraca, gdy nic jej już nie ścisza.
function Sounds.duckMusic(reason, on)
	if on then
		duckReasons[reason] = true
	else
		duckReasons[reason] = nil
	end
	local group = Sounds.musicGroup()
	local target, time = musicBase, MUSIC.RestoreTime or 1.2
	if next(duckReasons) ~= nil then
		target, time = musicBase * (MUSIC.DuckVolume or 0), MUSIC.DuckTime or 0.6
	end
	if duckTween ~= nil then
		duckTween:Cancel()
	end
	duckTween = TweenService:Create(group, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Volume = target })
	duckTween:Play()
end

-- Muzyka na wyłączność (np. w otwartym sklepie): jedna kopia na nazwę, w pętli, wchodzi i schodzi
-- płynnie (FadeIn, FadeOut), a na czas grania ścisza muzykę gry. Po krótkiej przerwie gra dalej od
-- tego samego miejsca, po dłuższej niż Restart sekund od początku. Zwraca { play(), stop(), preload() };
-- bez ID w Settings nic nie gra i niczego nie ścisza.
local tracks = {}
function Sounds.track(name)
	if tracks[name] ~= nil then
		return tracks[name]
	end
	local handle = {}
	tracks[name] = handle
	local info = Settings.Sounds and Settings.Sounds[name]
	local ids = info and soundIds(info)
	if ids == nil then
		function handle.play() end
		function handle.stop() end
		function handle.preload() end
		return handle
	end
	local sound = Instance.new("Sound")
	sound.Name = "Larp" .. name .. "Track"
	sound.SoundId = assetId(ids[1])
	sound.Looped = true
	sound.Volume = 0
	sound.Parent = SoundService
	local volume = info.Volume or 0.5
	local tween = nil
	local token = 0
	local state = "idle" -- idle (jeszcze nie grała), playing, fading (cichnie po stop), paused
	local stoppedAt = nil
	local function fade(target, seconds)
		if tween ~= nil then
			tween:Cancel()
		end
		tween = TweenService:Create(sound, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Volume = target })
		tween:Play()
	end
	function handle.play()
		token = token + 1
		Sounds.duckMusic(name, true)
		if state == "paused" and stoppedAt ~= nil and os.clock() - stoppedAt <= (info.Restart or 20) then
			sound:Resume()
		elseif state == "paused" or state == "idle" then
			sound.TimePosition = info.Start or 0
			sound:Play()
		end
		-- „fading”: jeszcze gra (cichnie po zamknięciu), więc tylko wraca do pełnej głośności
		state = "playing"
		fade(volume, info.FadeIn or 1)
	end
	function handle.stop()
		if state ~= "playing" then
			return
		end
		token = token + 1
		local mine = token
		state = "fading"
		stoppedAt = os.clock()
		Sounds.duckMusic(name, false)
		local out = info.FadeOut or 0.8
		fade(0, out)
		task.delay(out, function()
			if token == mine then
				sound:Pause()
				state = "paused"
			end
		end)
	end
	-- wczytanie w tle (żeby przy pierwszym otwarciu nie było ciszy)
	function handle.preload()
		task.spawn(function()
			pcall(function()
				ContentProvider:PreloadAsync({ sound })
			end)
		end)
	end
	return handle
end

return Sounds
