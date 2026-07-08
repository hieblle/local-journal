import SwiftUI
import SwiftData

/// App entry point. Wires up the single, on-device SwiftData store shared by the
/// main window and the Settings scene. Nothing here touches the network — all
/// AI work goes through `OllamaService` against a local server.
@main
struct LocalJournalApp: App {
    /// One container for the whole app so every scene reads the same local store.
    let container: ModelContainer

    init() {
        let schema = Schema([
            JournalEntry.self,
            EntryAnalysis.self,
            JournalPrompt.self,
            PersonEntity.self,
            TopicEntity.self,
            WeeklySummary.self,
            AppSettings.self,
            KnowledgeNode.self,
            KnowledgeEdge.self,
            GuidingPrinciple.self,
            EntryTemplate.self,
            PeriodicReport.self,
            NoteDocument.self,
            NoteThought.self,
            NoteInsight.self,
        ])
        // Persistent, local-only configuration. No CloudKit, no sync.
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            container = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("SwiftData-Store konnte nicht erstellt werden: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)
        .commands {
            // Replace the default "New" with a journaling-flavoured action.
            CommandGroup(replacing: .newItem) {
                Button("Neuer Eintrag") {
                    NotificationCenter.default.post(name: .newJournalEntry, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }

        // Standard macOS Settings window (⌘,) sharing the same store.
        Settings {
            SettingsView()
                .modelContainer(container)
                .frame(width: 460)
        }
    }
}

extension Notification.Name {
    /// Posted by the ⌘N menu command; the root view switches to the editor.
    static let newJournalEntry = Notification.Name("newJournalEntry")
}
