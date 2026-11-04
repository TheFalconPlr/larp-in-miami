-- Wywiad w studiu: wybór pytań do jednego programu i sprawdzanie treści z Config/Interview.
-- Czysta logika bez Roblox API (testuje ją InterviewSpec). Program prowadzi klient (InterviewShow).

local Interview = {}

-- Reakcje studia na odpowiedź (kamera i dźwięk są po stronie gracza, w InterviewShow).
Interview.Reacts = { "Boom", "Laugh", "Crickets", "Bruh" }

-- Najdłuższe napisy w znakach (emoji = 1 znak), żeby mieściły się w okienku, na przyciskach i w czacie.
Interview.Limits = { Ask = 46, Say = 22, Reply = 32, Comment = 30, Line = 46, User = 16 }

Interview.AnswerCount = 3 -- tyle odpowiedzi ma każde pytanie (tyle jest przycisków)
Interview.MinQuestions = 8 -- najmniej pytań w puli, żeby wywiady się nie powtarzały

-- Liczba znaków napisu w UTF-8 (emoji to 1 znak). Działa też w Lua 5.1, bez biblioteki utf8.
function Interview.length(text)
	local _, count = string.gsub(text, "[^\128-\191]", "")
	return count
end

-- Kopia listy w losowej kolejności (Fisher–Yates). random01() zwraca liczbę z [0, 1).
function Interview.shuffle(list, random01)
	local copy = {}
	for i, value in ipairs(list) do
		copy[i] = value
	end
	for i = #copy, 2, -1 do
		local j = math.min(i, math.floor(random01() * i) + 1)
		copy[i], copy[j] = copy[j], copy[i]
	end
	return copy
end

-- count różnych numerów pytań z 1 … total w losowej kolejności. Ostatnio zadane (recent: lista
-- numerów) są na końcu kolejki, więc wracają dopiero, gdy zabraknie nowych.
function Interview.pick(total, count, random01, recent)
	local isRecent = {}
	for _, number in ipairs(recent or {}) do
		isRecent[number] = true
	end
	local fresh, old = {}, {}
	for number = 1, total do
		if isRecent[number] then
			table.insert(old, number)
		else
			table.insert(fresh, number)
		end
	end
	local order = Interview.shuffle(fresh, random01)
	for _, number in ipairs(Interview.shuffle(old, random01)) do
		table.insert(order, number)
	end
	local result = {}
	for i = 1, math.min(count, #order) do
		result[i] = order[i]
	end
	return result
end

-- Problemy w treści wywiadu (pusta lista = wszystko dobrze): brakujące napisy, za długie napisy,
-- zła liczba odpowiedzi, nieznana reakcja, powtórzone pytanie.
function Interview.validate(content)
	local problems = {}
	local limits = Interview.Limits
	local reacts = {}
	for _, name in ipairs(Interview.Reacts) do
		reacts[name] = true
	end

	local function text(value, limit, where)
		if type(value) ~= "string" or value == "" then
			table.insert(problems, where .. ": brak napisu")
		elseif Interview.length(value) > limit then
			table.insert(problems, string.format("%s: za długi napis (%d > %d znaków): %s", where, Interview.length(value), limit, value))
		end
	end

	local function list(values, limit, where, minimum)
		if type(values) ~= "table" or #values < (minimum or 1) then
			table.insert(problems, where .. ": za mało pozycji")
			return
		end
		for i, value in ipairs(values) do
			text(value, limit, where .. " " .. i)
		end
	end

	if type(content) ~= "table" then
		return { "brak treści wywiadu" }
	end
	text(content.Host, limits.User, "Host")
	if type(content.Stall) ~= "string" then
		table.insert(problems, "Stall: brak napisu")
	end
	list(content.Intro, limits.Line, "Intro")
	list(content.Outro, limits.Line, "Outro")
	list(content.Users, limits.User, "Users", 5)
	if type(content.SignOff) ~= "table" or #content.SignOff < 1 then
		table.insert(problems, "SignOff: za mało pozycji")
	else
		for i, pair in ipairs(content.SignOff) do
			text(pair.Say, limits.Line, "SignOff " .. i)
			text(pair.Reply, limits.Reply, "SignOff " .. i .. " (prowadzący)")
		end
	end

	local comments = content.Comments
	if type(comments) ~= "table" then
		table.insert(problems, "Comments: brak komentarzy")
	else
		list(comments.Intro, limits.Comment, "Comments.Intro")
		list(comments.Thinking, limits.Comment, "Comments.Thinking")
		for _, name in ipairs(Interview.Reacts) do
			list(comments[name], limits.Comment, "Comments." .. name)
		end
		if type(comments.Grades) ~= "table" or #comments.Grades < 4 then
			table.insert(problems, "Comments.Grades: potrzebne 4 listy (Flop, Solid, Viral, Mega viral)")
		else
			for grade, values in ipairs(comments.Grades) do
				list(values, limits.Comment, "Comments.Grades " .. grade)
			end
		end
	end

	local questions = content.Questions
	if type(questions) ~= "table" or #questions < Interview.MinQuestions then
		table.insert(problems, string.format("Questions: za mało pytań (najmniej %d)", Interview.MinQuestions))
		return problems
	end
	local seen = {}
	for qi, question in ipairs(questions) do
		local where = "pytanie " .. qi
		text(question.Ask, limits.Ask, where)
		if type(question.Ask) == "string" then
			if seen[question.Ask] then
				table.insert(problems, where .. ": to samo pytanie jest drugi raz")
			end
			seen[question.Ask] = true
		end
		local answers = question.Answers
		if type(answers) ~= "table" or #answers ~= Interview.AnswerCount then
			table.insert(problems, string.format("%s: potrzebne %d odpowiedzi", where, Interview.AnswerCount))
		else
			for ai, answer in ipairs(answers) do
				local at = where .. ", odpowiedź " .. ai
				text(answer.Say, limits.Say, at)
				text(answer.Reply, limits.Reply, at .. " (prowadzący)")
				text(answer.Comment, limits.Comment, at .. " (komentarz)")
				if not reacts[answer.React] then
					table.insert(problems, at .. ": nieznana reakcja " .. tostring(answer.React))
				end
			end
		end
	end
	return problems
end

return Interview
