import Foundation
import SwiftData

/// A *journal* prompt: a writing impulse / reflection question shown to the
/// user. This is distinct from an LLM prompt template (see `LLMPromptTemplates`).
@Model
final class JournalPrompt {
    @Attribute(.unique) var id: UUID

    /// The reflection question itself, e.g. "Was beschäftigt mich gerade wirklich?".
    var text: String

    /// Loose grouping for browsing, e.g. "Gefühle", "Muster", "Perspektive".
    var category: String

    /// True if the user added it by hand (vs. seeded or AI-generated).
    var isUserCreated: Bool

    /// True if Gemma generated it from previous entries.
    var isAIGenerated: Bool

    /// Lets the user hide a prompt without deleting it.
    var isArchived: Bool

    var createdAt: Date

    init(
        id: UUID = UUID(),
        text: String,
        category: String = "Allgemein",
        isUserCreated: Bool = false,
        isAIGenerated: Bool = false,
        isArchived: Bool = false
    ) {
        self.id = id
        self.text = text
        self.category = category
        self.isUserCreated = isUserCreated
        self.isAIGenerated = isAIGenerated
        self.isArchived = isArchived
        self.createdAt = .now
    }
}
