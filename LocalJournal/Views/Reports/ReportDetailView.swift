import SwiftUI
import SwiftData
import Charts

/// The full page for one weekly / monthly report: a warm, editorial layout in
/// the dashboard style combining the LLM narrative with the deterministic
/// metrics (resilience, mood, themes, energy, deeper signals) and reflective
/// impulses for the next period.
struct ReportDetailView: View {
    @Bindable var report: PeriodicReport
    /// Start a new entry from a reflective impulse.
    var onStartWriting: (String) -> Void = { _ in }

    @Environment(AnalysisService.self) private var analysis
    @Query private var settingsList: [AppSettings]

    @State private var regenerating = false

    private var settings: AppSettings { settingsList.first ?? AppSettings() }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                overviewSection
                themesSection
                growthSection
                if !report.focus.isEmpty || !report.recommendations.isEmpty { nextStepsCard }
            }
            .padding(24)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.appBackground)
        .navigationTitle(report.kind.reportTitle)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    regenerate()
                } label: {
                    if regenerating {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Neu erzeugen", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(regenerating)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(report.kind.reportTitle)
            Text(report.rangeText)
                .serif(32)
                .foregroundStyle(.primary)
            HStack(spacing: 14) {
                metaItem("book.closed", "\(report.entryCount) Einträge")
                metaItem("calendar", "\(report.daysWritten) Tage")
                metaItem("text.word.spacing", "\(report.wordCount) Wörter")
                if report.entryCountDelta != 0 {
                    let up = report.entryCountDelta > 0
                    metaItem(up ? "arrow.up" : "arrow.down",
                             "\(abs(report.entryCountDelta)) \(report.kind.previousLabel)")
                }
            }
        }
    }

    private func metaItem(_ systemImage: String, _ text: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private var missingNarrativeBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Textzusammenfassung fehlt noch")
                    .font(.callout.weight(.medium))
                Text("Die Kennzahlen unten sind vollständig. Starte Ollama und erzeuge den Bericht neu für den erzählerischen Rückblick.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button("Neu erzeugen") { regenerate() }
                .buttonStyle(.borderedProminent)
                .disabled(regenerating)
        }
        .padding(16)
        .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Sections (grouped to stay within ViewBuilder limits)

    @ViewBuilder private var overviewSection: some View {
        if !report.hasNarrative { missingNarrativeBanner }
        if report.hasNarrative { narrativeCard }
        metricsRow
        if !report.trajectory.isEmpty { trajectoryCard }
        if !report.highlights.isEmpty { highlightsCard }
    }

    @ViewBuilder private var themesSection: some View {
        if !report.topTopics.isEmpty { themesCard }
        if !report.topFeelings.isEmpty || !report.topPeople.isEmpty { feelingsPeopleRow }
        if hasEnergy { energyCard }
    }

    @ViewBuilder private var growthSection: some View {
        if !report.learnings.isEmpty { learningsCard }
        if !report.patterns.isEmpty { patternsCard }
        if hasDeeper { deeperCard }
        if !report.goals.isEmpty || !report.openTasks.isEmpty { goalsTasksCard }
        if !report.strategies.isEmpty { strategiesCard }
    }

    // MARK: - Narrative

    private var narrativeCard: some View {
        PanelCard(label: "Rückblick") {
            Text(report.narrative)
                .font(.system(.title3, design: .serif))
                .foregroundStyle(.primary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var trajectoryCard: some View {
        PanelCard(label: "Entwicklung") {
            Text(report.trajectory)
                .font(.callout)
                .foregroundStyle(.primary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var highlightsCard: some View {
        PanelCard(label: "Höhepunkte") {
            bullets(report.highlights)
        }
    }

    // MARK: - Resilience + mood

    private var metricsRow: some View {
        HStack(alignment: .top, spacing: 16) {
            resilienceCard
            moodCard
        }
    }

    private var resilienceCard: some View {
        PanelCard(label: "Resilienz") {
            if report.resilienceOverall == 0 {
                Text("Zu wenige analysierte Einträge in diesem Zeitraum.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("\(report.resilienceOverall)").serif(48)
                        deltaBadge
                    }
                    Text(report.isAboveBaseline
                         ? "Über deinem Halbjahres-Schnitt (\(report.resilienceBaseline))."
                         : "Unter deinem Halbjahres-Schnitt (\(report.resilienceBaseline)).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    VStack(spacing: 10) {
                        MetricBar(label: "Emotionale Stabilität", value: report.resilienceEmotional)
                        MetricBar(label: "Selbstwirksamkeit", value: report.resilienceEfficacy)
                        MetricBar(label: "Körper & Energie", value: report.resiliencePhysical)
                    }
                }
            }
        }
    }

    private var deltaBadge: some View {
        let delta = report.resilienceDelta
        let up = delta >= 0
        return HStack(spacing: 4) {
            Image(systemName: up ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                .font(.caption2)
            Text("\(abs(delta)) \(report.kind.previousLabel)")
                .font(.caption.weight(.medium))
        }
        .foregroundStyle(delta == 0 ? Color.labelSoft : (up ? Color.sage : Color.orange))
    }

    private var moodCard: some View {
        PanelCard(label: "Stimmung", trailing: moodTrendLabel) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(moodEmoji).font(.title2)
                    Text(moodWord)
                        .font(.title3.weight(.medium))
                }
                if report.moodPoints.count >= 2 {
                    moodChart
                } else {
                    Text("Zu wenige Tage mit Einträgen für einen Verlauf.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var moodChart: some View {
        Chart(report.moodPoints) { point in
            AreaMark(x: .value("Tag", moodDate(point), unit: .day),
                     y: .value("Stimmung", point.value))
                .interpolationMethod(.catmullRom)
                .foregroundStyle(LinearGradient(colors: [Color.sage.opacity(0.28), Color.sage.opacity(0.02)],
                                                startPoint: .top, endPoint: .bottom))
            LineMark(x: .value("Tag", moodDate(point), unit: .day),
                     y: .value("Stimmung", point.value))
                .interpolationMethod(.catmullRom)
                .foregroundStyle(Color.sage)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
        }
        .chartYScale(domain: -1...1)
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(height: 130)
    }

    // MARK: - Themes / feelings / people

    private var themesCard: some View {
        PanelCard(label: "Themen") {
            VStack(alignment: .leading, spacing: 12) {
                countedList(report.topTopics)
                if !report.newTopics.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel("Neu in diesem Zeitraum")
                        chips(report.newTopics, tint: .sage)
                    }
                }
            }
        }
    }

    private var feelingsPeopleRow: some View {
        HStack(alignment: .top, spacing: 16) {
            if !report.topFeelings.isEmpty {
                PanelCard(label: "Gefühle") { countedList(report.topFeelings) }
            }
            if !report.topPeople.isEmpty {
                PanelCard(label: "Menschen") { countedList(report.topPeople) }
            }
        }
    }

    private var hasEnergy: Bool { !report.energyGivers.isEmpty || !report.energyDrainers.isEmpty }

    private var energyCard: some View {
        PanelCard(label: "Energie") {
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Gibt Energie", systemImage: "bolt.fill").font(.caption).foregroundStyle(.green)
                    if report.energyGivers.isEmpty {
                        Text("—").foregroundStyle(.tertiary)
                    } else {
                        ForEach(report.energyGivers) { tag in
                            Text("• \(tag.label)").font(.callout)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 8) {
                    Label("Kostet Energie", systemImage: "bolt.slash.fill").font(.caption).foregroundStyle(.orange)
                    if report.energyDrainers.isEmpty {
                        Text("—").foregroundStyle(.tertiary)
                    } else {
                        ForEach(report.energyDrainers) { tag in
                            Text("• \(tag.label)").font(.callout)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var learningsCard: some View {
        PanelCard(label: "Learnings") { bullets(report.learnings) }
    }

    private var patternsCard: some View {
        PanelCard(label: "Muster") { bullets(report.patterns) }
    }

    private var hasDeeper: Bool {
        !report.beliefs.isEmpty || !report.triggers.isEmpty || !report.needs.isEmpty
    }

    private var deeperCard: some View {
        PanelCard(label: "Tiefere Ebene") {
            VStack(alignment: .leading, spacing: 14) {
                if !report.beliefs.isEmpty { labelledChips("Glaubenssätze", report.beliefs, tint: .purple) }
                if !report.triggers.isEmpty { labelledChips("Trigger", report.triggers, tint: .pink) }
                if !report.needs.isEmpty { labelledChips("Bedürfnisse", report.needs, tint: .teal) }
            }
        }
    }

    private var goalsTasksCard: some View {
        PanelCard(label: "Ziele & Vorhaben") {
            VStack(alignment: .leading, spacing: 14) {
                if !report.goals.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel("Ziele")
                        bullets(report.goals)
                    }
                }
                if !report.openTasks.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel("Offene Vorhaben")
                        bullets(report.openTasks)
                    }
                }
            }
        }
    }

    private var strategiesCard: some View {
        PanelCard(label: "Strategien") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(report.strategies) { note in
                    VStack(alignment: .leading, spacing: 4) {
                        Label(note.problem, systemImage: "exclamationmark.triangle")
                            .font(.callout).foregroundStyle(.secondary)
                        Label(note.solution, systemImage: "arrow.turn.down.right")
                            .font(.callout).foregroundStyle(.primary)
                    }
                    if note.id != report.strategies.last?.id { Divider() }
                }
            }
        }
    }

    private var nextStepsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionLabel("Für die/den nächste(n) \(report.kind.unitLabel)", color: .white.opacity(0.55))
            if !report.focus.isEmpty {
                Text(report.focus)
                    .serif(22)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !report.recommendations.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(report.recommendations, id: \.self) { impulse in
                        Button {
                            onStartWriting(impulse)
                        } label: {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "pencil.line").foregroundStyle(.white.opacity(0.7))
                                Text(impulse)
                                    .font(.callout)
                                    .foregroundStyle(.white)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                                Image(systemName: "arrow.right").font(.caption).foregroundStyle(.white.opacity(0.6))
                            }
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Neuen Eintrag damit starten")
                        if impulse != report.recommendations.last {
                            Divider().overlay(Color.white.opacity(0.12))
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(Color.inkPanel, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: - Small building blocks

    private func countedList(_ tags: [CountedTag]) -> some View {
        VStack(spacing: 0) {
            ForEach(tags) { tag in
                HStack {
                    Text(tag.label).font(.callout)
                    Spacer()
                    Text("\(tag.count)×")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .padding(.vertical, 7)
                if tag.id != tags.last?.id { Divider() }
            }
        }
    }

    private func bullets(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 8) {
                    Text("•").foregroundStyle(Color.sage)
                    Text(item)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func labelledChips(_ label: String, _ items: [String], tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(label)
            chips(items, tint: tint)
        }
    }

    private func chips(_ items: [String], tint: Color) -> some View {
        ChipsView(items: items, tint: tint)
    }

    // MARK: - Derived copy / helpers

    private func moodDate(_ point: ReportMoodPoint) -> Date {
        Calendar.current.date(byAdding: .day, value: point.dayOffset, to: report.periodStart) ?? report.periodStart
    }

    private var moodTrendLabel: String? {
        guard report.moodPoints.count >= 2 else { return nil }
        let diff = report.moodEnd - report.moodStart
        if diff > 0.1 { return "aufwärts" }
        if diff < -0.1 { return "abwärts" }
        return "stabil"
    }

    private var moodWord: String {
        switch report.averageMood {
        case 0.35...:      return "überwiegend positiv"
        case 0.1..<0.35:   return "eher positiv"
        case -0.1..<0.1:   return "ausgeglichen"
        case -0.35..<(-0.1): return "eher belastet"
        default:           return "überwiegend belastet"
        }
    }

    private var moodEmoji: String {
        switch report.averageMood {
        case 0.35...:        return "😊"
        case 0.1..<0.35:     return "🙂"
        case -0.1..<0.1:     return "😐"
        case -0.35..<(-0.1): return "😕"
        default:             return "😔"
        }
    }

    // MARK: - Actions

    private func regenerate() {
        regenerating = true
        let currentSettings = settings
        let kind = report.kind
        let reference = report.periodStart
        Task { @MainActor in
            await analysis.generateReport(kind: kind, reference: reference,
                                          settings: currentSettings, requireEntries: false)
            regenerating = false
        }
    }
}
