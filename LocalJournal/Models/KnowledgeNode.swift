import Foundation
import SwiftData

/// The kinds of things that can be a node in the knowledge graph.
///
/// `person`, `topic`, `feeling` are short labels; `idea`, `learning`, `task` are
/// statement-like (a whole sentence the user wrote or intends). The set is kept
/// small on purpose — start with what's genuinely useful for a journal and grow
/// deliberately.
enum NodeKind: String, Codable, CaseIterable, Identifiable {
    case person
    case topic
    case feeling
    case idea
    case learning
    case task
    case goal
    case place
    case pattern

    var id: String { rawValue }

    var singular: String {
        switch self {
        case .person:   return "Person"
        case .topic:    return "Thema"
        case .feeling:  return "Gefühl"
        case .idea:     return "Idee"
        case .learning: return "Learning"
        case .task:     return "Vorhaben"
        case .goal:     return "Ziel"
        case .place:    return "Ort"
        case .pattern:  return "Muster"
        }
    }

    var plural: String {
        switch self {
        case .person:   return "Personen"
        case .topic:    return "Themen"
        case .feeling:  return "Gefühle"
        case .idea:     return "Ideen"
        case .learning: return "Learnings"
        case .task:     return "Vorhaben"
        case .goal:     return "Ziele"
        case .place:    return "Orte"
        case .pattern:  return "Muster"
        }
    }

    var systemImage: String {
        switch self {
        case .person:   return "person"
        case .topic:    return "tag"
        case .feeling:  return "heart"
        case .idea:     return "lightbulb"
        case .learning: return "graduationcap"
        case .task:     return "checklist"
        case .goal:     return "target"
        case .place:    return "mappin.and.ellipse"
        case .pattern:  return "repeat"
        }
    }

    /// Statement-like nodes carry a full sentence rather than a short label; they
    /// are the ones worth tracking as intentions / captured thoughts.
    var isStatement: Bool {
        switch self {
        case .idea, .learning, .task, .goal, .pattern: return true
        default: return false
        }
    }

    /// Whether this kind is shown in the **graph visualisation**. Only recurring,
    /// interconnecting *entities* earn a place there; statement-like kinds
    /// (learnings, ideas, tasks, patterns) are still stored and shown on the
    /// "Merken" board and in the list, but would only clutter the graph.
    var showsInGraph: Bool {
        switch self {
        case .person, .topic, .feeling, .place, .goal: return true
        case .idea, .learning, .task, .pattern: return false
        }
    }

    /// Map a raw type string from the model onto a kind. Defaults to `.topic`.
    static func fromLLM(_ raw: String) -> NodeKind {
        switch NodeNormalization.normalize(raw) {
        case "person", "people", "name", "mensch", "menschen":
            return .person
        case "topic", "topics", "theme", "subject", "thema", "themen":
            return .topic
        case "feeling", "feelings", "emotion", "mood", "gefühl", "gefühle", "stimmung":
            return .feeling
        case "idea", "ideas", "idee", "ideen":
            return .idea
        case "learning", "learnings", "insight", "insights", "erkenntnis", "lektion", "lernen":
            return .learning
        case "task", "tasks", "todo", "to-do", "aufgabe", "aufgaben", "vorhaben", "intention":
            return .task
        case "goal", "goals", "ziel", "ziele", "objective", "vorsatz":
            return .goal
        case "place", "places", "location", "locations", "ort", "orte":
            return .place
        case "pattern", "patterns", "muster", "trend", "trends":
            return .pattern
        default:
            return .topic
        }
    }
}

/// A node in the on-device knowledge graph: a distinct person, topic, feeling,
/// idea, learning or task recognised across entries. De-duplicated by
/// `nodeKey` (kind + normalised name).
@Model
final class KnowledgeNode {
    @Attribute(.unique) var id: UUID

    /// Backing store for `kind` (SwiftData persists the raw string).
    private var kindRaw: String

    /// Display name / statement text, original casing preserved.
    var name: String

    /// Store-unique matching key ("kind#normalizedName"); see `NodeNormalization`.
    @Attribute(.unique) var nodeKey: String

    /// Optional longer context (reserved for future use, e.g. task notes).
    var detail: String

    var firstSeen: Date
    var lastSeen: Date

    /// For `.task` nodes: has the intention been marked done?
    var isResolved: Bool

    /// User-curated: kept prominently on the "Merken" board. Default keeps
    /// automatic migration clean for stores created before pinning existed.
    var isPinned: Bool = false

    /// Entries that reference this node (inverse declared on `JournalEntry.nodes`).
    var entries: [JournalEntry]

    /// Edges where this node is the source. Deleting a node removes its edges.
    @Relationship(deleteRule: .cascade, inverse: \KnowledgeEdge.from)
    var outgoingEdges: [KnowledgeEdge]

    /// Edges where this node is the target.
    @Relationship(deleteRule: .cascade, inverse: \KnowledgeEdge.to)
    var incomingEdges: [KnowledgeEdge]

    var kind: NodeKind {
        get { NodeKind(rawValue: kindRaw) ?? .topic }
        set { kindRaw = newValue.rawValue }
    }

    /// How many distinct entries reference this node (drives "importance").
    var mentionCount: Int { entries.count }

    /// All edges touching this node, regardless of direction.
    var allEdges: [KnowledgeEdge] { outgoingEdges + incomingEdges }

    init(kind: NodeKind, name: String) {
        let display = NodeNormalization.cleanDisplayName(name)
        self.id = UUID()
        self.kindRaw = kind.rawValue
        self.name = display
        self.nodeKey = NodeNormalization.key(kind: kind, name: display)
        self.detail = ""
        self.firstSeen = .now
        self.lastSeen = .now
        self.isResolved = false
        self.entries = []
        self.outgoingEdges = []
        self.incomingEdges = []
    }
}
