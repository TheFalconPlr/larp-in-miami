# Larp in Miami — notatki dla Claude

Gra Roblox (clicker/simulator) dla Denyy (konto Roblox TheFalconPlr, grupa „Larping Studio$”). Rozmowy, komentarze w kodzie, README i odpowiedzi trybu testowego po polsku. Teksty w grze (UI) po angielsku.

## Układ (Rojo, `default.project.json`)
- `src/shared` → ReplicatedStorage.Shared: `Config/Economy` (generowany), `Config/Settings` (ręczny), `Data/Template` (zapis gracza), `Logic/*` (czysta logika), `Formulas`, `Format`, `Net`, `Tests/*Spec`
- `src/server` → ServerScriptService.Server: `Main` uruchamia `Services/*` (Data, Gamepass, Loop, Admin); `Vendor/ProfileStore` (1.0.3, Apache 2.0, licencja w `licenses/`)
- `src/client` → StarterPlayer.StarterPlayerScripts.Client: `Main`, `Hud`, `ClickInput`, `State`, `Admin`
- Mapę, modele i wygląd UI użytkownik buduje w Studio. Skrypty są tylko w plikach, bo Rojo nadpisuje je w Studio.

## Zasady
- `src/shared/Config/Economy.luau` generuje `python tools/gen_config.py` z modelu w `tools/economy/` (`final_cfg2.py` to ceny v2). Nie edytuj go ręcznie: zmień model i wygeneruj plik od nowa.
- `python tools/test_luau.py` (wymaga `pip install lupa`) kompiluje każdy plik `.luau` poza folderami `Vendor` w Lua 5.1, uruchamia ConfigSpec i LoopSpec i porównuje wzory z modelem w Pythonie. Dlatego nasz kod piszemy w składni zgodnej z Lua 5.1: bez adnotacji typów, `continue`, `+=`, `//`, wyrażeń `if … then … else` i interpolacji w backtickach, a pętle po tabelach zawsze przez `pairs`/`ipairs`. Test uruchamiaj przed każdym commitem.
- Moduły w `Shared/Logic` to czysta logika bez Roblox API (testowalna w lupa). Serwer jest jedynym źródłem prawdy: klient tylko prosi przez `Net` i pokazuje stan z `Sync`.
- Nowe pola zapisu dodawaj w `Data/Template` (Reconcile je uzupełni). Zmiana znaczenia pola wymaga migracji w `DataService` (`MIGRATIONS`, podbij `Version`).
- Zaokrąglenia jak w arkuszu: połówki w górę (`math.floor(x + 0.5 + 1e-9)`), nie bankierskie.
- UI w stylu Pet Simulator 99 (nasycone kolory, nie pastele; białe okna z szarym wzorem ikon „inwestowania” z `Ui/Pattern.luau`). Budujemy go w kodzie z klocków `src/client/Ui/Kit.luau` (napisy z obrysem, przyciski z krawędzią, kafelki, okna; komunikaty, podpowiedzi i napisy na pasku Bag to sam tekst z obrysem i ikonami, bez białego tła: `Kit.line`), kolory w `Ui/Theme.luau`, rozmiary w pikselach bazowych 1280×720 (UIScale w Hud). Nie używaj CanvasGroup pod UIScale (ucina zawartość). Ikony: najpierw własne z Toolboxa (`Settings.Ui.Icons`, ID Decala albo obrazka, pokazywane przez `rbxthumb://type=Asset`), potem arkusz `assets/icons/larp-icons.png` (`Settings.Ui.IconSheet`, `tools/build_icons.py`), na końcu emoji. Dźwięki w `Settings.Sounds`, odtwarza `Ui/Sounds.luau` (przyciski Kit mają domyślnie dźwięk „Button”).
- Nowy kod trafia na gałąź `main`. Użytkownik pobiera go przez `git pull`, a `rojo serve` przenosi go do Studio.
