import SwiftUI
import AppKit

extension Color {
    /// Subtle, dark-mode-aware surface used for cards and grouped content.
    static var cardSurface: Color { Color(nsColor: .controlBackgroundColor) }
}

/// A single dashboard metric (e.g. "Streak — 4 Tage").
struct StatCard: View {
    let title: String
    let value: String
    var systemImage: String
    var tint: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
            Text(value)
                .font(.system(.title, design: .rounded).weight(.semibold))
                .foregroundStyle(.primary)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.cardSurface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(tint.opacity(0.10))
        )
    }
}

/// A titled container card used to group content on the dashboard / analysis.
struct SectionCard<Content: View>: View {
    let title: String
    var systemImage: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .foregroundStyle(.secondary)
                }
                Text(title)
                    .font(.headline)
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.cardSurface, in: RoundedRectangle(cornerRadius: 12))
    }
}

/// Empty-state placeholder used across pages.
struct EmptyHint: View {
    let title: String
    var systemImage: String = "tray"
    var message: String? = nil

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
            if let message {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

/// A small status badge for the analysis lifecycle of an entry.
struct AnalysisStatusBadge: View {
    let status: AnalysisStatus

    var body: some View {
        Label(status.label, systemImage: status.systemImage)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.15), in: Capsule())
            .foregroundStyle(tint)
    }

    private var tint: Color {
        switch status {
        case .completed: return .green
        case .running:   return .blue
        case .pending:   return .orange
        case .failed:    return .red
        case .notStarted: return .secondary
        }
    }
}
