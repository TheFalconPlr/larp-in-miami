# Larp in Miami

Kod gry Roblox „Larp in Miami”. Kod jest w plikach (Luau), a Rojo przenosi go do Roblox Studio.

```
GitHub (kod)  ──git pull──▶  Twój komputer (ten folder)  ──rojo serve──▶  Roblox Studio
   ▲                                                                    (Plugins → Rojo → Connect)
   └── Claude wrzuca tu nowy kod
```

Mapę, modele i wygląd UI budujesz w Studio. Skrypty edytujemy tylko w plikach, bo Rojo nadpisuje je w Studio.

## Co jest w środku

| Folder | Trafia w Studio do | Co zawiera |
| --- | --- | --- |
| `src/shared` | ReplicatedStorage → Shared | `Config/Economy` (liczby z arkusza, generowane), `Config/Settings` (ustawienia gry, edytowane ręcznie), `Config/Pets` (nazwy i kolory petów), `Config/Interview` (pytania i odpowiedzi w wywiadzie, edytowane ręcznie), `Data/Template` (szablon zapisu gracza), `Logic/Loop` (klik, Bag, Sell, ulepszenia, strefy, aktywności, pety), `Logic/Interview` (losowanie pytań i sprawdzanie treści wywiadu), `Logic/RateLimiter`, `Formulas`, `Format`, `Net` (zdarzenia sieciowe), `Tests` |
| `src/server` | ServerScriptService → Server | `Main` (start serwera), `ConfigCheck` (testy w Studio), `Services/` (DataService, GamepassService, ZoneService, LoopService, ActivityService (aktywności w strefach 2–5), PetService, AdminService), `Vendor/ProfileStore` (zapis danych) |
| `src/client` | StarterPlayerScripts → Client | `Main` (start gracza), `Hud` (interfejs), `Zones` (bramki, tablice, okno Unlock), `Activities` (aktywności: auto, wywiad, jacht, odrzutowiec), `InterviewShow` (program wywiadu: pytania, odpowiedzi, czat), `Pets` (okno PETS: sprzedaż, łączenie, indeks; pety za graczami), `PetMerge` (okno i animacja łączenia), `Eggs` (jajka: tablice, okno, otwieranie), `SecretBanner` (komunikat o sekrecie u góry ekranu), `PetModels` (modele petów i jajek, wersje Golden i Diamond), `LocalHide` (ukrywanie części tylko u gracza), `Ui/Theme` (kolory, czcionka, skala), `Ui/Kit` (przyciski, kafelki, okna), `Ui/Icons` (ikony), `Ui/Sounds` (dźwięki), `Ui/Pattern` (wzór w tle), `ClickInput` (klikanie), `State` (stan od serwera), `Admin` (komendy testowe) |
| `assets/icons` | — | `larp-icons.png` (arkusz 16 ikon do wgrania w Roblox) i `svg/` (źródła ikon) |
| `docs` | — | rysunki do tego opisu (np. układ tymczasowych stref) |
| `tools` | — | `gen_config.py` (tworzy Config z modelu ekonomii), `test_luau.py` (testy bez Roblox), `build_icons.py` (rysuje arkusz ikon), `economy/` (model i symulacja) |
| `licenses` | — | licencje bibliotek (ProfileStore: Apache 2.0) |

## Instalacja (raz, Windows)

Wszystkie komendy wpisujesz w PowerShell.

1. **Git:** pobierz z https://git-scm.com/download/win i zainstaluj z domyślnymi opcjami.
2. **Rokit** (instaluje narzędzia Roblox):
   ```powershell
   Invoke-RestMethod https://raw.githubusercontent.com/rojo-rbx/rokit/main/scripts/install.ps1 | Invoke-Expression
   ```
   Potem zamknij PowerShell i otwórz go ponownie.
3. **Projekt:** pobierz go do folderu Dokumenty:
   ```powershell
   cd $HOME\Documents
   git clone https://github.com/TheFalconPlr/larp-in-miami.git
   cd larp-in-miami
   ```
4. **Rojo i plugin do Studio.** Wersja Rojo jest już zapisana w `rokit.toml`, więc wystarczą dwie komendy:
   ```powershell
   rokit install
   rojo plugin install
   ```
   Jeśli Rokit zapyta, czy ufasz narzędziu, odpowiedz `y`. Po instalacji pluginu uruchom Studio ponownie.
   Jeśli `rojo` zgłasza „Aftman error”, masz starsze narzędzie Aftman: zmień nazwę folderu `$HOME\.aftman` (np. na `.aftman-stary`) i otwórz PowerShell od nowa.
5. Opcjonalnie: VS Code z rozszerzeniami **Rojo** i **Luau Language Server**, jeśli chcesz zaglądać w kod.

## Codzienna praca (krok po kroku)

Za każdym razem, gdy włączasz laptopa i chcesz popracować:

```
PowerShell:  cd do projektu  →  git pull  →  rojo serve (to okno zostaje otwarte)
Studio:      otwórz grę  →  Plugins → Rojo → Connect  →  Play (F5)
Koniec:      Stop  →  Ctrl+S  →  w oknie z Rojo Ctrl+C
```

1. **Otwórz PowerShell:** Start → wpisz `PowerShell` → Enter.
2. **Wejdź do folderu projektu:**
   ```powershell
   cd $HOME\Documents\larp-in-miami
   ```
3. **Pobierz nowy kod od Claude:**
   ```powershell
   git pull
   ```
   Dobrze, gdy widzisz listę zmienionych plików albo `Already up to date.` (nic nowego).
4. **Uruchom Rojo:**
   ```powershell
   rojo serve
   ```
   Dobrze, gdy widzisz `Rojo server listening` i `Port: 34872`. Nie zamykaj tego okna, dopóki pracujesz: bez niego Studio nie dostaje kodu.
5. **Otwórz Roblox Studio** i grę `[NEW] Larp in Miami!` (z ostatnich gier albo z grupy Larping Studio$).
6. **Połącz Studio z Rojo:** zakładka **Plugins** → **Rojo** → **Connect**. Po chwili plugin pokazuje „Connected”, a skrypty z plików są już w Studio.
7. **Testuj:** **Play** (F5). W oknie **Output** (View → Output) powinny być m.in. te linie:
   ```
   [Larp in Miami] Serwer działa. Ekonomia v2 (arkusz z 29.10.2026). Strefa 5 kosztuje 3T L$, Rebirth 10 kosztuje 750Qa L$.
   ConfigCheck: OK (64 testów zgodnych z arkuszem)
   LoopCheck: OK (103 testów pętli: klik, Bag, Sell, ulepszenia, strefy, aktywności, pety)
   InterviewCheck: OK (16 testów wywiadu: pytania, odpowiedzi, losowanie)
   [Dane] TwojNick: zapis wczytany (DataStore: Access)
   ```
   Komendy testowe wpisujesz na czacie (zacznij od `/cmds`). **Stop** (Shift+F5) kończy test.
8. **Zapisz grę:** Ctrl+S (File → Save to Roblox). Gdy gracze mają zobaczyć zmiany: File → Publish to Roblox (Alt+P).
9. **Koniec pracy:** kliknij okno PowerShell z Rojo i naciśnij **Ctrl+C** (Rojo się zatrzymuje), potem zamknij Studio.

**Nowy kod w trakcie pracy.** Nie trzeba niczego wyłączać: otwórz drugie okno PowerShell i wpisz `cd $HOME\Documents\larp-in-miami`, a potem `git pull`. Rojo sam przeniesie zmiany do Studio, a Ty zrób Stop i Play.

**Gdy coś nie działa:**

| Problem | Co zrobić |
| --- | --- |
| `git pull` pisze `Your local changes ... would be overwritten` | W folderze ktoś zmienił pliki. `git stash` odkłada te zmiany na bok, potem znowu `git pull`. |
| `rojo` „is not recognized” | `rokit install`, potem zamknij PowerShell i otwórz go od nowa. |
| `rojo serve` pisze, że port jest zajęty | Rojo już działa w innym oknie PowerShell. Użyj tamtego albo je zamknij i uruchom `rojo serve` jeszcze raz. |
| Plugin Rojo się nie łączy | Sprawdź, czy okno z `rojo serve` jest otwarte, i kliknij Connect jeszcze raz (adres `localhost`, port `34872`). |
| W Studio jest stary kod | W pluginie Rojo: Disconnect, potem Connect. Potem Stop i Play. |
| W Output są czerwone błędy | Zrób zrzut ekranu okna Output i wyślij go Claude. |

## Etap 2: rdzeń pętli

Co działa: klikanie (myszą albo krótkim dotknięciem ekranu), LP trafiają do Bag, pole Sell zamienia LP na L$, przycisk SELL przenosi na pole Sell, ulepszenia Click Multiplier i Bag (Kup 1 i Kup max), zapis postępu, leaderstats (L$ i Rebirthy), podpowiedzi dla nowego gracza i tryb testowy.

**Sprzedaż.** Przy każdej sprzedaży banknoty wyskakują z paska Bag i lecą łukiem do licznika L$ (przy Auto-Sell mniej banknotów).

**Pole Sell.** Jeśli na mapie nie ma pola Sell, serwer stawia tymczasowe zielone pole obok spawnu. Gdy zbudujesz prawdziwe, nazwij część (Part) podłogi pola `SellPad` albo dodaj jej tag `SellPad` (Properties → Tags). Wtedy tymczasowe pole przestanie się pojawiać.

**Zapis danych.** Studio z włączonym „Enable Studio Access to API Services” zapisuje do prawdziwego DataStore tej gry. Dopóki gra nie jest publiczna, to nic złego, a test „wyjdź i wróć” działa w Studio: Stop, potem znowu Play. Jeśli w Output jest `DataStore: NoAccess`, włącz ten przełącznik (File → Experience Settings → Security).

**Ustawienia** (limit kliknięć, nazwa DataStore, admini) są w `src/shared/Config/Settings.luau`.

## Etap 3: strefy

Co działa: 5 stref z arkusza. Downtown Miami jest za darmo, a kolejne kupujesz za L$: Luxury Cars (6K), Luxury Mall (800K), Miami Beach (150M) i Private Airport (3T). Kupuje się je po kolei, przy bramce: gdy podejdziesz, otworzy się okno „Unlock” z ceną i mnożnikiem. Bramka znika tylko u gracza, który kupił strefę, a inni dalej widzą ścianę. W kupionej strefie każdy klik daje więcej LP (×1,5, ×5, ×8 i ×250), a po wejściu do strefy u góry ekranu pojawia się jej nazwa. Nad zamkniętymi bramkami wiszą tablice z nazwą, mnożnikiem i ceną.

**Tymczasowe strefy.** Dopóki na mapie nie ma stref, serwer stawia kolorową ścieżkę przed spawnem, w stronę, w którą patrzy SpawnLocation. Są na niej strefy 2–5 z bramkami i ścianami po bokach. Odległości są z arkusza: środek strefy jest tak daleko od spawnu, ile trwa powrót z niej na Sell (np. strefa 5: 35 s × 16 studs/s = 560 studs).

![Układ tymczasowych stref](docs/strefy-uklad.png)

**Twoje strefy.** Gdy budujesz prawdziwą mapę, nazwij części tak:

| Co | Nazwa | Uwagi |
| --- | --- | --- |
| Strefa 2–5 | `Zone2` … `Zone5` | Część (podłoga strefy albo niewidzialne pudło) albo model/folder z całą strefą. Do strefy liczy się wszystko nad jej częściami, do 60 studs w górę. Poza strefami 2–5 jest strefa 1 (spawn i Sell). |
| Bramka | `Gate2` … `Gate5` | Część albo model, który zamyka przejście do strefy. Ścieżka powinna mieć ściany po bokach, żeby bramki nie dało się obejść (mnożnik i tak działa tylko w kupionej strefie). |

Gdy na mapie jest choć jedna część `ZoneN`, tymczasowe strefy już się nie pojawiają. Jeśli którejś strefy albo bramki brakuje, w Output będzie ostrzeżenie `[Strefy]`.

## Etap 4: sesja zdjęciowa z autem

Co działa: w Luxury Cars stoi auto do zdjęć. Gdy podejdziesz, otworzy się okno „Car Photoshoot” z autem, nagrodą i przyciskiem START. Sesja trwa jak w arkuszu (8 s plus 3 s przejścia): ekran się ściemnia, stajesz przy aucie, kamera krąży wokół, błyskają flesze, a inni gracze są u Ciebie ukryci. W tym czasie kliknięcia nie działają. Na koniec LP trafiają do Bag, ale tylko tyle, ile się zmieści (z Auto-Sell całość). Gdy nagroda jest większa niż wolne miejsce, okno pokazuje „(Bag limit)”, więc opłaca się większy Bag. Z pełnym Bag sesji się nie zaczyna (najpierw Sell). Nagroda = wartość kliku × 110 × mnożnik auta × bonusy LP, bez mnożnika strefy. W tym samym oknie kupujesz lepsze auta za L$: German Sedan (20K, ×1,5), Muscle Car (50K, ×2,5), Italian Supercar (100K, ×4) i Hypercar (200K, ×6). Nazwy aut są robocze, zmienisz je w `src/client/Activities.luau` (`CarNames`).

**Tymczasowe miejsce.** Dopóki na mapie nie ma `CarSpot`, serwer stawia w strefie 2 platformę z 5 prostymi autami z klocków. Każdy gracz widzi tylko auto ze swojego tieru.

**Twoje miejsce.** Model `CarSpot` w strefie 2, a w nim:

| Co | Nazwa | Uwagi |
| --- | --- | --- |
| Auta | `Car1` … `Car5` | Po jednym modelu na tier, wszystkie w tym samym miejscu. Gracz widzi tylko swoje. |
| Miejsce gracza | `Pose` | Cienka, niewidoczna część na podłodze. Gracz stoi na niej przodem tam, gdzie patrzy przód części. |
| Reszta | dowolne | np. platforma, światła, dekoracje |

Kamera krąży wokół punktu obrotu (pivot) modelu `CarSpot`, więc ustaw go na środku auta. Dźwięki sesji są w `Settings.Sounds`: `Photo` (migawka przy fleszu) i `Reward` (oklaski na koniec).

## Etap 5: jajka i pety

Co działa: w każdej strefie stoją dwa jajka za L$: zwykłe i złote (droższe, z lepszymi szansami). Przy każdym jajku jest żółta pigułka z ceną. Jak w Pet Simulator 99: gdy podejdziesz, nad jajkiem pojawia się biały panel z petami, które mogą wypaść, i ich szansami, a przed jajkiem duże E. Klawisz E (albo kliknięcie w E, na telefonie dotknięcie) otwiera okno kupna „Would you like to buy a … Egg?” z Buy 1 i Buy 3. Buy 3 otwiera trzy jajka naraz i działa z gamepassem Triple Open (w teście `/pass TripleOpen`).

Animacja otwierania: jajko pęka 3 razy (dźwięk coraz wyżej, rysy i odpryski), skorupka się rozpryskuje, a pet wkręca się i odbija na tle promieni i poświaty w kolorze rzadkości. Przy Legendary i Secret są jeszcze iskry, drżenie ekranu i oklaski. Napisy (nazwa, rzadkość z bonusem, „Equipped!”) wskakują po kolei, a na koniec pet leci do kafelka PETS. W czasie animacji HUD jest schowany. Pierwsze jajko w grze (zwykłe w Downtown Miami) zawsze daje Rare. Nowy pet sam się zakłada, jeśli jest wolne miejsce.

Założone pety latają za graczem (widzą je wszyscy) i zwiększają L$ przy Sell. Bonus peta = moc strefy × mnożnik rzadkości, np. Rare z Downtown Miami daje +20% L$, a dwa takie pety dają ×1,4. Miejsca na pety: 3, po jednym więcej od Rebirth 3 i Rebirth 7, a gamepass Pet Slots daje +2. Kafelek PETS po lewej otwiera ekwipunek: kliknij peta, żeby go założyć albo zdjąć, a EQUIP BEST zakłada najmocniejsze. Obok tytułu widać, ile masz petów (np. 37/250; ekwipunek mieści 250). Czerwona kropka na PETS znaczy, że masz wolne miejsce i peta do założenia. Sprzedaż, łączenie i indeks petów opisuje Etap 7.

| Strefa | Zwykłe jajko | Złote jajko | Common → Legendary |
| --- | --- | --- | --- |
| Downtown Miami | 400 L$ | 2K L$ | +5% → +80% L$ |
| Luxury Cars | 6K L$ | 40K L$ | +12% → +192% L$ |
| Luxury Mall | 1M L$ | 5M L$ | +30% → +480% L$ |
| Miami Beach | 60M L$ | 400M L$ | +75% → +1200% L$ |
| Private Airport | 30B L$ | 200B L$ | +200% → +3200% L$ |

Zwykłe jajko: Common 60%, Uncommon 28%, Rare 10%, Epic 2%. Złote: Uncommon 50%, Rare 35%, Epic 13%, Legendary 2% i Secret 0,004% (×64). Ulepszenie Luck za Aurę (w późniejszym etapie) zwiększy szanse na rzadsze pety.

**Tymczasowe stoiska.** Dopóki na mapie nie ma żadnego stoiska, serwer stawia je sam: w Downtown Miami z boku drogi od spawnu do bramki, a w strefach 2–5 na podłodze strefy.

**Twoje stoiska i pety.**

| Co | Nazwa | Uwagi |
| --- | --- | --- |
| Zwykłe jajko | `EggA1` … `EggA5` | Model albo część; cyfra to strefa. Panel z petami wisi nad najwyższym punktem stoiska, a pigułka z ceną przy jego spodzie. Panel i E pokazują się, gdy gracz stoi najwyżej 8 studs od stoiska. |
| Złote jajko | `EggB1` … `EggB5` | jak wyżej |
| Model peta | folder `PetModels` w ReplicatedStorage, a w nim modele nazwane jak pety (np. `Pigeon`, `Alley Cat`) | Wielkość ok. 2–3 studs. Pet patrzy tam, gdzie przód punktu obrotu (pivot) modelu. Bez modelu pet jest kolorową kulką z oczami w kolorze rzadkości. Nazwy wszystkich petów są w `src/shared/Config/Pets.luau`. |

Dźwięki są w `Settings.Sounds`: `Crack` (pojedyncze pęknięcie: gra 3 razy, coraz wyżej, a przy rozbiciu dwa razy naraz, nisko i wysoko), `Hatch` (nowy pet) i `Reward` (oklaski przy Legendary, Mythic i Secret).

## Etap 6: aktywności w strefach 3–5

Co działa: w każdej kupionej strefie jest jedna aktywność. Działa jak zdjęcia z autem: podchodzisz, otwiera się okno z nagrodą i przyciskiem START, a sesja to zaciemnienie, kamera i efekty. W tym czasie kliknięcia nie działają, a inni gracze są u Ciebie ukryci. Na koniec LP trafiają do Bag, ale tylko do pełna (z Auto-Sell całość).

| Strefa | Aktywność | Czas | Nagroda | Co kupujesz |
| --- | --- | --- | --- | --- |
| Luxury Mall | Celebrity Interview: wywiad w studiu telewizyjnym | 45 s | wartość kliku × 3000 × ocena | nic, ocena jest losowa: Flop ×0,5 (20%), Solid ×1 (40%), Viral ×2 (30%), Mega viral ×4 (10%) |
| Miami Beach | Yacht Party: impreza na jachcie | 45 s | wartość kliku × 6000 × jacht | Motor Yacht 400M (×2), Large Yacht 1,5B (×5), Superyacht 4B (×10), Mega Yacht 8B (×25) |
| Private Airport | Private Jet: lot odrzutowcem | 60 s | wartość kliku × 315K × odrzutowiec | Light Jet 120B (×1, pierwszy trzeba kupić), Midsize Jet 1T (×2,5), Ultra Long Range 4T (×6) |

Wszystkie nagrody mnożą też bonusy LP (Rebirth, 2x LP), ale nie mnożnik strefy.

- **Wywiad:** odliczanie „LIVE IN 3, 2, 1”, a potem prowadzący zadaje proste pytania o giełdę (np. „How many companies are in the S&P 500?”, „Who's your broker?”), jak w filmikach z „traderami” z Miami. Gracz ma 3 odpowiedzi do wyboru i wszystkie są głupie („5.”, „California”, „Gary from the gym”). Napisy pojawiają się litera po literze i zostają chwilę na ekranie, a odpowiedzi wyskakują dopiero, gdy pytanie jest napisane. Na wybór jest ok. 6–7 s (w ostatnich 3 s tyka zegar). Gracz wybiera kliknięciem albo klawiszem 1–3, a gdy czas minie, mówi „Uhh...” i losową odpowiedź. Studio reaguje na 4 sposoby: dramatyczne zbliżenie na prowadzącego z „vine boom”, śmiech publiczności (3 wersje), niezręczna cisza ze świerszczami albo „bruh”. Przez cały program gra muzyka talk show (przy reakcjach na chwilę ciszej). Po prawej leci czat z komentarzami, z rogu wylatują emoji, a licznik wyświetleń skacze po każdej odpowiedzi. Zwykle są 3 pytania, a przy szybkich odpowiedziach 4 i pożegnanie gracza („Not financial advice!” → „Clearly.”). Na koniec klip idzie do sieci („whoosh”), czat komentuje wynik i wyskakuje ocena, np. MEGA VIRAL! ×4 (przy FLOP smutna trąbka). Wywiad trwa 45 s (wcześniej 25 s, było za szybko), a nagroda wzrosła tak, że LP na minutę zostały takie same. Ocenę losuje serwer na starcie, więc odpowiedzi jej nie zmieniają: są dla zabawy (inaczej każdy klikałby „najlepszą” i zawsze miał Mega viral, a to rozwaliłoby ekonomię). Okno przy studiu pokazuje nagrodę od–do i szanse ocen.
- **Jacht:** stoisz na pokładzie swojego jachtu i tańczysz, gra muzyka, jacht lekko się kołysze (Ty razem z nim), migają kolorowe światła, spada konfetti, a co kilka sekund ktoś robi zdjęcie (flesz z migawką). Kamera co ok. 4 s zmienia ujęcie jak w teledysku: plan ogólny, Ty z bliska, nisko od wody przy dziobie, zza pleców w stronę lądu, z drona i jazda wzdłuż burty. Kamera stoi zawsze po stronie lądu (tam, skąd przyszedłeś), więc nie wylatuje poza mapę. Na sam koniec trąbka i wybuch konfetti, a po zaciemnieniu oklaski.
- **Odrzutowiec:** w kabinie „ding”, gra muzyka do lotu, silnik rozkręca się (od 30% do pełnej głośności), samolot rusza po pasie (seria zdjęć przy starcie), startuje i leci wśród chmur: pod spodem, po bokach i czasem na trasie, a wtedy ekran na chwilę bieleje jak w chmurze. W locie co kilka sekund jest zdjęcie. Leci lokalna kopia samolotu (tylko u Ciebie), bo przy StreamingEnabled Roblox usuwał prawdziwy, gdy odleciał daleko od postaci. Twoje pety lecą z Tobą (na pasie ich nie widać). Bez odrzutowca okno pokazuje BUY.

W czasie sesji tablice aktywności i pigułki z cenami jajek są schowane, żeby nie wchodziły w kadr.

**Pytania w wywiadzie** zmieniasz w `src/shared/Config/Interview.luau`: pytanie (`Ask`), 3 odpowiedzi (`Say`), reakcja prowadzącego (`Reply`), komentarz w czacie (`Comment`) i rodzaj reakcji studia (`React`: `Boom`, `Laugh`, `Crickets` albo `Bruh`). Tam są też powitania, zakończenia, komentarze i nicki w czacie. Limity długości są opisane na górze pliku, a `python tools/test_luau.py` (i InterviewCheck w Studio) sprawdza, czy wszystko się mieści.

**Tymczasowe miejsca.** Dopóki na mapie nie ma miejsc, serwer stawia je z klocków po lewej stronie ścieżki: studio z tłem, biurkiem, prowadzącym i kamerą (strefa 3), basen z pomostem i 5 jachtami (strefa 4) oraz pas startowy z 3 odrzutowcami (strefa 5).

**Twoje miejsca.**

| Co | Nazwa | Uwagi |
| --- | --- | --- |
| Studio | model `InterviewSpot` w strefie 3 | W środku część `Pose` (tu stoi gość). Punkt obrotu (pivot) modelu na środku sceny, przodem do widowni: według niego ustawiają się kamery. |
| Jachty | model `YachtSpot` w strefie 4, w nim `Yacht1` … `Yacht5` | Jachty w tym samym miejscu na wodzie; w każdym może być własna `Pose` na pokładzie. Bez niej gracz stoi na `Pose` miejsca (np. na pomoście). |
| Odrzutowce | model `JetSpot` w strefie 5, w nim `Jet1` … `Jet3` i `Pose` | Punkt obrotu każdego odrzutowca przodem w stronę dziobu: w tę stronę samolot startuje, więc przed nim musi być pas. |
| Tablica | część `SignAnchor` (niewidoczna) w dowolnym miejscu | Tablica z nazwą i nagrodą wisi nad nią. Bez niej wisi nad największą częścią miejsca. |

Nazwy modeli w grze (auta, jachty, odrzutowce) są robocze, zmienisz je w `src/client/Activities.luau` (`KINDS`).

## Etap 7: sprzedaż, łączenie, indeks i sekrety

Zasady są z dokumentu projektu (etap „Pety, ubrania, sekrety”). Okno PETS ma teraz na dole trzy przyciski: INDEX, MERGE i SELL. DELETE zniknął, bo sprzedaż robi to samo i jeszcze daje L$.

- **SELL:** klikasz pety do sprzedaży (dostają czerwony X). Na kartach widać cenę, a na dole sumę. DUPES zaznacza duplikaty (z każdego rodzaju zostaje jeden: założony albo najstarszy; sekretów nie rusza), ALL zaznacza wszystkie niezałożone, SELL (N) sprzedaje, a CANCEL wraca. Pet daje 10% ceny jajka, z którego wypadł; Golden ×5, a Diamond ×25 (czyli tyle, ile pety, które na niego poszły). Założonych petów nie da się sprzedać, a sprzedaż sekreta trzeba potwierdzić w okienku.
- **MERGE:** wybierasz od 1 do 5 identycznych petów (ta sama strefa, rzadkość i poziom). Wybrane mają fioletowe numery, a pety, których nie da się dołożyć, są przygaszone. Każdy pet to 20% szansy (Merge Luck z Aury dodaje 1 pkt proc. na peta), więc 5 petów to 100%. AUTO dobiera identyczne pety do 5, a bez wyboru bierze rodzaj, którego masz najwięcej. Na dole widać szansę i opłatę. MERGE otwiera okno z petami, które możesz stracić, wynikiem, szansą, opłatą i ostrzeżeniem. Sukces daje wersję Golden (×2 mocy), a z Golden wersję Diamond (×4). Porażka zabiera wszystkie wrzucone pety. Opłata przepada zawsze: za każdego peta 1/5 ceny jajka przy Golden albo cała cena jajka przy Diamond, więc średnio Golden kosztuje zawsze 5 petów i cenę jajka. Animacja: pety krążą i zlatują się do środka, błysk, a potem nowy pet z promieniami i oklaskami (leci do PETS) albo szare odłamki i smutna trąbka. Pety z jajek premium (będą w etapie z Robuxami) łączą się tylko przy 100%.
- **INDEX:** 35 petów (5 stref × 7 rzadkości). Odkryte widać normalnie, a nieodkryte jako czarną sylwetkę z „???”. Na dole jest licznik sekretów (np. 1/5). Pet, którego jeszcze nie miałeś, ma w animacji jajka napis NEW!. Mythic wypadnie dopiero z jajek premium. Stare zapisy dostają w indeksie pety, które już mają.
- **Sekrety:** wypadają tylko ze złotego jajka (1 na 25 000). Mają specjalną animację: fioletowo-złote promienie, fioletowy błysk, „vine boom”, mocniejsze drżenie, napis SECRET PET! z „1 in 25,000” i dłuższy pokaz. Chwilę później u wszystkich graczy na wszystkich serwerach wjeżdża u góry pasek z głową awatara, np. „Nasdaq hatched a SECRET Iced Flamingo, 1 in 25,000” (u Ciebie „You hatched…”). Działa przez MessagingService. W Studio bez dostępu do API komunikat widać tylko na tym serwerze, a w Output jest wtedy ostrzeżenie.
- **Golden i Diamond** mają złoty i diamentowy kolor (kulka albo Twój model), na karcie wstążkę GOLDEN albo DIAMOND, a w nazwie słowo z przodu, np. „Golden Pigeon”. Pety za graczem też są złote i diamentowe. Żeby nie było „Golden Golden Doge”, zmieniłem 4 robocze nazwy: Golden Doge → Crypto Doge, Diamond Flamingo → Iced Flamingo, Golden Whale → Mega Whale, Diamond Griffin → Jetset Griffin. Jeśli masz już modele petów pod starymi nazwami, zmień im nazwy. We własnym modelu części, które mają zostać w swoim kolorze (np. oczy), oznacz atrybutem `KeepColor` (true).

Dźwięki w `Settings.Sounds`: `MergeFail` (nieudane łączenie, smutna trąbka), `SecretReveal` (sekret z jajka, „vine boom”) i `SecretAnnounce` (komunikat o sekrecie, gong z kabiny samolotu). Podmień je, jeśli znajdziesz lepsze.

Do testu: `/pet Rare 1 5` daje 5 Rare do łączenia, `/pet Epic 2 1 gold` daje Golden Epic, `/secret 3` daje sekreta ze strefy 3 i ogłasza go, `/mergeluck 5` ustawia Merge Luck, a `/clearindex` czyści indeks (znów są napisy NEW!).

Jeszcze nie ma: tytułu „Secret Society” za komplet 5 sekretów i rankingu „Sekrety”. Dojdą razem z tytułami i rankingami, a licznik sekretów już się zapisuje.

## Co dalej (plan etapów)

Kolejność jest jak w dokumencie projektu: najpierw pety i ubrania, potem Rebirth i Aura.

| Etap | Co |
| --- | --- |
| 6 | ✓ Gotowe: wywiad, jacht i odrzutowiec. |
| 7 | ✓ Gotowe: sprzedaż i łączenie petów, indeks i sekrety (opis wyżej). |
| 8 | Ubrania: 3 boxy w Mall (Street, Designer po odblokowaniu plaży, Iced po odblokowaniu lotniska), 7 kategorii po 1 slocie, bonus do LP, ubrania widoczne na awatarze (z opcją ukrycia), sprzedaż i łączenie jak u petów. |
| 9 | Rebirth i Aura: reset postępu za stały mnożnik LP, tytuły, teleport na spawn, +5% szybkości; Aura za Rebirthy, pasek czasu (w wywiadzie 2×) i sklep Aury (Click Boost, Luck, Aura Gain, Merge Luck), Aura Level i poświata. |
| 10 | Robux: gamepassy, produkty, boosty, jajka premium i starter pack (ID tworzysz w Creator Hub). |
| 11 | Nagrody dzienne i zadania, kody, bonus za grupę i znajomych, rankingi (LP, Rebirthy, jajka, Aura Level, sekrety), tytuły nad głową, udostępnianie zdjęć z sesji (CaptureService), poprawki przed premierą. |

Kolejność może się zmienić, jeśli coś będzie pilniejsze.

## Tryb testowy (komendy na czacie)

Działają w Studio, a w opublikowanej grze tylko dla właściciela grupy. W lewym górnym rogu widać wtedy „TEST MODE”. Odpowiedzi pojawiają się na czacie.

| Komenda | Co robi |
| --- | --- |
| `/cmds` | lista komend |
| `/cash 1.5M` | dodaje L$ (`/cash -100` odejmuje) |
| `/lp 500` | dodaje LP do Bag, także ponad pojemność |
| `/fill` | napełnia Bag do pełna |
| `/sell` | sprzedaje Bag od razu, bez chodzenia na Sell |
| `/click 20` | ustawia poziom Click Multipliera (0–150) |
| `/bag 10` | ustawia poziom Bag (0–35) |
| `/max` | wszystko na maksa: strefy 1–5, Click 150, Bag 35, najlepsze auto, jacht i odrzutowiec (L$ bez zmian) |
| `/zone 3` | ustawia ostatnią kupioną strefę (1 = tylko start) |
| `/tp 4` | teleportuje do strefy (mnożnik działa tylko w kupionej); `/tp sell` na pole Sell |
| `/speed 60` | prędkość chodzenia (16 = normalnie, po odrodzeniu wraca) |
| `/time 0` | pora dnia dla wszystkich (0 = noc, 14 = dzień) |
| `/tier yacht 3` | ustawia tier aktywności: `car` 1–5, `yacht` 1–5, `jet` 0–3 (0 = bez odrzutowca) |
| `/pet Legendary 2` | daje peta (rzadkość i strefa); dalej ile sztuk i poziom, np. `/pet Rare 1 5` (5 do łączenia) albo `/pet Epic 2 1 gold` (`gold`, `diamond`) |
| `/pet all 3` | daje po jednym pecie z każdej rzadkości ze strefy 3 |
| `/secret 3` | daje sekreta ze strefy 3 i ogłasza go wszystkim (na wszystkich serwerach, gdy działa MessagingService) |
| `/mergeluck 5` | ustawia ulepszenie Merge Luck (0–5, +1 pkt proc. na peta przy łączeniu) |
| `/clearpets` | usuwa wszystkie pety (indeks zostaje) |
| `/clearindex` | czyści indeks petów (zostają w nim pety, które masz), żeby znów zobaczyć NEW! |
| `/odds 10000 1 B` | losuje na próbę 10 000 złotych jajek ze strefy 1 i pokazuje, co wypadło (bez L$ i bez petów) |
| `/luck 20` | ustawia ulepszenie Luck (więcej losowań na jajko, wygrywa najrzadszy pet) |
| `/rebirth 3` | ustawia liczbę Rebirthów (poziom najwyżej 10) |
| `/aura 500` | ustawia Aurę |
| `/pass AutoSell` | włącza albo wyłącza gamepass (`all`, `none`), np. `/pass TripleOpen` dla Buy 3. Zostaje na kolejne testy, a `/reset` go czyści |
| `/stats` | pokazuje zapis |
| `/reset` | czyści zapis, jak u nowego gracza |

Liczby można pisać z sufiksami: `1.5K`, `2M`, `3T`, `1e12`.

## UI i ikony

Styl jak w Pet Simulator 99: nasycone kolory, białe okna z delikatnym szarym wzorem ikon „inwestowania”, grube ciemne obrysy i przyciski z wypukłą krawędzią. Komunikaty i podpowiedzi to sam biały tekst z obrysem i ikonami (bez tła), a ważne słowa mają kolor (np. czerwone SELL, zielona liczba LP). Kod UI buduje go z klocków w `src/client/Ui/Kit.luau`, kolory i rozmiary są w `src/client/Ui/Theme.luau`, a wzór w `src/client/Ui/Pattern.luau` (rysowany z kształtów, nic nie trzeba wgrywać). Pierwszy szkic był na kanwie „Larp in Miami — UI”.

Wszystko, co podmieniasz bez programowania, jest w `src/shared/Config/Settings.luau`:

- **Własne ikony z Toolboxa** (`Ui.Icons`): ID Decala albo obrazka, np. `Bag = 112098959943734`. Gra pokazuje je przez miniaturę Roblox, więc działa i Decal, i obrazek. `SellCash` to banknot z animacji sprzedaży.
- **Dźwięki** (`Sounds`): `Button` (domyślny dźwięk przycisków), `Click` (klikanie na LP), `Sell` (sprzedaż), `BagFull` (Bag się zapełnił), `BagFullClick` (klik przy pełnym Bag), `NotEnough` (brak L$), `Unlock` (kupno strefy albo auta), `Reward` (oklaski na koniec sesji zdjęciowej i przy rzadkim pecie), `Photo` (migawka przy fleszu), `Hatch` (nowy pet z jajka), `Crack` (pęknięcie jajka), `CashPop` i `CashTick` (banknoty przy sprzedaży), `JetEngine` (silnik odrzutowca), `JetMusic` (muzyka w locie), `JetCabin` („ding” w kabinie), `PartyMusic` (muzyka na jachcie), `PartyHorn` (trąbka na koniec imprezy), a w wywiadzie `InterviewMusic` (muzyka talk show), `AnswerTick` (zegar), `ReactBoom`, `ReactLaugh`, `ReactCrickets`, `ReactBruh` (reakcje studia), `Comment` (komentarz w czacie), `ClipPosted` („whoosh”), `InterviewFlop` (smutna trąbka) i `AnswerPick` (wybór odpowiedzi, na razie bez ID, więc gra `Button`). `Ids` zamiast `Id` to kilka wersji jednego dźwięku (gra losowa, np. 3 śmiechy). `Looped` gra dźwięk w pętli do końca sesji, `FadeIn` to ile sekund rośnie do pełnej głośności, a `FadeFrom` od jakiej części zaczyna (0 = od ciszy). `Start` pomija ciszę na początku pliku (od której sekundy grać). `Length` i `FadeOut` skracają dźwięk: gra najwyżej `Length` sekund i przez ostatnie `FadeOut` sekund cichnie. `Volume` 0.5 to normalna głośność, 1 to głośno, a cichy plik może dostać więcej (do 10). `Rise` przy `Click` sprawia, że klikanie pod rząd brzmi coraz wyżej: `Step` to ile półtonów w górę na klik, `Max` to sufit (12 = oktawa), a `Reset` to ile sekund przerwy wraca dźwięk do normy.
- **Wzór w tle** (`Ui.Pattern`): puste = wzór z kształtów; ID obrazka = kafelkowany obrazek.

Ikony bez własnego ID biorą się z arkusza `assets/icons/larp-icons.png` (16 ikon), a dopóki nie jest wgrany do Roblox, są emoji. Żeby go wgrać:

1. W Studio otwórz **Asset Manager** (zakładka Home albo menu Window).
2. Po lewej wybierz inwentarz gry (**Project**) albo grupy, bo gra należy do grupy.
3. Kliknij przycisk importu i wybierz plik `larp-icons.png` z folderu projektu (`assets\icons`).
4. Gdy obrazek pojawi się na liście (po krótkiej moderacji), kliknij go prawym przyciskiem → **Copy Asset ID**.
5. Wyślij to ID Claude. Trafi do `src/shared/Config/Settings.luau` (`Ui.IconSheet`).

Nowa ikona: dopisz ją w `tools/build_icons.py`, uruchom go (wymaga `pip install playwright`) i wgraj arkusz jeszcze raz.

## Liczby z arkusza

Wszystkie ceny, szanse i mnożniki są w `src/shared/Config/Economy.luau`. Tego pliku nie edytuj ręcznie, bo powstaje z modelu ekonomii:

```powershell
python tools/gen_config.py   # tworzy Economy.luau od nowa
python tools/test_luau.py    # sprawdza wzory, pętlę i liczby (wymaga: pip install lupa)
```

Jeśli zmienisz coś w arkuszu, wyślij go Claude, a Config zostanie wygenerowany od nowa.

## Studio MCP (żeby Claude mógł testować grę w Studio)

1. W Studio: **Assistant → … → Manage MCP Servers** → włącz **Enable Studio as MCP server**. Na dole okna pojawi się „MCP Ready”.
2. Jeśli w **Quick connect** jest **Claude Desktop**, włącz go. Jeśli go nie ma, dodaj serwer ręcznie: w aplikacji Claude **Settings → Developer → Edit Config** i wpisz do pliku `claude_desktop_config.json`:
   ```json
   {
     "mcpServers": {
       "Roblox_Studio": {
         "command": "cmd.exe",
         "args": ["/c", "cd /d %LOCALAPPDATA%\\Roblox && .\\mcp.bat"]
       }
     }
   }
   ```
   Jeśli w pliku są już inne ustawienia, dopisz tylko wpis `Roblox_Studio` do `mcpServers` (wpisy oddziela przecinek).
3. Zamknij aplikację Claude całkowicie (prawy klik na ikonę Claude przy zegarze → Quit) i uruchom ją ponownie.
4. W **Manage MCP Servers** zielony wskaźnik pokazuje liczbę połączonych klientów.

Komenda `claude mcp add …` z Quick connect jest dla Claude Code (program w terminalu), nie dla aplikacji Claude.

Uwaga: połączony klient może czytać i zmieniać otwarte miejsca w Studio, więc podłączaj tylko Claude.
