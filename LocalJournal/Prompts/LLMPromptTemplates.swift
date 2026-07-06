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

    // MARK: - Deeper reflective layer (second pass)

    /// Extract the deeper psychological layer of a single entry: beliefs, needs,
    /// triggers, energy, and problem→solution strategies. Kept as a *separate*
    /// focused prompt so the small local model stays sharp on each task.
    static func deepReflection(entryTitle: String, entryText: String) -> String {
        """
        \(systemPreamble)

        Analysiere den folgenden Journaleintrag auf einer tieferen, reflexiven \
        Ebene. Gib NUR wieder, was der Text klar hergibt oder deutlich nahelegt – \
        erfinde nichts und deute nicht über.

        Gib GENAU dieses JSON zurück:
        {
          "beliefs": ["innere Grundannahmen/Glaubenssätze hinter dem Verhalten, z. B. 'Ich muss immer stark sein'"],
          "needs": ["sichtbare oder unerfüllte Bedürfnisse, z. B. Anerkennung, Ruhe, Nähe"],
          "triggers": ["Auslöser, die Gefühle oder Reaktionen ausgelöst haben, z. B. Kritik, Zeitdruck"],
          "energyGivers": ["was in diesem Eintrag Energie gegeben hat"],
          "energyDrainers": ["was Energie gekostet hat"],
          "strategies": [{"problem": "was schieflief / ein Fehler", "solution": "was geholfen hat / eine Lösung"}]
        }

        Regeln:
        - Kurze, prägnante Formulierungen. Höchstens 3 Einträge pro Liste.
        - "beliefs" sind innere Grundannahmen – KEINE bloßen Themen.
        - "strategies" nur, wenn der Text einen Fehler/ein Problem UND einen \
          Umgang/eine Lösung erkennen lässt.
        - Leere Liste [] verwenden, wenn nichts Klares erkennbar ist.

        Titel: \(entryTitle.isEmpty ? "(kein Titel)" : entryTitle)
        Eintrag:
        \"\"\"
        \(entryText)
        \"\"\"
        """
    }

    /// Narrative synthesis: how the person changed between older and recent
    /// entries. Returns `{ "text": "..." }`.
    static func reflectOnChange(earlySummaries: [String], recentSummaries: [String]) -> String {
        """
        \(systemPreamble)

        Vergleiche die FRÜHEREN mit den JÜNGEREN Einträgen und beschreibe knapp \
        und konkret, wie sich die Person über die Zeit verändert hat: Stimmung, \
        Themen, Umgang mit Schwierigkeiten, wiederkehrende Muster. Wertschätzend, \
        nicht diagnostisch. 3–5 Sätze.

        Gib GENAU dieses JSON zurück:
        { "text": "..." }

        Frühere Einträge:
        \(earlySummaries.isEmpty ? "(keine)" : earlySummaries.map { "- \($0)" }.joined(separator: "\n"))
        Jüngere Einträge:
        \(recentSummaries.isEmpty ? "(keine)" : recentSummaries.map { "- \($0)" }.joined(separator: "\n"))
        """
    }

    /// Compare the person's written values / goals against how they actually
    /// acted in recent entries. Returns `{ "text": "..." }`.
    static func valueAlignment(values: [String], goals: [String], recentSummaries: [String]) -> String {
        """
        \(systemPreamble)

        Gleiche die selbst formulierten WERTE und ZIELE der Person mit ihren \
        tatsächlichen Handlungen in den letzten Einträgen ab. Benenne behutsam, \
        wo Handeln und Werte/Ziele zusammenpassen und wo nicht, und gib 1–2 \
        konkrete, wohlwollende Impulse. Nicht urteilend, keine Ferndiagnose. \
        4–6 Sätze.

        Gib GENAU dieses JSON zurück:
        { "text": "..." }

        Werte: \(csv(values))
        Ziele: \(csv(goals))
        Letzte Einträge:
        \(recentSummaries.isEmpty ? "(keine)" : recentSummaries.map { "- \($0)" }.joined(separator: "\n"))
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

    // MARK: - Weekly / monthly report

    /// Build a warm, grounded **weekly or monthly report** from already-computed,
    /// deterministic metrics plus the period's entry summaries. The numbers are
    /// pre-computed on purpose — the model must not invent figures, only narrate
    /// them. Returns the narrative layer (`PeriodReportNarrative`).
    static func periodReport(metrics m: ReportMetrics) -> String {
        let unit = m.kind.unitLabel
        let topics = csv(m.topTopics.map { "\($0.label) (\($0.count)×)" })
        let newTopics = csv(m.newTopics)
        let feelings = csv(m.topFeelings.map { "\($0.label) (\($0.count)×)" })
        let people = csv(m.topPeople.map(\.label))
        let givers = csv(m.energyGivers.map(\.label))
        let drainers = csv(m.energyDrainers.map(\.label))
        let strategies = m.strategies.isEmpty
            ? "(keine)"
            : m.strategies.map { "\($0.problem) → \($0.solution)" }.joined(separator: "; ")
        let summaries = m.summaries.isEmpty
            ? "(keine)"
            : m.summaries.map { "- \($0)" }.joined(separator: "\n")

        return """
        \(systemPreamble)

        Erstelle einen persönlichen \(m.kind.reportTitle) für den Zeitraum \
        \(rangeDescription(m)) auf Basis der folgenden, bereits lokal berechneten \
        Kennzahlen und Eintrags-Zusammenfassungen. Nutze AUSSCHLIESSLICH diese \
        Informationen – erfinde keine Fakten und keine Zahlen. Schreibe warm, \
        konkret und ermutigend, in der zweiten Person ("du"), nicht diagnostisch. \
        Beziehe dich auf konkrete Themen, Gefühle und Muster.

        Gib GENAU dieses JSON zurück:
        {
          "narrative": "3-5 Sätze: ehrlicher, wertschätzender Rückblick auf den Zeitraum",
          "trajectory": "2-4 Sätze: was sich über den Zeitraum entwickelt oder verändert hat (Stimmung, Themen, Umgang mit Schwierigem)",
          "highlights": ["max. 3 kurze Höhepunkte oder Wendepunkte"],
          "focus": "1 Satz: ein sinnvoller, machbarer Fokus für die/den nächste(n) \(unit)",
          "recommendations": ["2-3 offene, reflexive Fragen oder Impulse für die/den nächste(n) \(unit)"]
        }

        Kennzahlen:
        - Einträge: \(m.entryCount) (Vorperiode: \(m.previousEntryCount)), an \(m.daysWritten) Tag(en), \(m.wordCount) Wörter
        - Resilienz-Score: \(m.resilience.overall)/100 (Veränderung ggü. Vorperiode: \(signed(m.resilience.deltaThisMonth)))
        - Stimmung (Skala -1 bis +1): Durchschnitt \(twoDecimals(m.averageMood)), Verlauf von \(twoDecimals(m.moodStart)) zu \(twoDecimals(m.moodEnd))
        - Häufige Themen: \(topics)
        - Neue Themen ggü. Vorperiode: \(newTopics)
        - Häufige Gefühle: \(feelings)
        - Wichtige Personen: \(people)
        - Energiegeber: \(givers)
        - Energieräuber: \(drainers)
        - Ziele: \(csv(m.goals))
        - Learnings: \(csv(m.learnings))
        - Muster: \(csv(m.patterns))
        - Glaubenssätze: \(csv(m.beliefs))
        - Trigger: \(csv(m.triggers))
        - Bedürfnisse: \(csv(m.needs))
        - Strategien (Problem → Lösung): \(strategies)

        Eintrags-Zusammenfassungen:
        \(summaries)
        """
    }

    /// Human-readable period range for the report prompt.
    private static func rangeDescription(_ m: ReportMetrics) -> String {
        switch m.kind {
        case .monthly:
            return m.periodStart.formatted(.dateTime.month(.wide).year())
        case .weekly:
            let last = Calendar.current.date(byAdding: .day, value: -1, to: m.periodEnd) ?? m.periodEnd
            let start = m.periodStart.formatted(.dateTime.day().month())
            let end = last.formatted(.dateTime.day().month().year())
            return "\(start) – \(end)"
        }
    }

    /// "+3" / "-2" / "±0" for a signed integer delta.
    private static func signed(_ value: Int) -> String {
        value > 0 ? "+\(value)" : (value < 0 ? "\(value)" : "±0")
    }

    /// Two-decimal string with a dot separator, locale-independent.
    private static func twoDecimals(_ value: Double) -> String {
        String(format: "%.2f", value)
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
