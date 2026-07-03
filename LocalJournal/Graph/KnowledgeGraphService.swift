import Foundation
import SwiftData

/// Builds the knowledge graph from a single entry's analysis. Runs on the main
/// actor inside the analysis pipeline (see `AnalysisService.applyAnalysis`).
///
/// Two edge sources, by design:
///  1. **Co-occurrence** — every pair of concepts in the same entry gets a
///     `coOccursWith` edge. Deterministic, needs no AI, and forms the reliable
///     backbone of the graph.
///  2. **Typed relations** — `about`, `causes`, `feelsAbout`, … extracted by the
///     model, mapped through the fixed `RelationVocabulary`.
///
/// Nodes are upserted (fetch-or-create by `nodeKey`) so re-mentions collapse onto
/// the same node; edges are merged (weight incremented) so repeated observations
/// strengthen a link instead of duplicating it.
@MainActor
struct KnowledgeGraphService {
    let context: ModelContext

    /// Cap on concepts considered for co-occurrence per entry, so a very rich
    /// entry can't create a runaway number of pairwise edges (n² growth).
    private let coOccurrenceCap = 14

    func ingest(_ result: FullAnalysisResult, into entry: JournalEntry) {
        var nodesForEntry: [KnowledgeNode] = []
        var seenKeys = Set<String>()

        func add(_ names: [String], kind: NodeKind) {
            for raw in names {
                let display = NodeNormalization.cleanDisplayName(raw)
                guard !NodeNormalization.normalize(display).isEmpty else { continue }
                let key = NodeNormalization.key(kind: kind, name: display)
                guard seenKeys.insert(key).inserted else { continue }   // de-dupe within entry
                let node = upsert(kind: kind, displayName: display)
                node.lastSeen = max(node.lastSeen, entry.date)
                node.firstSeen = min(node.firstSeen, entry.date)
                nodesForEntry.append(node)
            }
        }

        add(result.people, kind: .person)
        add(result.topics, kind: .topic)
        add(result.feelings, kind: .feeling)
        add(result.ideas, kind: .idea)
        add(result.keyInsights, kind: .learning)   // insights == learnings
        add(result.tasks, kind: .task)
        add(result.goals, kind: .goal)
        add(result.events, kind: .event)
        add(result.places, kind: .place)
        add(result.patterns, kind: .pattern)        // cross-entry patterns as nodes

        // (Re)link the entry to exactly the nodes it references now. Assigning the
        // whole array keeps re-analysis idempotent for node membership.
        entry.nodes = nodesForEntry

        // 1) Co-occurrence backbone (no AI).
        let capped = Array(nodesForEntry.prefix(coOccurrenceCap))
        for i in capped.indices {
            for j in capped.indices where j > i {
                mergeSymmetric(.coOccursWith, capped[i], capped[j], origin: .cooccurrence, on: entry.date)
            }
        }

        // 2) Typed relations (AI), mapped through the fixed vocabulary.
        for triple in result.relationships {
            ingest(triple: triple, on: entry.date)
        }
    }

    // MARK: - Triples

    private func ingest(triple: RelationTriple, on date: Date) {
        let sourceName = NodeNormalization.cleanDisplayName(triple.source)
        let targetName = NodeNormalization.cleanDisplayName(triple.target)
        guard !NodeNormalization.normalize(sourceName).isEmpty,
              !NodeNormalization.normalize(targetName).isEmpty else { return }

        let sourceKind = NodeKind.fromLLM(triple.sourceType)
        let targetKind = NodeKind.fromLLM(triple.targetType)
        guard NodeNormalization.key(kind: sourceKind, name: sourceName)
                != NodeNormalization.key(kind: targetKind, name: targetName) else { return }  // no self-loops

        let relation = RelationVocabulary.canonical(triple.relation)
        let source = upsert(kind: sourceKind, displayName: sourceName)
        let target = upsert(kind: targetKind, displayName: targetName)
        source.lastSeen = max(source.lastSeen, date)
        target.lastSeen = max(target.lastSeen, date)

        if relation.isSymmetric {
            mergeSymmetric(relation, source, target, origin: .llm, on: date)
        } else {
            mergeDirected(relation, from: source, to: target, origin: .llm, on: date)
        }
    }

    // MARK: - Nodes

    private func upsert(kind: NodeKind, displayName: String) -> KnowledgeNode {
        let key = NodeNormalization.key(kind: kind, name: displayName)
        if let existing = fetchNode(key: key) { return existing }
        let node = KnowledgeNode(kind: kind, name: displayName)
        context.insert(node)
        return node
    }

    private func fetchNode(key: String) -> KnowledgeNode? {
        var descriptor = FetchDescriptor<KnowledgeNode>(
            predicate: #Predicate { $0.nodeKey == key }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    // MARK: - Edges

    /// Store a symmetric relation once, with a stable endpoint order (by id) so
    /// the pair maps to a single row regardless of which side was seen first.
    private func mergeSymmetric(_ relation: RelationType, _ a: KnowledgeNode, _ b: KnowledgeNode,
                                origin: EdgeOrigin, on date: Date) {
        let ordered = a.id.uuidString <= b.id.uuidString ? (a, b) : (b, a)
        mergeDirected(relation, from: ordered.0, to: ordered.1, origin: origin, on: date)
    }

    private func mergeDirected(_ relation: RelationType, from: KnowledgeNode, to: KnowledgeNode,
                               origin: EdgeOrigin, on date: Date) {
        let targetID = to.id
        if let edge = from.outgoingEdges.first(where: { $0.to?.id == targetID && $0.relation == relation }) {
            edge.weight += 1
            edge.lastSeen = max(edge.lastSeen, date)
        } else {
            let edge = KnowledgeEdge(relation: relation, from: from, to: to, origin: origin)
            edge.firstSeen = date
            edge.lastSeen = date
            context.insert(edge)
        }
    }
}
