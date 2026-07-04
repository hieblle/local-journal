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

            // Best-effort deeper reflective layer (beliefs, needs, triggers,
            // energy, strategies). Also non-fatal.
            await addDeepReflection(to: entry, using: service)

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

    /// Ask Gemma to propose new, **critically reflective** journal prompts based
    /// on recent entries (topics, patterns, feelings, goals, summaries).
    /// Returns an empty array (never throws) so the UI can degrade gracefully.
    func generateJournalPrompts(count: Int = 5, settings: AppSettings) async -> [String] {
        let service = OllamaService(baseURL: settings.ollamaBaseURL, model: settings.modelName)
        guard await service.isReachable() else { return [] }

        var descriptor = FetchDescriptor<JournalEntry>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = 10
        let recent = (try? context.fetch(descriptor)) ?? []
        let analyses = recent.compactMap { $0.analysis }
        let topics = uniqueLimited(analyses.flatMap { $0.topics }, limit: 12)
        let patterns = uniqueLimited(analyses.flatMap { $0.patterns }, limit: 8)
        let feelings = uniqueLimited(analyses.flatMap { $0.feelings }, limit: 10)
        let goals = uniqueLimited(analyses.flatMap { $0.goals }, limit: 8)
        let summaries = analyses.compactMap { $0.summary }.filter { !$0.isEmpty }

        let prompt = LLMPromptTemplates.generateReflectionPrompts(
            recentTopics: topics,
            recentPatterns: patterns,
            recentFeelings: feelings,
            recentGoals: goals,
            recentSummaries: summaries,
            count: count
        )
        return await decodePrompts(from: service, prompt: prompt)
    }

    /// Ask Gemma for **critically reflective follow-up questions for one entry**,
    /// grounded in its text and detected signals. Empty array on any failure.
    func reflectionPrompts(for entry: JournalEntry, count: Int = 4, settings: AppSettings) async -> [String] {
        let service = OllamaService(baseURL: settings.ollamaBaseURL, model: settings.modelName)
        guard await service.isReachable() else { return [] }

        let analysis = entry.analysis
        let prompt = LLMPromptTemplates.reflectionPromptsForEntry(
            entryTitle: entry.title,
            entryText: entry.text,
            topics: analysis?.topics ?? [],
            patterns: analysis?.patterns ?? [],
            feelings: analysis?.feelings ?? [],
            goals: analysis?.goals ?? [],
            count: count
        )
        return await decodePrompts(from: service, prompt: prompt)
    }

    /// Shared decoder for the `{ "prompts": [...] }` shape.
    private func decodePrompts(from service: OllamaService, prompt: String) async -> [String] {
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

    /// De-duplicate (case-insensitive, order-preserving) and cap a string list.
    private func uniqueLimited(_ values: [String], limit: Int) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for value in values {
            let key = value.lowercased()
            guard !value.isEmpty, seen.insert(key).inserted else { continue }
            out.append(value)
            if out.count >= limit { break }
        }
        return out
    }

    // MARK: - Deeper reflective layer + on-demand syntheses

    /// Second focused pass that fills the deeper reflective fields. Non-fatal:
    /// any failure simply leaves those fields empty.
    private func addDeepReflection(to entry: JournalEntry, using service: OllamaService) async {
        let prompt = LLMPromptTemplates.deepReflection(entryTitle: entry.title, entryText: entry.text)
        guard let raw = try? await service.generate(prompt: prompt) else { return }
        let result = DeepReflectionResult.parse(raw)
        guard let analysis = entry.analysis else { return }
        analysis.beliefs = result.beliefs
        analysis.needs = result.needs
        analysis.triggers = result.triggers
        analysis.energyGivers = result.energyGivers
        analysis.energyDrainers = result.energyDrainers
        analysis.strategies = result.strategies
    }

    /// On-demand narrative: how the person changed between older and recent
    /// entries. Empty string on any failure (offline / no data).
    func reflectOnChange(settings: AppSettings) async -> String {
        let service = OllamaService(baseURL: settings.ollamaBaseURL, model: settings.modelName)
        guard await service.isReachable() else { return "" }

        let ascending = FetchDescriptor<JournalEntry>(sortBy: [SortDescriptor(\.date, order: .forward)])
        guard let entries = try? context.fetch(ascending) else { return "" }
        let summaries = entries.compactMap { $0.analysis?.summary }.filter { !$0.isEmpty }
        guard summaries.count >= 4 else { return "" }

        let early = Array(summaries.prefix(6))
        let recent = Array(summaries.suffix(6))
        let prompt = LLMPromptTemplates.reflectOnChange(earlySummaries: early, recentSummaries: recent)
        return await decodeText(from: service, prompt: prompt, key: "text")
    }

    /// On-demand narrative: align the user's written values / goals with how they
    /// actually acted recently. Empty string on any failure.
    func checkValueAlignment(values: [String], goals: [String], settings: AppSettings) async -> String {
        let service = OllamaService(baseURL: settings.ollamaBaseURL, model: settings.modelName)
        guard await service.isReachable() else { return "" }
        guard !values.isEmpty || !goals.isEmpty else { return "" }

        var descriptor = FetchDescriptor<JournalEntry>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = 12
        let recent = (try? context.fetch(descriptor)) ?? []
        let summaries = recent.compactMap { $0.analysis?.summary }.filter { !$0.isEmpty }
        guard !summaries.isEmpty else { return "" }

        let prompt = LLMPromptTemplates.valueAlignment(values: values, goals: goals, recentSummaries: summaries)
        return await decodeText(from: service, prompt: prompt, key: "text")
    }

    /// Decode a single `{ "<key>": "..." }` text field from a model response.
    private func decodeText(from service: OllamaService, prompt: String, key: String) async -> String {
        guard let raw = try? await service.generate(prompt: prompt) else { return "" }
        let json = JSONText.extractObject(from: raw)
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = object[key] as? String else {
            return ""
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Applying results

    private func applyAnalysis(_ result: FullAnalysisResult, to entry: JournalEntry, modelName: String) {
        let analysis = entry.analysis ?? {
            let new = EntryAnalysis()
            entry.analysis = new
            return new
        }()

        analysis.summary = result.summary
        analysis.emotions = result.emotions
        analysis.feelings = result.feelings          // derived names, for charts/graph
        analysis.topics = result.topics
        analysis.people = result.people
        analysis.keyInsights = result.keyInsights
        analysis.ideas = result.ideas
        analysis.tasks = result.tasks
        analysis.goals = result.goals
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
