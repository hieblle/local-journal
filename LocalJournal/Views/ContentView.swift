import SwiftUI
import SwiftData
import Combine

/// Sidebar sections of the app.
enum AppSection: String, CaseIterable, Identifiable {
    case dashboard
    case memory
    case write
    case entries
    case prompts
    case insights
    case notes
    case reports
    case graph
    case analysis
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .memory:    return "Merken"
        case .write:     return "Schreiben"
        case .entries:   return "Einträge"
        case .prompts:   return "Reflexionsfragen"
        case .insights:  return "Einsichten"
        case .notes:     return "Notizen"
        case .reports:   return "Berichte"
        case .graph:     return "Wissensgraph"
        case .analysis:  return "Analyse"
        case .settings:  return "Einstellungen"
        }
    }

    var icon: String {
        switch self {
        case .dashboard: return "square.grid.2x2"
        case .memory:    return "star"
        case .write:     return "square.and.pencil"
        case .entries:   return "book.closed"
        case .prompts:   return "lightbulb"
        case .insights:  return "brain.head.profile"
        case .notes:     return "note.text"
        case .reports:   return "doc.text.magnifyingglass"
        case .graph:     return "point.3.connected.trianglepath.dotted"
        case .analysis:  return "chart.bar.xaxis"
        case .settings:  return "gearshape"
        }
    }
}

/// Root navigation. Owns the shared `AnalysisService` and injects it into the
/// detail pane via the environment so analysis state is consistent app-wide.
struct ContentView: View {
    @Environment(\.modelContext) private var context

    @State private var selection: AppSection? = .dashboard
    @State private var analysis: AnalysisService?

    /// A reflection prompt handed from the Reflexionsfragen page to the editor so
    /// the user can start writing straight from a question.
    @State private var pendingPrompt: String?

    /// A template handed from the library to the editor.
    @State private var pendingTemplate: EntryTemplate?

    /// Guards the once-per-launch auto-generation of due weekly/monthly reports.
    @State private var didKickReports = false

    var body: some View {
        Group {
            if let analysis {
                NavigationSplitView {
                    List(AppSection.allCases, selection: $selection) { section in
                        Label(section.title, systemImage: section.icon)
                            .tag(section)
                    }
                    .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
                    .navigationTitle("Local Journal")
                    // The key facts live permanently at the bottom of the existing
                    // sidebar — small, always visible, never a second column.
                    .safeAreaInset(edge: .bottom) {
                        SidebarStatsFooter()
                    }
                } detail: {
                    NavigationStack {
                        detail(for: selection ?? .dashboard)
                            .navigationDestination(for: JournalEntry.self) { entry in
                                // The environment must be re-injected on the
                                // destination: values set on the NavigationStack
                                // do NOT reach navigationDestination content, so
                                // EntryDetailView would otherwise crash looking
                                // up AnalysisService.
                                EntryDetailView(entry: entry, onStartWriting: startWriting)
                                    .environment(analysis)
                                    .background(Color.appBackground)
                            }
                            .navigationDestination(for: PeriodicReport.self) { report in
                                ReportDetailView(report: report, onStartWriting: startWriting)
                                    .environment(analysis)
                                    .background(Color.appBackground)
                            }
                    }
                    .environment(analysis)
                    .background(Color.appBackground)
                }
            } else {
                ProgressView()
            }
        }
        .onAppear {
            SeedManager.bootstrap(context)
            let service = analysis ?? AnalysisService(context: context)
            if analysis == nil { analysis = service }

            // Best-effort, once per launch: fill in reports for the last
            // completed week / month (deterministic always, narrative if Ollama
            // is reachable). Runs in the background so it never blocks the UI.
            if !didKickReports {
                didKickReports = true
                let currentSettings = AppSettings.current(in: context)
                Task { @MainActor in
                    await service.autoGenerateDueReports(settings: currentSettings)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .newJournalEntry)) { _ in
            selection = .write
        }
    }

    /// Switch to the editor and pre-load it with a reflection prompt.
    private func startWriting(with prompt: String) {
        pendingPrompt = prompt
        selection = .write
    }

    /// Switch to the editor and pre-load it from a template.
    private func beginTemplate(_ template: EntryTemplate) {
        pendingTemplate = template
        selection = .write
    }

    @ViewBuilder
    private func detail(for section: AppSection) -> some View {
        switch section {
        case .dashboard: DashboardView(goToSection: { selection = $0 }, onStartWriting: startWriting)
        case .memory:    MemoryBoardView()
        case .write:     JournalEditorView(initialPrompt: pendingPrompt,
                                           onConsumePrompt: { pendingPrompt = nil },
                                           initialTemplate: pendingTemplate,
                                           onConsumeTemplate: { pendingTemplate = nil })
        case .entries:   EntryListView()
        case .prompts:   PromptLibraryView(onStartWriting: startWriting,
                                           onStartTemplate: beginTemplate)
        case .insights:  InsightsView()
        case .notes:     NotesView()
        case .reports:   ReportsView(onStartWriting: startWriting)
        case .graph:     KnowledgeGraphView()
        case .analysis:  AnalysisView()
        case .settings:  SettingsView()
        }
    }
}
