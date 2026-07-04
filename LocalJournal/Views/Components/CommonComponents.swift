import SwiftUI
import AppKit

extension Color {
    /// Warm, dark-mode-aware surface used for cards and grouped content
    /// (near-white paper on the cream `appBackground`). See `Theme.swift`.
    static let cardSurface = Color(lightHex: 0xFBFAF6, darkHex: 0x262420)
}

extension NodeKind {
    /// Accent colour used consistently across the graph and memory views.
    var tint: Color {
        switch self {
        case .person:   return .purple
        case .topic:    return .blue
        case .feeling:  return .pink
        case .idea:     return .orange
        case .learning: return .green
        case .task:     return .teal
        case .goal:     return .mint
        case .place:    return .brown
        case .pattern:  return .gray
        }
    }
}

/// A compact, good-looking date field: a pill showing the selected date that
/// opens a graphical calendar in a popover. Much cleaner than the default
/// macOS stepper field and shared by the editor and the entry editor.
struct DateFieldButton: View {
    @Binding var date: Date
    var label: String = "Datum"

    @State private var showPicker = false

    var body: some View {
        Button {
            showPicker.toggle()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "calendar")
                    .foregroundStyle(.secondary)
                Text(date.formatted(date: .abbreviated, time: .omitted))
                    .foregroundStyle(.primary)
                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .font(.callout)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color.cardSurface, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.secondary.opacity(0.15)))
        }
        .buttonStyle(.plain)
        .help(label)
        .popover(isPresented: $showPicker, arrowEdge: .bottom) {
            DatePicker(label, selection: $date, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
                .padding(12)
                .frame(width: 300)
        }
    }
}

/// A `TextEditor` with a placeholder that lines up exactly with the text
/// insertion point. The placeholder is a sibling in a top-leading `ZStack`, so
/// it shares the editor's frame; a 5pt leading inset matches the macOS
/// `NSTextView` line-fragment padding (nudge `placeholderLeading`/`placeholderTop`
/// if a given macOS version insets differently).
struct TextEditorWithPlaceholder: View {
    @Binding var text: String
    var placeholder: String
    var minHeight: CGFloat = 300

    private let placeholderLeading: CGFloat = 5
    private let placeholderTop: CGFloat = 0

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder)
                    .font(.body)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, placeholderLeading)
                    .padding(.top, placeholderTop)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $text)
                .font(.body)
                .scrollContentBackground(.hidden)
                .frame(minHeight: minHeight)
        }
        .padding(12)
        .background(Color.cardSurface, in: RoundedRectangle(cornerRadius: 12))
    }
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
                .serif(28)
                .foregroundStyle(.primary)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.cardSurface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
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
