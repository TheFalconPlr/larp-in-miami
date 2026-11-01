-- Larp in Miami — start serwera. Uruchamia systemy gry w ustalonej kolejności.
-- Etap 2: zapis danych, klik z limitem, Bag, Sell, Click Multiplier i Bag za L$, tryb testowy.
-- Etap 3: strefy (bramki za L$, mnożnik LP strefy, tymczasowe strefy, gdy nie ma ich na mapie).

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
AdminService.start()
DataService.start()

print("[Larp in Miami] Etap 3 gotowy: klik, Bag, Sell, ulepszenia, strefy za L$ i tryb testowy.")
