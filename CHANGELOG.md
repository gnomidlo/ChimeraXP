## 0.7.0-beta.31 — ratowanie pachołka mimo przydzielonej roli osłony

- Poprawiono logikę `asekuracja`: przydział pierwszego pachołka do ochrony lidera nie blokuje już ratunkowej zasłony tego pachołka, gdy jego HP spada do 50% i algorytm wykrywa zagrożenie. Poprzednio próg `minion_cover_hp=50` traktował pachołka na 50% HP jak zdrowego obrońcę i zakazywał liderowi osłony.
- Reguła zachowania przydziału ochrony nadal działa dla stabilnego, zdrowego pachołka. Ratunek nadal respektuje rzeczywiste limity HP/obciążenia wykonawcy.
- Gdy planner nie znajdzie możliwości bezpiecznej zasłony, tekst decyzji Obrony wyjaśnia powód osobno dla dowódcy i pachołków: HP poniżej progu, limit napastników, cooldown, wyłączenie lub brak przydziału. Dostępny ratownik bez planu zostaje jawnie zasygnalizowany.
- Nowy test `tests/defense_ally_rescue.lua`: jeden silny mob, pierwszy pachołek HP 50%, dowódca asekuracja, stabilny vs alarmowy stan i zachowanie progu bezpieczeństwa 75%.

## 0.7.0-beta.30 — zaslony przy wielu napastnikach

- Obrona nie czeka na ponowny pakiet `Group.State` po przejsciu do nowego pokoju: niezmieniony sklad druzyny moze nie generowac nowego zdarzenia. Zanim podejmie decyzje, nadal wymaga danych `Room.Entities` i `Combat.State` z aktualnej lokacji oraz poprawnego, kompletnego snapshotu GMCP.
- Komenda `rozkaz ID zaslonic ciebie` nie wskazuje pojedynczego napastnika. Potwierdzenie sukcesu uznaje teraz przeniesienie **dowolnego z napastnikow** zaatakowanej postaci w chwili wydania rozkazu, a nie wylacznie pierwszego z listy. To ogranicza bezczynne oczekiwanie i pozwala szybciej angazowac drugiego wolnego pacholka.
- Pieciu lub wiecej napastnikow przy HP <=85% wywoluje ostrzezenie, a przy HP <=65% alarm ratunkowy nawet bez wystarczajacej historii obrazen. Osmiu slabych przeciwnikow przy pelnym HP nie powoduje alarmu.
- Wariant zbiorowy wciaz podlega limitom przejecia napastnikow; gdy nie jest bezpieczny, automat wybiera indywidualne zaslony zamiast bezczynnosci.
- Nowe testy `tests/defense_heavy_aggro.lua` odtwarzaja sytuacje: 8 przeciwnikow przy postaci, spadek 73% do 50%, 2 zdrowych wojownikow, brak powtornych danych grupy po ruchu i serwerowy wybor innego napastnika niz pierwszy na liscie.

## 0.7.0-beta.29 — Obrona 2.0: dynamika HP, gotowosc jednostek i pasek decyzji

- Obrona śledzi rzeczywisty spadek HP z GMCP (osobno ostatnie 5 i 25 sekund), rozróżnia stabilny stan, ostrzeżenie i stan ratunkowy. Silny pojedynczy cios lub szybkie zbliżanie się do 35% HP powoduje wcześniejszą próbę ratunku także przy jednym napastniku.
- Priorytet ratowania życia wyprzedza optymalizację szyku, ale nie omija granic HP, limitu przejmowanych przeciwników ani ochrony ratownika, który sam gwałtownie traci zdrowie.
- Poprawiono zachowanie roli Ochrona innych i automatycznych zadań pachołków. Przy zasłanianiu dowódcy komenda to `rozkaz <ID> zaslonic ciebie`; bezpieczna osłona całej drużyny zachowuje `rozkaz druzynie zaslonic ciebie`.
- Cooldown manewru (15 s) zapisujemy na ID **wykonawcy**, nie na rozkazującym ani na slocie P1/P2. Komunikat `<imię> jest gotow[ay] do kolejnej zmiany w szyku.` natychmiast odblokowuje tę postać. Ataki i samo wydawanie rozkazów nie nakładają 15-sekundowej blokady.
- Krótki bufor potwierdzenia GMCP pozostaje zabezpieczeniem przed powtarzaniem komend; nie blokuje na 15 s całej drużyny. Nie wymagamy cyklicznego ponawiania niezmienionego Group.State/Room.Entities w każdej 15-sekundowej przerwie.
- Pasek na górze wyświetla teraz bieżące rozumowanie Obrony obok fazy walki, zaś nazwa expowiska i czas są bliżej przycisków sterowania. Zachowano jedną wysokość 44 px i małe szerokości okna.
- Regresje `tests/defense_risk.lua` badają uratowanie postaci po gwałtownym spadku HP, niezależne cooldowny pachołków, poprawne składnie rozkazów i wariant zbiorowy.

## 0.7.0-beta.28 — szybkie przejscie po walce bez zbierania lupow

- Po **potwierdzonym przez GMCP** zakonczeniu walki AutoExp bez zarobku natychmiast kontynuuje wybor kolejnego celu lub pokoju. Nie czeka juz 7 sekund na nieaktywne zbieranie lupow.
- To samo dotyczy profilu z wlaczonym zarobkiem, ale pusta lista lupow.
- Gdy zarobek jest wlaczony i faktycznie skonfigurowano lupy, pozostaje dotychczasowa zwloka `economyLootGrace` (domyslnie 2 s) na synchronizacje cial i bezpieczne uruchomienie zbierania.
- Bez zmian pozostaja warunki bezpieczenstwa: walka musi byc zakonczona w GMCP, stan istot musi byc aktualny, ruch podlega ograniczeniom mappera i ewentualnemu odpoczynkowi.
- Regresje `tests/no_loot_combat_resume.lua` obejmuja wszystkie trzy warianty.

## 0.7.0-beta.27 — awaryjny odwrot natywnym chodzikiem, pokoj po pokoju

- `/exp stop` i przycisk STOP zatrzymuja tylko wyprawe, nie aktywna automatyke Obrona. Wylaczenie Obrony pozostaje jawne: `/exp taktyka off`.
- Kolejnosc celow `/exp cel` pozostaje nadrzedna; NPC z tego samego poziomu priorytetu sortowane sa wg rzeczywistego procentowego HP z GMCP. Remisy zachowuja obecny cel.
- Niepowodzenie zmiany celu podczas walki (oslanianie, brak potwierdzenia GMCP) **nie uruchamia odwrotu**. AutoExp pozwala walki trwac, zachowuje rzeczywisty cel na 15 s i stara sie ustawic na niego pozostala druzyne (tylko dowodca z `/exp druzyna on`). Rozkazy sa ograniczane czasowo i nie sa wysylane do niepotwierdzonych celow.
- Niepotwierdzony atak otwierajacy, gdy walka nie zaczela sie w ogole, oznacza pauze zamiast odwrotu.
- Test `tests/priority_focus_interception.lua`, regresje stopu i nieudanego ataku.


- Natywny `walker.go` prowadzi od teraz do **kolejnego pokoju trasy** wyznaczonej przez mapper, nie od razu w jednej sesji do schronienia.
- Po `chimera.walk.stopped(reason="atak")` AutoExp zachowuje docelowy numer schronienia i po potwierdzeniu pozycji GMCP/mapper uruchamia `walker.go` ponownie dla kolejnego kroku, także podczas walki.
- Opoznione potwierdzenie ruchu nie powoduje wyslania dwoch krokow ani falszywej pauzy z powodu recznej komendy.
- Zabezpieczenia: maksymalnie 4 przerwania na tej samej lokacji, najwyzej 3 odwiedziny danego pokoju podczas jednego odwrotu, inne powody przerwania bez automatycznego wznowienia.
- Oryginalne ustawienia chodzika (0,6 s i reakcja na atak) odtwarzamy dopiero po dojsciu do schronienia, przerwaniu albo zatrzymaniu AutoExp.
- Dodano regresje `tests/native_retreat_reissue.lua`.

## 0.7.0-beta.26 — schronienie na mapperze i odwrot chodzikiem

- `/exp bezpieczna` zapisuje teraz oba identyfikatory: GMCP oraz zweryfikowany numer pokoju Mudleta (`safeMap`). Stare profile z samym hashem GMCP nadal dzialaja, jesli mapper umie rozpoznac lokacje.
- Przy awaryjnym odwrocie AutoExp preferuje natywny `walker.go(numer)` (ta sama implementacja co `/idz numer`), tymczasowo ustawia opoznienie na 0,6 s i tryb ataku `ignoruj`, a po dojsciu, przerwaniu lub zatrzymaniu odtwarza poprzednie opcje. Zapis zabezpieczajacy pozwala odtworzyc je takze po restarcie Mudleta.
- Przy braku trasy natywnej pozostaje awaryjne przejscie GMCP, ale po wykryciu powracania do tych samych pokoi automat alarmuje i wstrzymuje odwrot zamiast bez konca odbijac sie miedzy pomieszczeniami.
- Puste `Room.Info.exits` wyzwala detekcje naglej ciemnosci tylko, gdy wyjscia zniknely w **tej samej lokacji aktywnego expowiska**. Puste wyjscia na trasie do sklepu lub banku nie zrywaja automatu. Komunikat `Ciemne miejsce.` pozostaje niezaleznym alarmem.
- Nowy test regresji `tests/native_shelter_mapper.lua`.

# Zmiany

## 0.7.0-beta.25

- Patrol pamięta docelowy punkt przy przechodzeniu przez pokoje pośrednie i po odpoczynku. Niespójna droga prowadząca ponownie do przebytego pokoju w tym samym odcinku wywołuje komunikat z identyfikatorami zamiast kolejnego ruchu.

## 0.7.0-beta.24

- Limit celów EXP pomija walkę w zatłoczonym pokoju. Patrol może przechodzić przez ten pokój w obie strony, także w trwającej walce. Jedyne wyjście pozostaje dostępne nawet bez znanej dalszej trasy.

## 0.7.0-beta.22

- Powrót po utracie światła kończy wyprawę w schronieniu. Przy braku drogi lub potwierdzenia ruchu XP podaje powód interwencji.
- Patrol i handel zlecają chodzikowi sąsiednie pokoje. Zagrożenie lokalne wyklucza pokój do końca obiegu.
- Ochrona podczas ręcznego ruchu i odwrotu, czasowe pierwszeństwo ręcznych rozkazów, rozróżnienie odpoczynku i alarmu w HUD.
- Regresje obejmują zapis śmiertelnego przejścia w ciemności, potwierdzone przejścia nazwane i spóźnione zdarzenia ruchu.

## 0.7.0-beta.16 — odświeżanie podczas odpoczynku

- Saferoom prosi o brakujące Room.Entities przez oficjalne refresh_entities co 5 s zamiast czekać bez końca przy pełnej regeneracji. Wznowienie nadal wymaga poprawnych danych.
- Odpoczynek w saferoom i po odmowie ruchu nie wysyła komendy `stan`. Kondycja i siły są oceniane z aktualizacji GMCP; osobne odświeżanie brakujących Room.Entities pozostaje aktywne.
- Status podaje konkretną blokadę odpoczynku (walka, dane, HP postaci/drużyny, siły) albo czas do wznowienia.
- Regresja odtwarza pełną regenerację bez pakietu lokacji i automatyczny powrót po jego odświeżeniu.

## 0.7.0-beta.15 — odwrót przez nazwane wyjścia

- Awaryjny odwrót obsługuje wyjścia GMCP takie jak `wyjscie`, także bez znanego identyfikatora celu (`false`). Nadal wysyła pojedynczy krok i czeka na potwierdzenie zmiany pokoju. Nie zgaduje wyjść, których nie ma w GMCP.
- Komunikat odwrotu nie przypisuje każdej przyczyny do niskiego HP.
- Regresje: jedyne nazwane wyjście ze znanym i nieznanym celem, brak duplikatów oraz dotarcie do schronienia.

## 0.7.0-beta.14 — sprzedaż kamieni

- Kategoria `kamienie` wysyła cztery komendy sprzedaży z normalnym odstępem, pozostałe kategorie jedną. Bank następuje po czwartej komendzie i jej odstępie. STOP i opuszczenie sklepu anulują pozostałe próby.

## 0.7.0-beta.13 — priorytety podczas trwającej walki

- Ponowny wybór celu według listy również podczas walki: przybycie wyższego priorytetu i śmierć przeciwnika nie wymagają zakończenia całej walki. Aktualny przeciwnik jest zachowany w obrębie tego samego priorytetu.
- Jedna oczekująca komenda ataku; brak potwierdzenia zmiany celu uruchamia powrót do saferoom.
- Przekroczenie limitu celów XP podczas walki uruchamia bezpośrednio powrót do saferoom. NPC spoza listy nadal nie zwiększają licznika.
- Testy obejmują yuan-ti przed ettinami, automatycznie wybraną goblinkę, stabilne cele, przybycia i wzrost do pięciu ettinów przy limicie trzech.

## 0.7.0-beta.12 — saferoom i ponowienie patrolu

- Pierwsza niebezpieczna lokacja jest omijana. Kolejna przeszkoda lub brak obejścia uruchamia powrót do saferoom zamiast pauzy. Odwrót używa pojedynczych kroków GMCP; brak drogi lub potwierdzenia uruchamia alarm i ponowną próbę po 30 s.
- Saferoom jest zaufanym schronieniem: słaby agresor nie powoduje dalszej ucieczki, a taktyka może działać podczas walki. Po walce wymagane są HP powrotu całej obserwowanej drużyny, co najmniej 30% sił oraz dane Entities. Komenda stan odświeża kondycję co 5 s.
- Po regeneracji przerwa wynosi 30 s, rośnie o 30 s przy kolejnych powrotach, maksymalnie do 150 s na wyprawę. Pamięć zagrożeń pozostaje aktywna. STOP i ręczna pauza anulują procedurę.
- Niepotwierdzony atak na żywy cel o wyższym priorytecie prowadzi do saferoom zamiast pomijania go na rzecz kolejnego typu NPC. Limit nadal liczy wyłącznie cele XP; omijanie cudzych walk zachowane.
- Testy symulowane Lua 5.1/5.4; wymagana próba w żywym Mudlecie.

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

## 0.7.0-beta.9 — podnoszenie łupów z ziemi

- Po policzeniu ciał automat najpierw wysyła po jednym `wez KATEGORIA` dla listy łupów profilu, np. `wez bronie`, `wez zbroje`, `wez kamienie`. Następnie zbiera te kategorie z kolejnych ponumerowanych ciał.
- Podnoszenie z ziemi działa także przy potwierdzonym braku ciał. Liczenie poprzedza podnoszenie, aby odpowiedź o braku przedmiotu na ziemi nie została uznana za wynik liczenia.
- Kolejka zachowuje tempo, STOP, kontrolę lokacji i obsługę błędów wysyłania. Lista jest kopiowana na początku zbierania; odłożenie uszkodzonego sprzętu następuje po wszystkich próbach zbierania.

## 0.7.0-beta.8 — sprzedaż według listy łupów

- Sklep sprzedaje wyłącznie kategorie wpisane na liście łupów aktywnego profilu, w tej samej kolejności: np. `sprzedaj bronie`, `sprzedaj zbroje`, `sprzedaj kamienie`. Jedna kategoria oznacza jedną komendę, bez dodatkowej sprzedaży zbroi.
- Lista na dany kurs jest kopiowana przy jego rozpoczęciu; powtórzone wpisy są usuwane niezależnie od wielkości liter. Pusta lub nieprawidłowa lista zatrzymuje kurs przed podróżą.
- Każda sprzedaż zachowuje ustawione tempo. Bank następuje po ostatniej komendzie i jej odstępie; STOP oraz opuszczenie sklepu przerywają kolejkę. Wysłanie komendy nie stanowi potwierdzenia sprzedaży przez sklep.
- Menu i komunikaty opisują wybrane kategorie zamiast stałej pary bronie/zbroje. Zbieranie korzysta z dotychczasowej listy łupów.

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

## 0.7.0-beta.5 — przeciwnik odszedł bez pozostawienia ciała

- Odpowiedź „Nie widzisz tu niczego takiego.” na własne `policz ciala` oznacza zero ciał; po standardowym sprzątaniu automat kontynuuje patrol zamiast pauzować po 5 s.
- Obsługa działa wyłącznie podczas oczekiwania na liczbę ciał w bieżącej lokacji, przy aktywnej i niewstrzymanej wyprawie. Nie zmienia już potwierdzonej liczby ciał ani nie wznawia automatu po STOP.
- Brak odpowiedzi nadal powoduje pauzę; testy obejmują odejście przeciwnika, wznowienie patrolu, odpowiedzi niepowiązane, duplikaty, zmianę lokacji i STOP.

## 0.7.0-beta.4 — koncentracja celu i ręczne rozkazy

- Pachołki w zadaniu Automatycznie wyrównują cel do postaci, gdy już walczą z innym wrogim NPC. Osłony zachowują wyższy priorytet.
- Ręczny parozkaz nie wyłącza automatyki pachołków. Rozpoznany adresat dostaje 15 s przerwy na odpowiedni rodzaj działania: atak/wsparcie albo osłonę. Przy niejednoznacznym adresacie przerwa obejmuje oba pachołki.
- Polecenia stanu i ekwipunku nie blokują taktyki; zmiana celu nie odbiera możliwości osłony, a ręczna osłona nie blokuje koncentracji celu.
- Wspólny atak drużyny (po włączeniu rozkazów zbiorowych) wyprzedza osobne wsparcia pachołków. Gotowość, aktualny cel PvE i ręczne blokady pozostają wymagane.
- Zmiana ID pachołka unieważnia starą próbę i nakłada przerwę także na koncentrację celu.
- Nowe regresje obejmują potwierdzenia celu, brak powtórnych rozkazów, priorytet ochrony, zakres ręcznych poleceń, wznowienie po 15 s, zmianę tożsamości i STOP.

## 0.7.0-beta.3 — jeden rząd i krótkie menu expowisk

- Nazwa terenu, czas i zarobek mieszczą się w pasku obok przycisków sterowania; bez dodatkowego rzędu i marginesu konsoli.
- Powtórne kliknięcie zakładki zamyka menu, także po wejściu w jego podmenu.
- Przy Taktyce i Expowiskach kółka oznaczają wyłączenie (szare), pauzę (żółte) i włączenie (zielone).
- Menu expowisk pokazuje trzy najbliższe osiągalne tereny według kosztu dojścia na mapie; pełna lista otwiera osobne okno z podziałem na strony.
- Każdy teren zajmuje jeden wiersz z osobnym przełącznikiem zarobku. Przeliczanie odległości następuje przy otwarciu menu i zmianie lokacji, zamiast przy każdym odświeżeniu zegara.
- Przycisk play uruchamia wybrany teren, pauza zatrzymuje czas, a kolejne play wznawia tę samą wyprawę.

## 0.7.0-beta.2 — położenie i wygląd HUD-u

- Pasek przy górnej krawędzi obszaru Mudleta (`y=0`), niezależnie od wcześniejszego marginesu konsoli.
- Zwarte, płaskie menu po lewej, wolna przestrzeń pośrodku i małe przyciski po prawej; menu otwierane pod przyciskiem.
- Etykieta AutoEXP rezerwuje miejsce nad tekstem gry; długa nazwa terenu nie usuwa zegara.
- Zmiany marginesu nie wywołują ponownego renderowania w pętli; ukrycie i przeładowanie przywracają poprzedni margines.

## 0.7.0-beta.1 — rework

- Zwięzły górny HUD w stylu ChimeraVIP: Drużyna i role, Taktyka, Expowiska, pauza, STOP i ustawienia.
- Mała etykieta aktywnego terenu z czasem wyprawy, pauzą i oznaczeniem auto-zarobku.
- Zintegrowana taktyka pochodząca z Tacticus NG beta.15; bez powielania HP drużyny.
- Jedna próba manewru naraz, filtrowanie głównego tanka, ochrona przed starym callbackiem i zachowanie ręcznego sterowania.
- Patrol i taktyka współpracują w fazie walki; taktyka czeka podczas ruchu, handlu i pauzy.
- Profile zachowane w przestrzeni `autoexp`; auto-zarobek edytowany osobno dla każdego terenu.
- Read-only wykrywanie znanych konfliktów z oficjalną Chimerą, starym Tacticusem i hookami automatyzacji.
- Modułowe źródła i powtarzalny build jednoplikowej paczki kompatybilnej z instalatorem.
- Regresje Lua 5.1/5.4 dla nowego HUD-u, koordynacji, tożsamości, STOP i instancji; zachowane testy patrolu, handlu i aktualizatora.

Wydanie przed próbą w żywym Mudlecie. Szczegóły i ograniczenia: `docs/REWORK.md`.
