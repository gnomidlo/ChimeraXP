# AutoExp 5 — silnik ChimeraXP (beta)

ChimeraXP to **osobny projekt**. Nie zależy od ChimeraVIP. Bazuje na API oficjalnej Chimery 5.x: `ctx:use('gmcp')`, `ctx:use('mapper')`, `ctx:use('walker')`, `ctx:on('chimera.*')`. Dla aktualizacji prywatnej paczki korzystaj z narzędzia `update.cmd` i własnego `gh auth login`. Instalacja jest możliwa offline z ZIP-a.

## Przed pierwszym uruchomieniem

1. Zachowaj kopię profilu Mudleta i starej bazy `<profil>/ChimeraVIP-data/autoexp.lua` lub `<profil>/autoexp_areas.lua`.
2. Wyłącz starą grupę `EXP` (XML), aby aliasy nie dublowały się.
3. Uruchom `install.cmd` w rozpakowanym repozytorium lub uruchom `installer/ChimeraXP.ps1 -Source Local` z podanym profilem.
4. W Mudlecie `/przeladuj` → `/wtyczki` → `/exp` → `/exp test`.
5. `/exp import` tylko w razie potrzeby i na pustej nowej bazie.

## Mapowanie i konfiguracja

`/exp mapuj Bagna` — start mapowania; powtórzenie zapisuje i scala trasę. `/exp mapuj! Bagna` — mapa zastępcza. `/exp mapuj-` — rezygnacja. `/exp wybierz Bagna` — wybór obszaru. `/exp cel snotling` — dopisanie celu. `/exp unikaj boss` — wykluczenie NPC. `/exp bezpieczna` — obecny pokój jako miejsce powrotu. `/exp hp 35 85` — progi odwrotu/powrotu. `/exp limit 3` — limit obcych NPC. `/exp odnowa 60` — cooldown pustej lokacji.

`/exp test` nie wysyła żadnej komendy. `/exp start` uruchamia automat, `/exp pauza`, `/exp wznow` i `/exp stop` sterują nim. Domyślnie automat jest **wyłączony**.

## Migracja danych

`/exp import` odczytuje, **nie nadpisuje**, starszy plik bazy. Kopiuje nazwy expowisk, zapamiętaną trasę GMCP ID, cele, wyjątki, bezpieczną lokację i podstawowe progi. Nowa baza znajduje się w pamięci trwałej oficjalnej Chimery (`ctx:saved()` / `Database_settings.db`). Import do już wypełnionej nowej bazy jest blokowany.

Nie importujemy danych dotyczących dawnego interfejsu, handlu, bankowania, selektywnych łupów ani deklinacji nazw NPC. Atak wykorzystuje komendę `zabij <GMCP ID>`.

## Bezpieczeństwo

- Cel jest wybierany tylko po potwierdzeniu `Chimera.Room.Entities.room == Room.Info.id`.
- Odrzucamy własną drużynę, graczy, NPC na liście wyjątków i obszary okupowane przez obce walki PvE.
- Chodzik jest własnością oficjalnego modułu `walker`, a nie globalnego `amap`.
- Brak synchronizacji GMCP, rozłączenie, nieoczekiwane przerwanie chodzika, ruch ręczny czy niebezpiecznie niskie HP powodują pauzę/stop zamiast zgadywania kolejnych kroków.
- Przy niskim HP podczas **aktywnej walki** automat się wstrzymuje; nie próbuje bezwarunkowego `walker.go` w trakcie walki.
- **Nie pozostawiaj automatu bez nadzoru** na etapie beta.

## Ograniczenia

Brak handlu, bankowania i zbierania łupów. Brak panelu Geyser. Instancje o tym samym GMCP Room.Info.id mogą wymagać dodatkowej obsługi. Automat nie ponawia tego samego ataku w jednym pokoju. Wariant startu, przy którym inny chodzik już działa, powinien być testowany ostrożnie.

## Instalator — uwagi dla utrzymujących

Manifest ma schemat `1`, nazwę `ChimeraXP` i wyłącznie jeden dozwolony plik `plugins/chimera_autoexp/init.lua` oraz jego SHA-256. Skrypt Windows weryfikuje sumę SHA-256 przed zapisem; obcy istniejący `init.lua` nie jest nadpisywany. Przy zmianie zachowuje kopię poprzedniego pliku w katalogu `<profil>/ChimeraXP/backups/`. Jest to niezależny instalator — nie wymaga `loader.lua` ChimeraVIP i nie modyfikuje upstreamu.

Wersja prywatna **nie udostępnia anonimowego endpointu raw.githubusercontent.com** dla znajomych; `update.cmd` wykorzystuje `gh api` w kontekście uprawnień użytkownika. Nie udostępniaj wspólnego tokenu. Instrukcja dla znajomych w `README.md`.

## Testy

- `lua tests/autoexp5_mock.lua` — symulowane zdarzenia / GMCP / walka / ruch / bezpieczeństwo.
- `python tests/test_manifest.py` — sprawdzenie integralności pliku względem manifestu.

Wersja beta **nie była jeszcze przetestowana w rzeczywistej sesji na serwerze**. Testy jednostkowe i symulacyjne nie zastępują testów w Mudlecie.