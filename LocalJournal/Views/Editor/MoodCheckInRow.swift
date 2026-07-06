import SwiftUI

/// A quick, intuitive mood check-in: one question and five emoji to tap. Purely
/// self-reported (separate from the AI mood), stored on the entry as `selfMood`.
struct MoodCheckInRow: View {
    @Binding var selfMood: Int

    var body: some View {
        HStack(spacing: 12) {
            Text(prompt)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                ForEach(MoodScale.values, id: \.self) { value in
                    moodButton(value)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.cardSurface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.secondary.opacity(0.10)))
    }

    private var prompt: String {
        selfMood == 0 ? "Wie fühlst du dich gerade?" : "Stimmung: \(MoodScale.label(selfMood))"
    }

    private func moodButton(_ value: Int) -> some View {
        let isSelected = selfMood == value
        return Button {
            withAnimation(.snappy(duration: 0.15)) {
                selfMood = isSelected ? 0 : value   // tap again to clear
            }
        } label: {
            Text(MoodScale.emoji(value))
                .font(.system(size: 22))
                .opacity(selfMood == 0 || isSelected ? 1 : 0.45)
                .scaleEffect(isSelected ? 1.15 : 1)
                .frame(width: 34, height: 34)
                .background {
                    if isSelected {
                        Circle().fill(Color.sage.opacity(0.20))
                    }
                }
        }
        .buttonStyle(.plain)
        .help(MoodScale.label(value))
    }
}
