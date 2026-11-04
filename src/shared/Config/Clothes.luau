-- Ubrania i boxy: nazwy, kolory i kształty (edytowane ręcznie). Liczby (ceny, szanse, bonusy) są
-- w Economy.luau. Każda kategoria ma jedno ubranie na rzadkość. Nazwy są robocze, zmień je śmiało,
-- tylko bez słów „Golden” i „Diamond” na początku: tak zaczynają się nazwy po łączeniu.
--
-- Dopóki nie ma rzeczy z katalogu Roblox, ubrania są zbudowane z klocków (Shared/ClothModels):
--   Main    główny kolor (włosy, szkła okularów, koszula, spodnie, buty, pasek zegarka, zawieszka)
--   Accent  drugi kolor (oprawka, ogniwa łańcucha, tarcza zegarka, pasek spodni, podeszwa, wstawki)
--   Finish  wykończenie głównego koloru: Metal (połysk), Ice (lód i blask), Neon (świeci), Fabric
--           (materiał); drugi kolor dostaje to samo (poza Neon i Fabric), chyba że ma własne AccentFinish
--   Crosses krzyże w drugim kolorze (ubrania „chrome” z Ultra Secret)
--   oraz kształt zależny od kategorii (opisany przy kategorii).
--
-- UltraSecret: ubrania „chrome” tylko z boxa Iced (1 na 250 000): czarne ze srebrnymi i białymi
-- krzyżami. Tylko styl, bez nazwy prawdziwej marki i bez logo (jak przy autach).

local hex = Color3.fromHex

local Clothes = {}

-- [kategoria][rzadkość] = ubranie
Clothes.Items = {
	-- Style: Short (krótkie), Slick (zaczesane do tyłu), Waves (fale), Flow (długie), Beanie (czapka)
	Hair = {
		Common = { Name = "Buzz Cut", Main = hex("#3B2A20"), Style = "Short" },
		Uncommon = { Name = "Fresh Fade", Main = hex("#1E1A18"), Style = "Short" },
		Rare = { Name = "Slick Back", Main = hex("#2E1F14"), Style = "Slick", Finish = "Metal" },
		Epic = { Name = "Bleached Waves", Main = hex("#F2E3A0"), Style = "Waves" },
		Legendary = { Name = "Platinum Flow", Main = hex("#E6ECF5"), Style = "Flow", Finish = "Metal" },
		Mythic = { Name = "Neon Flow", Main = hex("#FF4FD8"), Style = "Flow", Finish = "Neon" },
		UltraSecret = { Name = "Chrome Cross Beanie", Main = hex("#141418"), Accent = hex("#DDE2EA"), Style = "Beanie", Finish = "Fabric", AccentFinish = "Metal", Crosses = true },
	},
	-- Visor = jedna szeroka szyba zamiast dwóch szkieł
	Glasses = {
		Common = { Name = "Plastic Shades", Main = hex("#1E1E24"), Accent = hex("#EDEDED") },
		Uncommon = { Name = "Aviators", Main = hex("#4A3A22"), Accent = hex("#C9CED6"), Finish = "Metal" },
		Rare = { Name = "Racer Shades", Main = hex("#FF7A1A"), Accent = hex("#202020"), Visor = true },
		Epic = { Name = "Lux Frames", Main = hex("#2B2B35"), Accent = hex("#FFC233"), Finish = "Metal" },
		Legendary = { Name = "Iced Shades", Main = hex("#9BE8FF"), Accent = hex("#FFFFFF"), Finish = "Ice" },
		Mythic = { Name = "Laser Visor", Main = hex("#FF2E4D"), Accent = hex("#202020"), Visor = true, Finish = "Neon" },
		UltraSecret = { Name = "Chrome Cross Shades", Main = hex("#0E0E12"), Accent = hex("#DDE2EA"), AccentFinish = "Metal", Crosses = true },
	},
	-- Links = grubość ogniw (1 = zwykła), Pendant = zawieszka (Gem, Plate albo Cross)
	Chain = {
		Common = { Name = "Thin Chain", Main = hex("#C9CED6"), Accent = hex("#C9CED6"), Links = 0.8, Finish = "Metal" },
		Uncommon = { Name = "Rope Chain", Main = hex("#FFC233"), Accent = hex("#FFC233"), Links = 1, Finish = "Metal" },
		Rare = { Name = "Cuban Link", Main = hex("#FFB21E"), Accent = hex("#FFB21E"), Links = 1.35, Finish = "Metal" },
		Epic = { Name = "Pendant Chain", Main = hex("#3DA9FF"), Accent = hex("#FFC233"), Links = 1, Pendant = "Gem", Finish = "Metal" },
		Legendary = { Name = "Iced Cuban", Main = hex("#DFF7FF"), Accent = hex("#DFF7FF"), Links = 1.4, Finish = "Ice" },
		Mythic = { Name = "Dollar Chain", Main = hex("#2ECC71"), Accent = hex("#FFC233"), Links = 1.3, Pendant = "Plate", Finish = "Metal" },
		UltraSecret = { Name = "Chrome Cross Chain", Main = hex("#DDE2EA"), Accent = hex("#DDE2EA"), Links = 1.2, Pendant = "Cross", Finish = "Metal" },
	},
	Watch = {
		Common = { Name = "Digital Watch", Main = hex("#222222"), Accent = hex("#7CFC8A") },
		Uncommon = { Name = "Steel Watch", Main = hex("#C9CED6"), Accent = hex("#FFFFFF"), Finish = "Metal" },
		Rare = { Name = "Chrono Watch", Main = hex("#2B2B35"), Accent = hex("#1F6FD1"), Finish = "Metal" },
		Epic = { Name = "Rose Watch", Main = hex("#E8A07A"), Accent = hex("#FFF1E6"), Finish = "Metal" },
		Legendary = { Name = "Iced Watch", Main = hex("#DFF7FF"), Accent = hex("#9BE8FF"), Finish = "Ice" },
		Mythic = { Name = "Moon Watch", Main = hex("#202030"), Accent = hex("#B060FF"), AccentFinish = "Neon" },
		UltraSecret = { Name = "Chrome Cross Watch", Main = hex("#141418"), Accent = hex("#DDE2EA"), AccentFinish = "Metal", Crosses = true },
	},
	-- Sleeves: None (bez rękawów), Short, Long; Bulky = grubsze (futro); Dots = kwiaty z przodu
	Shirt = {
		Common = { Name = "Plain Tee", Main = hex("#FFFFFF"), Accent = hex("#D0D4DC"), Sleeves = "Short" },
		Uncommon = { Name = "Tank Top", Main = hex("#3DA9FF"), Accent = hex("#FFFFFF"), Sleeves = "None" },
		Rare = { Name = "Flower Shirt", Main = hex("#FF6CB8"), Accent = hex("#FFE14D"), Sleeves = "Short", Dots = true },
		Epic = { Name = "Silk Shirt", Main = hex("#7A2CF5"), Accent = hex("#FFC233"), Sleeves = "Long", Finish = "Metal" },
		Legendary = { Name = "Fur Coat", Main = hex("#F4EBDD"), Accent = hex("#C8B89A"), Sleeves = "Long", Bulky = true },
		Mythic = { Name = "Iced Jacket", Main = hex("#BDEFFF"), Accent = hex("#FFFFFF"), Sleeves = "Long", Finish = "Ice" },
		UltraSecret = { Name = "Chrome Cross Tee", Main = hex("#141418"), Accent = hex("#EEF1F5"), Sleeves = "Long", Finish = "Fabric", Crosses = true },
	},
	-- Long = długie nogawki (bez tego szorty)
	Pants = {
		Common = { Name = "Gym Shorts", Main = hex("#3B4252"), Accent = hex("#FFFFFF") },
		Uncommon = { Name = "Cargo Shorts", Main = hex("#8A7A55"), Accent = hex("#5A4D33") },
		Rare = { Name = "Linen Pants", Main = hex("#F1E8D6"), Accent = hex("#A08860"), Long = true },
		Epic = { Name = "Silk Pants", Main = hex("#1F1530"), Accent = hex("#FFC233"), Long = true, Finish = "Metal" },
		Legendary = { Name = "Velvet Pants", Main = hex("#8E1B3A"), Accent = hex("#FFC233"), Long = true },
		Mythic = { Name = "Iced Jeans", Main = hex("#9FD8FF"), Accent = hex("#FFFFFF"), Long = true, Finish = "Ice" },
		UltraSecret = { Name = "Chrome Cross Jeans", Main = hex("#2E2E34"), Accent = hex("#EEF1F5"), Long = true, Finish = "Fabric", Crosses = true },
	},
	-- Flat = płaskie (klapki), bez tego sneakersy
	Shoes = {
		Common = { Name = "Flip Flops", Main = hex("#3DA9FF"), Accent = hex("#F2F2F2"), Flat = true },
		Uncommon = { Name = "Slides", Main = hex("#222222"), Accent = hex("#FFFFFF"), Flat = true },
		Rare = { Name = "Fresh Kicks", Main = hex("#FFFFFF"), Accent = hex("#FF2E4D") },
		Epic = { Name = "Runway Sneakers", Main = hex("#FF4F86"), Accent = hex("#FFFFFF") },
		Legendary = { Name = "Croc Loafers", Main = hex("#4A7A3A"), Accent = hex("#2B1D10"), Finish = "Metal" },
		Mythic = { Name = "Iced Kicks", Main = hex("#DFF7FF"), Accent = hex("#9BE8FF"), Finish = "Ice" },
		UltraSecret = { Name = "Chrome Cross Kicks", Main = hex("#141418"), Accent = hex("#F2F2F2"), AccentFinish = "Metal", Crosses = true },
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
