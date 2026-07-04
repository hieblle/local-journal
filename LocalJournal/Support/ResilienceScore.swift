import Foundation

/// A 0–100 **Resilience Score** derived purely, locally and deterministically
/// from the per-entry AI analysis — no network, instant, explainable.
///
/// The overall score is a weighted blend of three sub-scores:
///
///  - **Emotional stability (40%)** — a good *and* steady mood. Half from the
///    average `moodScore` (level), half from *low* volatility (standard
///    deviation of the daily moods). Someone can be calm at a low mood or jumpy
///    at a high one; both pull the score down.
///  - **Self-efficacy (35%)** — evidence of agency and coping: entries that set
///    goals, capture problem→solution strategies, surface learnings, or name
///    concrete intentions. Baselined at 40 (writing at all shows some agency).
///  - **Körper & Energie (25%)** — self-care: the balance of energy givers vs.
///    drainers plus mentions of rest/sleep/movement/nature. Baselined at 30.
///
/// Windows: the current score uses the last 30 days; `deltaThisMonth` compares
/// it to the previous 30 days; `sixMonthAverage` is the same blend over 180 days
/// as a personal baseline. All sub-scores clamp to 0…100.
struct ResilienceScore {
    var overall: Int
    var emotionalStability: Int
    var selfEfficacy: Int
    var physicalHealth: Int
    var deltaThisMonth: Int
    var sixMonthAverage: Int
    var sampleSize: Int

    /// Need a few analysed entries before the number means anything.
    var hasEnoughData: Bool { sampleSize >= 3 }
    var aboveSixMonthAverage: Bool { overall >= sixMonthAverage }

    static let empty = ResilienceScore(overall: 0, emotionalStability: 0, selfEfficacy: 0,
                                       physicalHealth: 0, deltaThisMonth: 0,
                                       sixMonthAverage: 0, sampleSize: 0)
}

enum ResilienceCalculator {

    static func score(for entries: [JournalEntry],
                      now: Date = .now,
                      calendar: Calendar = .current) -> ResilienceScore {
        func analyses(fromDaysAgo start: Int, toDaysAgo end: Int) -> [EntryAnalysis] {
            let startDate = calendar.date(byAdding: .day, value: -start, to: now) ?? now
            let endDate = calendar.date(byAdding: .day, value: -end, to: now) ?? now
            return entries.compactMap { entry in
                guard let analysis = entry.analysis else { return nil }
                return (entry.date > startDate && entry.date <= endDate) ? analysis : nil
            }
        }

        let current = analyses(fromDaysAgo: 30, toDaysAgo: 0)
        let previous = analyses(fromDaysAgo: 60, toDaysAgo: 30)
        let halfYear = analyses(fromDaysAgo: 180, toDaysAgo: 0)

        let cur = subscores(current)
        let prev = subscores(previous)
        let half = subscores(halfYear)

        let delta = (current.isEmpty || previous.isEmpty) ? 0 : cur.overall - prev.overall

        return ResilienceScore(
            overall: cur.overall,
            emotionalStability: cur.emotional,
            selfEfficacy: cur.efficacy,
            physicalHealth: cur.physical,
            deltaThisMonth: delta,
            sixMonthAverage: half.overall,
            sampleSize: current.count
        )
    }

    // MARK: - Sub-scores

    private struct Sub { var overall: Int; var emotional: Int; var efficacy: Int; var physical: Int }

    private static func subscores(_ a: [EntryAnalysis]) -> Sub {
        guard !a.isEmpty else { return Sub(overall: 0, emotional: 0, efficacy: 0, physical: 0) }
        let e = emotionalStability(a)
        let s = selfEfficacy(a)
        let p = physicalHealth(a)
        let overall = Int((0.40 * Double(e) + 0.35 * Double(s) + 0.25 * Double(p)).rounded())
        return Sub(overall: clamp(overall), emotional: e, efficacy: s, physical: p)
    }

    /// Mood level (55%) + low volatility (45%).
    private static func emotionalStability(_ a: [EntryAnalysis]) -> Int {
        let moods = a.map(\.moodScore)
        let avg = moods.reduce(0, +) / Double(moods.count)          // -1 … 1
        let moodLevel = (avg + 1) / 2 * 100                          // 0 … 100
        let variance = moods.reduce(0) { $0 + ($1 - avg) * ($1 - avg) } / Double(moods.count)
        let sd = variance.squareRoot()                              // ~0 … 1+
        let lowVolatility = (1 - min(sd, 1)) * 100
        return clamp(Int((0.55 * moodLevel + 0.45 * lowVolatility).rounded()))
    }

    /// Agency / coping signals, baselined at 40.
    private static func selfEfficacy(_ a: [EntryAnalysis]) -> Int {
        let n = Double(a.count)
        func rate(_ predicate: (EntryAnalysis) -> Bool) -> Double {
            Double(a.filter(predicate).count) / n
        }
        let goals = rate { !$0.goals.isEmpty }
        let strategies = rate { !$0.strategies.isEmpty }
        let learnings = rate { !$0.keyInsights.isEmpty }
        let tasks = rate { !$0.tasks.isEmpty }
        let signal = 0.30 * goals + 0.30 * strategies + 0.25 * learnings + 0.15 * tasks   // 0 … 1
        return clamp(Int((40 + 60 * signal).rounded()))
    }

    private static let careLexicon = [
        "schlaf", "sleep", "ruhe", "rest", "pause", "erholung", "sport", "bewegung",
        "exercise", "spazier", "lauf", "yoga", "gesund", "health", "körper", "essen",
        "ernährung", "natur", "draußen", "meditation", "achtsam"
    ]

    /// Energy balance (givers vs. drainers) + self-care mentions, baselined at 30.
    private static func physicalHealth(_ a: [EntryAnalysis]) -> Int {
        let givers = a.reduce(0) { $0 + $1.energyGivers.count }
        let drainers = a.reduce(0) { $0 + $1.energyDrainers.count }
        let energyBalance: Double = (givers + drainers) == 0
            ? 0.5
            : Double(givers) / Double(givers + drainers)

        let haystack = a.flatMap { $0.topics + $0.needs + $0.energyGivers }.map { $0.lowercased() }
        let careHits = haystack.reduce(0) { acc, text in
            acc + (careLexicon.contains { text.contains($0) } ? 1 : 0)
        }
        let careSignal = min(Double(careHits) / Double(a.count), 1)

        return clamp(Int((30 + 45 * energyBalance + 25 * careSignal).rounded()))
    }

    private static func clamp(_ value: Int) -> Int { min(max(value, 0), 100) }
}
