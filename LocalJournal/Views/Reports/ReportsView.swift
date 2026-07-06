import SwiftUI
import SwiftData

/// The **Berichte** section: weekly and monthly reports. Reports for completed
/// periods are generated automatically on launch; the two buttons here generate
/// a report for the *current* (in-progress) week or month on demand. Each report
/// opens a rich detail page.
struct ReportsView: View {
    /// Start a new entry preloaded with a reflective impulse (passed to detail).
    var onStartWriting: (String) -> Void = { _ in }

    @Environment(AnalysisService.self) private var analysis
    @Query(sort: \PeriodicReport.periodStart, order: .reverse) private var reports: [PeriodicReport]
    @Query private var settingsList: [AppSettings]

    @State private var filter: ReportFilter = .all
    @State private var generating: ReportKind?
    @State private var notice: String?

    private var settings: AppSettings { settingsList.first ?? AppSettings() }

    private var filtered: [PeriodicReport] {
        switch filter {
        case .all:     return reports
        case .weekly:  return reports.filter { $0.kind == .weekly }
        case .monthly: return reports.filter { $0.kind == .monthly }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                generateRow
                if let notice { noticeBanner(notice) }

                if !reports.isEmpty { filterPicker }

                if filtered.isEmpty {
                    emptyState
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(filtered) { report in
                            NavigationLink(value: report) {
                                ReportCard(report: report)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 1080, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.appBackground)
        .navigationTitle("Berichte")
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel("Rückblick")
            Text("Wochen- & Monatsberichte")
                .serif(32)
                .foregroundStyle(.primary)
            Text("Abgeschlossene Wochen und Monate werden automatisch zusammengefasst – lokal aus deinen Einträgen. Du kannst den laufenden Zeitraum jederzeit selbst erstellen.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var generateRow: some View {
        HStack(spacing: 12) {
            generateButton(.weekly, title: "Diese Woche")
            generateButton(.monthly, title: "Dieser Monat")
            Spacer()
        }
    }

    private func generateButton(_ kind: ReportKind, title: String) -> some View {
        Button {
            generate(kind)
        } label: {
            HStack(spacing: 8) {
                if generating == kind {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: kind.systemImage)
                }
                Text(title)
            }
            .font(.callout.weight(.medium))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.sage.opacity(0.16), in: Capsule())
            .foregroundStyle(Color.sage)
            .overlay(Capsule().strokeBorder(Color.sage.opacity(0.25)))
        }
        .buttonStyle(.plain)
        .disabled(generating != nil)
    }

    private func noticeBanner(_ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle").foregroundStyle(.secondary)
            Text(text).font(.callout).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(12)
        .background(Color.cardSurface, in: RoundedRectangle(cornerRadius: 12))
    }

    private var filterPicker: some View {
        Picker("Zeitraum", selection: $filter) {
            ForEach(ReportFilter.allCases) { option in
                Text(option.label).tag(option)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: 340)
    }

    private var emptyState: some View {
        PanelCard {
            EmptyHint(title: reports.isEmpty ? "Noch keine Berichte" : "Keine Berichte in dieser Ansicht",
                      systemImage: "doc.text.magnifyingglass",
                      message: reports.isEmpty
                        ? "Sobald eine Woche oder ein Monat abgeschlossen ist, entsteht hier automatisch ein Rückblick. Oder erstelle jetzt einen für den laufenden Zeitraum."
                        : "Wähle eine andere Ansicht oder erstelle einen neuen Bericht.")
        }
    }

    // MARK: - Actions

    private func generate(_ kind: ReportKind) {
        generating = kind
        notice = nil
        let currentSettings = settings
        Task { @MainActor in
            let report = await analysis.generateReport(kind: kind, reference: .now, settings: currentSettings)
            generating = nil
            if report == nil {
                notice = "Noch keine Einträge in \(kind == .weekly ? "dieser Woche" : "diesem Monat")."
            }
        }
    }
}

/// Filter over the report list.
private enum ReportFilter: String, CaseIterable, Identifiable {
    case all, weekly, monthly
    var id: String { rawValue }
    var label: String {
        switch self {
        case .all:     return "Alle"
        case .weekly:  return "Woche"
        case .monthly: return "Monat"
        }
    }
}

/// A summary card for one report in the list.
private struct ReportCard: View {
    let report: PeriodicReport

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label(report.kind.reportTitle, systemImage: report.kind.systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.sage)
                Spacer()
                Text(report.rangeText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if report.hasNarrative {
                Text(report.narrative)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Zusammenfassung ausstehend – Kennzahlen sind bereits da.")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .italic()
            }

            HStack(spacing: 14) {
                metaChip(systemImage: "book.closed", "\(report.entryCount) Einträge")
                if report.resilienceOverall > 0 {
                    metaChip(systemImage: "shield.lefthalf.filled", "Resilienz \(report.resilienceOverall)")
                }
                metaChip(systemImage: "calendar", "\(report.daysWritten) Tage")
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(18)
        .background(Color.cardSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.secondary.opacity(0.08)))
        .contentShape(Rectangle())
    }

    private func metaChip(systemImage: String, _ text: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
