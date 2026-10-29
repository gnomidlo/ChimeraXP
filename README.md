# ChimeraXP — wyprawy, role drużyny i auto-zarobek

**0.7.0-beta.3** dla Mudleta i oficjalnej Chimery **5.x**. Wspólny, zwięzły górny HUD łączy patrol ChimeraXP z przebudowaną taktyką wywodzącą się z Tacticus NG beta.15. Wizualnie uzupełnia ChimeraVIP; nie wymaga ChimeraVIP do działania.

Po uruchomieniu skryptów patrol i taktyka są wyłączone. Wydanie ma testy automatyczne Lua 5.1/5.4; zachowanie serwerowych komend i wygląd Qt/Geyser wymagają jeszcze próby w działającym Mudlecie.

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

Z pobranego repozytorium uruchom `install.cmd`, wybierz katalog profilu Mudleta, a następnie w Mudlecie wykonaj `/przeladuj`.

Publiczny bootstrap znajduje się w `packages/ChimeraXP.xml`; po importowaniu pobiera aktualne wydanie z gałęzi `main`. **Przed scaleniem gałęzi rework do main bootstrap online nadal instaluje dotychczasową wersję.** Do testowania pull requestu użyj instalacji lokalnej z jego plików.

Zachowano jednoplikowy format instalacji. Kod z `src/chimeraxp/` jest łączony przez `build.py` w samowystarczalny `plugins/chimera_autoexp/init.lua`; instalator nie musi pobierać dodatkowych modułów. `manifest.json` zawiera SHA-256 tego pliku.

Przed migracją:

1. Zatrzymaj `/exp stop` oraz `/tng off` i wykonaj kopię profilu Mudleta.
2. Wyłącz stary instalator XML AutoExp. Wyłącz oddzielną wtyczkę Tacticus NG, przenosząc jej katalog poza `chimera_wtyczki`; pozostaw zapisane ustawienia. Samo zamknięcie okna nie wyłącza wtyczki.
3. Zainstaluj nowe ChimeraXP lokalnie i wykonaj `/przeladuj`.
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
- oddaje kanał postaci po ręcznym manewrze i kanały pachołków po zewnętrznym parozkazie;
- rozkazy graczom uzależnia od prowadzenia; rozkazy zbiorowe są domyślnie wyłączone;
- nie uruchamia AUTO po rozłączeniu, przeładowaniu ani imporcie ustawień.

„Wycofanie w szyku” to manewr w bieżącej lokacji, a „powrót do schronienia” to osobna operacja ruchu XP. Rola nie jest pomiarem pancerza ani obrażeń. Zasady nadal opierają się na procentach HP, liczbie napastników i zadeklarowanej polityce; szczegóły i ograniczenia opisuje [projekt reworku](docs/REWORK.md).

## Współpraca z oficjalną Chimerą i ChimeraVIP

Przed startem i wznowieniem oraz podczas ewaluacji patrolu sprawdzane są znane konflikty: stary Tacticus, oficjalny bot, autopościg, autowsparcie, hooki przed/po ruchu i po walce. Zbieranie oficjalne blokuje profil, który sam zbiera łupy w trybie zarobkowym. Ustawień oficjalnej paczki nie przełączamy potajemnie.

STOP obejmuje wykonawców ChimeraXP i jego ruch. Nie cofa polecenia już wysłanego do serwera ani nie zatrzymuje dowolnego obcego skryptu lub serwerowej automatyki. Przy konflikcie właścicieli górnego marginesu HUD oddaje przestrzeń, pauzuje patrol i wyłącza taktykę; nie zeruje marginesu innego dodatku.

**Auto-zarobek:** zachowano istniejące komendy `sprzedaj bronie` i `sprzedaj zbroje`. Mogą objąć prywatne wyposażenie. Włączenie tej opcji zgłasza ostrzeżenie; przed użyciem trzeba zweryfikować zakres sprzedaży i konfigurację pojemników. Gra nie dostarcza tu ogólnego, potwierdzonego mechanizmu automatycznej selekcji prywatnych przedmiotów.

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
