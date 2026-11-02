-- Ukrywanie części tylko u tego gracza (inni dalej je widzą): bramki kupionych stref, auta z innych
-- tierów, inni gracze w czasie aktywności. Część robi się przezroczysta (LocalTransparencyModifier),
-- a jej napisy, naklejki, światła i efekty znikają razem z nią. Opcjonalnie traci też kolizje.

local TweenService = game:GetService("TweenService")

local LocalHide = {}

local FADE = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local savedCollision = setmetatable({}, { __mode = "k" }) -- [część] = kolizje sprzed ukrycia
local savedEnabled = setmetatable({}, { __mode = "k" }) -- [efekt] = Enabled sprzed ukrycia
local hiddenState = setmetatable({}, { __mode = "k" }) -- [część] = true, gdy ukryta

local function setDecorations(part, visible)
	for _, d in ipairs(part:GetDescendants()) do
		if d:IsA("Decal") then
			if visible then
				d.LocalTransparencyModifier = 0
			else
				d.LocalTransparencyModifier = 1
			end
		elseif d:IsA("LayerCollector") or d:IsA("ParticleEmitter") or d:IsA("Beam") or d:IsA("Trail") or d:IsA("Light") then
			if savedEnabled[d] == nil then
				savedEnabled[d] = d.Enabled
			end
			d.Enabled = visible and savedEnabled[d] or false
		end
	end
end

-- opts: animate (powolne znikanie), collide (false = ukryta część zostaje twarda; domyślnie traci kolizje)
function LocalHide.set(part, hidden, opts)
	opts = opts or {}
	if hiddenState[part] == hidden then
		return
	end
	hiddenState[part] = hidden
	if opts.collide ~= false then
		if savedCollision[part] == nil then
			savedCollision[part] = { part.CanCollide, part.CanTouch, part.CanQuery }
		end
		local s = savedCollision[part]
		if hidden then
			part.CanCollide = false
			part.CanTouch = false
			part.CanQuery = false
		else
			part.CanCollide = s[1]
			part.CanTouch = s[2]
			part.CanQuery = s[3]
		end
	end
	local target = 0
	if hidden then
		target = 1
	end
	local faded = false
	if opts.animate then
		faded = pcall(function()
			TweenService:Create(part, FADE, { LocalTransparencyModifier = target }):Play()
		end)
	end
	if not faded then
		part.LocalTransparencyModifier = target
	end
	setDecorations(part, not hidden)
end

-- Cały model, folder albo część (z wszystkimi częściami w środku).
function LocalHide.setAll(inst, hidden, opts)
	if inst:IsA("BasePart") then
		LocalHide.set(inst, hidden, opts)
	end
	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("BasePart") then
			LocalHide.set(d, hidden, opts)
		end
	end
end

return LocalHide
