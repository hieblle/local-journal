import SwiftUI
import SwiftData

/// The **Resonanz** card on an entry's detail page: what from your curated
/// knowledge base speaks to this entry ("Aus deinen Notizen") and which earlier
/// entries resemble the situation ("Schon mal erlebt") — including what helped
/// back then. Computed live and deterministically (see `ResonanceEngine`), so it
/// improves automatically as more insights are kept or entries re-analysed, and
/// the shared-signal chips always explain WHY something shows up.
struct ResonanceCard: View {
    let entry: JournalEntry

    @Query private var allEntries: [JournalEntry]
    @Query private var allInsights: [NoteInsight]

    private var insightMatches: [ResonanceEngine.InsightMatch] {
        ResonanceEngine.relevantInsights(to: entry, from: allInsights)
    }

    private var entryMatches: [ResonanceEngine.EntryMatch] {
        ResonanceEngine.similarEntries(to: entry, in: allEntries)
    }

    var body: some View {
        let insights = insightMatches
        let entries = entryMatches
        if !insights.isEmpty || !entries.isEmpty {
            SectionCard(title: "Resonanz", systemImage: "waveform") {
                VStack(alignment: .leading, spacing: 18) {
                    if !insights.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionLabel("Aus deinen Notizen")
                            ForEach(insights) { match in
                                insightRow(match)
                            }
                        }
                    }
                    if !entries.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionLabel("Schon mal erlebt")
                            ForEach(entries) { match in
                                entryRow(match)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Knowledge-base row

    private func insightRow(_ match: ResonanceEngine.InsightMatch) -> some View {
        let insight = match.insight
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Label(insight.kind.label, systemImage: insight.kind.systemImage)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(insight.kind.tint)
                Spacer()
                if !insight.sourceDocumentName.isEmpty {
                    Text(insight.sourceDocumentName)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Text(insight.text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            sharedChips(match.shared)
        }
        .padding(12)
        .background(Color.sage.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.sage.opacity(0.15)))
    }

    // MARK: - Similar-entry row

    private func entryRow(_ match: ResonanceEngine.EntryMatch) -> some View {
        let other = match.entry
        return NavigationLink(value: other) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(other.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(other.title.isEmpty ? "Ohne Titel" : other.title)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                sharedChips(match.shared)

                if let helped = helpedBack(then: other), !helped.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Damals half dir:")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        ForEach(helped, id: \.self) { line in
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "checkmark.circle")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                                Text(line)
                                    .font(.caption)
                                    .foregroundStyle(.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.cardSurface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.secondary.opacity(0.10)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// What the earlier entry recorded as working: its strategies' solutions
    /// first, then learnings — max three short lines.
    private func helpedBack(then other: JournalEntry) -> [String]? {
        guard let analysis = other.analysis else { return nil }
        var lines: [String] = []
        for strategy in analysis.strategies where !strategy.solution.isEmpty {
            lines.append(strategy.solution)
        }
        for learning in analysis.keyInsights {
            lines.append(learning)
        }
        return Array(lines.prefix(3))
    }

    private func sharedChips(_ shared: [String]) -> some View {
        FlowLayout(spacing: 5) {
            ForEach(shared, id: \.self) { signal in
                Text(signal)
                    .font(.caption2)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.10), in: Capsule())
                    .foregroundStyle(.secondary)
            }
        }
    }
}
