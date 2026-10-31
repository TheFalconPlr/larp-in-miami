-- Wygląd UI w jednym miejscu: kolory, gradienty, czcionka i skala. Projekt: kanwa „Larp in Miami — UI”.
-- Rozmiary w całym UI są w pikselach bazowych ekranu 1280×720; Hud skaluje je do ekranu gracza.

local hex = Color3.fromHex

local Theme = {}

Theme.Font = Enum.Font.FredokaOne

Theme.Outline = hex("#2A1638") -- obrysy i krawędzie przycisków
Theme.White = hex("#FFFFFF")
Theme.Dark = hex("#2A1638") -- ciemny tekst na jasnym tle
Theme.Muted = hex("#6B5A85") -- tekst pomocniczy
Theme.Good = "#179443" -- nowa, lepsza wartość (w tekście RichText)
Theme.GoldText = hex("#F5A800")
Theme.BadgeRed = hex("#FF3B5C")
Theme.TestYellow = hex("#FFE36B")

-- Gradienty z góry na dół (jasny → ciemny).
Theme.Gradients = {
	Green = { hex("#A4F78F"), hex("#2DB84C") },
	Pink = { hex("#FFA3D8"), hex("#E0338A") },
	Yellow = { hex("#FFE97A"), hex("#FFAE1A") },
	Red = { hex("#FF8A9C"), hex("#E0233F") },
	Gray = { hex("#D6D1E2"), hex("#A9A2BC") },
	Cyan = { hex("#8FF0FF"), hex("#22A8E6") },
	Gold = { hex("#FFF6B3"), hex("#FFB300") },
	LP = { hex("#FFB3E0"), hex("#FF3D8B") },
	Aura = { hex("#F3C9FF"), hex("#9B4DFF") },
	Panel = { hex("#FFFFFF"), hex("#F3ECFF") },
	CardPink = { hex("#FFF4FA"), hex("#FFD3EA") },
	CardAqua = { hex("#F0FFFC"), hex("#C9F6EF") },
	BagFull = { hex("#FF7A8E"), hex("#FF3D5E") },
}

-- Pasek Bag: zachód słońca w Miami, od lewej do prawej.
Theme.BagFill = { hex("#FF8FD0"), hex("#FF5E9C"), hex("#FF8A4C") }

-- Skala: 1 na ekranie 1280×720, mniej na telefonie, więcej na dużym monitorze.
Theme.BaseSize = Vector2.new(1280, 720)
Theme.MinScale = 0.7
Theme.MaxScale = 1.5

return Theme
