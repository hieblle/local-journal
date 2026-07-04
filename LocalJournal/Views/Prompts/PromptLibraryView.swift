import SwiftUI
import SwiftData

/// The journal prompt library: a *customizable collection* of reflection
/// questions you can favourite, edit, archive and — most importantly — start a
/// new entry from. These are user-facing writing impulses, not LLM templates.
struct PromptLibraryView: View {
    /// Start a new entry preloaded with this reflection question.
    var onStartWriting: (String) -> Void = { _ in }

    @Environment(\.modelContext) private var context
    @Environment(AnalysisService.self) private var analysis

    @Query(sort: [SortDescriptor(\JournalPrompt.category), SortDescriptor(\JournalPrompt.createdAt, order: .reverse)])
    private var prompts: [JournalPrompt]
    @Query private var settingsList: [AppSettings]

    @State private var showArchived = false
    @State private var onlyFavorites = false
    @State private var isGenerating = false
    @State private var generationMessage: String?

    // One sheet for both adding and editing.
    @State private var showEditor = false
    @State private var editingPrompt: JournalPrompt?

    private var settings: AppSettings { settingsList.first ?? AppSettings() }

    private var visiblePrompts: [JournalPrompt] {
        prompts.filter { prompt in
            (showArchived || !prompt.isArchived) && (!onlyFavorites || prompt.isFavorite)
        }
    }

    private var grouped: [(key: String, value: [JournalPrompt])] {
        Dictionary(grouping: visiblePrompts, by: { $0.category })
            .map { (key: $0.key, value: sortedForDisplay($0.value)) }
            .sorted { $0.key < $1.key }
    }

    /// Favourites first, then most recent.
    private func sortedForDisplay(_ items: [JournalPrompt]) -> [JournalPrompt] {
        items.sorted { lhs, rhs in
            if lhs.isFavorite != rhs.isFavorite { return lhs.isFavorite }
            return lhs.createdAt > rhs.createdAt
        }
    }

    var body: some View {
        List {
            introSection

            if let generationMessage {
                Section {
                    Label(generationMessage, systemImage: "info.circle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            if visiblePrompts.isEmpty {
                EmptyHint(title: onlyFavorites ? "Keine Favoriten" : "Keine Prompts",
                          systemImage: "lightbulb",
                          message: onlyFavorites
                            ? "Markiere Prompts mit dem Stern, um sie hier zu sammeln."
                            : "Füge eigene Reflexionsfragen hinzu oder lass dir welche von Ollama vorschlagen.")
            }

            ForEach(grouped, id: \.key) { group in
                Section(group.key) {
                    ForEach(group.value) { prompt in
                        PromptRow(prompt: prompt,
                                  onStart: { onStartWriting(prompt.text) },
                                  onEdit: { editingPrompt = prompt; showEditor = true },
                                  onToggleFavorite: { toggleFavorite(prompt) },
                                  onToggleArchive: { prompt.isArchived.toggle(); save() },
                                  onDelete: { context.delete(prompt); save() })
                            .swipeActions(edge: .leading) {
                                Button {
                                    toggleFavorite(prompt)
                                } label: {
                                    Label("Favorit", systemImage: "star")
                                }
                                .tint(.yellow)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    context.delete(prompt); save()
                                } label: {
                                    Label("Löschen", systemImage: "trash")
                                }
                                Button {
                                    prompt.isArchived.toggle(); save()
                                } label: {
                                    Label(prompt.isArchived ? "Aktivieren" : "Archivieren",
                                          systemImage: prompt.isArchived ? "tray.and.arrow.up" : "archivebox")
                                }
                                .tint(.orange)
                            }
                    }
                }
            }
        }
        .navigationTitle("Prompts")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Toggle(isOn: $onlyFavorites) {
                    Label("Favoriten", systemImage: onlyFavorites ? "star.fill" : "star")
                }
                Toggle(isOn: $showArchived) {
                    Label("Archiv", systemImage: "archivebox")
                }
                Button {
                    Task { @MainActor in await generate() }
                } label: {
                    if isGenerating {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("KI-Vorschläge", systemImage: "sparkles")
                    }
                }
                .disabled(isGenerating)
                Button {
                    editingPrompt = nil
                    showEditor = true
                } label: {
                    Label("Hinzufügen", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showEditor) {
            PromptEditorSheet(
                initialText: editingPrompt?.text ?? "",
                initialCategory: editingPrompt?.category ?? "Allgemein",
                isEditing: editingPrompt != nil
            ) { text, category in
                if let prompt = editingPrompt {
                    prompt.text = text
                    prompt.category = category
                } else {
                    context.insert(JournalPrompt(text: text, category: category, isUserCreated: true))
                }
                save()
            }
        }
    }

    // MARK: - Intro

    private var introSection: some View {
        Section {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "lightbulb.fill")
                    .foregroundStyle(.yellow)
                Text("Deine Sammlung an Reflexionsfragen. Markiere Favoriten ⭐︎, "
                     + "bearbeite sie oder starte direkt einen Eintrag damit.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - Actions

    private func toggleFavorite(_ prompt: JournalPrompt) {
        prompt.isFavorite.toggle()
        save()
    }

    private func save() {
        try? context.save()
    }

    private func generate() async {
        isGenerating = true
        generationMessage = nil
        let suggestions = await analysis.generateJournalPrompts(count: 5, settings: settings)
        if suggestions.isEmpty {
            generationMessage = "Keine Vorschläge erhalten. Läuft Ollama und gibt es schon analysierte Einträge?"
        } else {
            for text in suggestions {
                context.insert(JournalPrompt(text: text, category: "Kritische Reflexion", isAIGenerated: true))
            }
            save()
            generationMessage = "\(suggestions.count) neue Fragen aus deinen Einträgen hinzugefügt."
        }
        isGenerating = false
    }
}

/// A single prompt in the library, with inline actions (start, favourite, more).
private struct PromptRow: View {
    @Bindable var prompt: JournalPrompt
    var onStart: () -> Void
    var onEdit: () -> Void
    var onToggleFavorite: () -> Void
    var onToggleArchive: () -> Void
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggleFavorite) {
                Image(systemName: prompt.isFavorite ? "star.fill" : "star")
                    .foregroundStyle(prompt.isFavorite ? .yellow : .secondary)
            }
            .buttonStyle(.plain)
            .help(prompt.isFavorite ? "Favorit entfernen" : "Als Favorit markieren")

            VStack(alignment: .leading, spacing: 3) {
                Text(prompt.text)
                    .font(.body)
                    .foregroundStyle(prompt.isArchived ? .secondary : .primary)
                HStack(spacing: 6) {
                    if prompt.isAIGenerated {
                        badge("KI", systemImage: "sparkles", tint: .purple)
                    }
                    if prompt.isUserCreated {
                        badge("Eigen", systemImage: "pencil", tint: .blue)
                    }
                    if prompt.isArchived {
                        badge("Archiviert", systemImage: "archivebox", tint: .orange)
                    }
                }
            }

            Spacer(minLength: 8)

            Button(action: onStart) {
                Label("Schreiben", systemImage: "square.and.pencil")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Eintrag mit dieser Frage starten")

            Menu {
                Button { onEdit() } label: { Label("Bearbeiten", systemImage: "pencil") }
                Button { onToggleFavorite() } label: {
                    Label(prompt.isFavorite ? "Favorit entfernen" : "Favorit",
                          systemImage: prompt.isFavorite ? "star.slash" : "star")
                }
                Button { onToggleArchive() } label: {
                    Label(prompt.isArchived ? "Aktivieren" : "Archivieren",
                          systemImage: prompt.isArchived ? "tray.and.arrow.up" : "archivebox")
                }
                Divider()
                Button(role: .destructive) { onDelete() } label: {
                    Label("Löschen", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }

    private func badge(_ text: String, systemImage: String, tint: Color) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption2)
            .foregroundStyle(tint)
    }
}

/// Sheet for adding *or* editing a prompt.
private struct PromptEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let initialText: String
    let initialCategory: String
    let isEditing: Bool
    var onSave: (String, String) -> Void

    @State private var text: String
    @State private var category: String

    private let categories = ["Allgemein", "Gefühle", "Muster", "Vermeidung",
                              "Perspektive", "Beziehungen", "Energie & Fokus",
                              "Kritische Reflexion"]

    init(initialText: String,
         initialCategory: String,
         isEditing: Bool,
         onSave: @escaping (String, String) -> Void) {
        self.initialText = initialText
        self.initialCategory = initialCategory
        self.isEditing = isEditing
        self.onSave = onSave
        _text = State(initialValue: initialText)
        _category = State(initialValue: initialCategory)
    }

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isEditing ? "Prompt bearbeiten" : "Neuer Prompt")
                .font(.title3.weight(.semibold))

            VStack(alignment: .leading, spacing: 6) {
                Text("Reflexionsfrage")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("z. B. Was hat mich heute überrascht?", text: $text, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...5)
            }

            Picker("Kategorie", selection: $category) {
                ForEach(categoryOptions, id: \.self) { Text($0).tag($0) }
            }

            HStack {
                Spacer()
                Button("Abbrechen") { dismiss() }
                Button(isEditing ? "Sichern" : "Hinzufügen") {
                    guard !trimmed.isEmpty else { return }
                    onSave(trimmed, category)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(trimmed.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    /// Ensure the current category is always selectable even if it's custom.
    private var categoryOptions: [String] {
        categories.contains(category) ? categories : categories + [category]
    }
}
