# Local Journal – Funktionsweise & Referenz

Dieses Dokument ist die **Gedächtnisstütze** für die ganze App: alle Features,
wie sie intern funktionieren, welche Daten wo liegen und welche Prompts an das
lokale Modell gehen. Stand: Juli 2026.

**Grundprinzip:** Alles läuft lokal. SwiftUI + SwiftData (macOS 14+), Analyse
über einen lokalen [Ollama](https://ollama.com)-Server (Standardmodell
`gemma4:e4b`, in den Einstellungen änderbar). Keine Cloud, kein Sync, keine
externen APIs – die einzige Netzwerkverbindung geht an `localhost:11434`.

---

## 1. Bereiche der App (Seitenleiste)

| Bereich | Zweck |
|---|---|
| **Dashboard** | Überblick: Resilienz-Score, Stimmungskurve, Statistiken, Themen, Tagesimpuls |
| **Merken** | Offene Vorhaben (abhakbar), Learnings, Angepinntes |
| **Schreiben** | Der Editor für neue Einträge (ruhige Schreibfläche + KI-Begleiter) |
| **Einträge** | Liste aller Einträge → Detailseite (lesen, bearbeiten, Analyse, Resonanz) |
| **Reflexionsfragen** | Sammlung von Fragen (Favoriten, eigene, KI-generierte) + Eintrags-**Vorlagen** |
| **Einsichten** | Verdichtung über alle Einträge: Muster, Trigger→Gefühle, Glaubenssätze, Werte & Ziele |
| **Notizen** | Alte Notizdateien importieren, destillieren, kuratieren → Wissensbasis |
| **Berichte** | Automatische Wochen- & Monatsberichte |
| **Wissensgraph** | Entitäten (Personen, Themen, Gefühle …) als interaktiver Graph |
| **Analyse** | Charts: Wörter/Tag, Stimmung über Zeit, häufigste Themen/Personen/Gefühle |
| **Einstellungen** | Ollama, KI-Prompts, Editor-Defaults, Markdown-Ordner |

Unten in der Seitenleiste hängt dauerhaft der kompakte **Einblicke-Block**
(Streak · Einträge gesamt · Wörter gesamt), umgesetzt als `safeAreaInset` unter
der Navigationsliste (`SidebarStatsFooter`).

---

## 2. Schreiben (Editor)

Datei: `Views/Editor/JournalEditorView.swift`

**Aufbau Mitte** (max. 820 pt breit, Apple-Journal-nah):
1. Werkzeugzeile: Datum (Kalender-Popover), Buttons für **Textformatierung**,
   **Mikrofon** (Platzhalter, noch ohne Funktion – Roadmap: lokale
   Transkription) und **Schreib-Timer**.
2. Starter-Buttons: **Reflexionsfrage** (Menü der Sammlung, Favoriten zuerst)
   und **Vorlage** (Menü der Vorlagen).
3. Optional eingeblendet: Formatierungsleiste, Fragen-Banner, Timer-Leiste.
4. Großer Serifen-**Titel**.
5. **Stimmungs-Check-in**: „Wie fühlst du dich gerade?" + 5 Emoji. Nach der
   Wahl faltet sich die Zeile animiert (matchedGeometryEffect) auf den
   gewählten Smiley zusammen; erneutes Antippen öffnet sie wieder. Wert landet
   als `selfMood` (1–5, 0 = nicht gesetzt) am Eintrag.
6. **Schreibfläche**: `MarkdownEditor` – ein `NSTextView`-Wrapper (SwiftUIs
   `TextEditor` kann auf macOS 14 keine Selektion). Der Text ist
   **Markdown-Quelltext** und landet 1:1 in der gespiegelten `.md`-Datei.

**Textformatierung** (`FormattingBar` + `MarkdownEditingController`): wirkt auf
die aktuelle Selektion und fügt echtes Markdown ein – `**fett**`, `*kursiv*`,
`<u>unterstrichen</u>` (Markdown kennt kein Unterstreichen), `~~durchgestrichen~~`,
`## Überschrift`, `- Liste`, `1. Liste`, `> Zitat`. Kein Auto-Toggle (nie
kaputtes Markup); Rückgängig per ⌘Z.

**Rechtes Panel – KI-Begleiter** (`CompanionChatPanel`, ein-/ausklappbar über
das ✨-Symbol): Chat mit dem lokalen Modell. Der **aktuelle Entwurf (Titel +
Text) geht bei jeder Frage als Kontext mit**; dazu Impulse zum Antippen.
Schalter **„Wissensbasis"** im Panel-Kopf: speist die Top-3 passenden
Erkenntnisse aus den Notizen ein (siehe Resonanz). Antwortet frei (kein JSON).

**Speichern** (⌘S): Der Eintrag wird **immer zuerst lokal gespeichert**, dann
Markdown-Spiegel geschrieben, dann (falls Auto-Analyse an) die Analyse als
Hintergrund-Task gestartet. Ollama offline ⇒ Status `pending`, nachholbar.

---

## 3. Die Analyse-Pipeline

Datei: `Services/AnalysisService.swift`

Status-Lebenszyklus je Eintrag: `notStarted → pending → running → completed | failed`.
`pending` = „gespeichert, Analyse wartet" (z. B. Ollama aus) – nachholbar über
Dashboard-Banner, Detailseite oder Einstellungen.

Bei `analyze(entry)` laufen nacheinander (alle Prompts fordern striktes JSON,
tolerant geparst in `Support/AnalysisDecoding.swift`):

1. **`fullAnalysis`** (ein Aufruf): Zusammenfassung, **Gefühle mit Intensität
   0–10**, Themen, Personen, Orte, Erkenntnisse, Ideen, Vorhaben, Ziele,
   Muster, `moodScore` (−1…+1) sowie **typisierte Relationen** für den Graphen.
2. **Entitäten-Verknüpfung**: erkannte Personen/Themen werden zu
   `PersonEntity`/`TopicEntity` normalisiert (einmal angelegt, wiederverwendet).
3. **Graph-Ingestion**: `KnowledgeGraphService` erzeugt/aktualisiert Knoten und
   gewichtete Kanten (Co-Occurrence + typisierte Relationen).
4. **7-Tage-Vergleich** (`compareWithLastWeek`): Fließtext + ggf. neue Muster.
5. **Tiefere Ebene** (`deepReflection`, zweiter fokussierter Aufruf):
   **Glaubenssätze, Bedürfnisse, Trigger, Energie-Geber/-Räuber, Strategien
   (Problem → Lösung)**.
6. Markdown-Spiegel wird mit der fertigen Analyse neu geschrieben.

Schritte 4–6 sind best-effort: ein Fehler dort verwirft die Hauptanalyse nicht.

---

## 4. Eintrags-Detailseite

Datei: `Views/Entries/EntryDetailView.swift`

- **Lesen**: Text, Zusammenfassung, erkannte Signale (Gefühle mit Intensität,
  Themen, Personen, Orte, Ziele), **tiefere Signale** (Glaubenssätze,
  Bedürfnisse, Trigger, Energie, Strategien), Erkenntnisse, Ideen, Vorhaben,
  Muster, 7-Tage-Vergleich.
- **Bearbeiten**: Titel/Datum/Text; nach Textänderung Banner „Analyse veraltet"
  + automatische Neu-Analyse (falls Auto-Analyse an). Spiegel-Datei wird
  aktualisiert; Löschen entfernt sie.
- **Resonanz-Karte** (siehe Abschnitt 8).
- **Kritische Reflexion**: erzeugt aus genau diesem Eintrag 4 kritisch-reflexive
  Anschlussfragen; jede lässt sich in die Sammlung übernehmen oder direkt als
  neuer Eintrag starten.

---

## 5. Dashboard & Resilienz-Score

Dateien: `Views/Dashboard/DashboardView.swift`, `Support/ResilienceScore.swift`

Dashboard: erzählerische Headline (datengetrieben), **Resilienz-Karte**,
**Stimmungskurve (30 Tage)**, Statistik-Kacheln (Streak, Wörter Woche/gesamt,
Einträge), wiederkehrende Themen mit Häufigkeit, **„Impuls für heute"**
(dunkle Karte; Favoriten-Frage nach Tag-im-Jahr rotiert; „Schreiben →" startet
den Editor mit der Frage), letzte Einträge.

**Resilienz-Score (0–100), rein lokal & deterministisch** – gewichtete Mischung:

| Teilwert | Gewicht | Berechnung |
|---|---|---|
| Emotionale Stabilität | 40 % | 0,55 · Stimmungsniveau ((Ø moodScore+1)/2) + 0,45 · niedrige Volatilität (1 − Std-Abw.) |
| Selbstwirksamkeit | 35 % | Basis 40 + 60 · (0,30 · Ziele-Rate + 0,30 · Strategien + 0,25 · Learnings + 0,15 · Vorhaben) |
| Körper & Energie | 25 % | Basis 30 + 45 · Energie-Balance (Geber/(Geber+Räuber)) + 25 · Selbstfürsorge-Signal (Lexikon: Schlaf, Sport, Natur …) |

Fenster: aktuelle 30 Tage; Delta vs. Vor-30-Tage; 180-Tage-Schnitt als
persönliche Baseline. Ab 3 analysierten Einträgen aussagekräftig
(`hasEnoughData`). Berichte nutzen dieselbe Rechnung **periodengenau**
(`score(current:previous:baseline:)`).

---

## 6. Reflexionsfragen & Vorlagen

Datei: `Views/Prompts/PromptLibraryView.swift` (zwei Tabs)

- **Fragen** (`JournalPrompt`): anpassbare Sammlung – Favorit ⭐︎, bearbeiten,
  archivieren, „Eintrag starten". Neue Fragen manuell oder **KI-generiert aus
  den letzten Einträgen** (kritisch-reflexiv: blinde Flecken, Widersprüche,
  Muster). Start-Seeds in `Prompts/JournalPromptSeedData.swift`.
- **Vorlagen** (`EntryTemplate`): **Titel + freier Text** + Rhythmus
  (flexibel/täglich/wöchentlich/monatlich/jährlich, rein informativ). „Mit
  Vorlage schreiben" füllt den Editor. Seeds: Tagesreflexion, Morgenseiten,
  Wochenrückblick, Jahresrückblick. (Altes Feld `sections` bleibt für
  Migration; `bodyText` fällt darauf zurück.)

---

## 7. Notizen → Wissensbasis (Destillation)

Dateien: `Views/Notes/NotesView.swift`, `Services/NotesService.swift`,
`Support/NoteChunker.swift`

**Import:** txt/md-Dateien oder ganze Ordner (rekursiv). SHA-256-Hash je Datei
⇒ identische Dateien werden übersprungen (Ordner gefahrlos erneut importierbar).

**Chunking (zeilenbasiert – Daily-Note-Stil):**
- jede Zeile mit ≥ 3 Wörtern → eigener **„Gedanke"** (`NoteThought`)
- jeder Listenpunkt (`-`, `1.`, `[ ]`, `•` …) → eigener Gedanke (Marker entfernt)
- Mini-Fragmente (< 3 Wörter) kleben am vorherigen Gedanken **desselben Blocks**
- `#`-Überschriften werden Kontext (`heading`), keine Gedanken
- Leerzeilen/Trennlinien erhöhen den **`paragraphIndex`** (Block-Grenze)

**Destillation** (Batches à max. 18 Gedanken / ~1200 Wörter; **schneidet nie
durch einen Block** – Sicherheitsnetz gegen zerschnittene Absätze): Gemma
extrahiert NUR dauerhaft Nützliches als `NoteInsight` mit Typ
**Empfehlung / Learning / Grundsatz / Idee**, prägnant umformuliert, mit
Themen und Quellstelle. Eine Erkenntnis darf **mehrere zusammenhängende Zeilen**
umfassen (`indices: [3,4,5]` → Quellstelle = ganzer Span). Text-Dedupe
verhindert Doppelte. **Pausier-/fortsetzbar**: Gedanken werden erst nach
erfolgreichem Batch als `isDistilled` markiert.

**Kuration** (3 Tabs): *Prüfen* (Behalten/Verwerfen je Karte, „Alle behalten"),
*Behalten* (durchsuchbare Wissensbasis), *Dateien* (Löschen entfernt Rohdaten;
behaltene Erkenntnisse überleben, da sie ihre Quelle als Kopie tragen).

---

## 8. Resonanz (Wissen ↔ neue Einträge)

Dateien: `Support/ResonanceEngine.swift`, `Views/Entries/ResonanceCard.swift`

Auf jeder Eintrags-Detailseite (nur wenn Treffer über dem Schwellwert):

- **„Aus deinen Notizen"**: Top-3 der **behaltenen** Erkenntnisse.
- **„Schon mal erlebt"**: Top-3 ähnliche frühere Einträge, inkl. **„Damals half
  dir:"** (Strategie-Lösungen + Learnings von damals) und Sprung zum Eintrag.

**Matching – bewusst ohne LLM** (transparent, live berechnet, nie veraltet):
gewichtete exakte Übereinstimmung der extrahierten Signale beider Seiten:

| Signal | Gewicht |
|---|---|
| Trigger, Muster | 3,0 |
| Glaubenssätze | 2,5 |
| Bedürfnisse, Themen | 2,0 |
| Personen | 1,5 |
| Gefühle | 1,0 |
| loser Token-Overlap (Stoppwörter raus, ≥ 4 Zeichen) | 0,5 je Token, max. 2,0 |

Schwellwert Einträge 3,0 (zwei gemeinsame Themen reichen, ein einzelnes nicht),
Notizen 2,0. Chips an jedem Treffer zeigen die gemeinsamen Signale. Der
**KI-Begleiter** nutzt dieselbe Engine gegen den rohen Entwurf (Token-basiert,
da noch keine Analyse existiert) – Schalter „Wissensbasis".

*Geplant (Phase 3):* Embeddings über Ollama (`bge-m3`), Vektoren als Blob in
SwiftData, Brute-Force-Cosine – hebt die Trefferqualität bei Umschreibungen,
gleiche UI. Keine Vektor-Datenbank nötig (< 10k Vektoren).

---

## 9. Berichte (Woche & Monat)

Dateien: `Views/Reports/`, `Support/ReportBuilder.swift`, Modell `PeriodicReport`

- **Automatisch:** Beim App-Start bekommt der jeweils **letzte abgeschlossene**
  Wochen-/Monats-Zeitraum einen Bericht (einmalig; leere Zeiträume übersprungen).
- **Auf Knopfdruck:** „Diese Woche" / „Dieser Monat" für den laufenden Zeitraum;
  „Neu erzeugen" in der Detailansicht. **Upsert** über (Art, Periodenstart) –
  nie Duplikate.
- **Zweigeteilt:** Deterministische Kennzahlen (`ReportBuilder` – immer da,
  auch offline): Einträge/Tage/Wörter, periodengenauer Resilienz-Score mit
  Delta zur Vorperiode + Halbjahres-Baseline, Stimmung (Ø, Verlauf, Tages-
  Sparkline), Themen mit Häufigkeit + **neue Themen** ggü. Vorperiode, Gefühle,
  Personen, Energie, Ziele, Vorhaben, Learnings, Muster, tiefere Ebene,
  Strategien. Darauf setzt der **LLM-Erzähltext** (best-effort): Rückblick,
  Entwicklung, Höhepunkte, ein Fokus und reflexive Impulse (starten per Klick
  einen neuen Eintrag). Das Modell bekommt die fertigen Zahlen und darf nichts
  erfinden.

---

## 10. Weitere Bereiche

- **Einsichten** (`Views/Insights/InsightsView.swift`): beantwortet die
  Leitfragen (Muster? Trigger→Gefühle? Glaubenssätze? Strategien? Learnings?
  Veränderung über Zeit?) durch deterministische Häufigkeits-Aggregation über
  alle Analysen + Graph-Kanten (`causes`). Dazu selbst formulierte **Werte &
  Ziele** (`GuidingPrinciple`) mit zwei On-Demand-LLM-Synthesen:
  „Wie habe ich mich verändert?" und „Werte/Ziele vs. tatsächliches Handeln".
- **Merken** (`MemoryBoardView`): offene Vorhaben (abhakbar), Learnings,
  „Wichtig zum Merken".
- **Wissensgraph** (`Views/Graph/`, Doku: `docs/knowledge-graph.md`): Knoten
  (Person, Thema, Gefühl, Ort, Ziel, Idee, Learning, Vorhaben, Muster) mit
  typisierten, gewichteten Kanten; Liste + lebendige Force-Simulation (Zoom,
  Pan, Filter).
- **Analyse** (`AnalysisView`): Swift-Charts über alle Einträge.

---

## 11. Datenmodell (SwiftData)

Alle Modelle registriert in `LocalJournalApp.swift`. Migrationsregel des
Projekts: **nur additiv** – neue Felder immer mit Default (`= ""`, `= 0`,
`= nil`, `= []`), neue Modelle = neue Tabellen; @Model-Klassen nie umbenennen.

| Modell | Kernfelder | Beziehungen |
|---|---|---|
| **JournalEntry** | title, date, text (Markdown-Quelltext), wordCount (denormalisiert), writingSeconds, **selfMood** (0–5), mirrorFileName, analysisStatusRaw | analysis (1:1, cascade), people [PersonEntity], topics [TopicEntity], nodes [KnowledgeNode] |
| **EntryAnalysis** | summary, **emotions** [{name, intensity 0–10}], feelings (Namen, abgeleitet), topics, people, places, keyInsights, ideas, tasks, goals, patterns, **beliefs, needs, triggers, energyGivers, energyDrainers, strategies** [{problem, solution}], comparisonWithLastWeek, moodScore (−1…1), modelName | entry (inverse) |
| **JournalPrompt** | text, category, isFavorite, isArchived, isAIGenerated | – |
| **EntryTemplate** | name, cadenceRaw, **text** (freier Körper), sections (legacy), detail, sortIndex | – |
| **PersonEntity / TopicEntity** | name, normalizedName (unique-Suche), lastSeen | entries (inverse) |
| **KnowledgeNode** | name, normalizedName, kindRaw | entries; Kanten via KnowledgeEdge |
| **KnowledgeEdge** | relationRaw (festes Vokabular), weight, source/target | – |
| **PeriodicReport** | kindRaw (weekly/monthly), periodStart/End, alle Kennzahlen (resilience*, mood*, topTopics [CountedTag], newTopics, energie, goals, learnings, patterns, beliefs, triggers, needs, strategies), narrative/trajectory/highlights/focus/recommendations, modelName | – (Upsert über kind+periodStart) |
| **WeeklySummary** | (Alt-Modell, durch PeriodicReport abgelöst; bleibt für Migrationssicherheit registriert) | – |
| **GuidingPrinciple** | kindRaw (value/goal), title, detail, sortIndex | – |
| **NoteDocument** | fileName, title, contentHash (SHA-256), importedAt | thoughts (cascade) |
| **NoteThought** | text (eine Zeile/Gedanke), heading, orderIndex, **paragraphIndex** (Block), isDistilled, embedding (Data, reserviert) | document |
| **NoteInsight** | kindRaw (recommendation/learning/principle/idea), statusRaw (pending/kept/discarded), text, topics, **sourceText + sourceDocumentName (Kopie!)**, thoughtID (lose UUID) | – (absichtlich beziehungslos: überlebt Dateilöschung) |
| **AppSettings** (Singleton) | ollamaBaseURL, modelName, autoAnalyze, timerEnabledByDefault, timerDurationMinutes, didSeedPrompts, didSeedTemplates, mirrorFolderBookmark (security-scoped), mirrorFolderPath, **customAnalysisTone, customReflectionGuidance, customReportGuidance**, **companionUsesKnowledge** | – |

Inline-Codable-Typen (keine Tabellen): `EmotionScore`, `StrategyNote`,
`CountedTag`, `ReportMoodPoint`.

---

## 12. LLM-Prompts

Datei: `Prompts/LLMPromptTemplates.swift` — **zwei Prompt-Sorten strikt getrennt:**
1. *Journal Prompts* = Reflexionsfragen für den Nutzer (in der App editierbar).
2. *LLM Prompt Templates* = technische Prompts an Gemma (unten).

Alle Analyse-Prompts bestehen aus **Ton** (editierbar) + **festen
JSON-Formatregeln** (nicht editierbar – schützt die Decoder). In den
**Einstellungen → „KI-Prompts"** sind drei Bausteine anpassbar (leer = Standard),
via `PromptOptions(settings)` überall durchgereicht: Grundton der Analyse,
Anleitung der Reflexionsfragen, Ton der Berichte.

| Template | Zweck | Antwortform |
|---|---|---|
| `fullAnalysis` | Hauptanalyse je Eintrag | großes JSON (→ EntryAnalysis) |
| `deepReflection` | tiefere Ebene je Eintrag | beliefs/needs/triggers/energy/strategies |
| `compareWithLastWeek` | 7-Tage-Vergleich | {comparison, patterns} |
| `generateReflectionPrompts` | neue Fragen aus letzten Einträgen | {prompts: []} |
| `reflectionPromptsForEntry` | kritische Fragen zu EINEM Eintrag | {prompts: []} |
| `reflectOnChange` | Veränderung früher↔heute (Einsichten) | {text} |
| `valueAlignment` | Werte/Ziele vs. Handeln (Einsichten) | {text} |
| `periodReport` | Erzähltext des Wochen-/Monatsberichts | {narrative, trajectory, highlights, focus, recommendations} |
| `distillNotes` | Notizen-Destillation (Batch) | {insights: [{indices, kind, text, topics}]} |
| `companionChat` | Editor-Chat (Entwurf + Wissensbasis als Kontext) | **freier Text** (einziger Nicht-JSON-Prompt) |

Ollama-Aufrufe (`Services/OllamaService.swift`): `/api/generate` mit
`format: "json"` (außer Chat), Temperatur 0,3–0,6, Timeout 120 s. Tolerante
Decoder in `Support/AnalysisDecoding.swift`, `ReportDecoding.swift`,
`NotesService.swift` (fehlende Schlüssel ⇒ leere Werte, nie Absturz).

---

## 13. Markdown-Spiegel

Datei: `Support/MarkdownMirror.swift` — **einseitig**, DB bleibt Quelle der Wahrheit.

- Ordner einmal in den Einstellungen wählen (Sandbox: security-scoped Bookmark
  auf `AppSettings.mirrorFolderBookmark`).
- Dateiname stabil je Eintrag: `YYYY-MM-DD-titel-slug-xxxxxx.md`
  (gespeichert in `mirrorFileName`; Bearbeiten überschreibt dieselbe Datei,
  Löschen entfernt sie, „Jetzt synchronisieren" schreibt alle neu).
- Inhalt: YAML-Front-Matter (date, title, words, status, **mood_self**, mood,
  topics, people, places, feelings) + `> [!summary]`-Callout + **Eintragstext
  unverändert** (= Markdown aus dem Editor) + Abschnitte „Erkenntnisse" und
  „Vorhaben" (als `- [ ]`).

---

## 14. Speicherorte, Backup, Sicherheit

- **SwiftData-Store** (alle Daten inkl. Analysen/Graph/Wissensbasis):
  `~/Library/Containers/academy.dbrains.LocalJournal/Data/Library/Application Support/`
  → **niemals von Hand löschen**; Backup über Time Machine.
- **Markdown-Ordner**: portables, lesbares Backup der Eintragstexte (+ Analyse-
  Zusammenfassung) – idealer Kandidat für iCloud-Drive-/Obsidian-Ordner.
- Sandbox: nur ausgehendes Netz (Ollama) + vom Nutzer gewählte Ordner/Dateien.
- Code-Sicherung: Git-Branch `claude/macos-journaling-ollama-e2j27p` auf GitHub;
  jeder Feature-Schritt ist ein eigener Commit (Wiederherstellungspunkt).

---

## 15. Design-System

Datei: `Views/Components/Theme.swift` (+ `CommonComponents.swift`)

Warm-redaktioneller Stil, hell/dunkel adaptiv über `NSColor(name:dynamicProvider:)`:
- Farben: `appBackground` (Creme/Warm-Schwarz), `cardSurface` (Papier),
  `sage` (einziger Akzent), `sageTrack`, `labelSoft` (Taupe-Labels),
  `inkPanel` (dunkle Impuls-Karten).
- Bausteine: `PanelCard` (Karte mit Uppercase-Label), `SectionLabel`,
  `MetricBar` (0–100-Balken), `StatCard`, `ChipsView`/`FlowLayout`,
  `DateFieldButton`, `.serif(size)` für Serifen-Headlines. `SectionCard` ist
  ein dünner Wrapper über `PanelCard` – dadurch sehen alle Seiten gleich aus.

---

## 16. Verzeichnisstruktur

```
LocalJournal/
├─ Models/     alle @Model-Klassen (siehe Tabelle oben)
├─ Services/   OllamaService (Netz) · AnalysisService (Pipeline) · NotesService (Import/Destillation)
├─ Prompts/    LLMPromptTemplates (an Gemma) · JournalPromptSeedData (für Nutzer)
├─ Graph/      RelationVocabulary · NodeNormalization · KnowledgeGraphService
├─ Support/    ResilienceScore · ReportBuilder · ResonanceEngine · NoteChunker ·
│              MarkdownMirror · JournalStatistics · MoodScale · Decoder · SeedManager
└─ Views/      Dashboard · Editor · Entries · Prompts · Insights · Notes ·
               Reports · Graph · Analysis · Memory · Settings · Components
```

**Offene Roadmap-Höhepunkte:** Suche, Embeddings/semantische Resonanz,
Sprachaufnahme→lokale Transkription, Backup/Restore aus der App, Kalenderansicht.
Vollständig in [`Roadmap.md`](../Roadmap.md).
