-- Stan gracza po stronie klienta: ostatnia kopia od serwera (Sync) i komunikaty (Notify).
-- Moduły rejestrują się przez onChange/onNotify, a start() podłącza zdarzenia z serwera.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("Shared").Net)

local State = {
	view = nil, -- ostatni stan od serwera (pola jak w Shared/Logic/Loop.view)
	busy = false, -- true w czasie aktywności (np. sesji zdjęciowej): kliknięcia i okna stref nie działają
}

local changeListeners = {}
local notifyListeners = {}

-- fn(view, oldView) po każdej zmianie stanu.
function State.onChange(fn)
	table.insert(changeListeners, fn)
	if State.view ~= nil then
		task.spawn(fn, State.view, nil)
	end
end

-- fn(payload) po każdym komunikacie z serwera, np. { Kind = "Sold", LP = 100, Cash = 100 }.
function State.onNotify(fn)
	table.insert(notifyListeners, fn)
end

function State.start()
	Net.event("Sync").OnClientEvent:Connect(function(view)
		local old = State.view
		State.view = view
		for _, fn in ipairs(changeListeners) do
			task.spawn(fn, view, old)
		end
	end)
	Net.event("Notify").OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" then
			return
		end
		for _, fn in ipairs(notifyListeners) do
			task.spawn(fn, payload)
		end
	end)
end

return State
