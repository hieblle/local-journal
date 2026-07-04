import Foundation
import SwiftData

/// Whether a guiding principle is a **value** (how I want to be) or a
/// longer-term **goal** (what I want to reach). Both are *authored by the user*
/// and later compared against their actual entries.
enum PrincipleKind: String, Codable, CaseIterable, Identifiable {
    case value
    case goal

    var id: String { rawValue }

    var singular: String { self == .value ? "Wert" : "Ziel" }
    var plural: String { self == .value ? "Werte" : "Ziele" }
    var systemImage: String { self == .value ? "heart.text.square" : "target" }
}

/// A self-authored **value or goal**. Unlike the AI-detected `goals` on an
/// `EntryAnalysis`, these are written by the user as a stable reference the app
/// can align their behaviour against (see `AnalysisService.checkValueAlignment`).
@Model
final class GuidingPrinciple {
    @Attribute(.unique) var id: UUID

    /// Backing store for `kind`.
    private var kindRaw: String

    /// Short title, e.g. "Ehrlichkeit" or "Mehr Zeit für Familie".
    var title: String

    /// Optional longer description / what it means to me.
    var detail: String

    /// Manual ordering (lower shows first); ties break by creation date.
    var sortIndex: Int = 0

    var createdAt: Date

    var kind: PrincipleKind {
        get { PrincipleKind(rawValue: kindRaw) ?? .value }
        set { kindRaw = newValue.rawValue }
    }

    init(kind: PrincipleKind, title: String, detail: String = "", sortIndex: Int = 0) {
        self.id = UUID()
        self.kindRaw = kind.rawValue
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.detail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        self.sortIndex = sortIndex
        self.createdAt = .now
    }
}
