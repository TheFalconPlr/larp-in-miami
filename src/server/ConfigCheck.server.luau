-- Testy: uruchamiają się tylko w Studio (Play). Sprawdzają liczby z arkusza (ConfigSpec), zasady
-- pętli (LoopSpec) i treść wywiadu (InterviewSpec). Wynik w oknie Output: „ConfigCheck: OK”,
-- „LoopCheck: OK” i „InterviewCheck: OK” albo lista błędów.

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
local interviewSpec = require(Shared.Tests.InterviewSpec)

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
report("InterviewCheck", "wywiadu: pytania, odpowiedzi, losowanie", interviewSpec())
