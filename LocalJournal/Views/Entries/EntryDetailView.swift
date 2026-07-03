import SwiftUI
import SwiftData

/// Read view for a single entry plus its structured AI analysis. Offers a
/// "re-analyse" action (useful for entries written while Ollama was offline).
struct EntryDetailView: View {
    let entry: JournalEntry

    @Environment(\.modelContext) private var context
    @Environment(AnalysisService.self) private var analysis
    @Environment(\.dismiss) private var dismiss

    @Query private var settingsList: [AppSettings]
    private var settings: AppSettings { settingsList.first ?? AppSettings() }

    @State private var showDeleteConfirm = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerCard
                entryTextCard
                if let analysis = entry.analysis, entry.analysisStatus == .completed {
                    analysisSection(analysis)
                } else {
                    analysisPlaceholder
                }
            }
            .padding(20)
        }
        .navigationTitle(entry.title.isEmpty ? "Eintrag" : entry.title)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    reanalyze()
                } label: {
                    if entry.analysisStatus == .running {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Neu analysieren", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .disabled(entry.analysisStatus == .running)

                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label("Löschen", systemImage: "trash")
                }
            }
        }
        .confirmationDialog("Diesen Eintrag löschen?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Löschen", role: .destructive) {
                context.delete(entry)
                try? context.save()
                dismiss()
            }
            Button("Abbrechen", role: .cancel) {}
        }
    }

    // MARK: - Cards

    private var headerCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.date.formatted(date: .complete, time: .omitted))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Label("\(entry.wordCount) Wörter", systemImage: "text.word.spacing")
                    if entry.writingSeconds > 0 {
                        Label(formattedDuration(entry.writingSeconds), systemImage: "timer")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            AnalysisStatusBadge(status: entry.analysisStatus)
        }
    }

    private var entryTextCard: some View {
        SectionCard(title: "Eintrag", systemImage: "doc.text") {
            Text(entry.text.isEmpty ? "(kein Text)" : entry.text)
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func analysisSection(_ analysis: EntryAnalysis) -> some View {
        if !analysis.summary.isEmpty {
            SectionCard(title: "Zusammenfassung", systemImage: "text.line.first.and.arrowtriangle.forward") {
                Text(analysis.summary)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }

        SectionCard(title: "Erkannte Signale", systemImage: "brain") {
            VStack(alignment: .leading, spacing: 14) {
                signal("Gefühle", analysis.feelings, image: "heart", tint: .pink)
                signal("Themen", analysis.topics, image: "tag", tint: .blue)
                signal("Personen", analysis.people, image: "person", tint: .purple)
                if analysis.feelings.isEmpty && analysis.topics.isEmpty && analysis.people.isEmpty {
                    Text("Keine Signale erkannt.")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                }
            }
        }

        if !analysis.keyInsights.isEmpty {
            SectionCard(title: "Erkenntnisse", systemImage: "sparkle") {
                ForEach(analysis.keyInsights, id: \.self) { insight in
                    Label(insight, systemImage: "checkmark.circle")
                        .font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }

        if !analysis.ideas.isEmpty {
            SectionCard(title: "Ideen", systemImage: "lightbulb") {
                ForEach(analysis.ideas, id: \.self) { idea in
                    Label(idea, systemImage: "lightbulb")
                        .font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }

        if !analysis.tasks.isEmpty {
            SectionCard(title: "Vorhaben", systemImage: "checklist") {
                ForEach(analysis.tasks, id: \.self) { task in
                    Label(task, systemImage: "circle")
                        .font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }

        if !analysis.patterns.isEmpty {
            SectionCard(title: "Muster & Trends", systemImage: "waveform.path.ecg") {
                ForEach(analysis.patterns, id: \.self) { pattern in
                    Label(pattern, systemImage: "arrow.triangle.branch")
                        .font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }

        if !analysis.comparisonWithLastWeek.isEmpty {
            SectionCard(title: "Vergleich: letzte 7 Tage", systemImage: "calendar.badge.clock") {
                Text(analysis.comparisonWithLastWeek)
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var analysisPlaceholder: some View {
        SectionCard(title: "KI-Analyse", systemImage: "brain") {
            switch entry.analysisStatus {
            case .running:
                Label("Analyse läuft …", systemImage: "arrow.triangle.2.circlepath")
                    .foregroundStyle(.secondary)
            case .pending, .notStarted:
                VStack(alignment: .leading, spacing: 10) {
                    Text("Für diesen Eintrag liegt noch keine Analyse vor.")
                        .foregroundStyle(.secondary)
                    Text("Starte sie, sobald dein lokales Ollama-Modell läuft.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Button("Jetzt analysieren") { reanalyze() }
                        .buttonStyle(.borderedProminent)
                }
            case .failed:
                VStack(alignment: .leading, spacing: 10) {
                    Label("Analyse fehlgeschlagen", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                    if let message = analysis.lastErrorMessage {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Button("Erneut versuchen") { reanalyze() }
                        .buttonStyle(.bordered)
                }
            case .completed:
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private func signal(_ title: String, _ items: [String], image: String, tint: Color) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                ChipsView(items: items, systemImage: image, tint: tint)
            }
        }
    }

    // MARK: - Actions

    private func reanalyze() {
        let captured = entry
        let currentSettings = settings
        Task { @MainActor in await analysis.analyze(captured, settings: currentSettings) }
    }

    private func formattedDuration(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let secs = seconds % 60
        if minutes > 0 { return "\(minutes) min \(secs) s" }
        return "\(secs) s"
    }
}
