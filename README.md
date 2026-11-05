# ChimeraXP — wyprawy, role drużyny i auto-zarobek

**0.7.0-beta.14** dla Mudleta i oficjalnej Chimery **5.x**. Wspólny, zwięzły górny HUD łączy patrol ChimeraXP z przebudowaną taktyką wywodzącą się z Tacticus NG beta.15. Wizualnie uzupełnia ChimeraVIP; nie wymaga ChimeraVIP do działania.

## Beta.13 — priorytety walki

Kolejność listy celów obowiązuje także podczas trwającej walki. Wyższy priorytet przejmuje cel po przybyciu; równorzędni przeciwnicy nie powodują przełączania. Przekroczenie limitu podczas walki uruchamia powrót do saferoom.

## Beta.12 — powrót do saferoom

Po pierwszym omijaniu kolejna przeszkoda uruchamia powrót do saferoom, regenerację i ponowienie patrolu. Słaby agresor w schronieniu nie powoduje ucieczki. Powrót wymaga zakończenia walki, progów HP, minimum 30% sił i przerwy 30–150 s. Brak drogi powoduje alarm i nadzorowane ponawianie co 30 s. Ręczna pauza i STOP pozostają nadrzędne. Limit dotyczy celów XP, a cudze walki są nadal omijane.

## Szybka instalacja w Mudlecie

W profilu z zainstalowaną oficjalną Chimerą **5.x** wklej do linii poleceń Mudleta:

```lua
lua installPackage("https://raw.githubusercontent.com/gnomidlo/ChimeraXP/main/packages/ChimeraXP.xml")
```

Po zakończeniu pobierania wykonaj `/przeladuj`, a następnie `/exp`, aby otworzyć menu expowisk. Pakiet pobiera aktualną wersję z gałęzi `main` i sprawdza aktualizacje przy uruchomieniu profilu. Ręcznie sprawdzisz je poleceniem `/exp aktualizuj`.

Po uruchomieniu skryptów patrol i taktyka są wyłączone. Wydanie ma testy automatyczne Lua 5.1/5.4; zachowanie serwerowych komend i wygląd Qt/Geyser wymagają jeszcze próby w działającym Mudlecie.

## 0.7.0-beta.7 — szybsza koncentracja drużyny

- Koncentracja ma pierwszeństwo przed zwykłym równoważeniem osłon, aby rutynowa osłona nie zajmowała najpierw wspólnego odstępu rozkazów. Pilna i priorytetowa ochrona nadal wygrywa.
- Nowe ID pachołka wprowadza tylko 1 s stabilizacji celu zamiast 15 s; zachowujemy istniejące ręczne blokady i odstępy po wysłanych poleceniach. Blokada osłon pozostaje niezależna.
- Kontrola po GMCP i co 0,5 s pozostaje aktywna przez całą walkę. Rozkaz drużynowy jest ponawiany najwcześniej po 15 s, tylko jeśli cele nadal się różnią lub ktoś nie atakuje. Po włączeniu AUTO nadal obowiązuje początkowa bariera 5 s i komplet świeżych danych.
- Gdy nikt nie wykonuje manewru, `/exp taktyka status` i menu Taktyka wskazują osoby bez wspólnego celu oraz blokadę rozkazów, wymagane ustawienia lub brak przywództwa.
- Regresje odtwarzają oba zrzuty GMCP użytkownika: wspólny cel całej drużyny oraz bezczynną Chasstanę. Sprawdzają zmianę ID, regularną kontrolę bez nowego zdarzenia GMCP w chwili upływu cooldownu i pierwszeństwo pilnej ochrony.

## 0.7.0-beta.6 — wspólny atak i wycofanie

- Przy włączonych AUTO, Rozkazach graczom i Rozkazach zbiorowych lider wydaje `rozkaz druzynie zaatakowac ID` również wtedy, gdy ktoś jeszcze nie atakuje. Cel to aktualny wrogi NPC atakowany przez lidera. Odstęp rozkazów drużynie: 15 s. Zgodny cel wszystkich kończy ponawianie.
- Samo niskie HP, ogłuszenie lub rzucanie czaru członka nie blokuje rozkazu koncentracji całej drużyny. Pozostają wymagane świeże GMCP, obecność, zgoda na automatykę i brak rezerwy/ręcznej blokady. Osłony mają pierwszeństwo.
- Wycofanie `wycofaj sie za ID` ma pełne 15 s od próby; komunikat gotowości zasłony nie skraca tej blokady. Nieudana próba nadal zużywa odstęp.
- Odbiorca wycofania musi mieć co najmniej 70% HP lub wyższy próg swojego profilu, nie być Supportem, ogłuszonym, rzucającym czar ani pachołkiem w rezerwie lub z wyłączonym udziałem. Nadal sprawdzany jest limit po przejęciu wszystkich napastników.
- HUD i ustawienia zachowane. Testy obejmują bezczynnych członków, zgodne cele, odnowienie, STOP, zdrowie i role odbiorców.

## 0.7.0-beta.11 — ochrona przed krążeniem między lokacjami

- Niebezpieczny pokój jest zapamiętywany przez 120 s. Patrol sprawdza także pokoje pośrednie całej trasy chodzika; dwa spokojne pokoje ani rozpoczęcie innej walki nie kasują tej pamięci. Świeże, poprawne dane GMCP z danego pokoju mogą usunąć jego blokadę wcześniej.
- Przy ucieczce preferowane są przejścia do nieodwiedzonych ostatnio pokoi. Gdy wszystkie trasy patrolu prowadzą przez zapamiętane zagrożenie, automat próbuje nowego wyjścia z GMCP, również poza zapisaną trasą. Nie jest to potwierdzenie bezpieczeństwa nieznanego pokoju — po wejściu ponownie ocenia NPC.
- Obejście i ucieczka mają wspólny limit 8 prób ruchu. Brak nowego przejścia powoduje pauzę i alarm zamiast powrotów między sąsiednimi pokojami. Ze spokojnej ślepej uliczki automat nie wraca sam w znane zagrożenie; potrzebne jest przejęcie sterowania lub wznowienie po zmianie warunków.
- Pamięć dotyczy bieżącego uruchomienia i identyfikatorów lokacji, nie zmiennych ID NPC. Krytyczny odwrót, odpoczynek po zmęczeniu i własność kroków zachowują dotychczasowe zabezpieczenia.

## 0.7.0-beta.10 — kolejność celów i odpoczynek po odmowie ruchu

- Cele wybierane są według kolejności wpisów NPC, nie kolejności Entities. Wszystkie dostępne gobliny poprzedzają goblinki, a te smoki. Przy nakładających się fragmentach nazw wygrywa najdłuższy pasujący wpis (goblinka nie trafia do kategorii goblin). Trwająca walka nie jest przerywana, a unikanie NPC i limity nadal obowiązują.
- Komunikat `Jestes tak zmeczona/zmeczony, ze nie mozesz isc w tym kierunku.` podczas własnego ruchu wstrzymuje patrol, ucieczkę, awaryjny odwrót i przejście handlowe. Siły są liczone jako `100 − Char.Vitals.fatigue`.
- Wznowienie wymaga nowego odczytu Vitals po odmowie oraz minimum 30% sił poza walką albo 10% w walce. Jest też minimalne 2 s oczekiwania; brak danych nie pozwala ruszyć. Próg jest oceniany ponownie przy zmianie walki.
- Odmowa ze zmęczenia nie zużywa limitu niepotwierdzonych prób. Zachowujemy kierunek awaryjnego/handlowego kroku i cel zwykłego chodzika. STOP i pauza anulują oczekiwanie, a późniejsze GMCP nie uruchamia automatu.

## Zwięzły interfejs

```text
[Drużyna i role ▾] [● Taktyka ▾] [● Expowiska ▾]    Jaskinie grimloków · 00:24:18 · Zarobek [Ⅱ] [■] [⚙]
```

- **Drużyna i role:** obecne jednostki, Tank / Off tank / Standard / Asekuracja / Support, udział w automatyce, efektywne progi, limit przeciwników i preferencja ochrony. Pachołki mają dodatkowo zadanie: automatyczne, ochrona, wsparcie lub rezerwa.
- **Expowiska:** trzy najbliższe osiągalne tereny według mapy. Każdy zajmuje jeden wiersz z liczbą lokacji, kosztem dojścia i przełącznikiem zarobku. „Wszystkie expowiska…” otwiera osobne okno z pełną listą i stronami. Zmiana terenu wymaga STOP; zmianę auto-zarobku można wykonać także w pauzie.
- **Stan wyprawy w pasku:** nazwa rzeczywiście aktywnego profilu i czas działania po prawej, obok sterowania, bez dodatkowego rzędu. Czas obejmuje patrol, walkę, regenerację i handel. Pauza zatrzymuje licznik, nowy start go zeruje. STOP chowa szczegóły wyprawy.
- **Taktyka:** osobne włączenie AUTO, rozkazów graczom, rozkazów zbiorowych, masowej zasłony i wycofania w szyku. Podczas wyprawy manewry wykonywane są tylko w fazie walki; podczas ruchu, handlu i pauzy czekają.
- **Ustawienia:** cele, unikane NPC, schronienie, progi powrotu, łupy, tempo handlu, mapowanie, import, sesja i komunikaty.

HP drużyny pozostaje w osobnym oknie Kondycji. Dolny pasek i docki ChimeraVIP nie są przebudowywane. Rozwinięcia mają strony dla dużych drużyn i list terenów. Tekstowe nazwy uzupełnia się w linii komend, bez wykonywania kodu Lua z nazw.

Ponowne kliknięcie zakładki zamyka jej menu. Kółka przy Taktyce i Expowiskach oznaczają: szare — wyłączone, żółte — pauza lub oczekiwanie taktyki na walkę, zielone — włączone. Play uruchamia wybrany teren, a po pauzie wznawia wyprawę.

## Instalacja i aktualizacja

Najprościej użyć komendy z sekcji „Szybka instalacja w Mudlecie” powyżej — bez pobierania repozytorium. Alternatywnie z pobranego repozytorium uruchom `install.cmd`, wybierz katalog profilu Mudleta, a następnie w Mudlecie wykonaj `/przeladuj`.

Zachowano jednoplikowy format instalacji. Kod z `src/chimeraxp/` jest łączony przez `build.py` w samowystarczalny `plugins/chimera_autoexp/init.lua`; instalator nie musi pobierać dodatkowych modułów. `manifest.json` zawiera SHA-256 tego pliku.

Przed migracją:

1. Zatrzymaj `/exp stop` oraz `/tng off` i wykonaj kopię profilu Mudleta.
2. Wyłącz stary instalator XML AutoExp. Wyłącz oddzielną wtyczkę Tacticus NG, przenosząc jej katalog poza `chimera_wtyczki`; pozostaw zapisane ustawienia. Samo zamknięcie okna nie wyłącza wtyczki.
3. Zainstaluj ChimeraXP powyższą komendą lub lokalnym instalatorem i wykonaj `/przeladuj`.
4. Sprawdź role w Drużyna i role, profil terenu, schronienie i ustawienia handlu. Dopiero potem włącz wybrane automaty.

Nie usuwamy automatycznie obcych katalogów ani poprzednich ustawień. Aktywny stary Tacticus blokuje uruchomienie nowej automatyki. Ustawienia Tacticus NG są kopiowane do konfiguracji ChimeraXP tylko przy pierwszym uruchomieniu, jeżeli oficjalny magazyn udostępnia poprzedni zapis. Stan AUTO nie jest importowany.

## Polecenia

| Polecenie | Działanie |
|---|---|
| `/exp` | Expowiska w rozwijanym HUD-zie; panel tekstowy bez Geyser |
| `/exp start`, `/exp pauza`, `/exp wznow` | Sterowanie wyprawą |
| `/exp stop` | Zatrzymanie patrolu i zintegrowanej taktyki |
| `/exp taktyka on`, `/exp taktyka off` | Osobne sterowanie taktyką; również podczas gry ręcznej |
| `/exp rola ID tank` | Rola obecnej jednostki; również `offtank`, `standard`, `asekuracja`, `support` |
| `/exp hud on`, `/exp hud off` | Widoczność paska; ukrycie nie zatrzymuje automatyki |
| `/exp okno reset` | Przywrócenie HUD-u i menu expowisk |
| `/exp status`, `/exp log`, `/exp glosnosc quiet` | Stan, historia i poziom komunikatów |
| `/exp mapuj NAZWA`, ponownie `/exp mapuj NAZWA` | Rozpoczęcie/zakończenie zapisu trasy terenu |
| `/exp wybierz NAZWA` | Wybór zatrzymanego profilu |
| `/exp cel TEKST`, `/exp unikaj TEKST` | Cele i unikane NPC; warianty `cel-`, `unikaj-` usuwają wpis |
| `/exp bezpieczna`, `/exp hp ODWROT POWROT` | Schronienie i progi HP |
| `/exp zarobek wlacz`, `/exp zarobek wylacz` | Auto-zarobek wybranego terenu |
| `/exp lup dodaj TEKST`, `/exp lup usun TEKST` | Lista łupów profilu |
| `/exp zarobek prog 75`, `/exp zarobek tempo 0.7` | Obciążenie i odstęp komend handlu |
| `/exp zarobek trasa` | Sprawdzenie trasy bez ruchu i sprzedaży |
| `/exp zarobek kurs` | Rzeczywisty jednorazowy kurs handlowy, nie symulacja |
| `/exp test` | Podgląd najbliższej decyzji bez wysyłania komendy |
| `/exp aktualizuj` | Sprawdzenie aktualizacji przez bootstrap |

Dotychczasowe komendy patrolu, importu i diagnostyki pozostają dostępne. Stare położenie i rozmiar pływającego okna `geyser_ui` nie mają zastosowania do nowego górnego paska.

## Zasłony i rozkazy

Planer korzysta ze spójnego obrazu GMCP: lokacja, jednostki, drużyna i walka. Własne HP jest konserwatywnym odczytem z dostępnych źródeł. Brak danych lub walka spoza zakresu PvE wstrzymuje manewry.

Przebudowany wykonawca:

- wysyła jedną próbę naraz; nie wydaje równolegle parozkazu i rozkazu graczowi dla tego samego przeciwnika;
- oddziela wysłanie, potwierdzenie w GMCP i brak wyniku;
- zachowuje lokalne odstępy manewrów i ograniczenie odwracania świeżego przydziału;
- odrzuca wyłączonych Supportów jako automatycznie wybierany punkt odniesienia dla tanka;
- oddaje kanał postaci po ręcznym manewrze; ręczny rozkaz pachołka wstrzymuje odpowiednie działanie na 15 s, bez wyłączania jego automatyki;
- rozkazy graczom uzależnia od prowadzenia; rozkazy zbiorowe są domyślnie wyłączone;
- nie uruchamia AUTO po rozłączeniu, przeładowaniu ani imporcie ustawień.

Pachołki z zadaniem Automatycznie wyrównują swój cel do aktualnego wrogiego celu postaci, jeżeli już walczą z innym przeciwnikiem. Ochrona i osłony mają wyższy priorytet. Ręczny rozkaz ataku chwilowo wstrzymuje zmianę celu danego pachołka, ale pozostawia możliwość osłony; ręczna osłona nie blokuje wsparcia celu. Gdy adresata nie da się ustalić, przerwa obejmuje oba pachołki. Rozkazy dotyczące ekwipunku lub stanu nie wyłączają automatyki. Wspólny atak całej drużyny wymaga prowadzenia oraz włączenia „Rozkazy graczom” i „Rozkazy zbiorowe”; obejmuje tylko już walczących, gotowych uczestników.

„Wycofanie w szyku” to manewr w bieżącej lokacji, a „powrót do schronienia” to osobna operacja ruchu XP. Rola nie jest pomiarem pancerza ani obrażeń. Zasady nadal opierają się na procentach HP, liczbie napastników i zadeklarowanej polityce; szczegóły i ograniczenia opisuje [projekt reworku](docs/REWORK.md).

## Współpraca z oficjalną Chimerą i ChimeraVIP

Przed startem i wznowieniem oraz podczas ewaluacji patrolu sprawdzane są znane konflikty: stary Tacticus, oficjalny bot, autopościg, autowsparcie, hooki przed/po ruchu i po walce. Zbieranie oficjalne blokuje profil, który sam zbiera łupy w trybie zarobkowym. Ustawień oficjalnej paczki nie przełączamy potajemnie.

STOP obejmuje wykonawców ChimeraXP i jego ruch. Nie cofa polecenia już wysłanego do serwera ani nie zatrzymuje dowolnego obcego skryptu lub serwerowej automatyki. Przy konflikcie właścicieli górnego marginesu HUD oddaje przestrzeń, pauzuje patrol i wyłącza taktykę; nie zeruje marginesu innego dodatku.

**Zbieranie łupów:** po policzeniu ciał automat wysyła kolejno `wez KATEGORIA` dla całej listy łupów (podnoszenie z ziemi), następnie zbiera z ponumerowanych ciał. Przy zerowej liczbie ciał pozostaje samo podnoszenie z ziemi. Każda komenda zachowuje ustawiony odstęp.

**Auto-zarobek:** sprzedaż używa listy łupów aktywnego profilu. Dla `bronie`, `zbroje`, `kamienie` wysyła kolejno `sprzedaj bronie`, `sprzedaj zbroje`, `sprzedaj kamienie`, z ustawionym odstępem. Sprzedaż obejmuje niesione przedmioty tych kategorii. Po ostatniej komendzie kurs prowadzi do banku; pusta lista nie rozpoczyna kursu.

## Rozwój i sprawdzenie

```text
python build.py
python build.py --check
python tests/run.py
python -m unittest discover -s tests -p "test_*.py" -v
```

`tests/run.py` używa Lupa dla Lua 5.1 i 5.4; bez Lupa może użyć systemowego Lua. Testy nie łączą się z MUD-em. Obejmują istniejące scenariusze patrolu i handlu oraz nowe role, współpracę taktyki, STOP z GUI/API/CLI, odmowy, tożsamość, nową instancję lokacji, czas działania, ekonomię profili, geometrię i cykl życia HUD-u.

Źródła modułów: `engine.lua`, `tactics_model.lua`, `tactics.lua`, `integration.lua`, `hud.lua`, `init.lua`. Edytuj źródła i przebuduj wygenerowany plik przed commitem.

Poprzednia dokumentacja interfejsu beta.2 została zachowana w [archiwum](docs/LEGACY_BETA2.md). Nie opisuje obecnego górnego HUD-u.
