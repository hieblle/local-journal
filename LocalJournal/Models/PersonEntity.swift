import Foundation
import SwiftData

/// A person recognised across journal entries. Created once and re-linked to
/// every entry that mentions the same (case-insensitive) name.
@Model
final class PersonEntity {
    @Attribute(.unique) var id: UUID

    /// Display name, e.g. "Anna".
    var name: String

    /// Normalised (lowercased, trimmed) name used for de-duplication / matching.
    @Attribute(.unique) var normalizedName: String

    var firstSeen: Date
    var lastSeen: Date

    /// Entries that mention this person (inverse declared on `JournalEntry.people`).
    var entries: [JournalEntry]

    var mentionCount: Int { entries.count }

    init(name: String) {
        self.id = UUID()
        self.name = name
        self.normalizedName = PersonEntity.normalize(name)
        self.firstSeen = .now
        self.lastSeen = .now
        self.entries = []
    }

    static func normalize(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
