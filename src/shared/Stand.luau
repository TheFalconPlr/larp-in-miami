-- Gdzie postawić postać na znaczniku „Pose” (sesje aktywności). Używa tego serwer (ActivityService.pose)
-- i klient (na jachcie sam trzyma gracza na kołyszącym się pokładzie), więc obaj stawiają go tak samo.
--   • podłoga: pierwsza widoczna powierzchnia pod czubkiem znacznika (niewidoczne części, np. sam
--     znacznik, się nie liczą). Znacznik wystający nad pokład zostawiał gracza w powietrzu,
--   • wysokość: środek HumanoidRootPart nad podłogą według awatara (R15: HipHeight + pół HRP,
--     R6: nogi 2 studs + pół HRP), a nie zawsze 3 studs (niższy awatar wisiał nad pokładem).
-- Używa Roblox API (raycast), więc nie jest w Shared/Logic.

local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

local Stand = {}

local SEARCH_FROM = 2.5 -- szukamy podłogi od tylu studs nad czubkiem znacznika…
local SEARCH_DOWN = 4 -- …do tylu studs pod nim
local ACCEPT_ABOVE = 0.6 -- powierzchnia najwyżej tyle nad czubkiem znacznika (wyżej to np. daszek)
local INVISIBLE = 0.95 -- części tak przezroczyste się nie liczą

-- Wysokość środka HumanoidRootPart nad podłogą, gdy postać stoi.
function Stand.height(character)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if humanoid == nil or root == nil then
		return 3
	end
	if humanoid.RigType == Enum.HumanoidRigType.R15 then
		return humanoid.HipHeight + root.Size.Y / 2
	end
	return 2 + root.Size.Y / 2 -- R6: nogi mają 2 studs (HipHeight w R6 jest 0)
end

-- Punkt podłogi pod znacznikiem (Vector3). Bez widocznej podłogi blisko: czubek znacznika.
-- ignore: modele, których nie liczymy (na serwerze jachty z innych tierów stoją w tym samym miejscu,
-- a u gracza są niewidoczne i bez kolizji).
function Stand.floor(pose, ignore)
	local top = pose.Position + Vector3.new(0, pose.Size.Y / 2, 0)
	local exclude = {}
	for _, inst in ipairs(ignore or {}) do
		table.insert(exclude, inst)
	end
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character ~= nil then
			table.insert(exclude, player.Character)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.IgnoreWater = true
	local origin = top + Vector3.new(0, SEARCH_FROM, 0)
	local direction = Vector3.new(0, -(SEARCH_FROM + SEARCH_DOWN), 0)
	for _ = 1, 10 do
		params.FilterDescendantsInstances = exclude
		local hit = Workspace:Raycast(origin, direction, params)
		if hit == nil then
			return top
		end
		local part = hit.Instance
		local visible = not part:IsA("BasePart") or part.Transparency < INVISIBLE
		if visible and hit.Position.Y <= top.Y + ACCEPT_ABOVE then
			return hit.Position
		end
		table.insert(exclude, part)
	end
	return top
end

-- CFrame dla HumanoidRootPart: na podłodze pod znacznikiem, przodem tam, gdzie patrzy znacznik.
function Stand.at(pose, character, ignore)
	local ground = Stand.floor(pose, ignore)
	local look = pose.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 0.1 then
		flat = Vector3.new(0, 0, -1)
	end
	local position = ground + Vector3.new(0, Stand.height(character), 0)
	return CFrame.lookAt(position, position + flat.Unit)
end

return Stand
