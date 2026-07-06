import Foundation
import SwiftData
import AppKit

/// Mirrors journal entries to plain **Markdown files** in a user-chosen folder,
/// one file per entry. The SwiftData store stays the source of truth (it holds
/// the rich analysis / graph); the Markdown folder is a **one-way, portable
/// copy** — readable, backup-friendly and Obsidian-compatible.
///
/// The mirror is opt-in: the user picks a folder once (a sandbox requirement),
/// which is stored as a security-scoped bookmark on `AppSettings`. After that,
/// writing / editing / deleting an entry keeps the file in sync automatically.
@MainActor
enum MarkdownMirror {

    static func isConfigured(_ settings: AppSettings) -> Bool {
        settings.mirrorFolderBookmark != nil
    }

    // MARK: - Public operations

    /// Write (create or overwrite) the Markdown file for one entry.
    static func writeEntry(_ entry: JournalEntry, settings: AppSettings) {
        guard let folder = resolveFolder(settings) else { return }
        let didScope = folder.startAccessingSecurityScopedResource()
        defer { if didScope { folder.stopAccessingSecurityScopedResource() } }

        let url = folder.appendingPathComponent(ensureFileName(for: entry))
        try? markdown(for: entry).data(using: .utf8)?.write(to: url, options: .atomic)
        try? entry.modelContext?.save()      // persist a newly generated filename
    }

    /// Remove an entry's Markdown file (on delete).
    static func removeEntry(_ entry: JournalEntry, settings: AppSettings) {
        guard !entry.mirrorFileName.isEmpty, let folder = resolveFolder(settings) else { return }
        let didScope = folder.startAccessingSecurityScopedResource()
        defer { if didScope { folder.stopAccessingSecurityScopedResource() } }

        let url = folder.appendingPathComponent(entry.mirrorFileName)
        try? FileManager.default.removeItem(at: url)
    }

    /// Rewrite every entry (used to backfill after first choosing the folder).
    static func syncAll(_ entries: [JournalEntry], settings: AppSettings) {
        guard let folder = resolveFolder(settings) else { return }
        let didScope = folder.startAccessingSecurityScopedResource()
        defer { if didScope { folder.stopAccessingSecurityScopedResource() } }

        for entry in entries {
            let url = folder.appendingPathComponent(ensureFileName(for: entry))
            try? markdown(for: entry).data(using: .utf8)?.write(to: url, options: .atomic)
        }
        try? entries.first?.modelContext?.save()
    }

    /// Reveal the mirror folder in Finder.
    static func openInFinder(_ settings: AppSettings) {
        guard let folder = resolveFolder(settings) else { return }
        let didScope = folder.startAccessingSecurityScopedResource()
        defer { if didScope { folder.stopAccessingSecurityScopedResource() } }
        NSWorkspace.shared.activateFileViewerSelecting([folder])
    }

    // MARK: - Folder resolution

    private static func resolveFolder(_ settings: AppSettings) -> URL? {
        guard let data = settings.mirrorFolderBookmark else { return nil }
        var isStale = false
        return try? URL(resolvingBookmarkData: data,
                        options: [.withSecurityScope],
                        relativeTo: nil,
                        bookmarkDataIsStale: &isStale)
    }

    // MARK: - File naming

    /// Stable, human-readable filename per entry; generated once and stored so
    /// later edits overwrite the same file. The id suffix guarantees uniqueness.
    private static func ensureFileName(for entry: JournalEntry) -> String {
        if !entry.mirrorFileName.isEmpty { return entry.mirrorFileName }
        let name = "\(dateStamp(entry.date))-\(slug(entry.title))-\(shortID(entry)).md"
        entry.mirrorFileName = name
        return name
    }

    private static func shortID(_ entry: JournalEntry) -> String {
        String(entry.id.uuidString.prefix(6)).lowercased()
    }

    private static func slug(_ text: String) -> String {
        let mapped = text.lowercased().map { ch -> Character in
            (ch.isLetter || ch.isNumber) ? ch : "-"
        }
        var slug = String(mapped)
        while slug.contains("--") { slug = slug.replacingOccurrences(of: "--", with: "-") }
        slug = slug.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return slug.isEmpty ? "eintrag" : String(slug.prefix(40))
    }

    private static func dateStamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    // MARK: - Markdown rendering

    static func markdown(for entry: JournalEntry) -> String {
        var lines: [String] = ["---"]
        lines.append("date: \(dateStamp(entry.date))")
        lines.append("title: \"\(escape(entry.title.isEmpty ? "Ohne Titel" : entry.title))\"")
        lines.append("words: \(entry.wordCount)")
        lines.append("status: \(entry.analysisStatus.rawValue)")

        if let analysis = entry.analysis {
            lines.append("mood: \(String(format: "%.2f", analysis.moodScore))")
            appendList(&lines, key: "topics", analysis.topics)
            appendList(&lines, key: "people", analysis.people)
            appendList(&lines, key: "places", analysis.places)
            appendList(&lines, key: "feelings", analysis.feelings)
        }
        lines.append("---")

        var out = lines.joined(separator: "\n") + "\n\n"

        if let analysis = entry.analysis, !analysis.summary.isEmpty {
            let quoted = analysis.summary.replacingOccurrences(of: "\n", with: "\n> ")
            out += "> [!summary] Zusammenfassung\n> \(quoted)\n\n"
        }

        out += entry.text.isEmpty ? "*(kein Text)*" : entry.text
        out += "\n"

        if let analysis = entry.analysis {
            if !analysis.keyInsights.isEmpty {
                out += "\n\n## Erkenntnisse\n" + analysis.keyInsights.map { "- \($0)" }.joined(separator: "\n") + "\n"
            }
            if !analysis.tasks.isEmpty {
                out += "\n## Vorhaben\n" + analysis.tasks.map { "- [ ] \($0)" }.joined(separator: "\n") + "\n"
            }
        }
        return out
    }

    private static func appendList(_ lines: inout [String], key: String, _ values: [String]) {
        let cleaned = values
            .map { $0.replacingOccurrences(of: ",", with: " ")
                     .replacingOccurrences(of: "\n", with: " ")
                     .replacingOccurrences(of: "[", with: "")
                     .replacingOccurrences(of: "]", with: "")
                     .trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return }
        lines.append("\(key): [\(cleaned.joined(separator: ", "))]")
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "\"", with: "'")
            .replacingOccurrences(of: "\n", with: " ")
    }
}
