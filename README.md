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
| `src/shared` | ReplicatedStorage → Shared | `Config/Economy` (liczby z arkusza, generowane), `Config/Settings` (ustawienia gry, edytowane ręcznie), `Data/Template` (szablon zapisu gracza), `Logic/Loop` (klik, Bag, Sell, ulepszenia, strefy), `Logic/RateLimiter`, `Formulas`, `Format`, `Net` (zdarzenia sieciowe), `Tests` |
| `src/server` | ServerScriptService → Server | `Main` (start serwera), `ConfigCheck` (testy w Studio), `Services/` (DataService, GamepassService, ZoneService, LoopService, ActivityService, AdminService), `Vendor/ProfileStore` (zapis danych) |
| `src/client` | StarterPlayerScripts → Client | `Main` (start gracza), `Hud` (interfejs), `Zones` (bramki, tablice, okno Unlock), `Activities` (sesja zdjęciowa z autem), `LocalHide` (ukrywanie części tylko u gracza), `Ui/Theme` (kolory, czcionka, skala), `Ui/Kit` (przyciski, kafelki, okna), `Ui/Icons` (ikony), `Ui/Sounds` (dźwięki), `Ui/Pattern` (wzór w tle), `ClickInput` (klikanie), `State` (stan od serwera), `Admin` (komendy testowe) |
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

## Codzienna praca

1. `git pull`, żeby pobrać nowy kod.
2. `rojo serve` i w Studio Rojo → Connect.
3. Budujesz i testujesz w Studio, a grę zapisujesz normalnie (Ctrl+S albo Publish).

Po **Play** w oknie Output powinny być m.in. te linie:
```
[Larp in Miami] Serwer działa. Ekonomia v2 (arkusz z 29.10.2026). Strefa 5 kosztuje 3T L$, Rebirth 10 kosztuje 750Qa L$.
ConfigCheck: OK (64 testów zgodnych z arkuszem)
LoopCheck: OK (64 testów pętli: klik, Bag, Sell, ulepszenia, strefy, aktywności)
[Dane] TwojNick: zapis wczytany (DataStore: Access)
```

## Etap 2: rdzeń pętli

Co działa: klikanie (myszą albo krótkim dotknięciem ekranu), LP trafiają do Bag, pole Sell zamienia LP na L$, przycisk SELL przenosi na pole Sell, ulepszenia Click Multiplier i Bag (Kup 1 i Kup max), zapis postępu, leaderstats (L$ i Rebirthy), podpowiedzi dla nowego gracza i tryb testowy.

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

### Tryb testowy (komendy na czacie)

Działają w Studio, a w opublikowanej grze tylko dla właściciela grupy. W lewym górnym rogu widać wtedy „TEST MODE”. Odpowiedzi pojawiają się na czacie.

| Komenda | Co robi |
| --- | --- |
| `/cmds` | lista komend |
| `/cash 1.5M` | dodaje L$ (`/cash -100` odejmuje) |
| `/lp 500` | dodaje LP do Bag, także ponad pojemność |
| `/click 20` | ustawia poziom Click Multipliera (0–150) |
| `/bag 10` | ustawia poziom Bag (0–35) |
| `/zone 3` | ustawia ostatnią kupioną strefę (1 = tylko start) |
| `/tp 4` | teleportuje do strefy (mnożnik działa tylko w kupionej) |
| `/tier car 3` | ustawia auto do zdjęć (tier 1–5) |
| `/rebirth 3` | ustawia liczbę Rebirthów (poziom najwyżej 10) |
| `/aura 500` | ustawia Aurę |
| `/pass AutoSell` | włącza albo wyłącza gamepass do końca testu (`all`, `none`) |
| `/stats` | pokazuje zapis |
| `/reset` | czyści zapis, jak u nowego gracza |

Liczby można pisać z sufiksami: `1.5K`, `2M`, `3T`, `1e12`.

## UI i ikony

Styl jak w Pet Simulator 99: nasycone kolory, białe okna z delikatnym szarym wzorem ikon „inwestowania”, grube ciemne obrysy i przyciski z wypukłą krawędzią. Komunikaty i podpowiedzi to sam biały tekst z obrysem i ikonami (bez tła), a ważne słowa mają kolor (np. czerwone SELL, zielona liczba LP). Kod UI buduje go z klocków w `src/client/Ui/Kit.luau`, kolory i rozmiary są w `src/client/Ui/Theme.luau`, a wzór w `src/client/Ui/Pattern.luau` (rysowany z kształtów, nic nie trzeba wgrywać). Pierwszy szkic był na kanwie „Larp in Miami — UI”.

Wszystko, co podmieniasz bez programowania, jest w `src/shared/Config/Settings.luau`:

- **Własne ikony z Toolboxa** (`Ui.Icons`): ID Decala albo obrazka, np. `Bag = 112098959943734`. Gra pokazuje je przez miniaturę Roblox, więc działa i Decal, i obrazek.
- **Dźwięki** (`Sounds`): `Button` (domyślny dźwięk przycisków), `Click` (klikanie na LP), `Sell` (sprzedaż), `BagFull` (Bag się zapełnił), `BagFullClick` (klik przy pełnym Bag), `NotEnough` (brak L$), `Unlock` (kupno strefy albo auta), `Reward` (oklaski na koniec sesji zdjęciowej), `Photo` (migawka przy fleszu). `Length` i `FadeOut` skracają dźwięk: gra najwyżej `Length` sekund i przez ostatnie `FadeOut` sekund cichnie. `Volume` 0.5 to normalna głośność, 1 to głośno, a cichy plik może dostać więcej (do 10). `Rise` przy `Click` sprawia, że klikanie pod rząd brzmi coraz wyżej: `Step` to ile półtonów w górę na klik, `Max` to sufit (12 = oktawa), a `Reset` to ile sekund przerwy wraca dźwięk do normy.
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
