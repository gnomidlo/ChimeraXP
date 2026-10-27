# ChimeraXP — AutoExp dla Chimery 5.x

Publiczny, niezależny projekt automatycznego patrolu PvE dla Mudleta i oficjalnej Chimery 5.x. Nie jest częścią ChimeraVIP ani oficjalnej Chimery. Wersja **0.5.0-beta.11** — testowa, **nie uruchamiaj bez nadzoru**.

## Instalacja — jedna komenda w Mudlecie

W otwartym profilu Mudleta, w którym działa oficjalna Chimera 5.x, wpisz:

```lua
lua installPackage("https://raw.githubusercontent.com/gnomidlo/ChimeraXP/main/packages/ChimeraXP.xml")
```

Pakiet `ChimeraXP.xml` zawiera niewielki instalator internetowy. Instaluje plik `chimera_wtyczki/chimera_autoexp/init.lua` z publicznego GitHuba i zachowuje istniejącą konfigurację oraz profile expowisk.

Poczekaj na komunikat `[ChimeraXP] Zainstalowano AutoExp ...`, a następnie wykonaj w Mudlecie:

```text
/przeladuj
/exp
/exp odwrot-test
/exp test
```

**Wyłącz starszą grupę/pakiet `EXP`**, jeżeli masz ją w profilu: oba pakiety obsługują podobne aliasy. Nie usuwaj starych danych, jeśli planujesz `/exp import`.

### Migracja ze starszego instalatora XML

Jeśli wcześniej zainstalowałeś samodzielny, ciężki pakiet `ChimeraXP.xml` (z wbudowanym AutoExp), **jednorazowo** zastąp go nowym bootstrapem:

```lua
lua uninstallPackage("ChimeraXP"); installPackage("https://raw.githubusercontent.com/gnomidlo/ChimeraXP/main/packages/ChimeraXP.xml")
```

Nie usuwaj katalogu profilu `chimera_wtyczki/chimera_autoexp/` ani danych zapisanych przez Chimerę. Odinstalowanie starego pakietu XML nie czyści tych danych. Po pobraniu i instalacji wykonaj `/przeladuj`.

## Aktualizacje — bez ZIP-ów i bez GitHub CLI

```text
/exp aktualizuj
```

Instalator **automatycznie sprawdza aktualizacje przy uruchomieniu profilu**. Korzysta z publicznego `manifest.json` oraz `plugins/chimera_autoexp/init.lua` na gałęzi `main`. Jeśli dostępna jest nowa wersja, pobiera ją, sprawdza oznaczenie pliku, numer wersji i składnię Lua, zabezpiecza poprzedni `init.lua` w `ChimeraXP/backups/`, a następnie informuje, że należy wykonać `/przeladuj`.

**Nigdy nie wywołuje automatycznego `/przeladuj` podczas walki lub patrolu.** Aktualizator nie nadpisuje nieznanych skryptów ani nowszych wersji z innej gałęzi. Awaria internetu nie usuwa aktualnej instalacji. Zmiany w publicznym repozytorium stają się dostępne dopiero po opublikowaniu na `main`.

To źródło jest publiczne: nie trzeba się logować, używać `gh auth login` ani wpisywać tokenów. Stary instalator Windows `install.cmd` można nadal uruchomić po pobraniu całego repozytorium, ale nie jest już zalecaną metodą.

## Komendy

`/exp`, `/exp pomoc`, `/exp obszary`, `/exp wybierz NAZWA`, `/exp mapuj NAZWA`, `/exp mapuj! NAZWA`, `/exp mapuj-`, `/exp cel TEKST`, `/exp unikaj TEKST`, `/exp bezpieczna`, `/exp hp 65 90`, `/exp limit 3`, `/exp odnowa 60`, `/exp odwrot-test`, `/exp test`, `/exp start`, `/exp pauza`, `/exp wznow`, `/exp stop`, `/exp import`, `/exp aktualizuj`.

**Przed rozpoczęciem expa sprawdź `/exp odwrot-test`**. Jeżeli pokazuje jedynie `cofanie` lub `wyjscie GMCP`, automat nie ma potwierdzonej trasy do bezpiecznej lokacji. Uzupełnij mapę lub wybierz bliższy punkt odwrotu. Podczas walki niskie HP postaci lub obecnego w GMCP członka drużyny (także pachołka) inicjuje próbę awaryjnego odwrotu.

`/exp unikaj pajak` oznacza: nie zaczynaj walki z pająkiem i spróbuj opuścić pomieszczenie również wtedy, kiedy już zaatakował. Pokój pozostaje przechodni: nie tworzymy 10-minutowej ani żadnej innej czasowej blokady wejścia. Przy każdej wizycie sprawdzamy nowe dane GMCP. Identycznie traktujemy przekroczenie `/exp limit NPC` i walkę obcej osoby: omijamy bieżące starcie, nie usuwamy pokoju z mapy. Powracając do nadal niebezpiecznego pokoju, próbujemy innego wyjścia, aby nie zapętlać ślepego zaułka. Zawartość sąsiednich lokacji nie jest z góry znana. Gra może samodzielnie wymuszać/utrzymywać walkę i blokować ruch — **automat nie może zagwarantować przeżycia**.

W wersji beta nie ma automatycznego handlu, banku, łupów ani panelu Geyser. Zbieranie łupów pozostaje w oficjalnej Chimerze. Więcej informacji: [docs/AUTOEXP_5.md](docs/AUTOEXP_5.md).

## Jak to działa

- `packages/ChimeraXP.xml` — niewielki pakiet do instalacji z URL, którego zawartość pochodzi z `installer/mudlet_updater.lua`.
- `installer/mudlet_updater.lua` — niezależny od API Chimery instalator i updater bazujący na `downloadFile()` oraz zdarzeniach `sysDownloadDone`/`sysDownloadError`.
- `plugins/chimera_autoexp/init.lua` — rzeczywisty AutoExp 5.x, ładowany przez oficjalną Chimerę po `/przeladuj`.
- `manifest.json` — wersja wydania i SHA-256 źródła; zgodność sprawdzana w testach wydania.
- `tests/` — testy integracyjne symulujące GMCP i test instalatora (offline).

Instalator nie zapisuje haseł ani tokenów, nie usuwa danych expowisk i nie ingeruje w ChimeraVIP. Przy każdej aktualizacji kodu należy podnieść wersję w źródle i w manifeście oraz zachować zgodność XML z `installer/mudlet_updater.lua`.

`/exp odnowa` nadal określa jedynie, kiedy ponownie farmić **sprawdzony pusty** pokój; nie zakazuje przechodzenia przez niego. Beta.9 nie blokuje tras z powodu ruchomych NPC.

## Ucieczka i walki innych graczy (beta.10)

Gdy **inny gracz walczy już przy naszym wejściu** i nasza drużyna jeszcze nie walczy, AutoExp pomija starcie i próbuje opuścić pokój. Jeżeli obcy gracz **dołączy podczas naszej walki** (także tuż po wysłaniu `zabij ID`), nie wymuszamy ucieczki tylko z tego powodu. W przypadku niskiego HP nadrzędny pozostaje awaryjny odwrót.

Ucieczka przed omijanymi NPC lub nadmierną liczbą mobów używa wspólnej pamięci bieżącej serii niebezpiecznych pokoi. Powrót do takiego pokoju jest dopuszczany tylko, gdy znamy stamtąd jeszcze niewykorzystane wyjście. Wykryta pętla kończy serię ruchem **STOP / PAUSED** z alarmem — nie próbujemy bez końca dwóch kierunków. Pokoi nadal nie blokujemy czasowo. Po opuszczeniu zagrożonego obszaru albo podjęciu poprawnej walki pamięć serii jest czyszczona.

**Nie testowano na żywym serwerze**. Sprawdź najpierw na słabym expowisku pod nadzorem.

## EXP + zarobek — etap 1 (beta.11)

Ten etap jest **bezpieczną diagnostyką i konfiguracją**, nie uruchamia automatycznego podnoszenia przedmiotów, handlu ani przelewów. Plan pełnego cyklu: [issue #8](https://github.com/gnomidlo/ChimeraXP/issues/8).

```text
/exp lup dodaj miecz
/exp lup dodaj tarcze
/exp lup lista
/exp lup usun miecz
/exp zarobek prog 75
/exp zarobek diagnoza
```

Lista łupów i próg są zapamiętywane **oddzielnie dla każdego profilu expowiska**. `/exp zarobek diagnoza` nic nie wysyła do MUD-a: wyświetla numeryczne pola GMCP sugerujące wagę/udźwig oraz identyfikatory potencjalnych ciał z Room.Entities. Jeśli brak właściwego pola, nie zgadujemy obciążenia. Do sprawdzenia tagów użyj istniejących `/room lista sklep` i `/room lista bank`.

**Nie uruchamiaj automatycznej sprzedaży** do czasu weryfikacji źródła udźwigu i komunikatów serwera po `wez ... z ciala`, `sprzedaj bronie/zbroje`, `wem`, `zdenominuj`, `wlm`. Komendy sprzedaży wszystkich broni/zbroi mogą też objąć przedmioty osobiste. Dopiero następny etap wprowadzi ochronę przed przypadkową sprzedażą.
