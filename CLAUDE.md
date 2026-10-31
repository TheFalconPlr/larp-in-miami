# Larp in Miami — notatki dla Claude

Gra Roblox (clicker/simulator) dla Denyy (Roblox: Nasdaq, grupa „Larping Studio$”). Rozmowy, komentarze w kodzie i teksty w README po polsku.

## Układ (Rojo, `default.project.json`)
- `src/shared` → ReplicatedStorage.Shared (`Config/Economy`, `Formulas`, `Format`, `Tests/ConfigSpec`)
- `src/server` → ServerScriptService.Server
- `src/client` → StarterPlayer.StarterPlayerScripts.Client
- Mapę, modele i wygląd UI użytkownik buduje w Studio. Skrypty są tylko w plikach, bo Rojo nadpisuje je w Studio.

## Zasady
- `src/shared/Config/Economy.luau` generuje `python tools/gen_config.py` z modelu w `tools/economy/` (`final_cfg2.py` to ceny v2). Nie edytuj go ręcznie: zmień model i wygeneruj plik od nowa.
- `python tools/test_luau.py` (wymaga `pip install lupa`) kompiluje każdy plik `.luau` w Lua 5.1, uruchamia ConfigSpec i porównuje wzory z modelem w Pythonie. Dlatego kod piszemy w składni zgodnej z Lua 5.1: bez adnotacji typów, `continue`, `+=`, `//` i interpolacji w backtickach. Test uruchamiaj przed każdym commitem.
- Zaokrąglenia jak w arkuszu: połówki w górę (`math.floor(x + 0.5 + 1e-9)`), nie bankierskie.
- Nowy kod trafia na gałąź `main`. Użytkownik pobiera go przez `git pull`, a `rojo serve` przenosi go do Studio.
