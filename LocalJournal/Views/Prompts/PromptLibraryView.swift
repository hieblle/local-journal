import SwiftUI
import SwiftData

private enum LibraryTab: String, CaseIterable, Identifiable {
    case fragen, vorlagen
    var id: String { rawValue }
    var label: String { self == .fragen ? "Fragen" : "Vorlagen" }
}

/// The writing-starter library, split into two tabs:
///  - **Fragen**: single reflection questions (favourite, edit, archive, start).
///  - **Vorlagen**: self-made entry templates — multi-question scaffolds with a
///    cadence, to start a structured entry (daily / weekly / yearly …).
struct PromptLibraryView: View {
    /// Start a new entry preloaded with this reflection question.
    var onStartWriting: (String) -> Void = { _ in }
    /// Start a new entry preloaded from a template.
    var onStartTemplate: (EntryTemplate) -> Void = { _ in }

    @Environment(\.modelContext) private var context
    @Environment(AnalysisService.self) private var analysis

    @Query(sort: [SortDescriptor(\JournalPrompt.category), SortDescriptor(\JournalPrompt.createdAt, order: .reverse)])
    private var prompts: [JournalPrompt]
    @Query(sort: [SortDescriptor(\EntryTemplate.sortIndex), SortDescriptor(\EntryTemplate.createdAt)])
    private var templates: [EntryTemplate]
    @Query private var settingsList: [AppSettings]

    @State private var tab: LibraryTab = .fragen
    @State private var showArchived = false
    @State private var onlyFavorites = false
    @State private var isGenerating = false
    @State private var generationMessage: String?

    // Prompt add/edit sheet.
    @State private var showEditor = false
    @State private var editingPrompt: JournalPrompt?

    // Template add/edit sheet.
    @State private var showTemplateEditor = false
    @State private var editingTemplate: EntryTemplate?

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

    private func sortedForDisplay(_ items: [JournalPrompt]) -> [JournalPrompt] {
        items.sorted { lhs, rhs in
            if lhs.isFavorite != rhs.isFavorite { return lhs.isFavorite }
            return lhs.createdAt > rhs.createdAt
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                ForEach(LibraryTab.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 300)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 10)

            Divider()

            if tab == .fragen {
                fragenList
            } else {
                vorlagenView
            }
        }
        .navigationTitle("Reflexionsfragen")
        .toolbar { toolbarContent }
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
        .sheet(isPresented: $showTemplateEditor) {
            TemplateEditorSheet(
                initialName: editingTemplate?.name ?? "",
                initialCadence: editingTemplate?.cadence ?? .flexible,
                initialDetail: editingTemplate?.detail ?? "",
                initialSections: editingTemplate?.sections ?? [""],
                isEditing: editingTemplate != nil
            ) { name, cadence, detail, sections in
                if let template = editingTemplate {
                    template.name = name
                    template.cadence = cadence
                    template.detail = detail
                    template.sections = sections
                } else {
                    context.insert(EntryTemplate(name: name, cadence: cadence, sections: sections,
                                                 detail: detail, sortIndex: templates.count))
                }
                save()
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if tab == .fragen {
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
                    Label("Frage hinzufügen", systemImage: "plus")
                }
            } else {
                Button {
                    editingTemplate = nil
                    showTemplateEditor = true
                } label: {
                    Label("Vorlage hinzufügen", systemImage: "plus")
                }
            }
        }
    }

    // MARK: - Fragen tab

    private var fragenList: some View {
        List {
            Section {
                introRow(icon: "lightbulb.fill", tint: .yellow,
                         text: "Deine Sammlung an Reflexionsfragen. Markiere Favoriten ⭐︎, "
                             + "bearbeite sie oder starte direkt einen Eintrag damit.")
            }

            if let generationMessage {
                Section {
                    Label(generationMessage, systemImage: "info.circle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            if visiblePrompts.isEmpty {
                EmptyHint(title: onlyFavorites ? "Keine Favoriten" : "Keine Reflexionsfragen",
                          systemImage: "lightbulb",
                          message: onlyFavorites
                            ? "Markiere Fragen mit dem Stern, um sie hier zu sammeln."
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
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    // MARK: - Vorlagen tab

    private var vorlagenView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                introRow(icon: "doc.text.fill", tint: .sage,
                         text: "Vorlagen geben dir eine feste Struktur zum Reinstarten – mehrere "
                             + "Fragen/Hinweise, z. B. für tägliche, wöchentliche oder jährliche Einträge.")

                if templates.isEmpty {
                    EmptyHint(title: "Keine Vorlagen",
                              systemImage: "doc.text",
                              message: "Erstelle eine Vorlage mit mehreren Fragen/Hinweisen, aus der du schnell einen Eintrag startest.")
                } else {
                    ForEach(templates) { template in
                        TemplateCard(template: template,
                                     onStart: { onStartTemplate(template) },
                                     onEdit: { editingTemplate = template; showTemplateEditor = true },
                                     onDelete: { context.delete(template); save() })
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func introRow(icon: String, tint: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundStyle(tint)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
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
                    if prompt.isAIGenerated { badge("KI", systemImage: "sparkles", tint: .purple) }
                    if prompt.isUserCreated { badge("Eigen", systemImage: "pencil", tint: .blue) }
                    if prompt.isArchived { badge("Archiviert", systemImage: "archivebox", tint: .orange) }
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
                Image(systemName: "ellipsis.circle").foregroundStyle(.secondary)
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

/// A template shown as a warm card with its questions and a "start" action.
private struct TemplateCard: View {
    let template: EntryTemplate
    var onStart: () -> Void
    var onEdit: () -> Void
    var onDelete: () -> Void

    var body: some View {
        PanelCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(template.name).serif(20)
                    cadenceBadge
                    Spacer()
                    Menu {
                        Button { onEdit() } label: { Label("Bearbeiten", systemImage: "pencil") }
                        Divider()
                        Button(role: .destructive) { onDelete() } label: { Label("Löschen", systemImage: "trash") }
                    } label: {
                        Image(systemName: "ellipsis.circle").foregroundStyle(.secondary)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                }

                if !template.detail.isEmpty {
                    Text(template.detail).font(.callout).foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(template.sections.prefix(6).enumerated()), id: \.offset) { _, section in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 5))
                                .foregroundStyle(.tertiary)
                                .padding(.top, 6)
                            Text(section).font(.callout).foregroundStyle(.secondary)
                        }
                    }
                    if template.sections.count > 6 {
                        Text("+ \(template.sections.count - 6) weitere")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                }

                Button(action: onStart) {
                    Label("Mit Vorlage schreiben", systemImage: "square.and.pencil")
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 2)
            }
        }
    }

    private var cadenceBadge: some View {
        Label(template.cadence.label, systemImage: template.cadence.systemImage)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.sage.opacity(0.16), in: Capsule())
            .foregroundStyle(Color.sage)
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

    init(initialText: String, initialCategory: String, isEditing: Bool,
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
            Text(isEditing ? "Reflexionsfrage bearbeiten" : "Neue Reflexionsfrage")
                .font(.title3.weight(.semibold))

            VStack(alignment: .leading, spacing: 6) {
                Text("Reflexionsfrage").font(.caption).foregroundStyle(.secondary)
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

    private var categoryOptions: [String] {
        categories.contains(category) ? categories : categories + [category]
    }
}

/// Sheet for adding *or* editing a template (name, cadence, hints/questions).
private struct TemplateEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let isEditing: Bool
    var onSave: (String, TemplateCadence, String, [String]) -> Void

    @State private var name: String
    @State private var cadence: TemplateCadence
    @State private var detail: String
    @State private var sections: [String]

    init(initialName: String, initialCadence: TemplateCadence, initialDetail: String,
         initialSections: [String], isEditing: Bool,
         onSave: @escaping (String, TemplateCadence, String, [String]) -> Void) {
        self.isEditing = isEditing
        self.onSave = onSave
        _name = State(initialValue: initialName)
        _cadence = State(initialValue: initialCadence)
        _detail = State(initialValue: initialDetail)
        _sections = State(initialValue: initialSections.isEmpty ? [""] : initialSections)
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(isEditing ? "Vorlage bearbeiten" : "Neue Vorlage")
                .font(.title3.weight(.semibold))

            VStack(alignment: .leading, spacing: 6) {
                Text("Name").font(.caption).foregroundStyle(.secondary)
                TextField("z. B. Tagesreflexion", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            Picker("Rhythmus", selection: $cadence) {
                ForEach(TemplateCadence.allCases) { Text($0.label).tag($0) }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Kurzbeschreibung (optional)").font(.caption).foregroundStyle(.secondary)
                TextField("Wofür ist diese Vorlage?", text: $detail)
                    .textFieldStyle(.roundedBorder)
            }

            Text("Fragen / Hinweise").font(.caption).foregroundStyle(.secondary)
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(sections.indices, id: \.self) { index in
                        HStack(spacing: 8) {
                            TextField("Frage oder Hinweis", text: $sections[index])
                                .textFieldStyle(.roundedBorder)
                            Button {
                                sections.remove(at: index)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .disabled(sections.count <= 1)
                        }
                    }
                }
            }
            .frame(maxHeight: 200)

            Button {
                sections.append("")
            } label: {
                Label("Zeile hinzufügen", systemImage: "plus")
            }
            .buttonStyle(.borderless)

            HStack {
                Spacer()
                Button("Abbrechen") { dismiss() }
                Button(isEditing ? "Sichern" : "Hinzufügen") {
                    let cleaned = sections
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                    guard !trimmedName.isEmpty, !cleaned.isEmpty else { return }
                    onSave(trimmedName, cadence, detail.trimmingCharacters(in: .whitespacesAndNewlines), cleaned)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(trimmedName.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 480)
    }
}
