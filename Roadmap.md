# Roadmap – Local Journal

Diese Datei sammelt bewusst **zurückgestellte** Funktionen. Version 1 baut eine
robuste Grundlage (lokales Schreiben, lokale KI-Analyse über Ollama, einfache
Auswertung). Die folgenden Punkte kommen später.

## Suche (nicht in Version 1)

Die Suche ist wichtig, wird aber erst nach einer stabilen Version 1 umgesetzt.

- [ ] Volltextsuche über alle Journaleinträge
- [ ] Suche nach Personen (z. B. alle Einträge mit „Anna“)
- [ ] Suche nach Topics (z. B. „Arbeit“, „Stress“)
- [ ] Suche nach Gefühlen / Stimmungen
- [ ] Filter nach Zeitraum (Tag, Woche, Monat, eigener Bereich)
- [ ] Filter nach KI-Insights (z. B. nur Einträge mit erkannten Mustern)
- [ ] Kombinierte Filter (Zeitraum + Person + Stimmung)

## Daten & Entitäten

- [ ] Manuelles Nachbearbeiten erkannter Entitäten
      (Personen/Topics umbenennen, zusammenführen, entfernen, Aliase)
- [ ] Entitäten manuell mit Einträgen verknüpfen / Verknüpfungen lösen
- [ ] Personen-/Topic-Detailseiten mit eigenem Verlauf

## Export & Backup

- [ ] Exportfunktion (Markdown / JSON / PDF)
- [ ] Einzelne Einträge oder Zeiträume exportieren
- [ ] Lokales Backup / Wiederherstellung

## KI-Funktionen

- [ ] Automatische **Wochenzusammenfassungen** (Modell `WeeklySummary` ist bereits
      angelegt) als geplanter Hintergrund-Job
- [ ] Strukturierte Ausgaben über Ollama-JSON-Schema statt nur `format: "json"`
- [ ] Auswahl mehrerer Modelle / Profile (schnell vs. gründlich)
- [ ] Re-Analyse-Warteschlange mit Fortschrittsanzeige

## UX

- [ ] Markdown-Formatierung im Editor
- [ ] Tag-/Wochenansicht (Kalender)
- [ ] Tastatur-Navigation & Shortcuts ausbauen
- [ ] Anhänge (Bilder) – weiterhin rein lokal

## Architektur / Technik

- [ ] Unit-Tests für `JournalStatistics`, JSON-Parsing und `OllamaService`
- [ ] Migrationsstrategie für das SwiftData-Schema
- [ ] Streaming-Antworten von Ollama für längere Analysen
