# Local Journal

Eine schlichte, **vollständig lokale** Journaling-App für macOS (SwiftUI +
SwiftData). Sie speichert Journaleinträge, analysiert sie mit einem lokalen
**Ollama**-Modell (Gemma) und erzeugt automatisch Zusammenfassungen, Gefühle,
Themen, Personen, Erkenntnisse, Muster und einen Vergleich mit den letzten 7
Tagen. Es gibt **keine Cloud, kein Sync und keine externen APIs** – die einzige
Netzwerkverbindung geht an deinen lokalen Ollama-Server.

## Funktionen (Version 1)

- **Dashboard** – Streak, Wörter diese Woche, Einträge/Wörter gesamt, letzte
  Einträge, kurze KI-Zusammenfassungen, erkannte Gefühle/Themen/Personen/Insights.
- **Editor** – Titel, Datum, Text, optionaler & einstellbarer Schreib-Timer.
  Einträge werden **immer zuerst lokal gespeichert**; die KI-Analyse läuft danach.
- **Journal-Prompt-Bibliothek** – Reflexionsfragen als Schreibimpulse: sichtbar,
  beim Schreiben auswählbar, manuell ergänzbar und per Ollama generierbar.
- **KI-Analyse nach jedem Eintrag** – Zusammenfassung, Themen, Gefühle, Personen,
  Erkenntnisse, Muster und 7-Tage-Vergleich; strukturiert lokal gespeichert.
- **Entitäten** – `PersonEntity` und `TopicEntity` werden einmal angelegt und bei
  erneuter Erwähnung automatisch mit neuen Einträgen verknüpft.
- **Analyse-Seite** – einfache SwiftUI-Charts (Wörter/Tag, Häufigkeit, Stimmung
  über Zeit, häufigste Themen/Personen/Gefühle) plus Entitätslisten.
- **Einstellungen** – Ollama-Adresse & Modell, Auto-Analyse, Timer-Defaults,
  „ausstehende Analysen nachholen“.

Geplante Features (u. a. die **Suche**) stehen in [`Roadmap.md`](./Roadmap.md).

## Voraussetzungen

- macOS 14 (Sonoma) oder neuer, Xcode 16+
- [Ollama](https://ollama.com) lokal installiert und gestartet:

  ```sh
  ollama serve            # startet den lokalen Server auf :11434
  ollama pull gemma3:4b   # kleines, lokales Gemma-Modell laden
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
│                 PersonEntity, TopicEntity, WeeklySummary, AppSettings)
├─ Services/      OllamaService (Netzwerk) · AnalysisService (Pipeline)
├─ Prompts/       LLMPromptTemplates.swift  (technische Prompts für Ollama)
│                 JournalPromptSeedData.swift (Schreibimpulse für Nutzer:innen)
├─ Support/       Statistik, JSON-Parsing, Seeding
└─ Views/         Dashboard · Editor · Prompts · Entries · Analysis · Settings
```

**Zwei Arten von Prompts** – bewusst getrennt:

1. **Journal Prompts** (`JournalPromptSeedData`) = Reflexionsfragen für dich.
2. **LLM Prompt Templates** (`LLMPromptTemplates`) = technische Prompts an Gemma,
   die strukturiertes, JSON-kompatibles Ergebnis anfordern.

## Pragmatische Annahmen (dokumentiert)

- **Modellname:** Der Brief nennt „Gemma 4 4B“. Auf Ollama gibt es aktuell kein
  „Gemma 4“; als kleines lokales Gemma wird daher `gemma3:4b` als Standard
  verwendet. Der Name ist in den **Einstellungen frei konfigurierbar**
  (`AppSettings.defaultModelName`).
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
