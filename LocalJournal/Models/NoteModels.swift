import Foundation
import SwiftData

/// What kind of lasting value a distilled insight carries.
enum NoteInsightKind: String, Codable, CaseIterable, Identifiable {
    case recommendation   // Empfehlung: "mach X, wenn Y"
    case learning         // Learning aus einer Erfahrung
    case principle        // Grundsatz / Leitsatz
    case idea             // aufgehobene Idee

    var id: String { rawValue }

    var label: String {
        switch self {
        case .recommendation: return "Empfehlung"
        case .learning:       return "Learning"
        case .principle:      return "Grundsatz"
        case .idea:           return "Idee"
        }
    }

    var systemImage: String {
        switch self {
        case .recommendation: return "hand.point.right"
        case .learning:       return "graduationcap"
        case .principle:      return "scope"
        case .idea:           return "lightbulb"
        }
    }
}

/// Curation state of a distilled insight: everything starts `pending` and the
/// user decides once — keep or discard.
enum NoteInsightStatus: String, Codable {
    case pending
    case kept
    case discarded
}

/// One imported notes file (txt / md). Holds the raw text plus a content hash so
/// re-importing the same file is skipped. Deleting a document cascades to its
/// thoughts; kept insights survive (they carry a copy of their source).
@Model
final class NoteDocument {
    @Attribute(.unique) var id: UUID

    var fileName: String
    /// Display title (file name without extension).
    var title: String
    /// SHA-256 of the raw file content, for import de-duplication.
    var contentHash: String
    var importedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \NoteThought.document)
    var thoughts: [NoteThought]

    init(fileName: String, title: String, contentHash: String) {
        self.id = UUID()
        self.fileName = fileName
        self.title = title
        self.contentHash = contentHash
        self.importedAt = .now
        self.thoughts = []
    }
}

/// One **thought**: a single line / paragraph from a notes file. The user's notes
/// are stream-of-consciousness — almost every line break starts a new topic — so
/// this is the retrieval unit (and later the embedding unit).
@Model
final class NoteThought {
    @Attribute(.unique) var id: UUID

    var text: String
    /// Nearest markdown heading above this thought (context for LLM/embedding).
    var heading: String?
    /// Position within the source document.
    var orderIndex: Int
    /// Set once the distillation pass has looked at this thought (resumability).
    var isDistilled: Bool = false
    /// Packed `[Float]` embedding vector; filled by the (future) semantic pass.
    var embedding: Data? = nil

    var document: NoteDocument?

    init(text: String, heading: String?, orderIndex: Int) {
        self.id = UUID()
        self.text = text
        self.heading = heading
        self.orderIndex = orderIndex
    }
}

/// A **distilled insight**: one lasting recommendation / learning / principle /
/// idea that Gemma extracted from the raw thoughts. Starts `pending` until the
/// user curates it. Carries a copy of its source snippet + file name so it stays
/// meaningful even if the raw document is deleted later.
@Model
final class NoteInsight {
    @Attribute(.unique) var id: UUID

    /// Backing store for `kind` / `status`.
    private var kindRaw: String
    private var statusRaw: String

    /// The refined, concise phrasing produced by the distillation.
    var text: String
    var topics: [String]

    /// Copy of the raw thought this came from + its file, for provenance.
    var sourceText: String
    var sourceDocumentName: String
    /// Loose reference to the source thought (no relationship on purpose —
    /// insights must survive document deletion).
    var thoughtID: UUID?

    var createdAt: Date

    var kind: NoteInsightKind {
        get { NoteInsightKind(rawValue: kindRaw) ?? .learning }
        set { kindRaw = newValue.rawValue }
    }

    var status: NoteInsightStatus {
        get { NoteInsightStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }

    init(kind: NoteInsightKind,
         text: String,
         topics: [String] = [],
         sourceText: String,
         sourceDocumentName: String,
         thoughtID: UUID? = nil) {
        self.id = UUID()
        self.kindRaw = kind.rawValue
        self.statusRaw = NoteInsightStatus.pending.rawValue
        self.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        self.topics = topics
        self.sourceText = sourceText
        self.sourceDocumentName = sourceDocumentName
        self.thoughtID = thoughtID
        self.createdAt = .now
    }
}
