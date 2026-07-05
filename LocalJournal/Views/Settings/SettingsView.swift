import SwiftUI
import SwiftData

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
