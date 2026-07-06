import Foundation
import SwiftData

/// How often a template is typically used — purely informational (a badge and a
/// grouping hint), no scheduling is implied.
enum TemplateCadence: String, Codable, CaseIterable, Identifiable {
    case flexible
    case daily
    case weekly
    case monthly
    case yearly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .flexible: return "Flexibel"
        case .daily:    return "Täglich"
        case .weekly:   return "Wöchentlich"
        case .monthly:  return "Monatlich"
        case .yearly:   return "Jährlich"
        }
    }

    var systemImage: String {
        switch self {
        case .flexible: return "square.dashed"
        case .daily:    return "sun.max"
        case .weekly:   return "calendar"
        case .monthly:  return "calendar.badge.clock"
        case .yearly:   return "sparkles"
        }
    }
}

/// A **self-made entry template**: a named scaffold of hints / questions the
/// user starts an entry from (e.g. a daily reflection, a weekly review). Applying
/// it pre-fills the editor's title and text so the user can just write.
@Model
final class EntryTemplate {
    @Attribute(.unique) var id: UUID

    var name: String

    /// Backing store for `cadence`.
    private var cadenceRaw: String

    /// The template body: free text the new entry starts from (headings,
    /// questions, prompts — whatever the user writes).
    var text: String = ""

    /// Legacy per-question scaffold (older templates). Kept for migration; new
    /// templates use `text`. Backfilled into `text` on launch.
    var sections: [String]

    /// Optional one-line description shown on the card.
    var detail: String

    /// Manual ordering (lower shows first); ties break by creation date.
    var sortIndex: Int = 0

    var createdAt: Date

    var cadence: TemplateCadence {
        get { TemplateCadence(rawValue: cadenceRaw) ?? .flexible }
        set { cadenceRaw = newValue.rawValue }
    }

    init(name: String,
         cadence: TemplateCadence = .flexible,
         text: String = "",
         sections: [String] = [],
         detail: String = "",
         sortIndex: Int = 0) {
        self.id = UUID()
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.cadenceRaw = cadence.rawValue
        self.text = text
        self.sections = sections
        self.detail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        self.sortIndex = sortIndex
        self.createdAt = .now
    }

    /// Body text used for display / editing (falls back to the legacy per-question
    /// scaffold for old templates).
    var bodyText: String {
        text.isEmpty ? sections.joined(separator: "\n\n") : text
    }

    /// The starter text a new entry begins with.
    func scaffoldText() -> String { bodyText }
}
