import Foundation
import SwiftData

/// Tracks where an entry is in the local AI-analysis lifecycle.
/// `pending` is the key state for the "Ollama not running" case: the entry is
/// saved safely and can be re-analysed later.
enum AnalysisStatus: String, Codable, CaseIterable {
    case notStarted   // analysis was never requested (e.g. auto-analyse off)
    case pending      // saved, waiting to be analysed (Ollama unreachable / queued)
    case running      // analysis currently in flight
    case completed    // analysis stored successfully
    case failed       // analysis attempted but failed (model / parse error)

    var label: String {
        switch self {
        case .notStarted: return "Keine Analyse"
        case .pending:    return "Analyse ausstehend"
        case .running:    return "Analysiere …"
        case .completed:  return "Analysiert"
        case .failed:     return "Analyse fehlgeschlagen"
        }
    }

    var systemImage: String {
        switch self {
        case .notStarted: return "circle.dashed"
        case .pending:    return "clock"
        case .running:    return "arrow.triangle.2.circlepath"
        case .completed:  return "checkmark.circle"
        case .failed:     return "exclamationmark.triangle"
        }
    }
}

/// A single journal entry written by the user. The source of truth for all
/// content; AI output lives in the attached `EntryAnalysis`.
@Model
final class JournalEntry {
    @Attribute(.unique) var id: UUID
    var title: String
    var date: Date
    var text: String
    var createdAt: Date
    var updatedAt: Date

    /// Seconds spent writing when the optional timer was used (0 otherwise).
    var writingSeconds: Int

    /// Word count is denormalised so dashboard / analysis stats stay cheap.
    var wordCount: Int

    /// Filename of this entry's mirrored Markdown file (if the Markdown mirror is
    /// enabled). Stored so edits overwrite the same file. Empty until first write;
    /// defaulted for safe migration.
    var mirrorFileName: String = ""

    /// Backing store for `analysisStatus` (SwiftData persists the raw string).
    private var analysisStatusRaw: String

    var analysisStatus: AnalysisStatus {
        get { AnalysisStatus(rawValue: analysisStatusRaw) ?? .notStarted }
        set { analysisStatusRaw = newValue.rawValue }
    }

    /// One-to-one AI analysis. Deleting the entry removes its analysis.
    @Relationship(deleteRule: .cascade, inverse: \EntryAnalysis.entry)
    var analysis: EntryAnalysis?

    /// Many-to-many links to recognised entities. The inverse lives here so the
    /// entity side stays a plain stored array.
    @Relationship(inverse: \PersonEntity.entries)
    var people: [PersonEntity]

    @Relationship(inverse: \TopicEntity.entries)
    var topics: [TopicEntity]

    /// Knowledge-graph nodes referenced by this entry (people, topics, feelings,
    /// ideas, learnings, tasks). Inverse declared here; `KnowledgeNode.entries`
    /// stays a plain stored array.
    @Relationship(inverse: \KnowledgeNode.entries)
    var nodes: [KnowledgeNode]

    init(
        id: UUID = UUID(),
        title: String = "",
        date: Date = .now,
        text: String = "",
        writingSeconds: Int = 0
    ) {
        self.id = id
        self.title = title
        self.date = date
        self.text = text
        self.createdAt = .now
        self.updatedAt = .now
        self.writingSeconds = writingSeconds
        self.wordCount = JournalEntry.countWords(in: text)
        self.analysisStatusRaw = AnalysisStatus.notStarted.rawValue
        self.people = []
        self.topics = []
        self.nodes = []
    }

    /// Recompute the denormalised word count from the current text.
    func refreshWordCount() {
        wordCount = JournalEntry.countWords(in: text)
    }

    static func countWords(in text: String) -> Int {
        text.split { $0.isWhitespace || $0.isNewline }
            .filter { !$0.isEmpty }
            .count
    }
}
