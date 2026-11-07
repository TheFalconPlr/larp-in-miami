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
			Clothes = 14002284211, -- kafelek i okno CLOTHES
			Rebirth = 18367579979, -- okno Rebirth i napis nad portalem
			SellCash = 120428722694490, -- banknoty lecące z paska Bag do licznika L$ przy sprzedaży
			Shop = 98363337879339, -- „Shop Icon”: kafelek SHOP i tytuł okna sklepu
			Teleport = 17368164623, -- „Teleport Outline 256”: kafelek TELEPORT, okno teleportu
			Boost = 79228072544070, -- „2X Speed”: boosty 2x LP (sklep, komunikaty)
		},
		-- Grafiki sklepu za Robuxy (ID Decali z Toolboxa). Z nich ShopArt składa grafiki gamepassów:
		-- trzy jajka (Triple Open), jajko z błyskawicą (Fast Open), dwa łańcuchy, dwa zegarki itd.
		-- 0 albo brak = zamiast obrazka emoji.
		ShopArt = {
			TwoX = 79228072544070, -- „2X Speed”: gamepass i boosty 2x LP
			Egg = 17079629931, -- „Egg”: Triple Open, Fast Open, premium jajka w podziękowaniu
			Bolt = 3674944390, -- „Speed”: błyskawica bez napisu (Fast Open)
			Teleport = 17368164623, -- „Teleport Outline 256”
			Chain = 17582470364, -- „GOLD CHAIN $_$”: Double Chain
			Watch = 10198027043, -- „Battleship Diepio”: tarcza zegarka (Double Wrist, zegarek w Starter Packu)
			-- Obrót obrazka zegarka (stopnie, + w prawo), żeby szare kawałki były paskiem u góry i u dołu,
			-- i wielkość niebieskiej tarczy względem obrazka (na niej leży złota obręcz i wskazówki).
			WatchRotation = 45,
			WatchFace = 0.56,
			-- „Window Shine 2”: ukośne smugi światła (jak odbicie na szybie) przesuwane po kartach
			-- i przyciskach. ShineWidth = szerokość obrazka względem wysokości ramki (1 = kwadrat).
			Shine = 159602435,
			ShineWidth = 1,
		},
		-- Wzór w tle okien (ikony „inwestowania”). Pusty = rysowany z kształtów; ID obrazka = kafelek z obrazka.
		Pattern = "",
	},
	-- Dźwięki (ID z Toolboxa). Volume: 0.5 = normalnie, 1 = głośno (cichy plik może mieć więcej, do 10).
	-- MinGap = najmniejszy odstęp między odtworzeniami (s). Length = gra najwyżej tyle sekund, a przez
	-- ostatnie FadeOut sekund powoli cichnie. Start = od której sekundy pliku zacząć (pomija ciszę na początku).
	Sounds = {
		Button = { Id = 100809160609628, Volume = 0.5, MinGap = 0.05 }, -- domyślny dźwięk przycisków
		-- klikanie na LP (cichy dźwięk „hover”, dlatego głośność 2). Rise: klikanie pod rząd podnosi
		-- dźwięk o Step półtonów co klik, najwyżej o Max półtonów (12 = oktawa); po Reset sekundach
		-- przerwy wraca do zwykłej wysokości. Bez Rise dźwięk ma tylko lekko losową wysokość.
		Click = { Id = 139719503904449, Volume = 2, MinGap = 0.06, Rise = { Step = 1, Max = 12, Reset = 0.8 } },
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
		-- sprzedaż: „pop”, gdy banknot wyskakuje z paska Bag, i „tick”, gdy wpada do licznika L$
		-- (kolejne ticki coraz wyżej, jak przy zbieraniu monet)
		CashPop = { Id = 72264591133889, Volume = 0.4, MinGap = 0.03 },
		CashTick = { Id = 8646410774, Volume = 0.45, MinGap = 0.03, Rise = { Step = 1, Max = 10, Reset = 0.5 } },

		-- Dźwięki na dłużej (Sounds.start): Looped = gra w pętli do końca sesji, FadeIn = przez tyle
		-- sekund rośnie do pełnej głośności (od FadeFrom: 0 = od ciszy, 0.3 = od 30%), FadeOut = tyle
		-- trwa wyciszanie na końcu. Ids = kilka wersji jednego dźwięku (gra losowa).
		-- odrzutowiec: silnik przez cały lot (cichy plik, dlatego głośność 2.5); na pasie rozkręca się
		-- od 30% do pełnej głośności i trochę wyżej. Do tego muzyka w locie i „ding” w kabinie na starcie.
		JetEngine = { Id = 116765821564780, Volume = 2.5, Looped = true, FadeIn = 6, FadeFrom = 0.3, FadeOut = 1.5 },
		JetMusic = { Id = 9046476113, Volume = 0.4, Looped = true, FadeIn = 3, FadeOut = 2, Music = true },
		JetCabin = { Id = 76104215304832, Volume = 0.6, MinGap = 1 },
		-- jacht: muzyka przez całą imprezę, a na koniec trąbka z wybuchem konfetti (potem oklaski Reward)
		PartyMusic = { Id = 1838028467, Volume = 0.5, Looped = true, FadeIn = 2, FadeOut = 1, Music = true },
		PartyHorn = { Id = 118248543183940, Volume = 0.8, MinGap = 0.3 },

		-- Wywiad: muzyka talk show przez cały program (ściszana na chwilę przy reakcjach studia).
		InterviewMusic = { Id = 9048498225, Volume = 0.3, Looped = true, FadeIn = 1, FadeOut = 1.2, Music = true },
		AnswerPick = { Volume = 0.6, MinGap = 0.1 }, -- wybór odpowiedzi (bez ID gra zwykły Button)
		AnswerTick = { Id = 507267777, Volume = 0.5, Looped = true }, -- tykanie zegara, gdy wybierasz odpowiedź
		ReactBoom = { Id = 140367458608473, Volume = 0.7 }, -- „vine boom” przy zbliżeniu na prowadzącego
		ReactLaugh = { Ids = { 139341401874820, 79013083482469, 81245133419507 }, Volume = 0.6 }, -- śmiech (3 wersje)
		ReactCrickets = { Id = 116480627582005, Volume = 0.7 }, -- świerszcze przy niezręcznej ciszy
		ReactBruh = { Id = 140007222940724, Volume = 0.6 }, -- „bruh” (plik jest głośny)
		Comment = { Id = 140323850218372, Volume = 0.25, MinGap = 0.08 }, -- nowy komentarz w czacie
		ClipPosted = { Id = 137081214744553, Volume = 1.2 }, -- „whoosh”: klip idzie do sieci (cichy plik)
		InterviewFlop = { Id = 116298781032555, Volume = 0.7 }, -- ocena FLOP: smutna trąbka

		-- Pety (Etap 7): nieudane łączenie (ta sama smutna trąbka), sekret z jajka („vine boom” przy
		-- rozbiciu, potem oklaski Reward) i komunikat o sekrecie u wszystkich graczy (gong z kabiny).
		MergeFail = { Id = 116298781032555, Volume = 0.6, MinGap = 0.5 },
		SecretReveal = { Id = 140367458608473, Volume = 0.8, MinGap = 0.5 },
		SecretAnnounce = { Id = 76104215304832, Volume = 0.5, MinGap = 1 },

		-- Sklep za Robuxy: otwarcie okna (ShopOpenSfx razem z „whoosh” ShopOpen, ten sam plik co
		-- ClipPosted), „ka-ching” przy kliknięciu przycisku z ceną (zanim wyskoczy okno zakupu), zmiana
		-- zakładki, podziękowanie po zakupie gamepassa albo Starter Packa (trąbka z konfetti) i po
		-- mniejszym zakupie (boost, Sell Now).
		ShopOpen = { Id = 137081214744553, Volume = 1, MinGap = 0.3 },
		ShopOpenSfx = { Id = 139871344666404, Volume = 0.7, MinGap = 0.3 },
		ShopBuy = { Id = 88168334908542, Volume = 0.7, MinGap = 0.15 },
		ShopTab = { Id = 100809160609628, Volume = 0.35, MinGap = 0.05 },
		Purchase = { Id = 118248543183940, Volume = 0.7, MinGap = 0.5 },
		PurchaseSmall = { Id = 111773238101465, Volume = 0.6, MinGap = 0.3 },
		-- Muzyka sklepu: gra w pętli, dopóki okno SHOP jest otwarte (wchodzi przez FadeIn sekund,
		-- schodzi przez FadeOut). Po krótkiej przerwie gra dalej od tego samego miejsca, po dłuższej
		-- niż Restart sekund od początku. W tym czasie muzyka gry (Music niżej) cichnie.
		ShopMusic = { Id = 106495808773197, Volume = 0.45, Looped = true, FadeIn = 1.2, FadeOut = 0.9, Restart = 20 },
	},
	-- Muzyka gry: dźwięki z Music = true (wyżej) i każdy dźwięk włożony w Studio do SoundGroup o tej
	-- nazwie w SoundService (Group; gdy jej nie ma, gra tworzy ją u gracza). Na czas muzyki sklepu
	-- grupa cichnie do DuckVolume (0 = cisza) przez DuckTime sekund, a potem wraca przez RestoreTime.
	Music = {
		Group = "Music",
		DuckVolume = 0,
		DuckTime = 0.6,
		RestoreTime = 1.2,
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
