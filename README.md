# Local Journal

Eine schlichte, **vollständig lokale** Journaling-App für macOS (SwiftUI +
SwiftData). Sie speichert Journaleinträge, analysiert sie mit einem lokalen
**Ollama**-Modell (Gemma) und erzeugt automatisch Zusammenfassungen, Gefühle,
Themen, Personen, Erkenntnisse, Muster und einen Vergleich mit den letzten 7
Tagen. Es gibt **keine Cloud, kein Sync und keine externen APIs** – die einzige
Netzwerkverbindung geht an deinen lokalen Ollama-Server.

## Funktionen (Version 1)

- **Dashboard** – ruhiges, redaktionelles Layout: eine erzählerische Headline,
  ein **Resilience-Score** (0–100) mit Untermetriken (emotionale Stabilität,
  Selbstwirksamkeit, Körper & Energie) samt Monatsveränderung, eine
  **30-Tage-Stimmungskurve**, die gewohnten Statistik-Kacheln (Streak, Wörter …),
  wiederkehrende Themen mit Häufigkeit und ein **Impuls für heute** zum
  Direkt-Losschreiben. Der Resilience-Score wird lokal und deterministisch aus
  der Analyse berechnet (siehe `Support/ResilienceScore.swift`).
- **Editor** – eine ruhige, aufgeräumte Schreibfläche (Apple-Journal-nah, im
  warmen Stil der App). In der Mitte Titel, ein **Stimmungs-Check-in** (eine Frage,
  fünf Emoji zum schnellen Antippen – nach der Wahl **faltet sich die Zeile
  animiert auf genau diesen Smiley zusammen**; erneutes Antippen öffnet sie wieder)
  und der Schreibbereich; darüber Datum, optionaler **Schreib-Timer**, die Starter
  für **Reflexionsfrage/Vorlage** und eine **Textformatierung** (fett/kursiv/
  unterstrichen/durchgestrichen, Überschrift, Aufzählung, nummerierte Liste, Zitat)
  – als **Markdown**, das 1:1 in der `.md`-Datei landet. Ein **Mikrofon-Button** ist
  für spätere Sprachaufnahme + Transkription vorbereitet (noch ohne Funktion, siehe
  Roadmap). **Rechts** lässt sich ein **KI-Begleiter** ein-/ausklappen: ein Chat mit
  dem lokalen Ollama-Modell, dem der **aktuelle Entwurf als Kontext** mitgegeben
  wird – inklusive schneller **Impulse** zum Antippen.

  Einträge werden **immer zuerst lokal gespeichert**; die KI-Analyse läuft danach.
- **Einblicke in der Seitenleiste** – die wichtigsten Zahlen (Streak, Einträge
  gesamt, Wörter gesamt) stehen dauerhaft und kompakt **unten in der linken
  Navigationsspalte** – immer sichtbar, ohne zusätzliche Spalte.
- **Eintrag ansehen & bearbeiten** – jeder Eintrag öffnet eine Detailseite mit
  Text und der vollständigen KI-Analyse; per „Bearbeiten" lassen sich Titel,
  Datum und Text ändern (die Analyse wird danach aktualisiert). Ein Block
  **„Kritische Reflexion"** erzeugt aus genau diesem Eintrag kritisch-reflexive
  Anschlussfragen – jede lässt sich in die Sammlung übernehmen oder direkt als
  neuer Eintrag starten.
- **Reflexionsfragen** – zwei Tabs:
  - **Fragen** – eine anpassbare **Sammlung** von Reflexionsfragen: als
    **Favorit ⭐︎ markieren**, bearbeiten, archivieren und mit einem Klick **einen
    Eintrag damit starten**. Neue Fragen entstehen **manuell** oder werden **aus
    deinen bisherigen Einträgen generiert** (auf kritische Selbstreflexion
    ausgelegt: Muster, Gefühle, Ziele, blinde Flecken).
  - **Vorlagen** – **selbst erstellte Eintrags-Vorlagen** aus **Titel + freiem
    Text** plus einem Rhythmus (täglich/wöchentlich/…). „Mit Vorlage schreiben"
    füllt den Editor mit Titel und Text zum Reinstarten.

  Beim **neuen Eintrag** gibt es oben zwei Buttons: **Reflexionsfrage** und
  **Vorlage** – jeweils zum Auswählen.
- **KI-Analyse nach jedem Eintrag** – Zusammenfassung, **Gefühle mit Intensität
  (0–10)**, Themen, Personen, Orte, Erkenntnisse, Ideen, Vorhaben, Ziele, Muster
  und 7-Tage-Vergleich; strukturiert lokal je Eintrag gespeichert (`EntryAnalysis`).
  Ein zweiter, fokussierter Durchgang extrahiert die **tiefere Ebene**:
  Glaubenssätze, Bedürfnisse, Trigger, Energie-Geber/-Räuber und Strategien
  (Fehler → Lösung).
- **Einsichten** – ein eigener Bereich, der über alle Einträge verdichtet und
  deine Leitfragen beantwortet: *welche Muster wiederholen sich, welche Trigger
  lösen welche Gefühle aus, welche Glaubenssätze & Strategien tauchen auf, welche
  Learnings kehren wieder, wie habe ich mich verändert.* Dazu selbst formulierte
  **Werte & Ziele**, die die App per KI mit deinen Handlungen **abgleicht**.
- **Berichte** – automatische **Wochen- und Monatsberichte**. Sobald eine Woche
  oder ein Monat abgeschlossen ist, entsteht beim nächsten Start ein Rückblick;
  den laufenden Zeitraum erstellst du per Knopfdruck („Diese Woche" / „Dieser
  Monat"). Jeder Bericht kombiniert **lokal berechnete, deterministische
  Kennzahlen** – Resilienz-Score (mit Veränderung ggü. Vorperiode),
  Stimmungsverlauf, häufige & neue Themen, Gefühle, Personen, Energie-Geber/
  -Räuber, Ziele, Learnings, Muster, Glaubenssätze/Trigger/Bedürfnisse und
  Strategien – mit einem **erzählerischen Rückblick des lokalen LLM** (Rückblick,
  Entwicklung/Veränderung, Höhepunkte, ein Fokus und reflexive Impulse für den
  nächsten Zeitraum, aus denen sich direkt ein neuer Eintrag starten lässt). Die
  Zahlen entstehen deterministisch (`Support/ReportBuilder.swift`); das LLM
  formuliert nur den Text und ist best-effort – ist Ollama offline, bleiben die
  Kennzahlen trotzdem erhalten und der Text lässt sich später nachziehen.
- **Notizen** – importiere deine **alten Notizdateien** (txt/md, auch ganze
  Ordner). Jede Datei wird **zeilenweise in „Gedanken" zerlegt** (Daily Notes:
  fast jede Zeile ein neues Thema; Überschriften werden als Kontext mitgeführt).
  Als **Sicherheitsnetz gegen zu feines Zerschneiden** merkt sich der Import die
  **Blockgrenzen** (Leerzeilen): die Destillation sieht Zeilen im Verbund ihres
  Blocks, Batches schneiden nie durch einen Block, und eine Erkenntnis darf
  **mehrere zusammengehörige Zeilen umfassen** (Quellstelle = ganzer Span). Die
  lokale KI **destilliert** in Batches nur das, was bleibenden Wert hat –
  Empfehlungen, Learnings, Grundsätze, Ideen. Du **kuratierst einmal**
  (Behalten/Verwerfen); Behaltenes bildet deine persönliche **Wissensbasis**,
  der Rohtext bleibt zeilenweise durchsuchbar (und wird später zeilenweise
  eingebettet). Die Destillation ist pausier-/fortsetzbar und offline-tolerant.
- **Resonanz** – jeder Eintrag zeigt auf seiner Detailseite automatisch, was aus
  deinem alten Wissen gerade relevant ist: **„Aus deinen Notizen"** (die
  passendsten behaltenen Erkenntnisse) und **„Schon mal erlebt"** (frühere
  Einträge mit ähnlicher Situation, inkl. **„Damals half dir:"** aus deren
  Strategien/Learnings, mit Sprung zum Eintrag). Das Matching ist bewusst
  **deterministisch und erklärbar** – Chips zeigen die gemeinsamen Signale
  (Trigger/Muster wiegen mehr als Themen), es wird live berechnet (verbessert
  sich automatisch mit jeder behaltenen Erkenntnis) und unter einem
  Mindest-Score erscheint nichts. Der **KI-Begleiter** im Editor bekommt die
  Top-Erkenntnisse zum aktuellen Entwurf als Kontext – abschaltbar über den
  Schalter **„Wissensbasis"** im Chat-Panel.
- **Markdown-Spiegel** – optional wird jeder Eintrag zusätzlich als **`.md`-Datei**
  in einem selbst gewählten Ordner gespeichert (z. B. ein Obsidian-Vault): mit
  YAML-Front-Matter (Datum, Stimmung, Themen/Personen/Gefühle), Zusammenfassung
  und Text. Bearbeiten aktualisiert die Datei, Löschen entfernt sie – einseitig,
  die SwiftData-DB bleibt die Quelle der Wahrheit. In den Einstellungen einmalig
  den Ordner wählen (Sandbox-Zugriff via Security-Scoped Bookmark).
- **Entitäten** – `PersonEntity` und `TopicEntity` werden einmal angelegt und bei
  erneuter Erwähnung automatisch mit neuen Einträgen verknüpft.
- **Wissensgraph** – wiederkehrende **Entitäten** (Personen, Themen, Gefühle,
  Orte, Ziele) werden als Knoten mit typisierten, gewichteten Kanten verbunden
  (Co-Occurrence ohne KI + typisierte Relationen mit KI, per Few-shot gesteuert).
  Im Tab „Wissensgraph" als **Liste** oder als **lebendige Graph-Ansicht**: eine
  kontinuierliche Force-Simulation ohne Überlappungen (Knoten ziehen/abstoßen,
  Nachbarn passen sich live an), Mausrad-/Pinch-Zoom, Pan, Filter, Global ⇄
  Umgebung – rein SwiftUI, keine Abhängigkeit.
  Details: [`docs/knowledge-graph.md`](./docs/knowledge-graph.md).
- **Merken** – eine fokussierte Seite mit **offenen Vorhaben** (abhakbar),
  **Learnings** und **„Wichtig zum Merken"** (angepinnte Punkte ⭐︎ plus
  automatisch eingeblendete Ziele und wiederkehrende Learnings/Muster).
- **Analyse-Seite** – einfache SwiftUI-Charts (Wörter/Tag, Häufigkeit, Stimmung
  über Zeit, häufigste Themen/Personen/Gefühle) plus Entitätslisten.
- **Einstellungen** – Ollama-Adresse & Modell, Auto-Analyse, Timer-Defaults,
  „ausstehende Analysen nachholen“, Markdown-Ordner und – neu – **anpassbare
  KI-Prompts**: die wichtigsten *inhaltlichen* Anweisungen (Grundton der Analyse,
  Erzeugung der Reflexionsfragen, Ton der Wochen-/Monatsberichte) lassen sich hier
  bearbeiten. Die strukturellen JSON-Regeln bleiben fest verdrahtet, damit die
  Analyse-Pipeline stabil bleibt; ein leeres Feld nutzt den Standard.

Geplante Features (u. a. die **Suche**) stehen in [`Roadmap.md`](./Roadmap.md).

## Voraussetzungen

- macOS 14 (Sonoma) oder neuer, Xcode 16+
- [Ollama](https://ollama.com) lokal installiert und gestartet:

  ```sh
  ollama serve            # startet den lokalen Server auf :11434
  ollama pull gemma4:e4b  # lokales Gemma-Modell laden
  ```

## Öffnen & Starten

```sh
open LocalJournal.xcodeproj
```

Dann das Schema **LocalJournal** wählen und ausführen (⌘R).

> Hinweis: Das Projekt verwendet das moderne Xcode-Format mit
> *file-system-synchronized groups* – neue Dateien im Ordner `LocalJournal/`
> werden automatisch zum Target hinzugefügt.

## Architektur

Klare Trennung von UI, Datenmodell und LLM-Logik:

```
LocalJournal/
├─ Models/        SwiftData-Modelle (JournalEntry, EntryAnalysis, JournalPrompt,
│                 PersonEntity, TopicEntity, WeeklySummary, PeriodicReport,
│                 GuidingPrinciple, EntryTemplate, AppSettings,
│                 KnowledgeNode, KnowledgeEdge)
├─ Services/      OllamaService (Netzwerk) · AnalysisService (Pipeline)
├─ Prompts/       LLMPromptTemplates.swift  (technische Prompts für Ollama)
│                 JournalPromptSeedData.swift (Schreibimpulse für Nutzer:innen)
├─ Graph/         Wissensgraph: RelationVocabulary (festes Vokabular),
│                 NodeNormalization (Dedup), KnowledgeGraphService (Aufbau)
├─ Support/       Statistik, JSON-Parsing, Seeding
└─ Views/         Dashboard · Editor · Prompts · Graph · Entries · Analysis · Settings
```

**Zwei Arten von Prompts** – bewusst getrennt:

1. **Journal Prompts** (`JournalPromptSeedData`) = Reflexionsfragen für dich –
   direkt im Bereich *Reflexionsfragen* editierbar (markieren, ändern, anlegen).
2. **LLM Prompt Templates** (`LLMPromptTemplates`) = technische Prompts an Gemma,
   die strukturiertes, JSON-kompatibles Ergebnis anfordern. Der **Ton** und die
   wichtigsten **inhaltlichen Anweisungen** sind über `AppSettings` in den
   Einstellungen anpassbar (siehe `PromptOptions`); die JSON-Formatregeln
   (`formatRules`) werden immer automatisch ergänzt und sind nicht editierbar.

## Pragmatische Annahmen (dokumentiert)

- **Modellname:** „Gemma 4 4B“ entspricht auf Ollama dem Tag `gemma4:e4b`, das
  daher als Standard verwendet wird. Der Name ist in den **Einstellungen frei
  konfigurierbar** (`AppSettings.defaultModelName`); mit „Modelle laden“ kannst
  du die lokal vorhandenen Tags direkt auswählen.
- **Strukturierte Ausgaben:** Für maximale Kompatibilität werden Analysen mit
  `format: "json"` plus präzisen Prompt-Vorgaben erzeugt und tolerant geparst
  (siehe `AnalysisDecoding.swift`). Echte JSON-Schema-Constraints stehen auf der
  Roadmap.
- **Robustheit ohne Ollama:** Ist der Server nicht erreichbar, wird der Eintrag
  trotzdem gespeichert und als **„Analyse ausstehend“** markiert. Die Analyse
  lässt sich später (Dashboard-Banner, Eintragsdetail oder Einstellungen)
  nachholen.
- **Effizienz:** Die Pipeline nutzt einen kombinierten Analyse-Prompt
  (`fullAnalysis`) für einen Modell-Aufruf pro Eintrag; die Einzeltemplates
  existieren zusätzlich als dokumentierte Bausteine.

## Datenschutz

Alle Daten bleiben in einem lokalen SwiftData-Store auf dem Gerät. Die App ist
sandboxed und besitzt nur die Berechtigung für ausgehende Netzwerkverbindungen,
ausschließlich um den lokalen Ollama-Server zu erreichen.
