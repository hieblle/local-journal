import SwiftUI
import SwiftData
import Charts

/// The home page, redesigned around a calm, editorial feel: a narrative
/// headline, a **Resilience Score** with sub-metrics, a 30-day mood curve, the
/// familiar stat blocks, recurring themes and a prompt for today.
struct DashboardView: View {
    var goToSection: (AppSection) -> Void
    /// Start a new entry preloaded with a reflection question.
    var onStartWriting: (String) -> Void = { _ in }

    @Environment(\.modelContext) private var context
    @Environment(AnalysisService.self) private var analysis

    @Query(sort: \JournalEntry.date, order: .reverse) private var entries: [JournalEntry]
    @Query private var settingsList: [AppSettings]
    @Query(sort: \JournalPrompt.createdAt, order: .reverse) private var prompts: [JournalPrompt]

    @State private var monitor = OllamaMonitor()

    private var settings: AppSettings { settingsList.first ?? AppSettings() }
    private var recentEntries: [JournalEntry] { Array(entries.prefix(5)) }
    private var pendingCount: Int {
        entries.filter { $0.analysisStatus == .pending || $0.analysisStatus == .failed }.count
    }

    private var resilience: ResilienceScore { ResilienceCalculator.score(for: entries) }
    private var moodSeries: [JournalStatistics.DayValue] { JournalStatistics.moodPerDay(entries, days: 30) }

    private let statColumns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                narrativeHeader

                if pendingCount > 0 { pendingBanner }

                if entries.isEmpty {
                    welcomeCard
                } else {
                    topRow
                    statGrid
                    bottomRow
                    recentEntriesCard
                }
            }
            .padding(24)
            .frame(maxWidth: 1080, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.appBackground)
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

    // MARK: - Narrative header

    private var narrativeHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                SectionLabel(greeting)
                Spacer()
                OllamaStatusBadge(isReachable: monitor.isReachable, isChecking: monitor.isChecking)
            }
            Text(headlineSentence)
                .serif(34)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Top row: resilience + mood

    private var topRow: some View {
        HStack(alignment: .top, spacing: 16) {
            resilienceCard
            moodCard
        }
    }

    private var resilienceCard: some View {
        PanelCard(label: "Resilienz") {
            if !resilience.hasEnoughData {
                Text("Noch zu wenig analysierte Einträge – dein Wert entsteht mit der Zeit.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("\(resilience.overall)").serif(52)
                        deltaBadge
                    }
                    Text(resilience.aboveSixMonthAverage
                         ? "Über deinem Halbjahres-Schnitt."
                         : "Unter deinem Halbjahres-Schnitt.")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    VStack(spacing: 12) {
                        MetricBar(label: "Emotionale Stabilität", value: resilience.emotionalStability)
                        MetricBar(label: "Selbstwirksamkeit", value: resilience.selfEfficacy)
                        MetricBar(label: "Körper & Energie", value: resilience.physicalHealth)
                    }
                    .padding(.top, 4)
                }
            }
        }
    }

    private var deltaBadge: some View {
        let delta = resilience.deltaThisMonth
        let up = delta >= 0
        return HStack(spacing: 4) {
            Image(systemName: up ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                .font(.caption2)
            Text("\(abs(delta)) diesen Monat")
                .font(.caption.weight(.medium))
        }
        .foregroundStyle(delta == 0 ? Color.labelSoft : (up ? Color.sage : Color.orange))
    }

    private var moodCard: some View {
        PanelCard(label: "Stimmung · 30 Tage", trailing: moodTrendLabel) {
            if moodSeries.isEmpty {
                Text("Noch keine Stimmungsdaten – erscheint nach der KI-Analyse.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 200, alignment: .topLeading)
            } else {
                moodChart
            }
        }
    }

    private var moodChart: some View {
        Chart(moodSeries) { item in
            AreaMark(x: .value("Tag", item.day, unit: .day),
                     y: .value("Stimmung", item.value))
                .interpolationMethod(.catmullRom)
                .foregroundStyle(LinearGradient(colors: [Color.sage.opacity(0.28), Color.sage.opacity(0.02)],
                                                startPoint: .top, endPoint: .bottom))
            LineMark(x: .value("Tag", item.day, unit: .day),
                     y: .value("Stimmung", item.value))
                .interpolationMethod(.catmullRom)
                .foregroundStyle(Color.sage)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
        }
        .chartYScale(domain: -1...1)
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: 14)) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    .foregroundStyle(.secondary)
            }
        }
        .frame(height: 200)
    }

    // MARK: - Stat blocks (kept from the previous dashboard)

    private var statGrid: some View {
        LazyVGrid(columns: statColumns, spacing: 12) {
            StatCard(title: "Streak", value: "\(JournalStatistics.currentStreak(entries)) Tage",
                     systemImage: "flame", tint: .orange)
            StatCard(title: "Wörter diese Woche", value: "\(JournalStatistics.wordsThisWeek(entries))",
                     systemImage: "calendar", tint: .blue)
            StatCard(title: "Einträge gesamt", value: "\(entries.count)",
                     systemImage: "book.closed", tint: .purple)
            StatCard(title: "Wörter gesamt", value: "\(JournalStatistics.totalWords(entries))",
                     systemImage: "text.word.spacing", tint: .green)
        }
    }

    // MARK: - Bottom row: themes + prompt

    private var bottomRow: some View {
        HStack(alignment: .top, spacing: 16) {
            themesCard
            promptCard
        }
    }

    private var themesCard: some View {
        PanelCard(label: "Wiederkehrende Themen") {
            if recurringThemes.isEmpty {
                Text("Noch keine Themen erkannt.")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(recurringThemes.enumerated()), id: \.element.text) { index, theme in
                        HStack {
                            Text(theme.text).font(.body)
                            Spacer()
                            Text("\(theme.count) \(theme.count == 1 ? "Erwähnung" : "Erwähnungen")")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 10)
                        if index < recurringThemes.count - 1 { Divider() }
                    }
                }
            }
        }
    }

    private var promptCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionLabel("Impuls für heute", color: .white.opacity(0.55))
            Text(todaysPrompt)
                .serif(22)
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button {
                onStartWriting(todaysPrompt)
            } label: {
                HStack(spacing: 6) {
                    Text("Schreiben")
                    Image(systemName: "arrow.right")
                }
                .font(.callout.weight(.medium))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.white, in: Capsule())
                .foregroundStyle(.black)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(Color.inkPanel, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: - Recent entries

    private var recentEntriesCard: some View {
        PanelCard(label: "Letzte Einträge") {
            VStack(spacing: 0) {
                ForEach(recentEntries) { entry in
                    NavigationLink(value: entry) {
                        DashboardEntryRow(entry: entry)
                    }
                    .buttonStyle(.plain)
                    if entry.id != recentEntries.last?.id { Divider() }
                }
                Button("Alle Einträge ansehen") { goToSection(.entries) }
                    .buttonStyle(.link)
                    .padding(.top, 6)
            }
        }
    }

    // MARK: - Welcome / pending

    private var welcomeCard: some View {
        PanelCard(label: "Willkommen") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Fang mit einem Eintrag an.")
                    .serif(24)
                Text("Resilienz, Stimmungsverlauf und Einsichten entstehen aus dem, was du schreibst.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("Ersten Eintrag schreiben") { goToSection(.write) }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

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
        .padding(16)
        .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Derived copy / data

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        switch hour {
        case 5..<11:  return "Guten Morgen"
        case 11..<17: return "Hallo"
        case 17..<22: return "Guten Abend"
        default:      return "Gute Nacht"
        }
    }

    private var headlineSentence: String {
        guard resilience.hasEnoughData else {
            return "Schreib ein paar Einträge – dein Bild entsteht mit der Zeit."
        }
        let delta = resilience.deltaThisMonth
        if delta >= 3 { return "Du bist diesen Monat spürbar ausgeglichener geworden." }
        if delta <= -3 { return "Dieser Monat war fordernder – auch das darf sein." }
        return "Dein Monat verläuft ruhig und beständig."
    }

    private var moodTrendLabel: String? {
        guard moodSeries.count >= 2,
              let first = moodSeries.first?.value,
              let last = moodSeries.last?.value else { return nil }
        let diff = last - first
        if diff > 0.1 { return "Tendenz aufwärts" }
        if diff < -0.1 { return "Tendenz abwärts" }
        return "stabil"
    }

    private var recurringThemes: [(text: String, count: Int)] {
        var counts: [String: Int] = [:]
        var display: [String: String] = [:]
        for analysis in entries.compactMap(\.analysis) {
            for topic in analysis.topics {
                let value = topic.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !value.isEmpty else { continue }
                let key = value.lowercased()
                counts[key, default: 0] += 1
                if display[key] == nil { display[key] = value }
            }
        }
        return counts
            .map { (display[$0.key] ?? $0.key, $0.value) }
            .sorted { $0.1 > $1.1 }
            .prefix(5)
            .map { (text: $0.0, count: $0.1) }
    }

    private var todaysPrompt: String {
        let available = prompts.filter { !$0.isArchived }
        let favourites = available.filter { $0.isFavorite }
        let pool = favourites.isEmpty ? available : favourites
        guard !pool.isEmpty else { return "Wofür bist du gerade wirklich dankbar – und warum?" }
        let day = Calendar.current.ordinality(of: .day, in: .year, for: .now) ?? 0
        return pool[day % pool.count].text
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
