import Foundation

/// Pure, dependency-free statistics computed from journal entries. Kept out of
/// the views so the dashboard / analysis pages stay declarative.
enum JournalStatistics {

    // MARK: - Totals

    static func totalWords(_ entries: [JournalEntry]) -> Int {
        entries.reduce(0) { $0 + $1.wordCount }
    }

    /// Words written in the current calendar week.
    static func wordsThisWeek(_ entries: [JournalEntry], now: Date = .now,
                              calendar: Calendar = .current) -> Int {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: now) else { return 0 }
        return entries
            .filter { week.contains($0.date) }
            .reduce(0) { $0 + $1.wordCount }
    }

    /// Consecutive days (ending today, or yesterday if nothing yet today) that
    /// contain at least one entry.
    static func currentStreak(_ entries: [JournalEntry], now: Date = .now,
                              calendar: Calendar = .current) -> Int {
        let days = Set(entries.map { calendar.startOfDay(for: $0.date) })
        guard !days.isEmpty else { return 0 }

        var day = calendar.startOfDay(for: now)
        // Grace period: not having journaled *today* yet shouldn't break a streak.
        if !days.contains(day) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = yesterday
        }

        var streak = 0
        while days.contains(day) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return streak
    }

    // MARK: - Chart series

    struct DayValue: Identifiable {
        var id: Date { day }
        let day: Date
        let value: Double
    }

    /// Total words per day for the last `days` days (zero-filled for gaps).
    static func wordsPerDay(_ entries: [JournalEntry], days: Int = 30,
                            now: Date = .now, calendar: Calendar = .current) -> [DayValue] {
        bucketByDay(entries, days: days, now: now, calendar: calendar) { bucket in
            Double(bucket.reduce(0) { $0 + $1.wordCount })
        }
    }

    /// Entry count per day for the last `days` days (journaling frequency).
    static func entriesPerDay(_ entries: [JournalEntry], days: Int = 30,
                              now: Date = .now, calendar: Calendar = .current) -> [DayValue] {
        bucketByDay(entries, days: days, now: now, calendar: calendar) { bucket in
            Double(bucket.count)
        }
    }

    /// Average mood score per day over the last `days` days, for days that have
    /// at least one analysed entry (gaps are omitted so the line isn't dragged
    /// to zero).
    static func moodPerDay(_ entries: [JournalEntry], days: Int = 30,
                           now: Date = .now, calendar: Calendar = .current) -> [DayValue] {
        let today = calendar.startOfDay(for: now)
        var result: [DayValue] = []
        for offset in stride(from: days - 1, through: 0, by: -1) {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let scores = entries
                .filter { calendar.isDate($0.date, inSameDayAs: day) }
                .compactMap { $0.analysis?.moodScore }
            guard !scores.isEmpty else { continue }
            let avg = scores.reduce(0, +) / Double(scores.count)
            result.append(DayValue(day: day, value: avg))
        }
        return result
    }

    private static func bucketByDay(_ entries: [JournalEntry], days: Int,
                                    now: Date, calendar: Calendar,
                                    reduce: ([JournalEntry]) -> Double) -> [DayValue] {
        let today = calendar.startOfDay(for: now)
        var result: [DayValue] = []
        for offset in stride(from: days - 1, through: 0, by: -1) {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let bucket = entries.filter { calendar.isDate($0.date, inSameDayAs: day) }
            result.append(DayValue(day: day, value: reduce(bucket)))
        }
        return result
    }

    // MARK: - Aggregated text signals

    struct Counted: Identifiable {
        var id: String { label }
        let label: String
        let count: Int
    }

    /// Most frequent feelings across the given analyses.
    static func topFeelings(_ entries: [JournalEntry], limit: Int = 8) -> [Counted] {
        tally(entries.flatMap { $0.analysis?.feelings ?? [] }, limit: limit)
    }

    private static func tally(_ values: [String], limit: Int) -> [Counted] {
        var counts: [String: Int] = [:]
        for value in values {
            let key = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { continue }
            counts[key, default: 0] += 1
        }
        return counts
            .sorted { $0.value > $1.value || ($0.value == $1.value && $0.key < $1.key) }
            .prefix(limit)
            .map { Counted(label: $0.key, count: $0.value) }
    }
}
