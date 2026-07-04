import SwiftUI
import AppKit

// MARK: - Palette
//
// A warm, calm, editorial palette (cream paper, sage accent, taupe labels) with
// light/dark variants so the whole app reads as one system. Semantic colours are
// defined once here and reused everywhere.

extension Color {
    /// Adaptive colour from two sRGB hex values (0xRRGGBB) for light / dark.
    init(lightHex: UInt, darkHex: UInt) {
        self = Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? darkHex : lightHex)
        })
    }

    /// Warm paper background behind all content.
    static let appBackground = Color(lightHex: 0xF3F1EA, darkHex: 0x1B1A17)

    /// Muted sage — the single accent (progress, chart line, highlights).
    static let sage = Color(lightHex: 0x7E8C6A, darkHex: 0x9DAA86)

    /// Track behind a sage progress bar.
    static let sageTrack = Color(lightHex: 0xE4E2D6, darkHex: 0x3A382F)

    /// Soft taupe for uppercase, letter-spaced section labels.
    static let labelSoft = Color(lightHex: 0xA99E88, darkHex: 0x8B8272)

    /// A deliberately dark, warm panel (e.g. the "prompt for today" card).
    static let inkPanel = Color(lightHex: 0x24221D, darkHex: 0x0F0E0C)
}

extension NSColor {
    convenience init(hex: UInt) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}

// MARK: - Serif display helper

extension View {
    /// The editorial serif used for headlines and big numbers.
    func serif(_ size: CGFloat, weight: Font.Weight = .regular) -> some View {
        font(.system(size: size, weight: weight, design: .serif))
    }
}

// MARK: - Building blocks

/// A small, uppercase, letter-spaced label used to title panels
/// ("RESILIENZ", "STIMMUNG · 30 TAGE", "WIEDERKEHRENDE THEMEN").
struct SectionLabel: View {
    let text: String
    var color: Color = .labelSoft
    init(_ text: String, color: Color = .labelSoft) {
        self.text = text
        self.color = color
    }
    var body: some View {
        Text(text.uppercased())
            .font(.caption.weight(.semibold))
            .tracking(1.4)
            .foregroundStyle(color)
    }
}

/// The warm, generously-padded card used across the redesigned surfaces. Unlike
/// `SectionCard` it uses an uppercase label (no icon) and softer geometry.
struct PanelCard<Content: View>: View {
    var label: String? = nil
    var trailing: String? = nil
    var background: Color = .cardSurface
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if label != nil || trailing != nil {
                HStack(alignment: .firstTextBaseline) {
                    if let label { SectionLabel(label) }
                    Spacer(minLength: 8)
                    if let trailing {
                        Text(trailing)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// A labelled 0–100 progress bar (the resilience sub-metrics).
struct MetricBar: View {
    let label: String
    let value: Int
    var tint: Color = .sage

    private var fraction: CGFloat { CGFloat(min(max(value, 0), 100)) / 100 }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(label).font(.callout)
                Spacer()
                Text("\(value)").font(.callout.weight(.medium)).monospacedDigit()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.sageTrack)
                    Capsule().fill(tint).frame(width: max(6, geo.size.width * fraction))
                }
            }
            .frame(height: 6)
        }
    }
}
