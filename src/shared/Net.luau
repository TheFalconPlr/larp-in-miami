-- Zdarzenia sieciowe gry (RemoteEvent i RemoteFunction) w jednym miejscu.
-- Serwer tworzy je przy starcie (Net.setup), a klient czeka na nie po nazwie.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = {}

-- klient → serwer: Click, TeleportToSell, SetSetting, Admin, GroupJoined (gracz dołączył do grupy
-- przyciskiem JOIN GROUP: serwer sprawdza to sam)
-- serwer → klient: Sync (stan gracza), Notify (komunikaty)
local EVENTS = { "Click", "TeleportToSell", "SetSetting", "Admin", "GroupJoined", "Sync", "Notify" }
-- klient → serwer z odpowiedzią: BuyUpgrade, BuyZone, StartActivity, BuyActivityTier, BuyEgg,
-- EquipPet, EquipBest, SellPets, MergePets, BuyBox, WearCloth, WearBest, SellClothes, MergeClothes,
-- Rebirth, BuyAuraUpgrade, Buy (Robux: okno zakupu), WatchAd (reklama za nagrodę), TeleportToZone,
-- RedeemCode (kod z budki z kodami)
local FUNCTIONS = {
	"BuyUpgrade",
	"BuyZone",
	"StartActivity",
	"BuyActivityTier",
	"BuyEgg",
	"EquipPet",
	"EquipBest",
	"SellPets",
	"MergePets",
	"BuyBox",
	"WearCloth",
	"WearBest",
	"SellClothes",
	"MergeClothes",
	"Rebirth",
	"BuyAuraUpgrade",
	"Buy",
	"WatchAd",
	"TeleportToZone",
	"RedeemCode",
}

local FOLDER_NAME = "Remotes"

local function folder()
	if RunService:IsServer() then
		local f = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
		if f == nil then
			f = Instance.new("Folder")
			f.Name = FOLDER_NAME
			f.Parent = ReplicatedStorage
		end
		return f
	end
	return ReplicatedStorage:WaitForChild(FOLDER_NAME)
end

local function get(name, className)
	local f = folder()
	if RunService:IsServer() then
		local remote = f:FindFirstChild(name)
		if remote == nil then
			remote = Instance.new(className)
			remote.Name = name
			remote.Parent = f
		end
		return remote
	end
	return f:WaitForChild(name)
end

function Net.setup()
	for _, name in ipairs(EVENTS) do
		get(name, "RemoteEvent")
	end
	for _, name in ipairs(FUNCTIONS) do
		get(name, "RemoteFunction")
	end
end

function Net.event(name)
	return get(name, "RemoteEvent")
end

function Net.func(name)
	return get(name, "RemoteFunction")
end

return Net
