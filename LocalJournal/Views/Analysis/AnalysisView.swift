import SwiftUI
import SwiftData
import Charts

/// Visual analysis page: simple, calm charts plus the recognised-entity lists.
struct AnalysisView: View {
    @Query(sort: \JournalEntry.date, order: .reverse) private var entries: [JournalEntry]
    @Query private var topics: [TopicEntity]
    @Query private var people: [PersonEntity]

    private var hasData: Bool { !entries.isEmpty }

    private var topTopics: [TopicEntity] {
        topics.filter { !$0.entries.isEmpty }
            .sorted { $0.entries.count > $1.entries.count }
    }
    private var topPeople: [PersonEntity] {
        people.filter { !$0.entries.isEmpty }
            .sorted { $0.entries.count > $1.entries.count }
    }
    private var topFeelings: [JournalStatistics.Counted] {
        JournalStatistics.topFeelings(entries)
    }

    var body: some View {
        ScrollView {
            if !hasData {
                EmptyHint(title: "Noch keine Daten",
                          systemImage: "chart.bar.xaxis",
                          message: "Schreibe ein paar Einträge – die Analyse füllt sich automatisch.")
                    .padding(40)
            } else {
                VStack(alignment: .leading, spacing: 20) {
                    wordsChart
                    frequencyChart
                    moodChart
                    topicsChart
                    peopleChart
                    feelingsChart
                    entitiesSection
                }
                .padding(20)
            }
        }
        .navigationTitle("Analyse")
    }

    // MARK: - Charts

    private var wordsChart: some View {
        SectionCard(title: "Wörter pro Tag (30 Tage)", systemImage: "text.word.spacing") {
            Chart(JournalStatistics.wordsPerDay(entries, days: 30)) { item in
                BarMark(
                    x: .value("Tag", item.day, unit: .day),
                    y: .value("Wörter", item.value)
                )
                .foregroundStyle(Color.accentColor.gradient)
            }
            .frame(height: 180)
            .chartXAxis { AxisMarks(values: .stride(by: .day, count: 7)) }
        }
    }

    private var frequencyChart: some View {
        SectionCard(title: "Journaling-Häufigkeit (30 Tage)", systemImage: "calendar") {
            Chart(JournalStatistics.entriesPerDay(entries, days: 30)) { item in
                BarMark(
                    x: .value("Tag", item.day, unit: .day),
                    y: .value("Einträge", item.value)
                )
                .foregroundStyle(Color.green.gradient)
            }
            .frame(height: 140)
            .chartXAxis { AxisMarks(values: .stride(by: .day, count: 7)) }
            .chartYAxis { AxisMarks(values: .automatic(desiredCount: 3)) }
        }
    }

    @ViewBuilder
    private var moodChart: some View {
        let mood = JournalStatistics.moodPerDay(entries, days: 30)
        SectionCard(title: "Stimmung über Zeit", systemImage: "face.smiling") {
            if mood.isEmpty {
                Text("Noch keine Stimmungsdaten – wird nach der KI-Analyse gefüllt.")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            } else {
                Chart(mood) { item in
                    LineMark(
                        x: .value("Tag", item.day, unit: .day),
                        y: .value("Stimmung", item.value)
                    )
                    .interpolationMethod(.catmullRom)
                    PointMark(
                        x: .value("Tag", item.day, unit: .day),
                        y: .value("Stimmung", item.value)
                    )
                }
                .chartYScale(domain: -1...1)
                .frame(height: 160)
            }
        }
    }

    @ViewBuilder
    private var topicsChart: some View {
        let items = Array(topTopics.prefix(8))
        SectionCard(title: "Häufigste Themen", systemImage: "tag") {
            if items.isEmpty {
                emptyChartHint
            } else {
                Chart(items) { topic in
                    BarMark(
                        x: .value("Erwähnungen", topic.entries.count),
                        y: .value("Thema", topic.name)
                    )
                    .foregroundStyle(Color.blue.gradient)
                }
                .frame(height: CGFloat(items.count) * 28 + 20)
            }
        }
    }

    @ViewBuilder
    private var peopleChart: some View {
        let items = Array(topPeople.prefix(8))
        SectionCard(title: "Häufig erwähnte Personen", systemImage: "person.2") {
            if items.isEmpty {
                emptyChartHint
            } else {
                Chart(items) { person in
                    BarMark(
                        x: .value("Erwähnungen", person.entries.count),
                        y: .value("Person", person.name)
                    )
                    .foregroundStyle(Color.purple.gradient)
                }
                .frame(height: CGFloat(items.count) * 28 + 20)
            }
        }
    }

    @ViewBuilder
    private var feelingsChart: some View {
        SectionCard(title: "Häufigste Gefühle", systemImage: "heart") {
            if topFeelings.isEmpty {
                emptyChartHint
            } else {
                Chart(topFeelings) { feeling in
                    BarMark(
                        x: .value("Anzahl", feeling.count),
                        y: .value("Gefühl", feeling.label)
                    )
                    .foregroundStyle(Color.pink.gradient)
                }
                .frame(height: CGFloat(topFeelings.count) * 28 + 20)
            }
        }
    }

    private var emptyChartHint: some View {
        Text("Noch keine Daten – erscheint nach der KI-Analyse.")
            .font(.callout)
            .foregroundStyle(.tertiary)
    }

    // MARK: - Entities

    private var entitiesSection: some View {
        SectionCard(title: "Erkannte Entitäten", systemImage: "circle.grid.cross") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Themen")
                    .font(.subheadline.weight(.medium))
                if topTopics.isEmpty {
                    Text("Noch keine Themen erkannt.").font(.callout).foregroundStyle(.tertiary)
                } else {
                    ForEach(topTopics) { topic in
                        EntityDisclosure(name: topic.name, count: topic.entries.count,
                                         entries: sortedEntries(topic.entries))
                    }
                }

                Divider().padding(.vertical, 4)

                Text("Personen")
                    .font(.subheadline.weight(.medium))
                if topPeople.isEmpty {
                    Text("Noch keine Personen erkannt.").font(.callout).foregroundStyle(.tertiary)
                } else {
                    ForEach(topPeople) { person in
                        EntityDisclosure(name: person.name, count: person.entries.count,
                                         entries: sortedEntries(person.entries))
                    }
                }
            }
        }
    }

    private func sortedEntries(_ entries: [JournalEntry]) -> [JournalEntry] {
        entries.sorted { $0.date > $1.date }
    }
}

/// Expandable row: an entity name + count, revealing its linked entries.
private struct EntityDisclosure: View {
    let name: String
    let count: Int
    let entries: [JournalEntry]

    var body: some View {
        DisclosureGroup {
            ForEach(entries) { entry in
                NavigationLink(value: entry) {
                    HStack {
                        Text(entry.title.isEmpty ? "Ohne Titel" : entry.title)
                            .font(.callout)
                        Spacer()
                        Text(entry.date.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        } label: {
            HStack {
                Text(name)
                    .font(.callout.weight(.medium))
                Spacer()
                Text("\(count)")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }
        }
    }
}
