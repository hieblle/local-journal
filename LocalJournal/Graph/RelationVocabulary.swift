import Foundation

/// **Fixed relation vocabulary** for the knowledge graph.
///
/// A closed, controlled set of edge types is the single most important guard
/// against a messy graph: a small local model (Gemma 4B) will happily invent 20
/// spellings of "is related to". Every relation the model proposes is mapped
/// onto exactly one of these canonical cases (see `RelationVocabulary.canonical`)
/// — and anything unrecognised falls back to `.relatedTo` rather than being
/// dropped. New relation types must be added here and nowhere else.
enum RelationType: String, Codable, CaseIterable, Identifiable {
    /// Two nodes appear in the same entry. Derived deterministically, **without
    /// AI** — the cheap, always-correct backbone of the graph.
    case coOccursWith
    /// Generic association; also the safe fallback for unknown model output.
    case relatedTo
    /// A statement (idea / learning / task) is *about* a topic or person.
    case about
    /// A task or event *involves* a person.
    case involves
    /// A feeling is directed *at* a topic, person or event.
    case feelsAbout
    /// Something *leads to* / triggers a feeling.
    case causes
    /// Hierarchy: a topic (or task) is *part of* a larger topic.
    case partOf
    /// A task *depends on* another task, person or topic.
    case dependsOn

    var id: String { rawValue }

    /// Symmetric relations are stored once, with a canonical endpoint order.
    var isSymmetric: Bool {
        switch self {
        case .coOccursWith, .relatedTo: return true
        default: return false
        }
    }

    var germanLabel: String {
        switch self {
        case .coOccursWith: return "kommt gemeinsam vor mit"
        case .relatedTo:    return "hängt zusammen mit"
        case .about:        return "handelt von"
        case .involves:     return "bezieht ein"
        case .feelsAbout:   return "Gefühl gegenüber"
        case .causes:       return "führt zu"
        case .partOf:       return "gehört zu"
        case .dependsOn:    return "hängt ab von"
        }
    }

    var systemImage: String {
        switch self {
        case .coOccursWith: return "circle.grid.cross"
        case .relatedTo:    return "link"
        case .about:        return "text.bubble"
        case .involves:     return "person.2"
        case .feelsAbout:   return "heart"
        case .causes:       return "arrow.right"
        case .partOf:       return "square.stack.3d.up"
        case .dependsOn:    return "arrow.triangle.branch"
        }
    }
}

enum RelationVocabulary {
    /// Relations the model is *allowed* to emit. `coOccursWith` is intentionally
    /// excluded — it is derived by us, never asked of the model.
    static let modelRelations: [RelationType] = [
        .relatedTo, .about, .involves, .feelsAbout, .causes, .partOf, .dependsOn,
    ]

    /// Map any raw relation string (English, German, snake_case, synonyms) onto a
    /// single canonical `RelationType`. Never returns nil — unknown input
    /// generalises to `.relatedTo` so no edge is silently lost.
    static func canonical(_ raw: String) -> RelationType {
        let key = NodeNormalization.normalize(raw).replacingOccurrences(of: " ", with: "_")
        switch key {
        case "co_occurs_with", "cooccurs", "co_occurrence", "together", "gemeinsam", "co_occurs":
            return .coOccursWith
        case "about", "regarding", "concerns", "concerning", "on", "betrifft", "handelt_von", "über", "thema":
            return .about
        case "involves", "involving", "includes", "with", "beteiligt", "bezieht_ein", "mit":
            return .involves
        case "feels_about", "feels", "feel", "emotion", "emotional", "fühlt", "gefühl", "gefühl_gegenüber":
            return .feelsAbout
        case "causes", "cause", "leads_to", "triggers", "results_in", "führt_zu", "auslöst", "verursacht", "bewirkt":
            return .causes
        case "part_of", "partof", "belongs_to", "subtopic", "subtopic_of", "gehört_zu", "teil_von":
            return .partOf
        case "depends_on", "dependson", "requires", "needs", "blocked_by", "hängt_ab_von", "benötigt", "braucht":
            return .dependsOn
        case "related_to", "relatedto", "related", "associated", "connected", "linked", "verbunden", "zusammenhang":
            return .relatedTo
        default:
            return .relatedTo
        }
    }

    /// Compact, human-readable list injected into the LLM prompt so the model
    /// stays inside the vocabulary.
    static func promptList() -> String {
        modelRelations
            .map { "\"\($0.rawValue)\" (\($0.germanLabel))" }
            .joined(separator: ", ")
    }
}
