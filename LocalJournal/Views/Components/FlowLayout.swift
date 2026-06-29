import SwiftUI

/// A simple wrapping layout (left-to-right, wrap to next line). Used for tag
/// chips of feelings / topics / people where the count is unknown.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rows = rowHeights(maxWidth: maxWidth, subviews: subviews)
        let height = rows.reduce(0) { $0 + $1 } + CGFloat(max(0, rows.count - 1)) * spacing
        // If we couldn't lay anything out, fall back to a single line height.
        if rows.isEmpty { rows = [0] }
        return CGSize(width: maxWidth == .infinity ? widestSubview(subviews) : maxWidth,
                      height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                // wrap
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }

    private func rowHeights(maxWidth: CGFloat, subviews: Subviews) -> [CGFloat] {
        var rows: [CGFloat] = []
        var x: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                rows.append(rowHeight)
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        if rowHeight > 0 { rows.append(rowHeight) }
        return rows
    }

    private func widestSubview(_ subviews: Subviews) -> CGFloat {
        subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
    }
}

/// Renders a list of short strings as soft, rounded chips inside a `FlowLayout`.
struct ChipsView: View {
    let items: [String]
    var systemImage: String?
    var tint: Color = .accentColor

    /// De-duplicated, preserving order, so `id: \.self` never collides.
    private var uniqueItems: [String] {
        var seen = Set<String>()
        return items.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(uniqueItems, id: \.self) { item in
                HStack(spacing: 4) {
                    if let systemImage {
                        Image(systemName: systemImage)
                            .font(.caption2)
                    }
                    Text(item)
                        .font(.callout)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(tint.opacity(0.12), in: Capsule())
                .foregroundStyle(tint)
            }
        }
    }
}
