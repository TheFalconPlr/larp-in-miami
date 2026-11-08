-- Nagrody (Etap 11): kody, nagroda dzienna i zadania dzienne. Czysta logika na zapisie gracza
-- (bez Roblox API), więc działa na serwerze (RewardsService) i w testach (RewardsSpec).
--
-- Nagroda z Economy.Rewards to { Label, Items }. Label to opis z dokumentu projektu, a Items to lista
-- rzeczy, które gra naprawdę daje:
--   { Kind = "Boost", Boost = "LP"|"AutoSell", Minutes = 15 }   boost (sumuje się z kupionymi)
--   { Kind = "Egg", Egg = "A"|"B", Count = 3 }                    jajka z najwyższej odblokowanej strefy
--   { Kind = "Box", Box = "Best", Count = 2 }                     najlepszy odblokowany box (przed strefą 3 Street)
--   { Kind = "PremiumEgg", Count = 1 }                            premium jajko z najwyższej strefy
-- Jajka i boxy z nagród losują tak samo jak kupione za L$ (ze szczęściem z Aury), tylko nic nie
-- kosztują. Darmowe premium jajko nie jest płatnym losowaniem, więc dostaje je każdy tak samo.

local Economy = require(script.Parent.Parent.Config.Economy)
local Loop = require(script.Parent.Loop)
local Clothes = require(script.Parent.Clothes)
local Shop = require(script.Parent.Shop)
local Rebirth = require(script.Parent.Rebirth)

local Rewards = {}

Rewards.CodeMaxLength = 30 -- dłuższy tekst to na pewno nie kod
Rewards.Kinds = { Boost = true, Egg = true, Box = true, PremiumEgg = true }

----------------------------------------------------------------- Skąd jajko i który box
-- Najwyższa odblokowana strefa, w której jest jajko egg (A albo B).
function Rewards.eggZone(data, egg)
	local unlocked = math.min(data.ZonesUnlocked or 1, #Economy.Pets.Eggs)
	for zone = unlocked, 1, -1 do
		if Loop.eggInfo(zone, egg or "A") ~= nil then
			return zone
		end
	end
	return 1
end

-- Najlepszy odblokowany box (najwyższe RequiresZone, które gracz ma), a przed strefą z boxami
-- najtańszy (Street), żeby nagroda zawsze coś dawała.
function Rewards.bestBox(data)
	local unlocked = data.ZonesUnlocked or 1
	local best, bestZone, bestPrice = nil, -1, -1
	local cheapest, cheapestPrice = nil, math.huge
	for name in pairs(Economy.Clothes.Boxes) do
		local info = Clothes.boxInfo(name)
		if info ~= nil and info.RequiresZone ~= nil then
			if info.RequiresZone <= unlocked then
				if info.RequiresZone > bestZone or (info.RequiresZone == bestZone and info.Price > bestPrice) then
					best, bestZone, bestPrice = name, info.RequiresZone, info.Price
				end
			end
			if info.Price < cheapestPrice then
				cheapest, cheapestPrice = name, info.Price
			end
		end
	end
	return best or cheapest
end

----------------------------------------------------------------- Miejsce w ekwipunku
-- Ile petów i ubrań doda nagroda.
function Rewards.counts(items)
	local pets, clothes = 0, 0
	for _, item in ipairs(items or {}) do
		local count = item.Count or 1
		if item.Kind == "Egg" or item.Kind == "PremiumEgg" then
			pets = pets + count
		elseif item.Kind == "Box" then
			clothes = clothes + count
		end
	end
	return pets, clothes
end

-- Czy wszystko z nagrody się zmieści. limits = { pets = najwięcej petów, clothes = najwięcej ubrań }
-- (nil albo brak pola = bez limitu). Zwraca true albo false i powód: PetInventory, ClothInventory.
function Rewards.fits(data, items, limits)
	local pets, clothes = Rewards.counts(items)
	if limits ~= nil then
		if pets > 0 and limits.pets ~= nil and Loop.petCount(data) + pets > limits.pets then
			return false, "PetInventory"
		end
		if clothes > 0 and limits.clothes ~= nil and Clothes.count(data) + clothes > limits.clothes then
			return false, "ClothInventory"
		end
	end
	return true, nil
end

----------------------------------------------------------------- Przyznanie
-- Daje wszystko z listy items (miejsce sprawdza wcześniej Rewards.fits). random01 = funkcja losująca
-- liczbę z [0, 1). Zwraca, co gracz dostał:
--   Boosts = { { Boost, Minutes } }
--   Eggs   = { { Zone, Egg ("A", "B" albo "P" = premium), Pets = { { id, pet, new } } } }
--   Boxes  = { { Box, Items = { { id, item, worn } } } }
function Rewards.grant(data, ctx, items, random01)
	local result = { Boosts = {}, Eggs = {}, Boxes = {} }
	random01 = random01 or math.random
	for _, item in ipairs(items or {}) do
		local count = item.Count or 1
		if item.Kind == "Boost" then
			if Shop.addBoost(data, item.Boost, item.Minutes) > 0 then
				table.insert(result.Boosts, { Boost = item.Boost, Minutes = item.Minutes })
			end
		elseif item.Kind == "Egg" then
			local zone = Rewards.eggZone(data, item.Egg)
			local list = Loop.openEggs(data, ctx, zone, item.Egg, count, random01, nil, true)
			if list ~= nil and #list > 0 then
				table.insert(result.Eggs, { Zone = zone, Egg = item.Egg, Pets = list })
			end
		elseif item.Kind == "PremiumEgg" then
			local zone = Shop.premiumZone(data, nil)
			local list = Shop.openPremium(data, ctx, zone, count, random01)
			if #list > 0 then
				table.insert(result.Eggs, { Zone = zone, Egg = "P", Pets = list })
			end
		elseif item.Kind == "Box" then
			local box = item.Box
			if box == "Best" or Clothes.boxInfo(box) == nil then
				box = Rewards.bestBox(data)
			end
			local list = Clothes.openBoxes(data, ctx, box, count, random01, nil, nil, true)
			if list ~= nil and #list > 0 then
				table.insert(result.Boxes, { Box = box, Items = list })
			end
		end
	end
	return result
end

----------------------------------------------------------------- Kody
-- Kod tak, jak go porównujemy: bez spacji i wielkimi literami („ larpinmiami” = LARPINMIAMI).
-- Zwraca nil dla pustego, zbyt długiego albo nietekstowego.
function Rewards.normalizeCode(text)
	if type(text) ~= "string" or #text > Rewards.CodeMaxLength * 4 then
		return nil
	end
	local code = string.upper((string.gsub(text, "%s", "")))
	if code == "" or #code > Rewards.CodeMaxLength then
		return nil
	end
	return code
end

-- Nagroda za kod (z Economy.Rewards.Codes) albo nil.
function Rewards.codeInfo(code)
	if type(code) ~= "string" then
		return nil
	end
	return Economy.Rewards.Codes[code]
end

-- Czy kod jeszcze działa: Ends = koniec w sekundach UTC (os.time()); bez Ends działa zawsze.
function Rewards.codeActive(info, now)
	return info ~= nil and (info.Ends == nil or now == nil or now < info.Ends)
end

-- Czy gracz już wpisał ten kod.
function Rewards.codeUsed(data, code)
	return type(data.Codes) == "table" and data.Codes[code] == true
end

-- Wpisany kod. limits jak w Rewards.fits, now = os.time() (dla kodów z końcem). Zwraca wynik jak
-- Rewards.grant (z polami Code i Label) albo nil i powód: Invalid (pusty albo za długi), Unknown
-- (nie ma takiego kodu), Expired, Used (już wpisany na tym koncie), PetInventory, ClothInventory.
-- Bez miejsca kod zostaje niewpisany, więc można go użyć po zrobieniu miejsca.
function Rewards.redeemCode(data, ctx, text, random01, limits, now)
	local code = Rewards.normalizeCode(text)
	if code == nil then
		return nil, "Invalid"
	end
	local info = Rewards.codeInfo(code)
	if info == nil then
		return nil, "Unknown"
	end
	if not Rewards.codeActive(info, now) then
		return nil, "Expired"
	end
	if type(data.Codes) ~= "table" then
		data.Codes = {}
	end
	if data.Codes[code] then
		return nil, "Used"
	end
	local ok, reason = Rewards.fits(data, info.Items, limits)
	if not ok then
		return nil, reason
	end
	data.Codes[code] = true
	local result = Rewards.grant(data, ctx, info.Items, random01)
	result.Code = code
	result.Label = info.Label
	return result
end

----------------------------------------------------------------- Nagroda dzienna
-- 7 dni z Economy.Rewards.DailyStreak. Dzień zmienia się o północy UTC (jak Verified i reklamy).
-- Odbiór dzień po dniu podnosi serię, a po dniu 7 cykl zaczyna się od dnia 1 (seria rośnie dalej).
-- Opuszczony dzień: seria od nowa (dzień 1). Zapis: data.Daily = { Day, Streak, Claimed }.
function Rewards.day(now)
	return Shop.day(now)
end

local function dailyOf(data)
	if type(data.Daily) ~= "table" then
		data.Daily = {}
	end
	local d = data.Daily
	d.Day = d.Day or 0 -- dzień UTC ostatniego odbioru (0 = nigdy)
	d.Streak = d.Streak or 0 -- ile dni pod rząd (rośnie też po dniu 7)
	d.Claimed = d.Claimed or 0 -- wszystkie odebrane nagrody dzienne
	return d
end

-- Stan nagrody dziennej w chwili now (sekundy UTC):
--   Day          dzień w cyklu (1–7): do odebrania albo odebrany dziś
--   CanClaim     czy można dziś odebrać
--   Streak       seria (przy zerwanej 0)
--   Lost         seria właśnie się zerwała (opuszczony dzień)
--   SecondsLeft  do następnej nagrody (0, gdy można odebrać)
--   Reward       nagroda dnia Day (z Economy.Rewards.DailyStreak)
function Rewards.dailyState(data, now)
	local d = dailyOf(data)
	local today = Rewards.day(now)
	local days = #Economy.Rewards.DailyStreak
	local state = { Streak = d.Streak, SecondsLeft = 0, Lost = false }
	if d.Day == today and d.Streak > 0 then
		state.CanClaim = false
		state.Day = ((d.Streak - 1) % days) + 1
		state.SecondsLeft = (today + 1) * Shop.DaySeconds - now
	elseif d.Day == today - 1 and d.Streak > 0 then
		state.CanClaim = true
		state.Day = (d.Streak % days) + 1
		state.Continues = true
	else
		state.CanClaim = true
		state.Day = 1
		state.Lost = d.Streak > 0
		state.Streak = 0
	end
	state.Reward = Economy.Rewards.DailyStreak[state.Day]
	return state
end

-- Odbiera dzisiejszą nagrodę. limits jak w Rewards.fits. Zwraca wynik jak Rewards.grant (z polami
-- Day i Streak) albo nil i powód: Claimed (już dziś), PetInventory, ClothInventory. Bez miejsca
-- nagroda czeka (można ją odebrać po zrobieniu miejsca, tego samego dnia).
function Rewards.claimDaily(data, ctx, random01, limits, now)
	local state = Rewards.dailyState(data, now)
	if not state.CanClaim then
		return nil, "Claimed"
	end
	local ok, reason = Rewards.fits(data, state.Reward.Items, limits)
	if not ok then
		return nil, reason
	end
	local d = dailyOf(data)
	if state.Continues then
		d.Streak = d.Streak + 1
	else
		d.Streak = 1
	end
	d.Day = Rewards.day(now)
	d.Claimed = d.Claimed + 1
	local result = Rewards.grant(data, ctx, state.Reward.Items, random01)
	result.Day = state.Day
	result.Streak = d.Streak
	return result
end

----------------------------------------------------------------- Zadania dzienne
-- 3 zadania na dzień UTC (Economy.Rewards.QuestsPerDay) z puli 17 (Economy.Rewards.DailyQuests).
-- Losuje je serwer przy pierwszym stanie danego dnia (Rewards.ensureQuests), tylko spośród tych, które
-- gracz może już zrobić (Requires: aktywność ze swoją strefą i tierem, strefa, Rebirth, ulepszenie nie
-- na maksa). Najpierw idą zadania, których nie było poprzednio, żeby dni się różniły.
-- Postęp (Rewards.questProgress) liczy to, co gracz robi sam: kliki bez Auto-Click, Sell na polu Sell,
-- skończone aktywności (i oceny Viral w wywiadzie, pełny pasek Aury), jajka i boxy za L$, łączenie
-- petów albo ubrań (próby i udane), sprzedaż petów, ulepszenia za L$ i minuty w grze. Auto-Click,
-- Auto-Sell, Sell Now i premium jajka się nie liczą, bo za Robuxy nigdy nie ma Aury. Skończone zadanie serwer od razu
-- odbiera (Rewards.claimQuest); bez miejsca w ekwipunku nagroda czeka na CLAIM w oknie (do północy).
-- Za każde zadanie +10 Aury, a za komplet +20 (Economy.Aura, razy Aura Gain, od Rebirth 1).
-- Zapis: data.Quests = { Day, List = { { Key, Progress, Claimed } }, Bonus, Completed }.

-- Zadanie za skończoną aktywność (rodzaje z Loop.ActivityKinds); każda aktywność liczy się też
-- do zadania Activities.
Rewards.ActivityQuests = { Car = "CarPhotos", Interview = "Interviews", Yacht = "YachtSessions", Jet = "JetRentals" }

-- Najniższa ocena wywiadu, która liczy się do zadania ViralInterviews (Viral; Mega viral też).
Rewards.ViralGrade = math.huge
for i, grade in ipairs((Economy.Activities.Interview or {}).Grades or {}) do
	if grade.Name == "Viral" then
		Rewards.ViralGrade = i
	end
end

-- Zadanie z puli po kluczu: { Key, Target, Reward } albo nil.
function Rewards.questInfo(key)
	for _, quest in ipairs(Economy.Rewards.DailyQuests) do
		if quest.Key == key then
			return quest
		end
	end
	return nil
end

-- Czy gracz może już zrobić zadanie key. Requires z Economy.Rewards.DailyQuests: Activity =
-- aktywność ze swoją strefą i tierem (np. kupiony odrzutowiec), Zone = najniższa strefa, Rebirth =
-- najmniej Rebirthów, Upgrade = Click Multiplier albo Bag jeszcze nie na maksa. Bez Requires: zawsze.
function Rewards.questAvailable(data, key)
	local info = Rewards.questInfo(key)
	if info == nil then
		return false
	end
	local needs = info.Requires
	if needs == nil then
		return true
	end
	local zones = data.ZonesUnlocked or 1
	if needs.Activity ~= nil then
		local activity = Economy.Activities[needs.Activity]
		if activity == nil or zones < activity.Zone or Loop.activityTier(data, needs.Activity) < 1 then
			return false
		end
	end
	if needs.Zone ~= nil and zones < needs.Zone then
		return false
	end
	if needs.Rebirth ~= nil and (data.RebirthCount or 0) < needs.Rebirth then
		return false
	end
	if needs.Upgrade and Loop.nextCost(data, "Click") == nil and Loop.nextCost(data, "Bag") == nil then
		return false
	end
	return true
end

local function questsOf(data)
	if type(data.Quests) ~= "table" then
		data.Quests = {}
	end
	local q = data.Quests
	q.Day = q.Day or 0 -- dzień UTC, na który są wylosowane (0 = jeszcze nigdy)
	if type(q.List) ~= "table" then
		q.List = {}
	end
	q.Bonus = q.Bonus == true -- komplet już dał Aurę
	q.Completed = q.Completed or 0 -- wszystkie odebrane zadania
	return q
end

local function shuffle(list, random01)
	for i = #list, 2, -1 do
		local j = math.min(i, math.floor(random01() * i) + 1)
		list[i], list[j] = list[j], list[i]
	end
end

-- Losuje count różnych zadań z tych, które gracz może zrobić (kolejność jak w puli). previous = lista
-- z poprzedniego losowania: jej zadania idą na koniec, więc wracają tylko wtedy, gdy nowych jest za mało.
function Rewards.pickQuests(data, random01, count, previous)
	local before = {}
	for _, quest in ipairs(previous or {}) do
		if type(quest) == "table" and quest.Key ~= nil then
			before[quest.Key] = true
		end
	end
	local fresh, old = {}, {}
	for i, quest in ipairs(Economy.Rewards.DailyQuests) do
		if Rewards.questAvailable(data, quest.Key) then
			if before[quest.Key] then
				table.insert(old, i)
			else
				table.insert(fresh, i)
			end
		end
	end
	shuffle(fresh, random01)
	shuffle(old, random01)
	local picked = {}
	for _, list in ipairs({ fresh, old }) do
		for _, index in ipairs(list) do
			if #picked < count then
				table.insert(picked, index)
			end
		end
	end
	table.sort(picked)
	local out = {}
	for _, index in ipairs(picked) do
		table.insert(out, { Key = Economy.Rewards.DailyQuests[index].Key, Progress = 0, Claimed = false })
	end
	return out
end

local function poolOrder(key)
	for i, quest in ipairs(Economy.Rewards.DailyQuests) do
		if quest.Key == key then
			return i
		end
	end
	return math.huge
end

-- Po Rebirthie strefy wracają do 1, więc nieskończone zadanie z aktywnością, której gracz już nie
-- może zrobić, zamieniamy na inne z jego puli (postęp od zera). Zwraca, ile zadań się zmieniło.
local function replaceUnavailable(q, data, random01)
	local taken = {}
	for _, quest in ipairs(q.List) do
		taken[quest.Key] = true
	end
	local replaced = 0
	for i, quest in ipairs(q.List) do
		local info = Rewards.questInfo(quest.Key)
		local unfinished = info == nil or (not quest.Claimed and quest.Progress < info.Target)
		if unfinished and not Rewards.questAvailable(data, quest.Key) then
			local pool = {}
			for _, candidate in ipairs(Economy.Rewards.DailyQuests) do
				if not taken[candidate.Key] and Rewards.questAvailable(data, candidate.Key) then
					table.insert(pool, candidate.Key)
				end
			end
			if #pool > 0 then
				local key = pool[math.min(#pool, math.floor(random01() * #pool) + 1)]
				taken[key] = true
				q.List[i] = { Key = key, Progress = 0, Claimed = false }
				replaced = replaced + 1
			end
		end
	end
	if replaced > 0 then
		table.sort(q.List, function(a, b)
			return poolOrder(a.Key) < poolOrder(b.Key)
		end)
	end
	return replaced
end

-- Zadania na dziś (zwraca data.Quests): nowe losowanie, gdy zmienił się dzień UTC. random01 = funkcja
-- losująca z [0, 1) (na serwerze Random), now = os.time(). Niedobrane nagrody z wczoraj przepadają.
function Rewards.ensureQuests(data, random01, now)
	local q = questsOf(data)
	local today = Rewards.day(now)
	random01 = random01 or math.random
	if q.Day ~= today then
		q.List = Rewards.pickQuests(data, random01, Economy.Rewards.QuestsPerDay, q.List)
		q.Day = today
		q.Bonus = false
	else
		replaceUnavailable(q, data, random01)
	end
	return q
end

-- Postęp: gracz zrobił amount razy to, co liczy zadanie key (np. "Clicks", 10). Zwraca true, gdy
-- coś się zmieniło, i listę numerów zadań, które właśnie się skończyły (albo nil).
function Rewards.questProgress(data, key, amount, random01, now)
	amount = tonumber(amount)
	if amount == nil or amount ~= amount or amount < 1 then
		return false, nil
	end
	amount = math.floor(amount)
	local q = Rewards.ensureQuests(data, random01, now)
	local changed, done = false, nil
	for i, quest in ipairs(q.List) do
		local info = Rewards.questInfo(quest.Key)
		if quest.Key == key and info ~= nil and not quest.Claimed and quest.Progress < info.Target then
			quest.Progress = math.min(info.Target, quest.Progress + amount)
			changed = true
			if quest.Progress >= info.Target then
				done = done or {}
				table.insert(done, i)
			end
		end
	end
	return changed, done
end

-- Czy wszystkie dzisiejsze zadania są odebrane.
function Rewards.allQuestsClaimed(data)
	local q = questsOf(data)
	if #q.List == 0 then
		return false
	end
	for _, quest in ipairs(q.List) do
		if not quest.Claimed then
			return false
		end
	end
	return true
end

-- Ile Aury da teraz jedno zadanie i komplet (razy Aura Gain; przed Rebirth 1 zero).
function Rewards.questAura(data)
	if not Rebirth.unlocked(data) then
		return 0, 0
	end
	local gain = Rebirth.gain(data)
	return Economy.Aura.DailyQuestReward * gain, Economy.Aura.DailyAllQuestsBonus * gain
end

-- Odbiera nagrodę skończonego zadania nr index. limits jak w Rewards.fits. Zwraca wynik jak
-- Rewards.grant z polami Index, Key, Aura (dodana za zadanie), BonusAura (za komplet, gdy to ostatnie
-- z trzech, inaczej 0) i AllDone albo nil i powód: BadRequest, NotDone, Claimed, PetInventory,
-- ClothInventory. Bez miejsca nagroda czeka (do północy UTC).
function Rewards.claimQuest(data, ctx, index, random01, limits, now)
	local q = Rewards.ensureQuests(data, random01, now)
	local quest = nil
	if type(index) == "number" then
		quest = q.List[index]
	end
	local info = quest and Rewards.questInfo(quest.Key)
	if info == nil then
		return nil, "BadRequest"
	end
	if quest.Claimed then
		return nil, "Claimed"
	end
	if quest.Progress < info.Target then
		return nil, "NotDone"
	end
	local ok, reason = Rewards.fits(data, info.Reward.Items, limits)
	if not ok then
		return nil, reason
	end
	quest.Claimed = true
	q.Completed = q.Completed + 1
	local result = Rewards.grant(data, ctx, info.Reward.Items, random01)
	result.Index = index
	result.Key = quest.Key
	result.Aura = Rebirth.addAura(data, Economy.Aura.DailyQuestReward)
	result.BonusAura = 0
	result.AllDone = false
	if not q.Bonus and Rewards.allQuestsClaimed(data) then
		q.Bonus = true
		result.AllDone = true
		result.BonusAura = Rebirth.addAura(data, Economy.Aura.DailyAllQuestsBonus)
	end
	return result
end

-- Stan zadań dla okna (po Rewards.ensureQuests): List = { { Index, Key, Progress, Target, Claimed } },
-- Bonus (komplet już dał Aurę), Aura i BonusAura (ile dadzą teraz), SecondsLeft (do nowych zadań).
function Rewards.questView(data, now)
	local q = questsOf(data)
	local list = {}
	for i, quest in ipairs(q.List) do
		local info = Rewards.questInfo(quest.Key)
		if info ~= nil then
			table.insert(list, {
				Index = i,
				Key = quest.Key,
				Progress = math.min(quest.Progress, info.Target),
				Target = info.Target,
				Claimed = quest.Claimed == true,
			})
		end
	end
	local aura, bonus = Rewards.questAura(data)
	return {
		List = list,
		Bonus = q.Bonus,
		Aura = aura,
		BonusAura = bonus,
		SecondsLeft = (Rewards.day(now) + 1) * Shop.DaySeconds - now,
	}
end

return Rewards
