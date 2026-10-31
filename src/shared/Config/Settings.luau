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
		MaxPerSecond = 100,
		-- Ile kliknięć może przyjść naraz, np. po chwilowym lagu.
		Burst = 100,
		-- Klient wysyła kliknięcia paczkami co tyle sekund (mniej zdarzeń w sieci).
		BatchInterval = 0.1,
		-- Najwięcej kliknięć w jednej paczce.
		MaxBatch = 100,
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
	Admin = {
		-- Komendy testowe (/cmds) w Studio.
		AllowInStudio = true,
		-- W opublikowanej grze: właściciel grupy i osoby z listy UserIds. Przed premierą ustaw false.
		AllowInLive = true,
		UserIds = {},
	},
}

return Settings
