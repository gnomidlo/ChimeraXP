# ChimeraXP

**Osobny, prywatny projekt AutoExp dla oficjalnej Chimery 5.x w Mudlecie.** Nie jest modułem ChimeraVIP i nie jest częścią oficjalnych skryptów. Korzysta wyłącznie z publicznego API wtyczek Chimery (`gmcp`, `mapper`, `walker`, zdarzenia `chimera.*`).

**Wydanie:** `0.5.0-beta.4` — testowe. Nie uruchamiaj patrolu bez nadzoru. Instalacja nie włącza automatu; to wymaga `/exp start`.

## Instalacja bezposrednio w Mudlecie (XML)

Pakiet **`ChimeraXP.xml`** jest na razie dostepny w zalaczniku wydania ZIP; plik XML nie zostal jeszcze opublikowany w prywatnym repozytorium. W Mudlecie otworz profil, wylacz stary `EXP` i przeciagnij pobrany `ChimeraXP.xml` na okno albo wykonaj:

```lua
lua installPackage([[C:\sciezka\do\ChimeraXP.xml]])
```

Pakiet z zalacznika tworzy `chimera_wtyczki/chimera_autoexp/init.lua`, nie modyfikuje oficjalnej Chimery ani ChimeraVIP; potem wykonaj `/przeladuj` i `/exp test`. Pakiet jest idempotentny i **nie nadpisuje nowszej wtyczki** podczas kolejnych startow Mudleta. Aktualizacje nadal mozna wykonywac przez `update.cmd` po zalogowaniu `gh auth login`.

**WAZNE: prywatne repozytorium.** Samo polecenie `lua installPackage("https://raw.githubusercontent.com/gnomidlo/ChimeraXP/main/packages/ChimeraXP.xml")` **nie zadziala** z prywatnym repo — Mudlet nie dolacza do zwyklego pobrania uwierzytelnienia GitHuba. Aby instalowac jednym poleceniem URL, trzeba publicznie udostepnic pakiet XML (co ujawni osadzony w nim kod) albo opublikowac maly publiczny loader korzystajacy z odrebnej autoryzacji. **Nie udostepniaj prywatnych tokenow w URL.**

## Instalacja Windows — z prywatnego repozytorium, bez tokenów

1. Uruchom oficjalną **Chimerę 5.x** w Mudlecie. Zrób kopię profilu i starej bazy AutoExp.
2. **Wyłącz stary pakiet/grupę `EXP` w Mudlecie** — oba skrypty rejestrują aliasy `/exp`. Nie usuwaj bazy danych.
3. Po uzyskaniu dostępu do prywatnego repozytorium wybierz na GitHubie **Code → Download ZIP**, wypakuj **cały** ZIP i kliknij dwukrotnie **`install.cmd`**. Instalator wykryje profil Mudleta lub poprosi o jego wybór.
4. W Mudlecie wykonaj **`/przeladuj`** (albo uruchom profil ponownie). Sprawdź `/wtyczki`, następnie `/exp` i **`/exp test`**.
5. Jeśli chcesz przenieść poprzednio zapisane expowiska, wykonaj **`/exp import`**. Stara baza pozostaje nietknięta. Po imporcie wybierz obszar i ponownie wykonaj `/exp test`.

> Instalator umieszcza tylko `chimera_wtyczki/chimera_autoexp/init.lua` w katalogu **wybranego profilu Mudleta**, a wersję i kopie poprzedniego kodu w jego `ChimeraXP/`. Nie modyfikuje `ChimeraVIP` ani plików oficjalnej Chimery i nie kopiuje danych sesji do repozytorium.

Można również wskazać profil bez automatycznego wyszukiwania:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\installer\ChimeraXP.ps1 -Source Local -ProfileDir 'C:\sciezka\do\profilu'
```

W Mudlecie prawidłowy katalog uzyskasz poleceniem Lua: `lua getMudletHomeDir()`.

## Aktualizacje — prywatny GitHub

Zwykłe `downloadFile()` z publicznego ChimeraVIP **nie zadziała** z prywatnym repozytorium. Dlatego aktualizacja korzysta z **GitHub CLI (`gh`) i indywidualnego konta użytkownika**, bez wpisywania ani udostępniania tokenu w Mudlecie.

1. Zainstaluj [GitHub CLI](https://cli.github.com/), zaloguj się: `gh auth login` i zaakceptuj zaproszenie do repozytorium.
2. Uruchom **`update.cmd`** z rozpakowanego katalogu repozytorium. Instalator pobierze `manifest.json` i plik wtyczki z autoryzowanego GitHub API, zweryfikuje SHA-256, a przy zmianie przygotuje kopię starej wersji.
3. W Mudlecie wykonaj `/przeladuj`.

Jeżeli nie masz już katalogu z pobranym ZIP-em, użyj kopii instalatora zapisanej w katalogu swojego profilu `ChimeraXP/ChimeraXP.ps1`:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File 'C:\sciezka\do\profilu\ChimeraXP\ChimeraXP.ps1' -Source GitHub -ProfileDir 'C:\sciezka\do\profilu'
```

**To aktualizacja na żądanie**, nie automatyczny updater działający wewnątrz Mudleta. Ponowne pobranie pliku wymaga dostępu użytkownika do prywatnego repozytorium. W trybie offline (`install.cmd`) GitHub CLI **nie jest potrzebny**.

## Komendy AutoExp

`/exp`, `/exp pomoc`, `/exp obszary`, `/exp wybierz NAZWA`, `/exp mapuj NAZWA`, `/exp mapuj! NAZWA`, `/exp mapuj-`, `/exp cel TEKST`, `/exp unikaj TEKST`, `/exp bezpieczna`, `/exp hp 35 85`, `/exp limit 3`, `/exp odnowa 60`, `/exp import`, `/exp test`, `/exp start`, `/exp pauza`, `/exp wznow`, `/exp stop`.

Zobacz [pełną dokumentację i ograniczenia](docs/AUTOEXP_5.md).

## Udostępnianie niewielkiej grupie osób

Prywatne repozytorium można udostępnić przez **Settings → Collaborators → Add people**. Użytkownicy muszą zaakceptować zaproszenie; każdy używa własnego logowania `gh auth login`. **Uwaga:** współpracownicy prywatnego repozytorium należącego do konta osobistego mogą również **zapisywać zmiany (push)**. Jeśli znajomi powinni mieć tylko **read-only**, rozważ prywatne repozytorium należące do organizacji GitHub z rolą **Read** lub ręczne udostępnianie ZIP-ów bez dostępu do źródeł repozytorium.

Nie udostępniaj nikomu własnego PAT, tokenów GitHub CLI ani prywatnych kluczy. Wtyczka nie ma wpisanych danych logowania, a instalator nie zapisuje sekretów.

## Rozwój i testy

- `packages/ChimeraXP.xml` — samodzielny pakiet Mudlet z osadzonym kodem wtyczki, do importu z pliku.

- `plugins/chimera_autoexp/init.lua` — jedyny plik uruchamiany przez oficjalny loader Chimery 5.
- `manifest.json` — jawna lista plików instalacyjnych i suma SHA-256.
- `installer/ChimeraXP.ps1`, `install.cmd`, `update.cmd` — osobny instalator offline i prywatne aktualizacje po autoryzacji.
- `tests/autoexp5_mock.lua` — test symulowanego GMCP i zdarzeń Chimery 5 (uruchom: `lua tests/autoexp5_mock.lua` jeśli masz Lua w PATH).
- `tests/test_manifest.py` — kontrola poprawności manifestu i integralności paczki (`python tests/test_manifest.py`).

**Zakres beta:** patrol, GMCP ID, mapa, progi bezpieczeństwa, sesyjny stan, import. **Nie obejmuje** handlu/banku/łupów ani panelu Geyser. Pierwsze testy wykonuj na łatwym expowisku pod nadzorem.

## Omijanie NPC (beta.3)

`/exp unikaj pajak`: jezeli aktualne GMCP `Room.Entities` pokazuje pajaka,
AutoExp nie wysyla `zabij`. Zamiast pauzowac, natychmiast probuje wyjsc
pojedynczym krokiem przez wyjscie GMCP, preferujac dalsza trase patrolu.
Probuje rowniez po agresywnym ataku pajaka: chodzik oficjalny zatrzymuje sie
w walce, dlatego do opuszczenia lokacji uzywana jest zwykla komenda kierunku.
Przez 10 minut nie prowadzi patrolu przez pokoj, w ktorym zobaczyl omijanego NPC.
Ruch jest potwierdzany przez zmiane `Room.Info`; brak potwierdzenia powoduje
proby innych wyjsc (maksymalnie 3), a ostatecznie pauze z ostrzezeniem.

Nie da sie wykryc NPC w sasiednim pokoju, dopoki GMCP nie dostarczy jego zawartosci.
Nie ma gwarancji ucieczki, jesli serwer zabrania ruchu podczas walki; nie mozna
tez powstrzymac automatycznego kontrataku postaci lub towarzysza samym AutoExp.
Ponadto AutoExp nie uzywa automatycznego chodzika podczas samej ucieczki.

Automat czeka co najmniej 7 sekund po wykryciu zakonczenia walki zanim przejdzie dalej,
aby dac oficjalnemu zbieraniu czas na wykonanie komend. Nie naprawia to blednych
komend modulu `collect` oficjalnej Chimery. Podczas testowania warto wykonac
`/zbieranie nie` (Chimera 5) i sprawdzic stary pakiet EXP oraz pozostale aliasy lootowania.

Niski poziom HP podczas rozpoczetego odwrotu nie uruchamia ponownie chodzika.


### Awaryjny odwrot (beta.4)

Przy niskim HP w walce AutoExp probuje wyjsc do ustawionej /exp bezpieczna, krok po kroku przez GMCP. Wysyla pojedyncze kierunki i czeka na potwierdzenie zmiany lokacji. Jesli MUD blokuje ruch, po ograniczonej liczbie prob wstrzymuje automat i alarmuje. **Nie gwarantuje to ucieczki**; testowac tylko pod nadzorem i ustawic konserwatywny prog HP.
