-- Larp in Miami — start klienta (gracza): HUD, klikanie i tryb testowy.
-- Najpierw moduły rejestrują, czego słuchają, a na końcu State podłącza zdarzenia z serwera.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared.Config.Economy)

local State = require(script.Parent.State)
local Hud = require(script.Parent.Hud)
local ClickInput = require(script.Parent.ClickInput)
local Admin = require(script.Parent.Admin)
local Sounds = require(script.Parent.Ui.Sounds)

Sounds.preload()
local hud = Hud.start()
ClickInput.start(hud)
Admin.start()
State.start()

print(string.format("[Larp in Miami] Klient gotowy: %s, ekonomia %s", Players.LocalPlayer.Name, Economy.Version))
