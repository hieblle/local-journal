import Foundation
import SwiftData

/// First-launch setup: ensures an `AppSettings` record exists and seeds the
/// journal prompt library exactly once (guarded by `didSeedPrompts`).
enum SeedManager {
    @MainActor
    static func bootstrap(_ context: ModelContext) {
        let settings = AppSettings.current(in: context)
        guard !settings.didSeedPrompts else { return }

        for seed in JournalPromptSeedData.seeds {
            context.insert(JournalPrompt(text: seed.text, category: seed.category))
        }
        settings.didSeedPrompts = true

        try? context.save()
    }
}
