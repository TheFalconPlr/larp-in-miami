-- Bonus za grupę i znajomych (Etap 11): +5% LP dla członków grupy gry i +10% LP za każdego znajomego
-- na tym samym serwerze (najwyżej 3). Liczby są w Economy.Bonuses, a mnożnik liczy Loop.lpBonus
-- (LoopService.contextFor wpisuje ctx.inGroup i ctx.friends z tego modułu).
--
-- Grupa: Settings.Group.Id, a przy 0 grupa, do której należy gra (game.CreatorId). Roblox pamięta
-- wynik IsInGroupAsync na serwerze, więc gracza spoza grupy sprawdzamy co 2 minuty, a po dołączeniu
-- przyciskiem JOIN GROUP (klient: GroupService:PromptJoinAsync, potem zdarzenie GroupJoined) także
-- po kilku sekundach. Komunikaty dla gracza: Notify „Bonus” (What = Group, Friend, FriendLeft).
-- Ten moduł nie wymaga LoopService (LoopService wymaga jego), więc zmiany zgłasza przez onChanged.

local Players = game:GetService("Players")
local GroupService = game:GetService("GroupService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared.Config.Economy)
local Settings = require(Shared.Config.Settings)
local Net = require(Shared.Net)

local BonusService = {}

local RECHECK_SECONDS = 120 -- co tyle sprawdzamy graczy spoza grupy (dołączenie na stronie grupy)
local JOIN_CHECKS = { 3, 15, 45, 90 } -- po JOIN GROUP w grze sprawdzamy po tylu sekundach
local FIRST_CHECK_DELAY = 4 -- pierwsze sprawdzenie chwilę po wejściu (klient zdąży słuchać Notify)

local inGroup = {} -- [gracz] = true
local friendsOf = {} -- [gracz] = { [inny gracz] = true }
local overrides = {} -- [gracz] = { group = true/false, friends = liczba } (tryb testowy: /bonus)
local joinChecks = {} -- [gracz] = true, gdy czekamy na sprawdzenie po JOIN GROUP
local unsure = {} -- [gracz] = true, gdy Roblox nie odpowiedział (członek grupy nie dostanie wtedy „dzięki za dołączenie”)
local callbacks = {}

local function fire(player)
	for _, fn in ipairs(callbacks) do
		task.spawn(fn, player)
	end
end

local function notify(player, payload)
	if player.Parent == Players then
		Net.event("Notify"):FireClient(player, payload)
	end
end

-- fn(player) po każdej zmianie bonusu gracza (LoopService wysyła wtedy nowy stan).
function BonusService.onChanged(fn)
	table.insert(callbacks, fn)
end

-- ID grupy z bonusem (0 = brak: gra nie należy do grupy i Settings.Group.Id = 0).
function BonusService.groupId()
	local id = Settings.Group and Settings.Group.Id
	if type(id) == "number" and id > 0 then
		return id
	end
	if game.CreatorType == Enum.CreatorType.Group then
		return game.CreatorId
	end
	return 0
end

function BonusService.inGroup(player)
	local o = overrides[player]
	if o ~= nil and o.group ~= nil then
		return o.group
	end
	return inGroup[player] == true
end

-- Liczba znajomych na serwerze (bez limitu; limit 3 liczy Loop.lpBonus).
function BonusService.friends(player)
	local o = overrides[player]
	if o ~= nil and o.friends ~= nil then
		return o.friends
	end
	local n = 0
	for other in pairs(friendsOf[player] or {}) do
		if other.Parent == Players then
			n = n + 1
		end
	end
	return n
end

-- Znajomi, którzy liczą się do bonusu (najwyżej Economy.Bonuses.FriendMax).
local function counted(player)
	return math.min(BonusService.friends(player), Economy.Bonuses.FriendMax)
end

-- Tryb testowy (/bonus): what = "group" (true/false/nil) albo "friends" (liczba/nil); nil = naprawdę.
function BonusService.setOverride(player, what, value)
	if overrides[player] == nil then
		overrides[player] = {}
	end
	overrides[player][what] = value
	fire(player)
end

----------------------------------------------------------------- Grupa
-- Nowe wywołania Robloxa (…Async), a gdy ich nie ma, stare.
local function isMember(player, groupId)
	local ok, member = pcall(function()
		return player:IsInGroupAsync(groupId)
	end)
	if ok then
		return true, member == true
	end
	ok, member = pcall(function()
		return player:IsInGroup(groupId)
	end)
	return ok, ok and member == true
end

-- Lista grup gracza ze strony Roblox (świeższa niż IsInGroupAsync zaraz po dołączeniu).
local function inGroupList(player, groupId)
	local ok, groups = pcall(function()
		return GroupService:GetGroupsAsync(player.UserId)
	end)
	if not ok or type(groups) ~= "table" then
		return false
	end
	for _, group in ipairs(groups) do
		if group.Id == groupId then
			return true
		end
	end
	return false
end

-- Sprawdza grupę; joined = gracz właśnie dołączył (komunikat „dzięki za dołączenie”).
local function checkGroup(player, joined, fresh)
	local groupId = BonusService.groupId()
	if groupId <= 0 or inGroup[player] or player.Parent ~= Players then
		return
	end
	local ok, member = isMember(player, groupId)
	if (not ok or not member) and fresh then
		member = inGroupList(player, groupId)
	end
	if member and not inGroup[player] and player.Parent == Players then
		inGroup[player] = true
		fire(player)
		local thanks = joined == true and not unsure[player]
		notify(player, { Kind = "Bonus", What = "Group", Bonus = Economy.Bonuses.Group, Joined = thanks })
	end
	if not ok and not member then
		unsure[player] = true
	end
end

local function onGroupJoined(player)
	if joinChecks[player] or inGroup[player] then
		return
	end
	joinChecks[player] = true
	task.spawn(function()
		local waited = 0
		for _, at in ipairs(JOIN_CHECKS) do
			task.wait(at - waited)
			waited = at
			if player.Parent ~= Players or inGroup[player] then
				break
			end
			checkGroup(player, true, true)
		end
		joinChecks[player] = nil
	end)
end

----------------------------------------------------------------- Znajomi
local function areFriends(player, other)
	local ok, result = pcall(function()
		return player:IsFriendsWithAsync(other.UserId)
	end)
	if ok then
		return result == true
	end
	ok, result = pcall(function()
		return player:IsFriendsWith(other.UserId)
	end)
	return ok and result == true
end

local function link(a, b)
	-- IsFriendsWithAsync czeka na odpowiedź Robloxa, więc ktoś mógł w tym czasie wyjść
	if a.Parent ~= Players or b.Parent ~= Players then
		return
	end
	if friendsOf[a] == nil then
		friendsOf[a] = {}
	end
	if friendsOf[b] == nil then
		friendsOf[b] = {}
	end
	if friendsOf[a][b] then
		return
	end
	local beforeA, beforeB = counted(a), counted(b)
	friendsOf[a][b] = true
	friendsOf[b][a] = true
	fire(a)
	fire(b)
	-- komunikat tylko wtedy, gdy bonus naprawdę urósł (4. znajomy już nic nie dodaje)
	if counted(a) > beforeA then
		notify(a, { Kind = "Bonus", What = "Friend", Name = b.DisplayName, Friends = counted(a), Bonus = Economy.Bonuses.FriendEach })
	end
	if counted(b) > beforeB then
		notify(b, { Kind = "Bonus", What = "Friend", Name = a.DisplayName, Friends = counted(b), Bonus = Economy.Bonuses.FriendEach })
	end
end

local function findFriends(player)
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player and player.Parent == Players and other.Parent == Players then
			if areFriends(player, other) then
				link(player, other)
			end
		end
	end
end

local function onPlayerRemoving(player)
	for other in pairs(friendsOf[player] or {}) do
		local list = friendsOf[other]
		if list ~= nil and list[player] then
			local before = counted(other)
			list[player] = nil
			fire(other)
			if counted(other) < before then
				notify(other, { Kind = "Bonus", What = "FriendLeft", Name = player.DisplayName, Friends = counted(other), Bonus = Economy.Bonuses.FriendEach })
			end
		end
	end
	friendsOf[player] = nil
	inGroup[player] = nil
	overrides[player] = nil
	joinChecks[player] = nil
	unsure[player] = nil
end

----------------------------------------------------------------- Start
function BonusService.start()
	local function onPlayer(player)
		task.delay(FIRST_CHECK_DELAY, function()
			if player.Parent ~= Players then
				return
			end
			checkGroup(player, false, false)
			findFriends(player)
		end)
	end
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayer(player)
	end
	Players.PlayerAdded:Connect(onPlayer)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	Net.event("GroupJoined").OnServerEvent:Connect(onGroupJoined)
	-- dołączenie do grupy na stronie Roblox w trakcie gry
	task.spawn(function()
		while true do
			task.wait(RECHECK_SECONDS)
			for _, player in ipairs(Players:GetPlayers()) do
				if not inGroup[player] then
					task.spawn(checkGroup, player, true, false)
				end
			end
		end
	end)
end

return BonusService
