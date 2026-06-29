import Foundation
import SwiftData

/// A topic / theme recognised across journal entries, e.g. "Arbeit", "Stress".
/// Created once and re-linked to every entry that surfaces the same theme.
@Model
final class TopicEntity {
    @Attribute(.unique) var id: UUID

    /// Display name, e.g. "Kreativität".
    var name: String

    /// Normalised name used for de-duplication / matching.
    @Attribute(.unique) var normalizedName: String

    var firstSeen: Date
    var lastSeen: Date

    /// Entries tagged with this topic (inverse declared on `JournalEntry.topics`).
    var entries: [JournalEntry]

    var mentionCount: Int { entries.count }

    init(name: String) {
        self.id = UUID()
        self.name = name
        self.normalizedName = TopicEntity.normalize(name)
        self.firstSeen = .now
        self.lastSeen = .now
        self.entries = []
    }

    static func normalize(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
