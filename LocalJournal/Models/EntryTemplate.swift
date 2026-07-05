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

    /// Ordered hints / questions that scaffold the entry.
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
         sections: [String] = [],
         detail: String = "",
         sortIndex: Int = 0) {
        self.id = UUID()
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.cadenceRaw = cadence.rawValue
        self.sections = sections
        self.detail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        self.sortIndex = sortIndex
        self.createdAt = .now
    }

    /// The starter text a new entry begins with: each hint / question on its own
    /// line with room to write underneath.
    func scaffoldText() -> String {
        sections
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { "\($0)\n\n\n" }
            .joined()
    }
}
