import Foundation

/// **Resonanz**: deterministic matching between a journal entry and (a) the
/// curated knowledge base (kept `NoteInsight`s) and (b) earlier entries with a
/// similar situation. Deliberately LLM-free: the shared signals are shown to the
/// user, so every match is explainable, always fresh (computed live) and instant.
/// The semantic embedding pass (roadmap) later improves the scores — same UI.
///
/// Scoring: exact matches of extracted signals carry most weight — triggers and
/// patterns (the deeper layer) more than topics; a thin token overlap adds a
/// little. Below `threshold` nothing is shown: better empty than noise.
enum ResonanceEngine {

    struct EntryMatch: Identifiable {
        let entry: JournalEntry
        let score: Double
        /// Human-readable shared signals ("Zeitdruck", "Konflikt mit Anna" …).
        let shared: [String]
        var id: UUID { entry.id }
    }

    struct InsightMatch: Identifiable {
        let insight: NoteInsight
        let score: Double
        let shared: [String]
        var id: UUID { insight.id }
    }

    // MARK: - Public API

    /// Earlier entries that resemble this one. Topic-only overlap is allowed
    /// (two shared topics pass the threshold); a single weak signal is not.
    static func similarEntries(to entry: JournalEntry,
                               in all: [JournalEntry],
                               limit: Int = 3,
                               threshold: Double = 3.0) -> [EntryMatch] {
        guard let analysis = entry.analysis else { return [] }
        let base = Signals(analysis: analysis)
        guard !base.isEmpty else { return [] }

        return all
            .filter { $0.id != entry.id }
            .compactMap { other -> EntryMatch? in
                guard let otherAnalysis = other.analysis else { return nil }
                let (score, shared) = base.match(Signals(analysis: otherAnalysis))
                guard score >= threshold else { return nil }
                return EntryMatch(entry: other, score: score, shared: shared)
            }
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map { $0 }
    }

    /// Kept insights from the knowledge base that speak to this entry.
    static func relevantInsights(to entry: JournalEntry,
                                 from insights: [NoteInsight],
                                 limit: Int = 3,
                                 threshold: Double = 2.0) -> [InsightMatch] {
        guard let analysis = entry.analysis else { return [] }
        let base = Signals(analysis: analysis)
        guard !base.isEmpty else { return [] }

        return insights
            .filter { $0.status == .kept }
            .compactMap { insight -> InsightMatch? in
                let (score, shared) = base.match(insight: insight)
                guard score >= threshold else { return nil }
                return InsightMatch(insight: insight, score: score, shared: shared)
            }
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map { $0 }
    }

    /// Knowledge for the in-editor companion chat, matched against the raw draft
    /// (no analysis exists yet): token overlap plus exact topic hits.
    static func relevantInsights(forDraft text: String,
                                 title: String,
                                 from insights: [NoteInsight],
                                 limit: Int = 3,
                                 threshold: Double = 2.0) -> [NoteInsight] {
        let draftTokens = tokens(of: title + " " + text)
        guard !draftTokens.isEmpty else { return [] }

        return insights
            .filter { $0.status == .kept }
            .compactMap { insight -> (NoteInsight, Double)? in
                var score = 0.0
                for topic in insight.topics where draftTokens.contains(normalize(topic)) {
                    score += 1.5
                }
                let overlap = tokens(of: insight.text).intersection(draftTokens)
                score += Double(min(overlap.count, 4)) * 0.5
                guard score >= threshold else { return nil }
                return (insight, score)
            }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map { $0.0 }
    }

    // MARK: - Signal sets

    /// The extracted signals of one analysis, normalised for matching but keeping
    /// a display form for the shared-signal chips.
    private struct Signals {
        var triggers: [String: String] = [:]   // normalised → display
        var patterns: [String: String] = [:]
        var beliefs: [String: String] = [:]
        var needs: [String: String] = [:]
        var topics: [String: String] = [:]
        var people: [String: String] = [:]
        var feelings: [String: String] = [:]

        /// All content tokens across the signals (for the weak token overlap).
        var allTokens: Set<String> = []

        var isEmpty: Bool {
            triggers.isEmpty && patterns.isEmpty && beliefs.isEmpty && needs.isEmpty
                && topics.isEmpty && people.isEmpty && feelings.isEmpty
        }

        init(analysis: EntryAnalysis) {
            triggers = Self.map(analysis.triggers)
            patterns = Self.map(analysis.patterns)
            beliefs = Self.map(analysis.beliefs)
            needs = Self.map(analysis.needs)
            topics = Self.map(analysis.topics)
            people = Self.map(analysis.people)
            feelings = Self.map(analysis.feelings)
            let everything = analysis.triggers + analysis.patterns + analysis.beliefs
                + analysis.needs + analysis.topics + analysis.people + analysis.feelings
            allTokens = ResonanceEngine.tokens(of: everything.joined(separator: " "))
        }

        private static func map(_ values: [String]) -> [String: String] {
            var out: [String: String] = [:]
            for value in values {
                let display = value.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !display.isEmpty else { continue }
                out[ResonanceEngine.normalize(display)] = display
            }
            return out
        }

        /// Weighted match against another entry's signals.
        func match(_ other: Signals) -> (score: Double, shared: [String]) {
            var score = 0.0
            var shared: [String] = []
            var counted = Set<String>()

            func overlap(_ mine: [String: String], _ theirs: [String: String], weight: Double) {
                for (key, display) in mine where theirs[key] != nil {
                    score += weight
                    counted.insert(key)
                    shared.append(display)
                }
            }
            overlap(triggers, other.triggers, weight: 3.0)
            overlap(patterns, other.patterns, weight: 3.0)
            overlap(beliefs, other.beliefs, weight: 2.5)
            overlap(needs, other.needs, weight: 2.0)
            overlap(topics, other.topics, weight: 2.0)
            overlap(people, other.people, weight: 1.5)
            overlap(feelings, other.feelings, weight: 1.0)

            // Weak token overlap for near-misses ("Zeitdruck" vs "Druck im Job"),
            // excluding tokens of already-counted exact matches.
            let countedTokens = counted.flatMap { ResonanceEngine.tokens(of: $0) }
            let loose = allTokens.intersection(other.allTokens).subtracting(countedTokens)
            score += Double(min(loose.count, 4)) * 0.5

            return (score, Array(shared.prefix(6)))
        }

        /// Weighted match against a knowledge-base insight.
        func match(insight: NoteInsight) -> (score: Double, shared: [String]) {
            var score = 0.0
            var shared: [String] = []

            for topic in insight.topics {
                let key = ResonanceEngine.normalize(topic)
                // An insight topic hitting the deeper layer weighs more than a topic.
                if triggers[key] != nil || patterns[key] != nil || beliefs[key] != nil || needs[key] != nil {
                    score += 2.5
                    shared.append(topic)
                } else if topics[key] != nil || people[key] != nil || feelings[key] != nil {
                    score += 2.0
                    shared.append(topic)
                }
            }

            let sharedTokens = Set(shared.flatMap { ResonanceEngine.tokens(of: $0) })
            let loose = ResonanceEngine.tokens(of: insight.text)
                .intersection(allTokens)
                .subtracting(sharedTokens)
            score += Double(min(loose.count, 4)) * 0.5
            shared.append(contentsOf: loose.sorted().prefix(max(0, 4 - shared.count)))

            return (score, Array(shared.prefix(6)))
        }
    }

    // MARK: - Text helpers

    static func normalize(_ text: String) -> String {
        text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Lowercased content tokens: letters/numbers only, stopwords removed,
    /// length ≥ 4 (German content words are rarely shorter).
    static func tokens(of text: String) -> Set<String> {
        let parts = text.lowercased().split { !$0.isLetter && !$0.isNumber }
        return Set(parts.map(String.init).filter { $0.count >= 4 && !stopwords.contains($0) })
    }

    private static let stopwords: Set<String> = [
        "aber", "alle", "allem", "allen", "aller", "alles", "also", "auch", "beim",
        "bist", "dann", "dass", "dein", "deine", "dem", "den", "denn", "der", "des",
        "diese", "diesem", "diesen", "dieser", "dieses", "doch", "dort", "durch",
        "eine", "einem", "einen", "einer", "eines", "einfach", "etwas", "für",
        "ganz", "gegen", "habe", "haben", "hatte", "hatten", "heute", "hier",
        "ihre", "immer", "kann", "können", "machen", "mehr", "mein", "meine",
        "meinem", "meinen", "meiner", "mich", "mir", "mit", "muss", "nach", "nicht",
        "noch", "nur", "oder", "schon", "sehr", "sein", "seine", "sich", "sie",
        "sind", "soll", "sollte", "über", "und", "uns", "unser", "viel", "vielleicht",
        "vom", "von", "vor", "war", "waren", "was", "weil", "wenn", "werden", "wieder",
        "wird", "wir", "wurde", "zum", "zur"
    ]
}
