-- Wygląd UI w jednym miejscu: kolory, gradienty, czcionka i skala.
-- Kierunek: nasycone kolory jak w Pet Simulator 99 (nie pastele), białe okna z delikatnym szarym wzorem,
-- grube ciemne obrysy. Rozmiary w całym UI są w pikselach bazowych ekranu 1280×720.

local hex = Color3.fromHex

local Theme = {}

Theme.Font = Enum.Font.FredokaOne

Theme.Outline = hex("#1F1530") -- obrysy i krawędzie przycisków
Theme.White = hex("#FFFFFF")
Theme.Dark = hex("#1F1530") -- ciemny tekst na jasnym tle
Theme.Muted = hex("#5E5675") -- tekst pomocniczy
Theme.NextValue = "#FFE14D" -- nowa, lepsza wartość w kartach (RichText)
Theme.GoldText = hex("#FFC21A")
Theme.BadgeRed = hex("#FF2E4D")
Theme.TestYellow = hex("#FFD93D")
Theme.PatternColor = hex("#E2E6EF") -- szary wzór w tle okien

-- Gradienty z góry na dół (jaśniejszy → ciemniejszy).
Theme.Gradients = {
	Green = { hex("#86E83E"), hex("#3AB01D") },
	Pink = { hex("#FF6CB8"), hex("#D42C84") },
	Yellow = { hex("#FFDA3D"), hex("#FFA200") },
	Red = { hex("#FF5468"), hex("#D21C38") },
	Gray = { hex("#C9C6D3"), hex("#9790AA") },
	Cyan = { hex("#4FD3FF"), hex("#1C8EE3") },
	Gold = { hex("#FFE45C"), hex("#FFA200") },
	LP = { hex("#FF7AC6"), hex("#F0257F") },
	Aura = { hex("#E2A6FF"), hex("#8A3CF5") },
	Panel = { hex("#FFFFFF"), hex("#EEF1F7") },
	CardPink = { hex("#FF73BC"), hex("#DB3189") },
	CardBlue = { hex("#55CBFF"), hex("#1E88E3") },
	BagFull = { hex("#E8243A"), hex("#A8102A") },
	Money = { hex("#7BF26A"), hex("#14A84A") }, -- zielony jak banknoty (kwoty w komunikatach)
}

-- Pasek Bag: czerwony, od lewej do prawej.
Theme.BagFill = { hex("#FF6B57"), hex("#F23B3B"), hex("#D91A33") }

-- Skala: 1 na ekranie 1280×720, mniej na telefonie, więcej na dużym monitorze.
Theme.BaseSize = Vector2.new(1280, 720)
Theme.MinScale = 0.7
Theme.MaxScale = 1.5

return Theme
