-- Larp in Miami — start klienta (gracza).
-- Etap 1: tylko potwierdza, że skrypty klienta działają. HUD (LP, Bag, L$) dochodzi w Etapie 2.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared.Config.Economy)

print(string.format("[Larp in Miami] Klient gotowy: %s, ekonomia %s", Players.LocalPlayer.Name, Economy.Version))
