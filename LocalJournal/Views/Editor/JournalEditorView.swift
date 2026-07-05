import SwiftUI
import SwiftData

/// Write a new journal entry. On save the entry is persisted locally first;
/// AI analysis is then kicked off best-effort (and degrades to "pending" when
/// Ollama is unavailable).
struct JournalEditorView: View {
    /// Optional reflection prompt to preload (handed over from the Prompts page).
    var initialPrompt: String? = nil
    /// Called once the initial prompt has been consumed, so the parent can clear it.
    var onConsumePrompt: () -> Void = {}
    /// Optional template to preload (fills title + a scaffold of hints/questions).
    var initialTemplate: EntryTemplate? = nil
    /// Called once the initial template has been consumed.
    var onConsumeTemplate: () -> Void = {}

    @Environment(\.modelContext) private var context
    @Environment(AnalysisService.self) private var analysis

    @Query(sort: \JournalPrompt.createdAt, order: .reverse) private var prompts: [JournalPrompt]
    @Query(sort: [SortDescriptor(\EntryTemplate.sortIndex), SortDescriptor(\EntryTemplate.createdAt)])
    private var templates: [EntryTemplate]
    @Query private var settingsList: [AppSettings]

    @State private var title = ""
    @State private var date: Date = .now
    @State private var text = ""
    @State private var activePrompt: String?

    @State private var timerEnabled = false
    @State private var timer = WritingTimer()

    @State private var didConfigureDefaults = false
    @State private var showSavedToast = false

    private var settings: AppSettings { settingsList.first ?? AppSettings() }
    private var availablePrompts: [JournalPrompt] { prompts.filter { !$0.isArchived } }
    private var wordCount: Int { JournalEntry.countWords(in: text) }
    private var canSave: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    metaFields

                    if timerEnabled {
                        TimerBar(timer: timer)
                    }

                    promptArea

                    TextEditorWithPlaceholder(text: $text,
                                              placeholder: "Schreib einfach los …",
                                              minHeight: 320)
                }
                .padding(20)
            }

            footer
        }
        .navigationTitle("Neuer Eintrag")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                templateMenu
                promptMenu
                Button {
                    save()
                } label: {
                    Label("Speichern", systemImage: "checkmark.circle.fill")
                }
                .disabled(!canSave)
                .keyboardShortcut("s", modifiers: .command)
            }
        }
        .onAppear(perform: configureDefaultsIfNeeded)
        .onDisappear { timer.stop() }
        .overlay(alignment: .bottom) {
            if showSavedToast {
                savedToast
                    .padding(.bottom, 70)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    // MARK: - Meta fields

    private var metaFields: some View {
        VStack(spacing: 12) {
            TextField("Titel (optional)", text: $title)
                .textFieldStyle(.plain)
                .font(.title2.weight(.semibold))

            HStack {
                DateFieldButton(date: $date)
                Spacer()
                Toggle(isOn: $timerEnabled.animation()) {
                    Label("Timer", systemImage: "timer")
                }
                .toggleStyle(.switch)
                .onChange(of: timerEnabled) { _, enabled in
                    if enabled { timer.reset() } else { timer.stop() }
                }
            }
        }
    }

    // MARK: - Prompt picker

    /// Either the active reflection question (as a banner) or an inline
    /// invitation to start writing from one.
    @ViewBuilder
    private var promptArea: some View {
        if let activePrompt {
            promptBanner(activePrompt)
        } else if !availablePrompts.isEmpty {
            promptChooserInline
        }
    }

    private var promptChooserInline: some View {
        Menu {
            promptMenuContent
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "lightbulb")
                    .foregroundStyle(.yellow)
                Text("Mit einer Reflexionsfrage starten")
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.yellow.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.yellow.opacity(0.20)))
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var promptMenu: some View {
        Menu {
            promptMenuContent
        } label: {
            Label("Impuls wählen", systemImage: "lightbulb")
        }
    }

    @ViewBuilder
    private var templateMenu: some View {
        if !templates.isEmpty {
            Menu {
                ForEach(templates) { template in
                    Button {
                        applyTemplate(template)
                    } label: {
                        Label(template.name, systemImage: template.cadence.systemImage)
                    }
                }
            } label: {
                Label("Vorlage", systemImage: "doc.text")
            }
        }
    }

    /// Fill the editor from a template. If the entry is still empty the scaffold
    /// replaces it; otherwise it is appended so nothing is lost.
    private func applyTemplate(_ template: EntryTemplate) {
        if title.isEmpty { title = template.name }
        let scaffold = template.scaffoldText()
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            text = scaffold
        } else {
            text += "\n\n" + scaffold
        }
        activePrompt = nil
    }

    @ViewBuilder
    private var promptMenuContent: some View {
        if availablePrompts.isEmpty {
            Text("Keine Reflexionsfragen vorhanden")
        } else {
            ForEach(groupedPrompts, id: \.key) { group in
                Section(group.key) {
                    ForEach(group.value) { prompt in
                        Button(prompt.text) { applyPrompt(prompt) }
                    }
                }
            }
        }
    }

    private var groupedPrompts: [(key: String, value: [JournalPrompt])] {
        // Favourites first within the flat list, then grouped by category.
        Dictionary(grouping: availablePrompts, by: { $0.category })
            .map { ($0.key, $0.value.sorted { ($0.isFavorite ? 0 : 1) < ($1.isFavorite ? 0 : 1) }) }
            .sorted { $0.key < $1.key }
    }

    private func promptBanner(_ prompt: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "quote.opening")
                .foregroundStyle(.tertiary)
            Text(prompt)
                .font(.callout)
                .italic()
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                activePrompt = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("Reflexionsfrage entfernen")
        }
        .padding(12)
        .background(.yellow.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private func applyPrompt(_ prompt: JournalPrompt) {
        activePrompt = prompt.text
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Label("\(wordCount) Wörter", systemImage: "text.word.spacing")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if settings.autoAnalyze {
                Label("KI-Analyse nach dem Speichern", systemImage: "sparkles")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button("Speichern") { save() }
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private var savedToast: some View {
        Label("Eintrag gespeichert", systemImage: "checkmark.circle.fill")
            .font(.callout.weight(.medium))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.green.opacity(0.9), in: Capsule())
            .foregroundStyle(.white)
            .shadow(radius: 8, y: 4)
    }

    // MARK: - Actions

    private func configureDefaultsIfNeeded() {
        guard !didConfigureDefaults else { return }
        didConfigureDefaults = true
        timerEnabled = settings.timerEnabledByDefault
        timer.durationMinutes = settings.timerDurationMinutes
        timer.reset()

        // Preload a template (title + scaffold) handed over from the library.
        if let initialTemplate {
            applyTemplate(initialTemplate)
            onConsumeTemplate()
        }

        // Preload a reflection prompt handed over from the Reflexionsfragen page.
        if let initialPrompt, !initialPrompt.isEmpty {
            activePrompt = initialPrompt
            onConsumePrompt()
        }
    }

    private func save() {
        guard canSave else { return }
        timer.pause()

        let entry = JournalEntry(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            date: date,
            text: text,
            writingSeconds: timer.elapsedSeconds
        )
        // Persist locally FIRST so nothing is lost if analysis can't run.
        entry.analysisStatus = settings.autoAnalyze ? .pending : .notStarted
        context.insert(entry)
        try? context.save()

        if settings.autoAnalyze {
            let captured = entry
            let currentSettings = settings
            // Unstructured, main-actor Task: survives navigating away from the editor.
            Task { @MainActor in await analysis.analyze(captured, settings: currentSettings) }
        }

        resetEditor()
        flashSavedToast()
    }

    private func resetEditor() {
        title = ""
        text = ""
        date = .now
        activePrompt = nil
        timer.reset()
    }

    private func flashSavedToast() {
        withAnimation { showSavedToast = true }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            withAnimation { showSavedToast = false }
        }
    }
}

/// Compact timer controls shown above the editor when the timer is enabled.
private struct TimerBar: View {
    @Bindable var timer: WritingTimer

    var body: some View {
        HStack(spacing: 14) {
            Button {
                timer.toggle()
            } label: {
                Image(systemName: timer.isRunning ? "pause.circle.fill" : "play.circle.fill")
                    .font(.title2)
            }
            .buttonStyle(.plain)

            Text(timer.formattedRemaining)
                .font(.system(.title3, design: .monospaced).weight(.medium))
                .foregroundStyle(timer.finished ? .green : .primary)
                .frame(width: 72, alignment: .leading)

            ProgressView(value: timer.progress)
                .tint(timer.finished ? .green : .accentColor)

            Stepper(value: $timer.durationMinutes, in: 1...120) {
                Text("\(timer.durationMinutes) min")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .disabled(timer.isRunning)
            .fixedSize()

            Button {
                timer.reset()
            } label: {
                Image(systemName: "arrow.counterclockwise")
            }
            .buttonStyle(.plain)
            .help("Timer zurücksetzen")
        }
        .padding(12)
        .background(Color.cardSurface, in: RoundedRectangle(cornerRadius: 10))
    }
}
