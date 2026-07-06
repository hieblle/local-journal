import SwiftUI
import SwiftData
import AppKit

/// App settings: local Ollama configuration, editor defaults, and privacy info.
/// Reachable both from the sidebar and the standard macOS Settings window (⌘,).
struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query private var settingsList: [AppSettings]

    var body: some View {
        Group {
            if let settings = settingsList.first {
                SettingsForm(settings: settings)
            } else {
                ProgressView()
                    .onAppear {
                        _ = AppSettings.current(in: context)
                        try? context.save()
                    }
            }
        }
        .navigationTitle("Einstellungen")
    }
}

private struct SettingsForm: View {
    @Bindable var settings: AppSettings
    @Environment(\.modelContext) private var context

    @State private var monitor = OllamaMonitor()
    @State private var availableModels: [String] = []
    @State private var loadingModels = false
    @State private var pendingResult: String?
    @State private var isAnalyzingPending = false
    @State private var isSyncing = false

    var body: some View {
        Form {
            Section("Ollama (lokal)") {
                LabeledContent("Server-Adresse") {
                    TextField("http://localhost:11434", text: $settings.ollamaBaseURL)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 260)
                }

                LabeledContent("Modell") {
                    HStack {
                        TextField("gemma4:e4b", text: $settings.modelName)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 180)
                        if !availableModels.isEmpty {
                            Menu("Auswählen") {
                                ForEach(availableModels, id: \.self) { model in
                                    Button(model) { settings.modelName = model }
                                }
                            }
                            .frame(width: 110)
                        }
                    }
                }

                HStack {
                    Button {
                        Task { @MainActor in await testConnection() }
                    } label: {
                        Label("Verbindung testen", systemImage: "antenna.radiowaves.left.and.right")
                    }
                    Button {
                        Task { @MainActor in await loadModels() }
                    } label: {
                        if loadingModels {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Modelle laden", systemImage: "arrow.down.circle")
                        }
                    }
                    Spacer()
                    OllamaStatusBadge(isReachable: monitor.isReachable, isChecking: monitor.isChecking)
                }

                Text("Standardmodell ist `gemma4:e4b` (lokales Gemma). Passe es an das Modell an, das du mit `ollama pull` geladen hast (`ollama list`).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("KI-Analyse") {
                Toggle("Einträge automatisch nach dem Speichern analysieren", isOn: $settings.autoAnalyze)

                HStack {
                    Button {
                        Task { @MainActor in await analyzePending() }
                    } label: {
                        if isAnalyzingPending {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Ausstehende Analysen nachholen", systemImage: "clock.arrow.circlepath")
                        }
                    }
                    .disabled(isAnalyzingPending)
                    Spacer()
                    if let pendingResult {
                        Text(pendingResult)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Editor") {
                Toggle("Timer standardmäßig anzeigen", isOn: $settings.timerEnabledByDefault)
                Stepper(value: $settings.timerDurationMinutes, in: 1...120) {
                    Text("Timer-Dauer: \(settings.timerDurationMinutes) min")
                }
            }

            Section("Markdown-Ordner") {
                if settings.mirrorFolderBookmark == nil {
                    Text("Speichere jeden Eintrag zusätzlich als **.md-Datei** in einem Ordner deiner Wahl (z. B. ein Obsidian-Vault). Einmal wählen – danach wird automatisch synchronisiert.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button {
                        chooseMirrorFolder()
                    } label: {
                        Label("Ordner wählen …", systemImage: "folder.badge.plus")
                    }
                } else {
                    LabeledContent("Ordner") {
                        Text(settings.mirrorFolderPath)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    HStack {
                        Button {
                            MarkdownMirror.openInFinder(settings)
                        } label: {
                            Label("Im Finder öffnen", systemImage: "folder")
                        }
                        Button {
                            syncMirrorNow()
                        } label: {
                            if isSyncing {
                                ProgressView().controlSize(.small)
                            } else {
                                Label("Jetzt synchronisieren", systemImage: "arrow.triangle.2.circlepath")
                            }
                        }
                        .disabled(isSyncing)
                        Button("Ordner ändern …") { chooseMirrorFolder() }
                        Spacer()
                        Button(role: .destructive) { disableMirror() } label: {
                            Label("Deaktivieren", systemImage: "xmark.circle")
                        }
                    }
                    Text("Neue und bearbeitete Einträge werden automatisch geschrieben, gelöschte entfernt. Rein einseitig (Bearbeiten passiert in der App).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Datenschutz") {
                Label("Alle Daten bleiben lokal auf diesem Mac.", systemImage: "lock.shield")
                    .font(.callout)
                Text("Keine Cloud, kein Sync, keine externen APIs. Die einzige Netzwerkverbindung geht an deinen lokalen Ollama-Server.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Color.appBackground)
        .task {
            await monitor.refresh(baseURL: settings.ollamaBaseURL, model: settings.modelName)
        }
        .onDisappear { try? context.save() }
    }

    // MARK: - Actions

    private func testConnection() async {
        try? context.save()
        await monitor.refresh(baseURL: settings.ollamaBaseURL, model: settings.modelName)
    }

    private func loadModels() async {
        loadingModels = true
        let service = OllamaService(baseURL: settings.ollamaBaseURL, model: settings.modelName)
        availableModels = (try? await service.availableModels()) ?? []
        loadingModels = false
    }

    // MARK: - Markdown mirror

    private func chooseMirrorFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Ordner wählen"
        panel.message = "Ordner für die Markdown-Spiegelung deiner Einträge wählen"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let bookmark = try? url.bookmarkData(options: [.withSecurityScope],
                                                   includingResourceValuesForKeys: nil,
                                                   relativeTo: nil) else { return }
        settings.mirrorFolderBookmark = bookmark
        settings.mirrorFolderPath = url.path(percentEncoded: false)
        try? context.save()
        syncMirrorNow()
    }

    private func syncMirrorNow() {
        isSyncing = true
        let entries = (try? context.fetch(FetchDescriptor<JournalEntry>())) ?? []
        MarkdownMirror.syncAll(entries, settings: settings)
        isSyncing = false
    }

    private func disableMirror() {
        settings.mirrorFolderBookmark = nil
        settings.mirrorFolderPath = ""
        try? context.save()
    }

    private func analyzePending() async {
        isAnalyzingPending = true
        pendingResult = nil
        try? context.save()
        let service = AnalysisService(context: context)
        let done = await service.analyzePending(settings: settings)
        pendingResult = done > 0 ? "\(done) analysiert" : "Nichts zu tun oder Ollama offline"
        isAnalyzingPending = false
    }
}
