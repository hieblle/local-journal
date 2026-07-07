import SwiftUI

/// A quick, intuitive mood check-in: one question and five emoji to tap. Once a
/// mood is picked the whole row **collapses onto that single emoji** with a
/// dynamic (matched-geometry) motion; tapping the lone emoji again re-opens the
/// row to change the choice. Purely self-reported, stored on the entry as
/// `selfMood`.
struct MoodCheckInRow: View {
    @Binding var selfMood: Int

    /// Whether the picker is folded down to just the chosen emoji.
    @State private var isCollapsed = false
    @Namespace private var moodNamespace

    /// Collapsed only makes sense once something is actually selected.
    private var showCollapsed: Bool { isCollapsed && selfMood > 0 }

    var body: some View {
        Group {
            if showCollapsed {
                collapsedView
            } else {
                expandedView
            }
        }
        .frame(maxWidth: .infinity, alignment: showCollapsed ? .trailing : .leading)
    }

    // MARK: - Expanded (question + all emoji)

    private var expandedView: some View {
        HStack(spacing: 12) {
            Text(selfMood == 0 ? "Wie fühlst du dich gerade?" : "Stimmung: \(MoodScale.label(selfMood))")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                ForEach(MoodScale.values, id: \.self) { value in
                    emojiButton(value)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(Color.cardSurface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.secondary.opacity(0.10)))
    }

    private func emojiButton(_ value: Int) -> some View {
        let isSelected = selfMood == value
        return Button {
            withAnimation(.snappy(duration: 0.3)) {
                selfMood = value
                isCollapsed = true      // fold onto the chosen emoji
            }
        } label: {
            Text(MoodScale.emoji(value))
                .font(.system(size: 22))
                .opacity(selfMood == 0 || isSelected ? 1 : 0.45)
                .frame(width: 34, height: 34)
                .background {
                    if isSelected { Circle().fill(Color.sage.opacity(0.20)) }
                }
                .matchedGeometryEffect(id: "mood-\(value)", in: moodNamespace)
        }
        .buttonStyle(.plain)
        .help(MoodScale.label(value))
    }

    // MARK: - Collapsed (only the chosen emoji)

    private var collapsedView: some View {
        Button {
            withAnimation(.snappy(duration: 0.3)) { isCollapsed = false }
        } label: {
            Text(MoodScale.emoji(selfMood))
                .font(.system(size: 24))
                .frame(width: 42, height: 42)
                .background(Circle().fill(Color.sage.opacity(0.18)))
                .overlay(Circle().strokeBorder(Color.sage.opacity(0.30)))
                .matchedGeometryEffect(id: "mood-\(selfMood)", in: moodNamespace)
        }
        .buttonStyle(.plain)
        .help("Stimmung ändern")
    }
}
