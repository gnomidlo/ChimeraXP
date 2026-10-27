# AutoExp 5 — silnik ChimeraXP (beta)

ChimeraXP to **osobny projekt**. Nie zależy od ChimeraVIP. Bazuje na API oficjalnej Chimery 5.x: `ctx:use('gmcp')`, `ctx:use('mapper')`, `ctx:use('walker')`, `ctx:on('chimera.*')`. Dla aktualizacji prywatnej paczki korzystaj z narzędzia `update.cmd` i własnego `gh auth login`. Instalacja jest możliwa offline z ZIP-a.

## Przed pierwszym uruchomieniem

1. Zachowaj kopię profilu Mudleta i starej bazy `<profil>/ChimeraVIP-data/autoexp.lua` lub `<profil>/autoexp_areas.lua`.
2. Wyłącz starą grupę `EXP` (XML), aby aliasy nie dublowały się.
3. Uruchom `install.cmd` w rozpakowanym repozytorium lub uruchom `installer/ChimeraXP.ps1 -Source Local` z podanym profilem.
4. W Mudlecie `/przeladuj` → `/wtyczki` → `/exp` → `/exp test`.
5. `/exp import` tylko w razie potrzeby i na pustej nowej bazie.

## Mapowanie i konfiguracja

`/exp mapuj Bagna` — start mapowania; powtórzenie zapisuje i scala trasę. `/exp mapuj! Bagna` — mapa zastępcza. `/exp mapuj-` — rezygnacja. `/exp wybierz Bagna` — wybór obszaru. `/exp cel snotling` — dopisanie celu. `/exp unikaj boss` — wykluczenie NPC. `/exp bezpieczna` — obecny pokój jako miejsce powrotu. `/exp hp 35 85` — progi odwrotu/powrotu. `/exp limit 3` — limit żywych NPC pasujących do `/exp cel`, nie ogólnej liczby istot w pokoju. `/exp odnowa 60` — cooldown pustej lokacji.

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

### Poprawki 0.5.0-beta.7

- Zachowanie `/exp unikaj ...` od beta.3: po wykryciu omijanego NPC wychodzi przez dostepne wyjscie GMCP, rowniez podczas walki, bez wysylania `zabij`.
- Po walce odczekuje minimum 7 sekund przed kolejnym krokiem; komendy lootowania wysyla wylacznie oficjalna Chimera, nie ChimeraXP.
- Odwrot rozpoczetym chodzikiem nie jest w kolko restartowany przez kolejne pakiety HP.
- Nie naprawia bledow zbierania oficjalnej Chimery. W testach mozna tymczasowo uzyc `/zbieranie nie`.

### Ucieczka z lokacji z omijanym NPC (0.5.0-beta.6)

- W pierwszej kolejnosci wyjscie do kolejnego pokoju z zapisanej trasy, dalej kierunek do dostepnej lokacji; sprawdzane sa wyjscia z aktualnego `Room.Info`.
- W trakcie walki oficjalny `walker.go` nie daje gwarancji ruchu, wiec ucieczka wysyla bezposrednio jedna komende kierunku i czeka na GMCP `Room.Info`.
- Ochrona przed spamem: 4 s na potwierdzenie kroku, do 3 prob roznymi wyjsciami, nastepnie pauza. Brak wyjsc = pauza.
- Lokacja z omijanym NPC zostaje zablokowana na 600 s, by nie wracac na nia natychmiast; znane zablokowane pomieszczenia sa odrzucane jako posrednie pokoje planowanej trasy, o ile Mudlet dostarcza `speedWalkPath`.
- AutoExp nie zleca ataku na omijanego NPC, lecz serwer moze sam uruchamiac automatyczne kontrataki / zachowania najemnikow.
- Nie ma mozliwosci przewidzenia NPC w kolejnej lokacji bez GMCP o jej zawartosci.


### Awaryjny odwrot (beta.4)

Przy niskim HP w walce AutoExp probuje wyjsc do ustawionej /exp bezpieczna, krok po kroku przez GMCP. Wysyla pojedyncze kierunki i czeka na potwierdzenie zmiany lokacji. Jesli MUD blokuje ruch, po ograniczonej liczbie prob wstrzymuje automat i alarmuje. **Nie gwarantuje to ucieczki**; testowac tylko pod nadzorem i ustawic konserwatywny prog HP.

## Poprawka beta.5 — własny krok nie oznacza przejęcia sterowania

Oficjalny numpad emituje `chimera.step.manual` także po komendzie kierunkowej wysłanej przez inny skrypt. AutoExp rozpoznaje teraz dokładnie własny, synchroniczny krok podczas `AVOID_ESCAPE` i `EMERGENCY_RETREAT`, dzięki czemu nie zatrzymuje się fałszywym komunikatem „Gracz przejal sterowanie”. Rzeczywisty ręczny krok gracza wciąż wstrzymuje automat. Sprawdzone symulacją zdarzeń; działanie na żywym serwerze nadal wymaga weryfikacji.

## Beta.6 - opoznione zdarzenie manualnego kroku

Gdy Chimera emituje `chimera.step.manual` po wyslaniu komendy przez AutoExp (np. `w` podczas `AVOID_ESCAPE`), AutoExp rozpoznaje pierwszy zgodny sygnal jako wlasny krok rowniez przez maksymalnie 2 sekundy przed potwierdzeniem nowego pokoju przez GMCP. Kolejne zdarzenie, inny kierunek lub zdarzenie poza tym oknem nadal wstrzymuje skrypt. Zachowujemy zabezpieczenie recznego sterowania, ale identyczne polecenie wpisane przez gracza jako **pierwsze** w krotkim oknie mogloby zostac pomylone z echem AutoExp - podczas testowania nie steruj recznie jednoczesnie z awaryjnym odwrotem.

Komenda `/exp` pokazuje teraz numer wersji; jesli `/exp start` wykonano podczas pauzy, wyjasnia jak uzyc `/exp wznow` lub `/exp stop`.

Nowy test `tests/autoexp_manual_event.lua` weryfikuje wywolania synchroniczne i opoznione oraz rzeczywiste przejecie sterowania. Testy sa symulacyjne, nie z realnego Mudleta.

## Awaryjny odwrot: fallback GMCP (beta.7)

Gdy przy niskim HP w walce `getPath()` nie znajduje drogi lub lokalizacja jeszcze nie istnieje na mapie, AutoExp najpierw szuka trasy w historii potwierdzonych przejsc i `Room.Info.exits`, potem cofa sie po faktycznej trasie gracza, a na koncu probuje dostepnego wyjscia z pomieszczenia. Ruch jest pojedynczy, z potwierdzeniem pokoju i kontrola ponownych prob.

Nieoczekiwana zmiana pokoju nie przerwie odwrotu: bieżąca lokacja z GMCP staje się nowym punktem startu. Brak drogi do schronienia wyzwala alarm, ale nie natychmiastowa pauze, jesli istnieje niezablokowane wyjscie.

Komenda `/exp odwrot-test` sprawdza pierwszy krok bez wysylania ruchu. Zrodlo `GMCP` lub `mapper` oznacza wykryta droge do zapisanej bezpiecznej lokacji; `cofanie` lub `wyjscie GMCP` to jedynie proba opuszczenia niebezpiecznego miejsca. To nie gwarantuje przezycia ani odleglej trasy do bezpiecznego pokoju.

Jesli serwer odrzuca ruch w walce, po dwoch probach i braku zmiany `Room.Info` automat alarmuje i oddaje sterowanie. `emergencyFallbackSteps` (domyslnie 40) ogranicza tylko kroki bez potwierdzonej drogi do schronienia; dlugie trasy `mapper`/`GMCP` nie sa przez to ucinane.

## Ruchome NPC — beta.9

`/exp unikaj TEKST`, przekroczenie `/exp limit X` i walki innych graczy powodują pominięcie bieżącej walki, ale **nie zakładają blokady czasowej pokoju**. GMCP `Room.Entities` sprawdzamy za każdym ponownym wejściem. Każdy pokój nadal może służyć jako tranzyt do dalszych punktów patrolu albo awaryjnej ucieczki. Podczas jednego patrolu zapamiętujemy kierunki, którymi wychodziliśmy z nadal niebezpiecznego pokoju, i przy kolejnym przejściu preferujemy inną drogę. Pamięć znika natychmiast po potwierdzeniu bezpiecznej zawartości pokoju lub ponownym uruchomieniu patrolu. Ograniczone ponowne próby nieudanego kroku pozostają dla bezpieczeństwa.

`minRoomRevisit` nadal dotyczy jedynie okresu odnowy pokojów już sprawdzonych jako puste; nie blokuje trasy przez te pokoje. Gdy serwer sam włącza walkę albo zabrania ruchu, nie możemy zapewnić ucieczki samym skryptem.

## Walki innych graczy i pętle ucieczki (beta.10)

- Walka obcego gracza **zastana przy wejściu**, gdy nasza drużyna nie walczy: omijamy tę walkę i próbujemy przejść dalej.
- Obcy gracz, który zaatakuje podczas naszej walki lub po wysłaniu przez AutoExp `zabij ID`: nie uruchamia wyjścia z lokacji tylko z powodu `foreign`. Własna walka i stan próby ataku mają pierwszeństwo.
- Dwie niebezpieczne lokacje nie mogą nas w nieskończoność przeganiać: pamięć kolejnych pokojów sprawdza, czy powrót do znanego zagrożenia daje nową drogę. Gdy nie ma takiego wyjścia, pojawia się alarm i automat pauzuje. Dodatkowo istnieje twardy limit kroków w jednej serii ucieczki.
- Brak czasowego blacklistowania pokojów; po rzeczywistym postępie bezpieczna historia jest czyszczona. Wcześniejsze zasady odwrotu HP mają nadrzędny priorytet.

## EXP + zarobek: diagnostyka i lista łupów (beta.11)

Wprowadzono **tylko konfigurację** per profil expowiska: `/exp lup dodaj TEKST`, `/exp lup usun TEKST`, `/exp lup lista`, `/exp zarobek prog 75`, `/exp zarobek diagnoza`. Przypisane przedmioty zachowują podaną odmianę dla planowanego `wez <tekst> z ciala`. Diagnostyka jest tylko do odczytu (GMCP Char, Inventory, Items i Room.Entities). Nie wykonuje sprzedaży i nie porusza postacią. Pełna maszyna stanów łupy→sklep→bank→powrót: https://github.com/gnomidlo/ChimeraXP/issues/8

## EXP + zarobek — plan trasy (beta.12)

`/exp zarobek trasa` — tylko odczyt tagów `locations.targets("sklep")` i `locations.targets("bank")`. Kandydat musi mieć poprawny GMCP hash i identyfikator na mapie. Algorytm sprawdza koszt `walker.cost`, wybiera najbliższy osiągalny sklep i bank osiągalny od tego sklepu, pokazuje koszty oraz przykładowy powrót na expowisko. **Nie wykonuje żadnych ruchów, poleceń handlowych ani bankowych.** Działa wyłącznie przy zgodności GMCP z mapperem. Brak tagów lub trasy jest zgłaszany jako ostrzeżenie.

Diagnostyka wyświetla surowe `gmcp.Char.Vitals.encumbrance`, **bez przypisywania skali procentowej** przed potwierdzeniem w grze.

## Poprawka /room: deklaracja locations (beta.13)

Moduł AutoExp do wywołania `ctx:use("locations")` wymaga jawnego `locations` na liście `deps`. Zgodnie z implementacją Kuriera, beta.13 deklaruje go jako czwartą zależność. Zapobiega to fałszywemu komunikatowi o niedostępności serwisu przy działających `/room sklep` i `/room bank`. Brak samego modułu w oficjalnej Chimerze jest rzeczywistym błędem zależności, który należy sprawdzić przez `/chimera bledy`.


## EXP + zarobek: pełny kurs TESTOWY (beta.14)

**UWAGA: eksperymentalne polecenia wykonują rzeczywisty handel.** Polecenia `sprzedaj bronie` i `sprzedaj zbroje` mogą sprzedać także prywatne, niesione bronie i pancerze, nie tylko łupy. Zanim uruchomisz test, odłóż cenne przedmioty i zachowaj zapas gotówki. Nie uruchamiaj bez nadzoru.

```text
/exp stop
/exp zarobek trasa
/exp zarobek kurs
```

`/exp zarobek kurs` wykonuje **jeden rzeczywisty kurs**, bez aktywowania automatycznego handlu dla profilu: zapisuje bieżący pokój GMCP, idzie do najbliższego tagowanego sklepu, wysyła `sprzedaj bronie`, po 3 s `sprzedaj zbroje`, potem idzie do najbliższego banku liczonego od sklepu, wywołuje `expandAlias("wem",false)`, po 3 s wysyła `zdenominuj`, czeka na potwierdzenie gry, wywołuje `expandAlias("wlm",false)`, po 3 s wraca do **oryginalnego pokoju** i zatrzymuje AutoExp. Brak potwierdzenia denominacji w 20 s = PAUSED i **brak** `wlm`. Przerwanie chodzika, walka, błędny pokój lub niskie HP = PAUSED / alarm. `/exp stop` zatrzymuje kurs.

Niezależne, **domyślnie WYŁĄCZONE** automatyczne kursy patrolowe włącza `/exp zarobek wlacz`. Po walce, po standardowej pauzie na łupy, dla każdej pozycji `/exp lup dodaj TEKST` próbuje kolejno `wez TEKST z ciala` i dopiero potem sprawdza `gmcp.Char.Vitals.encumbrance`. Jeżeli surowa wartość jest **większa** niż `/exp zarobek prog 75`, uruchamia kurs sklep→bank→powrót i wznowienie patrolu. Wyłącz komendą `/exp zarobek wylacz` (w stanie OFF/PAUSED).

**Aktualne ograniczenia:** nie mamy jeszcze wiarygodnych tekstowych potwierdzeń podnoszenia z ciał, obu sprzedaży ani działania `wem`/`wlm`. Dla tych etapów beta.14 wysyła pojedynczą próbę, odczekuje i kontynuuje z widocznym ostrzeżeniem. **Potwierdzenie `zdenominuj` jest obowiązkowe** (`Twoje pieniadze zostaly zdenominowane.` albo `Twoje pieniadze juz sa maksymalnie zdenominowane.`). `encumbrance` jest traktowane jako wartość progowa 0–100 do testu; skala nadal wymaga sprawdzenia w prawdziwej grze. Jeśli po kursie pozostaje powyżej progu, patrol pauzuje, zamiast jechać ponownie do sklepu.

Bez testu na żywym serwerze — sprawdź najpierw jednorazowe `/exp zarobek kurs` z bezpiecznego pokoju, pod nadzorem.

## Przyspieszenie ekonomii (beta.15)

W trybie EXP + zarobek rozpoczęcie próby zbierania następuje po 2 s od końca walki (`economyLootGrace`, domyślnie 2), kolejne próby `wez ... z ciala` są rozdzielone 0,7 s (`economyCommandDelay`), a sprawdzenie obciążenia jest kolejkowane po 0,7 s (`economyWeightWait`). Te dwie ostatnie wartości dotyczą planowanego odstępu; domyślną przerwę poleceń możesz zmienić komendą `/exp zarobek tempo 0.7` w zakresie 0,3–3,0 s. Przerwy między sprzedażami, po `wem` i po `wlm` używają tego samego parametru. Stan `BANK_DENOMINATE` nie przyspiesza przez timer: natychmiast reaguje na potwierdzenie serwera lub zatrzymuje się po 20 s bez odpowiedzi. Bez zmian w mechanizmie `walker` i w 7-sekundowej przerwie zwykłego AutoExp bez zarobku.

## Liczenie celów EXP (beta.16)

Wcześniej `target_info()` zwiększał `npc_count` dla każdego obcego NPC w pokoju, nawet jeśli nie był celem. To powodowało ucieczkę z pokoju zawierającego dwa zające i jednego gnolla przy `/exp limit 1`. Obecnie licznik obejmuje wyłącznie żywe, niefriendly NPC spełniające dopasowanie `/exp cel` i niespełniające `/exp unikaj`. Zbieramy **liczbę wszystkich takich NPC**, niezależnie od tego, czy dany cel był już zaatakowany i odrzucony jako bieżący cel (nie można przez to obchodzić limitu). Wykrycie NPC z `/exp unikaj` nadal ma osobny, wcześniejszy priorytet i uruchamia opuszczenie pokoju. `/exp limit 1`: 2 zające + 1 gnoll → atak; 2 zające + 2 gnolle → omijanie. Brak czasowych blokad pokojów.
