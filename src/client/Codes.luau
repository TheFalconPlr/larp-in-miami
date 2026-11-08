-- Kody i bonus za grupę i znajomych po stronie gracza (Etap 11). Wygląd jest w sklepie: zakładka
-- FREE na samym dole (ShopWindow: karty JOIN GROUP i INVITE, karta sekretnych kodów z polem i REDEEM,
-- jak w Pet Simulator 99). Tu są akcje i komunikaty:
--   Codes.redeem(tekst)  → odpowiedź serwera (RedeemCode); wynik pokazuje jeden komunikat na dole ekranu
--   Codes.joinGroup()    → okienko dołączania Robloxa, potem GroupJoined (bonus włącza serwer)
--   Codes.invite()       → okno zaproszeń Robloxa
--   Codes.groupName(fn)  → nazwa grupy z Robloxa (raz na grę), fn(nazwa)
-- Kod i bonus sprawdza serwer (RewardsService, BonusService, Logic/Rewards).

local GroupService = game:GetService("GroupService")
local SocialService = game:GetService("SocialService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared.Config.Economy)
local Net = require(Shared.Net)
local State = require(script.Parent.State)
local Theme = require(script.Parent.Ui.Theme)
local Sounds = require(script.Parent.Ui.Sounds)

local Codes = {}

local TEXT = {
	Redeemed = "Redeemed %s!",
	Unknown = "That code doesn't exist",
	Used = "You already used this code",
	Expired = "This code has expired",
	Invalid = "Type a code first",
	PetInventory = "No room for pets: sell or merge some first",
	ClothInventory = "No room for clothes: sell or merge some first",
	TooMany = "Too many tries, wait %d s",
	Cooldown = "Slow down a bit",
	NotLoaded = "Still loading, try again",
	BoostLP = "2x LP +%d min",
	BoostAutoSell = "Auto Sell +%d min",
	Pets = "+%d pets",
	Pet = "+1 pet",
	Items = "+%d clothes",
	Item = "+1 clothing item",
	Joined = "Joined! Your +%d%% LP turns on in a moment",
	JoinPending = "Join request sent",
	JoinFailed = "Couldn't open the group prompt",
	NoGroup = "No group for this game yet",
	InviteFailed = "Invites aren't available right now",
	ToastGroup = "Group bonus: +%d%% LP",
	ToastGroupJoined = "Thanks for joining! +%d%% LP",
	ToastFriend = "%s is here: +%d%% LP (%d/%d)",
	ToastFriendLeft = "%s left: friend bonus %d/%d",
}

local hud = nil
local requesting = false
local joining = false

local function percent(x)
	return math.floor(x * 100 + 0.5)
end

local function toast(items, key)
	if hud ~= nil then
		hud.toast(items, key)
	end
end

local function fail(text, key)
	Sounds.play("NotEnough")
	toast({ { text = text, size = 26, colors = Theme.Gradients.Red } }, key)
end

-- Co dała nagroda (boosty, liczba petów i ubrań), np. „2x LP +15 min”, do komunikatu.
function Codes.rewardItems(result)
	local items = {}
	for _, boost in ipairs(result.Boosts or {}) do
		local format = TEXT.BoostLP
		if boost.Boost == "AutoSell" then
			format = TEXT.BoostAutoSell
		end
		table.insert(items, { icon = "Boost", size = 36 })
		table.insert(items, { text = string.format(format, boost.Minutes or 0), size = 26, colors = Theme.Gradients.Gold })
	end
	local pets = result.Pets or 0
	if pets > 0 then
		table.insert(items, { icon = "Pets", size = 36 })
		table.insert(items, { text = (pets == 1 and TEXT.Pet) or string.format(TEXT.Pets, pets), size = 26, colors = Theme.Gradients.Gold })
	end
	local clothes = result.Items or 0
	if clothes > 0 then
		table.insert(items, { icon = "Clothes", size = 36 })
		table.insert(items, { text = (clothes == 1 and TEXT.Item) or string.format(TEXT.Items, clothes), size = 26, colors = Theme.Gradients.Gold })
	end
	return items
end

-- Wpisany kod. Zwraca odpowiedź serwera ({ Ok, Code, Boosts, Pets, Items, Reason }) albo nil, gdy
-- prośba już trwa albo nie doszła. Wynik (sukces albo błąd) to jeden komunikat na dole ekranu.
function Codes.redeem(text)
	if requesting then
		return nil
	end
	if type(text) ~= "string" or string.gsub(text, "%s", "") == "" then
		fail(TEXT.Invalid, "CodeError")
		return { Ok = false, Reason = "Invalid" }
	end
	requesting = true
	local ok, result = pcall(function()
		return Net.func("RedeemCode"):InvokeServer(text)
	end)
	requesting = false
	if not ok or type(result) ~= "table" then
		return nil
	end
	if result.Ok then
		Sounds.play("Unlock", { volume = 0.7 })
		local items = { { icon = "Key", size = 36 }, { text = string.format(TEXT.Redeemed, tostring(result.Code)), size = 26, colors = Theme.Gradients.Green } }
		for _, item in ipairs(Codes.rewardItems(result)) do
			table.insert(items, item)
		end
		toast(items)
		return result
	end
	local message = TEXT[result.Reason] or TEXT.Unknown
	if result.Reason == "TooMany" then
		message = string.format(TEXT.TooMany, result.Wait or 30)
	end
	fail(message, "CodeError")
	return result
end

-- JOIN GROUP: okienko dołączania Robloxa. Zwraca "Joined", "Pending", "Failed" albo "None".
function Codes.joinGroup()
	local view = State.view or {}
	local groupId = view.GroupId or 0
	if view.InGroup or joining then
		return "None"
	end
	if groupId <= 0 then
		fail(TEXT.NoGroup, "GroupError")
		return "Failed"
	end
	joining = true
	local ok, status = pcall(function()
		return GroupService:PromptJoinAsync(groupId)
	end)
	joining = false
	if not ok then
		fail(TEXT.JoinFailed, "GroupError")
		return "Failed"
	end
	if status == Enum.GroupMembershipStatus.Joined or status == Enum.GroupMembershipStatus.AlreadyMember then
		-- serwer sprawdzi sam (IsInGroupAsync); bonus włącza się po chwili
		Net.event("GroupJoined"):FireServer()
		Sounds.play("Unlock", { volume = 0.6 })
		toast({ { icon = "Group", size = 40 }, { text = string.format(TEXT.Joined, percent(Economy.Bonuses.Group)), size = 26, colors = Theme.Gradients.Green } }, "GroupJoin")
		return "Joined"
	elseif status == Enum.GroupMembershipStatus.JoinRequestPending then
		toast({ { icon = "Group", size = 40 }, { text = TEXT.JoinPending, size = 26, colors = Theme.Gradients.Gold } }, "GroupJoin")
		return "Pending"
	end
	return "None"
end

-- INVITE: okno zaproszeń Robloxa.
function Codes.invite()
	local player = Players.LocalPlayer
	local ok, can = pcall(function()
		return SocialService:CanSendGameInviteAsync(player)
	end)
	if ok and can then
		pcall(function()
			SocialService:PromptGameInvite(player)
		end)
		return true
	end
	fail(TEXT.InviteFailed, "InviteError")
	return false
end

-- Nazwa grupy z Robloxa (raz na grę). fn(nazwa) od razu, gdy jest, inaczej po pobraniu.
local groupName = nil
local groupNameFor = nil
local waiting = {}
function Codes.groupName(groupId, fn)
	if groupId == nil or groupId <= 0 then
		return
	end
	if groupNameFor == groupId and groupName ~= nil then
		fn(groupName)
		return
	end
	table.insert(waiting, fn)
	if groupNameFor == groupId then
		return
	end
	groupNameFor = groupId
	task.spawn(function()
		local ok, info = pcall(function()
			return GroupService:GetGroupInfoAsync(groupId)
		end)
		if ok and type(info) == "table" and type(info.Name) == "string" then
			groupName = info.Name
			local list = waiting
			waiting = {}
			for _, callback in ipairs(list) do
				task.spawn(callback, groupName)
			end
		end
	end)
end

function Codes.start(hudApi)
	hud = hudApi
	-- bonus za grupę i znajomych: komunikat, gdy się włącza i gdy znajomy wchodzi albo wychodzi
	State.onNotify(function(payload)
		if payload.Kind ~= "Bonus" then
			return
		end
		local B = Economy.Bonuses
		local text = nil
		local icon = "Friends"
		if payload.What == "Group" then
			icon = "Group"
			text = string.format((payload.Joined and TEXT.ToastGroupJoined) or TEXT.ToastGroup, percent(B.Group))
			if payload.Joined then
				Sounds.play("Unlock", { volume = 0.7 })
			end
		elseif payload.What == "Friend" then
			text = string.format(TEXT.ToastFriend, tostring(payload.Name), percent(B.FriendEach), payload.Friends or 0, B.FriendMax)
		elseif payload.What == "FriendLeft" then
			text = string.format(TEXT.ToastFriendLeft, tostring(payload.Name), payload.Friends or 0, B.FriendMax)
		end
		if text ~= nil then
			toast({ { icon = icon, size = 40 }, { text = text, size = 26, colors = Theme.Gradients.Gold } }, "Bonus" .. tostring(payload.What) .. tostring(payload.Name))
		end
	end)
end

return Codes
