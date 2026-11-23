# ChimeraXP — Wieża (Kręgi Shoona), beta.1

Wersja **jednopiętrowa**, bez automatycznego uruchamiania mozaiki. Po oczyszczeniu wszystkich osiągalnych pomieszczeń bot wraca do mozaiki wyjściowej, wysyła `ob mozaike` i kończy działanie **wyłącznie** po odpowiedzi `Krag mozaiki jarzy sie jasno.` Gracz sam wysyła `stan na mozaice`, a na kolejnym piętrze ponownie `/exp wieza start`.

## Jak uruchomić

1. Zainstaluj oficjalną Chimerę **5.0.4-beta.2** lub nowszą z obsługą mapowania Kręgów Shoona. Wyłącz oficjalne `/zbieranie`, `/autopogon` i `/autowsparcie` oraz konkurencyjne automaty, które sterują ruchem lub walką.
2. **Stanąć w komnacie wejściowej nowego piętra**, przy mozaice powrotnej (nazwa lokacji może się różnić) przy aktualnych GMCP Room.Info, Room.Entities, Combat.State i Group.State.
3. Uruchom `/exp wieza start`. Automat najpierw wysyła `ob mozaike` i czeka maksymalnie 5 s na odpowiedź `Mozaika tli sie zimnym blaskiem.`. Tylko wtedy przypisuje komnatę jako safe lock i zaczyna eksplorację. Automat rozpoznaje piętro po `area`, konkretne losowanie po `area_id` i wykorzystuje **oficjalny** mapper + walker.
4. Kontroluj stan komendą `/exp wieza status`. W razie problemów: `/exp wieza pauza`, `/exp wieza wznow` albo `/exp wieza stop`. Główny STOP ChimeraXP również zatrzymuje Wieżę.
5. Po komunikacie o aktywnej mozaice wyślij **ręcznie** `stan na mozaice`. W nowej komnacie wejściowej kolejny raz `/exp wieza start`.

## Komendy

| Komenda | Znaczenie |
| --- | --- |
| `/exp wieza start` | Rozpoczęcie od komnaty wejściowej |
| `/exp druzyna on|off` | Włączenie/wyłączenie wspólnego celu drużyny **dla Wieży** podczas jej działania; to samo co przełącznik w HUD |
| `/exp wieza status` | Stan, poziom, liczba odwiedzonych/oczyszczonych pokoi, mozaika, punkty z serwera i gotowość przejścia |\n| `/exp wieza punkty` | Ostatnia punktacja zapisana z komunikatu serwera: poziom, zdobyte, razem |\n| `/exp wieza historia` | Ostatnie 10 wyników z historii (maksymalnie 50 przechowywanych) |
| `/exp wieza pauza` / `wznow` / `stop` | Kontrola jednego piętra |
| `/exp wieza lup lista` | Aktualne kategorie przedmiotów |
| `/exp wieza lup dodaj <tekst>` | Dodanie kategorii (np. `szkatulki`) |
| `/exp wieza lup usun <tekst>` | Usunięcie kategorii |
| `/exp wieza limit 8` | Maksymalna liczba przeciwników jednocześnie w pokoju; przekroczenie **pauzuje**, nie omija pokoju |
| `/exp wieza hp 35 85` | Progi odwrotu i powrotu drużyny (%) |

Zbieracz nie uruchamia się w pustych pomieszczeniach: wymaga rozpoznania wrogiego NPC, stanu walki lub potwierdzonego zabicia przez drużynę. **Ograniczenie:** przedmioty leżące na ziemi w całkowicie pustej, niewalczącej lokacji nie mają obecnie wiarygodnego sygnału GMCP i mogą zostać pominięte; można je zebrać ręcznie.\n\nDomyślne łupy: `zlote monety`, `mithrylowe monety`, `kamienie`, `szkatulki`. Zbieramy najpierw z ziemi, potem z każdego policzonego ciała: `wez <kategoria> z <N>. ciala`. Na końcu automatycznie `wloz monety do plecaka` oraz `napelnij plecak`. Bez sprzedaży, bankowania i automatycznego przejścia na następny krąg.

## Wspólny cel ataku podczas eksploracji Wieży

Opcja **Wspólny cel ataku** w menu Drużyna pokazuje ustawienie aktualnego automatu. Podczas eksploracji Wieży jest to osobna, zapamiętywana opcja `tower.partyAttack` (domyślnie **włączona**, zgodnie z dotychczasowym zachowaniem). Po wyłączeniu Wieża nadal samodzielnie atakuje NPC, ale nie wysyła `rozkaz druzynie zaatakowac <ID>`. Podczas działania Wieży komenda `/exp druzyna on|off` steruje tym samym ustawieniem. Gdy Wieża nie jest uruchomiona, przełącznik i komenda dotyczą wybranego klasycznego expowiska. Ustawienia klasycznego EXP i Wieży nie nadpisują się nawzajem.

## Punkty Kręgów i otwarcie mozaiki

Po komunikacie serwera `Poziom 6 jest czysty. Zyskujesz 4 punktow Kregow (razem 14).` Wieża zapisuje **trzy niezależne liczby** (numer poziomu, zdobyte punkty, punkty razem) wraz z identyfikatorem losowania `area_id`. Liczby nie są szacowane z liczby zabitych NPC. Powtórzona wiadomość z tego samego poziomu nie dodaje podwójnego wyniku. Historia jest zachowywana po przeładowaniu wtyczki.

Komunikat `Gdzies w komnacie straznika rozjarza sie mozaika przejscia.` sygnalizuje odblokowanie wyjścia. Pokazujemy go w `/exp wieza status`. Nie wskazuje jednak identyfikatora komnaty w GMCP, dlatego skrypt nie zgaduje jej położenia; nadal lokalizuje i potwierdza mozaikę przez `ob mozaike`. **Na razie kontynuuje ustaloną eksplorację piętra i zatrzymuje się na aktywnej mozaice**, zamiast przerywać wyprawę na podstawie domniemanego progu 80% wrogów i bossa. Dokładny warunek aktywacji nie jest zweryfikowany.

Przy zakończeniu piętra Wieża wyświetla osobne podsumowanie z punktami i zapisuje wynik nawet wtedy, gdy komunikat serwera pojawił się kilka pokoi wcześniej. Jeśli serwer nie wysłał jeszcze punktacji, raport wyraźnie zaznacza brak danych.

## Mechanika i bezpieczeństwo

- Nowe pokoje poznajemy przez wyjścia GMCP, ale **własna** pamięć odwiedzonych lokacji przechowuje tylko aktualne `area_id`. Pomiędzy odwiedzonymi lokacjami korzystamy z oficjalnego `walker.go`, po kontroli, że trasa nie przechodzi przez nieodkryte lokacje. Nowe przejścia wykonujemy pojedynczym, potwierdzonym krokiem. Cofanie i nawigacja po znanych trasach uwzględnia kolejność zdarzeń oficjalnego chodzika: jego `walk.arrived` może nadejść, zanim Wieża otrzyma `room.changed` z tej samej zmiany pokoju.
- Cel ataku musi mieć `kind="npc"`, `relation="hostile"` **lub** `relation="neutral"` i nie należeć do drużyny. Wrogie istoty w Kręgach mogą być neutralne do pierwszego ataku. Preferowany jest najbardziej zraniony wróg. Istniejący silnik taktyki drużyny działa w tym samym HUD-zie; przed nową walką Wieża wydaje potwierdzany GMCP rozkaz celu grupowego.
- Komnata wejściowa każdego piętra stanowi lokalne schronienie. Przy krytycznie niskim HP drużyny bot próbuje odwrotu **wyłącznie potwierdzoną** trasą do startu. Powtarzający się krytyczny HP w tej samej lokacji wstrzymuje automat; brak drogi również pauzuje. Nie gwarantuje to przeżycia podczas walki.
- Mozaikę identyfikuje `ob mozaike`: powrotna `Mozaika tli sie zimnym blaskiem.`, nieaktywna `Krag mozaiki jest martwy.`, aktywna `Krag mozaiki jarzy sie jasno.`, brak `Nie zauwazasz niczego takiego.`. Nigdy nie wywołuje `stan na mozaice`.
- Oficjalny mapper ma własne podświetlenia, dlatego Wieża maluje tylko mozaiki: **wyraźny błękit oraz niebieskie obramowanie komnaty startowej** (mozaika powrotna), pomarańcz dla nieaktywnej i miętowy dla aktywnej. Oznaczenie wejścia jest przywracane po zmianach podświetlenia przez oficjalny mapper. Poprzedni własny kolor i grubość obramowania są przywracane po zatrzymaniu Wieży. Na zakończenie/pauzę nie usuwa mapy.
- Zmiana poziomu, losowania (`area_id`), ruch poza automatem, brak świeżych danych GMCP, nieznana droga lub nieaktywna mozaika na końcu **pauzują** zamiast zgadywania.
- Stan eksploracji trwa w pamięci podczas pauzy i wznowienia; rozłączenie/przeładowanie wymaga nowego startu. Start obsługiwany jest wyłącznie w pokoju z potwierdzoną mozaiką powrotną danego piętra, a nie na podstawie nazwy lokacji.

## Ograniczenia beta i testy

Dostępność przeciwników wymaga `relation="hostile"` lub `relation="neutral"`; inni pokojowi NPC (np. interaktywni handlarze) o relacji neutralnej również mogą zostać zaatakowani, dlatego tryb jest przeznaczony wyłącznie do Kręgów Shoona. Ukryte wyjścia i niestandardowe bramy nie są automatycznie odkrywane. Odwołujemy się do rzeczywistych komunikatów polskiego MUD-a; zmiana ich formy lub duża liczba ciał (>30) zatrzyma zbieranie. Nie uruchamiaj bez nadzoru na wartościowej postaci.

Testy symulacyjne: `python tests/run.py tests/tower_mock.lua` albo `lua tests/tower_mock.lua` w katalogu repozytorium. Sprawdzają: eksplorację i zakończenie na mozaice, zebranie łupów z dwóch ciał, brak samoczynnego awansu, nieaktywną mozaikę, ręczne przejęcie i ochronę HP. **Testy nie zastępują próby w Mudlecie i na serwerze.**