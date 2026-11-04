-- Larp in Miami — start serwera. Uruchamia systemy gry w ustalonej kolejności.
-- Etap 2: zapis danych, klik z limitem, Bag, Sell, Click Multiplier i Bag za L$, tryb testowy.
-- Etap 3: strefy (bramki za L$, mnożnik LP strefy, tymczasowe strefy, gdy nie ma ich na mapie).
-- Etap 4: aktywności, na razie sesja zdjęciowa z autem w Luxury Cars (tiery aut za L$).
-- Etap 5: jajka i pety (stoiska w strefach, otwieranie za L$, ekwipunek, bonus petów do L$ przy Sell).
-- Etap 6: aktywności w strefach 3–5 (wywiad z losową oceną, impreza na jachcie, lot odrzutowcem).
-- Etap 7: sprzedaż i łączenie petów, indeks, sekrety z komunikatem na wszystkich serwerach.
-- Etap 8: ubrania (mystery boxy w Mall, 7 kategorii, bonus do LP, ubrania na awatarze).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared.Config.Economy)
local Format = require(Shared.Format)
local Net = require(Shared.Net)

local Services = script.Parent.Services
local DataService = require(Services.DataService)
local GamepassService = require(Services.GamepassService)
local ZoneService = require(Services.ZoneService)
local LoopService = require(Services.LoopService)
local ActivityService = require(Services.ActivityService)
local PetService = require(Services.PetService)
local ClothesService = require(Services.ClothesService)
local AdminService = require(Services.AdminService)

print(string.format(
	"[Larp in Miami] Serwer działa. Ekonomia %s. Strefa 5 kosztuje %s L$, Rebirth 10 kosztuje %s L$.",
	Economy.Version,
	Format.number(Economy.Zones[5].Cost),
	Format.number(Economy.Rebirth.Fees[10])
))

-- Najpierw zdarzenia sieciowe i systemy, które czekają na dane, a zapis danych na końcu:
-- wtedy każdy system dostaje informację o wczytaniu zapisu, także dla graczy, którzy już są w grze.
Net.setup()
GamepassService.start()
ZoneService.start()
LoopService.start()
ActivityService.start()
PetService.start()
ClothesService.start()
AdminService.start()
DataService.start()

print("[Larp in Miami] Etap 8 gotowy: klik, Bag, Sell, ulepszenia, strefy, aktywności, pety (łączenie, indeks, sekrety), ubrania, tryb testowy.")
