import SwiftUI
import SwiftData

/// Chronological list of all journal entries. (Full-text search is intentionally
/// deferred to a later version — see Roadmap.md.)
struct EntryListView: View {
    @Environment(\.modelContext) private var context

    @Query(sort: \JournalEntry.date, order: .reverse) private var entries: [JournalEntry]
    @Query private var settingsList: [AppSettings]

    var body: some View {
        Group {
            if entries.isEmpty {
                EmptyHint(title: "Noch keine Einträge",
                          systemImage: "book.closed",
                          message: "Deine geschriebenen Einträge erscheinen hier.")
            } else {
                List {
                    ForEach(entries) { entry in
                        NavigationLink(value: entry) {
                            EntryRow(entry: entry)
                        }
                    }
                    .onDelete(perform: delete)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("Einträge")
    }

    private func delete(at offsets: IndexSet) {
        let settings = settingsList.first ?? AppSettings()
        for index in offsets {
            MarkdownMirror.removeEntry(entries[index], settings: settings)
            context.delete(entries[index])
        }
        try? context.save()
    }
}

private struct EntryRow: View {
    let entry: JournalEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(entry.title.isEmpty ? "Ohne Titel" : entry.title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Text(entry.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(entry.analysis?.summary.isEmpty == false ? entry.analysis!.summary : entry.text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack(spacing: 8) {
                AnalysisStatusBadge(status: entry.analysisStatus)
                Text("\(entry.wordCount) Wörter")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}
