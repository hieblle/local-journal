import SwiftUI
import SwiftData

/// The "Merken" board: one calm page that surfaces what the user needs to *act
/// on* and *remember* — open tasks, learnings, and the most important items.
///
/// It reads directly from the knowledge graph (`KnowledgeNode`), so it fills
/// itself automatically as entries are analysed. Users curate the top section by
/// pinning (⭐︎); goals and recurring learnings/patterns surface there on their own.
struct MemoryBoardView: View {
    @Environment(\.modelContext) private var context

    @Query(sort: \KnowledgeNode.lastSeen, order: .reverse) private var nodes: [KnowledgeNode]

    // MARK: - Derived groups

    /// Top section: pinned first, then goals, then recurring learnings/patterns/
    /// ideas — de-duplicated, capped so the board stays scannable.
    private var highlights: [KnowledgeNode] {
        var result: [KnowledgeNode] = []
        var seen = Set<UUID>()
        func addAll(_ candidates: [KnowledgeNode]) {
            for node in candidates where seen.insert(node.id).inserted { result.append(node) }
        }
        let pinned = nodes.filter { $0.isPinned }
        let goals = nodes.filter { $0.kind == .goal }
            .sorted { $0.mentionCount > $1.mentionCount }
        let recurring = nodes
            .filter { [.learning, .pattern, .idea].contains($0.kind) && $0.mentionCount >= 2 }
            .sorted { $0.mentionCount > $1.mentionCount }
        addAll(pinned)
        addAll(goals)
        addAll(recurring)
        return Array(result.prefix(12))
    }

    private var openTasks: [KnowledgeNode] {
        nodes.filter { $0.kind == .task && !$0.isResolved }
            .sorted { $0.lastSeen > $1.lastSeen }
    }
    private var doneTasks: [KnowledgeNode] {
        nodes.filter { $0.kind == .task && $0.isResolved }
            .sorted { $0.lastSeen > $1.lastSeen }
    }
    private var learnings: [KnowledgeNode] {
        nodes.filter { $0.kind == .learning }
            .sorted {
                if $0.mentionCount != $1.mentionCount { return $0.mentionCount > $1.mentionCount }
                return $0.lastSeen > $1.lastSeen
            }
    }

    private var isEmptyBoard: Bool {
        highlights.isEmpty && openTasks.isEmpty && doneTasks.isEmpty && learnings.isEmpty
    }

    var body: some View {
        ScrollView {
            if isEmptyBoard {
                EmptyHint(title: "Noch nichts zum Merken",
                          systemImage: "star",
                          message: "Sobald Einträge analysiert werden, sammeln sich hier deine Vorhaben, Learnings und wichtigsten Punkte.")
                    .padding(40)
            } else {
                VStack(alignment: .leading, spacing: 20) {
                    highlightsCard
                    tasksCard
                    learningsCard
                }
                .padding(20)
            }
        }
        .navigationTitle("Merken")
    }

    // MARK: - Cards

    private var highlightsCard: some View {
        SectionCard(title: "Wichtig zum Merken", systemImage: "star.fill") {
            if highlights.isEmpty {
                Text("Pinne Learnings, Ziele oder Vorhaben mit dem Stern – sie erscheinen dann hier oben. Wiederkehrende Themen tauchen automatisch auf.")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            } else {
                VStack(spacing: 0) {
                    ForEach(highlights) { node in
                        MemoryRow(node: node,
                                  showCheck: node.kind == .task,
                                  onTogglePin: { togglePin(node) },
                                  onToggleTask: { toggleTask(node) })
                        if node.id != highlights.last?.id { Divider().opacity(0.4) }
                    }
                }
            }
        }
    }

    private var tasksCard: some View {
        SectionCard(title: "Offene Vorhaben", systemImage: "checklist") {
            VStack(alignment: .leading, spacing: 0) {
                if openTasks.isEmpty {
                    Text("Keine offenen Vorhaben. 🎉")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                } else {
                    ForEach(openTasks) { node in
                        MemoryRow(node: node, showCheck: true,
                                  onTogglePin: { togglePin(node) },
                                  onToggleTask: { toggleTask(node) })
                        if node.id != openTasks.last?.id { Divider().opacity(0.4) }
                    }
                }

                if !doneTasks.isEmpty {
                    DisclosureGroup {
                        ForEach(doneTasks) { node in
                            MemoryRow(node: node, showCheck: true,
                                      onTogglePin: { togglePin(node) },
                                      onToggleTask: { toggleTask(node) })
                        }
                    } label: {
                        Text("Erledigt (\(doneTasks.count))")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, openTasks.isEmpty ? 0 : 10)
                }
            }
        }
    }

    private var learningsCard: some View {
        SectionCard(title: "Learnings", systemImage: "graduationcap") {
            if learnings.isEmpty {
                Text("Noch keine Learnings erkannt – sie entstehen aus deinen Einträgen.")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            } else {
                VStack(spacing: 0) {
                    ForEach(learnings) { node in
                        MemoryRow(node: node, showCheck: false,
                                  onTogglePin: { togglePin(node) },
                                  onToggleTask: { toggleTask(node) })
                        if node.id != learnings.last?.id { Divider().opacity(0.4) }
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func togglePin(_ node: KnowledgeNode) {
        node.isPinned.toggle()
        save()
    }

    private func toggleTask(_ node: KnowledgeNode) {
        node.isResolved.toggle()
        save()
    }

    private func save() {
        try? context.save()
    }
}

/// A single board row: optional check circle (tasks), kind icon + text, a kind
/// badge, and a pin toggle. Shared across all three sections for consistency.
private struct MemoryRow: View {
    let node: KnowledgeNode
    var showCheck: Bool
    var onTogglePin: () -> Void
    var onToggleTask: () -> Void

    private var isDone: Bool { node.kind == .task && node.isResolved }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if showCheck {
                Button(action: onToggleTask) {
                    Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isDone ? .green : .secondary)
                }
                .buttonStyle(.plain)
                .help(isDone ? "Als offen markieren" : "Als erledigt markieren")
            } else {
                Image(systemName: node.kind.systemImage)
                    .foregroundStyle(node.kind.tint)
                    .frame(width: 20)
                    .padding(.top, 1)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(node.name)
                    .font(.callout)
                    .strikethrough(isDone)
                    .foregroundStyle(isDone ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if node.mentionCount > 1 {
                    Text("in \(node.mentionCount) Einträgen")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Text(node.kind.singular)
                .font(.caption2)
                .foregroundStyle(node.kind.tint)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(node.kind.tint.opacity(0.12), in: Capsule())

            Button(action: onTogglePin) {
                Image(systemName: node.isPinned ? "star.fill" : "star")
                    .foregroundStyle(node.isPinned ? .yellow : .secondary)
            }
            .buttonStyle(.plain)
            .help(node.isPinned ? "Nicht mehr merken" : "Wichtig – oben behalten")
        }
        .padding(.vertical, 8)
    }
}
