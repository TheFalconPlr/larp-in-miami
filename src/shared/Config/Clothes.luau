-- Ubrania i boxy: nazwy, kolory i kształty (edytowane ręcznie). Liczby (ceny, szanse, bonusy) są
-- w Economy.luau. Każda kategoria ma jedno ubranie na rzadkość. Nazwy są robocze, zmień je śmiało,
-- tylko bez słów „Golden” i „Diamond” na początku: tak zaczynają się nazwy po łączeniu.
--
-- Dopóki nie ma rzeczy z katalogu Roblox, ubrania są zbudowane z klocków (Shared/ClothModels):
--   Main    główny kolor (włosy, szkła okularów, koszula, spodnie, cholewka buta, pasek zegarka)
--   Accent  drugi kolor (oprawka, ogniwa łańcucha, tarcza zegarka, lamówki, podeszwa, płatki kwiatów)
--   Detail  trzeci kolor (guziki, środek kwiatka, pasek w spodniach); bez niego jak Accent
--   Lens    kolor szkieł okularów (bez niego Main), Metal kolor metalowych dodatków (koperta, zamek)
--   Finish  wykończenie głównego koloru: Metal (połysk metalu), Ice (lód i blask), Neon (świeci),
--           Fabric (materiał), Gloss (połysk, np. żel na włosach), Satin (jedwab); drugi kolor dostaje
--           to samo (poza Neon i Fabric), chyba że ma własne AccentFinish
--   Crosses krzyże (ubrania „chrome” z Ultra Secret)
--   oraz kształt zależny od kategorii (opisany przy kategorii).
--
-- UltraSecret: ubrania „chrome” tylko z boxa Iced (1 na 250 000): czarne ze srebrnymi i białymi
-- krzyżami. Tylko styl, bez nazwy prawdziwej marki i bez logo (jak przy autach).

local hex = Color3.fromHex

local Clothes = {}

-- [kategoria][rzadkość] = ubranie
Clothes.Items = {
	-- Style: Buzz (krótko), Fade (wyżej na górze, krótko po bokach), Slick (zaczesane do tyłu),
	-- Curls (loki), Flow (długie do ramion), Beanie (czapka z wywiniętym brzegiem)
	Hair = {
		Common = { Name = "Buzz Cut", Main = hex("#3B2A20"), Style = "Buzz" },
		Uncommon = { Name = "Fresh Fade", Main = hex("#1E1A18"), Style = "Fade" },
		Rare = { Name = "Slick Back", Main = hex("#2E1F14"), Style = "Slick", Finish = "Gloss" },
		Epic = { Name = "Bleached Waves", Main = hex("#F2E3A0"), Style = "Curls" },
		Legendary = { Name = "Platinum Flow", Main = hex("#E6ECF5"), Style = "Flow", Finish = "Gloss" },
		Mythic = { Name = "Neon Flow", Main = hex("#FF4FD8"), Style = "Flow", Finish = "Neon" },
		UltraSecret = { Name = "Chrome Cross Beanie", Main = hex("#141418"), Accent = hex("#DDE2EA"), Style = "Beanie", Finish = "Fabric", AccentFinish = "Metal", Crosses = true },
	},
	-- Style: Square (kwadratowe oprawki), Aviator (łezki), Wrap (szyba dookoła), Visor (jedna szyba).
	-- Accent = oprawka, Lens/Main = szkła. Bold = grube oprawki, Studs = kamyczki na oprawce.
	Glasses = {
		Common = { Name = "Plastic Shades", Main = hex("#23232B"), Accent = hex("#EDEDED"), Style = "Square" },
		Uncommon = { Name = "Aviators", Main = hex("#5A4425"), Accent = hex("#D3D8E0"), Style = "Aviator", AccentFinish = "Metal" },
		Rare = { Name = "Racer Shades", Main = hex("#FF7A1A"), Accent = hex("#202020"), Style = "Wrap" },
		Epic = { Name = "Lux Frames", Main = hex("#2B2B35"), Accent = hex("#FFC233"), Style = "Square", Bold = true, AccentFinish = "Metal" },
		Legendary = { Name = "Iced Shades", Main = hex("#9BE8FF"), Accent = hex("#F4FBFF"), Style = "Square", Studs = true, Finish = "Ice" },
		Mythic = { Name = "Laser Visor", Main = hex("#FF2E4D"), Accent = hex("#202020"), Style = "Visor", Finish = "Neon" },
		UltraSecret = { Name = "Chrome Cross Shades", Main = hex("#0E0E12"), Accent = hex("#16161B"), Style = "Square", Crosses = true },
	},
	-- Links = wielkość ogniw (1 = zwykła), Count = liczba ogniw, Rope = skręcone, Cuban = grube płaskie,
	-- Pendant = zawieszka (Gem, Dollar albo Cross). Accent = ogniwa, Main = zawieszka.
	Chain = {
		Common = { Name = "Thin Chain", Main = hex("#C9CED6"), Accent = hex("#D5DAE2"), Links = 0.8, Count = 19, Finish = "Metal" },
		Uncommon = { Name = "Rope Chain", Main = hex("#FFC233"), Accent = hex("#FFC233"), Rope = true, Finish = "Metal" },
		Rare = { Name = "Cuban Link", Main = hex("#FFB21E"), Accent = hex("#FFB21E"), Cuban = true, Links = 1.05, Finish = "Metal" },
		Epic = { Name = "Pendant Chain", Main = hex("#3DA9FF"), Accent = hex("#FFC233"), Pendant = "Gem", Finish = "Metal" },
		Legendary = { Name = "Iced Cuban", Main = hex("#DFF7FF"), Accent = hex("#DFF7FF"), Cuban = true, Links = 1.1, Finish = "Ice" },
		Mythic = { Name = "Dollar Chain", Main = hex("#2ECC71"), Accent = hex("#FFC233"), Rope = true, Pendant = "Dollar", Finish = "Metal" },
		UltraSecret = { Name = "Chrome Cross Chain", Main = hex("#DDE2EA"), Accent = hex("#DDE2EA"), Links = 1.1, Pendant = "Cross", Finish = "Metal" },
	},
	-- Style: Analog (koperta, luneta, tarcza, wskazówki) albo Digital. Main = pasek, Accent = tarcza,
	-- Metal = koperta. Chrono = małe tarcze, Studs = kamyczki na lunecie, Moon = księżyc na tarczy.
	Watch = {
		Common = { Name = "Digital Watch", Main = hex("#222222"), Accent = hex("#7CFC8A"), Style = "Digital" },
		Uncommon = { Name = "Steel Watch", Main = hex("#C9CED6"), Accent = hex("#FFFFFF"), Style = "Analog", Finish = "Metal", AccentFinish = "Satin" },
		Rare = { Name = "Chrono Watch", Main = hex("#2B2B35"), Accent = hex("#1F6FD1"), Style = "Analog", Chrono = true, Finish = "Metal" },
		Epic = { Name = "Rose Watch", Main = hex("#E8A07A"), Accent = hex("#FFF1E6"), Metal = hex("#F0B08C"), Style = "Analog", Finish = "Metal", AccentFinish = "Satin" },
		Legendary = { Name = "Iced Watch", Main = hex("#DFF7FF"), Accent = hex("#9BE8FF"), Metal = hex("#EAF8FF"), Style = "Analog", Studs = true, Finish = "Ice" },
		Mythic = { Name = "Moon Watch", Main = hex("#202030"), Accent = hex("#B060FF"), Style = "Analog", Moon = true, DialFinish = "Neon" },
		UltraSecret = { Name = "Chrome Cross Watch", Main = hex("#141418"), Accent = hex("#1A1A20"), Style = "Analog", Crosses = true },
	},
	-- Sleeves: None (na ramiączkach), Short, Long. Collar: Crew, V, Open (rozpięty z wyłogami), Fur,
	-- High (stójka), None. Pocket (kieszonka), Buttons, Flowers (kwiaty), Puffer (pikowane pasy), Zipper,
	-- Coat (płaszcz do pół uda), Fur (futrzane mankiety i obszycia), Bulky (grubszy), Number (numer
	-- z przodu i z tyłu). TrimRole/CuffRole = kolor lamówek i mankietów (domyślnie Dark: główny ciemniej).
	Shirt = {
		Common = { Name = "Plain Tee", Main = hex("#FFFFFF"), Accent = hex("#D0D4DC"), Sleeves = "Short", Collar = "Crew", Pocket = true, Finish = "Fabric" },
		Uncommon = { Name = "Tank Top", Main = hex("#3DA9FF"), Accent = hex("#FFFFFF"), Sleeves = "None", Collar = "None", Number = "23", TrimRole = "Accent", Finish = "Fabric" },
		Rare = { Name = "Flower Shirt", Main = hex("#FF6CB8"), Accent = hex("#FFE14D"), Detail = hex("#FFFFFF"), Sleeves = "Short", Collar = "Open", Buttons = true, Flowers = true, Finish = "Fabric" },
		Epic = { Name = "Silk Shirt", Main = hex("#7A2CF5"), Accent = hex("#FFC233"), Sleeves = "Long", Collar = "V", Buttons = true, Finish = "Satin", AccentFinish = "Metal", TrimRole = "Accent", CuffRole = "Accent" },
		Legendary = { Name = "Fur Coat", Main = hex("#E3CDAA"), Accent = hex("#FFF8EC"), Detail = hex("#4A3020"), Sleeves = "Long", Collar = "Fur", Coat = true, Fur = true, Bulky = true, Finish = "Fabric", AccentFinish = "Fabric" },
		Mythic = { Name = "Iced Jacket", Main = hex("#BDEFFF"), Accent = hex("#FFFFFF"), Metal = hex("#FFFFFF"), Sleeves = "Long", Collar = "High", Puffer = true, Zipper = true, Finish = "Ice" },
		UltraSecret = { Name = "Chrome Cross Tee", Main = hex("#141418"), Accent = hex("#EEF1F5"), Sleeves = "Long", Collar = "Crew", Crosses = true, TrimRole = "Accent", Finish = "Fabric" },
	},
	-- Long = długie nogawki (bez tego szorty). Belt (pasek w kolorze Detail z klamrą Buckle), Drawstring,
	-- Stripe (lampas), Cargo (kieszenie na udach), BackPockets, Rips (przetarcia), Studs, Cuffs
	-- (podwinięte nogawki).
	Pants = {
		Common = { Name = "Gym Shorts", Main = hex("#3B4252"), Accent = hex("#FFFFFF"), Stripe = true, Drawstring = true, Finish = "Fabric" },
		Uncommon = { Name = "Cargo Shorts", Main = hex("#8A7A55"), Accent = hex("#6B5D3F"), Detail = hex("#3A2F20"), Cargo = true, Belt = true, Buckle = "Metal", BackPockets = true, Finish = "Fabric" },
		Rare = { Name = "Linen Pants", Main = hex("#F1E8D6"), Accent = hex("#D8CDB6"), Detail = hex("#8A6A42"), Long = true, Belt = true, Cuffs = true, Finish = "Fabric" },
		Epic = { Name = "Silk Pants", Main = hex("#1F1530"), Accent = hex("#FFC233"), Long = true, Stripe = true, Finish = "Satin", AccentFinish = "Metal" },
		Legendary = { Name = "Velvet Pants", Main = hex("#8E1B3A"), Accent = hex("#FFC233"), Detail = hex("#16161B"), Long = true, Stripe = true, Belt = true, Finish = "Fabric", AccentFinish = "Metal" },
		Mythic = { Name = "Iced Jeans", Main = hex("#9FD8FF"), Accent = hex("#FFFFFF"), Long = true, BackPockets = true, Rips = true, Studs = true, Finish = "Ice" },
		UltraSecret = { Name = "Chrome Cross Jeans", Main = hex("#2E2E34"), Accent = hex("#EEF1F5"), Long = true, BackPockets = true, Crosses = true, Finish = "Fabric" },
	},
	-- Style: Sneaker, HighTop (za kostkę), FlipFlop, Slide, Loafer. Main = cholewka, Accent = podeszwa
	-- i wstawki. Chunky = gruba podeszwa, Studs = kamyczki z boku.
	Shoes = {
		Common = { Name = "Flip Flops", Main = hex("#3DA9FF"), Accent = hex("#F2F2F2"), Style = "FlipFlop" },
		Uncommon = { Name = "Slides", Main = hex("#222222"), Accent = hex("#FFFFFF"), Style = "Slide" },
		Rare = { Name = "Fresh Kicks", Main = hex("#FFFFFF"), Accent = hex("#FF2E4D"), Style = "Sneaker" },
		Epic = { Name = "Runway Sneakers", Main = hex("#FF4F86"), Accent = hex("#FFFFFF"), Style = "Sneaker", Chunky = true },
		Legendary = { Name = "Croc Loafers", Main = hex("#4A7A3A"), Accent = hex("#2B1D10"), Style = "Loafer", Finish = "Gloss" },
		Mythic = { Name = "Iced Kicks", Main = hex("#DFF7FF"), Accent = hex("#9BE8FF"), Style = "Sneaker", Studs = true, Finish = "Ice" },
		UltraSecret = { Name = "Chrome Cross Kicks", Main = hex("#141418"), Accent = hex("#F2F2F2"), Style = "HighTop", Crosses = true },
	},
}

-- Kolejność i nazwy kategorii w oknie CLOTHES
Clothes.CategoryOrder = { "Hair", "Glasses", "Chain", "Watch", "Shirt", "Pants", "Shoes" }

-- Boxy w grze: nazwa, kolor pudełka i wstążki, wykończenie (jak przy ubraniach) i krótki opis
-- (stoiska, okno kupna i animacja otwierania)
Clothes.Boxes = {
	Street = { Name = "Street Box", Color = hex("#FF8A1F"), Ribbon = hex("#1FD1C1") },
	Designer = { Name = "Designer Box", Color = hex("#1F1530"), Ribbon = hex("#FFC233"), RibbonFinish = "Metal" },
	Iced = { Name = "Iced Box", Color = hex("#BDEFFF"), Ribbon = hex("#FFFFFF"), Finish = "Ice", RibbonFinish = "Ice" },
}

-- Najwięcej ubrań w ekwipunku (żeby zapis gracza nie rósł bez końca)
Clothes.MaxInventory = 250

local FALLBACK = { Name = "?", Main = hex("#C3C8D4"), Accent = hex("#FFFFFF") }

function Clothes.item(category, rarity)
	local list = Clothes.Items[category]
	return (list and list[rarity]) or FALLBACK
end

function Clothes.name(category, rarity)
	return Clothes.item(category, rarity).Name
end

-- Nazwa z poziomem, np. „Golden Cuban Link” (słowa poziomów jak u petów).
local LEVEL_NAMES = { [1] = "Golden", [2] = "Diamond" }
function Clothes.fullName(category, rarity, level)
	local prefix = LEVEL_NAMES[level or 0]
	if prefix == nil then
		return Clothes.name(category, rarity)
	end
	return prefix .. " " .. Clothes.name(category, rarity)
end

return Clothes
