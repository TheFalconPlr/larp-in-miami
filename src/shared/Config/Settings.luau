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
		MaxPerSecond = 50,
		-- Ile kliknięć może przyjść naraz, np. po chwilowym lagu.
		Burst = 50,
		-- Klient wysyła kliknięcia paczkami co tyle sekund (mniej zdarzeń w sieci).
		BatchInterval = 0.1,
		-- Najwięcej kliknięć w jednej paczce.
		MaxBatch = 50,
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
		-- odblokowanie strefy (na razie ten sam dźwięk co sprzedaż; podmień, gdy znajdziesz lepszy)
		Unlock = { Id = 111773238101465, Volume = 0.8, MinGap = 0.5 },
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
