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

## Wissensgraph & RAG

Stufe 1 (Graph-first) ist umgesetzt: Knoten (Personen, Themen, Gefühle, Ideen,
Learnings, Vorhaben) + typisierte, gewichtete Kanten, festes Relations-Vokabular
und Normalisierung. Siehe [`docs/knowledge-graph.md`](./docs/knowledge-graph.md).

- [x] Property-Graph aus Analyse-Ergebnissen (Co-Occurrence ohne KI + typisierte
      Relationen mit KI)
- [x] Browsebarer „Wissensgraph"-Tab (Knoten, Verbindungen, verknüpfte Einträge)
- [x] Knotentypen: Person, Thema, Gefühl, Ereignis, Ort, Idee, Learning,
      Vorhaben, Ziel, Muster
- [x] Few-shot-Beispiel im Analyse-Prompt gegen `relatedTo`-Übernutzung
- [ ] **Embeddings pro Eintrag** (on-device via `NLContextualEmbedding` oder
      Ollama-Embeddings) als Basis für semantische Suche
- [ ] **„Frag dein Journal"** (RAG): Retrieval + fundierte, belegte Antworten
- [ ] **GraphRAG**: Retrieval, das den Graphen traversiert, + Themen-Summaries
      über Zeit
- [x] Lebendige Force-Simulation im Graph (Anziehung/Abstoßung/Kollision ohne
      Überlappung, Abkühlen + Reheat, Positions-Persistenz, Mausrad-Zoom,
      Global ⇄ Umgebung; nur Entitäts-Knoten)
- [x] Gefühle mit Intensität (`EmotionScore`), Ereignis-Knoten entfernt
- [ ] Navigation von einem Graph-Knoten direkt zu seinen Einträgen
- [ ] Emotions-Intensität in Charts nutzen (z. B. Intensität über Zeit)
- [ ] Barnes-Hut / Quadtree für sehr große Graphen (>~300 Knoten)
- [ ] Zoom auf Cursor-Position (statt Zentrum) beim Mausrad
- [ ] Muster auch aus dem 7-Tage-Vergleich in den Graph übernehmen (aktuell nur
      die Einzeleintrags-Patterns)
- [ ] Semantisches Zusammenführen naher Satz-Knoten (Ideen/Ziele/Muster)
- [ ] Volle Kanten-Provenienz pro Eintrag (saubere Re-Analyse ohne Doppelzählung)

## Einsichten & Selbstreflexion

Der Bereich **Einsichten** verdichtet die Einträge zu wiederkehrenden Mustern,
Trigger→Gefühl-Verbindungen, Glaubenssätzen, Strategien, Learnings und Veränderung
über Zeit; dazu selbst formulierte Werte/Ziele mit KI-Abgleich.

- [x] Tiefere Extraktion pro Eintrag (Glaubenssätze, Bedürfnisse, Trigger,
      Energie-Geber/-Räuber, Strategien) als zweiter, fokussierter Analyse-Durchgang
- [x] „Einsichten"-Seite: deterministische Aggregation + Graph (Trigger→Gefühle)
- [x] Selbst formulierte **Werte & Ziele** + KI-Abgleich mit den Einträgen
- [x] KI-Synthese „Wie habe ich mich über die Zeit verändert?"
- [ ] Semantische Zusammenführung ähnlicher Muster/Glaubenssätze (statt exakter
      Textgleichheit) – braucht Embeddings
- [ ] Zeitverlauf pro Einsicht (wann trat ein Muster zuerst/zuletzt auf?)
- [ ] Deep-Reflection-Durchgang optional per Einstellung (spart einen Modell-Aufruf)
- [ ] Werte/Ziele-Abgleich als speicherbarer Report statt nur flüchtig

## Daten & Entitäten

- [ ] Manuelles Nachbearbeiten erkannter Entitäten
      (Personen/Topics umbenennen, zusammenführen, entfernen, Aliase)
- [ ] Entitäten manuell mit Einträgen verknüpfen / Verknüpfungen lösen
- [ ] Personen-/Topic-Detailseiten mit eigenem Verlauf
- [ ] Wissensgraph und `PersonEntity`/`TopicEntity` zu einer Quelle vereinheitlichen

## Export & Backup

- [x] **Markdown-Spiegel**: jeder Eintrag als `.md` in einem selbst gewählten
      Ordner, automatisch bei Speichern/Bearbeiten/Löschen (einseitig,
      Security-Scoped Bookmark)
- [ ] PDF-Export
- [ ] Einzelne Einträge oder Zeiträume gezielt exportieren
- [ ] Zwei-Wege-Sync / Re-Import aus den Markdown-Dateien
- [ ] Vollständiges lokales Backup / Wiederherstellung (inkl. Analysen & Graph)

## KI-Funktionen

- [x] Automatische **Wochen- & Monatsberichte** – umgesetzt im Bereich „Berichte"
      (`PeriodicReport` + `ReportBuilder` + `AnalysisService.generateReport`):
      deterministische Kennzahlen plus best-effort LLM-Rückblick, automatisch für
      abgeschlossene Zeiträume beim Start und on-demand für den laufenden.
      Nächster Schritt: echter geplanter Hintergrund-Job statt Start-Trigger
- [ ] Strukturierte Ausgaben über Ollama-JSON-Schema statt nur `format: "json"`
- [ ] Auswahl mehrerer Modelle / Profile (schnell vs. gründlich)
- [ ] Re-Analyse-Warteschlange mit Fortschrittsanzeige

## UX

- [x] Markdown-Formatierung im Editor – Werkzeugleiste (fett/kursiv/unterstrichen/
      durchgestrichen, Überschrift, Listen, Zitat) über einen NSTextView-basierten
      Editor; der Text ist Markdown-Quelltext und landet 1:1 in der `.md`-Datei
- [ ] **Sprachaufnahme → Transkription** – der Mikrofon-Button im Editor ist
      bereits vorhanden (noch ohne Funktion). Anzubinden an eine
      **Transkriptions-API**; passend zur lokalen Ausrichtung idealerweise ein
      **lokales** Modell (z. B. WhisperKit / whisper.cpp) statt einer Cloud-API
- [ ] Tag-/Wochenansicht (Kalender)
- [ ] Tastatur-Navigation & Shortcuts ausbauen
- [ ] Anhänge (Bilder) – weiterhin rein lokal

## Architektur / Technik

- [ ] Unit-Tests für `JournalStatistics`, JSON-Parsing und `OllamaService`
- [ ] Migrationsstrategie für das SwiftData-Schema
- [ ] Streaming-Antworten von Ollama für längere Analysen
