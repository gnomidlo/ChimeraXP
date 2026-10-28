# ChimeraXP — AutoExp dla Chimery 5.x

Publiczny, niezależny projekt automatycznego patrolu PvE dla Mudleta i oficjalnej Chimery 5.x. Nie jest częścią ChimeraVIP ani oficjalnej Chimery. Wersja **0.6.0-beta.1** — testowa, **nie uruchamiaj bez nadzoru**.

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

## EXP + zarobek — planowanie kursu (beta.12)

Nowa diagnostyczna komenda `/exp zarobek trasa` **niczego nie wysyła do serwera** i nie uruchamia chodzika. Korzysta z istniejących tagów `/room sklep` i `/room bank` poprzez oficjalny moduł `locations`; wybiera najbliższy osiągalny sklep i najbliższy bank *od sklepu*. Weryfikuje GMCP hash celu, numery pokoi na mapie i koszt trasy `walker.cost`. Pokazuje także możliwość powrotu do pierwszego pokoju trasy expa, ale docelowo pełny automat wróci do faktycznego miejsca przerwania.

`/exp zarobek diagnoza` pokazuje `gmcp.Char.Vitals.encumbrance` jako **surową wartość**, jeśli jest dostępna. Wynik np. `13` nie dowodzi jeszcze, że oznacza `13%` — przed autonomicznym kursem trzeba potwierdzić skalę i aktualizację po podnoszeniu.

**Handel, bank i podnoszenie łupów nadal nie są automatyczne.** Są planowane w [issue #8](https://github.com/gnomidlo/ChimeraXP/issues/8); nie należy włączać ich przed sprawdzeniem komunikatów sukcesu i odmowy.

## Poprawka integracji z tagami /room (beta.13)

W beta.12 `/exp zarobek trasa` wyświetlało „Modul locations nie jest dostepny”, ponieważ AutoExp wywoływał `ctx:use("locations")` **bez wpisania `locations` do `deps`**. W beta.13 moduł `locations` jest wymaganą zależnością, tak samo jak we wtyczce Kurier oficjalnej Chimery. Test integracyjny weryfikuje, że wszystkie użycia `ctx:use()` mają zadeklarowane zależności.

Po instalacji wykonaj `/przeladuj`, a następnie `/exp zarobek trasa`. Jeśli oficjalna Chimera nie ma uruchomionego modułu locations, AutoExp może odmówić uruchomienia — wtedy sprawdź diagnostykę `/chimera bledy`. Tagowanie `/room` jest obsługiwane przez oficjalną Chimerę; nie kopiujemy jej bazy do ChimeraXP. Nadal **nie ma automatycznego handlu ani podnoszenia łupów**.


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

## Szybszy EXP + zarobek (beta.15)

Zamiast 3-sekundowych przerw między sprzedażą, `wem`, `zdenominuj` i powrotem po `wlm`, używamy teraz domyślnie **0,7 s**, zachowując ścisłą kolejność. Zbieranie kolejnych przedmiotów z ciał: **0,7 s** zamiast 2 s. Po ostatniej próbie zebrania czekamy **0,7 s** zamiast 2 s na GMCP obciążenia. Przy włączonym zarobku start zbierania następuje po **2 s** od zakończenia walki zamiast po 7 s. Standardowy AutoExp bez zarobku zachowuje dotychczasowe 7 s na oficjalne zbieranie łupów.

Możesz dostosować odstępy **dla wybranego profilu**:

```text
/exp zarobek tempo 0.7
/exp zarobek tempo 1.2
```

Dopuszczalny zakres: 0,3–3,0 s. Zmiana konfiguracji wymaga zatrzymania lub wstrzymania patrolu. Nie skracamy limitu 20 s **oczekiwania na potwierdzenie** `zdenominuj`: `wlm` nadal rusza dopiero po jego odpowiedzi. Po `wlm` pozostała tylko krótka przerwa przed powrotem. Sama szybkość kroków chodzika jest nadal kontrolowana przez oficjalną Chimerę, nie przez ten parametr.

Uwaga: etapy `sprzedaj bronie`, `sprzedaj zbroje`, `wem` i `wlm` nadal nie mają zweryfikowanych odpowiedzi serwera. Tempo 0,7 s jest kompromisem; jeśli serwer gubi polecenia, wróć do `/exp zarobek tempo 1.2` lub `2`. Wszystkie ograniczenia dotyczące masowej sprzedaży niesionego sprzętu pozostają aktualne.

## Limit celów zamiast liczenia całej fauny (beta.16)

`/exp limit 1` pozwala na walkę, gdy na lokacji jest **jeden NPC zgodny z listą `/exp cel`**, niezależnie od obecności zwierząt i innych niecelowanych NPC. Przykład: dwa zające i jeden gnoll → atak gnolla; dwa zające i dwa gnolle → pominięcie starcia (`zbyt wiele celow EXP (2/1)`). Pod uwagę bierzemy tylko żywe, nieprzyjazne cele wskazane w ustawieniach; NPC z `/exp unikaj` nie są doliczane do limitu i nadal powodują natychmiastowe omijanie lokacji własnym mechanizmem. Zawartość lokacji pozostaje dynamiczna, bez czasowego blacklistowania. Przy wielu wpisach `/exp cel` limit jest wspólny dla wszystkich dopasowanych celów.

## Kurs handlowy przerwany przez atak (beta.17)

Gdy podczas przejścia do sklepu, banku albo z powrotem na expowisko oficjalny chodzik zatrzyma się z powodem `atak`, ChimeraXP **nie przerywa kursu**. Zachowuje cel etapu, a w razie walki próbuje przejść pojedynczymi komendami kierunków wynikającymi z mappera i wyjść GMCP. Każdy krok musi zostać potwierdzony przez `Room.Info` — nie używamy ślepych wielokrotnych komend ruchu. Jeśli po skutecznym kroku GMCP potwierdzi koniec walki, znowu uruchamia się normalny chodzik z aktualnej lokacji do zapisanego celu. Omijanie NPC i limity zwykłego patrolu nie przejmują sterowania podczas kursu. AutoExp nie rozpoczyna dodatkowych ataków.

**Zabezpieczenia:** przy niskim HP wcześniejszy awaryjny odwrót ma pierwszeństwo. Brak potwierdzenia kroku przez 2 sekundy pozwala na maksymalnie 3 próby, potem `PAUSED` z alarmem; powtarzający się cykl pokojów także kończy kurs alarmem. Ruch ręczny nadal wstrzymuje automat. Jeżeli gra nie pozwala przejść przez walkę, automat **nie może wymusić** ruchu. Istniejące warunki bezpieczeństwa transakcji pozostają bez zmian.

## Brak encumbrance = zero (beta.18)

Chimera pomija pole `gmcp.Char.Vitals.encumbrance`, gdy postać ma **0 obciążenia**. Od beta.18 brak tego pola w istniejącym `Char.Vitals` jest jednoznacznie interpretowany jako **0**, także podczas zwykłego patrolu z włączonym zarobkiem, diagnostyki `/exp zarobek diagnoza` i po powrocie z handlu. Nie będzie już fałszywego `Zarobek: brak encumbrance w GMCP` ani pauzy po udanym kursie, gdy odciążona postać nie ma pola w GMCP.

Brak całego pakietu `Char.Vitals` albo jawnie nieprawidłowa wartość `encumbrance` to nadal błąd danych — dla bezpieczeństwa nie podstawiamy w takich przypadkach zera.

## Zbieranie z każdego ciała (beta.19)

Przy włączonym `/exp zarobek wlacz` i skonfigurowanym `/exp lup dodaj bronie` AutoExp **po zakończeniu walki** wykonuje `policz ciala`, a nie pojedyncze `wez bronie z ciala`. Dopiero po odebraniu odpowiedzi serwera, np. `Doliczylas sie jednej sztuki.` albo `Doliczylas sie dwoch sztuk.`, pobiera łupy kolejno z każdego indeksowanego ciała:

```text
policz ciala
wez bronie z 1. ciala
wez bronie z 2. ciala
```

Jeżeli w profilu są także `zbroje`, dla **każdego** numeru ciała wykonuje najpierw `wez bronie z N. ciala`, potem `wez zbroje z N. ciala`. Próby są rozdzielone skonfigurowanym `/exp zarobek tempo 0.7`. Zbieranie jest jednorazowe dla każdego elementu i numeru ciała, bez ślepych powtórek. Skrypt nie opuszcza lokacji przed zakończeniem sekwencji, a dopiero potem sprawdza obciążenie i ewentualnie wykonuje dotychczasowy kurs sklep→bank→EXP.

Obsługiwane są zapisane słownie liczby **1–30** (wersje żeńska i męska) oraz odpowiadające im odpowiedzi liczbowe. Znane odpowiedzi o zerowej liczbie ciał powodują pominięcie zbierania. Brak rozpoznanej odpowiedzi na `policz ciala` przez 5 sekund powoduje `PAUSED` z ostrzeżeniem; w takiej sytuacji skrypt **nie zgaduje** liczby i nie odchodzi. Gdy serwer korzysta z innego polecenia lub formatu odpowiedzi, należy przekazać log do uzupełnienia parsera. Możesz ręcznie wykonać `/exp stop` w dowolnym momencie.

## Uszkodzony sprzęt po zbieraniu łupów (beta.20)

Po ostatnim `wez ... z N. ciala` (lub po potwierdzeniu zerowej liczby ciał) automat wykonuje **dokładnie dwa dodatkowe polecenia**, w tej kolejności:

```text
odloz zlamane bronie
odloz zniszczone zbroje
```

Polecenia są wysyłane kolejno, z przerwą ustawioną przez `/exp zarobek tempo 0.7`. Dopiero **po obu próbach odkładania** i krótkim odczekaniu na GMCP aktualizowane jest obciążenie i może zacząć się kurs sklep → bank → powrót. Dzięki temu nieprzydatne do sprzedaży, uszkodzone łupy nie obciążają postaci podczas marszu. Zatrzymanie automatu w trakcie tego etapu anuluje pozostałe komendy.

**Uwaga:** to komendy masowe, nie ograniczają się do łupów z ostatniej walki. Mogą odłożyć również inne niesione złamane bronie lub zniszczone zbroje, jeśli pasują do tych kategorii. Potwierdzenia serwera po `odloz` nie są jeszcze parsowane; wysyłana jest jedna próba na kategorię.

## Panel /exp i najbliższe expowiska (beta.21)

Samo `/exp` otwiera nowy **panel konsolowy**, bez dodatkowych okien Mudleta. W zwykłym kliencie klikalne elementy wykorzystują `cechoLink` i uruchamiają istniejące aliasy (start, pauza/wznow, stop, wybierz, ustawienia). Tam, gdzie klient nie udostępnia `cechoLink`, wyświetlana jest tekstowa komenda do ręcznego wykonania. Poprzedni tabelkowy status pozostaje pod `/exp status`.

Panel pokazuje **trzy najbliższe osiągalne expowiska**: dla każdego profilu liczy minimum `walker.cost(aktualny_pokoj_mapy, kazdy_pokoj_profilu)`, pomijając nieznane pokoje i niedostępne trasy; remis rozstrzyga nazwą. Kliknięcie nazwy uruchamia dotychczasowe `/exp wybierz NAZWA`, więc nadal obowiązuje blokada zmian przy działającym patrolu. Liczby w nawiasach kwadratowych to koszty tras z mappera, nie odległość geometryczna. Przy braku aktualnej lokacji albo tras wyświetlany jest komunikat o braku osiągalnych profili — bez zgadywania.

Sekcje: `/exp panel profile`, `/exp panel walka`, `/exp panel bezpieczenstwo`, `/exp panel handel`, `/exp panel komunikaty`. Opcje mają krótkie wyjaśnienia i odsyłacze do dotychczasowych aliasów; ustawienie limitu celów dostępne także przez przyciski `[Limit -]` / `[Limit +]` (aliasy `/exp limit-`, `/exp limit+`). Nie wszystkie parametry mają osobny klikalny edytor: dla tekstowych list i progów panel podpowiada pełną składnię aliasu — celowo unikamy niepewnego wysyłania tekstu do inputu.

### Komunikaty i historia

`/exp glosnosc quiet|normal|debug` zmienia globalny poziom wypisywania (zapamiętywany osobno od profili). Domyślny `quiet` ukrywa częste przejścia stanów `MOVING`, `WAIT_ENTITIES`, `COOLDOWN` i szczegółowe próby zbierania/handlu; `normal` pokazuje istotniejsze etapy, a `debug` pełniejsze logowanie. **Ostrzeżenia i alarmy zawsze pozostają widoczne.** `/exp log` pokazuje 40 ostatnich komunikatów zapisanych w trakcie sesji, również ukrytych. Dane logu nie są trwale przechowywane. Funkcje handlowe, progi HP i sekwencje bankowe nie zostały zmienione.

## Pływający panel Geyser 0.6.0-beta.1

`/exp` otwiera **natywne, ruchome okno `Geyser.UserWindow`**. Możesz przeciągać je za standardowy pasek tytułu systemu operacyjnego i ustawiać w dowolnym miejscu ekranu. `autoDock=false` zapobiega przypadkowemu dokowaniu, `restoreLayout=true` oraz `saveWindowLayout()` pozwalają zachować jego układ i położenie. Okno korzysta z Geyser.Label dla przycisków i paneli, bez obrazków i bez ręcznego ASCII. Jeśli środowisko nie ma Geyser, dostępny jest dotychczasowy panel tekstowy. Starszy tabelaryczny widok można wywołać przez `/exp status`.

Przycisk **—** zwija okno do **315 × 93 pikseli**, zachowując natywny ruchomy pasek tytułu. Miniatura pokazuje wybrane expowisko, **czas aktywnej sesji EXP** oraz sumę otrzymanego XP. Zielony panel oznacza działanie, bursztynowy pauzę, a dyskretny grafitowy OFF. Kliknięcie nazwy na miniaturze przełącza pauza/wznow, natomiast gdy EXP jest wyłączony — otwiera ustawienia; oddzielne `▴` zawsze rozwija okno. Czas stoi podczas pauzy i po zatrzymaniu. Nowy start resetuje czas i XP. Czas obejmuje automatyczny handel. XP sumuje tekstowe znaczniki `[123xp]` zabójstw (włącznie z drużyną), bez szacowania wartości. Liczniki są **sesyjne**, a nie historyczne.

Zakładki Geyser: **Główna, Expowiska, Walka, Bezpieczeństwo, Handel i Komunikaty**. Główna pokazuje trzy najbliższe osiągalne profile według kosztu `walker.cost` i pozwala przełączać profil po zatrzymaniu AutoExp. W pozostałych sekcjach można kliknięciem zmieniać limity, progi, tempo oraz włączanie handlu. Edycja tekstowych nazw (np. cele, omijane NPC, łupy lub nazwa profilu) wstawia gotową komendę do linii wejściowej Mudleta: można ją uzupełnić i zatwierdzić Enterem. Nowe `/exp nazwa NOWA NAZWA` zmienia nazwę bieżącego profilu bez utraty trasy. **Wszelkie zmiany profili wymagają `/exp stop`**, również gdy sesja jest tylko wstrzymana. Ostrzeżenia bezpieczeństwa pozostają w konsoli. `/exp status`, `/exp log` i `/exp glosnosc` nadal działają.

**Uwaga:** interfejs i jego zachowanie przeszły symulacje w testach Lua, ale wymaga weryfikacji w prawdziwym Mudlecie w szczególności wizualnego wyglądu etykiet Geyser oraz przywracania pozycji w systemie operacyjnym.
