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
          "feelings": ["erkannte Gefühle/Stimmungen, kurze Begriffe"],
          "topics": ["zentrale Themen, kurze Substantive, z. B. Arbeit, Stress"],
          "people": ["konkret erwähnte Personen, nur Namen"],
          "keyInsights": ["wichtige Erkenntnisse oder Learnings aus dem Eintrag"],
          "patterns": ["mögliche wiederkehrende Muster, die der Eintrag andeutet"],
          "moodScore": 0.0
        }

        Regeln:
        - "moodScore" ist eine Zahl zwischen -1.0 (sehr negativ) und 1.0 (sehr positiv).
        - Erfinde keine Personen oder Themen, die nicht im Text vorkommen.
        - Halte die Listen kurz (max. 6 Einträge) und ohne Dopplungen.

        Titel: \(entryTitle.isEmpty ? "(kein Titel)" : entryTitle)
        Eintrag:
        \"\"\"
        \(entryText)
        \"\"\"
        """
    }

    // MARK: - Individual building blocks

    /// Generate new journal reflection prompts from the user's recent themes.
    static func generateReflectionPrompts(recentTopics: [String],
                                          recentSummaries: [String],
                                          count: Int = 5) -> String {
        """
        \(systemPreamble)

        Erzeuge \(count) neue, offene Reflexionsfragen für das Journaling, \
        passend zu den bisherigen Themen der Person. Die Fragen sollen Reflexion \
        vertiefen, Muster sichtbar machen und neue Perspektiven anbieten – \
        niemals diagnostisch.

        Gib GENAU dieses JSON zurück:
        { "prompts": ["Frage 1", "Frage 2", "..."] }

        Bisherige Themen: \(recentTopics.isEmpty ? "(noch keine)" : recentTopics.joined(separator: ", "))
        Letzte Zusammenfassungen:
        \(recentSummaries.isEmpty ? "(keine)" : recentSummaries.map { "- \($0)" }.joined(separator: "\n"))
        """
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
