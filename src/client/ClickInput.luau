-- Klikanie: kliknięcie myszą albo krótkie dotknięcie ekranu (nie w przycisk) wysyła klik do serwera.
-- Przeciągnięcie palcem obraca kamerę, więc się nie liczy. Klient ma ten sam limit co serwer,
-- żeby nie pokazywać kliknięć, których serwer nie przyjmie.

local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared.Config.Economy)
local Settings = require(Shared.Config.Settings)
local RateLimiter = require(Shared.Logic.RateLimiter)
local Net = require(Shared.Net)
local State = require(script.Parent.State)

local ClickInput = {}

local TAP_MAX_SECONDS = 0.35
local TAP_MAX_MOVE = 14

function ClickInput.start(hud)
	local clickEvent = Net.event("Click")
	local limiter = RateLimiter.new(Settings.Click.MaxPerSecond, Settings.Click.Burst)
	local touches = {}

	-- Auto-Click zużywa część limitu serwera, więc ręcznych kliknięć pokazujemy odpowiednio mniej.
	State.onChange(function(view)
		local rate = Settings.Click.MaxPerSecond
		local passes = view.Passes or {}
		if passes.AutoClick and view.Settings and view.Settings.AutoClick then
			rate = rate - Economy.Robux.Gamepasses.AutoClick.ClicksPerSecond
		end
		limiter.rate = math.max(1, rate)
	end)

	-- Kliknięcia zbieramy i wysyłamy paczką co Settings.Click.BatchInterval sekund.
	local pending = 0
	local sinceFlush = 0
	RunService.Heartbeat:Connect(function(dt)
		sinceFlush = sinceFlush + dt
		if pending > 0 and sinceFlush >= Settings.Click.BatchInterval then
			local count = math.min(pending, Settings.Click.MaxBatch)
			pending = pending - count
			sinceFlush = 0
			clickEvent:FireServer(count)
		end
	end)

	local function click(screenPosition)
		local view = State.view
		if view == nil or State.busy then
			return
		end
		if limiter:take(os.clock(), 1) < 1 then
			return
		end
		pending = pending + 1
		-- napis i dźwięk kliknięcia (przy pełnym Bag razem z napisem „BAG FULL”) robi HUD
		hud.clickFeedback(screenPosition, view)
	end

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			click(Vector2.new(input.Position.X, input.Position.Y))
		elseif input.UserInputType == Enum.UserInputType.Touch then
			touches[input] = { position = input.Position, time = os.clock() }
		end
	end)

	UserInputService.InputEnded:Connect(function(input, processed)
		if input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		local start = touches[input]
		touches[input] = nil
		if start == nil or processed then
			return
		end
		local quick = os.clock() - start.time <= TAP_MAX_SECONDS
		local still = (input.Position - start.position).Magnitude <= TAP_MAX_MOVE
		if quick and still then
			click(Vector2.new(input.Position.X, input.Position.Y))
		end
	end)
end

return ClickInput
