import Foundation

/// Normalisation rules for knowledge-graph nodes — the single place that decides
/// when two mentions are "the same" node.
///
/// De-duplication hinges entirely on `normalize(_:)`: two names that normalise to
/// the same string collapse into one node. The rules are deliberately
/// conservative for German text — we lowercase and tidy whitespace/punctuation
/// but **never fold umlauts** (ä→a would wrongly merge distinct words).
enum NodeNormalization {

    /// Characters stripped from the *ends* of a name (never from the middle, so
    /// "to-do" or "Work-Life" stay intact).
    private static let edgePunctuation = CharacterSet(charactersIn: ".,;:!?\"'`´()[]{}…-–—*_ ")

    /// Matching key: lowercased, whitespace-collapsed, end-punctuation-trimmed.
    /// Used for equality / de-duplication, not for display.
    static func normalize(_ raw: String) -> String {
        let collapsed = raw
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .lowercased()
        return collapsed.trimmingCharacters(in: edgePunctuation)
    }

    /// Human-facing name: whitespace tidied, original casing preserved.
    static func cleanDisplayName(_ raw: String) -> String {
        raw
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    /// Store-unique key for a node. Scoped by kind so the same word can exist as
    /// both a topic and a task without colliding (e.g. topic "Sport" vs. the
    /// intention "Sport" as a task).
    static func key(kind: NodeKind, name: String) -> String {
        "\(kind.rawValue)#\(normalize(name))"
    }
}
