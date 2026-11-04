-- Treść wywiadu w studiu (strefa 3). Ten plik edytujemy ręcznie, napisy w grze są po angielsku.
--
-- Pomysł jak w filmikach z Miami: prowadzący pyta „tradera” o proste rzeczy (ile spółek jest
-- w S&P 500, kto jest jego brokerem), a ten odpowiada głupio, bo tylko udaje, że gra na giełdzie.
-- W każdym wywiadzie są 3 losowe pytania (4, gdy gracz odpowiada szybko). Gracz wybiera jedną
-- z trzech odpowiedzi i wszystkie są głupie. Ocenę klipu (Flop … Mega viral) losuje serwer, więc
-- odpowiedź jej nie zmienia: jest dla zabawy.
--
-- Pola odpowiedzi:
--   Say     = co mówi gracz (najwyżej 22 znaki, bo musi się zmieścić na przycisku),
--   Reply   = reakcja prowadzącego (najwyżej 32 znaki),
--   Comment = komentarz w czacie (najwyżej 30 znaków, emoji liczy się jako 1 znak),
--   React   = jak reaguje studio:
--     "Boom"     dramatyczne zbliżenie kamery na twarz prowadzącego (jak w memach),
--     "Laugh"    śmiech publiczności i plan ogólny,
--     "Crickets" niezręczna cisza: prowadzący najpierw milczy („...”), kamera z boku,
--     "Bruh"     prowadzący patrzy w kamerę: „bruh”.
-- Pytanie (Ask) ma najwyżej 46 znaków. Limity i liczbę odpowiedzi sprawdza InterviewSpec
-- (python tools/test_luau.py i ConfigCheck w Studio), więc po zmianach uruchom test.
-- Gracze to głównie dzieci i nastolatki: humor bez przekleństw, bez prawdziwych osób i bez
-- prawdziwych porad finansowych (zasady Roblox).

return {
	Host = "🎤 HOST", -- podpis prowadzącego w okienku z napisami (gracz ma swoją nazwę)
	Stall = "Uhh... ", -- gdy czas na odpowiedź minie, gracz zaczyna od tego i mówi losową odpowiedź

	-- Powitanie (losowe).
	Intro = {
		"We're LIVE with a real Miami day trader!",
		"Today: a self-made millionaire. Allegedly.",
		"Our guest says they're a trading genius.",
		"Real trader, real questions. Let's go!",
		"Live from Miami. Quick questions, ready?",
	},

	-- Zakończenie, zanim klip pójdzie do sieci (losowe).
	Outro = {
		"That's a wrap. Posting this NOW.",
		"Thank you, genius. We're done here.",
		"Okay. I've heard enough.",
		"Incredible. Truly. Posting it.",
		"Wow. The internet needs to see this.",
	},

	Questions = {
		{
			Ask = "How many companies are in the S&P 500?",
			Answers = {
				{ Say = "5.", Reply = "Five.", Comment = "bro rounded down 💀", React = "Boom" },
				{ Say = "Like... 100?", Reply = "It's literally in the name.", Comment = "THE NAME 😭😭", React = "Laugh" },
				{ Say = "It's a car, bro", Reply = "...It's not a car.", Comment = "500 horsepower 💀", React = "Crickets" },
			},
		},
		{
			Ask = "Who's your broker?",
			Answers = {
				{ Say = "California", Reply = "That's a state.", Comment = "CALIFORNIA 😭😭😭", React = "Laugh" },
				{ Say = "My mom", Reply = "Your mom is your broker?", Comment = "mom approves every trade 💀", React = "Boom" },
				{ Say = "Gary from the gym", Reply = "Who is Gary?", Comment = "Gary runs Wall Street fr", React = "Bruh" },
			},
		},
		{
			Ask = "Okay, easy one. What's a stock?",
			Answers = {
				{ Say = "Like a stick?", Reply = "That's a stick.", Comment = "bro invested in sticks 🌳", React = "Boom" },
				{ Say = "A stock photo", Reply = "Not that kind.", Comment = "bro trades JPEGs 📸", React = "Crickets" },
				{ Say = "I only do Robux", Reply = "That's not the stock market.", Comment = "Robux > stocks tbh", React = "Laugh" },
			},
		},
		{
			Ask = "What does 'buy low, sell high' mean?",
			Answers = {
				{ Say = "Buy high, sell low", Reply = "That's backwards.", Comment = "this is why bro rents 💀", React = "Boom" },
				{ Say = "Sell it on a ladder", Reply = "Not THAT kind of high.", Comment = "ladder strategy 📈", React = "Laugh" },
				{ Say = "Whisper buy, YELL sell", Reply = "Please don't yell.", Comment = "SELL!!! 📢", React = "Crickets" },
			},
		},
		{
			Ask = "Quick math. What's 10% of 100?",
			Answers = {
				{ Say = "100%", Reply = "...What?", Comment = "math teacher fainted 😵", React = "Boom" },
				{ Say = "Like... 1,000?", Reply = "That's MORE than 100.", Comment = "the math went UP 📈", React = "Laugh" },
				{ Say = "Ask my calculator", Reply = "...It's ten.", Comment = "calculator carrying 😭", React = "Crickets" },
			},
		},
		{
			Ask = "When does the stock market open?",
			Answers = {
				{ Say = "When I wake up", Reply = "It doesn't wait for you.", Comment = "market opens at 2 PM for bro", React = "Boom" },
				{ Say = "It's 24/7, bro", Reply = "That's a gas station.", Comment = "gas station trader ⛽", React = "Laugh" },
				{ Say = "When the doors open", Reply = "There are no doors.", Comment = "bro thinks it's a mall 😭", React = "Crickets" },
			},
		},
		{
			Ask = "What's a bull market?",
			Answers = {
				{ Say = "They sell bulls there", Reply = "No.", Comment = "moo 🐮", React = "Boom" },
				{ Say = "A very angry market", Reply = "...Honestly? Not bad.", Comment = "lowkey cooked 🔥", React = "Laugh" },
				{ Say = "Opposite of cow market", Reply = "That's not a thing.", Comment = "cow market 😭😭", React = "Bruh" },
			},
		},
		{
			Ask = "What's your trading strategy?",
			Answers = {
				{ Say = "Eyes closed, click", Reply = "That's... a strategy.", Comment = "eyes closed, money gone 💸", React = "Boom" },
				{ Say = "I ask my dog", Reply = "And what does he say?", Comment = "the dog is up 400% 🐶", React = "Laugh" },
				{ Say = "Vibes.", Reply = "Just vibes?", Comment = "vibe trading 📉", React = "Crickets" },
			},
		},
		{
			Ask = "What does CEO stand for?",
			Answers = {
				{ Say = "Chief Eating Officer", Reply = "No.", Comment = "CEO of snacks 🍕", React = "Boom" },
				{ Say = "Cool Expensive Outfit", Reply = "That's... not it.", Comment = "drip over degree 💧", React = "Laugh" },
				{ Say = "Me.", Reply = "...Okay, boss.", Comment = "CEO of nothing 😭", React = "Bruh" },
			},
		},
		{
			Ask = "Do you know what a candle chart is?",
			Answers = {
				{ Say = "Vanilla scented", Reply = "Not THAT candle.", Comment = "smells like profit ✨", React = "Laugh" },
				{ Say = "Birthday stuff?", Reply = "It's not a birthday.", Comment = "happy birthday, portfolio 🎂", React = "Boom" },
				{ Say = "Red means spicy", Reply = "Red means you lost money.", Comment = "spicy portfolio 🔥", React = "Crickets" },
			},
		},
		{
			Ask = "How much money do you have in the market?",
			Answers = {
				{ Say = "Like 3 dollars", Reply = "Three dollars.", Comment = "bro is ALL IN 💀", React = "Boom" },
				{ Say = "In my other wallet", Reply = "Sure it is.", Comment = "the other wallet: 👻", React = "Crickets" },
				{ Say = "Can I check later?", Reply = "We're live.", Comment = "bro is checking rn 😭", React = "Bruh" },
			},
		},
		{
			Ask = "Nice watch. Is it real?",
			Answers = {
				{ Say = "Real... ly rented", Reply = "So, no.", Comment = "rented drip 💀", React = "Boom" },
				{ Say = "It tells time, so yes", Reply = "Fair, I guess.", Comment = "technically correct 🤓", React = "Laugh" },
				{ Say = "Don't touch it!", Reply = "I wasn't going to.", Comment = "it came in a cereal box 😭", React = "Crickets" },
			},
		},
		{
			Ask = "Is that your supercar outside?",
			Answers = {
				{ Say = "Yes. For one hour.", Reply = "You rented it?", Comment = "rental timer is ticking ⏳", React = "Boom" },
				{ Say = "It's my uncle's", Reply = "Does he know?", Comment = "uncle is calling 📞", React = "Laugh" },
				{ Say = "What car?", Reply = "The one you posed with.", Comment = "bro took the bus 🚌", React = "Crickets" },
			},
		},
		{
			Ask = "What does 'going short' mean?",
			Answers = {
				{ Say = "Not being tall", Reply = "Not your height!", Comment = "short king energy 👑", React = "Laugh" },
				{ Say = "Wearing shorts", Reply = "Please stop.", Comment = "summer trader 😎", React = "Boom" },
				{ Say = "Leaving early", Reply = "You can't leave yet.", Comment = "bro is walking away 💀", React = "Crickets" },
			},
		},
		{
			Ask = "Can you name ONE stock?",
			Answers = {
				{ Say = "The green one", Reply = "The green one?", Comment = "bro means the chart 😭", React = "Laugh" },
				{ Say = "Chicken stock", Reply = "That's soup.", Comment = "chef trader 🍗", React = "Bruh" },
				{ Say = "Roblox?", Reply = "...Okay, that one's real.", Comment = "FIRST REAL ANSWER 😳", React = "Boom" },
			},
		},
		{
			Ask = "What was your biggest win?",
			Answers = {
				{ Say = "Found $5 in my jacket", Reply = "That's not trading.", Comment = "real profit tho 💵", React = "Laugh" },
				{ Say = "Beat my little bro", Reply = "At trading?", Comment = "family W 🏆", React = "Boom" },
				{ Say = "This interview", Reply = "...We'll see.", Comment = "so humble 😭", React = "Crickets" },
			},
		},
		{
			Ask = "What's a bear market?",
			Answers = {
				{ Say = "Teddy bear sale", Reply = "Cute. But no.", Comment = "🧸🧸🧸", React = "Laugh" },
				{ Say = "Bears buying honey", Reply = "That's... no.", Comment = "honey stocks 🍯", React = "Boom" },
				{ Say = "The market's asleep", Reply = "That's hibernation.", Comment = "market sleeping 💤", React = "Crickets" },
			},
		},
		{
			Ask = "A stock drops from $10 to $5. Did you lose?",
			Answers = {
				{ Say = "No, it's on sale!", Reply = "That's one way to see it.", Comment = "black friday trader 💀", React = "Laugh" },
				{ Say = "Only if I look", Reply = "That's not how it works.", Comment = "can't lose if you don't look 🙈", React = "Boom" },
				{ Say = "I still have it, so no", Reply = "That's the problem.", Comment = "pure copium 😭", React = "Crickets" },
			},
		},
		{
			Ask = "What does 'portfolio' mean?",
			Answers = {
				{ Say = "A folder for drawings", Reply = "That's an art portfolio.", Comment = "art trader 🎨", React = "Laugh" },
				{ Say = "My photo gallery", Reply = "Of rented cars?", Comment = "100 pics, 0 stocks 📸", React = "Boom" },
				{ Say = "A port for folios?", Reply = "What's a folio?", Comment = "bro made up a word 😭", React = "Bruh" },
			},
		},
		{
			Ask = "How long have you been trading?",
			Answers = {
				{ Say = "Since this morning", Reply = "And you're a pro already?", Comment = "day 1 legend 😭", React = "Laugh" },
				{ Say = "Since I saw one video", Reply = "One video?", Comment = "certified expert 🎓", React = "Boom" },
				{ Say = "Trading what?", Reply = "...You said you're a trader.", Comment = "plot twist 💀", React = "Bruh" },
			},
		},
		{
			Ask = "Simple one. What's 2 + 2?",
			Answers = {
				{ Say = "22", Reply = "That's two twos.", Comment = "TWENTY TWO 😭", React = "Laugh" },
				{ Say = "Fish", Reply = "...Fish.", Comment = "🐟🐟🐟", React = "Crickets" },
				{ Say = "Depends on the market", Reply = "It does not.", Comment = "math is volatile now 📉", React = "Boom" },
			},
		},
		{
			Ask = "What's the stock market, in your words?",
			Answers = {
				{ Say = "Where you buy socks", Reply = "Stocks. Not socks.", Comment = "sock market 🧦", React = "Laugh" },
				{ Say = "A mall for rich people", Reply = "Close... but no.", Comment = "this mall is the market 💀", React = "Crickets" },
				{ Say = "Like... Wall Street?", Reply = "And what's Wall Street?", Comment = "a street. with walls. 😭", React = "Bruh" },
			},
		},
		{
			Ask = "What's inflation?",
			Answers = {
				{ Say = "Blowing up balloons", Reply = "Wrong inflation.", Comment = "balloon economics 🎈", React = "Laugh" },
				{ Say = "Prices go to the gym", Reply = "...Weirdly close.", Comment = "prices getting swole 💪", React = "Crickets" },
				{ Say = "When my tires go flat", Reply = "That's the opposite.", Comment = "bro deflated 💀", React = "Bruh" },
			},
		},
	},

	-- Komentarze w czacie (po prawej, jak na transmisji na żywo).
	Comments = {
		Intro = { "omg LIVE 🔴", "first!", "who is this 👀", "a REAL trader?? 👀", "let's goooo" },
		Thinking = { "bro is thinking 🤔", "this is gonna be good", "answer quick 😭", "the silence 💀", "say something 😭" },
		-- po każdej odpowiedzi: komentarz z odpowiedzi i jeden z puli jej reakcji
		Boom = { "💀💀💀", "NAHHH 💀", "bro what", "I can't 💀" },
		Laugh = { "😭😭😭", "LMAOOO", "I'm crying 😭", "stop 😭😭" },
		Crickets = { "...", "awkward 😬", "the silence 😐", "bro froze" },
		Bruh = { "bruh", "bruh moment 😑", "why 😭", "💀" },
		-- po wrzuceniu klipu, według oceny: Flop, Solid, Viral, Mega viral
		Grades = {
			{ "who is this", "mid 😐", "scroll.", "0 likes speedrun" },
			{ "lmao", "W guest 😭", "the confidence 💀", "this made my day" },
			{ "this is going viral 🔥", "FYP 🔥", "everyone needs to see this", "clip of the year 😭" },
			{ "BEST CLIP EVER 😭😭", "bro is famous now 💀", "LEGEND 👑", "1M views incoming 🚀" },
		},
	},

	-- Nicki w czacie (wymyślone).
	Users = {
		"xX_Trader_Xx",
		"lambo_larper",
		"candle_queen",
		"noob_investor",
		"moms_broker",
		"stonks4life",
		"gary_from_gym",
		"miami_mike",
		"sigma_saver",
		"fyp_king",
		"chart_watcher",
		"bagholder99",
		"robux_rich",
		"teddy_bear_fund",
		"w_rizz_22",
		"bruh_moment",
		"real_ceo_99",
		"yacht_kid",
		"luxury_lou",
		"not_a_bot_fr",
		"pizza_ceo",
		"dog_trader",
		"certified_bull",
	},
}
