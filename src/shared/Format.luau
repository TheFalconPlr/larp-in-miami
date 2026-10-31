-- Formatowanie liczb i czasu tak, jak pokazuje je gra: 1.5K, 2.3M, 937.5Qa, 1h 05m.
-- Ten sam zapis co kolumna „W grze” w arkuszu ekonomii.

local Format = {}

local SUFFIXES = {
	"K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No",
	"Dc", "Ud", "Dd", "Td", "Qad", "Qid", "Sxd", "Spd", "Ocd", "Nod", "Vg",
}

local function trimZeros(s)
	s = string.gsub(s, "(%..-)0+$", "%1")
	s = string.gsub(s, "%.$", "")
	return s
end

-- Liczba z sufiksem (maks. 2 miejsca po przecinku, bez zbędnych zer).
function Format.number(n)
	if n ~= n then
		return "NaN"
	end
	if n < 0 then
		return "-" .. Format.number(-n)
	end
	if n == math.huge then
		return "∞"
	end
	if n < 1000 then
		local rounded = math.floor(n + 0.5)
		if rounded < 1000 then
			return tostring(rounded)
		end
	end
	local tier = math.floor(math.log10(n) / 3 + 1e-12)
	if tier < 1 then
		tier = 1
	end
	if tier > #SUFFIXES then
		tier = #SUFFIXES
	end
	local rounded = math.floor(n / 10 ^ (tier * 3) * 100 + 0.5) / 100
	if rounded >= 1000 and tier < #SUFFIXES then
		tier = tier + 1
		rounded = math.floor(n / 10 ^ (tier * 3) * 100 + 0.5) / 100
	end
	return trimZeros(string.format("%.2f", rounded)) .. SUFFIXES[tier]
end

-- Małe liczby z jednym miejscem po przecinku (1.5 LP za klik), większe jak number().
function Format.small(n)
	if n < 100 and n ~= math.floor(n) then
		return trimZeros(string.format("%.1f", n))
	end
	return Format.number(n)
end

local SUFFIX_VALUE = {}
for i, s in ipairs(SUFFIXES) do
	SUFFIX_VALUE[string.lower(s)] = 10 ^ (3 * i)
end

-- Odwrotność number() dla komend testowych: "1.5M" -> 1500000, "3t" -> 3e12, "2e9", "-100".
-- Zła liczba -> nil.
function Format.parse(text)
	if type(text) ~= "string" then
		return nil
	end
	text = string.gsub(text, "[%s,_]", "")
	local num, suffix = string.match(text, "^(%-?[%d%.]+[eE]?[%+%-]?%d*)(%a*)$")
	if num == nil then
		return nil
	end
	local n = tonumber(num)
	if n == nil then
		return nil
	end
	if suffix ~= "" then
		local mult = SUFFIX_VALUE[string.lower(suffix)]
		if mult == nil then
			return nil
		end
		n = n * mult
	end
	if n ~= n or n == math.huge or n == -math.huge then
		return nil
	end
	return n
end

-- Czas: 45s, 3m 05s, 1h 05m.
function Format.duration(seconds)
	seconds = math.max(0, math.floor(seconds + 0.5))
	local h = math.floor(seconds / 3600)
	local m = math.floor((seconds % 3600) / 60)
	local s = seconds % 60
	if h > 0 then
		return string.format("%dh %02dm", h, m)
	elseif m > 0 then
		return string.format("%dm %02ds", m, s)
	end
	return string.format("%ds", s)
end

-- Procent: 0.05 -> "5%", 0.004 -> "0.4%", 0.00004 -> "0.004%".
function Format.percent(p)
	local v = p * 100
	local s
	if v >= 10 then
		s = string.format("%.1f", v)
	elseif v >= 0.1 then
		s = string.format("%.2f", v)
	else
		s = string.format("%.4f", v)
	end
	return trimZeros(s) .. "%"
end

-- Szansa jako „1 in X” dla graczy (tekst w grze po angielsku): 0.00004 -> "1 in 25,000".
function Format.oneIn(p)
	if p <= 0 then
		return "-"
	end
	local x = math.floor(1 / p + 0.5)
	local s = tostring(x)
	local out = ""
	while #s > 3 do
		out = "," .. string.sub(s, -3) .. out
		s = string.sub(s, 1, -4)
	end
	return "1 in " .. s .. out
end

return Format
