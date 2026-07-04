import Foundation

/// Central, single-source-of-truth collection of **LLM prompt templates** —
/// the technical prompts sent to Ollama / Gemma.
///
/// These are intentionally separate from *journal prompts* (the reflection
/// questions shown to the user, seeded in `JournalPromptSeedData`).
///
/// Design notes:
///  - Every template asks for **strict JSON** with stable, English keys so the
///    Swift decoders (`AnalysisService`) stay simple, even though the surrounding
///    instructions and the user's text are German.
///  - The pipeline uses `fullAnalysis(...)` (one round-trip per entry) for
///    efficiency; the individual templates below exist as documented building
///    blocks and can be used standalone (e.g. re-summarise only).
///  - Send these with Ollama's `format: "json"` (see `OllamaService`) to force
///    syntactically valid JSON output.
enum LLMPromptTemplates {

    /// Shared framing prepended to analysis prompts. Keeps the model grounded,
    /// local, and explicitly *non-diagnostic*.
    static let systemPreamble = """
    Du bist ein achtsamer, zurückhaltender Reflexions-Assistent für eine lokale \
    Journaling-App. Du hilfst, Gedanken zu ordnen und Muster sichtbar zu machen. \
    Formuliere niemals therapeutisch-diagnostisch und stelle keine Ferndiagnosen. \
    Antworte ausschließlich mit gültigem JSON, ohne Markdown, ohne Code-Fences \
    und ohne Erklärtext außerhalb des JSON. Verwende die exakt vorgegebenen \
    Schlüssel. Wenn etwas unklar ist, gib leere Werte ([] bzw. "") zurück.
    """

    // MARK: - Combined analysis (used by the pipeline)

    /// One prompt that produces the full per-entry analysis as a single JSON
    /// object. Maps directly onto `EntryAnalysis`.
    static func fullAnalysis(entryTitle: String, entryText: String) -> String {
        """
        \(systemPreamble)

        Analysiere den folgenden Journaleintrag und gib GENAU dieses JSON zurück:
        {
          "summary": "1-2 Sätze, die den Eintrag neutral zusammenfassen",
          "emotions": [{"name": "Gefühl, kurzer Begriff", "intensity": 0}],
          "topics": ["zentrale Themen, kurze Substantive, z. B. Arbeit, Kommunikation"],
          "people": ["konkret erwähnte Personen, nur Namen"],
          "places": ["konkret erwähnte Orte, z. B. Büro, zuhause"],
          "keyInsights": ["wichtige Erkenntnisse oder Learnings aus dem Eintrag"],
          "ideas": ["neue Ideen oder Einfälle, die im Eintrag auftauchen"],
          "tasks": ["konkrete Vorhaben/To-dos, die sich die Person vornimmt"],
          "goals": ["längerfristige Ziele/Vorsätze, z. B. ruhiger in Meetings bleiben"],
          "patterns": ["mögliche wiederkehrende Muster, die der Eintrag andeutet"],
          "moodScore": 0.0,
          "relationships": [
            {"source": "Name/Begriff", "sourceType": "<typ>",
             "relation": "relatedTo", "target": "Name/Begriff", "targetType": "<typ>"}
          ]
        }

        Erlaubte Typen für "sourceType"/"targetType":
        person, topic, feeling, place, goal, idea, learning, task, pattern.

        Regeln:
        - "emotions": "intensity" ist eine ganze Zahl 0–10 (0 = kaum, 10 = sehr stark).
          Verwende Gefühl-Begriffe unter "name" (z. B. Stress, Erleichterung).
        - "moodScore" ist eine Zahl zwischen -1.0 (sehr negativ) und 1.0 (sehr positiv).
        - Erfinde nichts, was nicht im Text vorkommt.
        - Halte die Listen kurz (max. 6 Einträge) und ohne Dopplungen.
        - Lege KEINE eigenen Knoten für Ereignisse wie "Gespräch mit Anna" an;
          verbinde stattdessen die Person direkt mit Thema/Gefühl.
        - "relationships" beschreibt Verbindungen zwischen den oben genannten Begriffen.
          "relation" MUSS exakt einer dieser Werte sein: \(RelationVocabulary.promptList()).
          Wähle die spezifischste passende Relation; nutze "relatedTo" nur, wenn keine andere passt.
          Nutze nur Begriffe, die auch in den Listen oben vorkommen (Personen/Themen/Gefühle/Orte/Ziele).
          Gib höchstens 8 Beziehungen an; bei keiner sinnvollen Beziehung: [].

        Beispiel NUR zur Orientierung für Struktur und Relationen – NICHT ausgeben,
        Inhalte NICHT übernehmen:
        Text: "Das Gespräch mit Anna im Büro war anstrengend. Ich will ruhiger in
        Meetings bleiben."
        Passende relationships:
        [
          {"source": "Anna", "sourceType": "person", "relation": "causes", "target": "anstrengend", "targetType": "feeling"},
          {"source": "anstrengend", "sourceType": "feeling", "relation": "feelsAbout", "target": "Kommunikation", "targetType": "topic"},
          {"source": "ruhiger in Meetings bleiben", "sourceType": "goal", "relation": "about", "target": "Kommunikation", "targetType": "topic"}
        ]

        Titel: \(entryTitle.isEmpty ? "(kein Titel)" : entryTitle)
        Eintrag:
        \"\"\"
        \(entryText)
        \"\"\"
        """
    }

    // MARK: - Individual building blocks

    /// Generate new, **critically reflective** journal prompts grounded in the
    /// user's recent material (topics, patterns, feelings, goals, summaries).
    static func generateReflectionPrompts(recentTopics: [String],
                                          recentPatterns: [String],
                                          recentFeelings: [String],
                                          recentGoals: [String],
                                          recentSummaries: [String],
                                          count: Int = 5) -> String {
        """
        \(systemPreamble)

        Erzeuge \(count) offene, **kritisch-reflexive** Journaling-Fragen, die \
        konkret an das anknüpfen, was die Person zuletzt geschrieben hat. Die \
        Fragen sollen zu ehrlicher Selbstreflexion anregen: blinde Flecken, \
        unausgesprochene Annahmen, Widersprüche, Vermeidungen und wiederkehrende \
        Muster behutsam sichtbar machen und neue Perspektiven eröffnen. Kritisch, \
        aber wertschätzend – nie diagnostisch oder belehrend. Beziehe dich, wo \
        möglich, auf die genannten Themen/Muster/Gefühle/Ziele. Jede Frage ist \
        EINE offene Frage (kein Ja/Nein).

        Gib GENAU dieses JSON zurück:
        { "prompts": ["Frage 1", "Frage 2", "..."] }

        Themen: \(csv(recentTopics))
        Wiederkehrende Muster: \(csv(recentPatterns))
        Gefühle: \(csv(recentFeelings))
        Ziele/Vorhaben: \(csv(recentGoals))
        Letzte Zusammenfassungen:
        \(recentSummaries.isEmpty ? "(keine)" : recentSummaries.map { "- \($0)" }.joined(separator: "\n"))
        """
    }

    /// Generate critically reflective follow-up questions for **one specific
    /// entry**, grounded in its text and detected signals.
    static func reflectionPromptsForEntry(entryTitle: String,
                                          entryText: String,
                                          topics: [String],
                                          patterns: [String],
                                          feelings: [String],
                                          goals: [String],
                                          count: Int = 4) -> String {
        """
        \(systemPreamble)

        Lies den folgenden Journaleintrag und erzeuge \(count) **kritisch-reflexive** \
        Anschlussfragen NUR zu diesem Eintrag. Die Fragen sollen die Person zu einer \
        tieferen, ehrlichen Auseinandersetzung mit dem Geschriebenen einladen: \
        hinterfrage Annahmen, benenne mögliche blinde Flecken, Vermeidungen oder \
        Widersprüche behutsam und öffne neue Perspektiven. Kritisch, aber \
        wertschätzend – nie diagnostisch. Jede Frage ist EINE offene Frage \
        (kein Ja/Nein) und knüpft konkret am Inhalt an.

        Gib GENAU dieses JSON zurück:
        { "prompts": ["Frage 1", "Frage 2", "..."] }

        Erkannte Themen: \(csv(topics))
        Erkannte Muster: \(csv(patterns))
        Erkannte Gefühle: \(csv(feelings))
        Ziele/Vorhaben: \(csv(goals))

        Titel: \(entryTitle.isEmpty ? "(kein Titel)" : entryTitle)
        Eintrag:
        \"\"\"
        \(entryText)
        \"\"\"
        """
    }

    /// Compact comma-separated list for prompt context, or a placeholder.
    private static func csv(_ items: [String]) -> String {
        items.isEmpty ? "(keine)" : items.joined(separator: ", ")
    }

    /// Summarise a single entry.
    static func summarizeEntry(entryText: String) -> String {
        """
        \(systemPreamble)

        Fasse den folgenden Journaleintrag in 1-2 neutralen Sätzen zusammen.
        Gib GENAU dieses JSON zurück:
        { "summary": "..." }

        Eintrag:
        \"\"\"
        \(entryText)
        \"\"\"
        """
    }

    /// Extract feelings / moods plus a coarse mood score.
    static func extractFeelings(entryText: String) -> String {
        """
        \(systemPreamble)

        Erkenne Gefühle und Stimmungen im folgenden Eintrag.
        Gib GENAU dieses JSON zurück:
        { "feelings": ["..."], "moodScore": 0.0 }
        "moodScore" liegt zwischen -1.0 und 1.0.

        Eintrag:
        \"\"\"
        \(entryText)
        \"\"\"
        """
    }

    /// Extract mentioned people.
    static func extractPeople(entryText: String) -> String {
        """
        \(systemPreamble)

        Erkenne konkret erwähnte Personen (nur Namen) im folgenden Eintrag.
        Gib GENAU dieses JSON zurück:
        { "people": ["..."] }

        Eintrag:
        \"\"\"
        \(entryText)
        \"\"\"
        """
    }

    /// Extract topics / themes.
    static func extractTopics(entryText: String) -> String {
        """
        \(systemPreamble)

        Erkenne zentrale Themen (kurze Substantive) im folgenden Eintrag.
        Gib GENAU dieses JSON zurück:
        { "topics": ["..."] }

        Eintrag:
        \"\"\"
        \(entryText)
        \"\"\"
        """
    }

    /// Extract key insights / learnings.
    static func extractKeyInsights(entryText: String) -> String {
        """
        \(systemPreamble)

        Extrahiere die wichtigsten Erkenntnisse / Learnings aus dem Eintrag.
        Gib GENAU dieses JSON zurück:
        { "keyInsights": ["..."] }

        Eintrag:
        \"\"\"
        \(entryText)
        \"\"\"
        """
    }

    /// Detect recurring patterns across several recent summaries.
    static func detectPatterns(recentSummaries: [String]) -> String {
        """
        \(systemPreamble)

        Erkenne wiederkehrende Muster und Trends in den folgenden \
        Zusammenfassungen der letzten Einträge.
        Gib GENAU dieses JSON zurück:
        { "patterns": ["..."], "trends": ["..."] }

        Zusammenfassungen:
        \(recentSummaries.map { "- \($0)" }.joined(separator: "\n"))
        """
    }

    /// Compare the current entry against the last 7 days of summaries.
    static func compareWithLastWeek(currentSummary: String,
                                    lastWeekSummaries: [String]) -> String {
        """
        \(systemPreamble)

        Vergleiche den aktuellen Eintrag mit den Zusammenfassungen der letzten \
        7 Tage. Beschreibe knapp, was sich verändert, wiederholt oder \
        zugespitzt hat.
        Gib GENAU dieses JSON zurück:
        { "comparison": "2-4 Sätze", "patterns": ["..."] }

        Aktueller Eintrag (Zusammenfassung): \(currentSummary)
        Letzte 7 Tage:
        \(lastWeekSummaries.isEmpty ? "(keine vorherigen Einträge)" : lastWeekSummaries.map { "- \($0)" }.joined(separator: "\n"))
        """
    }

    /// Build a weekly digest from a set of entry summaries.
    static func weeklySummary(summaries: [String],
                              topics: [String],
                              people: [String]) -> String {
        """
        \(systemPreamble)

        Erstelle aus den folgenden Eintrags-Zusammenfassungen einer Woche eine \
        kompakte Wochenübersicht.
        Gib GENAU dieses JSON zurück:
        {
          "summary": "kurzer Fließtext zur Woche",
          "moodTrend": "1 Satz zum Stimmungsverlauf",
          "topTopics": ["..."],
          "topPeople": ["..."],
          "insights": ["..."]
        }

        Zusammenfassungen:
        \(summaries.map { "- \($0)" }.joined(separator: "\n"))
        Häufige Themen: \(topics.joined(separator: ", "))
        Häufige Personen: \(people.joined(separator: ", "))
        """
    }

    /// Produce short dashboard insights from the most recent analyses.
    static func dashboardInsights(recentSummaries: [String],
                                  recentFeelings: [String],
                                  recentTopics: [String]) -> String {
        """
        \(systemPreamble)

        Erzeuge eine sehr knappe Dashboard-Übersicht für die letzten Einträge.
        Gib GENAU dieses JSON zurück:
        {
          "headline": "1 Satz, was gerade zentral ist",
          "feelings": ["..."],
          "topics": ["..."],
          "insights": ["max. 3 kurze Erkenntnisse"]
        }

        Letzte Zusammenfassungen:
        \(recentSummaries.map { "- \($0)" }.joined(separator: "\n"))
        Zuletzt erkannte Gefühle: \(recentFeelings.joined(separator: ", "))
        Zuletzt erkannte Themen: \(recentTopics.joined(separator: ", "))
        """
    }
}
