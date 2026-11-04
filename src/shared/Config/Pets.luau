-- Pety i jajka: nazwy i kolory (edytowane ręcznie). Liczby (ceny, szanse, moc) są w Economy.luau.
-- Każda strefa ma po jednym pecie na rzadkość. Nazwy są robocze, zmień je śmiało, tylko bez słów
-- „Golden” i „Diamond” na początku: tak zaczynają się nazwy petów po łączeniu (Golden Pigeon).
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
		Legendary = "Crypto Doge",
		Mythic = "Neon Iguana",
		Secret = "Iced Flamingo",
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
		Secret = "Mega Whale",
	},
	[5] = { -- Private Airport
		Common = "Parrot",
		Uncommon = "Eagle",
		Rare = "Jet Owl",
		Epic = "Falcon",
		Legendary = "Phoenix",
		Mythic = "Sky Dragon",
		Secret = "Jetset Griffin",
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

-- Poziomy po łączeniu (Level w zapisie): 1 = Złoty, 2 = Diamentowy. Nazwa w grze i kolory kafelka.
Pets.LevelNames = { [1] = "Golden", [2] = "Diamond" }
Pets.LevelColors = {
	[1] = { hex("#FFE066"), hex("#FFB21E") },
	[2] = { hex("#E6FBFF"), hex("#6FD8FF") },
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

-- Nazwa z poziomem, np. „Golden Pigeon” albo „Diamond Pigeon”.
function Pets.fullName(zone, rarity, level)
	local prefix = Pets.LevelNames[level or 0]
	if prefix == nil then
		return Pets.name(zone, rarity)
	end
	return prefix .. " " .. Pets.name(zone, rarity)
end

return Pets
