# Film auf Apple TV

Stand: 16.10.2026. Native tvOS-App im bestehenden Projekt. iPhone und TV teilen Daten- und Empfehlungskern sowie die Designsprache.

## Dienststatus

Der TV-Dienst wurde nach ausdrücklicher Freigabe aktiviert. Unbestätigte Kopplung und Abbruch wurden live erfolgreich geprüft. Eine vollständige Anmeldung mit zwei echten Geräten und der Lichtscan auf Hardware sind noch nicht abgenommen. Bestehende App-Versionen bleiben zunächst nutzbar; sobald ein Konto die neue Synchronisierung verwendet, benötigen dessen andere Geräte die aktuelle App für weitere Online-Schreibzugriffe.

## Starten

1. `FilmPrototyp.xcodeproj` öffnen.
2. Scheme **FilmTV** und einen Apple-TV-Simulator oder das eigene Apple TV wählen.
3. Starten. Der reguläre Start zeigt die Anmeldung mit iPhone-Bestätigung.
4. Für eine lokale Vorführung unter Product → Scheme → Edit Scheme → Run → Arguments `-seedDemo YES` eintragen. Das ist ein ausdrücklich gewähltes Demo-Konto ohne Online-Anmeldung. Danach die Argumente für einen echten Login wieder entfernen.

Die vorhandene iOS-Scheme-Konfiguration bleibt erhalten. Bei einer erneuten Projektgenerierung mit XcodeGen eigene Scheme-Einstellungen sichern. Beide Apps nutzen `de.beispiel.filmprototyp` für gemeinsame App-Store-Käufe; Signierung/App-Store-Connect-Konfiguration muss zum eigenen Entwicklerkonto passen.

## Implementierter Umfang

- Lichtcode-, QR- und sechsstelliger Code beziehen sich auf denselben einmaligen Anmeldevorgang. Das angemeldete iPhone zeigt Konto, Gerät, Code und eine ausdrückliche Bestätigung/Ablehnung. Kamera- und Polling-Aufgaben werden beim Schließen beendet.
- TV-Zugänge liegen getrennt in der Keychain, lassen sich am iPhone verwalten und widerrufen. Rotation kann eine verlorene Serverantwort wieder aufnehmen; beim Offline-Abmelden bleibt ein Widerruf zum erneuten Versuch in der Keychain vorgemerkt.
- Profile erstellen/bearbeiten/löschen, Kinderprofile/FSK, pausierte Profile/Tarifgrenzen, Zuschauerwahl und gemeinsamer Geschmack, Kalibrierung und Kinderfavoriten.
- Einzelvorschlag mit Match und Grund, Alternativen, Merken, gesehen, Rückgängig, Zeit-/Format-/Stimmungsfilter; Katalog, Suche, Merkliste, Details, Trailerwahl, Staffeln/Folgen.
- Nativer AVPlayer mit gespeicherter Position und Bewertungen je Profil. Fortsetzen/Abschluss, aktive Zuschauer und Wiedergabeberechtigung werden berücksichtigt. Ein Wechsel der Altersfreigabe oder Berechtigung beendet eine nicht mehr erlaubte laufende Wiedergabe.
- Import, Geschmacksdialog, KI-Stimmung, längere Reviews, externe Links, Aboverwaltung und Kontolöschung können als bestätigte iPhone-Aufgabe weitergeführt werden. iPhone-Entwürfe verändern TV-Profile erst beim angenommenen Abschluss.
- Gemeinsame Kontodaten über versionierte Mutationen; dauerhaft kontogebundene Offline-Outbox, stabile Operations-IDs, sichere Zusammenführung unabhängiger Änderungen und sichtbare Auswahl bei kollidierenden Metadaten im Kontobereich beider Apps. Aktive Zuschauer bleiben pro Gerät lokal.
- Demo-Tarife bleiben als Demo gekennzeichnet. Echte StoreKit-Belege werden dem Server zur kryptografischen Prüfung übergeben; ohne eingerichteten Prüfdienst gibt es keine serverseitige Kaufbestätigung.

## Server und Verifikation

Einrichtung, Migration und Sicherheitsprüfung stehen in [supabase/README.md](../supabase/README.md). Der Dienst ist aktiviert; produktive Konten mit neuer Synchronisierung dürfen nicht durch alte Snapshot-Clients überschrieben werden. Der Server erzwingt diese Grenze. Ein vollständiger Hardware-Durchlauf bleibt offen.

Aktuelle Tests und Messgrenzen stehen in [Performance-Prüfung](performance-2026-10-16.md). Reale Käufe, Kameralichtscan und Siri-Remote-Touchgefühl benötigen weiterhin Hardwaretests. Die Simulator-Prüfung ersetzt diese nicht.
