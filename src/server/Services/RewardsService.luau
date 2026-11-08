-- Nagrody (Etap 11). Część 1: kody. Logika jest w Shared/Logic/Rewards, a tu żądania gracza,
-- budka z kodami i komunikaty dla klienta.
--
-- Jak oznaczyć budkę w Studio: model albo część „CodesBooth” w Downtown (tag LarpCodes nadaje serwer).
-- Gdy jej nie ma, serwer stawia tymczasową po drugiej stronie pola Sell niż sklep Aury.
--
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

RewardsService.CodesTag = "LarpCodes" -- budka z kodami (klient szuka jej po tagu)

local CODE_GAP = 1.2 -- najmniejszy odstęp między próbami wpisania kodu (s)
local WRONG_LIMIT = 6 -- tyle złych kodów pod rząd…
local WRONG_PAUSE = 30 -- …i potem tyle sekund przerwy
local SECRET_EXTRA = 3 -- komunikat o sekrecie z nagrody po animacjach (s)

local booths = {}
local lastTry = {} -- [gracz] = os.clock() ostatniej próby
local wrong = {} -- [gracz] = { count = złe pod rząd, untilTime = koniec przerwy }

local rng = Random.new()
local function random01()
	return rng:NextNumber()
end

----------------------------------------------------------------- Budka z kodami
local function addBooth(inst)
	for _, existing in ipairs(booths) do
		if existing == inst then
			return
		end
	end
	CollectionService:AddTag(inst, RewardsService.CodesTag)
	table.insert(booths, inst)
end

local function scan()
	for _, inst in ipairs(Workspace:GetDescendants()) do
		if (inst:IsA("Model") or inst:IsA("BasePart")) and inst.Name == "CodesBooth" then
			addBooth(inst)
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

local DARK = Color3.fromRGB(44, 34, 66)
local PINK = Color3.fromRGB(255, 70, 170)
local GOLD = Color3.fromRGB(255, 200, 60)
local MINT = Color3.fromRGB(70, 230, 170)

-- Tymczasowa budka: niski cokół, kiosk z różową ramką i ekranem, złoty bilet nad nim.
-- frame = środek cokołu na ziemi, przodem (LookVector) do gracza.
local function buildBooth(frame)
	local model = Instance.new("Model")
	model.Name = "CodesBooth"
	block(model, "Base", Vector3.new(6, 0.6, 4), frame * CFrame.new(0, 0.3, 0), DARK)
	block(model, "Kiosk", Vector3.new(4.4, 5.4, 1.6), frame * CFrame.new(0, 3.3, 0.6), Color3.fromRGB(245, 245, 250))
	block(model, "FrameTop", Vector3.new(4.8, 0.4, 1.8), frame * CFrame.new(0, 6.1, 0.6), PINK, Enum.Material.Neon)
	block(model, "FrameLeft", Vector3.new(0.4, 5.4, 1.8), frame * CFrame.new(-2.4, 3.3, 0.6), PINK, Enum.Material.Neon)
	block(model, "FrameRight", Vector3.new(0.4, 5.4, 1.8), frame * CFrame.new(2.4, 3.3, 0.6), PINK, Enum.Material.Neon)
	block(model, "Screen", Vector3.new(3.2, 2.2, 0.2), frame * CFrame.new(0, 4.1, -0.25), MINT, Enum.Material.Neon)
	block(model, "Slot", Vector3.new(2.2, 0.3, 0.3), frame * CFrame.new(0, 2.2, -0.3), DARK)
	local ticket = block(model, "Ticket", Vector3.new(3.6, 1.8, 0.4), frame * CFrame.new(0, 7.6, 0.6) * CFrame.Angles(0, 0, math.rad(-8)), GOLD, Enum.Material.Neon)
	ticket.CanCollide = false
	local light = Instance.new("PointLight")
	light.Color = PINK
	light.Range = 14
	light.Brightness = 1.4
	light.Parent = ticket
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
	if #booths > 0 then
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
		addBooth(buildBooth(frame))
		print("[Nagrody] Na mapie nie ma CodesBooth, więc obok pola Sell stoi tymczasowa budka z kodami.")
	else
		warn("[Nagrody] Nie ma pola Sell ani SpawnLocation, więc nie ma gdzie postawić budki z kodami.")
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
	local limits = { pets = PetsConfig.MaxInventory, clothes = ClothesConfig.MaxInventory }
	local result, reason = Rewards.redeemCode(data, LoopService.contextFor(player), text, random01, limits, os.time())
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

----------------------------------------------------------------- Start
function RewardsService.start()
	scan()
	buildPlaceholder()

	-- bonus za grupę i znajomych w stanie gracza (okno kodów pokazuje go z przyciskami JOIN i INVITE)
	LoopService.addViewHook(function(player, view)
		view.GroupId = BonusService.groupId()
		view.InGroup = BonusService.inGroup(player)
		view.FriendsHere = BonusService.friends(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastTry[player] = nil
		wrong[player] = nil
	end)
	Net.func("RedeemCode").OnServerInvoke = redeemCode
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
