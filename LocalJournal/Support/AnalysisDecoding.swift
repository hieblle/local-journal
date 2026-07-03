import Foundation

/// Decoded shape of `LLMPromptTemplates.fullAnalysis`. Tolerant on purpose:
/// local models occasionally omit keys, wrap JSON in prose, or emit numbers as
/// strings. Every field has a safe default so a partial answer is still usable.
struct FullAnalysisResult: Decodable {
    var summary: String = ""
    var feelings: [String] = []
    var topics: [String] = []
    var people: [String] = []
    var keyInsights: [String] = []
    var ideas: [String] = []
    var tasks: [String] = []
    var goals: [String] = []
    var events: [String] = []
    var places: [String] = []
    var patterns: [String] = []
    var moodScore: Double = 0

    /// Typed relations between concepts, used to build knowledge-graph edges.
    var relationships: [RelationTriple] = []

    enum CodingKeys: String, CodingKey {
        case summary, feelings, topics, people, keyInsights, ideas, tasks
        case goals, events, places, patterns, moodScore, relationships
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let s = try? c.decode(String.self, forKey: .summary) {
            summary = s.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        feelings = Self.stringArray(c, .feelings)
        topics = Self.stringArray(c, .topics)
        people = Self.stringArray(c, .people)
        keyInsights = Self.stringArray(c, .keyInsights)
        ideas = Self.stringArray(c, .ideas)
        tasks = Self.stringArray(c, .tasks)
        goals = Self.stringArray(c, .goals)
        events = Self.stringArray(c, .events)
        places = Self.stringArray(c, .places)
        patterns = Self.stringArray(c, .patterns)
        moodScore = Self.lenientDouble(c, .moodScore)
        // Relations are best-effort: a malformed list must not fail the whole parse.
        relationships = (try? c.decode([RelationTriple].self, forKey: .relationships)) ?? []
    }

    /// Parse a raw model response that should contain a single JSON object.
    static func parse(_ raw: String) throws -> FullAnalysisResult {
        let json = JSONText.extractObject(from: raw)
        guard let data = json.data(using: .utf8) else {
            throw OllamaError.decodingFailed("Antwort war kein UTF-8.")
        }
        do {
            return try JSONDecoder().decode(FullAnalysisResult.self, from: data)
        } catch {
            throw OllamaError.decodingFailed(error.localizedDescription)
        }
    }

    private static func stringArray(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> [String] {
        if let array = try? c.decode([String].self, forKey: key) {
            return array
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        // Some models return a single comma-separated string instead of a list.
        if let single = try? c.decode(String.self, forKey: key) {
            return single.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        return []
    }

    private static func lenientDouble(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Double {
        if let d = try? c.decode(Double.self, forKey: key) {
            return min(max(d, -1), 1)
        }
        if let s = try? c.decode(String.self, forKey: key),
           let d = Double(s.replacingOccurrences(of: ",", with: ".")) {
            return min(max(d, -1), 1)
        }
        return 0
    }
}

/// One `(source) —relation→ (target)` statement from the model, with a type hint
/// for each endpoint. Tolerant: any missing field decodes to "" so a single
/// malformed triple never breaks the surrounding list.
struct RelationTriple: Decodable {
    var source: String = ""
    var sourceType: String = ""
    var relation: String = ""
    var target: String = ""
    var targetType: String = ""

    enum CodingKeys: String, CodingKey {
        case source, sourceType, relation, target, targetType
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        source = (try? c.decode(String.self, forKey: .source)) ?? ""
        sourceType = (try? c.decode(String.self, forKey: .sourceType)) ?? ""
        relation = (try? c.decode(String.self, forKey: .relation)) ?? ""
        target = (try? c.decode(String.self, forKey: .target)) ?? ""
        targetType = (try? c.decode(String.self, forKey: .targetType)) ?? ""
    }
}

/// Small helpers for coaxing a JSON object out of an LLM response.
enum JSONText {
    /// Strip Markdown fences and return the substring from the first `{` to the
    /// matching last `}`. Falls back to the trimmed input if no braces found.
    static func extractObject(from raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("```") {
            // remove leading ```json / ``` and trailing ```
            s = s.replacingOccurrences(of: "```json", with: "")
                 .replacingOccurrences(of: "```", with: "")
                 .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let start = s.firstIndex(of: "{"),
              let end = s.lastIndex(of: "}"),
              start <= end else {
            return s
        }
        return String(s[start...end])
    }
}
