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
| `/exp wieza status` | Stan, poziom, liczba odwiedzonych/oczyszczonych pokoi, mozaika, konfiguracja |
| `/exp wieza pauza` / `wznow` / `stop` | Kontrola jednego piętra |
| `/exp wieza lup lista` | Aktualne kategorie przedmiotów |
| `/exp wieza lup dodaj <tekst>` | Dodanie kategorii (np. `szkatulki`) |
| `/exp wieza lup usun <tekst>` | Usunięcie kategorii |
| `/exp wieza limit 8` | Maksymalna liczba przeciwników jednocześnie w pokoju; przekroczenie **pauzuje**, nie omija pokoju |
| `/exp wieza hp 35 85` | Progi odwrotu i powrotu drużyny (%) |

Domyślne łupy: `zlote monety`, `mithrylowe monety`, `kamienie`, `szkatulki`. Zbieramy najpierw z ziemi, potem z każdego policzonego ciała: `wez <kategoria> z <N>. ciala`. Na końcu automatycznie `wloz monety do plecaka` oraz `napelnij plecak`. Bez sprzedaży, bankowania i automatycznego przejścia na następny krąg.

## Mechanika i bezpieczeństwo

- Nowe pokoje poznajemy przez wyjścia GMCP, ale **własna** pamięć odwiedzonych lokacji przechowuje tylko aktualne `area_id`. Pomiędzy odwiedzonymi lokacjami korzystamy z oficjalnego `walker.go`, po kontroli, że trasa nie przechodzi przez nieodkryte lokacje. Nowe przejścia wykonujemy pojedynczym, potwierdzonym krokiem.
- Cel ataku musi mieć `kind="npc"`, `relation="hostile"` i nie należeć do drużyny. Preferowany jest najbardziej zraniony wróg. Istniejący silnik taktyki drużyny działa w tym samym HUD-zie; przed nową walką Wieża wydaje potwierdzany GMCP rozkaz celu grupowego.
- Komnata wejściowa każdego piętra stanowi lokalne schronienie. Przy krytycznie niskim HP drużyny bot próbuje odwrotu **wyłącznie potwierdzoną** trasą do startu. Powtarzający się krytyczny HP w tej samej lokacji wstrzymuje automat; brak drogi również pauzuje. Nie gwarantuje to przeżycia podczas walki.
- Mozaikę identyfikuje `ob mozaike`: powrotna `Mozaika tli sie zimnym blaskiem.`, nieaktywna `Krag mozaiki jest martwy.`, aktywna `Krag mozaiki jarzy sie jasno.`, brak `Nie zauwazasz niczego takiego.`. Nigdy nie wywołuje `stan na mozaice`.
- Oficjalny mapper ma własne podświetlenia, dlatego Wieża maluje tylko mozaiki: błękit dla powrotnej, pomarańcz dla nieaktywnej i miętowy dla aktywnej. Na zakończenie/pauzę nie usuwa mapy.
- Zmiana poziomu, losowania (`area_id`), ruch poza automatem, brak świeżych danych GMCP, nieznana droga lub nieaktywna mozaika na końcu **pauzują** zamiast zgadywania.
- Stan eksploracji trwa w pamięci podczas pauzy i wznowienia; rozłączenie/przeładowanie wymaga nowego startu. Start obsługiwany jest wyłącznie w pokoju z potwierdzoną mozaiką powrotną danego piętra, a nie na podstawie nazwy lokacji.

## Ograniczenia beta i testy

Dostępność przeciwników wymaga `relation="hostile"`; boss lub neutralny przeciwnik z inną relacją może wymagać obsługi dodatkowej. Ukryte wyjścia i niestandardowe bramy nie są automatycznie odkrywane. Odwołujemy się do rzeczywistych komunikatów polskiego MUD-a; zmiana ich formy lub duża liczba ciał (>30) zatrzyma zbieranie. Nie uruchamiaj bez nadzoru na wartościowej postaci.

Testy symulacyjne: `python tests/run.py tests/tower_mock.lua` albo `lua tests/tower_mock.lua` w katalogu repozytorium. Sprawdzają: eksplorację i zakończenie na mozaice, zebranie łupów z dwóch ciał, brak samoczynnego awansu, nieaktywną mozaikę, ręczne przejęcie i ochronę HP. **Testy nie zastępują próby w Mudlecie i na serwerze.**