-- Pety i jajka: nazwy i kolory (edytowane ręcznie). Liczby (ceny, szanse, moc) są w Economy.luau.
-- Każda strefa ma po jednym pecie na rzadkość. Nazwy są robocze, zmień je śmiało.
-- Własne modele petów: model w ReplicatedStorage → PetModels o nazwie peta (np. „Pigeon”).
-- Bez modelu pet jest kolorową kulką z oczami (kolor rzadkości).

local hex = Color3.fromHex

local Pets = {}

-- [strefa][rzadkość] = nazwa peta w grze
Pets.Names = {
	[1] = { -- Downtown Miami
		Common = "Pigeon",
		Uncommon = "Alley Cat",
		Rare = "Chihuahua",
		Epic = "Flamingo",
		Legendary = "Golden Doge",
		Mythic = "Neon Iguana",
		Secret = "Diamond Flamingo",
	},
	[2] = { -- Luxury Cars
		Common = "Hamster",
		Uncommon = "Bulldog",
		Rare = "Dalmatian",
		Epic = "Racing Fox",
		Legendary = "Turbo Cheetah",
		Mythic = "Chrome Panther",
		Secret = "Gold Rim Lion",
	},
	[3] = { -- Luxury Mall
		Common = "Poodle",
		Uncommon = "Persian Cat",
		Rare = "Pomeranian",
		Epic = "Designer Bunny",
		Legendary = "Lux Fox",
		Mythic = "Velvet Peacock",
		Secret = "Platinum Pug",
	},
	[4] = { -- Miami Beach
		Common = "Crab",
		Uncommon = "Seagull",
		Rare = "Sea Turtle",
		Epic = "Dolphin",
		Legendary = "Manatee",
		Mythic = "Neon Shark",
		Secret = "Golden Whale",
	},
	[5] = { -- Private Airport
		Common = "Parrot",
		Uncommon = "Eagle",
		Rare = "Jet Owl",
		Epic = "Falcon",
		Legendary = "Phoenix",
		Mythic = "Sky Dragon",
		Secret = "Diamond Griffin",
	},
}

-- Kolory rzadkości (napisy w UI i kulki-pety bez własnego modelu)
Pets.RarityColors = {
	Common = hex("#C3C8D4"),
	Uncommon = hex("#5BD86A"),
	Rare = hex("#3DA9FF"),
	Epic = hex("#B060FF"),
	Legendary = hex("#FFB21E"),
	Mythic = hex("#FF4F86"),
	Secret = hex("#2B2B35"),
}

-- Nazwy jajek w grze: A za L$, B (lepsze szanse) za L$
Pets.EggNames = {
	A = "%s Egg",
	B = "%s Golden Egg",
}

-- Najwięcej petów w ekwipunku (żeby zapis gracza nie rósł bez końca)
Pets.MaxInventory = 250

function Pets.name(zone, rarity)
	local list = Pets.Names[zone]
	return (list and list[rarity]) or rarity
end

return Pets
