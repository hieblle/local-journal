import SwiftUI
import SwiftData

/// The home page: a calm overview of streak, volume, recent entries and the
/// most recent AI-detected feelings / topics / people / insights.
struct DashboardView: View {
    var goToSection: (AppSection) -> Void

    @Environment(\.modelContext) private var context
    @Environment(AnalysisService.self) private var analysis

    @Query(sort: \JournalEntry.date, order: .reverse) private var entries: [JournalEntry]
    @Query private var settingsList: [AppSettings]

    @State private var monitor = OllamaMonitor()

    private var settings: AppSettings { settingsList.first ?? AppSettings() }

    private var recentEntries: [JournalEntry] { Array(entries.prefix(5)) }
    private var pendingCount: Int {
        entries.filter { $0.analysisStatus == .pending || $0.analysisStatus == .failed }.count
    }

    // Aggregate signals from the most recent analysed entries.
    private var recentAnalyses: [EntryAnalysis] {
        entries.prefix(10).compactMap(\.analysis)
    }
    private var recentFeelings: [String] { dedupe(recentAnalyses.flatMap(\.feelings), limit: 12) }
    private var recentTopics: [String] { dedupe(recentAnalyses.flatMap(\.topics), limit: 12) }
    private var recentPeople: [String] { dedupe(recentAnalyses.flatMap(\.people), limit: 12) }
    private var recentInsights: [String] { dedupe(recentAnalyses.flatMap(\.keyInsights), limit: 6) }

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                if pendingCount > 0 {
                    pendingBanner
                }

                LazyVGrid(columns: columns, spacing: 12) {
                    StatCard(title: "Streak", value: "\(JournalStatistics.currentStreak(entries)) Tage",
                             systemImage: "flame", tint: .orange)
                    StatCard(title: "Wörter diese Woche", value: "\(JournalStatistics.wordsThisWeek(entries))",
                             systemImage: "calendar", tint: .blue)
                    StatCard(title: "Einträge gesamt", value: "\(entries.count)",
                             systemImage: "book.closed", tint: .purple)
                    StatCard(title: "Wörter gesamt", value: "\(JournalStatistics.totalWords(entries))",
                             systemImage: "text.word.spacing", tint: .green)
                }

                if entries.isEmpty {
                    SectionCard(title: "Willkommen", systemImage: "sparkles") {
                        EmptyHint(title: "Noch keine Einträge",
                                  systemImage: "square.and.pencil",
                                  message: "Schreibe deinen ersten Eintrag, um Streak, Statistiken und KI-Einsichten zu sehen.")
                        Button("Ersten Eintrag schreiben") { goToSection(.write) }
                            .buttonStyle(.borderedProminent)
                            .frame(maxWidth: .infinity)
                    }
                } else {
                    recentEntriesCard
                    insightsCard
                }
            }
            .padding(20)
        }
        .navigationTitle("Dashboard")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { goToSection(.write) } label: {
                    Label("Neuer Eintrag", systemImage: "square.and.pencil")
                }
            }
        }
        .task {
            await monitor.refresh(baseURL: settings.ollamaBaseURL, model: settings.modelName)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(greeting)
                    .font(.title2.weight(.semibold))
                Text(Date.now.formatted(date: .complete, time: .omitted))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            OllamaStatusBadge(isReachable: monitor.isReachable, isChecking: monitor.isChecking)
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        switch hour {
        case 5..<11: return "Guten Morgen"
        case 11..<17: return "Hallo"
        case 17..<22: return "Guten Abend"
        default: return "Gute Nacht"
        }
    }

    // MARK: - Pending banner

    private var pendingBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(pendingCount) Eintrag(e) mit ausstehender Analyse")
                    .font(.callout.weight(.medium))
                Text("Starte die lokale Analyse, sobald Ollama läuft.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Jetzt analysieren") {
                let currentSettings = settings
                Task { @MainActor in
                    await monitor.refresh(baseURL: currentSettings.ollamaBaseURL, model: currentSettings.modelName)
                    await analysis.analyzePending(settings: currentSettings)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(analysis.isWorking)
        }
        .padding(14)
        .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Recent entries

    private var recentEntriesCard: some View {
        SectionCard(title: "Letzte Einträge", systemImage: "clock") {
            VStack(spacing: 0) {
                ForEach(recentEntries) { entry in
                    // Value-based so it routes through the shared
                    // navigationDestination (which injects AnalysisService).
                    NavigationLink(value: entry) {
                        DashboardEntryRow(entry: entry)
                    }
                    .buttonStyle(.plain)
                    if entry.id != recentEntries.last?.id {
                        Divider()
                    }
                }
            }
            Button("Alle Einträge ansehen") { goToSection(.entries) }
                .buttonStyle(.link)
                .padding(.top, 4)
        }
    }

    // MARK: - Insights

    private var insightsCard: some View {
        SectionCard(title: "KI-Einsichten der letzten Einträge", systemImage: "brain") {
            if recentAnalyses.isEmpty {
                EmptyHint(title: "Noch keine Analyse",
                          systemImage: "brain",
                          message: "Sobald Ollama läuft, erscheinen hier Zusammenfassungen, Gefühle, Themen und Personen.")
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    signalBlock(title: "Gefühle", items: recentFeelings, image: "heart", tint: .pink)
                    signalBlock(title: "Themen", items: recentTopics, image: "tag", tint: .blue)
                    signalBlock(title: "Personen", items: recentPeople, image: "person", tint: .purple)

                    if !recentInsights.isEmpty {
                        Divider()
                        Text("Zentrale Erkenntnisse")
                            .font(.subheadline.weight(.medium))
                        ForEach(recentInsights, id: \.self) { insight in
                            Label(insight, systemImage: "sparkle")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func signalBlock(title: String, items: [String], image: String, tint: Color) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                ChipsView(items: items, systemImage: image, tint: tint)
            }
        }
    }

    // MARK: - Helpers

    private func dedupe(_ values: [String], limit: Int) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values {
            let key = value.lowercased()
            guard !value.isEmpty, seen.insert(key).inserted else { continue }
            result.append(value)
            if result.count >= limit { break }
        }
        return result
    }
}

/// Compact entry row used inside the dashboard's recent list.
private struct DashboardEntryRow: View {
    let entry: JournalEntry

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.title.isEmpty ? "Ohne Titel" : entry.title)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                if let summary = entry.analysis?.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                } else {
                    Text(entry.text)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(entry.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                AnalysisStatusBadge(status: entry.analysisStatus)
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}
