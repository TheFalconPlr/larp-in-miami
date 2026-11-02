-- Ustawienia gry, których nie ma w arkuszu ekonomii. Ten plik edytujemy ręcznie
-- (w przeciwieństwie do Economy.luau, który jest generowany).

local Settings = {
	Data = {
		-- Nazwa DataStore. Zmiana nazwy = wszyscy gracze zaczynają od zera.
		StoreName = "PlayerData",
		KeyPrefix = "Player_",
		-- true: testy w Studio zapisują się w osobnym, tymczasowym magazynie (postęp znika po Stop).
		UseMockInStudio = false,
	},
	Click = {
		-- Limit serwera: najwyżej tyle kliknięć na sekundę (ręczne i Auto-Click razem).
		-- 10/s to mniej więcej szybki człowiek, więc autoclicker nie daje dużej przewagi.
		MaxPerSecond = 10,
		-- Ile kliknięć może przyjść naraz, np. po chwilowym lagu.
		Burst = 10,
		-- Klient wysyła kliknięcia paczkami co tyle sekund (mniej zdarzeń w sieci).
		BatchInterval = 0.1,
		-- Najwięcej kliknięć w jednej paczce.
		MaxBatch = 10,
	},
	Sell = {
		-- Pole Sell to część (Part) z tym tagiem albo o tej nazwie. Bez niej serwer stawia tymczasowe pole.
		PadTag = "SellPad",
		-- Odstęp między teleportami na Sell (s).
		TeleportCooldown = 2,
		-- Odstęp między sprzedażami po wejściu na pole (s).
		TouchCooldown = 0.5,
	},
	-- Jak często serwer wysyła graczowi jego stan (s).
	SyncInterval = 0.1,
	Ui = {
		-- Arkusz ikon (assets/icons/larp-icons.png) wgrany do Roblox, np. "rbxassetid://1234567890".
		-- Puste = ikony bez własnego ID poniżej są jako emoji.
		IconSheet = "",
		-- Własne ikony z Toolboxa: ID Decala albo obrazka (liczba) albo gotowe "rbxassetid://…".
		-- Ikona z tej listy ma pierwszeństwo przed arkuszem. Nazwy jak w src/client/Ui/Icons.luau.
		Icons = {
			Bag = 15507676003,
			Click = 17293879645,
			Upgrades = 108527921987826,
			Cash = 15040641396, -- raczej tymczasowa
			Sell = 131296908597094, -- raczej tymczasowa
		},
		-- Wzór w tle okien (ikony „inwestowania”). Pusty = rysowany z kształtów; ID obrazka = kafelek z obrazka.
		Pattern = "",
	},
	-- Dźwięki (ID z Toolboxa). Volume: 0.5 = normalnie, 1 = głośno (cichy plik może mieć więcej, do 10).
	-- MinGap = najmniejszy odstęp między odtworzeniami (s).
	Sounds = {
		Button = { Id = 100809160609628, Volume = 0.5, MinGap = 0.05 }, -- domyślny dźwięk przycisków
		-- klikanie na LP (cichy dźwięk „hover”, dlatego głośność 1). Rise: klikanie pod rząd podnosi
		-- dźwięk o Step półtonów co klik, najwyżej o Max półtonów (12 = oktawa); po Reset sekundach
		-- przerwy wraca do zwykłej wysokości. Bez Rise dźwięk ma tylko lekko losową wysokość.
		Click = { Id = 139719503904449, Volume = 1, MinGap = 0.06, Rise = { Step = 1, Max = 12, Reset = 0.8 } },
		Sell = { Id = 111773238101465, Volume = 0.6, MinGap = 0.15 }, -- sprzedaż
		BagFull = { Id = 139063727738556, Volume = 0.6, MinGap = 1 }, -- Bag właśnie się zapełnił
		BagFullClick = { Id = 88442833509532, Volume = 0.6, MinGap = 0.1 }, -- klik przy pełnym Bag (razem z BAG FULL)
		NotEnough = { Id = 87519554692663, Volume = 0.6, MinGap = 0.15 }, -- brak L$ na zakup
		-- odblokowanie strefy (na razie ten sam dźwięk co sprzedaż; podmień, gdy znajdziesz lepszy)
		Unlock = { Id = 111773238101465, Volume = 0.8, MinGap = 0.5 },
		-- koniec aktywności: oklaski tłumu. Length = gra najwyżej tyle sekund, a przez ostatnie
		-- FadeOut sekund powoli cichnie (cały plik trwa ok. 7 s).
		Reward = { Id = 96549311151424, Volume = 0.7, MinGap = 0.3, Length = 3, FadeOut = 2 },
		Photo = { Id = 135432517383409, Volume = 0.6, MinGap = 0.2 }, -- migawka aparatu przy fleszu
		-- nowy pet z jajka (na razie ten sam dźwięk co sprzedaż; podmień, gdy znajdziesz lepszy).
		-- Przy Legendary, Mythic i Secret gra Reward (oklaski).
		Hatch = { Id = 111773238101465, Volume = 0.8, MinGap = 0.3 },
	},
	Admin = {
		-- Komendy testowe (/cmds) w Studio.
		AllowInStudio = true,
		-- W opublikowanej grze: właściciel grupy i osoby z listy UserIds. Przed premierą ustaw false.
		AllowInLive = true,
		UserIds = {},
	},
}

return Settings
