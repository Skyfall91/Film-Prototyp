# Native Film-App für Apple TV mit Lichtcode-Login

Datum: 14.10.2026 · Status: schriftlicher Entwurf zur Prüfung, noch nicht implementiert

## Auftrag und Erfolg

Das Team möchte eine native Apple-TV-App mit allen benötigten Funktionen, die die vorhandene iOS-App bereits hat. Ein Lichtcode nach dem Vorbild Octoglow verbindet die angemeldete iPhone-App mit dem Apple TV: scannen, den Fernseher bestätigen, anschließend dieselben Kontoprofile und Inhalte nutzen. Das Team hat am 14.10.2026 den beschriebenen Entwurf mit „los gehts“ zur Ausarbeitung freigegeben. Dieser Text konkretisiert Architektur, Produktumfang und Prüfbedingungen; er ist noch keine Bestätigung funktionierender Software.

Erfolg bedeutet: Der Kernablauf ist vollständig mit der Siri Remote bedienbar; Anmeldung erfordert keine Passworteingabe am Fernseher; Konto, Bewertungen und Merklisten sind zwischen den aktualisierten Apps konsistent. Funktionen, die ein iPhone benötigen, sind vom TV aus erreichbar und haben einen klaren Übergabe- und Rückkehrzustand. Geräte ohne verfügbare KI behalten nutzbare Empfehlungen und Suche.

## Geprüfter Ausgangspunkt

Repository: `/Users/robin/Documents/Apps/iOS/Film-Prototyp`, Ausgangscommit `f571d22`. Es gibt ein iOS-Target in `project.yml`. Xcode-Projekt und iOS-Scheme haben bereits uncommittete Änderungen; diese müssen unverändert erhalten bleiben, insbesondere Signing und Bundle-ID. Keine globale Neuerzeugung des Xcode-Projekts ohne Übernahme dieser Einstellungen.

`CloudAccounts.swift` enthält Supabase-Registrierung, Passwortlogin, Refresh, Keychain-Sitzung und Zugriff auf `account_state`. `AppStore.swift` speichert lokale Snapshots und lädt den gesamten Kontostand zeitlich gesammelt hoch. Die Online-Konvertierung leert bereits Passwort-Hash und Salt. Ein Kopplungsdienst, eigener TV-Login und Konfliktprotokoll existieren noch nicht. Das Schema und die tatsächlich eingerichteten RLS-Regeln des Servers wurden in diesem Entwurf nicht live gelesen; die Migration muss diese vor einer Aktivierung prüfen.

Die Empfehlung ist unabhängig vom Sprachmodell. Profile enthalten unter anderem Interaktionen, Merkliste, Reviews, Trainingsdaten, KI-Hinweise und Serienfortschritt. Aktive Zuschauer, Filter und UI-Zustände sind teilweise im selben Snapshot enthalten und müssen künftig von den gemeinsam genutzten Kontodaten getrennt sein.

Im installierten AppleTVOS27.0-SDK sind `FoundationModels.SystemLanguageModel` und SwiftUI `fileImporter` ausdrücklich für tvOS nicht verfügbar. Das TV-Konzept setzt daher keine lokale Apple-Intelligence-Ausführung und keinen iOS-Dateiauswahldialog voraus. Vorhandene Wiedergabe nutzt Trailer; der vorhandene SharePlay-Bereich ist eine Vorschau, Käufe sind im Entwicklungsbetrieb simuliert.

## Produktumfang

| Bereich | Verhalten auf dem TV | Zusammenarbeit mit iPhone |
|---|---|---|
| Konto | Lichtcode-Login, angemeldet bleiben, Kontoinformation, Abmelden, verknüpftes Gerät widerrufen | Falls nötig zunächst anmelden/registrieren; TV-Anfrage bestätigen |
| Profile | Erstellen, bearbeiten, Avatar, Kind/FSK, Auswahl und Löschen; pausierte Profile nach Tarifwechsel | Derselbe synchronisierte Profilbestand |
| Gemeinsam schauen | Mehrere Profile auswählen, strengste Altersgrenze, gemeinsame Empfehlung | Bewertungen bleiben je Profil getrennt |
| Einstieg | Bekannte Filme bewerten, ungesehene Titel überspringen, Kinderfavoriten, Geschmack anzeigen | CSV-Import und KI-gestützter Geschmackstext |
| Für dich | Ein Vorschlag mit Match und Grund, Alternative, merken, gesehen, Details, abspielen, rückgängig | Gemeinsame Geschmacksdaten; keine Übernahme des aktuellen TV-Fokus aufs Handy |
| Filter | Film/Serie, Laufzeit und Stimmungsfilter | KI-Interpretation eines freien Wunsches auf einem geeigneten iPhone |
| Suche/Katalog | Titel und Stichwörter suchen, sortieren/filtern, Ergebnisse und Details | Importierte und KI-abgeleitete Profilinformationen stehen auch am TV bereit |
| Merkliste | Hinzufügen, entfernen, ansehen und abspielen | Änderungen werden beidseitig übernommen |
| Details | Beschreibung, Begründung, FSK, Bewertungen, Trailerwahl, Staffeln/Folgen | Externe Bewertungsseiten über QR/iPhone öffnen, statt einen TV-Browser vorauszusetzen |
| Wiedergabe | Nativer TV-Player, Pause/Spulen, Ende, Serienfortschritt, fortsetzen | Kontoweiter Fortschritt je Profil und Titel |
| Bewertung | Vier Bewertungsstufen und optionaler Review, nach gemeinsamem Schauen je Person | Texte auch bequem auf dem iPhone eingeben |
| Geschmack bearbeiten | Weiter bewerten und aktuellen Geschmack ansehen | KI-Dialog über iPhone; daraus bestätigte Hinweise werden synchronisiert |
| Import | Aktion „Bewertungen importieren“ erklärt und startet die Übergabe | Bestehender Letterboxd-/IMDb-CSV-Import; Ergebnis und Fehler erscheinen auch am TV |
| Abo/Tarif | Dieselben Tarife, Testphase, Profilgrenzen, Downgrade/Pausieren, Demo-/StoreKit-Status und Wiederherstellung | Verwaltung mit iPhone-Unterstützung, wo ein Systemablauf sie benötigt |
| SharePlay | Ehrlich bezeichnete Vorschau entsprechend dem vorhandenen Prototyp | Kein funktionierender GroupActivities-Dienst wird behauptet |
| Kontolöschung | Vom TV erreichbar, verständlicher Umfang, erneute Bestätigung auf dem angemeldeten iPhone | Vorhandene serverseitige Löschung plus Widerruf aller neuen TV-Zugänge und Löschen der lokalen Zustände |

Lizenzierte vollständige Filme, produktiver Zahlungsbetrieb und echtes SharePlay werden durch diesen Auftrag nicht automatisch zu fertigen Funktionen. Alle bestehenden Entwicklungsfunktionen bleiben als solche erkennbar. Neue gekoppelte KI-Aufträge laufen nur nach einer Handlung des Nutzers; die Kamera wird nur im geöffneten Scanner aktiviert.

## Architekturentscheidung

Empfohlen ist ein gemeinsamer fachlicher Kern mit getrennten nativen iOS- und tvOS-Oberflächen. Der Kern enthält Katalogmodelle, Profile, Tarifregeln, Empfehlungen, Lernschritte, Importergebnisse, Mutationen und Synchronisierungsvertrag. UI-Farben, Avataransichten, Gesten, UIKit-Orientierung, Face-ID-Blätter und plattformspezifische KI bleiben in den jeweiligen Adaptern. Die bestehenden SwiftUI-Abhängigkeiten der Modelle werden gezielt in Präsentationshilfen ausgelagert. Die iOS-App wird dabei weiter gebaut und geprüft.

Alternativen wurden bewertet: Ein kopierter TV-Kern wäre zunächst leichter anzulegen, ließe aber FSK, Tarife und Lernen auseinanderlaufen. Eine vollständig gemeinsame Oberfläche würde den aktuellen iOS-Aufbau stärker verändern und den TV-Fokus erschweren. Der gemeinsame Kern mit TV-Views trägt beide Plattformen mit kleinerer fachlicher Doppelung.

Vier getrennte Verantwortlichkeiten bilden den Ausbau: (1) nativer TV-Client, (2) iPhone-Scanner und unterstützte Aufgaben, (3) serverseitige Gerätekopplung und TV-Sitzungen, (4) gemeinsamer Kontozustand mit Mutationen und Versionierung. Jede hat einen eigenen testbaren Vertrag. Im Repository kommen ein TV-Target, gemeinsame Quellbereiche, plattformspezifische Views und lokale Backend-Migrationen/Funktionen hinzu. Secrets bleiben ausschließlich in der Serverkonfiguration.

## TV-Oberfläche und Bedienung

Der TV bleibt filmisch und ruhig: großes Key-Art für den Einzelvorschlag, gut lesbare Begründung, klarer Fokus und wenige gleichwertige Aktionen. Hauptbereiche sind Für dich, Suche/Katalog, Merkliste, Profile und Konto. Tabellen und Kacheln verwenden native Fokusnavigation. Zurück führt auf eine nachvollziehbare übergeordnete Ebene; beim Schließen von Details oder Player wird der vorherige Fokus wiederhergestellt.

Die TV-Karte erhält erkennbare Aktionen für Alternative, Merken, Gesehen, Details und Abspielen. Richtungsnavigation darf nicht gleichzeitig eine unbeabsichtigte Bewertungsaktion auslösen. Beim Bewertungs-Onboarding gibt es vier eindeutig beschriftete fokussierbare Antworten. Alle Kernfunktionen sind ohne Touch erreichbar. Wiederholte Tastendrücke dürfen keinen Kauf oder eine Löschung mehrfach auslösen.

Lichtcode und Fokusanimation respektieren Reduce Motion. Im reduzierten Zustand bleibt der vollständige optische Code statisch lesbar; QR und Textcode bleiben vorhanden. VoiceOver benennt Zustände, verbleibende Gültigkeit und Aktionen. Lesbarkeit, Fokusverlust, Safe Areas und sehr lange Titel werden im TV-Simulator und auf einem echten Fernseher geprüft.

## Kopplung und Anmeldung

Der Server vermittelt die Anmeldung über HTTPS. Die TV-App erzeugt einen geheimen Abrufschlüssel mit 256 Bit Entropie und eine Kennung für diese Anfrage. Der Server speichert nur den Hash des Abrufschlüssels, erzeugt einen einmaligen öffentlichen sechsstelligen Code und begrenzt seine Gültigkeit auf fünf Minuten. Codes müssen während ihrer Gültigkeit eindeutig sein. Der öffentliche Code enthält weder ein Passwort noch einen Konto- oder Sitzungstoken.

TV-Zustände: bereit → Anfrage erstellen → auf Bestätigung warten → angemeldet; daneben abgelehnt, abgelaufen, abgebrochen und Netzwerkfehler. „Neuer Code“ ersetzt die alte Anfrage und entwertet sie. Der Server prüft Ablaufzeiten selbst; Geräteuhren entscheiden keine Autorisierung.

Die iPhone-App öffnet einen ausdrücklich gestarteten Scanner. Ein gültiger Lichtcode verweist auf genau eine aktive Anfrage. Die App zeigt den TV-Gerätetyp, den gleichen sichtbaren Textcode und das aktuell angemeldete Konto. Die Person kann bestätigen oder ablehnen. Erst diese Bestätigung über eine serverseitig geprüfte Supabase-Usersitzung bindet die Anfrage an das Konto. Kontowechsel während des Scannens verwirft die alte Freigabeansicht.

Der TV fragt mit seinem geheimen Schlüssel im vorgegebenen Intervall von fünf Sekunden nach dem Status. Die bestätigte Anfrage darf atomar genau einmal in eine eigene TV-Sitzung übergehen. Dafür erzeugt der TV zusätzlich bereits beim Erstellen der Anfrage einen separaten zufälligen 256-Bit-Bearer-Token und hinterlegt nur dessen Hash in der Anfrage. Der rohe Token bleibt im TV-Keychain. Nach Bestätigung aktiviert der Server atomar genau den vorab gebundenen Hash als TV-Sitzung. Derselbe TV kann den Aktivierungsstatus idempotent erneut abrufen, falls die erste Antwort verloren geht; ein zweiter TV kann die Sitzung weder umbiegen noch mit seinem eigenen Token übernehmen. Vor Aktivierung vermittelt der Token keinen Zugriff. Er ist kein kopierter iPhone-Refresh-Token und kein selbst gebauter Supabase-JWT.

Eine TV-Sitzung ist einzeln widerrufbar und nach 30 Tagen ohne erfolgreiche Erneuerung abgelaufen. Verlängerung rotiert den Token mit einem begrenzten Wiederholungsfenster für dieselbe Operation. Widerruf, Kontolöschung und Ablauf werden vor jedem Kontozugriff geprüft. Der TV erhält keine langfristig unkontrollierte Kopie aller Rechte des iPhones. Wiederherstellung nach Abmelden erfordert eine neue Kopplung.

Bei Rotation erzeugt der TV den neuen Token selbst und übermittelt dessen Hash unter der bestehenden Sitzung. Der Server ersetzt ihn atomar mit Operation-ID und hält den alten Hash höchstens 60 Sekunden ausschließlich für die Wiederholung dieser Rotation vor. Vor jeder Wiederholung wird erneut auf Widerruf geprüft. Normale Datenzugriffe mit dem alten Hash sind nach der Rotation gesperrt; der TV schreibt den neuen Token vor der Anfrage ausfallsicher in einen getrennten Keychain-Slot und aktiviert ihn nach bestätigtem Status.

Der Dienst hat explizite Verträge für `createPairing`, `resolveCode`, `approvePairing`, `rejectPairing`, `activateSession`, `rotateSession`, `revokeSession`, `readState` und `applyMutations`. `createPairing` nimmt Abruf- und Sitzungstoken-Hash sowie eine bereinigte Gerätebezeichnung; `resolveCode` liefert nur aktive Anfragekennung, sichtbaren Code, Geräteart und Ablauf. Freigabe/Ablehnung nimmt Anfragekennung unter geprüfter Usersitzung; Aktivierung verlangt den geheimen TV-Abrufschlüssel. Zustands- und Mutationsendpunkte akzeptieren entweder eine geprüfte Usersitzung oder einen aktiven TV-Principal. Pairing-/Sitzungstabellen sind über die öffentliche Daten-API nicht lesbar; privilegierte Zugriffe bleiben in den eng begrenzten Serverfunktionen. TV-Token sind nur für unseren Vermittlungsdienst gültig, nicht für direkten Zugriff auf Supabase Auth/PostgREST.

Anonyme Endpunkte erstellen nur Anfragen und lesen anonymisierte Anfragezustände. Freigabe/Widerruf erfordern eine gültige Usersitzung; TV-Kontozugriff erfordert einen gültigen TV-Token. Konto-IDs werden aus dem geprüften Principal abgeleitet und nie aus einem frei übergebenen Request-Feld übernommen. Geheime Server-Schlüssel verlassen die Edge Functions nicht. Rate Limits gelten für Anfrageerstellung, Codeauflösung und Abruf; nach fünf falschen Codeversuchen folgt mindestens eine Minute Pause. Globale Limits schützen zusätzlich vor verteiltem Raten. Codes, Token, Passwörter und Roh-Kamerabilder werden nicht protokolliert.

Der Ablauf ist an das Geräte-Anmeldeprinzip von RFC 8628 angelehnt, behauptet aber keine OAuth-Konformität des eigenen TV-Tokenprotokolls. Apples systemgestützte tvOS-Anmeldung bleibt eine getrennte mögliche Alternative. Der Scan-Login setzt keine automatische Hintergrundbenachrichtigung der eigenen iPhone-App voraus. Die gewünschte Erkennung der TV-Anfrage erfolgt beim Scannen.

## Optischer Code

Ein gemeinsamer versionierter Codec erzeugt und liest denselben sechsstelligen öffentlichen Code. Der sichtbare Partikelkörper trägt feste Farbregionen; Bewegung verändert die Position der Träger, nicht die Information. Ein einzelnes Kamerabild muss den gesamten Code enthalten. Der Decoder muss keine Animationsphase abwarten.

Der erste festgelegte Transport nutzt eine erkennbare Orientierung, kalibrierbare Referenzfarben, feste Farbpaare für die Nutzdaten und zusätzliche redundante Prüfinformation. Ein Scan wird erst nach zwei übereinstimmenden vollständigen Lesungen und einer gültigen serverseitigen Anfrage akzeptiert. Ein rein optisch gültiger Code autorisiert keinen Zugriff. Dies ist ein eigener kompatibel zwischen unseren Apps implementierter Codec, keine Zusage, Octoglow-Quellcode oder dessen Format unverändert zu übernehmen.

Die genaue Farbpalette und geometrische Aufteilung werden in einer isolierten Codec-Messung gewählt: synthetische Roundtrips und beschädigte Samples, anschließend Entfernung/Winkel/Helligkeit/TV-Farbmodus mit realer Hardware. Kandidaten müssen dunkle und helle Umgebungen sowie Reduce Motion bestehen. QR und manueller sechsstelliger Code sind vom ersten integrierten Login an verfügbare Ersatzwege zum selben Vorgang. Der Lichtdecoder bleibt als experimentell markiert, bis der reale Scan ausreichend zuverlässig ist. Ein Simulatorerfolg allein bestätigt die optische Zuverlässigkeit nicht.

## Kontodaten und Synchronisierung

Der bisherige Snapshot bleibt zunächst ein Migrationsformat. Aktualisierte iOS- und TV-Clients schreiben über einen gemeinsamen Mutationsdienst. Jede Mutation enthält eine zufällige Operation-ID, Gerätekennung, fachlichen Typ und Basisrevision. Der Server prüft Konto, Schema, Profilzugehörigkeit und Regeln, sperrt den Kontozustand für die kurze Transaktion, dedupliziert die Operation und erhöht die Revision. Wiederholte Übertragung einer Operation darf nicht erneut lernen, bewerten oder ein Profil erzeugen.

Der neue Kontodatenvertrag enthält keine lokalen Anmeldedaten, Passwort-Hashes, Salt, TV-Token, aktive Gerätesitzung oder Kameraaufnahmen. Aktive Zuschauer, Navigationszustand, Fokus, lokale Rückgängig-Historie und laufende Playerposition während einer Ansicht bleiben gerätespezifisch. Dauerhafte Bewertungen, Reviews, Merklisten, Profiländerungen, Lerndaten und abgeschlossener/gespeicherter Fortschritt werden kontoweit übernommen.

Verschiedene Merklistentitel oder Bewertungen verschiedener Filme können zusammengeführt werden. Bei widersprüchlichen Änderungen derselben Bewertung zählt die zuletzt serverseitig akzeptierte Handlung; die App zeigt den übernommenen Stand. „Rückgängig“ gleicht nur die eigene letzte Handlung aus, wenn diese fachlich noch der aktuelle Stand ist. Ein veraltetes Rückgängigmachen überschreibt keine spätere Änderung eines anderen Geräts.

Fachliche Mutationen sind Profil anlegen/bearbeiten/löschen, Bewertung setzen, Review setzen, Merkliste je Titel hinzufügen/entfernen, Lernhinweis setzen, Import als deduplizierbaren Stapel übernehmen, Serien-/Wiedergabefortschritt setzen, Tarif-/Demo-Abostand ändern und Pending-Rating bestätigen/verwerfen. Jede Operation benennt Profil- und Titel-IDs statt den ganzen Snapshot. Fortschritt wird als Episode plus Position und Abschlussstatus gespeichert; ein bewusster Neustart ist von einer verspäteten Fortschrittsmeldung unterscheidbar. Identische Importdateien müssen keine doppelten Lernsignale erzeugen. Serverbestätigte iOS- und TV-Operationen verwenden dieselben Regeln.

Profiländerungen verwenden Revisionsprüfung. Gelöschte Profile erhalten Tombstones; veraltete Offline-Updates dürfen sie nicht wiederherstellen. FSK, Profileigentum und Tarifgrenzen werden vor Mutationsannahme geprüft. Trainingsgewichte werden konsistent aus dem bestätigten fachlichen Stand abgeleitet, statt komplette verschieden berechnete Caches blind zusammenzuführen. KI-Hinweise werden als bestätigte Lernoperationen übernommen.

Offline-Handlungen bleiben in einer lokalen Outbox und wirken lokal sofort. Beim Wiederverbinden verarbeitet die App den Serverstand und die noch nicht bestätigten Operationen, meldet fachliche Konflikte und löscht nur bestätigte Outbox-Einträge. Die Outbox ist fest an Konto und Geräte-Epoch gebunden. Abmelden/Kontowechsel beendet fremde Hintergrundarbeit; Konto- und Profillöschung darf nicht durch verspätete Writes rückgängig gemacht werden. Widerrufene TVs können keine Offline-Outbox später ohne neue Autorisierung absenden.

Die Migration liest vorhandene Konto-JSONs und bewahrt Profil-IDs und Nutzerdaten. Alte Client-Upserts müssen nach der Umschaltung abgewiesen oder in eine ausdrücklich kompatible Übergangsroute gebracht werden. Beide aktualisierten Clients müssen daher vor Aktivierung derselben neuen Schreibregeln bereitstehen. Die tatsächlich vorhandenen Serverregeln werden vor der Migration geprüft; kein Zugriffsschutz wird pauschal abgeschaltet. `account_state` bleibt als lesbarer Kompatibilitätsstand erhalten, bis Migration und Rückfallweg geprüft sind.

## iPhone-gestützte Aufgaben

Der TV kann pro verknüpftem Konto einen kurzlebigen Auftrag starten: CSV-Import für ein bestimmtes Profil, Geschmacksdialog, KI-Stimmungsinterpretation oder Review-Text. Die iPhone-App zeigt solche Aufgaben beim Öffnen des Bereichs „Fernseher“ und nach dem Scannen des Auftragscodes. Es wird keine unsichtbar dauerhaft laufende iPhone-App vorausgesetzt.

Aufträge haben Kennung, Konto, Profil, Typ, Payload, Version, Ablauf und Status. Das iPhone muss den Profil-/Kontokontext prüfen und den Auftrag einmalig annehmen. Rohdateien und Kameraaufnahmen werden nicht gespeichert; Import liefert bestätigte fachliche Operationen. Eine KI-Antwort enthält nur die benötigten strukturierten Filter/Hinweise und eine Anzeigezusammenfassung, keinen Anspruch auf erfundene Katalogtitel. KI-Ausfall zeigt eine verständliche Nachricht und lässt die vorhandene Stichwortsuche aktiv.

Abbruch, abgelaufener Auftrag, gelöschtes Profil und Kontowechsel entwerten verspätete Ergebnisse. Bei fehlendem iPhone bleibt der TV mit Bewertungen, Katalog, Stichwortsuche und Empfehlungen bedienbar. Die bisherigen iOS-Importer und KI-Verfahren werden wiederverwendet; der Transport ist neu.

## Wiedergabe, Tarif und Jugendschutz

Der native tvOS-Player verwendet denselben Trailerkatalog und geeignete AVKit-Mechanismen. Die konkret gepinnte YouTubeKit-Version 0.4.9 wird auf tvOS gebaut und ihre Laufzeitauflösung geprüft; Plattformdeklaration allein gilt nicht als Playback-Nachweis. Fehler, keine verfügbare Quelle, Quellenwechsel, Fortsetzen und Player-Ende haben eigene Zustände. Der TV speichert Fortschritt, ohne während jeder Player-Sekunde den gesamten Kontostand zu übertragen.

Gemeinsame Runde, Profilgrenzen und Pausierung folgen den vorhandenen Tarifregeln. Aktuelle Abo-Anzeige und Wiederherstellung dürfen keine unbestätigte echte Zahlung behaupten. Gleichzeitige produktive Streams sind im bisherigen Prototyp kein belegter serverseitiger Anspruch; die TV-Version muss diese Grenze ehrlich darstellen, bis ein überprüfter Lease-Dienst dafür vorhanden ist.

FSK wird in Empfehlung, Suche, Katalog, Merkliste, Details, Episoden und Direktaufruf geprüft. Bei mehreren aktiven Profilen zählt die strengste Freigabe. Unbekannte Freigabe ist im Kinderkontext gesperrt. Ein Wiederherstellen des Fortschritts oder Wechsel der Trailerquelle darf keinen gesperrten Titel öffnen. Profil- oder Tarifwechsel während der Wiedergabe lösen eine erneute Berechtigungsprüfung aus.

## Prüfung und Fertigstellung

Die Erweiterung braucht echte fachliche Tests, keine Tests bloßer View-Struktur. Besonders wichtig sind Codec-Roundtrips/Fehlerfälle, Anmeldezustandsmaschine, atomare Einlösung und Widerruf, unerlaubte Konto-/Profilzugriffe, Outbox-Deduplizierung, gleichzeitige Geräteänderungen, Tombstones und FSK. Eingaben und Fixtures enthalten ausschließlich Testdaten.

UI-Prüfung: iOS-Regression des bisherigen Einstiegs/Swipens/Imports, tvOS-Build und vollständige Fernbedienungswege, Fokus nach Details/Player, lange Texte, VoiceOver und Reduce Motion. Backend-Prüfung erfolgt zuerst lokal oder in einer getrennten Testkonfiguration; live Migration und Deployment folgen erst nach überprüfbaren Artefakten und passenden Zugriffsrechten. Ein vorhandenes SDK bestätigt noch keinen installierten TV-Simulator oder ein echtes Testgerät.

Abnahme: ein angemeldetes iPhone autorisiert genau den angezeigten TV; ein fremder, abgelaufener oder widerrufener Vorgang erhält keine Kontodaten. Neuinstallation, Netzverlust, Abbruch, Double-Tap, wechselnde Konten und zwei TVs werden geprüft. Zwei aktualisierte Geräte verlieren keine unabhängigen Merkliste-/Bewertungsänderungen. Sämtliche TV-Funktionen sind mit der Remote erreichbar. Optischer Login wird nur als real geprüft bezeichnet, wenn er auf TV und iPhone getestet wurde. Verbleibende Hardware-/Deploymentgrenzen werden ausdrücklich berichtet.

## Quellen und Abgrenzung

- [Octoglow](https://maximedegreve.com/experiments/octoglow): visuelles und optisches Vorbild, kein geprüfter Code-/Lizenzlieferant.
- [RFC 8628](https://www.rfc-editor.org/info/rfc8628/): Geräte-Anmeldeprinzip, Bestätigung und begrenzte Codegültigkeit.
- [Apple: Simplify sign in for your tvOS apps](https://developer.apple.com/videos/play/wwdc2021/10279/): separate systemgestützte iPhone-Anmeldung.
- [Apple: Build SwiftUI apps for tvOS](https://developer.apple.com/videos/play/wwdc2020/10042/): native Fokusbedienung.
- [Supabase: Securing Edge Functions](https://supabase.com/docs/guides/functions/auth) und [getUser](https://supabase.com/docs/reference/javascript/auth-getuser): serverseitige Prüfung der angemeldeten Person und Trennung der Berechtigungen.
- [Supabase: Database functions](https://supabase.com/docs/guides/database/functions): Datenoperationen im Datenbankdienst; konkrete Mutations-/Konfliktregeln oben sind unser Entwurf.
- Lokale Evidenz: `project.yml`, `App/Model/{CloudAccounts,AppStore,Profile,Account,AccountDatabase}.swift`, iOS-Views/Engine und installierte tvOS-SDK-Schnittstellen.

Der bestehende MAS-Pitch bleibt eine Darstellung des vorhandenen iOS-Prototyps. Der TV-Ausbau wird in Obsidian als geplanter Ausbau geführt und erst nach entsprechender Prüfung als fertig beschrieben.
