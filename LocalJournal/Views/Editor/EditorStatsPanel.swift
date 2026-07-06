import SwiftUI

/// The left "Einblicke" panel on the writing page: the few numbers that motivate
/// a daily habit — current streak, total entries, total words — in the warm
/// dashboard style.
struct EditorStatsPanel: View {
    let entries: [JournalEntry]
    var onClose: () -> Void = {}

    private var streak: Int { JournalStatistics.currentStreak(entries) }
    private var totalWords: Int { JournalStatistics.totalWords(entries) }
    private var wordsThisWeek: Int { JournalStatistics.wordsThisWeek(entries) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                SectionLabel("Einblicke")
                Spacer()
                Button {
                    onClose()
                } label: {
                    Image(systemName: "sidebar.left")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Einblicke ausblenden")
            }

            // Hero: streak
            VStack(alignment: .leading, spacing: 2) {
                Text("\(streak)")
                    .serif(48)
                    .contentTransition(.numericText())
                Text(streak == 1 ? "Tag in Folge" : "Tage in Folge")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Divider()

            statRow(icon: "book.closed", value: "\(entries.count)", label: "Einträge gesamt", tint: .purple)
            statRow(icon: "text.word.spacing", value: "\(totalWords)", label: "Wörter gesamt", tint: .green)
            statRow(icon: "calendar", value: "\(wordsThisWeek)", label: "Wörter diese Woche", tint: .blue)

            Spacer(minLength: 0)

            Text(encouragement)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.cardSurface)
    }

    private func statRow(icon: String, value: String, label: String, tint: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.callout)
                .foregroundStyle(tint)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private var encouragement: String {
        switch streak {
        case 0:  return "Jeder Eintrag zählt – fang einfach an."
        case 1:  return "Ein guter Anfang. Morgen weiter?"
        case 2...6: return "Schöne Serie – bleib dran."
        default: return "Starke Routine. Weiter so!"
        }
    }
}
