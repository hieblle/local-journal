# Wissensgraph (Version 1: Graph-first)

Dieses Dokument beschreibt die **erste Stufe** des Wissenssystems: einen lokalen
Wissensgraphen aus Knoten und typisierten Kanten. Embeddings / RAG („Frag dein
Journal") kommen bewusst **später** und bauen auf diesem Graphen auf (siehe
`Roadmap.md`).

Alles läuft **rein lokal** auf dem Gerät – im SwiftData-Store. Keine Cloud, keine
externen APIs.

## Warum Graph-first

Die App erkennt schon Personen und Themen und verknüpft sie über Einträge – also
existiert bereits ein Mini-Graph. Diese Stufe verallgemeinert das zu einem
richtigen **Property-Graph**: einheitliche Knoten + typisierte, gewichtete
Kanten, deterministisch aufgebaut und für den Menschen überprüfbar.

## Knoten (`KnowledgeNode`, `NodeKind`)

Ein Knoten ist ein wiedererkennbares Konzept. Kurzlabels vs. satzartige Knoten:

| Kind        | Art        | Beispiel                                   | Quelle                     |
|-------------|------------|--------------------------------------------|----------------------------|
| `person`    | Label      | „Anna"                                      | `people`                   |
| `topic`     | Label      | „Arbeit", „Schlaf"                          | `topics`                   |
| `feeling`   | Label      | „überfordert", „ruhig"                      | `feelings`                 |
| `idea`      | Aussage    | „Newsletter monatlich statt wöchentlich"    | `ideas`                    |
| `learning`  | Aussage    | „Ich arbeite morgens fokussierter"          | `keyInsights`              |
| `task`      | Aussage    | „Diese Woche Zahnarzttermin machen"         | `tasks`                    |

- **De-Duplizierung** über `nodeKey = "<kind>#<normalisierterName>"`
  (`@Attribute(.unique)`). Gleiche Erwähnung ⇒ derselbe Knoten; `mentionCount`
  ergibt sich aus den verknüpften Einträgen.
- `task`-Knoten haben `isResolved` (im Wissensgraph abhakbar).
- Das Set ist bewusst klein gehalten. Weitere Kinds (z. B. `place`, `event`)
  sind eine einfache Erweiterung des Enums.

## Kanten (`KnowledgeEdge`) – mit und ohne KI

Kanten sind gerichtet, typisiert und **gewichtet** (`weight` = wie oft
beobachtet). Zwei Quellen, klar getrennt über `EdgeOrigin`:

1. **Ohne KI – `cooccurrence`:** Jedes Konzeptpaar im selben Eintrag bekommt eine
   `coOccursWith`-Kante. Deterministisch, immer korrekt, das verlässliche
   Rückgrat des Graphen. (Pro Eintrag auf max. 14 Konzepte gedeckelt, damit die
   Paarzahl nicht quadratisch explodiert.)
2. **Mit KI – `llm`:** Das Modell liefert typisierte Beziehungen (`about`,
   `causes`, `feelsAbout`, …), die über das **feste Relations-Vokabular**
   normalisiert werden.

Symmetrische Kanten (`coOccursWith`, `relatedTo`) werden **einmal** gespeichert
(kanonische Reihenfolge nach Knoten-ID). Wiederholte Beobachtungen erhöhen das
`weight`, statt Duplikate anzulegen.

## Festes Relations-Vokabular (`RelationVocabulary.swift`)

Ein **geschlossenes** Set von Kantentypen ist der wichtigste Schutz gegen einen
chaotischen Graphen – ein kleines lokales Modell erfindet sonst zwanzig
Schreibweisen für „hängt zusammen mit". Jede vom Modell gelieferte Relation wird
über `RelationVocabulary.canonical(_:)` auf genau einen dieser Werte abgebildet;
Unbekanntes fällt auf `relatedTo` zurück (nichts geht verloren).

| RelationType   | Bedeutung (DE)                | symmetrisch | typisch von → nach            |
|----------------|-------------------------------|-------------|-------------------------------|
| `coOccursWith` | kommt gemeinsam vor mit       | ja          | beliebig ↔ beliebig (ohne KI) |
| `relatedTo`    | hängt zusammen mit / Fallback | ja          | beliebig ↔ beliebig           |
| `about`        | handelt von                   | nein        | idea/learning/task → topic/person |
| `involves`     | bezieht ein                   | nein        | task → person                 |
| `feelsAbout`   | Gefühl gegenüber              | nein        | feeling → topic/person        |
| `causes`       | führt zu                      | nein        | beliebig → feeling            |
| `partOf`       | gehört zu                     | nein        | topic → topic                 |
| `dependsOn`    | hängt ab von                  | nein        | task → task/person/topic      |

Neue Relationen werden **nur** hier ergänzt. Die für das Modell erlaubten Werte
werden per `RelationVocabulary.promptList()` direkt in den Analyse-Prompt
injiziert.

## Normalisierung (`NodeNormalization.swift`)

De-Duplizierung hängt vollständig an `normalize(_:)`:

- klein schreiben, Whitespace zusammenfassen, Rand-Satzzeichen entfernen;
- **Umlaute bewusst NICHT falten** (ä→a würde verschiedene Wörter falsch
  zusammenführen – schlecht für deutsche Texte);
- `cleanDisplayName(_:)` bewahrt die Originalschreibweise für die Anzeige;
- `key(kind:name:)` erzeugt den Store-eindeutigen Schlüssel, **nach Kind
  getrennt** (Thema „Sport" ≠ Vorhaben „Sport").

## Pipeline-Einbettung

`KnowledgeGraphService.ingest(_:into:)` läuft am Ende von
`AnalysisService.applyAnalysis` (Main-Actor, rein lokale SwiftData-Mutation):

1. Konzepte aus dem Analyse-Ergebnis upserten (fetch-or-create per `nodeKey`).
2. Eintrag exakt mit diesen Knoten verknüpfen (`entry.nodes` neu setzen ⇒
   idempotent bzgl. Knoten-Mitgliedschaft).
3. Co-Occurrence-Kanten bauen (ohne KI).
4. Typisierte Relationen aus dem Modell mergen (mit KI, über das Vokabular).

Robustheit bleibt erhalten: Ist Ollama offline, wird der Eintrag wie gehabt als
`pending` markiert – der Graph wächst dann bei der Nachanalyse.

## Bewusste Annahmen / Grenzen (Version 1)

- **Re-Analyse:** Knoten-Verknüpfungen sind idempotent; Kantengewichte können bei
  erneuter Analyse desselben Eintrags leicht doppelt zählen (selten, da fertige
  Einträge nicht automatisch neu analysiert werden). Volle Kanten-Provenienz pro
  Eintrag ist eine spätere Erweiterung.
- **`@Attribute(.unique)`** ist bewusst genutzt. Für späteren iCloud/CloudKit-Sync
  müsste das entfallen (CloudKit erlaubt keine Unique-Constraints) – dann Dedup
  rein im Code. Siehe Sync-Planung.
- **Visualisierung:** vorerst eine ruhige, inspizierbare Liste
  (`KnowledgeGraphView`); ein force-directed Canvas kann folgen.

## Nächste Stufen (Roadmap)

- Embeddings pro Eintrag (on-device / Ollama) + semantische Suche.
- GraphRAG: Retrieval, das den Graphen traversiert + Themen-Summaries über Zeit.
- Manuelles Zusammenführen/Umbenennen von Knoten, Aliase.
