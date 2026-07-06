import Foundation

/// Decoded shape of `LLMPromptTemplates.periodReport`: the best-effort narrative
/// layer of a weekly/monthly report. Tolerant on purpose — a partial or missing
/// answer still yields a usable report (the deterministic metrics carry it).
struct PeriodReportNarrative: Decodable {
    var narrative: String = ""
    var trajectory: String = ""
    var highlights: [String] = []
    var focus: String = ""
    var recommendations: [String] = []

    enum CodingKeys: String, CodingKey {
        case narrative, trajectory, highlights, focus, recommendations
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        narrative = Self.text(c, .narrative)
        trajectory = Self.text(c, .trajectory)
        focus = Self.text(c, .focus)
        highlights = Self.strings(c, .highlights)
        recommendations = Self.strings(c, .recommendations)
    }

    static func parse(_ raw: String) -> PeriodReportNarrative {
        let json = JSONText.extractObject(from: raw)
        guard let data = json.data(using: .utf8),
              let result = try? JSONDecoder().decode(PeriodReportNarrative.self, from: data) else {
            return PeriodReportNarrative()
        }
        return result
    }

    private static func text(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> String {
        ((try? c.decode(String.self, forKey: key)) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func strings(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> [String] {
        if let array = try? c.decode([String].self, forKey: key) {
            return array.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        }
        if let single = try? c.decode(String.self, forKey: key), !single.isEmpty {
            return [single.trimmingCharacters(in: .whitespacesAndNewlines)]
        }
        return []
    }
}
