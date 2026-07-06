import Foundation
import SwiftData

/// Whether a report covers a **week** or a **month**. Drives the analysis window,
/// the labels and the icon. Deliberately a small closed set.
enum ReportKind: String, Codable, CaseIterable, Identifiable {
    case weekly
    case monthly

    var id: String { rawValue }

    /// Short noun ("Woche" / "Monat").
    var unitLabel: String { self == .weekly ? "Woche" : "Monat" }

    /// Title of a report of this kind.
    var reportTitle: String { self == .weekly ? "Wochenbericht" : "Monatsbericht" }

    /// "ggü. Vorwoche" / "ggü. Vormonat".
    var previousLabel: String { self == .weekly ? "ggü. Vorwoche" : "ggü. Vormonat" }

    var systemImage: String { self == .weekly ? "calendar.badge.clock" : "calendar" }

    /// Calendar unit spanned by one period of this kind.
    var calendarComponent: Calendar.Component { self == .weekly ? .weekOfYear : .month }
}

/// A label with a frequency count (e.g. a topic mentioned 4 times). Stored inline
/// inside `PeriodicReport` as Codable, like `EmotionScore` / `StrategyNote`.
struct CountedTag: Codable, Hashable, Identifiable {
    var label: String
    var count: Int

    var id: String { label.lowercased() }

    init(label: String, count: Int) {
        self.label = label.trimmingCharacters(in: .whitespacesAndNewlines)
        self.count = count
    }
}

/// One point of the report's mood sparkline: an average mood on a given day,
/// stored as an offset from the period start so dates reconstruct without
/// re-querying entries.
struct ReportMoodPoint: Codable, Hashable, Identifiable {
    var dayOffset: Int      // days from `periodStart`
    var value: Double       // -1.0 … 1.0

    var id: Int { dayOffset }
}

/// A **weekly or monthly report**: a stable snapshot of one period, combining
/// locally-computed, deterministic metrics (counts, mood, resilience) with an
/// optional local-LLM narrative. Regenerating a period upserts the same record,
/// so a report is never duplicated for a given window.
///
/// The deterministic fields are always filled (even offline); the narrative
/// fields are best-effort and stay empty when Ollama is unavailable.
@Model
final class PeriodicReport {
    @Attribute(.unique) var id: UUID

    /// Backing store for `kind`.
    private var kindRaw: String

    /// Inclusive start / exclusive end of the covered period.
    var periodStart: Date
    var periodEnd: Date

    /// When this snapshot was last (re)generated.
    var generatedAt: Date

    /// Model that produced the narrative (empty if none / offline).
    var modelName: String = ""

    // MARK: Deterministic metrics (always available)

    var entryCount: Int = 0
    var previousEntryCount: Int = 0
    var daysWritten: Int = 0
    var wordCount: Int = 0

    var resilienceOverall: Int = 0
    var resilienceEmotional: Int = 0
    var resilienceEfficacy: Int = 0
    var resiliencePhysical: Int = 0
    var resilienceDelta: Int = 0
    var resilienceBaseline: Int = 0

    var averageMood: Double = 0
    var moodStart: Double = 0
    var moodEnd: Double = 0
    var moodPoints: [ReportMoodPoint] = []

    var topTopics: [CountedTag] = []
    var newTopics: [String] = []
    var topPeople: [CountedTag] = []
    var topFeelings: [CountedTag] = []
    var energyGivers: [CountedTag] = []
    var energyDrainers: [CountedTag] = []

    var goals: [String] = []
    var openTasks: [String] = []
    var learnings: [String] = []
    var patterns: [String] = []
    var beliefs: [String] = []
    var triggers: [String] = []
    var needs: [String] = []
    var strategies: [StrategyNote] = []

    // MARK: LLM narrative (best-effort)

    /// Narrative recap of the period.
    var narrative: String = ""
    /// What developed / shifted across the period.
    var trajectory: String = ""
    /// A few highlights / turning points.
    var highlights: [String] = []
    /// One sensible focus for the next period.
    var focus: String = ""
    /// Reflective impulses / questions for the next period.
    var recommendations: [String] = []

    var kind: ReportKind {
        get { ReportKind(rawValue: kindRaw) ?? .weekly }
        set { kindRaw = newValue.rawValue }
    }

    /// True once a narrative has been produced (i.e. Ollama ran at least once).
    var hasNarrative: Bool {
        !narrative.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The number of entries seen relative to the previous period (+/-/0).
    var entryCountDelta: Int { entryCount - previousEntryCount }

    var isAboveBaseline: Bool { resilienceOverall >= resilienceBaseline }

    init(kind: ReportKind, periodStart: Date, periodEnd: Date) {
        self.id = UUID()
        self.kindRaw = kind.rawValue
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        self.generatedAt = .now
    }

    /// Human-readable range, e.g. "6.–12. Jan 2026" (week) or "Januar 2026" (month).
    var rangeText: String {
        let calendar = Calendar.current
        switch kind {
        case .monthly:
            return periodStart.formatted(.dateTime.month(.wide).year())
        case .weekly:
            // periodEnd is the exclusive start of the next week; show the last day.
            let lastDay = calendar.date(byAdding: .day, value: -1, to: periodEnd) ?? periodEnd
            let start = periodStart.formatted(.dateTime.day().month(.abbreviated))
            let end = lastDay.formatted(.dateTime.day().month(.abbreviated).year())
            return "\(start) – \(end)"
        }
    }
}
