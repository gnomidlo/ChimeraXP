# Zmiany

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
