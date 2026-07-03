import SwiftUI
import SwiftData

/// Obsidian-style node-link visualisation of the knowledge graph, drawn natively
/// in a `Canvas`. The layout is computed once per visible set (see
/// `GraphLayoutEngine`) and then rendered statically — pan, zoom and node drag
/// are pure view transforms, so there is no ongoing simulation cost.
///
/// Kept *useful*, not just pretty: filters (kind, edge weight, hide
/// co-occurrence) tame the hairball, and tapping a node offers a local focus
/// view of just its neighbourhood.
struct GraphCanvasView: View {
    @Query private var allNodes: [KnowledgeNode]
    @Query private var allEdges: [KnowledgeEdge]

    // Filters
    @State private var selectedKind: NodeKind?
    @State private var hideCoOccurrence = false
    @State private var minWeight = 1
    @State private var focusID: UUID?

    // Built (per visible set) — recomputed only when the signature changes.
    @State private var gNodes: [KnowledgeNode] = []
    @State private var gEdges: [GEdge] = []
    @State private var positions: [CGPoint] = []
    @State private var builtSignature = ""
    @State private var canvasSize: CGSize = .zero

    // View transform
    @State private var zoom: CGFloat = 1
    @State private var lastZoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var lastPan: CGSize = .zero

    // Interaction
    @State private var selectedID: UUID?
    @State private var dragKind: DragKind?

    private let nodeCap = 250

    private enum DragKind: Equatable { case canvas, node(Int) }
    private struct GEdge { let a: Int; let b: Int; let weight: Double; let cooc: Bool }

    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                draw(&context, size: size)
            }
            .background(canvasBackground)
            .gesture(dragGesture)
            .gesture(magnifyGesture)
            .gesture(tapGesture)
            .overlay(alignment: .top) { controls }
            .overlay(alignment: .bottom) { if let node = selectedNode { banner(node) } }
            .overlay(alignment: .topTrailing) { if capped { cappedNote } }
            .overlay { if gNodes.isEmpty && !builtSignature.isEmpty { emptyOverlay } }
            .onAppear { canvasSize = geo.size; rebuild() }
            .onChange(of: geo.size) { _, newSize in canvasSize = newSize; rebuild() }
            .onChange(of: currentSignature) { _, _ in
                if currentSignature != builtSignature { rebuild() }
            }
        }
    }

    // MARK: - Drawing

    private func draw(_ context: inout GraphicsContext, size: CGSize) {
        guard positions.count == gNodes.count, !gNodes.isEmpty else { return }

        // Edges first.
        for e in gEdges {
            guard e.a < positions.count, e.b < positions.count else { continue }
            let p1 = worldToScreen(positions[e.a])
            let p2 = worldToScreen(positions[e.b])
            var path = Path()
            path.move(to: p1)
            path.addLine(to: p2)
            let base: Color = e.cooc ? .gray : .accentColor
            let opacity = e.cooc ? 0.16 : 0.40
            let width = (e.cooc ? 0.8 : 1.3) + min(e.weight, 6) / 6 * 1.6
            context.stroke(path, with: .color(base.opacity(opacity)), lineWidth: CGFloat(width))
        }

        // Nodes + labels.
        for (i, node) in gNodes.enumerated() {
            let center = worldToScreen(positions[i])
            let r = nodeRadius(node) * clampedZoom
            let rect = CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r)
            context.fill(Path(ellipseIn: rect), with: .color(node.kind.tint))

            if node.id == selectedID || node.id == focusID {
                context.stroke(Path(ellipseIn: rect.insetBy(dx: -3, dy: -3)),
                               with: .color(.primary), lineWidth: 2)
            }

            if shouldLabel(node) {
                let label = Text(node.name)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.primary)
                context.draw(label, at: CGPoint(x: center.x, y: center.y + r + 7), anchor: .top)
            }
        }
    }

    private var canvasBackground: some View {
        Color.cardSurface.opacity(0.35)
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

            Button { setZoom(zoom / 1.25) } label: { Image(systemName: "minus.magnifyingglass") }
            Button { resetView() } label: { Image(systemName: "arrow.counterclockwise") }
            Button { setZoom(zoom * 1.25) } label: { Image(systemName: "plus.magnifyingglass") }
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
                Label(focusID == node.id ? "Fokus lösen" : "Fokus", systemImage: "scope")
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
                if dragKind == nil {
                    dragKind = nodeIndex(at: value.startLocation).map(DragKind.node) ?? .canvas
                }
                guard let kind = dragKind else { return }
                switch kind {
                case .node(let i):
                    if i < positions.count { positions[i] = screenToWorld(value.location) }
                case .canvas:
                    pan = CGSize(width: lastPan.width + value.translation.width,
                                 height: lastPan.height + value.translation.height)
                }
            }
            .onEnded { _ in
                if dragKind == .canvas { lastPan = pan }
                dragKind = nil
            }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in zoom = clamp(lastZoom * value.magnification, 0.3, 4) }
            .onEnded { _ in lastZoom = zoom }
    }

    private var tapGesture: some Gesture {
        SpatialTapGesture(coordinateSpace: .local)
            .onEnded { value in
                if let i = nodeIndex(at: value.location) {
                    selectedID = gNodes[i].id
                } else {
                    selectedID = nil
                }
            }
    }

    // MARK: - Transform helpers

    private var clampedZoom: CGFloat { clamp(zoom, 0.3, 4) }

    private func worldToScreen(_ p: CGPoint) -> CGPoint {
        let c = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
        return CGPoint(x: (p.x - c.x) * zoom + c.x + pan.width,
                       y: (p.y - c.y) * zoom + c.y + pan.height)
    }

    private func screenToWorld(_ s: CGPoint) -> CGPoint {
        let c = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
        return CGPoint(x: (s.x - pan.width - c.x) / zoom + c.x,
                       y: (s.y - pan.height - c.y) / zoom + c.y)
    }

    private func nodeIndex(at screen: CGPoint) -> Int? {
        guard positions.count == gNodes.count else { return nil }
        var best: Int?
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for i in gNodes.indices {
            let c = worldToScreen(positions[i])
            let ddx = c.x - screen.x, ddy = c.y - screen.y
            let distance = (ddx * ddx + ddy * ddy).squareRoot()
            let hit = nodeRadius(gNodes[i]) * clampedZoom + 6
            if distance < hit, distance < bestDistance {
                bestDistance = distance
                best = i
            }
        }
        return best
    }

    private func nodeRadius(_ node: KnowledgeNode) -> CGFloat {
        let m = CGFloat(node.mentionCount)
        return 6 + min(m.squareRoot() * 3.5, 22)
    }

    private func shouldLabel(_ node: KnowledgeNode) -> Bool {
        node.id == selectedID || node.id == focusID
            || gNodes.count <= 28 || node.mentionCount >= 3 || zoom >= 1.8
    }

    private func setZoom(_ value: CGFloat) {
        zoom = clamp(value, 0.3, 4)
        lastZoom = zoom
    }

    private func resetView() {
        zoom = 1; lastZoom = 1; pan = .zero; lastPan = .zero
    }

    private func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
        min(max(v, lo), hi)
    }

    // MARK: - Selection helpers

    private var selectedNode: KnowledgeNode? {
        guard let id = selectedID else { return nil }
        return gNodes.first { $0.id == id }
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

    private var presentKinds: [NodeKind] {
        NodeKind.allCases.filter { kind in allNodes.contains { $0.kind == kind } }
    }

    private var capped: Bool { gNodes.count >= nodeCap && allNodes.count > nodeCap }

    /// Cheap change-detector: filters + node count + canvas size. Recompute the
    /// layout only when one of these changes (not on every drag frame).
    private var currentSignature: String {
        "\(selectedKind?.rawValue ?? "all")|\(hideCoOccurrence)|\(minWeight)"
        + "|\(focusID?.uuidString ?? "none")|\(allNodes.count)"
        + "|\(Int(canvasSize.width))x\(Int(canvasSize.height))"
    }

    private func rebuild() {
        guard canvasSize.width > 0 else { return }

        let nodes = computeVisibleNodes()
        var index = [UUID: Int]()
        for (i, n) in nodes.enumerated() { index[n.id] = i }

        var edges: [GEdge] = []
        var layoutEdges: [(Int, Int, Double)] = []
        for edge in allEdges {
            guard edge.weight >= minWeight else { continue }
            let cooc = edge.origin == .cooccurrence
            if hideCoOccurrence && cooc { continue }
            guard let fromID = edge.from?.id, let toID = edge.to?.id,
                  let a = index[fromID], let b = index[toID], a != b else { continue }
            edges.append(GEdge(a: a, b: b, weight: Double(edge.weight), cooc: cooc))
            layoutEdges.append((a, b, Double(edge.weight)))
        }

        let iterations = nodes.count > 150 ? 250 : 400
        positions = GraphLayoutEngine.layout(count: nodes.count, edges: layoutEdges,
                                             size: canvasSize, iterations: iterations)
        gNodes = nodes
        gEdges = edges
        builtSignature = currentSignature
        resetView()

        if let id = selectedID, !nodes.contains(where: { $0.id == id }) { selectedID = nil }
    }

    private func computeVisibleNodes() -> [KnowledgeNode] {
        var nodes = allNodes

        if let neighbours = focusNeighbourIDs {
            nodes = nodes.filter { neighbours.contains($0.id) }
        }
        if let kind = selectedKind {
            nodes = nodes.filter { $0.kind == kind || $0.id == focusID }
        }
        nodes.sort {
            if $0.mentionCount != $1.mentionCount { return $0.mentionCount > $1.mentionCount }
            return $0.id.uuidString < $1.id.uuidString
        }
        if nodes.count > nodeCap { nodes = Array(nodes.prefix(nodeCap)) }
        return nodes
    }

    /// The focused node plus its direct (1-hop) neighbours.
    private var focusNeighbourIDs: Set<UUID>? {
        guard let focusID, let center = allNodes.first(where: { $0.id == focusID }) else { return nil }
        var ids: Set<UUID> = [focusID]
        for edge in center.outgoingEdges { if let to = edge.to { ids.insert(to.id) } }
        for edge in center.incomingEdges { if let from = edge.from { ids.insert(from.id) } }
        return ids
    }
}
