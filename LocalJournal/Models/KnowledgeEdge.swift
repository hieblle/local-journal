import Foundation
import SwiftData

/// How an edge came to exist — useful for trust / debugging and for later
/// weighting AI-inferred links differently from deterministic ones.
enum EdgeOrigin: String, Codable {
    /// Derived by us from co-occurrence in the same entry. No AI, always correct.
    case cooccurrence
    /// Extracted by the model as a typed relation.
    case llm
}

/// A directed, typed, weighted edge between two `KnowledgeNode`s.
///
/// Symmetric relations (see `RelationType.isSymmetric`) are stored exactly once
/// with a canonical endpoint order, so "A co-occurs B" and "B co-occurs A" are
/// the same row. `weight` counts how often the relation was observed; `lastSeen`
/// tracks recency.
@Model
final class KnowledgeEdge {
    @Attribute(.unique) var id: UUID

    /// Backing store for `relation`.
    private var relationRaw: String

    /// Backing store for `origin`.
    private var originRaw: String

    /// Number of times this relation was observed across entries.
    var weight: Int

    var firstSeen: Date
    var lastSeen: Date

    var from: KnowledgeNode?
    var to: KnowledgeNode?

    var relation: RelationType {
        get { RelationType(rawValue: relationRaw) ?? .relatedTo }
        set { relationRaw = newValue.rawValue }
    }

    var origin: EdgeOrigin {
        get { EdgeOrigin(rawValue: originRaw) ?? .llm }
        set { originRaw = newValue.rawValue }
    }

    init(relation: RelationType, from: KnowledgeNode, to: KnowledgeNode, origin: EdgeOrigin, weight: Int = 1) {
        self.id = UUID()
        self.relationRaw = relation.rawValue
        self.originRaw = origin.rawValue
        self.from = from
        self.to = to
        self.weight = weight
        self.firstSeen = .now
        self.lastSeen = .now
    }
}
