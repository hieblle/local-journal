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

    /// A reflection prompt handed from the Prompts page to the editor so the
    /// user can start writing straight from a question.
    @State private var pendingPrompt: String?

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
                            }
                    }
                    .environment(analysis)
                }
            } else {
                ProgressView()
            }
        }
        .onAppear {
            SeedManager.bootstrap(context)
            if analysis == nil {
                analysis = AnalysisService(context: context)
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

    @ViewBuilder
    private func detail(for section: AppSection) -> some View {
        switch section {
        case .dashboard: DashboardView(goToSection: { selection = $0 })
        case .memory:    MemoryBoardView()
        case .write:     JournalEditorView(initialPrompt: pendingPrompt,
                                           onConsumePrompt: { pendingPrompt = nil })
        case .entries:   EntryListView()
        case .prompts:   PromptLibraryView(onStartWriting: startWriting)
        case .insights:  InsightsView()
        case .graph:     KnowledgeGraphView()
        case .analysis:  AnalysisView()
        case .settings:  SettingsView()
        }
    }
}
