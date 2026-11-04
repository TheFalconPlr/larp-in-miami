-- Testy wywiadu: treść z Config/Interview (3 odpowiedzi na pytanie, długość napisów, reakcje)
-- i losowanie pytań (bez powtórek w jednym wywiadzie, ostatnio zadane na końcu kolejki).
-- Uruchamia je ConfigCheck w Studio i tools/test_luau.py poza Roblox.
-- Zwraca funkcję: passed, failed, messages.

local Shared = script.Parent.Parent
local Content = require(Shared.Config.Interview)
local Interview = require(Shared.Logic.Interview)

return function()
	local passed, failed, messages = 0, 0, {}

	local function check(cond, msg)
		if cond then
			passed = passed + 1
		else
			failed = failed + 1
			table.insert(messages, "InterviewSpec: " .. msg)
		end
	end

	-- stały ciąg „losowych” liczb (Park–Miller), żeby test zawsze wychodził tak samo
	local seed = 12345
	local function random01()
		seed = (seed * 16807) % 2147483647
		return seed / 2147483647
	end

	----------------------------------------------------------------- Treść
	local problems = Interview.validate(Content)
	for _, problem in ipairs(problems) do
		check(false, "treść: " .. problem)
	end
	check(#problems == 0, "treść wywiadu bez błędów")
	check(#Content.Questions >= 20, "co najmniej 20 pytań (żeby wywiady się nie nudziły)")
	local reactCount = {}
	for _, question in ipairs(Content.Questions) do
		for _, answer in ipairs(question.Answers) do
			reactCount[answer.React] = (reactCount[answer.React] or 0) + 1
		end
	end
	for _, name in ipairs(Interview.Reacts) do
		check((reactCount[name] or 0) >= 5, "reakcja " .. name .. " jest w co najmniej 5 odpowiedziach")
	end
	check(Interview.length("bro 💀") == 5 and Interview.length("") == 0, "długość liczy emoji jako 1 znak")
	check(#Interview.validate({}) > 0, "pusta treść ma błędy")

	----------------------------------------------------------------- Losowanie
	local distinct = true
	for _ = 1, 100 do
		local picked = Interview.pick(10, 4, random01, {})
		local seen = {}
		if #picked ~= 4 then
			distinct = false
		end
		for _, number in ipairs(picked) do
			if seen[number] or number < 1 or number > 10 then
				distinct = false
			end
			seen[number] = true
		end
	end
	check(distinct, "pick: 4 różne pytania z 10")

	local avoided = true
	for _ = 1, 100 do
		for _, number in ipairs(Interview.pick(10, 4, random01, { 1, 2, 3, 4, 5, 6 })) do
			if number <= 6 then
				avoided = false
			end
		end
	end
	check(avoided, "pick: ostatnio zadane nie wracają, gdy są nowe")

	local mixed = Interview.pick(5, 4, random01, { 1, 2, 3 })
	local firstTwoFresh = (mixed[1] == 4 or mixed[1] == 5) and (mixed[2] == 4 or mixed[2] == 5) and mixed[1] ~= mixed[2]
	check(#mixed == 4 and firstTwoFresh and mixed[3] <= 3 and mixed[4] <= 3, "pick: najpierw nowe, potem ostatnio zadane")
	check(#Interview.pick(3, 5, random01, {}) == 3, "pick: najwyżej tyle, ile jest pytań")

	local everyNumber = {}
	for _ = 1, 300 do
		everyNumber[Interview.pick(6, 1, random01, {})[1]] = true
	end
	local all = true
	for number = 1, 6 do
		all = all and everyNumber[number] == true
	end
	check(all, "pick: każde pytanie może wypaść")

	local list = { "a", "b", "c" }
	local shuffled = Interview.shuffle(list, random01)
	local count = {}
	for _, value in ipairs(shuffled) do
		count[value] = (count[value] or 0) + 1
	end
	check(#shuffled == 3 and count.a == 1 and count.b == 1 and count.c == 1, "shuffle: każdy element raz")
	check(list[1] == "a" and list[2] == "b" and list[3] == "c", "shuffle: nie zmienia oryginału")
	local firstPlaces = {}
	for _ = 1, 300 do
		firstPlaces[Interview.shuffle(list, random01)[1]] = true
	end
	check(firstPlaces.a and firstPlaces.b and firstPlaces.c, "shuffle: każda odpowiedź może być pierwsza")

	return passed, failed, messages
end
