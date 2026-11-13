-- Nagrody (Etap 11). Logika jest w Shared/Logic/Rewards, a tu żądania gracza i komunikaty dla klienta.
--
-- Nagroda dzienna: ClaimDaily() (z każdego miejsca: okno wyskakuje samo po wejściu, a tablica
-- z nagrodą dzienną w Downtown otwiera je klawiszem E). Tablica: model albo część „DailyBoard”
-- (tag LarpDaily nadaje serwer); gdy jej nie ma, serwer stawia tymczasową obok pola Sell.
-- O północy UTC gracze dostają nowy stan i Notify „DailyReady”.
--
-- Zadania dzienne: 3 na dzień UTC (Logic/Rewards, zapis data.Quests). Postęp przychodzi z innych
-- serwisów przez LoopService.progress (kliki gracza, Sell na polu, aktywności, jajka za L$, łączenie).
-- Skończone zadanie czeka na gracza: dostaje on Notify „QuestReady” i sam odbiera nagrodę przyciskiem
-- CLAIM (lista zadań po prawej albo okno: ClaimQuest(numer)); bez miejsca w ekwipunku nagroda czeka
-- dalej. Nieodebrane nagrody przepadają z nowym dniem UTC, razem ze starymi zadaniami. Nagroda idzie
-- przez deliver (Source = "Quest", z Aura i BonusAura), a stan okna w view.Quests.
--
-- Kody: pole na kod jest na samym dole sklepu (ShopWindow, zakładka FREE, jak w Pet Simulator 99).
-- RedeemCode(tekst): kod z Economy.Rewards.Codes, każdy raz na konto (data.Codes). Odpowiedź:
-- { Ok, Code, Reason, Boosts, Pets, Items }. Jajka i boxy z nagrody klient otwiera tą samą animacją
-- co kupione: Notify „Reward” z Eggs = { { Zone, Egg, Pets } } i Boxes = { { Box, Items } }.
-- Bonus za grupę i znajomych liczy BonusService; tu tylko dopisujemy go do stanu gracza.

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared.Config.Economy)
local PetsConfig = require(Shared.Config.Pets)
local ClothesConfig = require(Shared.Config.Clothes)
local Loop = require(Shared.Logic.Loop)
local Rewards = require(Shared.Logic.Rewards)
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)
local LoopService = require(script.Parent.LoopService)
local PetService = require(script.Parent.PetService)
local ClothesService = require(script.Parent.ClothesService)
local BonusService = require(script.Parent.BonusService)

local RewardsService = {}

RewardsService.DailyTag = "LarpDaily" -- tablica z nagrodą dzienną (klient szuka jej po tagu)

local CODE_GAP = 1.2 -- najmniejszy odstęp między próbami wpisania kodu (s)
local CLAIM_GAP = 1 -- najmniejszy odstęp między próbami odebrania nagrody dziennej (s)
local DAY_CHECK = 5 -- co tyle sekund sprawdzamy, czy minęła północ UTC
local WRONG_LIMIT = 6 -- tyle złych kodów pod rząd…
local WRONG_PAUSE = 30 -- …i potem tyle sekund przerwy
local SECRET_EXTRA = 3 -- komunikat o sekrecie z nagrody po animacjach (s)
local QUEST_CLAIM_GAP = 0.4 -- najmniejszy odstęp między CLAIM przy zadaniach (s; można odebrać kilka pod rząd)

local lastTry = {} -- [gracz] = os.clock() ostatniej próby
local lastClaim = {} -- [gracz] = os.clock() ostatniego odbioru nagrody dziennej
local lastQuestClaim = {} -- [gracz] = os.clock() ostatniego CLAIM przy zadaniu
local boards = {}
local wrong = {} -- [gracz] = { count = złe pod rząd, untilTime = koniec przerwy }

local rng = Random.new()
local function random01()
	return rng:NextNumber()
end

local function limitsFor()
	return { pets = PetsConfig.MaxInventory, clothes = ClothesConfig.MaxInventory }
end

----------------------------------------------------------------- Tablica z nagrodą dzienną
local function addBoard(inst)
	for _, existing in ipairs(boards) do
		if existing == inst then
			return
		end
	end
	CollectionService:AddTag(inst, RewardsService.DailyTag)
	table.insert(boards, inst)
end

local function scan()
	for _, inst in ipairs(Workspace:GetDescendants()) do
		if (inst:IsA("Model") or inst:IsA("BasePart")) and inst.Name == "DailyBoard" then
			addBoard(inst)
		end
	end
end

local function block(model, name, size, cframe, color, material)
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = model
	return part
end

-- Tymczasowa tablica: dwa słupki, biała tablica w złotej ramce i prezent z kokardą na górze.
-- frame = środek między słupkami na ziemi, przodem (LookVector) do gracza.
local function buildBoard(frame)
	local model = Instance.new("Model")
	model.Name = "DailyBoard"
	local dark = Color3.fromRGB(44, 34, 66)
	local gold = Color3.fromRGB(255, 200, 60)
	local red = Color3.fromRGB(235, 52, 84)
	for _, x in ipairs({ -3.4, 3.4 }) do
		block(model, "Post", Vector3.new(0.6, 8, 0.6), frame * CFrame.new(x, 4, 0), dark)
	end
	block(model, "Board", Vector3.new(7.4, 4.4, 0.4), frame * CFrame.new(0, 5.6, 0), Color3.fromRGB(245, 245, 250))
	block(model, "FrameTop", Vector3.new(7.8, 0.35, 0.55), frame * CFrame.new(0, 7.85, 0), gold, Enum.Material.Neon)
	block(model, "FrameBottom", Vector3.new(7.8, 0.35, 0.55), frame * CFrame.new(0, 3.35, 0), gold, Enum.Material.Neon)
	block(model, "Gift", Vector3.new(2, 1.6, 2), frame * CFrame.new(0, 8.8, 0), red)
	block(model, "Ribbon", Vector3.new(0.4, 1.65, 2.05), frame * CFrame.new(0, 8.8, 0), gold, Enum.Material.Neon)
	block(model, "Ribbon", Vector3.new(2.05, 1.65, 0.4), frame * CFrame.new(0, 8.8, 0), gold, Enum.Material.Neon)
	local bow = block(model, "Bow", Vector3.new(1.2, 0.5, 1.2), frame * CFrame.new(0, 9.8, 0) * CFrame.Angles(0, math.rad(45), 0), gold, Enum.Material.Neon)
	local light = Instance.new("PointLight")
	light.Color = gold
	light.Range = 14
	light.Brightness = 1.3
	light.Parent = bow
	model.WorldPivot = frame
	model.Parent = Workspace
	return model
end

local function facing(position, toward)
	local flat = Vector3.new(toward.X - position.X, 0, toward.Z - position.Z)
	if flat.Magnitude < 0.1 then
		return CFrame.new(position)
	end
	return CFrame.lookAt(position, position + flat.Unit)
end

local function buildPlaceholder()
	if #boards > 0 then
		return
	end
	local pad = LoopService.firstSellPad()
	local frame = nil
	if pad ~= nil then
		-- po drugiej stronie pola Sell niż tymczasowy sklep Aury
		local ground = pad.CFrame * CFrame.new(-(pad.Size.X / 2 + 10), -pad.Size.Y / 2, 0)
		frame = facing(ground.Position, pad.Position)
	else
		local spawnPart = Workspace:FindFirstChildWhichIsA("SpawnLocation", true)
		if spawnPart ~= nil then
			local ground = spawnPart.Position - Vector3.new(0, spawnPart.Size.Y / 2, 0)
			frame = facing(ground + Vector3.new(-14, 0, -24), ground)
		end
	end
	if frame ~= nil then
		addBoard(buildBoard(frame))
		print("[Nagrody] Na mapie nie ma DailyBoard, więc obok pola Sell stoi tymczasowa tablica z nagrodą dzienną.")
	else
		warn("[Nagrody] Nie ma pola Sell ani SpawnLocation, więc nie ma gdzie postawić tablicy z nagrodą dzienną.")
	end
end

----------------------------------------------------------------- Nagroda dla klienta
local function petsForClient(data, list)
	local out = {}
	for _, entry in ipairs(list) do
		table.insert(out, {
			Id = entry.id,
			Zone = entry.pet.Zone,
			Rarity = entry.pet.Rarity,
			Level = entry.pet.Level or 0,
			Egg = entry.pet.Egg,
			New = entry.new == true,
			Equipped = Loop.isEquipped(data, entry.id),
		})
	end
	return out
end

-- Wysyła graczowi nagrodę do pokazania (animacje jajek i boxów, komunikat o boostach) i ogłasza sekrety
-- po animacjach. source = "Code" (kolejne części: "Daily", "Quest"). Zwraca liczbę petów i ubrań.
function RewardsService.deliver(player, data, result, source, extra)
	local openTime = PetService.openTime(player)
	local payload = { Kind = "Reward", Source = source, Boosts = result.Boosts, Eggs = {}, Boxes = {}, OpenTime = openTime }
	for key, value in pairs(extra or {}) do
		payload[key] = value
	end
	local pets, items = 0, 0
	local secrets = {}
	for _, group in ipairs(result.Eggs) do
		table.insert(payload.Eggs, { Zone = group.Zone, Egg = group.Egg, Pets = petsForClient(data, group.Pets) })
		pets = pets + #group.Pets
		for _, entry in ipairs(group.Pets) do
			if entry.pet.Rarity == "Secret" then
				table.insert(secrets, entry.pet)
			end
		end
	end
	for _, group in ipairs(result.Boxes) do
		local list = {}
		for _, entry in ipairs(group.Items) do
			local reply = ClothesService.itemForClient(data, entry.id, entry.item)
			reply.Worn = entry.worn
			table.insert(list, reply)
			if entry.item.Rarity == "UltraSecret" then
				table.insert(secrets, { Category = entry.item.Category, Level = entry.item.Level or 0 })
			end
		end
		table.insert(payload.Boxes, { Box = group.Box, Items = list })
		items = items + #list
	end
	LoopService.markDirty(player)
	LoopService.notify(player, payload)
	if #secrets > 0 then
		-- po wszystkich animacjach (jajka i boxy idą po kolei), żeby nie zdradzić wyniku
		local delay = (#payload.Eggs + #payload.Boxes) * (openTime + 2) + SECRET_EXTRA
		for _, secret in ipairs(secrets) do
			task.delay(delay, function()
				if player.Parent == Players then
					PetService.announceSecret(player, secret)
				end
			end)
		end
	end
	return pets, items
end

----------------------------------------------------------------- Kody
local function redeemCode(player, text)
	if type(text) ~= "string" or #text > 120 then
		return { Ok = false, Reason = "Invalid" }
	end
	local data = DataService.get(player)
	if data == nil then
		return { Ok = false, Reason = "NotLoaded" }
	end
	local now = os.clock()
	local w = wrong[player]
	if w ~= nil and w.untilTime ~= nil and now < w.untilTime then
		return { Ok = false, Reason = "TooMany", Wait = math.ceil(w.untilTime - now) }
	end
	if lastTry[player] ~= nil and now - lastTry[player] < CODE_GAP then
		return { Ok = false, Reason = "Cooldown" }
	end
	lastTry[player] = now
	local result, reason = Rewards.redeemCode(data, LoopService.contextFor(player), text, random01, limitsFor(), os.time())
	if result == nil then
		if reason == "Unknown" or reason == "Invalid" then
			w = wrong[player] or { count = 0 }
			w.count = w.count + 1
			if w.count >= WRONG_LIMIT then
				w.count = 0
				w.untilTime = now + WRONG_PAUSE
			end
			wrong[player] = w
		end
		return { Ok = false, Reason = reason }
	end
	wrong[player] = nil
	local pets, items = RewardsService.deliver(player, data, result, "Code", { Code = result.Code })
	return { Ok = true, Code = result.Code, Boosts = result.Boosts, Pets = pets, Items = items }
end

----------------------------------------------------------------- Nagroda dzienna
local function claimDaily(player)
	local data = DataService.get(player)
	if data == nil then
		return { Ok = false, Reason = "NotLoaded" }
	end
	local now = os.clock()
	if lastClaim[player] ~= nil and now - lastClaim[player] < CLAIM_GAP then
		return { Ok = false, Reason = "Cooldown" }
	end
	lastClaim[player] = now
	local result, reason = Rewards.claimDaily(data, LoopService.contextFor(player), random01, limitsFor(), os.time())
	if result == nil then
		return { Ok = false, Reason = reason }
	end
	local pets, items = RewardsService.deliver(player, data, result, "Daily", { Day = result.Day, Streak = result.Streak })
	return { Ok = true, Day = result.Day, Streak = result.Streak, Boosts = result.Boosts, Pets = pets, Items = items }
end

----------------------------------------------------------------- Zadania dzienne
-- Postęp z LoopService.progress. Skończone zadanie czeka na CLAIM (lista zadań po prawej albo okno
-- nagrody dziennej), a gracz dostaje o nim komunikat.
local function onProgress(player, key, amount)
	local data = DataService.get(player)
	if data == nil then
		return
	end
	local changed, done = Rewards.questProgress(data, key, amount, random01, os.time())
	if changed then
		LoopService.markDirty(player)
	end
	for _, index in ipairs(done or {}) do
		local quest = data.Quests.List[index]
		LoopService.notify(player, { Kind = "QuestReady", Index = index, Key = quest and quest.Key })
	end
end

-- CLAIM: nagroda skończonego zadania (numer z listy na dziś). Bez miejsca w ekwipunku nagroda czeka.
local function claimQuest(player, index)
	if type(index) ~= "number" or index ~= index or index % 1 ~= 0 then
		return { Ok = false, Reason = "BadRequest" }
	end
	local data = DataService.get(player)
	if data == nil then
		return { Ok = false, Reason = "NotLoaded" }
	end
	local now = os.clock()
	if lastQuestClaim[player] ~= nil and now - lastQuestClaim[player] < QUEST_CLAIM_GAP then
		return { Ok = false, Reason = "Cooldown" }
	end
	lastQuestClaim[player] = now
	local result, reason = Rewards.claimQuest(data, LoopService.contextFor(player), index, random01, limitsFor(), os.time())
	if result == nil then
		LoopService.markDirty(player) -- np. nowy dzień: lista u gracza była stara
		return { Ok = false, Reason = reason }
	end
	local pets, items = RewardsService.deliver(player, data, result, "Quest", {
		Index = index,
		Key = result.Key,
		Aura = result.Aura,
		BonusAura = result.BonusAura,
		AllDone = result.AllDone,
	})
	return {
		Ok = true,
		Index = index,
		Key = result.Key,
		Boosts = result.Boosts,
		Pets = pets,
		Items = items,
		Aura = result.Aura,
		BonusAura = result.BonusAura,
		AllDone = result.AllDone,
	}
end

-- Tryb testowy: postęp zadania (np. /quests done 2 dokłada brakującą resztę). Nagroda czeka na CLAIM.
function RewardsService.progressQuest(player, key, amount)
	onProgress(player, key, amount)
end

-- O północy UTC: nowy stan dla wszystkich (nowe zadania losuje hook stanu) i komunikat
-- (Daily = czy nagroda dzienna czeka, Quests = nowe zadania).
local function watchMidnight()
	local lastDay = Rewards.day(os.time())
	while true do
		task.wait(DAY_CHECK)
		local now = os.time()
		local today = Rewards.day(now)
		if today ~= lastDay then
			lastDay = today
			for _, player in ipairs(Players:GetPlayers()) do
				local data = DataService.get(player)
				if data ~= nil then
					LoopService.markDirty(player)
					LoopService.notify(player, { Kind = "DailyReady", Daily = Rewards.dailyState(data, now).CanClaim, Quests = true })
				end
			end
		end
	end
end

----------------------------------------------------------------- Start
function RewardsService.start()
	scan()
	buildPlaceholder()

	LoopService.addViewHook(function(player, view)
		-- bonus za grupę i znajomych (zakładka FREE w sklepie: JOIN GROUP i INVITE)
		view.GroupId = BonusService.groupId()
		view.InGroup = BonusService.inGroup(player)
		view.FriendsHere = BonusService.friends(player)
		-- nagroda dzienna (okno z 7 dniami) i zadania dzienne (zakładka QUESTS w tym samym oknie)
		local data = DataService.get(player)
		if data ~= nil then
			local now = os.time()
			local state = Rewards.dailyState(data, now)
			view.Daily = {
				Day = state.Day,
				CanClaim = state.CanClaim,
				Streak = state.Streak,
				Lost = state.Lost,
				SecondsLeft = math.floor(state.SecondsLeft),
			}
			Rewards.ensureQuests(data, random01, now) -- nowy dzień = nowe zadania
			local quests = Rewards.questView(data, now)
			quests.SecondsLeft = math.floor(quests.SecondsLeft)
			view.Quests = quests
		end
	end)
	LoopService.onProgress(onProgress)
	Players.PlayerRemoving:Connect(function(player)
		lastTry[player] = nil
		wrong[player] = nil
		lastClaim[player] = nil
		lastQuestClaim[player] = nil
	end)
	Net.func("RedeemCode").OnServerInvoke = redeemCode
	Net.func("ClaimDaily").OnServerInvoke = claimDaily
	Net.func("ClaimQuest").OnServerInvoke = claimQuest
	task.spawn(watchMidnight)
end

-- Ile kodów z gry jest (dla komendy /codes).
function RewardsService.codeList()
	local list = {}
	for code in pairs(Economy.Rewards.Codes) do
		table.insert(list, code)
	end
	table.sort(list)
	return list
end

return RewardsService
