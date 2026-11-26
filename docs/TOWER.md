# ChimeraXP — Wieża (Kręgi Shoona), beta.41

Tryb domyślny zatrzymuje się na aktywnej mozaice. `/exp wieza auto on` włącza opcjonalny automatyczny awans. Moduł korzysta z rzeczywistego licznika pozostałych istot i potwierdzeń serwera, a nie szacowanego progu procentowego.

## Jak uruchomić

Górny pasek i `/exp start`, `/exp pauza`, `/exp wznow`, `/exp stop` rozpoznają Kręgi Shoona przez GMCP. Start nadal wymaga potwierdzonej mozaiki powrotnej; STOP anuluje także oczekującą weryfikację wejścia. Poza Wieżą komendy pozostają klasyczne.

1. Zainstaluj oficjalną Chimerę **5.0.4-beta.2** lub nowszą z obsługą mapowania Kręgów Shoona. Wyłącz oficjalne `/zbieranie`, `/autopogon` i `/autowsparcie` oraz konkurencyjne automaty, które sterują ruchem lub walką.
2. **Stanąć w komnacie wejściowej nowego piętra**, przy mozaice powrotnej (nazwa lokacji może się różnić) przy aktualnych GMCP Room.Info, Room.Entities, Combat.State i Group.State.
3. Uruchom `/exp wieza start`. Automat najpierw wysyła `ob mozaike` i czeka maksymalnie 5 s na odpowiedź `Mozaika tli sie zimnym blaskiem.`. Tylko wtedy przypisuje komnatę jako safe lock i zaczyna eksplorację. Automat rozpoznaje piętro po `area`, konkretne losowanie po `area_id` i wykorzystuje **oficjalny** mapper + walker.
4. Kontroluj stan komendą `/exp wieza status`. W razie problemów: `/exp wieza pauza`, `/exp wieza wznow` albo `/exp wieza stop`. Główny STOP ChimeraXP również zatrzymuje Wieżę.
5. W trybie ręcznym po komunikacie o aktywnej mozaice wyślij `stan na mozaice`, a na nowym piętrze `/exp wieza start`. W trybie AUTO skrypt wykona to sam po sprawdzeniu bezpieczeństwa i potwierdzeniu nowej komnaty wejściowej.

## Komendy

| Komenda | Znaczenie |
| --- | --- |
| `/exp wieza start` | Rozpoczęcie od komnaty wejściowej |
| `/exp wieza auto on` / `/exp wieza auto off` | Opcjonalny automatyczny awans (domyślnie wyłączony) |
| `/exp wieza sesja` | Wyniki kolejnych pięter i suma punktów zdobytych w aktualnej sesji |
| `/exp druzyna on` / `off` | Włączenie/wyłączenie wspólnego celu drużyny **dla Wieży** podczas jej działania; to samo co przełącznik w HUD |
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

Komunikat `Blada iskra Kregow ulatuje znad pokonanej istoty -- zyskujesz punkt Kregow (razem 31).` przyznaje **jeden dodatkowy punkt**, niezależnie od nagrody za ukończenie piętra. Raporty pokazują punkty za istoty, za ukończenie piętra, sumę obu i ostatni łączny stan serwera. Powtórzony lub starszy stan punktów w tej samej instancji jest ignorowany. Nie naliczamy punktów za każde zabicie ani nie wyliczamy ich z różnicy stanów serwera. Iskra nie zmienia warunku ukończenia piętra ani gotowości mozaiki. Nowa sesja nie dolicza zapisanych wcześniej nagród z tej samej instancji.

Po komunikacie serwera `Poziom 6 jest czysty. Zyskujesz 4 punktow Kregow (razem 14).` Wieża zapisuje **trzy niezależne liczby** (numer poziomu, zdobyte punkty, punkty razem) wraz z identyfikatorem losowania `area_id`. Liczby nie są szacowane z liczby zabitych NPC. Powtórzona wiadomość z tego samego poziomu nie dodaje podwójnego wyniku. Historia jest zachowywana po przeładowaniu wtyczki.

Komunikaty o pozostałych istotach podają liczbę wymaganą przez serwer (`istot`, `istote`, `istoty`). `Dosc istot padlo, a straznik kregu wciaz czeka.` oznacza zero pozostałych zwykłych przeciwników. Automat rozpoznaje mozaikę przed rozpoczęciem walki, jeżeli nie został już zaatakowany; odkłada neutralnych NPC w komnacie strażnika do spełnienia warunku albo do wyczerpania innych osiągalnych dróg. Gdy wymóg jest spełniony i komnata jest znana, wraca do niej. Jeśli nie jest jeszcze znana, szuka mozaiki, omijając neutralne NPC w zwykłych pomieszczeniach; aktywna walka ma pierwszeństwo. `Krag mozaiki w posadzce rozjarza sie jasnym blaskiem.` identyfikuje lokalne wyjście; ogłoszenie `Gdzies w komnacie straznika rozjarza sie mozaika przejscia.` potwierdza otwarcie bez identyfikowania konkretnego pokoju. Przed zakończeniem lub awansem zawsze ponownie potwierdza aktywną mozaikę przez `ob mozaike`.

Przy zakończeniu piętra Wieża wyświetla osobne podsumowanie z punktami i zapisuje wynik nawet wtedy, gdy komunikat serwera pojawił się kilka pokoi wcześniej. Jeśli serwer nie wysłał jeszcze punktacji, raport wyraźnie zaznacza brak danych.

## Sesja i automatyczny awans

Wynik piętra i suma sesji są raportowane po każdym zakończeniu oraz po STOP. Sumujemy tylko nowe punkty z komunikatów w sesji, nie łączną historyczną wartość serwera. Sesja obejmuje kolejne piętra, także ręcznie uruchomione bez STOP; po STOP i nowym starcie rozpoczyna się nowa sesja. Brak wyniku jest oznaczony jako niepełne dane; historia poziomów pozostaje zapisana po przeładowaniu.

AUTO sprawdza świeże GMCP, brak walki, HP co najmniej na progu powrotu i aktywną mozaikę. Przy bezpiecznej lokacji z mozaiką czeka na regenerację do progu powrotu; krytyczne HP nadal uruchamia mechanizm odwrotu. Jednokrotnie wysyła `stan na mozaice`; czeka maksymalnie 15 sekund na nowy poziom N+1 i nowe `area_id`, zgodność mappera i świeże dane. Następnie sprawdza mozaikę powrotną, zapisuje nowe schronienie i rozpoczyna piętro. Nie ponawia niepotwierdzonej komendy; nieoczekiwany poziom lub brak danych pauzuje sesję. Pierwsze próby prowadzić pod nadzorem.

## Mechanika i bezpieczeństwo

- Nowe pokoje poznajemy przez wyjścia GMCP, ale **własna** pamięć odwiedzonych lokacji przechowuje tylko aktualne `area_id`. Pomiędzy odwiedzonymi lokacjami korzystamy z oficjalnego `walker.go`, po kontroli, że trasa nie przechodzi przez nieodkryte lokacje. Nowe przejścia wykonujemy pojedynczym, potwierdzonym krokiem. Cofanie i nawigacja po znanych trasach uwzględnia kolejność zdarzeń oficjalnego chodzika: jego `walk.arrived` może nadejść, zanim Wieża otrzyma `room.changed` z tej samej zmiany pokoju.
- Cel ataku musi mieć `kind="npc"`, `relation="hostile"` **lub** `relation="neutral"` i nie należeć do drużyny. Wrogie istoty w Kręgach mogą być neutralne do pierwszego ataku. Preferowany jest najbardziej zraniony wróg. Istniejący silnik taktyki drużyny działa w tym samym HUD-zie; przed nową walką Wieża wydaje potwierdzany GMCP rozkaz celu grupowego.
- Komnata wejściowa każdego piętra stanowi lokalne schronienie. Przy krytycznie niskim HP drużyny bot próbuje odwrotu **wyłącznie potwierdzoną** trasą do startu. Powtarzający się krytyczny HP w tej samej lokacji wstrzymuje automat; brak drogi również pauzuje. Nie gwarantuje to przeżycia podczas walki.
- Mozaikę identyfikuje `ob mozaike`: powrotna `Mozaika tli sie zimnym blaskiem.`, nieaktywna `Krag mozaiki jest martwy.`, aktywna `Krag mozaiki jarzy sie jasno.`, brak `Nie zauwazasz niczego takiego.`. Wysyła `stan na mozaice` wyłącznie w trybie AUTO po weryfikacji wyjścia.
- Trwałe kolory pokojów przez `setRoomEnv` i `setCustomEnvColor`: błękit wejścia, pomarańcz nieaktywnego wyjścia, mięta aktywnego. Pozostają po ręcznym ruchu i STOP; stare pokoje usuwa oficjalny mapper przy nowym losowaniu. Awaryjny fallback w starszym Mudlecie to podświetlenie.
- Zmiana poziomu, losowania (`area_id`), ruch poza automatem, brak świeżych danych GMCP, nieznana droga lub nieaktywna mozaika na końcu **pauzują** zamiast zgadywania.
- Stan eksploracji trwa w pamięci podczas pauzy i wznowienia; rozłączenie/przeładowanie wymaga nowego startu. Start obsługiwany jest wyłącznie w pokoju z potwierdzoną mozaiką powrotną danego piętra, a nie na podstawie nazwy lokacji.

## Ograniczenia beta i testy

Dostępność przeciwników wymaga `relation="hostile"` lub `relation="neutral"`; inni pokojowi NPC (np. interaktywni handlarze) o relacji neutralnej również mogą zostać zaatakowani, dlatego tryb jest przeznaczony wyłącznie do Kręgów Shoona. Ukryte wyjścia i niestandardowe bramy nie są automatycznie odkrywane. Odwołujemy się do rzeczywistych komunikatów polskiego MUD-a; zmiana ich formy lub duża liczba ciał (>30) zatrzyma zbieranie. Nie uruchamiaj bez nadzoru na wartościowej postaci.

Testy symulacyjne: `python tests/run.py tests/tower_mock.lua` albo `lua tests/tower_mock.lua` w katalogu repozytorium. Sprawdzają: eksplorację i zakończenie na mozaice, zebranie łupów z dwóch ciał, brak samoczynnego awansu, nieaktywną mozaikę, ręczne przejęcie i ochronę HP. **Testy nie zastępują próby w Mudlecie i na serwerze.**