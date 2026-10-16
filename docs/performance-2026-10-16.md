# Performance-Prüfung · 16.10.2026

Die Ridge-Berechnung nutzt weiterhin dieselben Parameter und Ergebnisse, löst das symmetrische System aber per Cholesky und Accelerate. Der Vergleich mit dem bisherigen Solver wird numerisch getestet. Details lassen sich bereits während des Öffnens schließen; abgebrochene Übergänge öffnen sie nicht später erneut.

Debug, iPhone-18-Pro-Simulator, iOS 27: Median für 200 Lernbeispiele zuvor 368,84 ms, danach 24,29 ms (je drei Durchläufe). Swipe plus Undo bei 200 Einträgen: 34,42 ms; vollständige Wiederherstellung geprüft. Dies sind isolierte Rechen-/Zustandstests, keine auf Hardware gemessenen Bildraten oder Ende-zu-Ende-Latenzen.

16 Zustandstests erfolgreich, einschließlich früher Detail-Abbruch, Ghost-Rückweg mit wartender Folgeansicht, Undo und numerischer Übereinstimmung. Außerdem: Sync-Paket 41, Lichtcode-Paket 18, Backend 55 Tests; SQL-Integration 73 Prüfungen und TV-Regeln 30 Assertions erfolgreich. iPhone-Gerätebuild und tvOS-Simulatorbuild erfolgreich. Die aktuelle App wurde nach erneutem Versuch erfolgreich am iPhone installiert; eine vollständige Hardwareabnahme bleibt offen.

Oberfläche: acht Navigationstests im Gesamtlauf erfolgreich. Der Player-Test wurde durch einen gleichzeitig gestarteten Zustandstest unterbrochen und anschließend einzeln erfolgreich wiederholt (1 Test, 0 Fehler). Alle neun Navigationsfälle damit geprüft.
