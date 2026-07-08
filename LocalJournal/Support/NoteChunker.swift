import Foundation
import CryptoKit

/// Splits a raw notes file into **thoughts**. The user's notes are
/// stream-of-consciousness: a new line usually means a new thought, bullets are
/// individual items, and markdown headings give context but are not thoughts
/// themselves. So the rules are deliberately line-based:
///
///  - every non-empty line with ≥ 3 words → its own thought
///  - every bullet / numbered item → its own thought (marker stripped)
///  - tiny fragments (< 3 words) attach to the previous thought
///  - `#` headings become the `heading` context of the following thoughts
///  - separator lines (`---`, `===`, `***`) and blank lines just break flow
enum NoteChunker {

    struct Thought {
        var heading: String?
        var text: String
    }

    static func thoughts(from raw: String) -> [Thought] {
        let normalized = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        var result: [Thought] = []
        var heading: String? = nil

        func append(_ text: String) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            result.append(Thought(heading: heading, text: trimmed))
        }

        for rawLine in normalized.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            // Pure separator lines (---, ===, ***, ___)
            if line.count >= 3, line.allSatisfy({ "-=*_#".contains($0) }) { continue }

            // Markdown heading → context for what follows, not a thought itself.
            if line.hasPrefix("#") {
                let text = line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                if !text.isEmpty { heading = text }
                continue
            }

            // Bullet / numbered item → own thought, marker stripped.
            if let item = strippedListItem(line) {
                append(item)
                continue
            }

            let wordCount = line.split(whereSeparator: { $0.isWhitespace }).count
            if wordCount >= 3 || result.isEmpty {
                append(line)
            } else {
                // Tiny fragment ("Wichtig!", "→ Buch") — glue to the previous
                // thought so it keeps its context.
                result[result.count - 1].text += " " + line
            }
        }
        return result
    }

    /// Returns the item text if the line is a bullet / numbered list item.
    private static func strippedListItem(_ line: String) -> String? {
        for marker in ["- ", "* ", "+ ", "• ", "– ", "— ", "> "] where line.hasPrefix(marker) {
            return String(line.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
        }
        if let range = line.range(of: #"^\d{1,3}[.)]\s+"#, options: .regularExpression) {
            return String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        }
        // Checkbox items "[ ]" / "[x]"
        if let range = line.range(of: #"^\[[ xX]\]\s+"#, options: .regularExpression) {
            return String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    /// Hex SHA-256 of file data, for skip-on-reimport de-duplication.
    static func contentHash(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
