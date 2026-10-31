-- Limit zdarzeń na sekundę (wiadro z żetonami). Serwer używa go do kliku z limitem, a klient,
-- żeby nie pokazywać kliknięć, których serwer i tak nie przyjmie.

local RateLimiter = {}
RateLimiter.__index = RateLimiter

-- rate: żetony na sekundę, burst: najwięcej żetonów naraz
function RateLimiter.new(rate, burst)
	return setmetatable({ rate = rate, burst = burst, tokens = burst, last = nil }, RateLimiter)
end

-- Bierze do n żetonów w chwili now (sekundy, np. os.clock()). Zwraca, ile się udało wziąć.
function RateLimiter:take(now, n)
	n = n or 1
	if self.last ~= nil then
		local refill = (now - self.last) * self.rate
		if refill > 0 then
			self.tokens = math.min(self.burst, self.tokens + refill)
		end
	end
	self.last = now
	local granted = math.min(n, math.floor(self.tokens + 1e-9))
	if granted < 0 then
		granted = 0
	end
	self.tokens = self.tokens - granted
	return granted
end

return RateLimiter
