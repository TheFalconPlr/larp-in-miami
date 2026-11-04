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
	LP = { hex("#8CF8FF"), hex("#1E9BFF") }, -- nagrody w LP, np. z sesji zdjęciowej (neonowy błękit Miami)
	ClickPop = { hex("#FFFFFF"), hex("#E3E8F2") }, -- „+X” przy kursorze i „Larp” nad paskiem Bag (biały)
	Aura = { hex("#E2A6FF"), hex("#8A3CF5") },
	Panel = { hex("#FFFFFF"), hex("#EEF1F7") },
	CardPink = { hex("#FF73BC"), hex("#DB3189") },
	CardBlue = { hex("#55CBFF"), hex("#1E88E3") },
	BagFull = { hex("#E8243A"), hex("#A8102A") },
	Money = { hex("#7BF26A"), hex("#14A84A") }, -- zielony jak banknoty (kwoty w komunikatach)
}

-- Tytuły Rebirth (nad głową i w oknie Rebirth): gradient z góry na dół dla każdego poziomu.
-- Nazwy tytułów są w Economy.Rebirth.Titles (Broke … Certified Larper).
Theme.TitleColors = {
	[0] = { hex("#E2E2E8"), hex("#9A9AA8") }, -- Broke
	[1] = { hex("#FFFFFF"), hex("#C9DDFF") }, -- Wannabe
	[2] = { hex("#C8FF9E"), hex("#5CCB2E") }, -- Fake Rich
	[3] = { hex("#FFB3E2"), hex("#FF4FB8") }, -- Influencer
	[4] = { hex("#9EE8FF"), hex("#1FB2FF") }, -- Main Character
	[5] = { hex("#B6FFB0"), hex("#22B84A") }, -- Self-Made
	[6] = { hex("#A8C4FF"), hex("#3A6BFF") }, -- Trust Fund
	[7] = { hex("#E2BFFF"), hex("#9A4DFF") }, -- Old Money
	[8] = { hex("#9FFFF0"), hex("#12C9B0") }, -- Yacht Club
	[9] = { hex("#FFD29E"), hex("#FF8A1F") }, -- Jet Set
	[10] = { hex("#FFF07A"), hex("#FFA200") }, -- Certified Larper
}

-- Poświata wokół awatara na progach Aura Level (Economy.Aura.Glow): kolor iskier i światła.
-- Rainbow mieni się wszystkimi kolorami (Theme.Rainbow).
Theme.GlowColors = {
	White = hex("#FFFFFF"),
	Blue = hex("#4FA8FF"),
	Purple = hex("#B046FF"),
	Gold = hex("#FFC21A"),
	Red = hex("#FF3B3B"),
}
Theme.Rainbow = { hex("#FF3B3B"), hex("#FFA21A"), hex("#FFE14D"), hex("#4CE06A"), hex("#4FA8FF"), hex("#B046FF") }

-- Pasek Bag: czerwony, od lewej do prawej.
Theme.BagFill = { hex("#FF6B57"), hex("#F23B3B"), hex("#D91A33") }

-- Skala: 1 na ekranie 1280×720, mniej na telefonie, więcej na dużym monitorze.
Theme.BaseSize = Vector2.new(1280, 720)
Theme.MinScale = 0.7
Theme.MaxScale = 1.5

return Theme
