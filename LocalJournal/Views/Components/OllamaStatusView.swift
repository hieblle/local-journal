import SwiftUI

/// Observable reachability probe for the local Ollama server. Lightweight: it
/// only checks when asked (on appear / on demand), no background polling.
@MainActor
@Observable
final class OllamaMonitor {
    /// nil = unknown / not yet checked.
    private(set) var isReachable: Bool?
    private(set) var isChecking = false

    func refresh(baseURL: String, model: String) async {
        isChecking = true
        let service = OllamaService(baseURL: baseURL, model: model)
        let reachable = await service.isReachable()
        isReachable = reachable
        isChecking = false
    }
}

/// Compact "Ollama verbunden / nicht erreichbar" indicator.
struct OllamaStatusBadge: View {
    let isReachable: Bool?
    var isChecking: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            if isChecking {
                ProgressView()
                    .controlSize(.small)
            } else {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
            }
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.cardSurface, in: Capsule())
    }

    private var color: Color {
        switch isReachable {
        case .some(true): return .green
        case .some(false): return .orange
        case .none: return .gray
        }
    }

    private var label: String {
        if isChecking { return "Prüfe Ollama …" }
        switch isReachable {
        case .some(true): return "Ollama verbunden"
        case .some(false): return "Ollama nicht erreichbar"
        case .none: return "Ollama-Status unbekannt"
        }
    }
}
