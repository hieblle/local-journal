import Foundation

/// A tiny shared scale for the **self-reported mood** quick check-in (1…5).
/// Used by the editor's mood row, the entry model and the Markdown mirror so the
/// mapping to emoji / label lives in exactly one place.
enum MoodScale {
    /// Valid values, low → high.
    static let values = [1, 2, 3, 4, 5]

    static func emoji(_ value: Int) -> String {
        switch value {
        case 1: return "😔"
        case 2: return "😕"
        case 3: return "😐"
        case 4: return "🙂"
        case 5: return "😊"
        default: return ""
        }
    }

    static func label(_ value: Int) -> String {
        switch value {
        case 1: return "schwer"
        case 2: return "gedrückt"
        case 3: return "neutral"
        case 4: return "gut"
        case 5: return "sehr gut"
        default: return ""
        }
    }
}
