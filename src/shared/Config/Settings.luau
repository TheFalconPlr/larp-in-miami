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
			Cash = 17368058560,
			Sell = 131296908597094, -- raczej tymczasowa
			Pets = 16697439145,
			SellCash = 120428722694490, -- banknoty lecące z paska Bag do licznika L$ przy sprzedaży
		},
		-- Wzór w tle okien (ikony „inwestowania”). Pusty = rysowany z kształtów; ID obrazka = kafelek z obrazka.
		Pattern = "",
	},
	-- Dźwięki (ID z Toolboxa). Volume: 0.5 = normalnie, 1 = głośno (cichy plik może mieć więcej, do 10).
	-- MinGap = najmniejszy odstęp między odtworzeniami (s). Length = gra najwyżej tyle sekund, a przez
	-- ostatnie FadeOut sekund powoli cichnie. Start = od której sekundy pliku zacząć (pomija ciszę na początku).
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
		-- koniec aktywności i rzadki pet: oklaski tłumu (cały plik trwa ok. 7 s, gra 4,5 s i cichnie przez 2,5 s)
		Reward = { Id = 96549311151424, Volume = 0.7, MinGap = 0.3, Length = 4.5, FadeOut = 2.5 },
		Photo = { Id = 135432517383409, Volume = 0.6, MinGap = 0.2 }, -- migawka aparatu przy fleszu
		-- nowy pet z jajka (przy Legendary, Mythic i Secret dochodzą oklaski Reward)
		Hatch = { Id = 99608180022223, Volume = 0.7, MinGap = 0.3 },
		-- pojedyncze pęknięcie jajka: gra 3 razy, coraz wyżej, a przy rozbiciu dwa razy naraz (nisko i wysoko).
		-- Plik trwa 1,1 s, więc gra tylko początek, żeby pęknięcia się nie zlewały.
		Crack = { Id = 9113959343, Volume = 0.9, MinGap = 0.03, Length = 0.6, FadeOut = 0.25 },
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
