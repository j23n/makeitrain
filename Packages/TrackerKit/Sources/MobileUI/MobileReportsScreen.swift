#if os(iOS)
import SwiftUI
import TrackerCore
import TrackerKit

/// Totals for a day, week or month: the figures, the time of each day on a
/// chart, and the time by client, project or tag with a bar for each, and
/// the CSV to share.
struct MobileReportsScreen: View {
    let model: AppModel
    @State private var period = ReportPeriod.week
    /// The days shown, or nil for the period containing today.
    @State private var range: ClosedRange<LocalDate>?
    @State private var grouping = ReportRequest.Grouping.client

    var body: some View {
        let report = Report(
            ReportRequest(range: currentRange, grouping: grouping),
            ledger: model.ledger,
            resolved: model.resolved,
            now: model.now
        )
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Picker("Period", selection: periodBinding) {
                        Text("Day").tag(ReportPeriod.day)
                        Text("Week").tag(ReportPeriod.week)
                        Text("Month").tag(ReportPeriod.month)
                    }
                    .pickerStyle(.segmented)

                    // The arrows are as big as a finger; the title goes back
                    // to the period containing today.
                    HStack {
                        Button {
                            range = period.shift(currentRange, by: -1, firstWeekday: model.firstWeekday)
                        } label: {
                            Label("Previous", systemImage: "chevron.left")
                                .labelStyle(.iconOnly)
                                .frame(minWidth: 44, minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        Spacer()
                        Button(Format.days(currentRange)) {
                            range = nil
                        }
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .accessibilityHint(Text("Shows the current \(period.rawValue)"))
                        Spacer()
                        Button {
                            range = period.shift(currentRange, by: 1, firstWeekday: model.firstWeekday)
                        } label: {
                            Label("Next", systemImage: "chevron.right")
                                .labelStyle(.iconOnly)
                                .frame(minWidth: 44, minHeight: 44)
                                .contentShape(Rectangle())
                        }
                    }

                    ReportSummary(
                        report: report,
                        comparison: ReportComparison(
                            report,
                            period: period,
                            today: model.today,
                            firstWeekday: model.firstWeekday,
                            ledger: model.ledger,
                            resolved: model.resolved,
                            now: model.now
                        ),
                        period: period,
                        now: model.now,
                        incomplete: model.missingFiles > 0 || !model.issues.isEmpty
                    )
                    if report.days.count > 1 {
                        ReportChart(report: report, ledger: model.ledger, today: model.today, firstWeekday: model.firstWeekday, height: 150)
                            .card()
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        Picker("Group by", selection: $grouping) {
                            Text("Client").tag(ReportRequest.Grouping.client)
                            Text("Project").tag(ReportRequest.Grouping.project)
                            Text("Tag").tag(ReportRequest.Grouping.tag)
                        }
                        .pickerStyle(.segmented)
                        if report.groups.isEmpty {
                            Text("No time logged on these days.")
                                .foregroundStyle(.secondary)
                        } else {
                            ReportBreakdown(report: report, style: .stacked)
                        }
                    }
                    .card()
                }
                .padding()
            }
            .navigationTitle("Reports")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(
                        item: CSVFile(data: CSVExport.data(for: report, ledger: model.ledger)),
                        preview: SharePreview("Time Report \(currentRange.lowerBound) to \(currentRange.upperBound)")
                    ) {
                        Label("Export CSV", systemImage: "square.and.arrow.up")
                    }
                    .disabled(report.entries.isEmpty)
                }
            }
        }
    }

    private var currentRange: ClosedRange<LocalDate> {
        range ?? period.range(containing: model.today, firstWeekday: model.firstWeekday)
    }

    private var periodBinding: Binding<ReportPeriod> {
        Binding(
            get: { period },
            set: { newPeriod in
                let shown = currentRange
                period = newPeriod
                range = shown.contains(model.today)
                    ? nil
                    : newPeriod.range(containing: shown.lowerBound, firstWeekday: model.firstWeekday)
            }
        )
    }
}

#if DEBUG
#Preview("This Week") {
    MobileReportsScreen(model: PreviewData.model())
}

#Preview("A Freelancer's Week") {
    MobileReportsScreen(model: PreviewData.model(PreviewData.ownerLedger))
}

#Preview("No Entries") {
    MobileReportsScreen(model: PreviewData.model(Ledger()))
}
#endif
#endif
