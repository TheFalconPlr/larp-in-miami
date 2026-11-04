-- Wywiad w studiu (strefa 3): prowadzący zadaje proste pytania o giełdę, a gracz wybiera jedną z trzech
-- odpowiedzi. Wszystkie są głupie, jak w filmikach z „traderami” z Miami, którzy nie wiedzą, ile spółek
-- jest w S&P 500. Po odpowiedzi studio reaguje (zbliżenie kamery, śmiech publiczności, cisza albo
-- „bruh”), w czacie po prawej lecą komentarze, z rogu wylatują emoji, a licznik wyświetleń rośnie.
-- Na koniec klip idzie do sieci i wyświetlenia dobijają do wyniku.
-- Ocenę (Flop … Mega viral) losuje serwer na starcie sesji, więc odpowiedź jej nie zmienia: jest dla
-- zabawy (inaczej gracze nauczyliby się „najlepszych” odpowiedzi i zawsze mieliby Mega viral).
-- Treść jest w Shared/Config/Interview. Kamerę ustawia scena w Activities według state.shot:
-- wide (plan ogólny), host (prowadzący), hostZoom (zbliżenie na prowadzącego), guest (gracz), side (z boku).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Content = require(Shared.Config.Interview)
local Logic = require(Shared.Logic.Interview)
local Theme = require(script.Parent.Ui.Theme)
local Kit = require(script.Parent.Ui.Kit)
local Sounds = require(script.Parent.Ui.Sounds)
local Pattern = require(script.Parent.Ui.Pattern)

local InterviewShow = {}

-- Czasy programu (s). Sesja trwa tyle, ile w arkuszu (45 s), więc czas na wybór odpowiedzi liczy się
-- z tego, ile zostało: zwykle są 3 pytania, a gdy gracz odpowiada szybko, starcza na 4 albo 5.
-- Napisy pojawiają się litera po literze i zostają chwilę po napisaniu, żeby dało się je przeczytać.
local TIME = {
	hostSpeed = 26, -- tyle znaków na sekundę pisze prowadzący
	guestSpeed = 34, -- a tyle gracz
	read = 1.5, -- tyle sekund napis zostaje po napisaniu
	intro = 2.8, -- powitanie (najkrócej)
	lead = 0.5, -- od napisania pytania do pokazania odpowiedzi (najpierw czytasz pytanie)
	chooseMin = 4, -- najmniej czasu na wybór
	chooseMax = 7, -- najwięcej czasu na wybór
	bonusMin = 3.5, -- najmniej czasu na dodatkowe pytanie (dostaje je tylko ktoś, kto odpowiada szybko)
	toGuest = 1.4, -- po tylu sekundach wybierania kamera przechodzi na gracza
	tick = 3, -- przez tyle ostatnich sekund na odpowiedź tyka zegar
	answer = 1.8, -- odpowiedź gracza (najkrócej)
	react = 2.6, -- reakcja studia (najkrócej)
	silence = 0.8, -- przy ciszy (Crickets) prowadzący najpierw tyle milczy
	signOff = 4.2, -- pożegnanie gracza i odpowiedź prowadzącego (gdy zostanie czasu)
	outro = 2.8, -- najkrótsze zakończenie (klip idzie do sieci)
	margin = 0.45, -- zapas przed końcem sesji (nagroda przychodzi z serwera)
	answerGuess = 2, -- szacunek odpowiedzi gracza i reakcji przy liczeniu czasu na wybór
	reactGuess = 3.4,
}
local QUESTIONS = 3 -- tyle pytań w każdym wywiadzie
local BONUS = 2 -- najwięcej dodatkowych pytań, gdy gracz odpowiada szybko
local RECENT = 8 -- tyle ostatnio zadanych pytań wraca dopiero, gdy zabraknie nowych
local VIEW_SHARE = { 0.04, 0.1, 0.16, 0.2, 0.22 } -- część wyniku (wyświetleń) po kolejnych odpowiedziach
local MAX_COMMENTS = 5
local COMMENT_LIFE = 5.5 -- po tylu sekundach komentarz znika

local CHOICE_COLORS = { Theme.Gradients.Cyan, Theme.Gradients.Pink, Theme.Gradients.Gold }
local REACT_SHOT = { Boom = "hostZoom", Laugh = "wide", Crickets = "side", Bruh = "host" }
local REACT_SOUND = { Boom = "ReactBoom", Laugh = "ReactLaugh", Crickets = "ReactCrickets", Bruh = "ReactBruh" }
local REACT_EMOJI = {
	Boom = { "💀" },
	Laugh = { "😂", "😭", "🤣" },
	Crickets = { "😐", "😬" },
	Bruh = { "😑", "💀" },
}
local HEARTS = { "💖", "💗", "💖" }
local NAME_COLORS = {
	Color3.fromRGB(79, 211, 255),
	Color3.fromRGB(255, 108, 184),
	Color3.fromRGB(255, 218, 61),
	Color3.fromRGB(134, 232, 62),
	Color3.fromRGB(196, 140, 255),
	Color3.fromRGB(255, 150, 70),
}
local KEYS = {
	[Enum.KeyCode.One] = 1,
	[Enum.KeyCode.Two] = 2,
	[Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.KeypadOne] = 1,
	[Enum.KeyCode.KeypadTwo] = 2,
	[Enum.KeyCode.KeypadThree] = 3,
}

local recent = {} -- ostatnio zadane pytania (numery), żeby nie wracały od razu

local function pickOne(list)
	if list == nil or #list == 0 then
		return nil
	end
	return list[math.random(1, #list)]
end

local function remember(number)
	table.insert(recent, number)
	while #recent > RECENT do
		table.remove(recent, 1)
	end
end

-- Kolor nicku w czacie: zawsze ten sam dla tego samego nicku.
local function nameColor(name)
	local sum = 0
	for i = 1, #name do
		sum = sum + string.byte(name, i)
	end
	return NAME_COLORS[sum % #NAME_COLORS + 1]
end

local function setGradient(gradient, colors)
	gradient.Color = ColorSequence.new(colors[1], colors[2])
end

-- Wszystko w środku powoli znika (napisy, obrysy, tła).
local function fadeOut(root, seconds)
	local info = TweenInfo.new(seconds)
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("TextLabel") then
			TweenService:Create(d, info, { TextTransparency = 1 }):Play()
		elseif d:IsA("UIStroke") then
			TweenService:Create(d, info, { Transparency = 1 }):Play()
		elseif d:IsA("Frame") and d.BackgroundTransparency < 1 then
			TweenService:Create(d, info, { BackgroundTransparency = 1 }):Play()
		end
	end
end

-- hud: HUD (gui, registerScale). layer: warstwa na cały ekran w ScreenGui sesji (pod zaciemnieniem),
-- na emoji, które wylatują z prawego dolnego rogu.
function InterviewShow.create(hud, layer)
	local player = Players.LocalPlayer

	------------------------------------------------------------- Okienko z napisami nad paskiem Bag
	-- Ta sama kotwica i skala co pasek Bag (środek dołu ekranu), więc nic nie nachodzi na pasek.
	local holder = Kit.new("Frame", {
		Name = "InterviewShow",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -30),
		Size = UDim2.fromOffset(1000, 520),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = hud.gui,
	})
	hud.registerScale(holder)

	local BOX_SIZE = Vector2.new(760, 96)
	local box = Kit.new("Frame", {
		Name = "Dialog",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromOffset(500, 422),
		Size = UDim2.fromOffset(BOX_SIZE.X, BOX_SIZE.Y),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = holder,
	})
	-- środek inner w środku okienka: UIScale powiększa je od środka
	local boxInner = Kit.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = box,
	})
	local boxPop = Kit.new("UIScale", { Parent = boxInner })
	local boxEdge = Kit.new("Frame", {
		Position = UDim2.fromOffset(0, 7),
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Outline,
		BorderSizePixel = 0,
		ZIndex = 1,
		Parent = boxInner,
	})
	Kit.corner(boxEdge, 26)
	local boxBody = Kit.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.White,
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = boxInner,
	})
	Kit.corner(boxBody, 26)
	Kit.stroke(boxBody, 5, Enum.ApplyStrokeMode.Border)
	Kit.gradient(boxBody, Theme.Gradients.Panel, 90)
	Pattern.fill(boxBody, BOX_SIZE, { radius = 26 })
	local boxText = Kit.text(boxInner, {
		Name = "Text",
		Position = UDim2.fromOffset(30, 12),
		Size = UDim2.new(1, -60, 1, -36),
		Text = "",
		TextWrapped = true,
		ZIndex = 4,
	}, { maxSize = 32, stroke = 3.5 })
	-- kto mówi (prowadzący albo gracz): kolorowa plakietka na górnej krawędzi okienka
	local tag = Kit.new("Frame", {
		Name = "Speaker",
		Position = UDim2.fromOffset(28, -26),
		Size = UDim2.fromOffset(140, 40),
		BackgroundColor3 = Theme.White,
		BorderSizePixel = 0,
		Rotation = -3,
		ZIndex = 5,
		Parent = boxInner,
	})
	Kit.corner(tag, 20)
	Kit.stroke(tag, 4, Enum.ApplyStrokeMode.Border)
	local tagGradient = Kit.gradient(tag, Theme.Gradients.Pink, 90)
	local tagLabel = Kit.text(tag, {
		Position = UDim2.fromOffset(12, 4),
		Size = UDim2.new(1, -24, 1, -8),
		Text = "",
		ZIndex = 6,
	}, { maxSize = 24, stroke = 3 })
	-- czas na odpowiedź: pasek na dole okienka kurczy się do środka, w ostatniej sekundzie jest czerwony
	local timerTrack = Kit.new("Frame", {
		Name = "AnswerTimer",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -10),
		Size = UDim2.new(1, -90, 0, 10),
		BackgroundColor3 = Theme.PatternColor,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 4,
		Parent = boxInner,
	})
	Kit.corner(timerTrack, 5)
	Kit.stroke(timerTrack, 2.5, Enum.ApplyStrokeMode.Border)
	local timerFill = Kit.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.White,
		BorderSizePixel = 0,
		ZIndex = 5,
		Parent = timerTrack,
	})
	Kit.corner(timerFill, 5)
	local timerGradient = Kit.gradient(timerFill, Theme.Gradients.LP, 90)

	local typing = nil -- { start, total, speed }: napis pojawia się litera po literze
	-- Zwraca, ile sekund potrwa pisanie napisu.
	local function say(who, text)
		local name, colors, speed = Content.Host, Theme.Gradients.Pink, TIME.hostSpeed
		if who == "guest" then
			name, colors, speed = player.DisplayName, Theme.Gradients.Cyan, TIME.guestSpeed
		end
		tagLabel.Text = name
		setGradient(tagGradient, colors)
		tag.Size = UDim2.fromOffset(math.max(100, Kit.measure(name, 24).X + 34), 40)
		boxText.Text = text
		boxText.MaxVisibleGraphemes = 0
		typing = { start = os.clock(), total = Logic.length(text), speed = speed }
		box.Visible = true
		boxPop.Scale = 0.93
		TweenService:Create(boxPop, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		return typing.total / speed
	end

	------------------------------------------------------------- Przyciski z odpowiedziami
	local pickSound = "Button"
	if Sounds.has("AnswerPick") then
		pickSound = "AnswerPick"
	end
	local choosing = nil -- { picked, start, time, red } w czasie wybierania
	local ticking = nil -- tykanie zegara (dźwięk w pętli) w ostatnich sekundach wybierania
	local function stopTicking()
		if ticking ~= nil then
			ticking.stop(0.15)
			ticking = nil
		end
	end
	local choices = {}
	local function choose(i)
		local entry = choices[i]
		if choosing ~= nil and choosing.picked == nil and entry ~= nil and entry.used then
			choosing.picked = i
		end
	end
	for i = 1, Logic.AnswerCount do
		local button = Kit.button(holder, {
			name = "Answer" .. i,
			size = Vector2.new(280, 74),
			text = "",
			colors = CHOICE_COLORS[i] or Theme.Gradients.Green,
			textSize = 28,
			anchor = Vector2.new(0.5, 1),
			position = UDim2.fromOffset(500 + (i - 2) * 300, 290),
			sound = pickSound,
		})
		button.label.TextWrapped = true
		button.holder.Visible = false
		local pop = Kit.new("UIScale", { Scale = 0, Parent = button.body })
		-- na komputerze cyfra w rogu: odpowiedź można też wybrać klawiszem 1, 2 albo 3
		if UserInputService.KeyboardEnabled then
			local key = Kit.new("Frame", {
				Name = "Key",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(12, 10),
				Size = UDim2.fromOffset(34, 34),
				BackgroundColor3 = Theme.Outline,
				BorderSizePixel = 0,
				Rotation = -6,
				ZIndex = 8,
				Parent = button.face,
			})
			Kit.corner(key, 10)
			Kit.stroke(key, 3, Enum.ApplyStrokeMode.Border, Theme.White)
			Kit.text(key, {
				Position = UDim2.fromOffset(4, 3),
				Size = UDim2.new(1, -8, 1, -6),
				Text = tostring(i),
				ZIndex = 9,
			}, { maxSize = 22, stroke = 0 })
		end
		choices[i] = { button = button, pop = pop, used = false }
		button.Activated:Connect(function()
			choose(i)
		end)
	end
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or choosing == nil or choosing.picked ~= nil then
			return
		end
		local i = KEYS[input.KeyCode]
		if i ~= nil and choices[i] ~= nil and choices[i].used then
			Sounds.play(pickSound)
			choose(i)
		end
	end)

	local function showChoices(answers, seconds)
		stopTicking()
		choosing = { picked = nil, start = os.clock(), time = seconds, red = false }
		for i, entry in ipairs(choices) do
			local answer = answers[i]
			entry.used = answer ~= nil
			entry.button.holder.Visible = entry.used
			if answer ~= nil then
				entry.button.setText(answer.Say)
				entry.pop.Scale = 0
				TweenService:Create(
					entry.pop,
					TweenInfo.new(0.26, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0, false, (i - 1) * 0.07),
					{ Scale = 1 }
				):Play()
			end
		end
		timerFill.Size = UDim2.fromScale(1, 1)
		setGradient(timerGradient, Theme.Gradients.LP)
		timerTrack.Visible = true
	end

	-- Wybrana odpowiedź podskakuje, reszta znika; po chwili znika też wybrana.
	local function closeChoices(picked)
		choosing = nil
		stopTicking()
		timerTrack.Visible = false
		for i, entry in ipairs(choices) do
			if entry.used then
				if i == picked then
					TweenService:Create(entry.pop, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1.12 }):Play()
					task.delay(0.3, function()
						if choosing == nil then
							TweenService:Create(entry.pop, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Scale = 0 }):Play()
						end
					end)
				else
					TweenService:Create(entry.pop, TweenInfo.new(0.14, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Scale = 0 }):Play()
				end
			end
			entry.used = false
		end
	end

	local function hideChoices()
		choosing = nil
		stopTicking()
		timerTrack.Visible = false
		for _, entry in ipairs(choices) do
			entry.used = false
			entry.pop.Scale = 0
			entry.button.holder.Visible = false
		end
	end

	------------------------------------------------------------- Czat po prawej (jak na transmisji na żywo)
	local feed = Kit.new("Frame", {
		Name = "InterviewChat",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 96),
		Size = UDim2.fromOffset(320, 270),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = hud.gui,
	})
	local feedScale = hud.registerScale(feed)
	Kit.new("UIListLayout", {
		Padding = UDim.new(0, 4),
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = feed,
	})
	local comments = {} -- { frame, born, fading }
	local commentCount = 0

	-- Komentarz: kółko z literą, kolorowy nick i biały napis z obrysem (bez tła, jak w czacie na wideo).
	local function addComment(text, user)
		if text == nil or text == "" then
			return
		end
		user = user or pickOne(Content.Users) or "viewer"
		commentCount = commentCount + 1
		local frame = Kit.new("Frame", {
			Name = "Comment",
			Size = UDim2.new(1, 0, 0, 52),
			BackgroundTransparency = 1,
			LayoutOrder = commentCount,
			Parent = feed,
		})
		-- treść wjeżdża z prawej (ramkę ustawia lista, więc przesuwamy to, co w środku)
		local inner = Kit.new("Frame", {
			Position = UDim2.fromOffset(70, 0),
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Parent = frame,
		})
		local color = nameColor(user)
		local avatar = Kit.new("Frame", {
			Position = UDim2.fromOffset(0, 8),
			Size = UDim2.fromOffset(36, 36),
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			Parent = inner,
		})
		Kit.corner(avatar, 18)
		Kit.stroke(avatar, 3, Enum.ApplyStrokeMode.Border)
		Kit.text(avatar, {
			Position = UDim2.fromOffset(4, 4),
			Size = UDim2.new(1, -8, 1, -8),
			Text = string.upper(string.sub(user, 1, 1)),
		}, { maxSize = 20, stroke = 2 })
		Kit.text(inner, {
			Position = UDim2.fromOffset(44, 2),
			Size = UDim2.new(1, -44, 0, 18),
			Text = user,
			TextColor3 = color,
			TextXAlignment = Enum.TextXAlignment.Left,
		}, { maxSize = 17, stroke = 2.5 })
		Kit.text(inner, {
			Position = UDim2.fromOffset(44, 20),
			Size = UDim2.new(1, -44, 0, 30),
			Text = text,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
		}, { maxSize = 22, stroke = 2.5 })
		TweenService:Create(inner, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = UDim2.fromOffset(0, 0) }):Play()
		table.insert(comments, { frame = frame, born = os.clock(), fading = false })
		while #comments > MAX_COMMENTS do
			table.remove(comments, 1).frame:Destroy()
		end
		Sounds.play("Comment")
	end

	local function clearComments()
		for _, c in ipairs(comments) do
			c.frame:Destroy()
		end
		comments = {}
	end

	------------------------------------------------------------- Emoji lecące w górę (serduszka, 💀, 😭)
	local floaters = {}
	local function float(list, count)
		local size = layer.AbsoluteSize
		if size.X <= 0 or list == nil then
			return
		end
		local s = feedScale.Scale
		for k = 1, count do
			local label = Kit.new("TextLabel", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundTransparency = 1,
				Font = Theme.Font,
				Text = list[math.random(1, #list)],
				TextSize = math.floor((30 + math.random() * 18) * s),
				TextColor3 = Theme.White,
				Visible = false,
				Parent = layer,
			})
			table.insert(floaters, {
				label = label,
				t = -(k - 1) * 0.09,
				life = 1.7 + math.random() * 0.7,
				x = size.X - (60 + math.random() * 80) * s,
				y = size.Y - (200 + math.random() * 30) * s,
				rise = (240 + math.random() * 170) * s,
				drift = (math.random() - 0.5) * 70 * s,
				sway = math.random() * 6.28,
				wobble = 12 * s,
			})
		end
	end

	local function clearFloaters()
		for _, f in ipairs(floaters) do
			f.label:Destroy()
		end
		floaters = {}
	end

	------------------------------------------------------------- Co klatkę
	local function step(dt)
		if typing ~= nil then
			local shown = math.floor((os.clock() - typing.start) * typing.speed)
			if shown >= typing.total then
				boxText.MaxVisibleGraphemes = -1
				typing = nil
			else
				boxText.MaxVisibleGraphemes = shown
			end
		end
		if choosing ~= nil then
			local left = choosing.time - (os.clock() - choosing.start)
			timerFill.Size = UDim2.fromScale(math.clamp(left / choosing.time, 0, 1), 1)
			if left <= 1 and not choosing.red then
				choosing.red = true
				setGradient(timerGradient, Theme.Gradients.Red)
			end
			if left <= TIME.tick and left > 0 and ticking == nil then
				ticking = Sounds.start("AnswerTick")
			end
		end
		local now = os.clock()
		for i = #comments, 1, -1 do
			local c = comments[i]
			local age = now - c.born
			if age > COMMENT_LIFE + 0.4 then
				c.frame:Destroy()
				table.remove(comments, i)
			elseif age > COMMENT_LIFE and not c.fading then
				c.fading = true
				fadeOut(c.frame, 0.4)
			end
		end
		for i = #floaters, 1, -1 do
			local f = floaters[i]
			f.t = f.t + dt
			if f.t >= f.life then
				f.label:Destroy()
				table.remove(floaters, i)
			elseif f.t >= 0 then
				local p = f.t / f.life
				local ease = 1 - (1 - p) * (1 - p)
				f.label.Visible = true
				f.label.Position = UDim2.fromOffset(f.x + f.drift * p + math.sin(f.sway + f.t * 4) * f.wobble, f.y - f.rise * ease)
				if p > 0.65 then
					f.label.TextTransparency = (p - 0.65) / 0.35
				end
			end
		end
	end

	------------------------------------------------------------- Program
	local api = {}

	-- Zaczyna program. opts: duration (s), grade (1–4), target (wyświetlenia na koniec), onEmote(name).
	-- Zwraca { state, stop() }: state.shot i state.shotAt (os.clock) czyta kamera, a state.views
	-- to wyświetlenia, do których dąży licznik.
	function api.begin(opts)
		local state = { alive = true, shot = "wide", shotAt = os.clock(), views = 0 }
		local started = os.clock()
		local deadline = (opts.duration or 25) - TIME.margin
		local grade = opts.grade or 2
		local target = opts.target or 1000
		local hype = 0.5 + 0.25 * grade -- przy lepszej ocenie więcej serduszek i emoji
		local function now()
			return os.clock() - started
		end
		local function wait(seconds)
			local untilTime = os.clock() + seconds
			repeat
				task.wait()
				if not state.alive then
					return false
				end
			until os.clock() >= untilTime
			return true
		end
		local function cut(shot)
			state.shot = shot
			state.shotAt = os.clock()
		end
		local function emote(name)
			if opts.onEmote ~= nil then
				opts.onEmote(name)
			end
		end

		hideChoices()
		clearComments()
		clearFloaters()
		typing = nil
		box.Visible = false
		holder.Visible = true
		feed.Visible = true

		local nextHeart = 0.8
		local connection = RunService.RenderStepped:Connect(function(dt)
			step(dt)
			if now() >= nextHeart then
				nextHeart = now() + 0.6 / hype
				float(HEARTS, 1)
			end
		end)
		-- muzyka talk show przez cały program
		local music = Sounds.start("InterviewMusic")

		-- Jedno pytanie: prowadzący pyta, gracz czyta pytanie, potem wybiera (albo czas mija i mówi coś
		-- losowego), a studio reaguje. index = które to pytanie w wywiadzie. false = program przerwany.
		local function ask(question, number, seconds, index)
			remember(number)
			local answers = Logic.shuffle(question.Answers, math.random)
			cut("host")
			local typed = say("host", question.Ask)
			if not wait(typed + TIME.lead) then
				return false
			end
			showChoices(answers, seconds)
			local onGuest = false
			local thinking = math.random() < 0.5
			local startAt = os.clock()
			while choosing ~= nil and choosing.picked == nil and os.clock() - startAt < seconds do
				local t = os.clock() - startAt
				if not onGuest and t >= TIME.toGuest then
					onGuest = true
					cut("guest") -- gracz myśli, a kamera powoli się zbliża
				end
				if thinking and t >= 2.2 then
					thinking = false
					addComment(pickOne(Content.Comments.Thinking))
				end
				task.wait()
				if not state.alive then
					return false
				end
			end
			if not state.alive then
				return false
			end
			local picked = choosing and choosing.picked
			local line = nil
			if picked == nil then
				picked = math.random(1, #answers)
				line = Content.Stall .. answers[picked].Say
			end
			closeChoices(picked)
			local answer = answers[picked]
			-- gracz odpowiada pewnie siebie (z palcem w stronę prowadzącego); kamera zostaje na nim
			if not onGuest then
				cut("guest")
			end
			local typedAnswer = say("guest", line or answer.Say)
			emote("point")
			if not wait(math.max(TIME.answer, typedAnswer + 1.2)) then
				return false
			end
			-- reakcja studia (muzyka na chwilę ciszej, żeby było słychać śmiech, „boom” albo świerszcze)
			local react = answer.React
			cut(REACT_SHOT[react] or "host")
			music.setVolume(0.35, 0.2)
			Sounds.play(REACT_SOUND[react])
			if react == "Crickets" then
				say("host", "...")
				if not wait(TIME.silence) then
					return false
				end
			end
			local typedReply = say("host", answer.Reply)
			addComment(answer.Comment)
			float(REACT_EMOJI[react] or HEARTS, math.floor(4 * hype + 0.5))
			state.views = state.views + target * (VIEW_SHARE[index] or 0.1)
			local hold = math.max(TIME.react, typedReply + TIME.read)
			if not wait(0.6) then
				return false
			end
			addComment(pickOne(Content.Comments[react]))
			local finished = wait(math.max(0.3, hold - 0.6))
			music.setVolume(1, 0.8)
			return finished
		end

		-- Pożegnanie: gracz mówi coś na koniec, a prowadzący odpowiada (gdy po pytaniach zostało czasu).
		local function signOff()
			local pair = pickOne(Content.SignOff)
			if pair == nil then
				return true
			end
			cut("guest")
			local typedSay = say("guest", pair.Say)
			emote("wave")
			if not wait(math.max(1.8, typedSay + 1.1)) then
				return false
			end
			cut("host")
			local typedReply = say("host", pair.Reply)
			addComment(pickOne(Content.Comments.Laugh))
			return wait(math.max(2, typedReply + 1.2))
		end

		task.spawn(function()
			local ok, err = pcall(function()
				cut("wide")
				local typedIntro = say("host", pickOne(Content.Intro))
				state.views = target * 0.012
				addComment(pickOne(Content.Comments.Intro))
				if not wait(math.max(TIME.intro, typedIntro + TIME.read)) then
					return
				end
				-- czas na odpowiedź tak, żeby zmieściły się 3 pytania i zakończenie; przy szybkich
				-- odpowiedziach zostaje czas na dodatkowe pytania i pożegnanie
				local plan = Logic.pick(#Content.Questions, QUESTIONS + BONUS, math.random, recent)
				local asked = 0
				for _, number in ipairs(plan) do
					local question = Content.Questions[number]
					local fixed = Logic.length(question.Ask) / TIME.hostSpeed + TIME.lead + TIME.answerGuess + TIME.reactGuess
					local remaining = deadline - now() - TIME.outro
					local seconds
					if asked < QUESTIONS then
						if remaining < fixed + TIME.chooseMin then
							break
						end
						local left = QUESTIONS - asked
						seconds = math.clamp((remaining - fixed * left) / left, TIME.chooseMin, TIME.chooseMax)
					else
						seconds = math.min(TIME.chooseMax, remaining - fixed)
						if seconds < TIME.bonusMin then
							break
						end
					end
					asked = asked + 1
					if not ask(question, number, seconds, asked) then
						return
					end
				end
				if deadline - now() - TIME.outro >= TIME.signOff then
					if not signOff() then
						return
					end
				end
				-- koniec: klip idzie do sieci, wyświetlenia dobijają do wyniku, czat szaleje
				cut("wide")
				local typedOutro = say("host", pickOne(Content.Outro))
				if not wait(math.max(1.4, typedOutro + 0.6)) then
					return
				end
				Sounds.play("ClipPosted")
				state.views = target
				local list = Content.Comments.Grades[grade] or Content.Comments.Grades[2]
				local beat = 0
				while now() < deadline do
					beat = beat + 1
					addComment(pickOne(list))
					float(HEARTS, math.floor(3 * hype + 0.5))
					if beat == 2 then
						cut("guest")
						emote("cheer")
					elseif beat == 4 then
						cut("side")
					elseif beat == 6 then
						cut("wide")
					end
					if not wait(0.9) then
						return
					end
				end
			end)
			if not ok then
				warn("[Wywiad] " .. tostring(err))
			end
		end)

		local handle = { state = state }
		function handle.stop()
			if not state.alive then
				return
			end
			state.alive = false
			connection:Disconnect()
			music.stop()
			hideChoices()
			clearComments()
			clearFloaters()
			typing = nil
			box.Visible = false
			holder.Visible = false
			feed.Visible = false
		end
		return handle
	end

	return api
end

return InterviewShow
