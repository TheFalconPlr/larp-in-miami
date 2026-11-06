-- Gamepassy i produkty za Robuxy w jednym miejscu: ID z Config/RobuxIds (ręczny plik), opis i zapasowa
-- cena z Economy.Robux (generowany). Bez Roblox API, więc działa na serwerze, w UI i w testach.

local Economy = require(script.Parent.Config.Economy)
local Ids = require(script.Parent.Config.RobuxIds)

local Robux = {}

Robux.Gamepasses = Economy.Robux.Gamepasses
Robux.Products = Economy.Robux.Products
Robux.AdReward = Economy.Robux.AdReward

-- Klucze w stałej kolejności (sklep pokazuje je w tej kolejności).
Robux.PassOrder = {
	"TwoXLP",
	"AutoSell",
	"AutoClick",
	"Verified",
	"PetSlots",
	"TripleOpen",
	"FastOpen",
	"TwoXBag",
	"Teleport",
	"DoubleChain",
	"DoubleWrist",
}

local function idOf(list, key)
	local id = list and list[key]
	if type(id) == "number" and id > 0 then
		return id
	end
	return nil
end

-- ID gamepassa albo nil, gdy jeszcze go nie ma (0 w Config/RobuxIds).
function Robux.passId(key)
	return idOf(Ids.Gamepasses, key)
end

-- ID produktu albo nil.
function Robux.productId(key)
	return idOf(Ids.Products, key)
end

-- kind: "Pass" albo "Product".
function Robux.id(kind, key)
	if kind == "Pass" then
		return Robux.passId(key)
	end
	return Robux.productId(key)
end

function Robux.info(kind, key)
	if kind == "Pass" then
		return Robux.Gamepasses[key]
	elseif kind == "Product" then
		return Robux.Products[key]
	end
	return nil
end

-- Klucz gamepassa albo produktu po ID (np. z paragonu). nil, gdy nie znamy takiego ID.
function Robux.passKey(id)
	for key in pairs(Robux.Gamepasses) do
		if Robux.passId(key) == id then
			return key
		end
	end
	return nil
end

function Robux.productKey(id)
	for key in pairs(Robux.Products) do
		if Robux.productId(key) == id then
			return key
		end
	end
	return nil
end

-- Cena z Economy (zapas, gdy GetProductInfoAsync nie odpowie).
function Robux.basePrice(kind, key)
	local info = Robux.info(kind, key)
	return info and info.Price
end

function Robux.placementId()
	local id = Ids.AdPlacementId
	if type(id) == "number" and id > 0 then
		return id
	end
	return nil
end

return Robux
