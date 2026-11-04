-- Punkt zaczepienia napisów nad stoiskami (jajka i boxy). Napisy (BillboardGui) przesuwamy przez
-- StudsOffsetWorldSpace, który liczy się w układzie części, do której są przypięte. Przy obróconej
-- części (np. cokół to walec położony na boku) napisy uciekały w bok, pod stoisko. Dlatego każde
-- stoisko dostaje u gracza niewidzialną, prostą część w środku swojego obrysu.

local Workspace = game:GetService("Workspace")

local StandAnchor = {}

local folder = nil
local anchors = {} -- [stoisko] = część

local function container()
	if folder == nil or folder.Parent == nil then
		folder = Instance.new("Folder")
		folder.Name = "LarpStandAnchors"
		folder.Parent = Workspace
	end
	return folder
end

-- Wysokość obróconego prostopadłościanu w świecie (połowa): rzut jego krawędzi na oś Y.
local function halfHeight(cframe, size)
	local _, _, _, _, _, _, r10, r11, r12 = cframe:GetComponents()
	return 0.5 * (math.abs(r10) * size.X + math.abs(r11) * size.Y + math.abs(r12) * size.Z)
end

-- Obrys stoiska: środek (Vector3) i połowa wysokości albo nil, gdy nie ma jeszcze żadnej części
-- (przy StreamingEnabled części dochodzą później).
local function bounds(stand)
	if stand:IsA("BasePart") then
		return stand.Position, halfHeight(stand.CFrame, stand.Size)
	end
	local any = false
	for _, d in ipairs(stand:GetDescendants()) do
		if d:IsA("BasePart") then
			any = true
			break
		end
	end
	if not any then
		return nil
	end
	local cframe, size = stand:GetBoundingBox()
	return cframe.Position, halfHeight(cframe, size)
end

-- Zwraca część do przypięcia napisów oraz górę i dół stoiska względem jej środka (studs)
-- albo nil, 0, 0. Część stoi prosto, więc przesunięcia w górę działają jak w świecie.
function StandAnchor.get(stand)
	local center, half = bounds(stand)
	if center == nil then
		return nil, 0, 0
	end
	local anchor = anchors[stand]
	if anchor == nil or anchor.Parent == nil then
		anchor = Instance.new("Part")
		anchor.Name = "Anchor"
		anchor.Anchored = true
		anchor.CanCollide = false
		anchor.CanTouch = false
		anchor.CanQuery = false
		anchor.CastShadow = false
		anchor.Transparency = 1
		anchor.Size = Vector3.new(0.2, 0.2, 0.2)
		anchor.Parent = container()
		anchors[stand] = anchor
	end
	anchor.CFrame = CFrame.new(center)
	return anchor, half, -half
end

function StandAnchor.forget(stand)
	local anchor = anchors[stand]
	if anchor ~= nil then
		anchor:Destroy()
		anchors[stand] = nil
	end
end

return StandAnchor
