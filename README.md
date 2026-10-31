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
| `src/shared` | ReplicatedStorage → Shared | `Config/Economy` (wszystkie liczby z arkusza), `Formulas` (wzory), `Format` (zapis 1.5K, 937.5Qa), `Tests/ConfigSpec` |
| `src/server` | ServerScriptService → Server | `Main` (start serwera), `ConfigCheck` (test liczb, tylko w Studio) |
| `src/client` | StarterPlayerScripts → Client | `Main` (start gracza) |
| `tools` | — | `gen_config.py` (tworzy Config z modelu ekonomii), `test_luau.py` (testy bez Roblox), `economy/` (model i symulacja) |

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
5. Opcjonalnie: VS Code z rozszerzeniami **Rojo** i **Luau Language Server**, jeśli chcesz zaglądać w kod.

## Pierwsze uruchomienie (test Etapu 1)

1. Otwórz w Roblox Studio grę grupy „Larping Studio$”. Nową grę tworzysz przez File → Publish to Roblox, a jako twórcę wybierasz grupę.
2. W PowerShell w folderze projektu wpisz `rojo serve` i zostaw okno otwarte.
3. W Studio: zakładka **Plugins → Rojo → Connect**.
4. Kliknij **Play** i otwórz okno **Output** (View → Output). Powinno się tam pojawić:
   ```
   [Larp in Miami] Serwer działa. Ekonomia v2 (arkusz z 29.10.2026). Strefa 5 kosztuje 3T L$, Rebirth 10 kosztuje 750Qa L$.
   ConfigCheck: OK (64 testów zgodnych z arkuszem)
   [Larp in Miami] Klient gotowy: TwojNick, ekonomia v2 (arkusz z 29.10.2026)
   ```
   Jeśli widzisz te trzy linie, Etap 1 jest skończony.

## Codzienna praca

1. `git pull`, żeby pobrać nowy kod.
2. `rojo serve` i w Studio Rojo → Connect.
3. Budujesz i testujesz w Studio, a grę zapisujesz normalnie (Ctrl+S albo Publish).

## Liczby z arkusza

Wszystkie ceny, szanse i mnożniki są w `src/shared/Config/Economy.luau`. Tego pliku nie edytuj ręcznie, bo powstaje z modelu ekonomii:

```powershell
python tools/gen_config.py   # tworzy Economy.luau od nowa
python tools/test_luau.py    # sprawdza wzory i liczby (wymaga: pip install lupa)
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
