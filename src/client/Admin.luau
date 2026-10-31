-- Tryb testowy po stronie klienta: tworzy komendy czatu (/cash, /pass…) i pokazuje odpowiedzi
-- serwera jako wiadomości systemowe na czacie. Uprawnienia sprawdza serwer.

local TextChatService = game:GetService("TextChatService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("Shared").Net)
local State = require(script.Parent.State)

local Admin = {}

local created = false

local function systemMessage(text)
	for line in string.gmatch(text, "[^\n]+") do
		local ok = pcall(function()
			local channels = TextChatService:FindFirstChild("TextChannels")
			local system = channels and channels:FindFirstChild("RBXSystem")
			if system == nil then
				error("brak kanału RBXSystem")
			end
			system:DisplaySystemMessage("[TEST] " .. line)
		end)
		if not ok then
			print("[TEST] " .. line)
		end
	end
end

local function createCommands(names)
	if created or type(names) ~= "table" then
		return
	end
	created = true
	local adminEvent = Net.event("Admin")
	for _, name in ipairs(names) do
		local cmd = Instance.new("TextChatCommand")
		cmd.Name = "LarpTest_" .. name
		cmd.PrimaryAlias = "/" .. name
		cmd.Triggered:Connect(function(_, text)
			adminEvent:FireServer(text)
		end)
		cmd.Parent = TextChatService
	end
end

function Admin.start()
	State.onNotify(function(payload)
		if payload.Kind == "AdminCommands" then
			createCommands(payload.Commands)
			systemMessage("Tryb testowy włączony. Wpisz /cmds, żeby zobaczyć komendy.")
		elseif payload.Kind == "Admin" and type(payload.Text) == "string" then
			systemMessage(payload.Text)
		end
	end)
end

return Admin
