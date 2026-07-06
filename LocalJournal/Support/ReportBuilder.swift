import Foundation

/// Deterministic, locally-computed metrics for one report period. Pure (no
/// SwiftData writes, no network), so it is easy to reason about and test. The
/// service turns this into a stored `PeriodicReport` and layers the LLM
/// narrative on top.
struct ReportMetrics {
    var kind: ReportKind
    var periodStart: Date
    var periodEnd: Date

    var entryCount: Int
    var previousEntryCount: Int
    var daysWritten: Int
    var wordCount: Int

    var resilience: ResilienceScore

    var averageMood: Double
    var moodStart: Double
    var moodEnd: Double
    var moodPoints: [ReportMoodPoint]

    var topTopics: [CountedTag]
    var newTopics: [String]
    var topPeople: [CountedTag]
    var topFeelings: [CountedTag]
    var energyGivers: [CountedTag]
    var energyDrainers: [CountedTag]

    var goals: [String]
    var openTasks: [String]
    var learnings: [String]
    var patterns: [String]
    var beliefs: [String]
    var triggers: [String]
    var needs: [String]
    var strategies: [StrategyNote]

    /// Entry summaries for the LLM narrative prompt (not persisted on the model).
    var summaries: [String]

    var hasEntries: Bool { entryCount > 0 }
}

/// Builds `ReportMetrics` for a week/month from the full entry set. Also owns the
/// period-window arithmetic (which week/month a date falls in, the previous one,
/// the six-month baseline).
enum ReportBuilder {

    /// The calendar interval (start ..< end) of the period of `kind` that
    /// contains `date`.
    static func interval(kind: ReportKind,
                         containing date: Date,
                         calendar: Calendar = .current) -> DateInterval? {
        calendar.dateInterval(of: kind.calendarComponent, for: date)
    }

    /// A reference date inside the **last completed** period before `now`
    /// (used by auto-generation).
    static func completedReference(kind: ReportKind,
                                   before now: Date = .now,
                                   calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: kind.calendarComponent, value: -1, to: now) ?? now
    }

    /// Compute all deterministic metrics for the period of `kind` that contains
    /// `reference`, using the full `entries` set for previous-period comparison
    /// and the six-month baseline.
    static func metrics(kind: ReportKind,
                        entries: [JournalEntry],
                        reference: Date,
                        calendar: Calendar = .current) -> ReportMetrics {
        let window = interval(kind: kind, containing: reference, calendar: calendar)
            ?? DateInterval(start: calendar.startOfDay(for: reference), duration: 0)
        let previousRef = calendar.date(byAdding: kind.calendarComponent, value: -1, to: reference) ?? window.start
        let previousWindow = interval(kind: kind, containing: previousRef, calendar: calendar)
            ?? DateInterval(start: window.start, duration: 0)
        let baselineStart = calendar.date(byAdding: .day, value: -180, to: window.end) ?? window.start

        func inRange(_ entry: JournalEntry, _ range: DateInterval) -> Bool {
            entry.date >= range.start && entry.date < range.end
        }

        let periodEntries = entries.filter { inRange($0, window) }.sorted { $0.date < $1.date }
        let previousEntries = entries.filter { inRange($0, previousWindow) }
        let periodAnalyses = periodEntries.compactMap(\.analysis)
        let previousAnalyses = previousEntries.compactMap(\.analysis)
        let baselineAnalyses = entries
            .filter { $0.date >= baselineStart && $0.date < window.end }
            .compactMap(\.analysis)

        // Resilience aligned to this period (vs. previous period, vs. baseline).
        let resilience = ResilienceCalculator.score(current: periodAnalyses,
                                                     previous: previousAnalyses,
                                                     baseline: baselineAnalyses)

        // Mood: average, first→last, and a per-day sparkline.
        let moods = periodAnalyses.map(\.moodScore)
        let averageMood = moods.isEmpty ? 0 : moods.reduce(0, +) / Double(moods.count)
        let moodStart = periodAnalyses.first?.moodScore ?? 0
        let moodEnd = periodAnalyses.last?.moodScore ?? 0
        let moodPoints = moodSparkline(periodEntries, from: window.start, calendar: calendar)

        // Word / day activity.
        let wordCount = periodEntries.reduce(0) { $0 + $1.wordCount }
        let daysWritten = Set(periodEntries.map { calendar.startOfDay(for: $0.date) }).count

        // Frequency aggregates.
        let topTopics = counted(periodAnalyses.map(\.topics), limit: 8)
        let previousTopicKeys = Set(previousAnalyses.flatMap(\.topics).map { $0.lowercased() })
        let newTopics = topTopics
            .map(\.label)
            .filter { !previousTopicKeys.contains($0.lowercased()) }
            .prefix(6)
            .map { $0 }

        return ReportMetrics(
            kind: kind,
            periodStart: window.start,
            periodEnd: window.end,
            entryCount: periodEntries.count,
            previousEntryCount: previousEntries.count,
            daysWritten: daysWritten,
            wordCount: wordCount,
            resilience: resilience,
            averageMood: averageMood,
            moodStart: moodStart,
            moodEnd: moodEnd,
            moodPoints: moodPoints,
            topTopics: topTopics,
            newTopics: newTopics,
            topPeople: counted(periodAnalyses.map(\.people), limit: 6),
            topFeelings: counted(periodAnalyses.map(\.feelings), limit: 8),
            energyGivers: counted(periodAnalyses.map(\.energyGivers), limit: 6),
            energyDrainers: counted(periodAnalyses.map(\.energyDrainers), limit: 6),
            goals: unique(periodAnalyses.flatMap(\.goals), limit: 8),
            openTasks: unique(periodAnalyses.flatMap(\.tasks), limit: 8),
            learnings: unique(periodAnalyses.flatMap(\.keyInsights), limit: 8),
            patterns: unique(periodAnalyses.flatMap(\.patterns), limit: 8),
            beliefs: unique(periodAnalyses.flatMap(\.beliefs), limit: 6),
            triggers: unique(periodAnalyses.flatMap(\.triggers), limit: 6),
            needs: unique(periodAnalyses.flatMap(\.needs), limit: 6),
            strategies: uniqueStrategies(periodAnalyses.flatMap(\.strategies), limit: 6),
            summaries: periodAnalyses.compactMap { $0.summary.isEmpty ? nil : $0.summary }.prefix(14).map { $0 }
        )
    }

    // MARK: - Aggregation helpers

    /// Average mood per day (only for days that actually have entries), as offsets
    /// from `start` so the caller can reconstruct dates.
    private static func moodSparkline(_ entries: [JournalEntry],
                                      from start: Date,
                                      calendar: Calendar) -> [ReportMoodPoint] {
        let startDay = calendar.startOfDay(for: start)
        var byOffset: [Int: [Double]] = [:]
        for entry in entries {
            guard let analysis = entry.analysis else { continue }
            let day = calendar.startOfDay(for: entry.date)
            let offset = calendar.dateComponents([.day], from: startDay, to: day).day ?? 0
            byOffset[offset, default: []].append(analysis.moodScore)
        }
        return byOffset.keys.sorted().map { offset in
            let values = byOffset[offset] ?? []
            let mean = values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
            return ReportMoodPoint(dayOffset: offset, value: mean)
        }
    }

    /// Count occurrences across several string lists, most frequent first
    /// (ties broken alphabetically), keeping the first-seen casing.
    static func counted(_ lists: [[String]], limit: Int) -> [CountedTag] {
        var counts: [String: Int] = [:]
        var display: [String: String] = [:]
        for list in lists {
            for raw in list {
                let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !value.isEmpty else { continue }
                let key = value.lowercased()
                counts[key, default: 0] += 1
                if display[key] == nil { display[key] = value }
            }
        }
        return counts
            .map { CountedTag(label: display[$0.key] ?? $0.key, count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.label < $1.label }
            .prefix(limit)
            .map { $0 }
    }

    /// Order-preserving, case-insensitive de-duplication with a cap.
    static func unique(_ values: [String], limit: Int) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = trimmed.lowercased()
            guard !trimmed.isEmpty, seen.insert(key).inserted else { continue }
            out.append(trimmed)
            if out.count >= limit { break }
        }
        return out
    }

    private static func uniqueStrategies(_ values: [StrategyNote], limit: Int) -> [StrategyNote] {
        var seen = Set<String>()
        var out: [StrategyNote] = []
        for note in values {
            guard !(note.problem.isEmpty && note.solution.isEmpty),
                  seen.insert(note.id).inserted else { continue }
            out.append(note)
            if out.count >= limit { break }
        }
        return out
    }
}

// MARK: - Applying metrics to the stored model

extension PeriodicReport {
    /// Copy the deterministic metrics onto this report (idempotent; the narrative
    /// is applied separately).
    func apply(_ m: ReportMetrics) {
        periodStart = m.periodStart
        periodEnd = m.periodEnd
        entryCount = m.entryCount
        previousEntryCount = m.previousEntryCount
        daysWritten = m.daysWritten
        wordCount = m.wordCount

        resilienceOverall = m.resilience.overall
        resilienceEmotional = m.resilience.emotionalStability
        resilienceEfficacy = m.resilience.selfEfficacy
        resiliencePhysical = m.resilience.physicalHealth
        resilienceDelta = m.resilience.deltaThisMonth
        resilienceBaseline = m.resilience.sixMonthAverage

        averageMood = m.averageMood
        moodStart = m.moodStart
        moodEnd = m.moodEnd
        moodPoints = m.moodPoints

        topTopics = m.topTopics
        newTopics = m.newTopics
        topPeople = m.topPeople
        topFeelings = m.topFeelings
        energyGivers = m.energyGivers
        energyDrainers = m.energyDrainers

        goals = m.goals
        openTasks = m.openTasks
        learnings = m.learnings
        patterns = m.patterns
        beliefs = m.beliefs
        triggers = m.triggers
        needs = m.needs
        strategies = m.strategies
    }
}
