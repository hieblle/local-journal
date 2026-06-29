import Foundation

/// Errors surfaced by the Ollama layer. `notRunning` is the one the rest of the
/// app cares about most: it means we should keep the entry and mark analysis
/// as pending rather than failing loudly.
enum OllamaError: LocalizedError, Equatable {
    case invalidURL
    case notRunning              // connection refused / host unreachable
    case timedOut
    case server(status: Int)
    case emptyResponse
    case decodingFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Die Ollama-Adresse ist ungültig."
        case .notRunning:
            return "Ollama ist nicht erreichbar. Läuft der lokale Server (z. B. `ollama serve`)?"
        case .timedOut:
            return "Die Anfrage an Ollama hat zu lange gedauert."
        case .server(let status):
            return "Ollama hat mit Statuscode \(status) geantwortet."
        case .emptyResponse:
            return "Ollama hat eine leere Antwort geliefert."
        case .decodingFailed(let detail):
            return "Antwort von Ollama konnte nicht gelesen werden: \(detail)"
        }
    }
}

/// Thin, dependency-free networking layer for a **local** Ollama server.
/// Knows nothing about SwiftData or the UI — it just sends a prompt and returns
/// raw text. Configurable base URL and model name (default: small local Gemma).
struct OllamaService {
    var baseURL: String
    var model: String

    init(baseURL: String = AppSettings.defaultBaseURL,
         model: String = AppSettings.defaultModelName) {
        self.baseURL = baseURL
        self.model = model
    }

    /// `true` if the local server answers `/api/tags`. Used to gate auto-analysis
    /// and to show a connection indicator in the UI.
    func isReachable() async -> Bool {
        guard let url = endpoint("/api/tags") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 5
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    /// Names of models the local server has pulled (for the Settings picker).
    func availableModels() async throws -> [String] {
        guard let url = endpoint("/api/tags") else { throw OllamaError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        let data: Data
        do {
            let (responseData, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw OllamaError.emptyResponse }
            guard http.statusCode == 200 else { throw OllamaError.server(status: http.statusCode) }
            data = responseData
        } catch let error as OllamaError {
            throw error
        } catch {
            throw Self.mapTransportError(error)
        }
        let decoded = try? JSONDecoder().decode(TagsResponse.self, from: data)
        return decoded?.models.map(\.name) ?? []
    }

    /// Send a prompt to the model and return its raw text response.
    /// - Parameter json: when true, asks Ollama to constrain output to valid JSON
    ///   (`format: "json"`), which keeps the analysis decoders simple.
    func generate(prompt: String, json: Bool = true, temperature: Double = 0.4) async throws -> String {
        guard let url = endpoint("/api/generate") else { throw OllamaError.invalidURL }

        let body = GenerateRequest(
            model: model,
            prompt: prompt,
            stream: false,
            format: json ? "json" : nil,
            options: .init(temperature: temperature)
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120   // local 4B generation can take a while
        request.httpBody = try JSONEncoder().encode(body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw Self.mapTransportError(error)
        }

        guard let http = response as? HTTPURLResponse else { throw OllamaError.emptyResponse }
        guard http.statusCode == 200 else { throw OllamaError.server(status: http.statusCode) }

        do {
            let decoded = try JSONDecoder().decode(GenerateResponse.self, from: data)
            let text = decoded.response.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { throw OllamaError.emptyResponse }
            return text
        } catch let error as OllamaError {
            throw error
        } catch {
            throw OllamaError.decodingFailed(error.localizedDescription)
        }
    }

    // MARK: - Helpers

    private func endpoint(_ path: String) -> URL? {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
        return URL(string: base + path)
    }

    /// Translate low-level URL errors into our domain errors so callers can
    /// distinguish "server is down" from other failures.
    private static func mapTransportError(_ error: Error) -> OllamaError {
        guard let urlError = error as? URLError else { return .notRunning }
        switch urlError.code {
        case .timedOut:
            return .timedOut
        case .cannotConnectToHost, .cannotFindHost, .networkConnectionLost,
             .notConnectedToInternet, .dnsLookupFailed:
            return .notRunning
        default:
            return .notRunning
        }
    }

    // MARK: - Wire types

    private struct GenerateRequest: Encodable {
        let model: String
        let prompt: String
        let stream: Bool
        let format: String?
        let options: Options

        struct Options: Encodable {
            let temperature: Double
        }
    }

    private struct GenerateResponse: Decodable {
        let response: String
        let done: Bool?
    }

    private struct TagsResponse: Decodable {
        let models: [Tag]
        struct Tag: Decodable { let name: String }
    }
}
