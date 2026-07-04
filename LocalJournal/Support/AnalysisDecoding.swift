import Foundation

/// Decoded shape of `LLMPromptTemplates.fullAnalysis`. Tolerant on purpose:
/// local models occasionally omit keys, wrap JSON in prose, or emit numbers as
/// strings. Every field has a safe default so a partial answer is still usable.
struct FullAnalysisResult: Decodable {
    var summary: String = ""
    var emotions: [EmotionScore] = []
    var topics: [String] = []
    var people: [String] = []
    var keyInsights: [String] = []
    var ideas: [String] = []
    var tasks: [String] = []
    var goals: [String] = []
    var places: [String] = []
    var patterns: [String] = []
    var moodScore: Double = 0

    /// Typed relations between concepts, used to build knowledge-graph edges.
    var relationships: [RelationTriple] = []

    /// Feeling names derived from `emotions` (for name-only consumers).
    var feelings: [String] { emotions.map(\.name).filter { !$0.isEmpty } }

    enum CodingKeys: String, CodingKey {
        case summary, emotions, feelings, topics, people, keyInsights, ideas, tasks
        case goals, places, patterns, moodScore, relationships
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let s = try? c.decode(String.self, forKey: .summary) {
            summary = s.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        emotions = Self.emotionList(c)
        topics = Self.stringArray(c, .topics)
        people = Self.stringArray(c, .people)
        keyInsights = Self.stringArray(c, .keyInsights)
        ideas = Self.stringArray(c, .ideas)
        tasks = Self.stringArray(c, .tasks)
        goals = Self.stringArray(c, .goals)
        places = Self.stringArray(c, .places)
        patterns = Self.stringArray(c, .patterns)
        moodScore = Self.lenientDouble(c, .moodScore)
        // Relations are best-effort: a malformed list must not fail the whole parse.
        relationships = (try? c.decode([RelationTriple].self, forKey: .relationships)) ?? []
    }

    /// Decode `emotions` as `[{name,intensity}]`, tolerating (a) a plain string
    /// list under `emotions` or `feelings`, and (b) intensity given as a string.
    private static func emotionList(_ c: KeyedDecodingContainer<CodingKeys>) -> [EmotionScore] {
        if let raw = try? c.decode([RawEmotion].self, forKey: .emotions) {
            let mapped = raw
                .map { EmotionScore(name: $0.name, intensity: $0.intensityValue) }
                .filter { !$0.name.isEmpty }
            if !mapped.isEmpty { return mapped }
        }
        // Fallbacks: a bare string list under emotions, or the old feelings key.
        let names = stringArray(c, .emotions).isEmpty ? stringArray(c, .feelings) : stringArray(c, .emotions)
        return names.map { EmotionScore(name: $0, intensity: 5) }
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

/// Loosely-typed emotion object as it may arrive from the model
/// (`{"name": "...", "intensity": 7}`), tolerating string intensities.
private struct RawEmotion: Decodable {
    var name: String = ""
    private var intensityInt: Int?
    private var intensityStr: String?

    enum CodingKeys: String, CodingKey { case name, intensity }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = ((try? c.decode(String.self, forKey: .name)) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let i = try? c.decode(Int.self, forKey: .intensity) {
            intensityInt = i
        } else if let d = try? c.decode(Double.self, forKey: .intensity) {
            intensityInt = Int(d.rounded())
        } else if let s = try? c.decode(String.self, forKey: .intensity) {
            intensityStr = s
        }
    }

    /// Resolved intensity; defaults to a neutral 5 when unknown.
    var intensityValue: Int {
        if let intensityInt { return intensityInt }
        if let intensityStr,
           let d = Double(intensityStr.replacingOccurrences(of: ",", with: ".")) {
            return Int(d.rounded())
        }
        return 5
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
