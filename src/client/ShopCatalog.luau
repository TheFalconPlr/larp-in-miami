-- Treść sklepu za Robuxy w jednym miejscu: nazwy, opisy, kolory i grafiki gamepassów i produktów
-- (dla okna SHOP, podziękowania po zakupie i kafelków po prawej) oraz napisy w UI.
-- Ceny i ID są w Shared/Robux i Config/RobuxIds, a logika zakupu na serwerze (ShopService).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Economy = require(ReplicatedStorage:WaitForChild("Shared").Config.Economy)
local Theme = require(script.Parent.Ui.Theme)

local Catalog = {}

local sp = Economy.Robux.Products.StarterPack

Catalog.TEXT = {
	Shop = "SHOP",
	Teleport = "TELEPORT",
	Title = "Shop",
	Offers = "OFFERS",
	Passes = "PASSES",
	Boosts = "BOOSTS",
	OffersHeader = "Special Offers",
	PassesHeader = "Gamepasses",
	BoostsHeader = "Boosts",
	Owned = "OWNED",
	Forever = "FOREVER",
	Starter = "STARTER PACK",
	StarterEnds = "Ends in %s",
	OneTime = "ONE TIME ONLY!",
	Best = "BEST VALUE!",
	BestDeal = "BEST DEAL",
	Free = "FREE 2x LP!",
	FreeTag = "FREE",
	FreeDesc = "Watch a video: %d min 2x LP · %d/%d left today", -- nagroda opisana przed reklamą (zasady Roblox)
	Watch = "WATCH",
	WatchTest = "WATCH (TEST)",
	NoAds = "NO ADS NOW",
	Stacks = "Stacks with the 2x LP gamepass!",
	TeleportTitle = "Teleport",
	TeleportNote = "Teleport to any unlocked zone!",
	TeleportBuy = "GET TELEPORT",
	ZoneButton = "%d · %s",
	BoostLP = "2x LP",
	BoostAutoSell = "AUTO SELL",
	-- podziękowanie po zakupie
	Thanks = "THANK YOU!",
	ThanksPass = "Yours forever!",
	ThanksStarter = "Everything is in your inventory!",
	ThanksBoost = "+%d min",
	ThanksSell = "Bag sold!",
	ThanksPets = "Enjoy your new pets!",
	ThanksPet = "Enjoy your new pet!",
	ThanksTest = "TEST PURCHASE",
	TapToContinue = "Tap to continue",
	-- komunikaty
	Reasons = {
		Soon = "Coming soon!",
		Owned = "You already own this!",
		Expired = "This offer has ended",
		Zone = "Unlock this zone first!",
		Locked = "Unlock this zone first!",
		EmptyBag = "Your bag is empty!",
		Restricted = "Not available in your region",
		NotRestricted = "Buy the Premium Egg instead!",
		Limit = "No more free boosts today",
		NoPass = "You need the Teleport gamepass",
		Busy = "Finish what you're doing first",
		Error = "Something went wrong, try again",
	},
	TestBuy = "TEST PURCHASE",
	-- zakładka FREE na dole sklepu (Etap 11): bonus za grupę i znajomych, sekretne kody
	FreeTab = "FREE",
	FreeHeader = "Free Bonuses",
	GroupName = "Join the Group",
	GroupDesc = "+%d%% LP forever for members of %s",
	GroupActive = "You're in %s: +%d%% LP is on!",
	GroupNone = "No group for this game yet",
	GroupDefault = "our group",
	Join = "JOIN GROUP",
	Active = "ACTIVE",
	FriendsName = "Play with Friends",
	FriendsDesc = "+%d%% LP for each friend on your server (up to %d). Here now: %d",
	Invite = "INVITE",
	CodesHeader = "Secret Codes!",
	CodesTitle = "Got a secret code?",
	CodesDesc = "Enter it to unlock a reward!",
	CodesPlaceholder = "Enter code",
	Redeem = "REDEEM",
	CodesNote = "Each code works once per account!",
	ThanksSupport = "Thanks for the support",
	BoostDaily = "Verified bonus: 2x LP %d min!",
	BoostAd = "Thanks for watching! 2x LP +%d min",
	BoostEnded = "%s boost ended",
}

-- Gamepassy: nazwa, opis, grafika (ShopArt), kolory karty, mała ikona w tle karty i napis w rogu.
-- Kolejność w sklepie: Robux.PassOrder; dwa pierwsze są na dużych kartach (Catalog.FEATURED).
Catalog.PASSES = {
	TwoXLP = { name = "2x LP", desc = "Double LP from clicks and activities", art = "TwoXLP", colors = Theme.Gradients.LP, tag = "x2" },
	AutoSell = { name = "Auto Sell", desc = "Sells your Bag automatically, anywhere", art = "AutoSell", colors = Theme.Gradients.Green },
	AutoClick = { name = "Auto Click", desc = "Clicks for you, 3 times a second", art = "AutoClick", colors = Theme.Gradients.Yellow },
	Verified = { name = "Verified", desc = "+10% LP, blue check and 15 min 2x LP daily", art = "Verified", colors = Theme.Gradients.Cyan },
	PetSlots = { name = "+2 Pet Slots", desc = "Equip 2 more pets", art = "PetSlots", colors = Theme.Gradients.Pink },
	TripleOpen = { name = "Triple Open", desc = "Open 3 eggs or boxes at once", art = "TripleOpen", colors = Theme.Gradients.Premium },
	FastOpen = { name = "Fast Open", desc = "Open eggs and boxes 3× faster", art = "FastOpen", colors = Theme.Gradients.Red },
	TwoXBag = { name = "2x Bag", desc = "Double Bag capacity", art = "TwoXBag", colors = Theme.Gradients.Gold },
	Teleport = { name = "Teleport", desc = "Teleport to any unlocked zone", art = "Teleport", colors = Theme.Gradients.Portal },
	DoubleChain = { name = "Double Chain", desc = "Wear 2 chains at once", art = "DoubleChain", colors = Theme.Gradients.Gold },
	DoubleWrist = { name = "Double Wrist", desc = "Wear 2 watches at once", art = "DoubleWrist", colors = Theme.Gradients.Pink },
}
Catalog.FEATURED = { TwoXLP = true, AutoSell = true }

-- Boosty: karta z kilkoma czasami do wyboru (jak paczki w PS99) i Sell Now.
Catalog.BOOST_GROUPS = {
	{
		name = "LP",
		title = "2x LP Boost",
		desc = "Double LP from clicks and activities",
		note = Catalog.TEXT.Stacks,
		art = "Boost2xLP",
		colors = Theme.Gradients.LP,
		options = {
			{ key = "Boost2xLP5", label = "5 MIN", minutes = 5 },
			{ key = "Boost2xLP15", label = "15 MIN", minutes = 15 },
			{ key = "Boost2xLP60", label = "1 HOUR", minutes = 60 },
		},
	},
	{
		name = "AutoSell",
		title = "Auto Sell Boost",
		desc = "Your Bag sells itself, anywhere",
		art = "BoostAutoSell",
		colors = Theme.Gradients.Green,
		options = {
			{ key = "BoostAutoSell15", label = "15 MIN", minutes = 15 },
			{ key = "BoostAutoSell60", label = "1 HOUR", minutes = 60 },
		},
	},
}
Catalog.SELL_NOW = { key = "SellNow", name = "Sell Now", desc = "Sell your Bag from anywhere", art = "SellNow", colors = Theme.Gradients.Gold }

-- Zakładka FREE (Etap 11): karty bonusów (grafika ShopArt, kolory, przycisk) i karta kodów.
Catalog.BONUS = {
	Group = { name = Catalog.TEXT.GroupName, art = "Group", colors = Theme.Gradients.CardBlue, button = Catalog.TEXT.Join, buttonColors = Theme.Gradients.Green },
	Friends = { name = Catalog.TEXT.FriendsName, art = "Friends", colors = Theme.Gradients.CardPink, button = Catalog.TEXT.Invite, buttonColors = Theme.Gradients.Gold },
}
Catalog.CODES = { art = "Code", colors = Theme.Gradients.Premium }

-- Starter Pack: cztery rzeczy w środku (grafika ShopArt i podpis).
Catalog.STARTER_ITEMS = {
	{ art = "StarterWatch", label = sp.Watch .. " Watch" },
	{ art = "StarterPet", label = sp.PetRarity .. " Pet" },
	{ art = "Boost2xLP", label = string.format("2x LP\n%d min", sp.BoostMinutes) },
	{ art = "BoostAutoSell", label = string.format("Auto Sell\n%d min", sp.AutoSellMinutes) },
}

-- Podziękowanie za produkt (klucz z Robux.Products): nazwa i grafika.
Catalog.PRODUCTS = {
	StarterPack = { name = "Starter Pack", art = "Starter" },
	Boost2xLP5 = { name = "2x LP Boost", art = "Boost2xLP" },
	Boost2xLP15 = { name = "2x LP Boost", art = "Boost2xLP" },
	Boost2xLP60 = { name = "2x LP Boost", art = "Boost2xLP" },
	BoostAutoSell15 = { name = "Auto Sell Boost", art = "BoostAutoSell" },
	BoostAutoSell60 = { name = "Auto Sell Boost", art = "BoostAutoSell" },
	SellNow = { name = "Sell Now", art = "SellNow" },
	PremiumEgg1 = { name = "Premium Egg", art = "PremiumEgg" },
	PremiumEgg3 = { name = "3 Premium Eggs", art = "PremiumEgg" },
	PremiumEgg10 = { name = "10 Premium Eggs", art = "PremiumEgg" },
	DirectPetEpic = { name = "Epic Pet", art = "StarterPet" },
	DirectPetLegendary = { name = "Legendary Pet", art = "StarterPet" },
	DirectPetMythic = { name = "Mythic Pet", art = "StarterPet" },
}

return Catalog
