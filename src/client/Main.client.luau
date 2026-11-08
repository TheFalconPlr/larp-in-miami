-- Larp in Miami — start klienta (gracza): HUD, klikanie, strefy, aktywności, pety, jajka, ubrania
-- i mystery boxy, sklep za Robuxy, komunikaty o sekretach, Rebirth, sklep Aury, tytuły nad głową,
-- kody i bonus za grupę i znajomych (w sklepie), przycisk INVITE w pasku Robloxa, nagroda dzienna
-- i tryb testowy.
-- Najpierw moduły rejestrują, czego słuchają, a na końcu State podłącza zdarzenia z serwera.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared.Config.Economy)

local State = require(script.Parent.State)
local Hud = require(script.Parent.Hud)
local ClickInput = require(script.Parent.ClickInput)
local Admin = require(script.Parent.Admin)
local Zones = require(script.Parent.Zones)
local Activities = require(script.Parent.Activities)
local Pets = require(script.Parent.Pets)
local Eggs = require(script.Parent.Eggs)
local Wardrobe = require(script.Parent.Wardrobe)
local Boxes = require(script.Parent.Boxes)
local Shop = require(script.Parent.Shop)
local SecretBanner = require(script.Parent.SecretBanner)
local RebirthUi = require(script.Parent.RebirthUi)
local AuraShop = require(script.Parent.AuraShop)
local Codes = require(script.Parent.Codes)
local Daily = require(script.Parent.Daily)
local Topbar = require(script.Parent.Topbar)
local Nametags = require(script.Parent.Nametags)
local Sounds = require(script.Parent.Ui.Sounds)

Sounds.preload()
local hud = Hud.start()
ClickInput.start(hud)
Zones.start(hud)
Activities.start(hud)
Pets.start(hud)
Wardrobe.start(hud)
Eggs.start(hud)
Boxes.start(hud)
Shop.start(hud)
SecretBanner.start(hud)
RebirthUi.start(hud)
AuraShop.start(hud)
Codes.start(hud)
Daily.start(hud)
Topbar.start()
Nametags.start(hud)
Admin.start()
State.start()

print(string.format("[Larp in Miami] Klient gotowy: %s, ekonomia %s", Players.LocalPlayer.Name, Economy.Version))
