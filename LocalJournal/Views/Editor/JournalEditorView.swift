import SwiftUI
import SwiftData

/// Write a new journal entry. The centre is a calm, Apple-Journal-like writing
/// surface; a collapsible **Einblicke** panel sits on the left and a collapsible
/// **KI-Begleiter** chat on the right. On save the entry is persisted locally
/// first; AI analysis is then kicked off best-effort.
struct JournalEditorView: View {
    /// Optional reflection prompt to preload (handed over from the Prompts page).
    var initialPrompt: String? = nil
    /// Called once the initial prompt has been consumed, so the parent can clear it.
    var onConsumePrompt: () -> Void = {}
    /// Optional template to preload (fills title + body text).
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
    @State private var selfMood = 0
    @State private var activePrompt: String?

    @State private var timerEnabled = false
    @State private var timer = WritingTimer()

    // Panels + tools
    @State private var showChat = false
    @State private var showFormatting = false
    @State private var editor = MarkdownEditingController()
    @State private var chat = CompanionChat()

    @State private var didConfigureDefaults = false
    @State private var toast: Toast?

    private var settings: AppSettings { settingsList.first ?? AppSettings() }
    private var availablePrompts: [JournalPrompt] { prompts.filter { !$0.isArchived } }
    private var wordCount: Int { JournalEntry.countWords(in: text) }
    private var canSave: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(spacing: 0) {
            centerColumn

            if showChat {
                Divider()
                CompanionChatPanel(chat: chat, entryTitle: title, entryText: text, settings: settings) {
                    withAnimation(.snappy) { showChat = false }
                }
                .frame(width: 344)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .navigationTitle("Neuer Eintrag")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    withAnimation(.snappy) { showChat.toggle() }
                } label: {
                    Image(systemName: "sparkles")
                        .foregroundStyle(showChat ? Color.sage : Color.secondary)
                }
                .help("KI-Begleiter ein-/ausblenden")

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
        .overlay(alignment: .bottom) { toastView }
    }

    // MARK: - Centre column (the writing surface)

    private var centerColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            toolRow
            starterRow

            if showFormatting {
                FormattingBar(controller: editor)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if let activePrompt {
                promptBanner(activePrompt)
            }
            if timerEnabled {
                TimerBar(timer: timer)
            }

            titleField
            MoodCheckInRow(selfMood: $selfMood)
            editorSurface
            footer
        }
        .padding(24)
        .frame(maxWidth: 820, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.appBackground)
    }

    private var toolRow: some View {
        HStack(spacing: 10) {
            DateFieldButton(date: $date)
            Spacer()
            toolButton("textformat", active: showFormatting, help: "Textformatierung") {
                withAnimation(.snappy) { showFormatting.toggle() }
            }
            toolButton("mic", help: "Sprachaufnahme (bald)") {
                showToast("Sprachaufnahme & Transkription kommen bald.", icon: "mic", tint: .secondary)
            }
            toolButton("timer", active: timerEnabled, help: "Schreib-Timer") { toggleTimer() }
        }
    }

    private var titleField: some View {
        TextField("Titel", text: $title)
            .textFieldStyle(.plain)
            .font(.system(size: 26, weight: .semibold, design: .serif))
    }

    private var editorSurface: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text("Jetzt schreiben …")
                    .font(.system(size: 15))
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 11)
                    .padding(.top, 10)
                    .allowsHitTesting(false)
            }
            MarkdownEditor(text: $text, controller: editor)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Label("\(wordCount) Wörter", systemImage: "text.word.spacing")
                .font(.caption)
                .foregroundStyle(.secondary)
            if settings.autoAnalyze {
                Label("KI-Analyse nach dem Speichern", systemImage: "sparkles")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
    }

    // MARK: - Starter buttons (reflection question + template)

    private var starterRow: some View {
        HStack(spacing: 10) {
            Menu {
                promptMenuContent
            } label: {
                starterLabel("Reflexionsfrage", systemImage: "lightbulb", tint: .yellow)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

            Menu {
                if templates.isEmpty {
                    Text("Keine Vorlagen vorhanden")
                } else {
                    ForEach(templates) { template in
                        Button {
                            applyTemplate(template)
                        } label: {
                            Label(template.name, systemImage: template.cadence.systemImage)
                        }
                    }
                }
            } label: {
                starterLabel("Vorlage", systemImage: "doc.text", tint: .sage)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

            Spacer()
        }
    }

    private func starterLabel(_ title: String, systemImage: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage).foregroundStyle(tint)
            Text(title)
            Image(systemName: "chevron.down").font(.caption2).foregroundStyle(.tertiary)
        }
        .font(.callout)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.cardSurface, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.secondary.opacity(0.18)))
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

    /// Fill the editor from a template (title if empty, body appended if there is
    /// already text so nothing is lost).
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

    // MARK: - Small tool button + toast

    private func toolButton(_ symbol: String, active: Bool = false,
                            help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(active ? Color.sage : Color.secondary)
                .frame(width: 32, height: 28)
                .background(active ? Color.sage.opacity(0.15) : Color.clear,
                           in: RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private struct Toast {
        var text: String
        var icon: String
        var tint: Color
    }

    @ViewBuilder
    private var toastView: some View {
        if let toast {
            Label(toast.text, systemImage: toast.icon)
                .font(.callout.weight(.medium))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(toast.tint.opacity(0.35)))
                .padding(.bottom, 26)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func showToast(_ text: String, icon: String, tint: Color) {
        withAnimation { toast = Toast(text: text, icon: icon, tint: tint) }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.2))
            withAnimation { toast = nil }
        }
    }

    // MARK: - Actions

    private func toggleTimer() {
        withAnimation(.snappy) { timerEnabled.toggle() }
        if timerEnabled { timer.reset() } else { timer.stop() }
    }

    private func configureDefaultsIfNeeded() {
        guard !didConfigureDefaults else { return }
        didConfigureDefaults = true
        timerEnabled = settings.timerEnabledByDefault
        timer.durationMinutes = settings.timerDurationMinutes
        timer.reset()

        if let initialTemplate {
            applyTemplate(initialTemplate)
            onConsumeTemplate()
        }
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
        entry.selfMood = selfMood
        // Persist locally FIRST so nothing is lost if analysis can't run.
        entry.analysisStatus = settings.autoAnalyze ? .pending : .notStarted
        context.insert(entry)
        try? context.save()

        // Mirror to Markdown right away (analysis, if any, rewrites it later).
        MarkdownMirror.writeEntry(entry, settings: settings)

        if settings.autoAnalyze {
            let captured = entry
            let currentSettings = settings
            Task { @MainActor in await analysis.analyze(captured, settings: currentSettings) }
        }

        resetEditor()
        showToast("Eintrag gespeichert", icon: "checkmark.circle.fill", tint: .green)
    }

    private func resetEditor() {
        title = ""
        text = ""
        date = .now
        selfMood = 0
        activePrompt = nil
        chat.messages.removeAll()
        chat.notice = nil
        timer.reset()
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
