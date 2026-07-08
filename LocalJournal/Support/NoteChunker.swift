import Foundation
import CryptoKit

/// Splits a raw notes file into **thoughts**. The user's notes are
/// stream-of-consciousness: a new line usually means a new thought, bullets are
/// individual items, and markdown headings give context but are not thoughts
/// themselves. So the rules are deliberately line-based:
///
///  - every non-empty line with ≥ 3 words → its own thought
///  - every bullet / numbered item → its own thought (marker stripped)
///  - tiny fragments (< 3 words) attach to the previous thought of the same block
///  - `#` headings become the `heading` context of the following thoughts
///  - separator lines (`---`, `===`, `***`) and blank lines just break flow
///
/// Blank lines additionally advance `paragraphIndex`: lines of the same block
/// often belong to one topic, so the distillation keeps blocks together (a batch
/// never cuts through a paragraph) and may merge lines of a block into one
/// insight. The single line stays the storage / embedding unit.
enum NoteChunker {

    struct Thought {
        var heading: String?
        var text: String
        var paragraphIndex: Int
    }

    static func thoughts(from raw: String) -> [Thought] {
        let normalized = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        var result: [Thought] = []
        var heading: String? = nil
        var paragraph = 0
        var paragraphHasContent = false

        func nextParagraph() {
            if paragraphHasContent {
                paragraph += 1
                paragraphHasContent = false
            }
        }

        func append(_ text: String) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            result.append(Thought(heading: heading, text: trimmed, paragraphIndex: paragraph))
            paragraphHasContent = true
        }

        for rawLine in normalized.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { nextParagraph(); continue }

            // Pure separator lines (---, ===, ***, ___)
            if line.count >= 3, line.allSatisfy({ "-=*_#".contains($0) }) {
                nextParagraph()
                continue
            }

            // Markdown heading → context for what follows, not a thought itself.
            if line.hasPrefix("#") {
                nextParagraph()
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
            if wordCount >= 3 {
                append(line)
            } else if let lastIndex = result.indices.last,
                      result[lastIndex].paragraphIndex == paragraph {
                // Tiny fragment ("Wichtig!", "→ Buch") — glue to the previous
                // thought of the SAME block so it keeps its context.
                result[lastIndex].text += " " + line
            } else {
                append(line)
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
