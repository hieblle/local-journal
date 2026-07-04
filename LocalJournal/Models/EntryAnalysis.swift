import Foundation
import SwiftData

/// A single detected emotion with a coarse intensity (0–10). Stored as a Codable
/// value type inside `EntryAnalysis.emotions` — SwiftData persists it inline.
struct EmotionScore: Codable, Hashable, Identifiable {
    var name: String
    var intensity: Int          // 0 (kaum) … 10 (sehr stark)

    var id: String { name.lowercased() }

    /// Clamp to the valid range and tidy the name.
    init(name: String, intensity: Int) {
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.intensity = min(max(intensity, 0), 10)
    }
}

/// Structured, locally-generated AI analysis for a single `JournalEntry`.
/// All fields are filled from Gemma's JSON output (see `AnalysisService`).
/// This is the canonical per-entry metadata record used by the dashboard,
/// analysis charts, the knowledge graph and the "Merken" board.
@Model
final class EntryAnalysis {
    @Attribute(.unique) var id: UUID

    /// One or two sentence summary of the entry.
    var summary: String

    /// Detected emotions with intensity, e.g. [{"Stress", 7}, {"Erleichterung", 4}].
    /// The richer, canonical source; `feelings` below is derived from it.
    var emotions: [EmotionScore] = []

    /// Plain feeling names (derived from `emotions`). Kept for the existing
    /// charts / chips / graph that only need names.
    var feelings: [String]

    /// Raw topic names detected (also promoted to `TopicEntity`).
    var topics: [String]

    /// Raw person names detected (also promoted to `PersonEntity`).
    var people: [String]

    /// Key insights / learnings the entry surfaces (also promoted to `.learning` nodes).
    var keyInsights: [String]

    /// New ideas that surfaced in the entry (also promoted to `.idea` nodes).
    /// Default keeps automatic migration clean for stores created before graphs.
    var ideas: [String] = []

    /// Concrete intentions / to-dos the person set (also promoted to `.task` nodes).
    var tasks: [String] = []

    /// Longer-term goals the entry touches (also promoted to `.goal` nodes).
    var goals: [String] = []

    /// Places mentioned (also promoted to `.place` nodes).
    var places: [String] = []

    /// Recurring patterns the model noticed in this entry (also promoted to `.pattern` nodes).
    var patterns: [String]

    /// Free-text comparison of this entry against the last 7 days.
    var comparisonWithLastWeek: String

    /// Coarse mood score in -1.0 … 1.0 for charting over time (0 if unknown).
    var moodScore: Double

    var createdAt: Date

    /// Model that produced this analysis (for transparency / debugging).
    var modelName: String

    /// Inverse side of `JournalEntry.analysis`.
    var entry: JournalEntry?

    /// Average emotion intensity (0–10), handy for charts. 0 if none.
    var averageIntensity: Double {
        guard !emotions.isEmpty else { return 0 }
        return Double(emotions.map(\.intensity).reduce(0, +)) / Double(emotions.count)
    }

    init(
        id: UUID = UUID(),
        summary: String = "",
        emotions: [EmotionScore] = [],
        feelings: [String] = [],
        topics: [String] = [],
        people: [String] = [],
        keyInsights: [String] = [],
        ideas: [String] = [],
        tasks: [String] = [],
        goals: [String] = [],
        places: [String] = [],
        patterns: [String] = [],
        comparisonWithLastWeek: String = "",
        moodScore: Double = 0,
        modelName: String = ""
    ) {
        self.id = id
        self.summary = summary
        self.emotions = emotions
        self.feelings = feelings
        self.topics = topics
        self.people = people
        self.keyInsights = keyInsights
        self.ideas = ideas
        self.tasks = tasks
        self.goals = goals
        self.places = places
        self.patterns = patterns
        self.comparisonWithLastWeek = comparisonWithLastWeek
        self.moodScore = moodScore
        self.createdAt = .now
        self.modelName = modelName
    }
}
