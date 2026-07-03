import Foundation
import CoreGraphics

/// Deterministic force-directed layout (Fruchterman–Reingold style), computed
/// **once** per visible node set. No live simulation: we run a fixed number of
/// cooling iterations up front and then render statically — the most
/// power-efficient approach at journal scale (a few hundred nodes at most).
///
/// Deterministic on purpose (index-seeded start, no randomness) so the same
/// graph always settles into the same picture across recomputes.
enum GraphLayoutEngine {

    /// - Parameters:
    ///   - count: number of nodes.
    ///   - edges: `(indexA, indexB, weight)` referencing node indices.
    ///   - size: the canvas the layout should fill.
    ///   - iterations: cooling steps (fewer for larger graphs keeps it snappy).
    /// - Returns: one `CGPoint` per node, in canvas coordinates.
    static func layout(count n: Int,
                       edges: [(Int, Int, Double)],
                       size: CGSize,
                       iterations: Int = 400) -> [CGPoint] {
        guard n > 0 else { return [] }

        let w = Double(size.width > 0 ? size.width : 600)
        let h = Double(size.height > 0 ? size.height : 600)
        let k = (w * h / Double(n)).squareRoot() * 0.55   // ideal edge length
        let cx = w / 2, cy = h / 2
        let r0 = min(w, h) * 0.35

        // Seed on a slightly varied ring so symmetric graphs still spread out.
        var x = [Double](repeating: 0, count: n)
        var y = [Double](repeating: 0, count: n)
        for i in 0..<n {
            let a = Double(i) / Double(n) * 2 * .pi
            let rr = r0 * (0.45 + 0.55 * Double(i % 7) / 6)
            x[i] = cx + cos(a) * rr
            y[i] = cy + sin(a) * rr
        }

        var dx = [Double](repeating: 0, count: n)
        var dy = [Double](repeating: 0, count: n)
        var temp = min(w, h) * 0.12   // max move per step, cooled each iteration

        for _ in 0..<max(1, iterations) {
            for i in 0..<n { dx[i] = 0; dy[i] = 0 }

            // Repulsion between every pair — O(n²), fine for n ≤ ~300.
            if n > 1 {
                for i in 0..<(n - 1) {
                    for j in (i + 1)..<n {
                        var ddx = x[i] - x[j]
                        var ddy = y[i] - y[j]
                        var dist = (ddx * ddx + ddy * ddy).squareRoot()
                        if dist < 0.01 {
                            // Nudge coincident nodes apart deterministically.
                            ddx = 0.01 * Double((i % 3) - 1)
                            ddy = 0.01
                            dist = 0.02
                        }
                        let force = k * k / dist
                        let ux = ddx / dist, uy = ddy / dist
                        dx[i] += ux * force; dy[i] += uy * force
                        dx[j] -= ux * force; dy[j] -= uy * force
                    }
                }
            }

            // Attraction along edges (heavier edges pull a little harder).
            for e in edges {
                let a = e.0, b = e.1
                if a == b || a < 0 || b < 0 || a >= n || b >= n { continue }
                var ddx = x[a] - x[b]
                var ddy = y[a] - y[b]
                var dist = (ddx * ddx + ddy * ddy).squareRoot()
                if dist < 0.01 { dist = 0.01 }
                let weightBoost = 0.6 + 0.4 * min(e.2, 6) / 6
                let force = dist * dist / k * weightBoost
                let ux = ddx / dist, uy = ddy / dist
                dx[a] -= ux * force; dy[a] -= uy * force
                dx[b] += ux * force; dy[b] += uy * force
            }

            // Integrate with temperature limiting + gentle centering + bounds.
            for i in 0..<n {
                var mvx = dx[i], mvy = dy[i]
                let mlen = (mvx * mvx + mvy * mvy).squareRoot()
                if mlen > temp, mlen > 0 {
                    mvx = mvx / mlen * temp
                    mvy = mvy / mlen * temp
                }
                x[i] += mvx; y[i] += mvy
                x[i] += (cx - x[i]) * 0.008
                y[i] += (cy - y[i]) * 0.008
                x[i] = min(max(x[i], 24), w - 24)
                y[i] = min(max(y[i], 24), h - 24)
            }
            temp *= 0.975
        }

        return (0..<n).map { CGPoint(x: x[$0], y: y[$0]) }
    }
}
