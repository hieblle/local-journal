import SwiftUI

/// One turn of the companion conversation, in a shape the prompt template can use.
struct ChatTurn {
    var isUser: Bool
    var text: String
}

/// State + logic for the in-editor "KI-Begleiter" chat. Talks to the local Ollama
/// server (free-text, non-JSON) and always passes the current draft as context.
/// Best-effort: offline just shows a hint, nothing is lost.
@MainActor
@Observable
final class CompanionChat {
    struct Message: Identifiable {
        let id = UUID()
        let isUser: Bool
        var text: String
    }

    var messages: [Message] = []
    var draft: String = ""
    var isThinking = false
    var notice: String?

    /// A few generic starter impulses shown above an empty conversation.
    let impulses = [
        "Fass zusammen, was mir wichtig war.",
        "Stell mir eine tiefere Frage dazu.",
        "Was übersehe ich hier vielleicht?"
    ]

    func send(_ raw: String, entryTitle: String, entryText: String, settings: AppSettings) async {
        let question = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isThinking else { return }

        messages.append(Message(isUser: true, text: question))
        draft = ""
        isThinking = true
        notice = nil
        defer { isThinking = false }

        let service = OllamaService(baseURL: settings.ollamaBaseURL, model: settings.modelName)
        guard await service.isReachable() else {
            notice = "Ollama ist offline – starte den lokalen Server."
            return
        }

        let history = messages.dropLast().map { ChatTurn(isUser: $0.isUser, text: $0.text) }
        let prompt = LLMPromptTemplates.companionChat(
            entryTitle: entryTitle,
            entryText: entryText,
            history: Array(history),
            question: question,
            options: LLMPromptTemplates.PromptOptions(settings)
        )
        do {
            let reply = try await service.generate(prompt: prompt, json: false, temperature: 0.6)
            messages.append(Message(isUser: false, text: reply))
        } catch {
            notice = (error as? OllamaError)?.errorDescription ?? "Anfrage fehlgeschlagen."
        }
    }
}

/// The collapsible right-hand chat panel on the writing page.
struct CompanionChatPanel: View {
    @Bindable var chat: CompanionChat
    let entryTitle: String
    let entryText: String
    let settings: AppSettings
    var onClose: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if chat.messages.isEmpty { impulseSection }
                        conversationSection
                        if chat.isThinking { thinkingRow }
                        if let notice = chat.notice { noticeRow(notice) }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: chat.messages.count) {
                    if let last = chat.messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }
            Divider()
            inputBar
        }
        .background(Color.cardSurface)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.sage)
                .frame(width: 22, height: 22)
                .overlay(Image(systemName: "sparkles").font(.caption2).foregroundStyle(.white))
            Text("KI-Begleiter")
                .font(.callout.weight(.semibold))
            Spacer()
            Button {
                onClose()
            } label: {
                Image(systemName: "sidebar.right").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Begleiter ausblenden")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: - Sections

    private var impulseSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Impulse")
            ForEach(chat.impulses, id: \.self) { impulse in
                Button {
                    Task { await chat.send(impulse, entryTitle: entryTitle, entryText: entryText, settings: settings) }
                } label: {
                    Text(impulse)
                        .font(.callout)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color.appBackground, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.secondary.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .disabled(chat.isThinking)
            }
        }
    }

    private var conversationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !chat.messages.isEmpty {
                SectionLabel("Gespräch")
            }
            ForEach(chat.messages) { message in
                bubble(message).id(message.id)
            }
        }
    }

    private func bubble(_ message: CompanionChat.Message) -> some View {
        HStack {
            if message.isUser { Spacer(minLength: 24) }
            Text(message.text)
                .font(.callout)
                .foregroundStyle(message.isUser ? .white : .primary)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(
                    message.isUser ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.appBackground),
                    in: RoundedRectangle(cornerRadius: 12)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(message.isUser ? Color.clear : Color.secondary.opacity(0.12))
                )
            if !message.isUser { Spacer(minLength: 24) }
        }
    }

    private var thinkingRow: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("denkt nach …").font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
    }

    private func noticeRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.circle").foregroundStyle(.orange)
            Text(text).font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
    }

    // MARK: - Input

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Frag etwas …", text: $chat.draft)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Color.appBackground, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.secondary.opacity(0.15)))
                .onSubmit(sendDraft)

            Button(action: sendDraft) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(canSend ? Color.accentColor : Color.secondary.opacity(0.4)))
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
        }
        .padding(12)
    }

    private var canSend: Bool {
        !chat.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !chat.isThinking
    }

    private func sendDraft() {
        guard canSend else { return }
        Task { await chat.send(chat.draft, entryTitle: entryTitle, entryText: entryText, settings: settings) }
    }
}
