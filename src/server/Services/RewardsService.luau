-- Nagrody (Etap 11). Logika jest w Shared/Logic/Rewards, a tu żądania gracza i komunikaty dla klienta.
--
-- Kody: pole na kod jest na samym dole sklepu (ShopWindow, zakładka FREE, jak w Pet Simulator 99).
-- RedeemCode(tekst): kod z Economy.Rewards.Codes, każdy raz na konto (data.Codes). Odpowiedź:
-- { Ok, Code, Reason, Boosts, Pets, Items }. Jajka i boxy z nagrody klient otwiera tą samą animacją
-- co kupione: Notify „Reward” z Eggs = { { Zone, Egg, Pets } } i Boxes = { { Box, Items } }.
-- Bonus za grupę i znajomych liczy BonusService; tu tylko dopisujemy go do stanu gracza.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

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

local CODE_GAP = 1.2 -- najmniejszy odstęp między próbami wpisania kodu (s)
local WRONG_LIMIT = 6 -- tyle złych kodów pod rząd…
local WRONG_PAUSE = 30 -- …i potem tyle sekund przerwy
local SECRET_EXTRA = 3 -- komunikat o sekrecie z nagrody po animacjach (s)

local lastTry = {} -- [gracz] = os.clock() ostatniej próby
local wrong = {} -- [gracz] = { count = złe pod rząd, untilTime = koniec przerwy }

local rng = Random.new()
local function random01()
	return rng:NextNumber()
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
	-- bonus za grupę i znajomych w stanie gracza (zakładka FREE w sklepie: JOIN GROUP i INVITE)
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
