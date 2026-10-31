-- Larp in Miami — start serwera.
-- Etap 1: tylko potwierdza, że kod z repo dotarł do gry. Systemy (zapis danych, Bag, Sell,
-- Click Multiplier) dochodzą w Etapie 2.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared.Config.Economy)
local Format = require(Shared.Format)

print(string.format(
	"[Larp in Miami] Serwer działa. Ekonomia %s. Strefa 5 kosztuje %s L$, Rebirth 10 kosztuje %s L$.",
	Economy.Version,
	Format.number(Economy.Zones[5].Cost),
	Format.number(Economy.Rebirth.Fees[10])
))
