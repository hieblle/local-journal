import SwiftUI
import SwiftData

/// The journal prompt library: browse, add, archive and AI-generate writing
/// impulses. These are user-facing reflection questions, not LLM templates.
struct PromptLibraryView: View {
    @Environment(\.modelContext) private var context
    @Environment(AnalysisService.self) private var analysis

    @Query(sort: [SortDescriptor(\JournalPrompt.category), SortDescriptor(\JournalPrompt.createdAt, order: .reverse)])
    private var prompts: [JournalPrompt]
    @Query private var settingsList: [AppSettings]

    @State private var showArchived = false
    @State private var showAddSheet = false
    @State private var isGenerating = false
    @State private var generationMessage: String?

    private var settings: AppSettings { settingsList.first ?? AppSettings() }

    private var visiblePrompts: [JournalPrompt] {
        showArchived ? prompts : prompts.filter { !$0.isArchived }
    }

    private var grouped: [(key: String, value: [JournalPrompt])] {
        Dictionary(grouping: visiblePrompts, by: { $0.category })
            .map { ($0.key, $0.value) }
            .sorted { $0.key < $1.key }
    }

    var body: some View {
        List {
            if let generationMessage {
                Section {
                    Label(generationMessage, systemImage: "info.circle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            if visiblePrompts.isEmpty {
                EmptyHint(title: "Keine Prompts",
                          systemImage: "lightbulb",
                          message: "Füge eigene Reflexionsfragen hinzu oder lass dir welche von Ollama vorschlagen.")
            }

            ForEach(grouped, id: \.key) { group in
                Section(group.key) {
                    ForEach(group.value) { prompt in
                        PromptRow(prompt: prompt)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    context.delete(prompt)
                                } label: {
                                    Label("Löschen", systemImage: "trash")
                                }
                                Button {
                                    prompt.isArchived.toggle()
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
                    showAddSheet = true
                } label: {
                    Label("Hinzufügen", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddPromptSheet { text, category in
                let prompt = JournalPrompt(text: text, category: category, isUserCreated: true)
                context.insert(prompt)
                try? context.save()
            }
        }
    }

    private func generate() async {
        isGenerating = true
        generationMessage = nil
        let suggestions = await analysis.generateJournalPrompts(count: 5, settings: settings)
        if suggestions.isEmpty {
            generationMessage = "Keine Vorschläge erhalten. Läuft Ollama und gibt es schon analysierte Einträge?"
        } else {
            for text in suggestions {
                context.insert(JournalPrompt(text: text, category: "KI-Vorschläge", isAIGenerated: true))
            }
            try? context.save()
            generationMessage = "\(suggestions.count) neue Vorschläge hinzugefügt."
        }
        isGenerating = false
    }
}

private struct PromptRow: View {
    @Bindable var prompt: JournalPrompt

    var body: some View {
        HStack(spacing: 10) {
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
            Spacer()
        }
        .padding(.vertical, 2)
    }

    private func badge(_ text: String, systemImage: String, tint: Color) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption2)
            .foregroundStyle(tint)
    }
}

/// Sheet for manually adding a prompt.
private struct AddPromptSheet: View {
    @Environment(\.dismiss) private var dismiss
    var onAdd: (String, String) -> Void

    @State private var text = ""
    @State private var category = "Allgemein"

    private let categories = ["Allgemein", "Gefühle", "Muster", "Vermeidung",
                              "Perspektive", "Beziehungen", "Energie & Fokus"]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Neuer Prompt")
                .font(.title3.weight(.semibold))

            VStack(alignment: .leading, spacing: 6) {
                Text("Reflexionsfrage")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("z. B. Was hat mich heute überrascht?", text: $text, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)
            }

            Picker("Kategorie", selection: $category) {
                ForEach(categories, id: \.self) { Text($0).tag($0) }
            }

            HStack {
                Spacer()
                Button("Abbrechen") { dismiss() }
                Button("Hinzufügen") {
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    onAdd(trimmed, category)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}
