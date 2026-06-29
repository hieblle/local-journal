import Foundation

/// Seed data for the **journal prompt** library — the writing impulses and
/// reflection questions shown to the user. These are *not* LLM prompts; the
/// technical prompts for Ollama live in `LLMPromptTemplates`.
///
/// Inserted once on first launch (guarded by `AppSettings.didSeedPrompts`).
/// The user can add more by hand, and Gemma can later generate new ones based
/// on previous entries.
enum JournalPromptSeedData {

    struct Seed {
        let text: String
        let category: String
    }

    /// Categories are deliberately gentle and non-clinical: they invite
    /// reflection rather than self-diagnosis.
    static let seeds: [Seed] = [
        // Gefühle
        .init(text: "Was beschäftigt mich gerade wirklich?", category: "Gefühle"),
        .init(text: "Welche Situation hat heute emotional nachgewirkt?", category: "Gefühle"),
        .init(text: "Wofür bin ich heute dankbar?", category: "Gefühle"),
        .init(text: "Wann habe ich mich heute am lebendigsten gefühlt?", category: "Gefühle"),

        // Muster
        .init(text: "Welche wiederkehrenden Themen zeigen sich in letzter Zeit?", category: "Muster"),
        .init(text: "Was wiederholt sich in meinen Gedanken diese Woche?", category: "Muster"),
        .init(text: "Welche Situationen lösen bei mir immer wieder dieselbe Reaktion aus?", category: "Muster"),

        // Vermeidung
        .init(text: "Was vermeide ich gerade anzuschauen?", category: "Vermeidung"),
        .init(text: "Welche Entscheidung schiebe ich vor mir her – und warum?", category: "Vermeidung"),
        .init(text: "Worüber möchte ich eigentlich nicht nachdenken?", category: "Vermeidung"),

        // Perspektive
        .init(text: "Was würde ich einem Freund in meiner Lage raten?", category: "Perspektive"),
        .init(text: "Wie würde ich auf den heutigen Tag in einem Jahr zurückblicken?", category: "Perspektive"),
        .init(text: "Was sehe ich heute anders als noch vor einem Monat?", category: "Perspektive"),

        // Beziehungen
        .init(text: "Welche Begegnung hat mich heute beschäftigt?", category: "Beziehungen"),
        .init(text: "Wem möchte ich gerade näher sein – und was hält mich zurück?", category: "Beziehungen"),

        // Energie & Fokus
        .init(text: "Was hat mir heute Energie gegeben, was hat sie genommen?", category: "Energie & Fokus"),
        .init(text: "Was war heute wirklich wichtig – jenseits der To-do-Liste?", category: "Energie & Fokus"),
        .init(text: "Worauf möchte ich morgen meine Aufmerksamkeit richten?", category: "Energie & Fokus"),
    ]
}
