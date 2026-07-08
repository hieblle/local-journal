import SwiftUI
import SwiftData
import AppKit

/// The **Notizen** section: import old note files (txt/md), let Gemma distill
/// them into lasting insights, and curate the result once — keep or discard.
/// Kept insights become the app's personal knowledge base (used by the upcoming
/// Resonanz feature on new entries).
struct NotesView: View {
    @Environment(\.modelContext) private var context

    @Query(sort: \NoteDocument.importedAt, order: .reverse) private var documents: [NoteDocument]
    @Query(sort: \NoteInsight.createdAt, order: .reverse) private var insights: [NoteInsight]
    @Query private var thoughts: [NoteThought]
    @Query private var settingsList: [AppSettings]

    @State private var service: NotesService?
    @State private var tab: NotesTab = .review
    @State private var searchText = ""

    private var settings: AppSettings { settingsList.first ?? AppSettings() }
    private var pending: [NoteInsight] { insights.filter { $0.status == .pending } }
    private var kept: [NoteInsight] { insights.filter { $0.status == .kept } }
    private var undistilledCount: Int { thoughts.filter { !$0.isDistilled }.count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                actionRow

                if let service, service.isDistilling || service.lastMessage != nil {
                    distillStatusCard(service)
                }

                if documents.isEmpty {
                    emptyState
                } else {
                    tabPicker
                    switch tab {
                    case .review: reviewSection
                    case .kept:   keptSection
                    case .files:  filesSection
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.appBackground)
        .navigationTitle("Notizen")
        .onAppear {
            if service == nil { service = NotesService(context: context) }
        }
    }

    // MARK: - Header + actions

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel("Wissensbasis")
            Text("Deine Notizen, destilliert")
                .serif(32)
            Text("Importiere alte Notizdateien (txt/md). Die lokale KI zieht daraus, was bleibenden Wert hat – Empfehlungen, Learnings, Grundsätze. Du prüfst einmal, der Rest bleibt als durchsuchbarer Rohtext erhalten.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var actionRow: some View {
        HStack(spacing: 12) {
            Button {
                importNotes()
            } label: {
                Label("Notizen importieren …", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)

            if undistilledCount > 0 {
                if service?.isDistilling == true {
                    Button {
                        service?.stopDistilling()
                    } label: {
                        Label("Pausieren", systemImage: "pause.circle")
                    }
                } else {
                    Button {
                        startDistilling()
                    } label: {
                        Label("Destillieren (\(undistilledCount) Gedanken)", systemImage: "wand.and.stars")
                    }
                }
            }
            Spacer()
        }
    }

    private func distillStatusCard(_ service: NotesService) -> some View {
        HStack(spacing: 12) {
            if service.isDistilling {
                ProgressView(value: service.batchesTotal == 0 ? 0
                             : Double(service.batchesDone) / Double(service.batchesTotal))
                    .frame(maxWidth: 220)
                Text("Batch \(service.batchesDone)/\(service.batchesTotal) · \(service.foundThisRun) Erkenntnisse")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            } else if let message = service.lastMessage {
                Image(systemName: "info.circle").foregroundStyle(.secondary)
                Text(message).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(Color.cardSurface, in: RoundedRectangle(cornerRadius: 12))
    }

    private var emptyState: some View {
        PanelCard {
            EmptyHint(title: "Noch keine Notizen importiert",
                      systemImage: "note.text",
                      message: "Sammle deine txt-/md-Dateien in einem Ordner und importiere sie – Unterordner werden mitgelesen. Identische Dateien werden automatisch übersprungen.")
        }
    }

    private var tabPicker: some View {
        Picker("Bereich", selection: $tab) {
            Text("Prüfen (\(pending.count))").tag(NotesTab.review)
            Text("Behalten (\(kept.count))").tag(NotesTab.kept)
            Text("Dateien (\(documents.count))").tag(NotesTab.files)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: 420)
    }

    // MARK: - Review tab

    @ViewBuilder
    private var reviewSection: some View {
        if pending.isEmpty {
            PanelCard {
                EmptyHint(title: "Nichts zu prüfen",
                          systemImage: "checkmark.circle",
                          message: undistilledCount > 0
                            ? "Starte die Destillation, um neue Erkenntnisse aus den importierten Gedanken zu ziehen."
                            : "Alle Erkenntnisse sind kuratiert.")
            }
        } else {
            HStack {
                Text("Einmal durchgehen: Behalten wird Teil deiner Wissensbasis.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Alle behalten") {
                    for insight in pending { insight.status = .kept }
                    try? context.save()
                }
                .buttonStyle(.link)
            }
            LazyVStack(spacing: 10) {
                ForEach(pending) { insight in
                    ReviewCard(insight: insight,
                               onKeep: { setStatus(insight, .kept) },
                               onDiscard: { setStatus(insight, .discarded) })
                }
            }
        }
    }

    // MARK: - Kept tab

    @ViewBuilder
    private var keptSection: some View {
        if kept.isEmpty {
            PanelCard {
                EmptyHint(title: "Noch nichts behalten",
                          systemImage: "tray",
                          message: "Erkenntnisse, die du beim Prüfen behältst, landen hier.")
            }
        } else {
            TextField("Durchsuchen …", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 320)
            LazyVStack(spacing: 10) {
                ForEach(filteredKept) { insight in
                    KeptCard(insight: insight,
                             onDiscard: { setStatus(insight, .discarded) })
                }
            }
        }
    }

    private var filteredKept: [NoteInsight] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return kept }
        return kept.filter {
            $0.text.lowercased().contains(query)
                || $0.topics.contains { $0.lowercased().contains(query) }
                || $0.sourceText.lowercased().contains(query)
        }
    }

    // MARK: - Files tab

    private var filesSection: some View {
        LazyVStack(spacing: 10) {
            ForEach(documents) { document in
                HStack(spacing: 12) {
                    Image(systemName: "doc.text")
                        .foregroundStyle(Color.sage)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(document.title)
                            .font(.callout.weight(.medium))
                        Text("\(document.thoughts.count) Gedanken · \(document.thoughts.filter(\.isDistilled).count) destilliert · importiert \(document.importedAt.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(role: .destructive) {
                        context.delete(document)   // cascades thoughts; kept insights survive
                        try? context.save()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Datei samt Gedanken entfernen (behaltene Erkenntnisse bleiben)")
                }
                .padding(14)
                .background(Color.cardSurface, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    // MARK: - Actions

    private func setStatus(_ insight: NoteInsight, _ status: NoteInsightStatus) {
        withAnimation(.snappy) { insight.status = status }
        try? context.save()
    }

    private func importNotes() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Importieren"
        panel.message = "Notizdateien (txt/md) oder Ordner auswählen"
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        _ = service?.importFiles(at: panel.urls)
        tab = .review
    }

    private func startDistilling() {
        guard let service else { return }
        let currentSettings = settings
        Task { @MainActor in
            await service.distillPending(settings: currentSettings)
        }
    }
}

private enum NotesTab: Hashable {
    case review, kept, files
}

// MARK: - Cards

/// One pending insight with keep / discard controls and its provenance.
private struct ReviewCard: View {
    let insight: NoteInsight
    var onKeep: () -> Void
    var onDiscard: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                KindChip(kind: insight.kind)
                Spacer()
                if !insight.sourceDocumentName.isEmpty {
                    Text(insight.sourceDocumentName)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Text(insight.text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)

            if !insight.sourceText.isEmpty, insight.sourceText != insight.text {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "quote.opening")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(insight.sourceText)
                        .font(.caption)
                        .italic()
                        .foregroundStyle(.tertiary)
                        .lineLimit(3)
                }
            }

            HStack(spacing: 10) {
                Button {
                    onKeep()
                } label: {
                    Label("Behalten", systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button {
                    onDiscard()
                } label: {
                    Label("Verwerfen", systemImage: "xmark")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()
            }
        }
        .padding(16)
        .background(Color.cardSurface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.secondary.opacity(0.08)))
    }
}

/// One kept insight (read view + remove).
private struct KeptCard: View {
    let insight: NoteInsight
    var onDiscard: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: insight.kind.systemImage)
                .foregroundStyle(insight.kind.tint)
                .frame(width: 20)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(insight.text)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Text(insight.kind.label)
                        .font(.caption2)
                        .foregroundStyle(insight.kind.tint)
                    if !insight.sourceDocumentName.isEmpty {
                        Text("· \(insight.sourceDocumentName)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            Spacer()
            Button(role: .destructive) {
                onDiscard()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Aus der Wissensbasis entfernen")
        }
        .padding(14)
        .background(Color.cardSurface, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct KindChip: View {
    let kind: NoteInsightKind

    var body: some View {
        Label(kind.label, systemImage: kind.systemImage)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(kind.tint.opacity(0.14), in: Capsule())
            .foregroundStyle(kind.tint)
    }
}

extension NoteInsightKind {
    var tint: Color {
        switch self {
        case .recommendation: return .sage
        case .learning:       return .blue
        case .principle:      return .purple
        case .idea:           return .orange
        }
    }
}
