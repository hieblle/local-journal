import SwiftUI
import SwiftData

/// The knowledge-graph tab. Two modes: a calm, inspectable **list** (nodes,
/// connections, linked entries) and a native force-directed **graph** canvas
/// (`GraphCanvasView`). The list is best for reading/acting; the graph is best
/// for exploring clusters and central hubs.
struct KnowledgeGraphView: View {
    @Environment(\.modelContext) private var context

    @Query(sort: \KnowledgeNode.lastSeen, order: .reverse) private var nodes: [KnowledgeNode]
    @Query private var edges: [KnowledgeEdge]

    @State private var selectedKind: NodeKind?
    @State private var mode: GraphViewMode = .list

    enum GraphViewMode: String, CaseIterable, Identifiable {
        case list, graph
        var id: String { rawValue }
        var title: String { self == .list ? "Liste" : "Graph" }
        var icon: String { self == .list ? "list.bullet" : "point.3.connected.trianglepath.dotted" }
    }

    private var visibleNodes: [KnowledgeNode] {
        nodes
            .filter { selectedKind == nil || $0.kind == selectedKind }
            .sorted {
                if $0.mentionCount != $1.mentionCount { return $0.mentionCount > $1.mentionCount }
                return $0.lastSeen > $1.lastSeen
            }
    }

    private var presentKinds: [NodeKind] {
        NodeKind.allCases.filter { kind in nodes.contains { $0.kind == kind } }
    }

    private var openTaskCount: Int {
        nodes.filter { $0.kind == .task && !$0.isResolved }.count
    }

    var body: some View {
        Group {
            if nodes.isEmpty {
                ScrollView {
                    EmptyHint(title: "Noch kein Wissensgraph",
                              systemImage: "point.3.connected.trianglepath.dotted",
                              message: "Sobald Einträge analysiert werden, entstehen hier automatisch Knoten (Themen, Personen, Ideen, Learnings, Vorhaben) und ihre Verbindungen.")
                        .padding(40)
                }
            } else {
                VStack(spacing: 0) {
                    Picker("Ansicht", selection: $mode) {
                        ForEach(GraphViewMode.allCases) { m in
                            Label(m.title, systemImage: m.icon).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelStyle(.titleAndIcon)
                    .frame(maxWidth: 260)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                    Divider()

                    switch mode {
                    case .list:
                        ScrollView {
                            VStack(alignment: .leading, spacing: 20) {
                                statsRow
                                kindFilter
                                nodeList
                            }
                            .padding(20)
                        }
                    case .graph:
                        GraphCanvasView()
                    }
                }
            }
        }
        .navigationTitle("Wissensgraph")
    }

    // MARK: - Header

    private var statsRow: some View {
        HStack(spacing: 12) {
            StatCard(title: "Knoten", value: "\(nodes.count)", systemImage: "circle.grid.3x3", tint: .blue)
            StatCard(title: "Verbindungen", value: "\(edges.count)", systemImage: "link", tint: .teal)
            StatCard(title: "Offene Vorhaben", value: "\(openTaskCount)", systemImage: "checklist", tint: .orange)
        }
    }

    private var kindFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip(title: "Alle", systemImage: "square.grid.2x2", kind: nil, count: nodes.count)
                ForEach(presentKinds) { kind in
                    filterChip(title: kind.plural,
                               systemImage: kind.systemImage,
                               kind: kind,
                               count: nodes.filter { $0.kind == kind }.count)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func filterChip(title: String, systemImage: String, kind: NodeKind?, count: Int) -> some View {
        let isSelected = selectedKind == kind
        let tint = kind.map { color(for: $0) } ?? .accentColor
        return Button {
            selectedKind = kind
        } label: {
            HStack(spacing: 5) {
                Image(systemName: systemImage).font(.caption2)
                Text(title).font(.callout)
                Text("\(count)")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(.quaternary, in: Capsule())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(tint.opacity(isSelected ? 0.22 : 0.10), in: Capsule())
            .foregroundStyle(isSelected ? tint : .secondary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Node list

    private var nodeList: some View {
        SectionCard(title: "Knoten", systemImage: "circle.grid.cross") {
            if visibleNodes.isEmpty {
                Text("Keine Knoten für diesen Filter.")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(visibleNodes) { node in
                        NodeDisclosure(node: node, color: color(for: node.kind)) {
                            toggleResolved(node)
                        }
                        Divider().opacity(0.4)
                    }
                }
            }
        }
    }

    // MARK: - Actions & helpers

    private func toggleResolved(_ node: KnowledgeNode) {
        node.isResolved.toggle()
        try? context.save()
    }

    private func color(for kind: NodeKind) -> Color { kind.tint }
}

/// One expandable node row: header (name, kind, mention count) revealing its
/// connections and the entries it appears in.
private struct NodeDisclosure: View {
    let node: KnowledgeNode
    let color: Color
    var onToggleTask: () -> Void

    private var connections: [Connection] {
        let outgoing = node.outgoingEdges.compactMap { edge -> Connection? in
            guard let other = edge.to else { return nil }
            return Connection(edge: edge, other: other, outgoing: true)
        }
        let incoming = node.incomingEdges.compactMap { edge -> Connection? in
            guard let other = edge.from else { return nil }
            return Connection(edge: edge, other: other, outgoing: false)
        }
        return (outgoing + incoming).sorted { $0.edge.weight > $1.edge.weight }
    }

    private var sortedEntries: [JournalEntry] {
        node.entries.sorted { $0.date > $1.date }
    }

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 12) {
                if node.kind.isStatement && node.kind == .task {
                    Button(action: onToggleTask) {
                        Label(node.isResolved ? "Erledigt" : "Als erledigt markieren",
                              systemImage: node.isResolved ? "checkmark.circle.fill" : "circle")
                            .font(.callout)
                            .foregroundStyle(node.isResolved ? .green : .secondary)
                    }
                    .buttonStyle(.plain)
                }

                if connections.isEmpty {
                    Text("Noch keine Verbindungen.")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Verbindungen")
                            .font(.subheadline.weight(.medium))
                        ForEach(connections) { connection in
                            ConnectionRow(connection: connection)
                        }
                    }
                }

                if !sortedEntries.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Erwähnt in \(sortedEntries.count) \(sortedEntries.count == 1 ? "Eintrag" : "Einträgen")")
                            .font(.subheadline.weight(.medium))
                        ForEach(sortedEntries) { entry in
                            NavigationLink(value: entry) {
                                HStack {
                                    Text(entry.title.isEmpty ? "Ohne Titel" : entry.title)
                                        .font(.callout)
                                    Spacer()
                                    Text(entry.date.formatted(date: .abbreviated, time: .omitted))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.top, 4)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: node.kind.systemImage)
                    .foregroundStyle(color)
                    .frame(width: 18)
                Text(node.name)
                    .font(.callout.weight(.medium))
                    .lineLimit(2)
                    .strikethrough(node.kind == .task && node.isResolved)
                Spacer()
                Text(node.kind.singular)
                    .font(.caption2)
                    .foregroundStyle(color)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(color.opacity(0.12), in: Capsule())
                Text("\(node.mentionCount)")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }
        }
    }
}

/// A flattened edge from the perspective of one node.
private struct Connection: Identifiable {
    let edge: KnowledgeEdge
    let other: KnowledgeNode
    let outgoing: Bool
    var id: UUID { edge.id }
}

private struct ConnectionRow: View {
    let connection: Connection

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: connection.edge.relation.systemImage)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(connection.edge.relation.germanLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
            Image(systemName: connection.outgoing ? "arrow.right" : "arrow.left")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Image(systemName: connection.other.kind.systemImage)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(connection.other.name)
                .font(.callout)
                .lineLimit(1)
            Spacer()
            if connection.edge.weight > 1 {
                Text("×\(connection.edge.weight)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
