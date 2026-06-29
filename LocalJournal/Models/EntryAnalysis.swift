import Foundation
import SwiftData

/// Structured, locally-generated AI analysis for a single `JournalEntry`.
/// All fields are filled from Gemma's JSON output (see `AnalysisService`).
/// Arrays of primitives are stored directly by SwiftData.
@Model
final class EntryAnalysis {
    @Attribute(.unique) var id: UUID

    /// One or two sentence summary of the entry.
    var summary: String

    /// Detected feelings / moods, e.g. ["ruhig", "überfordert"].
    var feelings: [String]

    /// Raw topic names detected (also promoted to `TopicEntity`).
    var topics: [String]

    /// Raw person names detected (also promoted to `PersonEntity`).
    var people: [String]

    /// Key insights / learnings the entry surfaces.
    var keyInsights: [String]

    /// Recurring patterns the model noticed in this entry.
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

    init(
        id: UUID = UUID(),
        summary: String = "",
        feelings: [String] = [],
        topics: [String] = [],
        people: [String] = [],
        keyInsights: [String] = [],
        patterns: [String] = [],
        comparisonWithLastWeek: String = "",
        moodScore: Double = 0,
        modelName: String = ""
    ) {
        self.id = id
        self.summary = summary
        self.feelings = feelings
        self.topics = topics
        self.people = people
        self.keyInsights = keyInsights
        self.patterns = patterns
        self.comparisonWithLastWeek = comparisonWithLastWeek
        self.moodScore = moodScore
        self.createdAt = .now
        self.modelName = modelName
    }
}
