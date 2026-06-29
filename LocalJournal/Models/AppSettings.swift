import Foundation
import SwiftData

/// Single persisted settings record (a lightweight singleton). Holds the local
/// Ollama configuration and editor defaults. Fetched / created via
/// `AppSettings.current(in:)`.
@Model
final class AppSettings {
    @Attribute(.unique) var id: UUID

    /// Base URL of the local Ollama server. Never points outside the machine.
    var ollamaBaseURL: String

    /// Configurable model name. Defaults to a small local Gemma (see note below).
    var modelName: String

    /// Run AI analysis automatically after saving an entry.
    var autoAnalyze: Bool

    /// Editor: show the writing timer by default.
    var timerEnabledByDefault: Bool

    /// Editor: default timer length in minutes.
    var timerDurationMinutes: Int

    /// One-time guard so seed prompts are only inserted on first launch.
    var didSeedPrompts: Bool

    init(
        id: UUID = UUID(),
        ollamaBaseURL: String = AppSettings.defaultBaseURL,
        modelName: String = AppSettings.defaultModelName,
        autoAnalyze: Bool = true,
        timerEnabledByDefault: Bool = false,
        timerDurationMinutes: Int = 10,
        didSeedPrompts: Bool = false
    ) {
        self.id = id
        self.ollamaBaseURL = ollamaBaseURL
        self.modelName = modelName
        self.autoAnalyze = autoAnalyze
        self.timerEnabledByDefault = timerEnabledByDefault
        self.timerDurationMinutes = timerDurationMinutes
        self.didSeedPrompts = didSeedPrompts
    }

    static let defaultBaseURL = "http://localhost:11434"

    /// Assumption: "Gemma 4 4B" from the brief is interpreted as the current
    /// small local Gemma, which on Ollama is `gemma3:4b`. This is fully
    /// configurable in Settings — change it to whatever you have pulled
    /// (e.g. `gemma2:2b`, `gemma3:12b`). Documented in README.md.
    static let defaultModelName = "gemma3:4b"

    /// Fetch the existing settings record or create one on first launch.
    @MainActor
    static func current(in context: ModelContext) -> AppSettings {
        let descriptor = FetchDescriptor<AppSettings>()
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }
        let settings = AppSettings()
        context.insert(settings)
        return settings
    }
}
