import Foundation
import SwiftData
import Observation

/// Orchestrates the local AI-analysis pipeline that runs after an entry is
/// saved. All SwiftData mutation happens on the main actor; only the network
/// round-trips suspend. Designed to *never* lose an entry: if Ollama is
/// unreachable the entry is simply marked `.pending` for later.
@MainActor
@Observable
final class AnalysisService {
    private let context: ModelContext

    /// Lightweight UI signal: how many analyses are currently in flight.
    private(set) var activeCount: Int = 0

    /// Last user-facing error message (e.g. for a banner), if any.
    private(set) var lastErrorMessage: String?

    var isWorking: Bool { activeCount > 0 }

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: - Public API

    /// Analyse a single entry. Safe to call fire-and-forget from a `Task`.
    /// Marks the entry `.pending` (not `.failed`) when Ollama is unreachable.
    func analyze(_ entry: JournalEntry, settings: AppSettings) async {
        let service = OllamaService(baseURL: settings.ollamaBaseURL, model: settings.modelName)

        guard await service.isReachable() else {
            entry.analysisStatus = .pending
            save()
            return
        }

        activeCount += 1
        defer { activeCount -= 1 }

        entry.analysisStatus = .running
        save()

        do {
            let raw = try await service.generate(
                prompt: LLMPromptTemplates.fullAnalysis(entryTitle: entry.title, entryText: entry.text)
            )
            let result = try FullAnalysisResult.parse(raw)
            applyAnalysis(result, to: entry, modelName: settings.modelName)

            // Best-effort comparison with the previous 7 days; a failure here
            // must not invalidate the primary analysis.
            await addWeeklyComparison(to: entry, using: service)

            entry.analysisStatus = .completed
            lastErrorMessage = nil
            save()
        } catch let error as OllamaError {
            // A transport drop mid-run still leaves the entry recoverable.
            entry.analysisStatus = (error == .notRunning || error == .timedOut) ? .pending : .failed
            lastErrorMessage = error.errorDescription
            save()
        } catch {
            entry.analysisStatus = .failed
            lastErrorMessage = error.localizedDescription
            save()
        }
    }

    /// Re-run analysis for every entry still `.pending` or `.failed`.
    /// Returns the number of entries successfully analysed.
    @discardableResult
    func analyzePending(settings: AppSettings) async -> Int {
        let pendingStates: [AnalysisStatus] = [.pending, .failed, .notStarted]
        let descriptor = FetchDescriptor<JournalEntry>(
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )
        guard let entries = try? context.fetch(descriptor) else { return 0 }
        let todo = entries.filter { pendingStates.contains($0.analysisStatus) }

        var done = 0
        for entry in todo {
            await analyze(entry, settings: settings)
            if entry.analysisStatus == .completed { done += 1 }
        }
        return done
    }

    /// Ask Gemma to propose new *journal* prompts based on recent themes.
    /// Returns an empty array (never throws) so the UI can degrade gracefully.
    func generateJournalPrompts(count: Int = 5, settings: AppSettings) async -> [String] {
        let service = OllamaService(baseURL: settings.ollamaBaseURL, model: settings.modelName)
        guard await service.isReachable() else { return [] }

        var descriptor = FetchDescriptor<JournalEntry>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = 10
        let recent = (try? context.fetch(descriptor)) ?? []
        let topics = Array(Set(recent.flatMap { $0.analysis?.topics ?? [] })).prefix(12)
        let summaries = recent.compactMap { $0.analysis?.summary }.filter { !$0.isEmpty }

        let prompt = LLMPromptTemplates.generateReflectionPrompts(
            recentTopics: Array(topics),
            recentSummaries: summaries,
            count: count
        )
        guard let raw = try? await service.generate(prompt: prompt) else { return [] }

        let json = JSONText.extractObject(from: raw)
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = object["prompts"] as? [String] else {
            return []
        }
        return list
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Applying results

    private func applyAnalysis(_ result: FullAnalysisResult, to entry: JournalEntry, modelName: String) {
        let analysis = entry.analysis ?? {
            let new = EntryAnalysis()
            entry.analysis = new
            return new
        }()

        analysis.summary = result.summary
        analysis.feelings = result.feelings
        analysis.topics = result.topics
        analysis.people = result.people
        analysis.keyInsights = result.keyInsights
        analysis.ideas = result.ideas
        analysis.tasks = result.tasks
        analysis.goals = result.goals
        analysis.events = result.events
        analysis.places = result.places
        analysis.patterns = result.patterns
        analysis.moodScore = result.moodScore
        analysis.modelName = modelName
        analysis.createdAt = .now

        linkPeople(result.people, to: entry)
        linkTopics(result.topics, to: entry)

        // Fold this entry into the knowledge graph (nodes, co-occurrence + typed edges).
        KnowledgeGraphService(context: context).ingest(result, into: entry)
    }

    /// Resolve detected names to shared `PersonEntity` records (creating new ones
    /// as needed) and link them to the entry, de-duplicated by normalised name.
    private func linkPeople(_ names: [String], to entry: JournalEntry) {
        var resolved: [PersonEntity] = []
        var seen = Set<String>()
        for raw in names {
            let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let norm = PersonEntity.normalize(name)
            guard !norm.isEmpty, seen.insert(norm).inserted else { continue }
            let person = fetchPerson(normalized: norm) ?? {
                let p = PersonEntity(name: name)
                context.insert(p)
                return p
            }()
            person.lastSeen = max(person.lastSeen, entry.date)
            resolved.append(person)
        }
        entry.people = resolved
    }

    private func linkTopics(_ names: [String], to entry: JournalEntry) {
        var resolved: [TopicEntity] = []
        var seen = Set<String>()
        for raw in names {
            let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let norm = TopicEntity.normalize(name)
            guard !norm.isEmpty, seen.insert(norm).inserted else { continue }
            let topic = fetchTopic(normalized: norm) ?? {
                let t = TopicEntity(name: name)
                context.insert(t)
                return t
            }()
            topic.lastSeen = max(topic.lastSeen, entry.date)
            resolved.append(topic)
        }
        entry.topics = resolved
    }

    private func fetchPerson(normalized norm: String) -> PersonEntity? {
        var descriptor = FetchDescriptor<PersonEntity>(
            predicate: #Predicate { $0.normalizedName == norm }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func fetchTopic(normalized norm: String) -> TopicEntity? {
        var descriptor = FetchDescriptor<TopicEntity>(
            predicate: #Predicate { $0.normalizedName == norm }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    // MARK: - 7-day comparison

    private func addWeeklyComparison(to entry: JournalEntry, using service: OllamaService) async {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: entry.date) ?? entry.date
        let entryDate = entry.date
        var descriptor = FetchDescriptor<JournalEntry>(
            predicate: #Predicate {
                $0.date >= cutoff && $0.date < entryDate
            },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = 8

        guard let recent = try? context.fetch(descriptor) else { return }
        let entryID = entry.id
        let summaries = recent
            .filter { $0.id != entryID }              // exclude the current entry
            .compactMap { $0.analysis?.summary }
            .filter { !$0.isEmpty }
            .prefix(7)
        let summariesArray = Array(summaries)
        guard !summariesArray.isEmpty else { return }
        guard !summaries.isEmpty else { return }

        let prompt = LLMPromptTemplates.compareWithLastWeek(
            currentSummary: entry.analysis?.summary ?? "",
            lastWeekSummaries: summariesArray
        )
        guard let raw = try? await service.generate(prompt: prompt) else { return }
        let comparison = ComparisonResult.parse(raw)
        entry.analysis?.comparisonWithLastWeek = comparison.comparison
        if !comparison.patterns.isEmpty {
            let merged = (entry.analysis?.patterns ?? []) + comparison.patterns
            entry.analysis?.patterns = Array(Set(merged))
        }
    }

    // MARK: - Saving

    private func save() {
        do {
            try context.save()
        } catch {
            lastErrorMessage = "Speichern fehlgeschlagen: \(error.localizedDescription)"
        }
    }
}

/// Decoded shape of `LLMPromptTemplates.compareWithLastWeek`.
private struct ComparisonResult {
    var comparison: String = ""
    var patterns: [String] = []

    static func parse(_ raw: String) -> ComparisonResult {
        let json = JSONText.extractObject(from: raw)
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ComparisonResult()
        }
        var result = ComparisonResult()
        result.comparison = (object["comparison"] as? String) ?? ""
        result.patterns = (object["patterns"] as? [String]) ?? []
        return result
    }
}
