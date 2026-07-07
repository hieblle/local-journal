import SwiftUI
import SwiftData

/// A small, permanent **Einblicke** block pinned to the bottom of the app's left
/// navigation sidebar: streak, total entries, total words. Compact by design so
/// it never competes with the navigation list above it.
struct SidebarStatsFooter: View {
    @Query private var entries: [JournalEntry]

    private var streak: Int { JournalStatistics.currentStreak(entries) }
    private var totalWords: Int { JournalStatistics.totalWords(entries) }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Divider()
                .padding(.bottom, 2)
            SectionLabel("Einblicke")
            row(icon: "flame", tint: .orange,
                value: "\(streak)", label: streak == 1 ? "Tag in Folge" : "Tage in Folge")
            row(icon: "book.closed", tint: .purple,
                value: "\(entries.count)", label: "Einträge")
            row(icon: "text.word.spacing", tint: .green,
                value: totalWords.formatted(), label: "Wörter")
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(icon: String, tint: Color, value: String, label: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(tint)
                .frame(width: 15)
            Text(value)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }
}
