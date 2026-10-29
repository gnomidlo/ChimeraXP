# ChimeraXP 0.7: kontrakty i granice reworku

Wydanie przenosi sprawdzany wcześniej patrol do osobnego modułu, łączy go z przebudowanym wykonawcą Tacticusa i wdraża zaakceptowany wariant zwięzłego HUD-u. Nie wymaga modyfikacji repozytoriów oficjalnej Chimery ani ChimeraVIP.

## Moduły

| Moduł | Własność |
|---|---|
| `engine` | Profile `autoexp`, patrol, wybór celu, ruch awaryjny, łupy i handel |
| `tactics_model` | Czysta normalizacja i propozycje manewrów; pochodzenie: Tacticus NG beta.15 |
| `tactics` | Zgoda AUTO, kanały, świeżość danych, pojedyncza próba, potwierdzenia i ręczne przejęcie |
| `integration` | Odczyt znanych konfliktów z oficjalnej paczki i starych dodatków |
| `hud` | Górny pasek, menu i mała etykieta aktywnego terenu; bez HP drużyny |
| `init` | Złożenie modułów i wspólne punkty sterowania |

`build.py` tworzy samowystarczalną wtyczkę dla istniejącego instalatora jednoplikowego. Cache modułów dotyczy wyłącznie pojedynczego załadowania wygenerowanego pliku; ponowne załadowanie nie używa starego `require` cache.

## Przepływ

HUD jest zakotwiczony przy `y=0` głównego obszaru Mudleta. Górny margines służy wyłącznie do rezerwowania miejsca dla konsoli: większa z wartości poprzedniego marginesu i wysokości paska (44 px, opcjonalnie 52 px). Nazwa terenu i zegar znajdują się w tym samym rzędzie po prawej, obok sterowania; nie dodają marginesu. Przy małej szerokości skracamy podpisy zakładek i nazwę terenu, zachowując zegar. Menu mają zwarte szerokości i własne punkty zakotwiczenia. Powtórne kliknięcie zakładki zamyka również jej otwarte podmenu.

Kółka przy Taktyce i Expowiskach oznaczają wyłączenie (szare), pauzę (żółte) i włączenie (zielone). Taktyka oczekująca na walkę podczas wyprawy również jest oznaczona na żółto. Szczegółowy powód pozostaje w menu Taktyka.

Menu Expowiska pobiera przez `nearest_profiles(3)` trzy najbliższe osiągalne profile. Koszt to najkrótsze dojście do dowolnej znanej lokacji trasy według `walker.cost`, bez poruszania postacią. Nieznane i nieosiągalne tereny pozostają dostępne w osobnym oknie pełnej listy, posortowanym po nazwie i podzielonym na strony. Odległości buforujemy do zmiany lokacji lub ponownego otwarcia zakładki. Jeden wiersz obejmuje wybór terenu, liczbę lokacji, odległość i oddzielnie klikalny przełącznik zarobku; wybranie terenu nie uruchamia automatyki.

Patrol wybiera cel i trasę. Taktyka podczas aktywnej wyprawy może działać tylko w fazie `COMBAT`; podczas ręcznej gry może pracować samodzielnie. Przejście do powrotu, handlu, ruchu albo pauzy odbiera jej możliwość nowych manewrów. UI i aliasy korzystają z tych samych walidowanych operacji.

To celowo mały koordynator zakresów działania, a nie ogólny menedżer wszystkich skryptów Mudleta. Nie przechwytuje `_G.send`. Obce automaty muszą być wyłączone, gdy wykryty konflikt uniemożliwia zachowanie jednego właściciela ruchu lub celu.

Taktyka ma jedną próbę w toku. Zbiorowa komenda nadal może objąć kilka osób, ale rezerwuje odpowiednie lokalne kanały. Brak potwierdzenia nie oznacza sukcesu. Wygaśnięcie oczekiwania nie zeruje odstępu manewru. Zewnętrzny manewr postaci wyłącza jej kanał, zewnętrzny parozkaz wyłącza oba kanały pachołków; ponowne zezwolenie ustawia się w menu jednostki.

## Dane i stan

- `snapshot()` zwraca kopię profili, wybranego profilu, sesji i logu. Widok nie otrzymuje mutowalnych tabel silnika.
- `request(name, arg)` wywołuje zarejestrowaną operację patrolu i respektuje jej walidację; stare aliasy pozostają obsługiwane.
- `set_economy(key, enabled)` zmienia tylko dany profil, gdy wyprawa jest zatrzymana lub w pauzie.
- `stop_all()` zatrzymuje patrol i zintegrowaną taktykę; `/exp stop` ma ten sam zakres.
- Rola jest przypisana do ID, nazwy i typu. Callback GUI przekazuje oczekiwaną tożsamość; zmiana jednostki pod ID nie dziedziczy kliknięcia starego wiersza.
- Ustawienia `profiles`, `selected`, `verbosity` pozostają w przestrzeni `autoexp`. Role i opcje znajdują się w `autoexp:tactics`, wygląd w `autoexp:hud`.
- Przy pierwszym uruchomieniu dostępna konfiguracja `tacticus_ng:config` jest normalizowana i kopiowana do nowej przestrzeni. Stan AUTO oraz pending/cooldowny nie są importowane. Zachowany stary zapis pozwala na ręczny powrót do wcześniejszej wtyczki.
- Konfiguracja wczytanego profilu jest normalizowana, aby uzupełnić brakujące pola reguł wcześniejszych wydań. Nie zmienia to trasy gracza ani mapy Mudleta.
- Czas sesji obejmuje aktywną wyprawę, w tym handel i regenerację; pauza go nie zwiększa. Jest to czas sesyjny, nie historia utrzymywana pomiędzy restartami.

## Zmiany względem Tacticus NG beta.15

Usunięto parę równoległych prób zasłony dla tego samego chronionego i napastnika. Następna decyzja zapada po wyniku albo upływie oczekiwania, przy zachowaniu lokalnych blokad. Fallback głównego tanka sprawdza politykę, zdrowie i udział w automatyce; nie wybiera Supporta. Rozkaz zbiorowej ochrony postaci ma formę `rozkaz druzynie zaslonic ciebie`, zgodną z oficjalnym `/rz @` w analizowanej paczce. Rozkazy zbiorowe pozostają domyślnie wyłączone.

Zachowano czystą logikę planera: konserwatywny odczyt HP, ograniczenia obciążenia, jawne zadania pachołków, role, priorytety ochrony i warunki PvE. Nie dodano nieudokumentowanych wzorów na pancerz ani skuteczność zasłony.

## Granice zgodności

Stabilne odczyty GMCP są pobierane przez oficjalne `ctx:use("gmcp")`. Deklarowane zależności patrolu pozostają `gmcp`, `mapper`, `walker`, `locations`. Część kontroli zgodności wymaga odczytu konfiguracji i statusów loadera; te miejsca są izolowane w `integration.lua`, ponieważ nie są ogólnym stabilnym publicznym API.

Jeżeli któryś znany moduł istnieje, ale zgłasza błąd odczytu, uruchomienie jest blokowane. W środowisku bez aplikacji Chimery (testy kontraktów) brak informacji o tych modułach nie oznacza ich aktywności. Nie twierdzimy, że integracja wykrywa dowolną obcą wtyczkę.

Przeładowanie i rozłączenie wyłączają taktykę i patrol. Stare callbacki po sprzątnięciu nie mogą ponownie rozpocząć zadania. Górny margines jest przywracany tylko wtedy, gdy nadal ma wartość ustawioną przez ten HUD. Zmiana instancji przy tym samym ID świata pauzuje wyprawę i unieważnia kontekst wykonania.

## Ograniczenia wymagające gry i Qt

1. Model zagrożenia wykorzystuje liczbę napastników i procent HP; nie mierzy ich siły ani tempa obrażeń. Nie jest symulacją mechaniki serwera.
2. Okna świeżości 15 s i lokalne blokady 8/15 s są zachowawczymi regułami klienta, nie gwarantowanymi serwerowymi cooldownami.
3. Dane grupy i istot nie dowodzą właściciela NPC. Ponad dwóch kandydatów wstrzymuje niepotwierdzone kanały pachołków. W ustawieniach jednostki gracz może jawnie przypisać własnego NPC do P1/P2; po przypisaniu musi osobno włączyć jego udział. Zapisane potwierdzenie obejmuje ID i nazwę, a nie dowolnego sojusznika. Pełny automatyczny dowód własności wymaga pola właściciela lub dodatkowego kontraktu gry.
4. Zmiana celu napastnika potwierdza efekt, ale nie wyjaśnia całej trwałej relacji `covers`. Przy zbiorowej osłonie potwierdzenie zmiany przynajmniej jednego celu nie oznacza pełnego sukcesu całego szyku.
5. Wykonawca zachowuje jedną próbę naraz. Oczekiwanie do około 3 s może opóźnić decyzję innego kanału. Nie uruchamiamy niezweryfikowanej równoległości pod pozorem poprawy szybkości.
6. Sprzedaż odziedziczona z XP obejmuje bronie i zbroje; prywatny ekwipunek wymaga świadomego przygotowania. Testy nie dowodzą selektywnej sprzedaży ani kwoty przychodu.
7. Litery i numery walki nadal należą do oficjalnego okna Kondycji; HUD nie tworzy konkurującego mapowania oznaczeń.
8. Geometria jest sprawdzana atrapami Geyser, także dla 320 px. Weryfikacja faktycznego fontu, DPI, stosu etykiet i kliknięć Qt wymaga Mudleta.

## Plan próby w Mudlecie

Po kopii profilu i wyłączeniu osobnego Tacticusa: sprawdzić role bez AUTO; wybrać niewielki teren; sprawdzić schronienie i `/exp test`; uruchomić patrol bez zarobku; zweryfikować ręczne przejęcie i STOP. Następnie osobno sprawdzić pojedynczą osłonę i jej wynik w GMCP, a dopiero potem współpracę podczas wyprawy. Handel testować na przygotowanym ekwipunku. Zbiorowe komendy są ostatnim, osobnym testem.

Przy problemie zapisać: stan XP i taktyki, ID lokacji/instancji, aktualne `Combat.State`, rolę wykonawcy, komendę i odpowiedź gry. Sam komunikat „wysłano” nie potwierdza powodzenia.
