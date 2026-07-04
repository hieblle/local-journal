import SwiftUI
import SwiftData

/// Detail view for a single entry. Two modes:
///  - **Read**: the entry text plus its structured AI analysis.
///  - **Edit**: title, date and text become editable (tap "Bearbeiten").
/// Offers a "neu analysieren" action (useful after edits or for entries written
/// while Ollama was offline).
struct EntryDetailView: View {
    @Bindable var entry: JournalEntry
    /// Start a fresh entry preloaded with a reflection question.
    var onStartWriting: (String) -> Void = { _ in }

    @Environment(\.modelContext) private var context
    @Environment(AnalysisService.self) private var analysis
    @Environment(\.dismiss) private var dismiss

    @Query private var settingsList: [AppSettings]
    private var settings: AppSettings { settingsList.first ?? AppSettings() }

    @State private var showDeleteConfirm = false

    // Edit mode + drafts.
    @State private var isEditing = false
    @State private var draftTitle = ""
    @State private var draftDate = Date.now
    @State private var draftText = ""

    // Critical-reflection question generation.
    @State private var reflectionQuestions: [String] = []
    @State private var isGeneratingReflection = false
    @State private var reflectionMessage: String?
    @State private var savedQuestions: Set<String> = []

    private var draftWordCount: Int { JournalEntry.countWords(in: draftText) }
    private var canSaveEdits: Bool {
        !draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The text was changed after the last analysis ran, so the analysis is stale.
    private var analysisIsStale: Bool {
        guard let a = entry.analysis, entry.analysisStatus == .completed else { return false }
        return entry.updatedAt > a.createdAt.addingTimeInterval(1)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerCard
                if isEditing {
                    editCard
                } else {
                    entryTextCard
                    if analysisIsStale {
                        staleAnalysisBanner
                    }
                    if let analysis = entry.analysis, entry.analysisStatus == .completed {
                        analysisSection(analysis)
                    } else {
                        analysisPlaceholder
                    }
                    reflectionCard
                }
            }
            .padding(20)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(isEditing ? "Eintrag bearbeiten"
                                   : (entry.title.isEmpty ? "Eintrag" : entry.title))
        .toolbar { toolbarContent }
        .confirmationDialog("Diesen Eintrag löschen?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Löschen", role: .destructive) {
                context.delete(entry)
                try? context.save()
                dismiss()
            }
            Button("Abbrechen", role: .cancel) {}
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if isEditing {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Abbrechen") { isEditing = false }
                Button {
                    saveEdits()
                } label: {
                    Label("Sichern", systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSaveEdits)
                .keyboardShortcut("s", modifiers: .command)
            }
        } else {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    beginEditing()
                } label: {
                    Label("Bearbeiten", systemImage: "pencil")
                }

                Button {
                    reanalyze()
                } label: {
                    if entry.analysisStatus == .running {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Neu analysieren", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .disabled(entry.analysisStatus == .running)

                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label("Löschen", systemImage: "trash")
                }
            }
        }
    }

    // MARK: - Header

    private var headerCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.date.formatted(date: .complete, time: .omitted))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Label("\(isEditing ? draftWordCount : entry.wordCount) Wörter",
                          systemImage: "text.word.spacing")
                    if entry.writingSeconds > 0 {
                        Label(formattedDuration(entry.writingSeconds), systemImage: "timer")
                    }
                    if entry.updatedAt > entry.createdAt.addingTimeInterval(1) {
                        Label("bearbeitet", systemImage: "pencil")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            AnalysisStatusBadge(status: entry.analysisStatus)
        }
    }

    // MARK: - Read: entry text

    private var entryTextCard: some View {
        SectionCard(title: "Eintrag", systemImage: "doc.text") {
            Text(entry.text.isEmpty ? "(kein Text)" : entry.text)
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Edit: title / date / text

    private var editCard: some View {
        SectionCard(title: "Eintrag bearbeiten", systemImage: "pencil") {
            VStack(alignment: .leading, spacing: 14) {
                TextField("Titel (optional)", text: $draftTitle)
                    .textFieldStyle(.plain)
                    .font(.title3.weight(.semibold))

                DateFieldButton(date: $draftDate)

                Divider()

                TextEditorWithPlaceholder(text: $draftText,
                                          placeholder: "Schreib deinen Eintrag …",
                                          minHeight: 300)

                HStack {
                    Label("\(draftWordCount) Wörter", systemImage: "text.word.spacing")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if settings.autoAnalyze {
                        Label("Analyse wird nach dem Sichern aktualisiert", systemImage: "sparkles")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var staleAnalysisBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .foregroundStyle(.orange)
            Text("Der Text wurde nach der Analyse geändert.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Neu analysieren") { reanalyze() }
                .buttonStyle(.bordered)
                .disabled(entry.analysisStatus == .running)
        }
        .padding(12)
        .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Analysis (read only)

    @ViewBuilder
    private func analysisSection(_ analysis: EntryAnalysis) -> some View {
        if !analysis.summary.isEmpty {
            SectionCard(title: "Zusammenfassung", systemImage: "text.line.first.and.arrowtriangle.forward") {
                Text(analysis.summary)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }

        SectionCard(title: "Erkannte Signale", systemImage: "brain") {
            VStack(alignment: .leading, spacing: 14) {
                emotionsBlock(analysis.emotions)
                signal("Themen", analysis.topics, image: "tag", tint: .blue)
                signal("Personen", analysis.people, image: "person", tint: .purple)
                signal("Orte", analysis.places, image: "mappin.and.ellipse", tint: .brown)
                signal("Ziele", analysis.goals, image: "target", tint: .mint)
                if analysis.emotions.isEmpty && analysis.topics.isEmpty && analysis.people.isEmpty
                    && analysis.places.isEmpty && analysis.goals.isEmpty {
                    Text("Keine Signale erkannt.")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                }
            }
        }

        deeperSignals(analysis)

        if !analysis.keyInsights.isEmpty {
            SectionCard(title: "Erkenntnisse", systemImage: "sparkle") {
                ForEach(analysis.keyInsights, id: \.self) { insight in
                    Label(insight, systemImage: "checkmark.circle")
                        .font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }

        if !analysis.ideas.isEmpty {
            SectionCard(title: "Ideen", systemImage: "lightbulb") {
                ForEach(analysis.ideas, id: \.self) { idea in
                    Label(idea, systemImage: "lightbulb")
                        .font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }

        if !analysis.tasks.isEmpty {
            SectionCard(title: "Vorhaben", systemImage: "checklist") {
                ForEach(analysis.tasks, id: \.self) { task in
                    Label(task, systemImage: "circle")
                        .font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }

        if !analysis.patterns.isEmpty {
            SectionCard(title: "Muster & Trends", systemImage: "waveform.path.ecg") {
                ForEach(analysis.patterns, id: \.self) { pattern in
                    Label(pattern, systemImage: "arrow.triangle.branch")
                        .font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }

        if !analysis.comparisonWithLastWeek.isEmpty {
            SectionCard(title: "Vergleich: letzte 7 Tage", systemImage: "calendar.badge.clock") {
                Text(analysis.comparisonWithLastWeek)
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Critical reflection

    /// Generate critically reflective follow-up questions grounded in this entry;
    /// each can be saved to the collection or used to start a new entry.
    private var reflectionCard: some View {
        SectionCard(title: "Kritische Reflexion", systemImage: "questionmark.bubble") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Lass dir aus diesem Eintrag Fragen erzeugen, die zu ehrlicher, "
                     + "kritischer Selbstreflexion anregen.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                ForEach(reflectionQuestions, id: \.self) { question in
                    reflectionRow(question)
                }

                if let reflectionMessage {
                    Text(reflectionMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button {
                    generateReflection()
                } label: {
                    if isGeneratingReflection {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Erzeuge Fragen …")
                        }
                    } else {
                        Label(reflectionQuestions.isEmpty ? "Fragen generieren" : "Neue Fragen",
                              systemImage: "sparkles")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isGeneratingReflection)
            }
        }
    }

    private func reflectionRow(_ question: String) -> some View {
        let saved = savedQuestions.contains(question)
        return VStack(alignment: .leading, spacing: 8) {
            Text(question)
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                Button {
                    onStartWriting(question)
                } label: {
                    Label("Schreiben", systemImage: "square.and.pencil")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    saveReflectionToLibrary(question)
                } label: {
                    Label(saved ? "In Sammlung" : "In Sammlung sichern",
                          systemImage: saved ? "checkmark.circle.fill" : "plus.circle")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(saved)
                .tint(saved ? .green : .accentColor)

                Spacer()
            }
        }
        .padding(10)
        .background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.accentColor.opacity(0.12)))
    }

    private var analysisPlaceholder: some View {
        SectionCard(title: "KI-Analyse", systemImage: "brain") {
            switch entry.analysisStatus {
            case .running:
                Label("Analyse läuft …", systemImage: "arrow.triangle.2.circlepath")
                    .foregroundStyle(.secondary)
            case .pending, .notStarted:
                VStack(alignment: .leading, spacing: 10) {
                    Text("Für diesen Eintrag liegt noch keine Analyse vor.")
                        .foregroundStyle(.secondary)
                    Text("Starte sie, sobald dein lokales Ollama-Modell läuft.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Button("Jetzt analysieren") { reanalyze() }
                        .buttonStyle(.borderedProminent)
                }
            case .failed:
                VStack(alignment: .leading, spacing: 10) {
                    Label("Analyse fehlgeschlagen", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                    if let message = analysis.lastErrorMessage {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Button("Erneut versuchen") { reanalyze() }
                        .buttonStyle(.bordered)
                }
            case .completed:
                EmptyView()
            }
        }
    }

    /// The deeper reflective layer (beliefs, needs, triggers, energy, strategies),
    /// shown only when the second analysis pass found something.
    @ViewBuilder
    private func deeperSignals(_ analysis: EntryAnalysis) -> some View {
        let hasAny = !analysis.beliefs.isEmpty || !analysis.needs.isEmpty || !analysis.triggers.isEmpty
            || !analysis.energyGivers.isEmpty || !analysis.energyDrainers.isEmpty
            || !analysis.strategies.isEmpty
        if hasAny {
            SectionCard(title: "Tiefere Signale", systemImage: "brain.head.profile") {
                VStack(alignment: .leading, spacing: 14) {
                    signal("Glaubenssätze", analysis.beliefs, image: "quote.bubble", tint: .purple)
                    signal("Bedürfnisse", analysis.needs, image: "leaf", tint: .teal)
                    signal("Trigger", analysis.triggers, image: "bolt", tint: .orange)
                    signal("Gibt Energie", analysis.energyGivers, image: "arrow.up.circle", tint: .green)
                    signal("Kostet Energie", analysis.energyDrainers, image: "arrow.down.circle", tint: .orange)
                    if !analysis.strategies.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Strategien (Fehler → Lösung)")
                                .font(.subheadline.weight(.medium))
                            ForEach(analysis.strategies) { note in
                                VStack(alignment: .leading, spacing: 2) {
                                    if !note.problem.isEmpty {
                                        Label(note.problem, systemImage: "exclamationmark.triangle")
                                            .font(.callout).foregroundStyle(.orange)
                                    }
                                    if !note.solution.isEmpty {
                                        Label(note.solution, systemImage: "checkmark.circle")
                                            .font(.callout).foregroundStyle(.green)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func signal(_ title: String, _ items: [String], image: String, tint: Color) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                ChipsView(items: items, systemImage: image, tint: tint)
            }
        }
    }

    /// Emotions rendered as chips with their intensity (0–10); a stronger tint
    /// signals higher intensity.
    @ViewBuilder
    private func emotionsBlock(_ emotions: [EmotionScore]) -> some View {
        if !emotions.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Gefühle")
                    .font(.subheadline.weight(.medium))
                FlowLayout(spacing: 6) {
                    ForEach(emotions) { emotion in
                        HStack(spacing: 5) {
                            Image(systemName: "heart.fill").font(.caption2)
                            Text(emotion.name).font(.callout)
                            Text("\(emotion.intensity)")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(.pink.opacity(0.28), in: Capsule())
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.pink.opacity(0.12 + Double(emotion.intensity) / 10 * 0.18), in: Capsule())
                        .foregroundStyle(.pink)
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func beginEditing() {
        draftTitle = entry.title
        draftDate = entry.date
        draftText = entry.text
        isEditing = true
    }

    private func saveEdits() {
        guard canSaveEdits else { return }
        let textChanged = draftText != entry.text

        entry.title = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.date = draftDate
        entry.text = draftText
        entry.refreshWordCount()
        entry.updatedAt = .now
        try? context.save()

        isEditing = false

        // The old analysis no longer matches the edited text: refresh it
        // best-effort when auto-analyse is on (degrades to "pending" if offline).
        if textChanged && settings.autoAnalyze {
            reanalyze()
        }
    }

    private func reanalyze() {
        let captured = entry
        let currentSettings = settings
        Task { @MainActor in await analysis.analyze(captured, settings: currentSettings) }
    }

    private func generateReflection() {
        isGeneratingReflection = true
        reflectionMessage = nil
        let captured = entry
        let currentSettings = settings
        Task { @MainActor in
            let questions = await analysis.reflectionPrompts(for: captured, count: 4, settings: currentSettings)
            reflectionQuestions = questions
            if questions.isEmpty {
                reflectionMessage = "Keine Fragen erhalten. Läuft dein lokales Ollama-Modell?"
            }
            isGeneratingReflection = false
        }
    }

    private func saveReflectionToLibrary(_ question: String) {
        context.insert(JournalPrompt(text: question, category: "Kritische Reflexion", isAIGenerated: true))
        try? context.save()
        savedQuestions.insert(question)
    }

    private func formattedDuration(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let secs = seconds % 60
        if minutes > 0 { return "\(minutes) min \(secs) s" }
        return "\(secs) s"
    }
}
