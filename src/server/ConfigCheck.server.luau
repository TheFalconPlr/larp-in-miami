-- Testy: uruchamiają się tylko w Studio (Play). Sprawdzają liczby z arkusza (ConfigSpec), zasady
-- pętli (LoopSpec), ubrania (ClothesSpec), treść wywiadu (InterviewSpec) oraz Rebirth i Aurę
-- (RebirthSpec), zakupy za Robuxy (ShopSpec) i nagrody (RewardsSpec). Wynik w oknie Output:
-- „ConfigCheck: OK”, „LoopCheck: OK”, „ClothesCheck: OK”, „InterviewCheck: OK”, „RebirthCheck: OK”,
-- „ShopCheck: OK” i „RewardsCheck: OK” albo lista błędów.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

if not RunService:IsStudio() then
	return
end

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared.Config.Economy)
local Formulas = require(Shared.Formulas)
local Format = require(Shared.Format)
local configSpec = require(Shared.Tests.ConfigSpec)
local loopSpec = require(Shared.Tests.LoopSpec)
local clothesSpec = require(Shared.Tests.ClothesSpec)
local interviewSpec = require(Shared.Tests.InterviewSpec)
local rebirthSpec = require(Shared.Tests.RebirthSpec)
local shopSpec = require(Shared.Tests.ShopSpec)
local rewardsSpec = require(Shared.Tests.RewardsSpec)

local function report(name, what, passed, failed, messages)
	if failed == 0 then
		print(string.format("%s: OK (%d testów %s)", name, passed, what))
	else
		for _, m in ipairs(messages) do
			warn(m)
		end
		warn(string.format("%s: %d błędów, %d OK", name, failed, passed))
	end
end

report("ConfigCheck", "zgodnych z arkuszem", configSpec(Economy, Formulas, Format))
report("LoopCheck", "pętli: klik, Bag, Sell, ulepszenia, strefy, aktywności, pety", loopSpec())
report("ClothesCheck", "ubrań: boxy, sloty, warstwa LP, sprzedaż, łączenie", clothesSpec())
report("InterviewCheck", "wywiadu: pytania, odpowiedzi, losowanie", interviewSpec())
report("RebirthCheck", "Rebirth i Aury: reset, poziomy, pasek, sklep, poświata", rebirthSpec())
report("ShopCheck", "zakupów za Robuxy: paragony, boosty, Starter Pack, premium jajka", shopSpec())
report("RewardsCheck", "nagród: kody, darmowe jajka i boxy, bonus za grupę i znajomych", rewardsSpec())
