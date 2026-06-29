import Foundation
import SwiftData

/// A rolling weekly digest produced by the AI from that week's entries.
/// Used by the dashboard and analysis page for "last 7 days" context.
@Model
final class WeeklySummary {
    @Attribute(.unique) var id: UUID

    var weekStart: Date
    var weekEnd: Date

    /// Narrative summary of the week.
    var summary: String

    /// Most prominent topics that week.
    var topTopics: [String]

    /// Most mentioned people that week.
    var topPeople: [String]

    /// Short description of the mood trend across the week.
    var moodTrend: String

    /// Number of entries the summary was built from.
    var entryCount: Int

    /// Key insights of the week.
    var insights: [String]

    var createdAt: Date

    init(
        id: UUID = UUID(),
        weekStart: Date,
        weekEnd: Date,
        summary: String = "",
        topTopics: [String] = [],
        topPeople: [String] = [],
        moodTrend: String = "",
        entryCount: Int = 0,
        insights: [String] = []
    ) {
        self.id = id
        self.weekStart = weekStart
        self.weekEnd = weekEnd
        self.summary = summary
        self.topTopics = topTopics
        self.topPeople = topPeople
        self.moodTrend = moodTrend
        self.entryCount = entryCount
        self.insights = insights
        self.createdAt = .now
    }
}
