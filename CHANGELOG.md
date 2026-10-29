# Zmiany

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
