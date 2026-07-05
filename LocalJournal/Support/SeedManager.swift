import Foundation
import SwiftData

/// First-launch setup: ensures an `AppSettings` record exists and seeds the
/// journal prompt library exactly once (guarded by `didSeedPrompts`).
enum SeedManager {
    @MainActor
    static func bootstrap(_ context: ModelContext) {
        let settings = AppSettings.current(in: context)

        if !settings.didSeedPrompts {
            for seed in JournalPromptSeedData.seeds {
                context.insert(JournalPrompt(text: seed.text, category: seed.category))
            }
            settings.didSeedPrompts = true
        }

        if !settings.didSeedTemplates {
            for (index, seed) in EntryTemplateSeedData.seeds.enumerated() {
                context.insert(EntryTemplate(name: seed.name, cadence: seed.cadence,
                                             sections: seed.sections, detail: seed.detail,
                                             sortIndex: index))
            }
            settings.didSeedTemplates = true
        }

        try? context.save()
    }
}

/// A few ready-made templates so the "Vorlagen" tab isn't empty on first launch.
/// Users can edit, delete or add their own.
enum EntryTemplateSeedData {
    struct Seed {
        let name: String
        let cadence: TemplateCadence
        let detail: String
        let sections: [String]
    }

    static let seeds: [Seed] = [
        Seed(name: "Tagesreflexion", cadence: .daily,
             detail: "Kurzer Rückblick auf den Tag.",
             sections: [
                "Wie war mein Tag insgesamt?",
                "Was war heute gut?",
                "Was hat mich gefordert?",
                "Wofür bin ich dankbar?",
                "Was nehme ich mir für morgen vor?"
             ]),
        Seed(name: "Morgenseiten", cadence: .daily,
             detail: "Freies Schreiben zum Start in den Tag.",
             sections: [
                "Was geht mir gerade durch den Kopf?",
                "Worauf freue ich mich heute?",
                "Was ist heute wirklich wichtig?"
             ]),
        Seed(name: "Wochenrückblick", cadence: .weekly,
             detail: "Die Woche einordnen und die nächste ausrichten.",
             sections: [
                "Was waren die Highlights der Woche?",
                "Was habe ich gelernt?",
                "Was hat Energie gegeben, was gekostet?",
                "Woran will ich nächste Woche arbeiten?"
             ]),
        Seed(name: "Jahresrückblick", cadence: .yearly,
             detail: "Das Jahr würdigen und Richtung geben.",
             sections: [
                "Was war dieses Jahr bedeutsam?",
                "Worauf bin ich stolz?",
                "Was lasse ich zurück?",
                "Was nehme ich mir fürs neue Jahr vor?"
             ])
    ]
}
