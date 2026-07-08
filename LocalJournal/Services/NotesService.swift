import Foundation
import SwiftData
import Observation

/// Import + distillation pipeline for the **Notizen** area.
///
/// Import reads txt/md files (or folders of them), splits each into line-level
/// thoughts (`NoteChunker`) and stores them; identical files (same content hash)
/// are skipped. Distillation then walks all un-distilled thoughts in batches and
/// asks Gemma to extract only the lasting insights — resumable (each thought is
/// flagged once looked at), stoppable between batches, offline-tolerant.
@MainActor
@Observable
final class NotesService {
    private let context: ModelContext

    private(set) var isDistilling = false
    private(set) var batchesDone = 0
    private(set) var batchesTotal = 0
    private(set) var foundThisRun = 0
    private(set) var lastMessage: String?

    private var stopRequested = false

    /// Roughly one Gemma call per batch; sized so context stays comfortable.
    private let maxThoughtsPerBatch = 18
    private let maxWordsPerBatch = 1200

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: - Import

    struct ImportResult {
        var files = 0
        var thoughts = 0
        var skipped = 0
    }

    /// Import the given files/folders (recursively; only .txt / .md are read).
    func importFiles(at urls: [URL]) -> ImportResult {
        var result = ImportResult()
        let existingHashes = Set(fetchDocuments().map(\.contentHash))
        var seenHashes = existingHashes

        for url in expand(urls) {
            guard let data = try? Data(contentsOf: url) else { result.skipped += 1; continue }
            let hash = NoteChunker.contentHash(of: data)
            if seenHashes.contains(hash) { result.skipped += 1; continue }

            // utf8 first, then latin-1 as a lossless byte fallback for old files.
            guard let text = String(data: data, encoding: .utf8)
                    ?? String(data: data, encoding: .isoLatin1) else {
                result.skipped += 1
                continue
            }
            let thoughts = NoteChunker.thoughts(from: text)
            guard !thoughts.isEmpty else { result.skipped += 1; continue }

            let document = NoteDocument(
                fileName: url.lastPathComponent,
                title: url.deletingPathExtension().lastPathComponent,
                contentHash: hash
            )
            context.insert(document)
            for (index, thought) in thoughts.enumerated() {
                let record = NoteThought(text: thought.text, heading: thought.heading, orderIndex: index)
                record.document = document
                context.insert(record)
            }
            seenHashes.insert(hash)
            result.files += 1
            result.thoughts += thoughts.count
        }
        try? context.save()
        lastMessage = "\(result.files) Datei(en), \(result.thoughts) Gedanken importiert"
            + (result.skipped > 0 ? " · \(result.skipped) übersprungen" : "")
        return result
    }

    /// Recursively expand folders into their .txt / .md files.
    private func expand(_ urls: [URL]) -> [URL] {
        var files: [URL] = []
        let manager = FileManager.default
        for url in urls {
            var isDirectory: ObjCBool = false
            guard manager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }
            if isDirectory.boolValue {
                let enumerator = manager.enumerator(at: url, includingPropertiesForKeys: nil)
                while let child = enumerator?.nextObject() as? URL {
                    if isNoteFile(child) { files.append(child) }
                }
            } else if isNoteFile(url) {
                files.append(url)
            }
        }
        return files.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func isNoteFile(_ url: URL) -> Bool {
        ["txt", "md", "markdown", "text"].contains(url.pathExtension.lowercased())
    }

    // MARK: - Distillation

    var undistilledCount: Int {
        fetchThoughts().filter { !$0.isDistilled }.count
    }

    func stopDistilling() { stopRequested = true }

    /// Walk all un-distilled thoughts in document order, batch them, and let
    /// Gemma extract insights. Safe to re-run any time; continues where it left off.
    func distillPending(settings: AppSettings) async {
        guard !isDistilling else { return }

        let service = OllamaService(baseURL: settings.ollamaBaseURL, model: settings.modelName)
        guard await service.isReachable() else {
            lastMessage = "Ollama ist nicht erreichbar – Destillation später starten."
            return
        }

        let pending = fetchThoughts()
            .filter { !$0.isDistilled }
            .sorted { lhs, rhs in
                let l = lhs.document?.importedAt ?? .distantPast
                let r = rhs.document?.importedAt ?? .distantPast
                return l != r ? l < r : lhs.orderIndex < rhs.orderIndex
            }
        guard !pending.isEmpty else {
            lastMessage = "Alles bereits destilliert."
            return
        }

        let batches = makeBatches(pending)
        isDistilling = true
        stopRequested = false
        batchesDone = 0
        batchesTotal = batches.count
        foundThisRun = 0
        defer { isDistilling = false }

        // Case-insensitive text set of everything already extracted, so re-runs
        // and repetitive notes don't produce duplicate insights.
        var knownTexts = Set(fetchInsights().map { normalize($0.text) })
        let options = LLMPromptTemplates.PromptOptions(settings)

        for batch in batches {
            if stopRequested { break }

            let snippets = batch.enumerated().map { index, thought in
                LLMPromptTemplates.NoteSnippet(index: index + 1, heading: thought.heading, text: thought.text)
            }
            let prompt = LLMPromptTemplates.distillNotes(batch: snippets, options: options)

            if let raw = try? await service.generate(prompt: prompt, json: true, temperature: 0.3) {
                let extracted = NoteDistillResult.parse(raw).insights
                for item in extracted {
                    guard item.index >= 1, item.index <= batch.count else { continue }
                    let source = batch[item.index - 1]
                    let key = normalize(item.text)
                    guard !item.text.isEmpty, !knownTexts.contains(key) else { continue }
                    knownTexts.insert(key)
                    context.insert(NoteInsight(
                        kind: item.kind,
                        text: item.text,
                        topics: item.topics,
                        sourceText: source.text,
                        sourceDocumentName: source.document?.fileName ?? "",
                        thoughtID: source.id
                    ))
                    foundThisRun += 1
                }
                // Only mark the batch as done when the call succeeded, so a
                // dropped connection re-tries these thoughts next run.
                for thought in batch { thought.isDistilled = true }
            }

            batchesDone += 1
            try? context.save()
        }

        lastMessage = stopRequested
            ? "Pausiert – \(foundThisRun) Erkenntnisse bisher. Jederzeit fortsetzbar."
            : "Fertig: \(foundThisRun) neue Erkenntnisse gefunden."
    }

    private func makeBatches(_ thoughts: [NoteThought]) -> [[NoteThought]] {
        var batches: [[NoteThought]] = []
        var current: [NoteThought] = []
        var words = 0
        for thought in thoughts {
            let count = thought.text.split(whereSeparator: { $0.isWhitespace }).count
            if !current.isEmpty,
               current.count >= maxThoughtsPerBatch || words + count > maxWordsPerBatch {
                batches.append(current)
                current = []
                words = 0
            }
            current.append(thought)
            words += count
        }
        if !current.isEmpty { batches.append(current) }
        return batches
    }

    private func normalize(_ text: String) -> String {
        text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Fetching

    private func fetchDocuments() -> [NoteDocument] {
        (try? context.fetch(FetchDescriptor<NoteDocument>())) ?? []
    }

    private func fetchThoughts() -> [NoteThought] {
        (try? context.fetch(FetchDescriptor<NoteThought>())) ?? []
    }

    private func fetchInsights() -> [NoteInsight] {
        (try? context.fetch(FetchDescriptor<NoteInsight>())) ?? []
    }
}

/// Tolerant decoder for `LLMPromptTemplates.distillNotes`:
/// `{ "insights": [{"index": 3, "kind": "…", "text": "…", "topics": […]}] }`.
struct NoteDistillResult {
    struct Item {
        var index: Int
        var kind: NoteInsightKind
        var text: String
        var topics: [String]
    }

    var insights: [Item] = []

    static func parse(_ raw: String) -> NoteDistillResult {
        let json = JSONText.extractObject(from: raw)
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = object["insights"] as? [[String: Any]] else {
            return NoteDistillResult()
        }
        var result = NoteDistillResult()
        for entry in list {
            guard let index = intValue(entry["index"]) else { continue }
            let text = ((entry["text"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let topics = ((entry["topics"] as? [String]) ?? [])
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            result.insights.append(Item(index: index,
                                        kind: kind(from: entry["kind"] as? String),
                                        text: text,
                                        topics: topics))
        }
        return result
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let i = value as? Int { return i }
        if let d = value as? Double { return Int(d) }
        if let s = value as? String { return Int(s.trimmingCharacters(in: .whitespaces)) }
        return nil
    }

    /// Map the model's kind string (tolerating German synonyms) to our enum.
    private static func kind(from raw: String?) -> NoteInsightKind {
        switch (raw ?? "").lowercased().trimmingCharacters(in: .whitespaces) {
        case "recommendation", "empfehlung", "rat", "tipp": return .recommendation
        case "principle", "grundsatz", "leitsatz", "wert":  return .principle
        case "idea", "idee":                                return .idea
        default:                                            return .learning
        }
    }
}
