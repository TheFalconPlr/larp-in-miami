-- Test konfiguracji: uruchamia się tylko w Studio (Play) i sprawdza liczby z arkusza.
-- Wynik w oknie Output: „ConfigCheck: OK” albo lista błędów.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

if not RunService:IsStudio() then
	return
end

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared.Config.Economy)
local Formulas = require(Shared.Formulas)
local Format = require(Shared.Format)
local spec = require(Shared.Tests.ConfigSpec)

local passed, failed, messages = spec(Economy, Formulas, Format)

if failed == 0 then
	print(string.format("ConfigCheck: OK (%d testów zgodnych z arkuszem)", passed))
else
	for _, m in ipairs(messages) do
		warn(m)
	end
	warn(string.format("ConfigCheck: %d błędów, %d OK", failed, passed))
end
