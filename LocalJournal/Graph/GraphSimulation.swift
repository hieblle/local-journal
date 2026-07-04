import SwiftUI
import Observation

/// A live, continuously-stepped force simulation for the knowledge graph.
///
/// Nodes attract along edges, repel each other, and hard-separate on collision so
/// they never overlap. The simulation *cools* (alpha → 0) and then reports
/// `isSettled`, at which point the view pauses ticking — so an idle graph costs
/// nothing. Any interaction (dragging a node) or data change **reheats** it, so
/// the network visibly re-organises as the user's journal grows.
///
/// A reference type (`@Observable` class) so an `NSEvent` scroll monitor and the
/// SwiftUI gestures can all mutate the same live state.
@MainActor
@Observable
final class GraphSimulation {

    struct Node: Identifiable {
        let id: UUID
        let kind: NodeKind
        let name: String
        let radius: CGFloat
        var x: CGFloat
        var y: CGFloat
        var vx: CGFloat = 0
        var vy: CGFloat = 0
        var fixed: Bool = false      // pinned while being dragged
    }

    struct Edge {
        let a: Int
        let b: Int
        let weight: CGFloat          // 1…6
        let typed: Bool              // typed relation vs. co-occurrence
        let rest: CGFloat           // preferred length
    }

    private(set) var nodes: [Node] = []
    private(set) var edges: [Edge] = []

    /// View transform (read by the canvas each frame; mutated by gestures/scroll).
    var zoom: CGFloat = 1
    var pan: CGSize = .zero
    var isHovering = false

    private(set) var size: CGSize = .zero
    private var alpha: CGFloat = 0                 // simulation "heat"
    private var draggingIndex: Int?
    private var idToPosition: [UUID: CGPoint] = [:]  // position memory across rebuilds

    /// When true the view stops ticking (no work while idle).
    var isSettled: Bool { alpha <= 0.015 && draggingIndex == nil }

    // Tunables (moderate + damped → stable). May want light tuning on device.
    private let idealSpacing: CGFloat = 64
    private let repulsion: CGFloat = 7000
    private let springStrength: CGFloat = 0.045
    private let centerPull: CGFloat = 0.018
    private let damping: CGFloat = 0.85
    private let maxSpeed: CGFloat = 40
    private let collisionPadding: CGFloat = 6

    // MARK: - Setup

    func setSize(_ newSize: CGSize) {
        guard newSize.width > 0, newSize.height > 0 else { return }
        let wasZero = (size == .zero)
        size = newSize
        if wasZero && !nodes.isEmpty { reheat(1) }
    }

    private func reheat(_ value: CGFloat = 0.7) {
        alpha = max(alpha, value)
    }

    /// Rebuild from current data, preserving positions of nodes that persist so
    /// the network grows rather than reshuffling on every new entry.
    func rebuild(nodes newNodes: [(id: UUID, kind: NodeKind, name: String, mentions: Int)],
                 edges newEdges: [(a: Int, b: Int, weight: Int, typed: Bool)]) {
        for n in nodes { idToPosition[n.id] = CGPoint(x: n.x, y: n.y) }

        let cx = (size.width > 0 ? size.width : 600) / 2
        let cy = (size.height > 0 ? size.height : 600) / 2

        var built: [Node] = []
        built.reserveCapacity(newNodes.count)
        for (i, n) in newNodes.enumerated() {
            let radius = 8 + min(CGFloat(n.mentions).squareRoot() * 4, 26)
            let seed: CGPoint
            if let known = idToPosition[n.id] {
                seed = known
            } else {
                let a = CGFloat(i) / CGFloat(max(newNodes.count, 1)) * 2 * .pi
                seed = CGPoint(x: cx + cos(a) * 70, y: cy + sin(a) * 70)
            }
            built.append(Node(id: n.id, kind: n.kind, name: n.name, radius: radius, x: seed.x, y: seed.y))
        }

        nodes = built
        edges = newEdges.compactMap { e in
            guard e.a < built.count, e.b < built.count else { return nil }
            let rest = idealSpacing + built[e.a].radius + built[e.b].radius
            return Edge(a: e.a, b: e.b, weight: CGFloat(min(max(e.weight, 1), 6)), typed: e.typed, rest: rest)
        }
        reheat(1)
    }

    // MARK: - Simulation step

    func step() {
        let n = nodes.count
        guard n > 0, !isSettled else { return }

        let cx = size.width / 2
        let cy = size.height / 2
        var fx = [CGFloat](repeating: 0, count: n)
        var fy = [CGFloat](repeating: 0, count: n)

        // Repulsion + hard collision (O(n²) — fine at journal scale).
        if n > 1 {
            for i in 0..<(n - 1) {
                for j in (i + 1)..<n {
                    var dx = nodes[i].x - nodes[j].x
                    var dy = nodes[i].y - nodes[j].y
                    var dist = (dx * dx + dy * dy).squareRoot()
                    if dist < 0.01 {
                        dx = CGFloat((i % 5) - 2) + 0.1
                        dy = 0.3
                        dist = (dx * dx + dy * dy).squareRoot()
                    }
                    let ux = dx / dist, uy = dy / dist
                    let rep = repulsion / (dist * dist)
                    fx[i] += ux * rep; fy[i] += uy * rep
                    fx[j] -= ux * rep; fy[j] -= uy * rep

                    let minDist = nodes[i].radius + nodes[j].radius + collisionPadding
                    if dist < minDist {
                        let push = (minDist - dist) * 3
                        fx[i] += ux * push; fy[i] += uy * push
                        fx[j] -= ux * push; fy[j] -= uy * push
                    }
                }
            }
        }

        // Springs along edges.
        for e in edges {
            let dx = nodes[e.b].x - nodes[e.a].x
            let dy = nodes[e.b].y - nodes[e.a].y
            var dist = (dx * dx + dy * dy).squareRoot()
            if dist < 0.01 { dist = 0.01 }
            let ux = dx / dist, uy = dy / dist
            let stretch = dist - e.rest
            let force = stretch * springStrength * (0.6 + 0.4 * e.weight / 6)
            fx[e.a] += ux * force; fy[e.a] += uy * force
            fx[e.b] -= ux * force; fy[e.b] -= uy * force
        }

        // Gentle centering.
        for i in 0..<n {
            fx[i] += (cx - nodes[i].x) * centerPull
            fy[i] += (cy - nodes[i].y) * centerPull
        }

        // Integrate (fixed nodes stay put).
        for i in 0..<n {
            if nodes[i].fixed { nodes[i].vx = 0; nodes[i].vy = 0; continue }
            var vx = (nodes[i].vx + fx[i]) * damping
            var vy = (nodes[i].vy + fy[i]) * damping
            let speed = (vx * vx + vy * vy).squareRoot()
            if speed > maxSpeed { vx = vx / speed * maxSpeed; vy = vy / speed * maxSpeed }
            nodes[i].vx = vx
            nodes[i].vy = vy
            nodes[i].x += vx * alpha
            nodes[i].y += vy * alpha
            let r = nodes[i].radius
            nodes[i].x = min(max(nodes[i].x, r), max(size.width - r, r))
            nodes[i].y = min(max(nodes[i].y, r), max(size.height - r, r))
        }

        alpha *= 0.99
        if alpha < 0.015 { alpha = 0 }
    }

    // MARK: - Dragging

    @discardableResult
    func beginDrag(atScreen point: CGPoint) -> Bool {
        guard let i = nodeIndex(atScreen: point) else { return false }
        draggingIndex = i
        nodes[i].fixed = true
        reheat(0.9)
        return true
    }

    func updateDrag(toScreen point: CGPoint) {
        guard let i = draggingIndex else { return }
        let world = screenToWorld(point)
        nodes[i].x = world.x
        nodes[i].y = world.y
        nodes[i].vx = 0
        nodes[i].vy = 0
        reheat(0.6)          // keep neighbours rearranging live
    }

    func endDrag() {
        if let i = draggingIndex { nodes[i].fixed = false }
        draggingIndex = nil
        reheat(0.4)
    }

    // MARK: - Transform

    func worldToScreen(_ p: CGPoint) -> CGPoint {
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        return CGPoint(x: (p.x - c.x) * zoom + c.x + pan.width,
                       y: (p.y - c.y) * zoom + c.y + pan.height)
    }

    func screenToWorld(_ s: CGPoint) -> CGPoint {
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        return CGPoint(x: (s.x - pan.width - c.x) / zoom + c.x,
                       y: (s.y - pan.height - c.y) / zoom + c.y)
    }

    func nodeIndex(atScreen point: CGPoint) -> Int? {
        var best: Int?
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for i in nodes.indices {
            let c = worldToScreen(CGPoint(x: nodes[i].x, y: nodes[i].y))
            let dx = c.x - point.x, dy = c.y - point.y
            let distance = (dx * dx + dy * dy).squareRoot()
            let hit = nodes[i].radius * zoom + 6
            if distance < hit, distance < bestDistance {
                bestDistance = distance
                best = i
            }
        }
        return best
    }
}
