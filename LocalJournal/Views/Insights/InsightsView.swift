import SwiftUI
import SwiftData

/// "Einsichten": a synthesis across all entries that answers the reflective
/// questions —
///  1. Which inner patterns repeat?
///  2. Which triggers cause which feelings?
///  3. Which beliefs stand behind my behaviour?
///  4. Which strategies really help?
///  5. Which learnings recur?
///  6. Where have I changed over time?
///
/// Most sections are deterministic aggregations of the per-entry analysis (plus
/// the knowledge graph for trigger→feeling links). Two sections use an on-demand
/// local LLM synthesis (change over time, value alignment).
struct InsightsView: View {
    @Environment(\.modelContext) private var context
    @Environment(AnalysisService.self) private var analysis

    @Query(sort: \JournalEntry.date, order: .reverse) private var entries: [JournalEntry]
    @Query private var edges: [KnowledgeEdge]
    @Query(sort: [SortDescriptor(\GuidingPrinciple.sortIndex), SortDescriptor(\GuidingPrinciple.createdAt)])
    private var principles: [GuidingPrinciple]
    @Query private var settingsList: [AppSettings]

    // On-demand LLM syntheses (ephemeral).
    @State private var changeText = ""
    @State private var loadingChange = false
    @State private var alignmentText = ""
    @State private var loadingAlignment = false

    // Values / goals editor sheet.
    @State private var showPrincipleEditor = false
    @State private var editingPrinciple: GuidingPrinciple?
    @State private var newPrincipleKind: PrincipleKind = .value

    private var settings: AppSettings { settingsList.first ?? AppSettings() }
    private var analyses: [EntryAnalysis] { entries.compactMap(\.analysis) }
    private var hasAnalyses: Bool { !analyses.isEmpty }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                intro

                if !hasAnalyses {
                    SectionCard(title: "Noch keine Einsichten", systemImage: "brain.head.profile") {
                        EmptyHint(title: "Zu wenig Material",
                                  systemImage: "sparkles",
                                  message: "Schreibe und analysiere ein paar Einträge – dann verdichtet sich hier, was sich wiederholt, was dich auslöst und wie du dich veränderst.")
                    }
                } else {
                    patternsSection
                    triggerFeelingSection
                    beliefsSection
                    needsSection
                    energySection
                    strategiesSection
                    learningsSection
                    changeOverTimeSection
                }

                valuesSection   // usable even without analyses (authoring)
            }
            .padding(20)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Einsichten")
        .sheet(isPresented: $showPrincipleEditor) {
            PrincipleEditorSheet(
                initialKind: editingPrinciple?.kind ?? newPrincipleKind,
                initialTitle: editingPrinciple?.title ?? "",
                initialDetail: editingPrinciple?.detail ?? "",
                isEditing: editingPrinciple != nil
            ) { kind, title, detail in
                if let principle = editingPrinciple {
                    principle.kind = kind
                    principle.title = title
                    principle.detail = detail
                } else {
                    context.insert(GuidingPrinciple(kind: kind, title: title, detail: detail))
                }
                try? context.save()
            }
        }
    }

    // MARK: - Intro

    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Was deine Einträge über dich zeigen")
                .font(.title2.weight(.semibold))
            Text("Verdichtet aus \(entries.count) Einträgen – wiederkehrende Muster, Auslöser, Glaubenssätze, Strategien und deine Entwicklung.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 1. Patterns

    private var patternsSection: some View {
        let ranked = frequency(analyses.flatMap { $0.patterns })
        return SectionCard(title: "Wiederkehrende Muster", systemImage: "repeat") {
            countRows(ranked,
                      icon: "arrow.triangle.branch",
                      tint: .indigo,
                      empty: "Noch keine Muster erkannt.")
        }
    }

    // MARK: - 2. Trigger → feeling

    /// person/topic —causes→ feeling, taken straight from the knowledge graph.
    private var triggerFeelingLinks: [TriggerLink] {
        edges.compactMap { edge in
            guard let from = edge.from, let to = edge.to else { return nil }
            guard edge.relation == .causes, to.kind == .feeling,
                  from.kind == .person || from.kind == .topic else { return nil }
            return TriggerLink(from: from.name, feeling: to.name, weight: edge.weight)
        }
        .sorted { $0.weight > $1.weight }
    }

    private var triggerFeelingSection: some View {
        let links = triggerFeelingLinks
        let triggerWords = frequency(analyses.flatMap { $0.triggers })
        return SectionCard(title: "Trigger → Gefühle", systemImage: "bolt.heart") {
            VStack(alignment: .leading, spacing: 12) {
                if links.isEmpty && triggerWords.isEmpty {
                    Text("Noch keine klaren Auslöser-Gefühl-Verbindungen.")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                }
                ForEach(links.prefix(10)) { link in
                    HStack(spacing: 8) {
                        Text(link.from)
                            .font(.callout.weight(.medium))
                        Image(systemName: "arrow.right").font(.caption).foregroundStyle(.secondary)
                        Text(link.feeling)
                            .font(.callout)
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .background(.pink.opacity(0.14), in: Capsule())
                            .foregroundStyle(.pink)
                        Spacer()
                        if link.weight > 1 { countBadge(link.weight) }
                    }
                }
                if !triggerWords.isEmpty {
                    if !links.isEmpty { Divider() }
                    Text("Häufige Auslöser")
                        .font(.subheadline.weight(.medium))
                    countChips(triggerWords, tint: .orange)
                }
            }
        }
    }

    // MARK: - 3. Beliefs

    private var beliefsSection: some View {
        let ranked = frequency(analyses.flatMap { $0.beliefs })
        return SectionCard(title: "Glaubenssätze", systemImage: "quote.bubble") {
            countRows(ranked,
                      icon: "text.quote",
                      tint: .purple,
                      empty: "Noch keine Glaubenssätze erkannt. Sie entstehen aus tieferer Analyse mehrerer Einträge.")
        }
    }

    // MARK: - Needs

    private var needsSection: some View {
        let ranked = frequency(analyses.flatMap { $0.needs })
        return SectionCard(title: "Bedürfnisse", systemImage: "leaf") {
            if ranked.isEmpty {
                emptyLine("Noch keine Bedürfnisse erkannt.")
            } else {
                countChips(ranked, tint: .teal)
            }
        }
    }

    // MARK: - Energy

    private var energySection: some View {
        let givers = frequency(analyses.flatMap { $0.energyGivers })
        let drainers = frequency(analyses.flatMap { $0.energyDrainers })
        return SectionCard(title: "Energie", systemImage: "bolt") {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Gibt Energie", systemImage: "arrow.up.circle.fill")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.green)
                    if givers.isEmpty { emptyLine("—") } else { countChips(givers, tint: .green) }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Label("Kostet Energie", systemImage: "arrow.down.circle.fill")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.orange)
                    if drainers.isEmpty { emptyLine("—") } else { countChips(drainers, tint: .orange) }
                }
            }
        }
    }

    // MARK: - 4. Strategies

    private var strategiesSection: some View {
        // Most recent first, de-duplicated.
        var seen = Set<String>()
        let notes = analyses
            .sorted { $0.createdAt > $1.createdAt }
            .flatMap { $0.strategies }
            .filter { seen.insert($0.id).inserted }
            .prefix(12)
        return SectionCard(title: "Strategien: Fehler → Lösung", systemImage: "lightbulb.max") {
            if notes.isEmpty {
                emptyLine("Noch keine Strategien gesammelt. Sie entstehen, wenn ein Eintrag einen Fehler UND einen Umgang damit beschreibt.")
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(notes)) { note in
                        VStack(alignment: .leading, spacing: 4) {
                            if !note.problem.isEmpty {
                                Label(note.problem, systemImage: "exclamationmark.triangle")
                                    .font(.callout)
                                    .foregroundStyle(.orange)
                            }
                            if !note.solution.isEmpty {
                                Label(note.solution, systemImage: "checkmark.circle")
                                    .font(.callout)
                                    .foregroundStyle(.green)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color.cardSurface, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.secondary.opacity(0.12)))
                    }
                }
            }
        }
    }

    // MARK: - 5. Recurring learnings

    private var learningsSection: some View {
        let ranked = frequency(analyses.flatMap { $0.keyInsights })
        return SectionCard(title: "Wiederkehrende Learnings", systemImage: "graduationcap") {
            countRows(ranked,
                      icon: "sparkle",
                      tint: .blue,
                      empty: "Noch keine Learnings erkannt.")
        }
    }

    // MARK: - 6. Change over time

    private var changeOverTimeSection: some View {
        SectionCard(title: "Veränderung über Zeit", systemImage: "chart.line.uptrend.xyaxis") {
            VStack(alignment: .leading, spacing: 12) {
                moodTrendRow
                if !changeText.isEmpty {
                    Text(changeText)
                        .font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Button {
                    runChangeSynthesis()
                } label: {
                    if loadingChange {
                        HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Analysiere Verlauf …") }
                    } else {
                        Label(changeText.isEmpty ? "Wie habe ich mich verändert?" : "Neu analysieren",
                              systemImage: "sparkles")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(loadingChange)
            }
        }
    }

    /// Average mood of the earliest vs. the most recent analysed entries.
    private var moodTrendRow: some View {
        let scored = entries
            .compactMap { $0.analysis }
            .sorted { ($0.entry?.date ?? .distantPast) < ($1.entry?.date ?? .distantPast) }
            .map(\.moodScore)
        let early = Array(scored.prefix(5))
        let recent = Array(scored.suffix(5))
        let earlyAvg = early.isEmpty ? 0 : early.reduce(0, +) / Double(early.count)
        let recentAvg = recent.isEmpty ? 0 : recent.reduce(0, +) / Double(recent.count)
        return HStack(spacing: 16) {
            moodPill(title: "Früher", value: earlyAvg)
            Image(systemName: "arrow.right").foregroundStyle(.secondary)
            moodPill(title: "Zuletzt", value: recentAvg)
        }
    }

    private func moodPill(title: String, value: Double) -> some View {
        VStack(spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(moodLabel(value)).font(.callout.weight(.medium)).foregroundStyle(moodColor(value))
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(moodColor(value).opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Values & goals

    private var valuesSection: some View {
        let values = principles.filter { $0.kind == .value }
        let goals = principles.filter { $0.kind == .goal }
        return SectionCard(title: "Werte & Ziele", systemImage: "heart.text.square") {
            VStack(alignment: .leading, spacing: 14) {
                Text("Schreib auf, wofür du stehst und was du erreichen willst. Die App gleicht das mit deinen tatsächlichen Einträgen ab.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                principleGroup(title: "Meine Werte", kind: .value, items: values)
                principleGroup(title: "Meine Ziele", kind: .goal, items: goals)

                if !alignmentText.isEmpty {
                    Divider()
                    Label("Abgleich", systemImage: "checkmark.seal")
                        .font(.subheadline.weight(.medium))
                    Text(alignmentText)
                        .font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button {
                    runAlignment(values: values.map(\.title), goals: goals.map(\.title))
                } label: {
                    if loadingAlignment {
                        HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Gleiche ab …") }
                    } else {
                        Label("Mit meinen Einträgen abgleichen", systemImage: "sparkles")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(loadingAlignment || (values.isEmpty && goals.isEmpty))
            }
        }
    }

    private func principleGroup(title: String, kind: PrincipleKind, items: [GuidingPrinciple]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(title, systemImage: kind.systemImage)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Button {
                    editingPrinciple = nil
                    newPrincipleKind = kind
                    showPrincipleEditor = true
                } label: {
                    Label("Hinzufügen", systemImage: "plus")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .help("\(kind.singular) hinzufügen")
            }
            if items.isEmpty {
                emptyLine("Noch keine \(kind.plural) formuliert.")
            } else {
                ForEach(items) { principle in
                    principleRow(principle)
                }
            }
        }
    }

    private func principleRow(_ principle: GuidingPrinciple) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: principle.kind.systemImage)
                .foregroundStyle(principle.kind == .value ? .pink : .mint)
            VStack(alignment: .leading, spacing: 2) {
                Text(principle.title).font(.callout.weight(.medium))
                if !principle.detail.isEmpty {
                    Text(principle.detail).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                editingPrinciple = principle
                showPrincipleEditor = true
            } label: { Image(systemName: "pencil") }
                .buttonStyle(.borderless)
            Button(role: .destructive) {
                context.delete(principle)
                try? context.save()
            } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .foregroundStyle(.red)
        }
        .padding(10)
        .background(Color.cardSurface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.secondary.opacity(0.12)))
    }

    // MARK: - Reusable rendering

    /// A vertical list of ranked strings with a recurrence badge.
    @ViewBuilder
    private func countRows(_ ranked: [(text: String, count: Int)],
                           icon: String, tint: Color, empty: String) -> some View {
        if ranked.isEmpty {
            emptyLine(empty)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(ranked.prefix(12), id: \.text) { item in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: icon).font(.caption).foregroundStyle(tint)
                        Text(item.text)
                            .font(.callout)
                            .foregroundStyle(item.count > 1 ? .primary : .secondary)
                        Spacer()
                        if item.count > 1 { countBadge(item.count) }
                    }
                }
            }
        }
    }

    private func countChips(_ ranked: [(text: String, count: Int)], tint: Color) -> some View {
        FlowLayout(spacing: 6) {
            ForEach(ranked.prefix(20), id: \.text) { item in
                HStack(spacing: 4) {
                    Text(item.text).font(.callout)
                    if item.count > 1 {
                        Text("\(item.count)")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(tint.opacity(0.28), in: Capsule())
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(tint.opacity(0.12), in: Capsule())
                .foregroundStyle(tint)
            }
        }
    }

    private func countBadge(_ count: Int) -> some View {
        Text("×\(count)")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(.secondary.opacity(0.15), in: Capsule())
            .foregroundStyle(.secondary)
    }

    private func emptyLine(_ text: String) -> some View {
        Text(text).font(.callout).foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Aggregation

    /// Count occurrences (case-insensitive), preserve first-seen casing, sort by
    /// count desc then alphabetically.
    private func frequency(_ values: [String]) -> [(text: String, count: Int)] {
        var counts: [String: Int] = [:]
        var display: [String: String] = [:]
        for raw in values {
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { continue }
            let key = value.lowercased()
            counts[key, default: 0] += 1
            if display[key] == nil { display[key] = value }
        }
        return counts
            .map { (text: display[$0.key] ?? $0.key, count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.text < $1.text }
    }

    private func moodLabel(_ value: Double) -> String {
        switch value {
        case 0.25...:   return "positiv"
        case ..<(-0.25): return "belastet"
        default:        return "neutral"
        }
    }

    private func moodColor(_ value: Double) -> Color {
        switch value {
        case 0.25...:   return .green
        case ..<(-0.25): return .orange
        default:        return .secondary
        }
    }

    // MARK: - Actions

    private func runChangeSynthesis() {
        loadingChange = true
        let currentSettings = settings
        Task { @MainActor in
            let text = await analysis.reflectOnChange(settings: currentSettings)
            changeText = text.isEmpty ? "Noch zu wenig analysierte Einträge oder Ollama nicht erreichbar." : text
            loadingChange = false
        }
    }

    private func runAlignment(values: [String], goals: [String]) {
        loadingAlignment = true
        let currentSettings = settings
        Task { @MainActor in
            let text = await analysis.checkValueAlignment(values: values, goals: goals, settings: currentSettings)
            alignmentText = text.isEmpty ? "Kein Abgleich möglich – läuft Ollama und gibt es analysierte Einträge?" : text
            loadingAlignment = false
        }
    }
}

/// A person/topic → feeling link surfaced from the knowledge graph.
private struct TriggerLink: Identifiable {
    let from: String
    let feeling: String
    let weight: Int
    var id: String { from + "→" + feeling }
}

/// Sheet for adding or editing a value / goal.
private struct PrincipleEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let initialKind: PrincipleKind
    let initialTitle: String
    let initialDetail: String
    let isEditing: Bool
    var onSave: (PrincipleKind, String, String) -> Void

    @State private var kind: PrincipleKind
    @State private var title: String
    @State private var detail: String

    init(initialKind: PrincipleKind,
         initialTitle: String,
         initialDetail: String,
         isEditing: Bool,
         onSave: @escaping (PrincipleKind, String, String) -> Void) {
        self.initialKind = initialKind
        self.initialTitle = initialTitle
        self.initialDetail = initialDetail
        self.isEditing = isEditing
        self.onSave = onSave
        _kind = State(initialValue: initialKind)
        _title = State(initialValue: initialTitle)
        _detail = State(initialValue: initialDetail)
    }

    private var trimmed: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isEditing ? "Bearbeiten" : "Neu")
                .font(.title3.weight(.semibold))

            Picker("Art", selection: $kind) {
                ForEach(PrincipleKind.allCases) { Text($0.singular).tag($0) }
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 6) {
                Text(kind == .value ? "Wert" : "Ziel")
                    .font(.caption).foregroundStyle(.secondary)
                TextField(kind == .value ? "z. B. Ehrlichkeit" : "z. B. Mehr Zeit für Familie", text: $title)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Bedeutung (optional)")
                    .font(.caption).foregroundStyle(.secondary)
                TextField("Was heißt das für mich?", text: $detail, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)
            }

            HStack {
                Spacer()
                Button("Abbrechen") { dismiss() }
                Button(isEditing ? "Sichern" : "Hinzufügen") {
                    guard !trimmed.isEmpty else { return }
                    onSave(kind, trimmed, detail.trimmingCharacters(in: .whitespacesAndNewlines))
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(trimmed.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 440)
    }
}
