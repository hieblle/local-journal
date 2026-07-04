import SwiftUI
import SwiftData
import AppKit

/// Obsidian-style, **living** node-link view of the knowledge graph.
///
/// Nodes attract along their connections, gently repel, and never overlap; the
/// layout re-organises continuously while active and pauses once settled. Drag a
/// node and its neighbours make room; pan the canvas; zoom with the mouse wheel,
/// a trackpad pinch, or the buttons. Only recurring **entities** (people, topics,
/// feelings, places, goals) appear — statement-like nodes would just clutter it.
struct GraphCanvasView: View {
    @Query private var allNodes: [KnowledgeNode]
    @Query private var allEdges: [KnowledgeEdge]

    @State private var sim = GraphSimulation()

    // Filters
    @State private var selectedKind: NodeKind?
    @State private var hideCoOccurrence = false
    @State private var minWeight = 1
    @State private var focusID: UUID?
    @State private var selectedID: UUID?

    // Bookkeeping
    @State private var builtSignature = ""
    @State private var dragMode: DragMode?
    @State private var panBaseline: CGSize = .zero
    @State private var magnifyBaseline: CGFloat = 1
    @State private var magnifying = false
    @State private var scrollMonitor: Any?

    private let nodeCap = 220
    private enum DragMode: Equatable { case canvas, node }

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: sim.isSettled)) { context in
                Canvas { ctx, size in draw(&ctx, size: size) }
                    .onChange(of: context.date) { _, _ in sim.step() }
            }
            .background(Color.cardSurface.opacity(0.35))
            .contentShape(Rectangle())
            .gesture(dragGesture)
            .gesture(magnifyGesture)
            .gesture(tapGesture)
            .onHover { sim.isHovering = $0 }
            .overlay(alignment: .top) { controls }
            .overlay(alignment: .bottom) { if let node = selectedNode { banner(node) } }
            .overlay(alignment: .topTrailing) { if capped { cappedNote } }
            .overlay { if sim.nodes.isEmpty && !builtSignature.isEmpty { emptyOverlay } }
            .onAppear {
                sim.setSize(geo.size)
                installScrollMonitor()
                rebuild()
            }
            .onDisappear { removeScrollMonitor() }
            .onChange(of: geo.size) { _, newSize in sim.setSize(newSize) }
            .onChange(of: currentSignature) { _, _ in
                if currentSignature != builtSignature { rebuild() }
            }
        }
    }

    // MARK: - Drawing

    private func draw(_ context: inout GraphicsContext, size: CGSize) {
        let nodes = sim.nodes
        guard !nodes.isEmpty else { return }

        for e in sim.edges {
            guard e.a < nodes.count, e.b < nodes.count else { continue }
            let p1 = sim.worldToScreen(CGPoint(x: nodes[e.a].x, y: nodes[e.a].y))
            let p2 = sim.worldToScreen(CGPoint(x: nodes[e.b].x, y: nodes[e.b].y))
            var path = Path()
            path.move(to: p1)
            path.addLine(to: p2)
            let base: Color = e.typed ? .accentColor : .gray
            let opacity = e.typed ? 0.45 : 0.20
            let width = (e.typed ? 1.3 : 0.9) + e.weight / 6 * 1.6
            context.stroke(path, with: .color(base.opacity(opacity)), lineWidth: CGFloat(width))
        }

        for (i, node) in nodes.enumerated() {
            let c = sim.worldToScreen(CGPoint(x: node.x, y: node.y))
            let r = node.radius * sim.zoom
            let rect = CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)
            context.fill(Path(ellipseIn: rect), with: .color(node.kind.tint))

            if node.id == selectedID || node.id == focusID {
                context.stroke(Path(ellipseIn: rect.insetBy(dx: -3, dy: -3)),
                               with: .color(.primary), lineWidth: 2)
            }

            if shouldLabel(node, count: nodes.count) {
                let label = Text(node.name)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.primary)
                context.draw(label, at: CGPoint(x: c.x, y: c.y + r + 7), anchor: .top)
            }
        }
        _ = size
    }

    private func shouldLabel(_ node: GraphSimulation.Node, count: Int) -> Bool {
        node.id == selectedID || node.id == focusID
            || count <= 22 || node.radius >= 16 || sim.zoom >= 1.6
    }

    // MARK: - Overlays

    private var controls: some View {
        HStack(spacing: 8) {
            Menu {
                Button("Alle Typen") { selectedKind = nil }
                Divider()
                ForEach(presentKinds) { kind in
                    Button(kind.plural) { selectedKind = kind }
                }
            } label: {
                Label(selectedKind?.plural ?? "Alle Typen", systemImage: "line.3.horizontal.decrease.circle")
            }

            Menu {
                Button("Alle Kanten") { minWeight = 1 }
                Button("Gewicht ≥ 2") { minWeight = 2 }
                Button("Gewicht ≥ 3") { minWeight = 3 }
            } label: {
                Label(minWeight > 1 ? "Gewicht ≥ \(minWeight)" : "Alle Kanten", systemImage: "slider.horizontal.3")
            }

            Button { hideCoOccurrence.toggle() } label: {
                Label("Nur getypte Kanten",
                      systemImage: hideCoOccurrence ? "checkmark.circle.fill" : "circle")
            }

            if focusID != nil {
                Button { focusID = nil; selectedID = nil } label: {
                    Label("Gesamtansicht", systemImage: "arrow.up.left.and.arrow.down.right")
                }
            }

            Spacer(minLength: 0)

            Button { setZoom(sim.zoom / 1.25) } label: { Image(systemName: "minus.magnifyingglass") }
            Button { sim.zoom = 1; sim.pan = .zero } label: { Image(systemName: "arrow.counterclockwise") }
            Button { setZoom(sim.zoom * 1.25) } label: { Image(systemName: "plus.magnifyingglass") }
        }
        .labelStyle(.titleAndIcon)
        .font(.caption)
        .buttonStyle(.borderless)
        .padding(8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .padding(10)
    }

    private func banner(_ node: KnowledgeNode) -> some View {
        HStack(spacing: 10) {
            Image(systemName: node.kind.systemImage)
                .foregroundStyle(node.kind.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(node.name)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text(subtitle(for: node))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                focusID = (focusID == node.id) ? nil : node.id
            } label: {
                Label(focusID == node.id ? "Gesamt" : "Umgebung", systemImage: "scope")
            }
            .buttonStyle(.borderless)
            Button { selectedID = nil } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .frame(maxWidth: 540)
        .padding(10)
    }

    private var cappedNote: some View {
        Text("Top \(nodeCap) Knoten")
            .font(.caption2)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(10)
    }

    private var emptyOverlay: some View {
        Text("Keine Knoten für diese Filter.")
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.vertical, 6).padding(.horizontal, 12)
            .background(.ultraThinMaterial, in: Capsule())
    }

    // MARK: - Gestures

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .local)
            .onChanged { value in
                if dragMode == nil {
                    if sim.beginDrag(atScreen: value.startLocation) {
                        dragMode = .node
                    } else {
                        dragMode = .canvas
                        panBaseline = sim.pan
                    }
                }
                if let mode = dragMode {
                    switch mode {
                    case .node:
                        sim.updateDrag(toScreen: value.location)
                    case .canvas:
                        sim.pan = CGSize(width: panBaseline.width + value.translation.width,
                                         height: panBaseline.height + value.translation.height)
                    }
                }
            }
            .onEnded { _ in
                if dragMode == .node { sim.endDrag() }
                dragMode = nil
            }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if !magnifying { magnifying = true; magnifyBaseline = sim.zoom }
                sim.zoom = clampZoom(magnifyBaseline * value.magnification)
            }
            .onEnded { _ in magnifying = false }
    }

    private var tapGesture: some Gesture {
        SpatialTapGesture(coordinateSpace: .local)
            .onEnded { value in
                if let i = sim.nodeIndex(atScreen: value.location) {
                    selectedID = sim.nodes[i].id
                } else {
                    selectedID = nil
                }
            }
    }

    private func setZoom(_ value: CGFloat) { sim.zoom = clampZoom(value) }
    private func clampZoom(_ v: CGFloat) -> CGFloat { min(max(v, 0.3), 4) }

    // MARK: - Mouse-wheel zoom (works with a plain mouse, not just trackpad)

    private func installScrollMonitor() {
        removeScrollMonitor()
        let simulation = sim   // capture the shared instance, not the View
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            guard simulation.isHovering else { return event }
            let factor = 1 + event.scrollingDeltaY * 0.006
            simulation.zoom = min(max(simulation.zoom * factor, 0.3), 4)
            return nil   // consume so it doesn't scroll something behind
        }
    }

    private func removeScrollMonitor() {
        if let monitor = scrollMonitor {
            NSEvent.removeMonitor(monitor)
            scrollMonitor = nil
        }
    }

    // MARK: - Selection

    private var selectedNode: KnowledgeNode? {
        guard let id = selectedID else { return nil }
        return allNodes.first { $0.id == id }
    }

    private func subtitle(for node: KnowledgeNode) -> String {
        let mentions = "in \(node.mentionCount) \(node.mentionCount == 1 ? "Eintrag" : "Einträgen")"
        let neighbours = (node.outgoingEdges.compactMap { edge in edge.to.map { ($0, edge.weight) } }
                          + node.incomingEdges.compactMap { edge in edge.from.map { ($0, edge.weight) } })
            .sorted { $0.1 > $1.1 }
            .prefix(3)
            .map { $0.0.name }
        let base = "\(node.kind.singular) · \(mentions)"
        return neighbours.isEmpty ? base : base + " · " + neighbours.joined(separator: ", ")
    }

    // MARK: - Building the visible graph

    private var graphNodes: [KnowledgeNode] { allNodes.filter { $0.kind.showsInGraph } }

    private var presentKinds: [NodeKind] {
        NodeKind.allCases.filter { kind in
            kind.showsInGraph && graphNodes.contains { $0.kind == kind }
        }
    }

    private var capped: Bool { sim.nodes.count >= nodeCap && graphNodes.count > nodeCap }

    private var currentSignature: String {
        "\(selectedKind?.rawValue ?? "all")|\(hideCoOccurrence)|\(minWeight)"
        + "|\(focusID?.uuidString ?? "none")|\(graphNodes.count)"
        + "|\(Int(sim.size.width))x\(Int(sim.size.height))"
    }

    private func rebuild() {
        guard sim.size.width > 0 else { return }

        var visible = graphNodes
        if let neighbours = focusNeighbourIDs {
            visible = visible.filter { neighbours.contains($0.id) }
        }
        if let kind = selectedKind {
            visible = visible.filter { $0.kind == kind || $0.id == focusID }
        }
        visible.sort {
            if $0.mentionCount != $1.mentionCount { return $0.mentionCount > $1.mentionCount }
            return $0.id.uuidString < $1.id.uuidString
        }
        if visible.count > nodeCap { visible = Array(visible.prefix(nodeCap)) }

        var index = [UUID: Int]()
        for (i, n) in visible.enumerated() { index[n.id] = i }

        var simEdges: [(a: Int, b: Int, weight: Int, typed: Bool)] = []
        for edge in allEdges {
            guard edge.weight >= minWeight else { continue }
            let cooc = edge.origin == .cooccurrence
            if hideCoOccurrence && cooc { continue }
            guard let fromID = edge.from?.id, let toID = edge.to?.id,
                  let a = index[fromID], let b = index[toID], a != b else { continue }
            simEdges.append((a: a, b: b, weight: edge.weight, typed: !cooc))
        }

        let simNodes = visible.map {
            (id: $0.id, kind: $0.kind, name: $0.name, mentions: $0.mentionCount)
        }
        sim.rebuild(nodes: simNodes, edges: simEdges)
        builtSignature = currentSignature

        if let id = selectedID, !visible.contains(where: { $0.id == id }) { selectedID = nil }
    }

    /// Focused node plus its direct (1-hop) neighbours — the "Umgebung" / local view.
    private var focusNeighbourIDs: Set<UUID>? {
        guard let focusID, let center = allNodes.first(where: { $0.id == focusID }) else { return nil }
        var ids: Set<UUID> = [focusID]
        for edge in center.outgoingEdges { if let to = edge.to { ids.insert(to.id) } }
        for edge in center.incomingEdges { if let from = edge.from { ids.insert(from.id) } }
        return ids
    }
}
