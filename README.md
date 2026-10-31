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
| `src/shared` | ReplicatedStorage → Shared | `Config/Economy` (liczby z arkusza, generowane), `Config/Settings` (ustawienia gry, edytowane ręcznie), `Data/Template` (szablon zapisu gracza), `Logic/Loop` (klik, Bag, Sell, ulepszenia), `Logic/RateLimiter`, `Formulas`, `Format`, `Net` (zdarzenia sieciowe), `Tests` |
| `src/server` | ServerScriptService → Server | `Main` (start serwera), `ConfigCheck` (testy w Studio), `Services/` (DataService, GamepassService, LoopService, AdminService), `Vendor/ProfileStore` (zapis danych) |
| `src/client` | StarterPlayerScripts → Client | `Main` (start gracza), `Hud` (interfejs), `ClickInput` (klikanie), `State` (stan od serwera), `Admin` (komendy testowe) |
| `tools` | — | `gen_config.py` (tworzy Config z modelu ekonomii), `test_luau.py` (testy bez Roblox), `economy/` (model i symulacja) |
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
LoopCheck: OK (39 testów pętli: klik, Bag, Sell, ulepszenia)
[Dane] TwojNick: zapis wczytany (DataStore: Access)
```

## Etap 2: rdzeń pętli

Co działa: klikanie (myszą albo krótkim dotknięciem ekranu), LP trafiają do Bag, pole Sell zamienia LP na L$, przycisk SELL przenosi na pole Sell, ulepszenia Click Multiplier i Bag (Kup 1 i Kup max), zapis postępu, leaderstats (L$ i Rebirthy), podpowiedzi dla nowego gracza i tryb testowy.

**Pole Sell.** Jeśli na mapie nie ma pola Sell, serwer stawia tymczasowe zielone pole obok spawnu. Gdy zbudujesz prawdziwe, nazwij część (Part) podłogi pola `SellPad` albo dodaj jej tag `SellPad` (Properties → Tags). Wtedy tymczasowe pole przestanie się pojawiać.

**Zapis danych.** Studio z włączonym „Enable Studio Access to API Services” zapisuje do prawdziwego DataStore tej gry. Dopóki gra nie jest publiczna, to nic złego, a test „wyjdź i wróć” działa w Studio: Stop, potem znowu Play. Jeśli w Output jest `DataStore: NoAccess`, włącz ten przełącznik (File → Experience Settings → Security).

**Ustawienia** (limit kliknięć, nazwa DataStore, admini) są w `src/shared/Config/Settings.luau`.

### Tryb testowy (komendy na czacie)

Działają w Studio, a w opublikowanej grze tylko dla właściciela grupy. W lewym górnym rogu widać wtedy „TEST MODE”. Odpowiedzi pojawiają się na czacie.

| Komenda | Co robi |
| --- | --- |
| `/cmds` | lista komend |
| `/cash 1.5M` | dodaje L$ (`/cash -100` odejmuje) |
| `/lp 500` | dodaje LP do Bag, także ponad pojemność |
| `/click 20` | ustawia poziom Click Multipliera (0–150) |
| `/bag 10` | ustawia poziom Bag (0–35) |
| `/rebirth 3` | ustawia liczbę Rebirthów (poziom najwyżej 10) |
| `/aura 500` | ustawia Aurę |
| `/pass AutoSell` | włącza albo wyłącza gamepass do końca testu (`all`, `none`) |
| `/stats` | pokazuje zapis |
| `/reset` | czyści zapis, jak u nowego gracza |

Liczby można pisać z sufiksami: `1.5K`, `2M`, `3T`, `1e12`.

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
