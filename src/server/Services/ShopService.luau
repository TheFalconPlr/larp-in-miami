-- Zakupy za Robuxy (Etap 10) na serwerze:
--   • ProcessReceipt: produkt przyznaje Shared/Logic/Shop, a PurchaseId trafia do zapisu gracza.
--     Roblox dostaje PurchaseGranted dopiero wtedy, gdy ten zapis jest już w DataStore
--     (ProfileStore LastSavedData), więc zakup nigdy nie przyzna się dwa razy ani nie przepadnie.
--     Działa też dla zakupów poza grą (sklep na stronie gry): wtedy ProcessReceipt przychodzi po
--     wejściu gracza.
--   • okna zakupu (Net „Buy”): serwer sprawdza, czy produkt można kupić (Shop.canPrompt), zapamiętuje
--     strefę premium jajka i otwiera okno Roblox. Bez ID (0 w Config/RobuxIds) tester kupuje
--     „na niby” tą samą drogą, a zwykły gracz dostaje „coming soon”.
--   • PolicyService: gracz z ArePaidRandomItemsRestricted nie kupi premium jajka (płatne losowanie),
--     tylko konkretnego peta (DirectPet…). Gdy PolicyService nie odpowie, traktujemy gracza jak
--     z ograniczeniem (bezpieczniej).
--   • boosty (lecą tylko w grze), dzienny boost Verified, reklama za nagrodę (AdService),
--     teleport do stref z gamepassem Teleport.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local MarketplaceService = game:GetService("MarketplaceService")
local PolicyService = game:GetService("PolicyService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared.Config.Economy)
local Robux = require(Shared.Robux)
local Shop = require(Shared.Logic.Shop)
local Loop = require(Shared.Logic.Loop)
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)
local GamepassService = require(script.Parent.GamepassService)
local LoopService = require(script.Parent.LoopService)
local ZoneService = require(script.Parent.ZoneService)
local PetService = require(script.Parent.PetService)

local ShopService = {}
ShopService.RestrictedAttribute = "LarpNoPaidRandom" -- gracz bez płatnych losowań (PolicyService)
ShopService.VerifiedAttribute = "LarpVerified" -- gracz z gamepassem Verified (znaczek nad głową)

-- Tryb testowy: AdminService podmienia te funkcje (zakup „na niby” tylko dla testera).
ShopService.isTester = function()
	return false
end
ShopService.setTestPass = function() end

local PENDING_SECONDS = 600 -- tyle pamiętamy strefę jajka wybraną przed oknem zakupu
local PROMPT_GAP = 0.4 -- najmniejszy odstęp między prośbami o okno zakupu
local TELEPORT_GAP = 2
local POLICY_TRIES = 3
local DATA_WAIT = 30 -- tyle sekund ProcessReceipt czeka na wczytanie zapisu
local AD_WINDOW = 300 -- tyle sekund po starcie reklamy paragon nagrody liczymy jako reklamę

local pending = {} -- [gracz] = { key, zone, at }: wybór przed oknem zakupu (strefa premium jajka)
local policy = {} -- [gracz] = true (z ograniczeniem) / false; nil = jeszcze nie wiadomo
local policyOverride = {} -- [gracz] = true/false (tryb testowy: /policy)
local lastPrompt = {}
local lastTeleport = {}
local adBusy = {}
local adStarted = {} -- [gracz] = os.clock() startu reklamy (zapas, gdyby paragon nie miał kanału AdReward)
local rng = Random.new()

local function random01()
	return rng:NextNumber()
end

local function notify(player, payload)
	LoopService.notify(player, payload)
end

----------------------------------------------------------------- PolicyService
local function isRestricted(player)
	local o = policyOverride[player]
	if o ~= nil then
		return o
	end
	local p = policy[player]
	if p == nil then
		return true -- dopóki nie wiemy, nie pokazujemy płatnych losowań
	end
	return p
end
ShopService.isRestricted = isRestricted

local function applyPolicy(player)
	local value = isRestricted(player)
	if player:GetAttribute(ShopService.RestrictedAttribute) ~= value then
		player:SetAttribute(ShopService.RestrictedAttribute, value)
	end
	LoopService.markDirty(player)
end

local function fetchPolicy(player)
	for try = 1, POLICY_TRIES do
		local ok, info = pcall(PolicyService.GetPolicyInfoForPlayerAsync, PolicyService, player)
		if ok and type(info) == "table" then
			policy[player] = info.ArePaidRandomItemsRestricted == true
			applyPolicy(player)
			return
		end
		if player.Parent ~= Players then
			return
		end
		if try < POLICY_TRIES then
			task.wait(3)
		end
	end
	policy[player] = true
	applyPolicy(player)
	warn("[Sklep] PolicyService nie odpowiada: " .. player.Name .. " nie zobaczy premium jajek (bezpieczniej).")
end

-- /policy on|off|auto (tryb testowy): udaje gracza z ograniczeniem płatnych losowań albo bez.
function ShopService.setPolicyOverride(player, value)
	policyOverride[player] = value
	applyPolicy(player)
end

----------------------------------------------------------------- Przyznanie produktu
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

-- Daje produkt i mówi o tym klientowi (animacja jajek, komunikat). Wołają ją ProcessReceipt,
-- zakup testowy i reklama.
local function grantFor(player, data, key, opts)
	local ctx = LoopService.contextFor(player)
	local result, reason = Shop.grant(data, ctx, key, opts)
	if result == nil then
		error("nie umiem przyznać produktu " .. tostring(key) .. ": " .. tostring(reason))
	end
	LoopService.markDirty(player)
	local test = opts.test == true
	if result.Kind == "Pets" then
		notify(player, {
			Kind = "Purchase",
			Result = "Pets",
			Key = (result.Direct and "DirectPetEpic") or key,
			Zone = result.Zone,
			Pets = petsForClient(data, result.Pets),
			OpenTime = PetService.openTime(player),
			Test = test,
		})
	elseif result.Kind == "Starter" then
		local item = result.Item.item
		notify(player, {
			Kind = "Purchase",
			Result = "Starter",
			Key = key,
			Pet = petsForClient(data, { result.Pet })[1],
			Item = { Id = result.Item.id, Category = item.Category, Rarity = item.Rarity, Level = item.Level, Worn = result.Item.worn },
			BoostMinutes = result.BoostMinutes,
			AutoSellMinutes = result.AutoSellMinutes,
			Test = test,
		})
	elseif result.Kind == "Boost" then
		notify(player, { Kind = "Purchase", Result = "Boost", Key = key, Boost = result.Boost, Minutes = result.Minutes, Ad = result.Ad, Test = test })
	elseif result.Kind == "Sell" then
		if (result.LP or 0) > 0 then
			notify(player, { Kind = "Sold", LP = result.LP, Cash = result.Cash })
		end
	end
	return result
end
ShopService.grantFor = grantFor

----------------------------------------------------------------- ProcessReceipt
local function waitForProfile(player)
	local deadline = os.clock() + DATA_WAIT
	while player.Parent == Players and os.clock() < deadline do
		local profile = DataService.profile(player)
		if profile ~= nil and profile:IsActive() then
			return profile
		end
		task.wait(0.5)
	end
	return nil
end

local function savedReceipt(profile, purchaseId)
	local saved = profile.LastSavedData
	local r = type(saved) == "table" and saved.Robux
	if type(r) ~= "table" or type(r.Receipts) ~= "table" then
		return false
	end
	for _, id in ipairs(r.Receipts) do
		if id == purchaseId then
			return true
		end
	end
	return false
end

-- Przed premium jajkiem z paragonu czekamy chwilę na odpowiedź PolicyService (po wejściu do gry).
local function waitForPolicy(player)
	local deadline = os.clock() + 10
	while policy[player] == nil and policyOverride[player] == nil and player.Parent == Players and os.clock() < deadline do
		task.wait(0.2)
	end
end

-- Nagroda za reklamę liczy się do dziennego limitu. Kanał zakupu (Enum.ProductPurchaseChannel.AdReward)
-- sprawdzamy w pcall, a na wszelki wypadek liczymy też paragon nagrody, który przyszedł zaraz po
-- reklamie z WatchAd.
local function isAdReward(player, key, receipt)
	local ok, isAd = pcall(function()
		return receipt.ProductPurchaseChannel == Enum.ProductPurchaseChannel.AdReward
	end)
	local ad = ok and isAd == true
	if key == Robux.AdReward and adStarted[player] ~= nil then
		if os.clock() - adStarted[player] < AD_WINDOW then
			ad = true
		end
		adStarted[player] = nil
	end
	return ad
end

local function processReceipt(receipt)
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if player == nil then
		return Enum.ProductPurchaseDecision.NotProcessedYet -- Roblox spróbuje znowu, gdy gracz wejdzie
	end
	local key = Robux.productKey(receipt.ProductId)
	if key == nil then
		warn("[Sklep] Nieznany produkt " .. tostring(receipt.ProductId) .. ": dopisz jego ID w Config/RobuxIds.")
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local profile = waitForProfile(player)
	if profile == nil then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local purchaseId = receipt.PurchaseId
	if not Shop.hasReceipt(profile.Data, purchaseId) then
		if Robux.Products[key].Count ~= nil then
			waitForPolicy(player)
		end
		local opts = {
			random01 = random01,
			now = os.time(),
			spent = receipt.CurrencySpent,
			ad = isAdReward(player, key, receipt),
			-- premium jajko z paragonu u gracza z ograniczeniem (np. paragon po ponownym wejściu): bez losowania
			restricted = isRestricted(player),
		}
		local p = pending[player]
		if p ~= nil and p.key == key and os.clock() - p.at < PENDING_SECONDS then
			opts.zone = p.zone
			pending[player] = nil
		end
		local ok, err = pcall(grantFor, player, profile.Data, key, opts)
		if not ok then
			warn("[Sklep] Nie udało się przyznać " .. key .. ": " .. tostring(err))
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		Shop.rememberReceipt(profile.Data, purchaseId)
	end
	-- PurchaseGranted dopiero po zapisie paragonu w DataStore
	if savedReceipt(profile, purchaseId) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	while profile:IsActive() do
		local last = profile.LastSavedData
		profile:Save()
		if profile.LastSavedData == last then
			profile.OnAfterSave:Wait()
		end
		if savedReceipt(profile, purchaseId) then
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
	end
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

----------------------------------------------------------------- Żądania gracza
-- kind: "Pass" albo "Product"; opts.Zone = strefa stoiska premium jajka. Zwraca { Ok, Reason, Test }.
local function buy(player, kind, key, opts)
	if type(kind) ~= "string" or type(key) ~= "string" then
		return { Ok = false, Reason = "BadRequest" }
	end
	if type(opts) ~= "table" then
		opts = {}
	end
	local now = os.clock()
	if lastPrompt[player] ~= nil and now - lastPrompt[player] < PROMPT_GAP then
		return { Ok = false, Reason = "Cooldown" }
	end
	lastPrompt[player] = now
	local data = DataService.get(player)
	if data == nil then
		return { Ok = false, Reason = "NotLoaded" }
	end
	if kind == "Pass" then
		if Robux.Gamepasses[key] == nil then
			return { Ok = false, Reason = "BadRequest" }
		end
		if GamepassService.owns(player, key) then
			return { Ok = false, Reason = "Owned" }
		end
		local id = Robux.passId(key)
		if id ~= nil then
			MarketplaceService:PromptGamePassPurchase(player, id)
			return { Ok = true, Prompted = true }
		end
		if ShopService.isTester(player) then
			ShopService.setTestPass(player, key, true)
			notify(player, { Kind = "PassBought", Key = key, Test = true })
			return { Ok = true, Test = true }
		end
		return { Ok = false, Reason = "Soon" }
	elseif kind == "Product" then
		if Robux.Products[key] == nil then
			return { Ok = false, Reason = "BadRequest" }
		end
		local zone = tonumber(opts.Zone)
		local ok, reason = Shop.canPrompt(data, key, { zone = zone, restricted = isRestricted(player) }, os.time())
		if not ok then
			return { Ok = false, Reason = reason }
		end
		local id = Robux.productId(key)
		if id ~= nil then
			pending[player] = { key = key, zone = zone, at = now }
			MarketplaceService:PromptProductPurchase(player, id)
			return { Ok = true, Prompted = true }
		end
		if ShopService.isTester(player) then
			-- zakup testowy: ta sama droga co prawdziwy paragon, tylko bez Robuxów
			local granted, err = pcall(grantFor, player, data, key, { zone = zone, random01 = random01, now = os.time(), test = true })
			if not granted then
				warn("[Sklep] zakup testowy " .. key .. ": " .. tostring(err))
				return { Ok = false, Reason = "Error" }
			end
			return { Ok = true, Test = true }
		end
		return { Ok = false, Reason = "Soon" }
	end
	return { Ok = false, Reason = "BadRequest" }
end

-- Reklama za nagrodę (rewarded video). Nagrodę daje ProcessReceipt (kanał AdReward), nie ta funkcja.
-- Bez ID produktu nagrody tester ogląda „reklamę na niby” (2 s) i dostaje nagrodę od razu.
local function watchAd(player)
	local data = DataService.get(player)
	if data == nil then
		return { Ok = false, Reason = "NotLoaded" }
	end
	if Shop.adsLeft(data, os.time()) <= 0 then
		return { Ok = false, Reason = "Limit" }
	end
	if adBusy[player] then
		return { Ok = false, Reason = "Busy" }
	end
	local productId = Robux.productId(Robux.AdReward)
	if productId == nil then
		if not ShopService.isTester(player) then
			return { Ok = false, Reason = "Soon" }
		end
		adBusy[player] = true
		task.wait(2)
		adBusy[player] = nil
		local current = DataService.get(player)
		if current == nil then
			return { Ok = false, Reason = "NotLoaded" }
		end
		pcall(grantFor, player, current, Robux.AdReward, { ad = true, now = os.time(), test = true })
		return { Ok = true, Test = true }
	end
	adBusy[player] = true
	adStarted[player] = os.clock()
	local ok, result = pcall(function()
		local AdService = game:GetService("AdService")
		local reward = AdService:CreateAdRewardFromDevProductId(productId)
		return AdService:ShowRewardedVideoAdAsync(player, reward, Robux.placementId())
	end)
	adBusy[player] = nil
	local completed = ok and result == Enum.ShowAdResult.ShowCompleted
	if not completed and adStarted[player] ~= nil then
		adStarted[player] = nil -- reklama nie dobiegła końca, więc paragonu nie będzie
	end
	if not ok then
		warn("[Sklep] reklama: " .. tostring(result))
		return { Ok = false, Reason = "Error" }
	end
	return { Ok = completed, Result = tostring(result) }
end

-- Teleport do odblokowanej strefy (gamepass Teleport).
local function teleportToZone(player, zone)
	if type(zone) ~= "number" or Economy.Zones[zone] == nil then
		return { Ok = false, Reason = "BadRequest" }
	end
	if not GamepassService.owns(player, "Teleport") then
		return { Ok = false, Reason = "NoPass" }
	end
	local data = DataService.get(player)
	if data == nil then
		return { Ok = false, Reason = "NotLoaded" }
	end
	if zone > data.ZonesUnlocked then
		return { Ok = false, Reason = "Locked" }
	end
	if LoopService.isBusy(player) then
		return { Ok = false, Reason = "Busy" }
	end
	local now = os.clock()
	if lastTeleport[player] ~= nil and now - lastTeleport[player] < TELEPORT_GAP then
		return { Ok = false, Reason = "Cooldown" }
	end
	lastTeleport[player] = now
	if not ZoneService.teleport(player, zone) then
		return { Ok = false, Reason = "NoSpot" }
	end
	return { Ok = true, Zone = zone }
end

----------------------------------------------------------------- Co sekundę
local function verifiedCheck(player, data)
	local owns = GamepassService.owns(player, "Verified")
	if player:GetAttribute(ShopService.VerifiedAttribute) ~= owns then
		player:SetAttribute(ShopService.VerifiedAttribute, owns)
	end
	if owns then
		local minutes = Shop.verifiedDaily(data, os.time())
		if minutes > 0 then
			notify(player, { Kind = "Purchase", Result = "Boost", Key = "VerifiedDaily", Boost = "LP", Minutes = minutes, Daily = true })
			LoopService.markDirty(player)
		end
	end
end

local tickTimer = 0
local verifiedTimer = 0
local function onHeartbeat(dt)
	tickTimer = tickTimer + dt
	if tickTimer < 1 then
		return
	end
	local elapsed = tickTimer
	tickTimer = 0
	verifiedTimer = verifiedTimer + elapsed
	local checkVerified = verifiedTimer >= 30
	if checkVerified then
		verifiedTimer = 0
	end
	for _, player in ipairs(Players:GetPlayers()) do
		local data = DataService.get(player)
		if data ~= nil then
			local ended = Shop.tickBoosts(data, elapsed)
			if #ended > 0 then
				LoopService.markDirty(player)
				for _, kind in ipairs(ended) do
					notify(player, { Kind = "BoostEnded", Boost = kind })
				end
			end
			if checkVerified then
				verifiedCheck(player, data)
			end
		end
	end
end

----------------------------------------------------------------- Start
function ShopService.start()
	MarketplaceService.ProcessReceipt = processReceipt
	Net.func("Buy").OnServerInvoke = buy
	Net.func("WatchAd").OnServerInvoke = watchAd
	Net.func("TeleportToZone").OnServerInvoke = teleportToZone

	DataService.onLoaded(function(player, data)
		task.spawn(fetchPolicy, player)
		verifiedCheck(player, data)
	end)
	GamepassService.onChanged(function(player)
		local data = DataService.get(player)
		if data ~= nil then
			verifiedCheck(player, data)
		end
	end)
	-- prawdziwy zakup gamepassa: podziękowanie (sam gamepass zapisuje GamepassService)
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if purchased then
			local key = Robux.passKey(passId)
			if key ~= nil then
				notify(player, { Kind = "PassBought", Key = key })
			end
		end
	end)
	LoopService.addViewHook(function(player, view)
		local data = DataService.get(player)
		if data == nil then
			return
		end
		local now = os.time()
		view.Boosts = {
			LP = math.ceil(Shop.boostLeft(data, "LP")),
			AutoSell = math.ceil(Shop.boostLeft(data, "AutoSell")),
		}
		view.StarterLeft = math.floor(Shop.starterSecondsLeft(data, now))
		view.AdsLeft = Shop.adsLeft(data, now)
		view.AdsReady = Robux.productId(Robux.AdReward) ~= nil or ShopService.isTester(player)
		view.PaidRandomBlocked = isRestricted(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		pending[player] = nil
		policy[player] = nil
		policyOverride[player] = nil
		lastPrompt[player] = nil
		lastTeleport[player] = nil
		adBusy[player] = nil
		adStarted[player] = nil
	end)
	RunService.Heartbeat:Connect(onHeartbeat)
end

return ShopService
