import SwiftUI
import TrackerCore
import UniformTypeIdentifiers

// Report views shared by the Mac and iOS screens.

/// A report's figures: its total, its average day worked, how many days
/// had time logged, and the change from the period before; then what the
/// total leaves out or counts twice. A report of one day shows its entries
/// and when its work started and ended in place of the average and the
/// days.
public struct ReportSummary: View {
    let report: Report
    let comparison: ReportComparison
    let period: ReportPeriod
    let now: Timestamp
    let incomplete: Bool

    /// `incomplete` says some data files are still downloading or can't be
    /// read, so the totals may be missing entries.
    public init(report: Report, comparison: ReportComparison, period: ReportPeriod, now: Timestamp, incomplete: Bool = false) {
        self.report = report
        self.comparison = comparison
        self.period = period
        self.now = now
        self.incomplete = incomplete
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // In a row where they fit, otherwise two by two.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    totalTile
                    firstMiddleTile
                    secondMiddleTile
                    changeTile
                }
                .fixedSize(horizontal: false, vertical: true)
                Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                    GridRow {
                        totalTile
                        firstMiddleTile
                    }
                    GridRow {
                        secondMiddleTile
                        changeTile
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            notices
        }
    }

    private var isOneDay: Bool {
        report.days.count == 1
    }

    private var totalTile: some View {
        FigureTile("Total", detail: report.entries.count == 1 ? "1 entry" : "\(report.entries.count) entries") {
            DurationText(report.total, size: 30)
        }
    }

    /// The average day, or for a day its entries.
    @ViewBuilder
    private var firstMiddleTile: some View {
        if isOneDay {
            FigureTile("Entries", detail: report.daysWorked == 0 ? "No time logged" : nil) {
                FigureText("\(report.entries.count)")
            }
        } else {
            FigureTile("Daily Average", detail: "On days worked") {
                DurationText(report.averagePerDayWorked)
            }
        }
    }

    /// The days worked, or for a day when its work started and ended.
    @ViewBuilder
    private var secondMiddleTile: some View {
        if isOneDay {
            FigureTile("Workday", detail: "First start to last end") {
                FigureText(workday ?? "—")
            }
        } else {
            FigureTile("Days Worked", detail: "Out of \(report.days.count)") {
                FigureText("\(report.daysWorked)")
            }
        }
    }

    /// When the first entry started and the last one ended, each in its own
    /// time zone, such as "9:00 – 17:30"; nil without entries.
    private var workday: String? {
        guard let first = report.entries.first,
              let last = report.entries.max(by: { ($0.end ?? $0.start) < ($1.end ?? $1.start) }),
              let end = last.end
        else { return nil }
        return "\(Format.time(first.start, zone: first.entry.timeZone)) – \(Format.time(end, zone: last.entry.timeZone))"
    }

    private var changeTile: some View {
        FigureTile(changeTitle, detail: "\(Format.duration(comparison.previousTotal)) in \(Format.days(comparison.previousRange))") {
            FigureText(changeText)
        }
        .help(comparison.isPartial
            ? "Compared with as many days at the start of the period before, since this one isn't over yet"
            : "Compared with the period before, with the same filters")
    }

    /// Which period the change is from.
    private var changeTitle: String {
        switch (period, comparison.isPartial) {
        case (.day, _): "vs. Previous Day"
        case (.week, false): "vs. Previous Week"
        case (.week, true): "vs. Same Days Last Week"
        case (.month, false): "vs. Previous Month"
        case (.month, true): "vs. Same Days Last Month"
        case (.custom, _):
            "vs. Previous \(comparison.previousRange.upperBound.daysSince1970 - comparison.previousRange.lowerBound.daysSince1970 + 1) Days"
        }
    }

    /// Such as "+12%" or "−8%", or a dash when nothing was logged before.
    private var changeText: String {
        guard let percent = comparison.percent else { return "—" }
        return percent > 0 ? "+\(percent)%" : percent < 0 ? "\u{2212}\(-percent)%" : "0%"
    }

    /// What the total leaves out or counts twice, and whether it may be
    /// missing entries.
    @ViewBuilder
    private var notices: some View {
        VStack(alignment: .leading, spacing: 6) {
            if report.doubleCounted > 0 {
                Label(
                    "Includes \(Format.duration(report.doubleCounted)) counted twice where entries overlap.",
                    systemImage: "exclamationmark.triangle"
                )
                .foregroundStyle(.orange)
            }
            if let running = report.running {
                // The running timer's red mark, as wherever entries are listed.
                Label {
                    Text("Running: \(Format.duration(running.duration(now: now))), not included")
                } icon: {
                    RunningIcon()
                }
                .foregroundStyle(.secondary)
            }
            if incomplete {
                Label("Some data hasn't downloaded from iCloud or can't be read, so these totals may be incomplete.", systemImage: "icloud.slash")
                    .foregroundStyle(.orange)
            }
        }
        .font(.callout)
    }
}

/// A report's time on a chart: a column for each day, stacked by project in
/// the projects' colors, with each day's total over it and a dashed line at
/// the average day worked; for a long range, a column for each week or
/// month. The projects are named under it.
public struct ReportChart: View {
    let data: ReportChartData
    let height: CGFloat

    /// Weeks start on `firstWeekday`, and the column with `today` stands
    /// out.
    public init(report: Report, ledger: Ledger, today: LocalDate, firstWeekday: Int, height: CGFloat = 170) {
        data = ReportChartData(report, ledger: ledger, today: today, firstWeekday: firstWeekday)
        self.height = height
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(data.unit.title)
                .font(.headline)
            BarChart(columns: data.columns, average: data.average, height: height)
                .overlay {
                    if data.legend.isEmpty {
                        Text("No time logged")
                            .foregroundStyle(.secondary)
                    }
                }
            if !data.legend.isEmpty {
                ChartLegend(parts: data.legend)
            }
        }
    }
}

/// Lines of time by client, project or tag, each with its share of the
/// total and a bar for it, such as a report's groups. A client with
/// several projects has a bar in their colors, and its projects under it.
public struct ReportBreakdown: View {
    /// Where the bars go.
    public enum Style {
        /// Beside the names, in a column of their own, so they compare at a
        /// glance.
        case inline
        /// Under the names, for a narrow screen.
        case stacked
    }

    let rows: [BreakdownRow]
    let total: Int64
    let style: Style
    @ScaledMetric private var indent: CGFloat = 22
    @ScaledMetric private var markWidth: CGFloat = 14
    @ScaledMetric private var percentWidth: CGFloat = 40
    /// The names' column, beside the bars; a longer name is shortened.
    @ScaledMetric private var titleWidth: CGFloat = 240

    public init(report: Report, style: Style = .inline) {
        self.init(rows: BreakdownRow.rows(of: report), total: report.total, style: style)
    }

    /// `total` is what the shares are of.
    public init(rows: [BreakdownRow], total: Int64, style: Style = .inline) {
        self.rows = rows
        self.total = total
        self.style = style
    }

    public var body: some View {
        switch style {
        case .inline:
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
                ForEach(rows) { row in
                    GridRow {
                        title(row)
                            .padding(.leading, row.isNested ? indent : 0)
                            .frame(width: titleWidth, alignment: .leading)
                        bar(row)
                            .frame(minWidth: 60)
                        duration(row)
                            .gridColumnAlignment(.trailing)
                        percent(row)
                            .gridColumnAlignment(.trailing)
                    }
                }
            }
        case .stacked:
            VStack(alignment: .leading, spacing: 14) {
                ForEach(rows) { row in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            title(row)
                            Spacer(minLength: 8)
                            duration(row)
                            percent(row)
                                .frame(minWidth: percentWidth, alignment: .trailing)
                        }
                        bar(row)
                    }
                    .padding(.leading, row.isNested ? indent : 0)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func title(_ row: BreakdownRow) -> some View {
        HStack(spacing: 8) {
            switch row.mark {
            case .blank:
                EmptyView()
            case .client:
                Image(systemName: "briefcase")
                    .imageScale(.small)
                    .foregroundStyle(.secondary)
                    .frame(width: markWidth)
                    .accessibilityHidden(true)
            case .project(let color):
                ProjectDot(color: color.map { Color(hex: $0) })
                    .frame(width: markWidth)
            }
            Text(row.title)
                .fontWeight(row.isNested ? .regular : .medium)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    @ViewBuilder
    private func bar(_ row: BreakdownRow) -> some View {
        switch row.bar {
        case .accent:
            ShareBar(row.milliseconds, of: total, color: .accentColor)
        case .parts(let parts):
            ShareBar(
                parts: parts.map { ShareBar.Part(color: $0.color.map { Color(hex: $0) } ?? .gray, value: $0.milliseconds) },
                of: total
            )
        }
    }

    private func duration(_ row: BreakdownRow) -> some View {
        Text(Format.duration(row.milliseconds))
            .fontWeight(row.isNested ? .regular : .semibold)
            .monospacedDigit()
            .lineLimit(1)
    }

    private func percent(_ row: BreakdownRow) -> some View {
        Text(Format.percent(row.milliseconds, of: total))
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
}

/// What some entries add up to, for an inspector with nothing selected in
/// it, such as the days the timeline shows: their total and how many there
/// are, their time by project with a bar for each, and a hint at what to
/// do. The running timer counts as far as it has run.
public struct PeriodSummary: View {
    let title: String
    let entries: [ResolvedEntry]
    let ledger: Ledger
    let now: Timestamp
    let hint: String

    /// `title` names the entries, such as their days.
    public init(title: String, entries: [ResolvedEntry], ledger: Ledger, now: Timestamp, hint: String) {
        self.title = title
        self.entries = entries
        self.ledger = ledger
        self.now = now
        self.hint = hint
    }

    public var body: some View {
        let times = self.times
        let total = times.values.reduce(0, +)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                    DurationText(total, size: 34)
                    Text(entries.count == 1 ? "1 entry" : "\(entries.count.formatted()) entries")
                        .foregroundStyle(.secondary)
                    if entries.contains(where: \.isRunning) {
                        Label {
                            Text("With the running timer")
                        } icon: {
                            RunningIcon()
                        }
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    }
                }
                if total > 0 {
                    ReportBreakdown(rows: BreakdownRow.projects(times, ledger: ledger), total: total, style: .stacked)
                }
                Text(hint)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Each project's time, nil's for the unassigned entries.
    private var times: [UUID?: Int64] {
        var times: [UUID?: Int64] = [:]
        for entry in entries {
            times[entry.entry.projectID, default: 0] += entry.duration(now: now)
        }
        return times
    }
}

/// A CSV file for the save dialog.
public struct CSVDocument: FileDocument {
    public static var readableContentTypes: [UTType] { [.commaSeparatedText] }

    public var data: Data

    public init(data: Data) {
        self.data = data
    }

    public init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    public func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// A CSV file for the share sheet.
public struct CSVFile: Transferable {
    public var data: Data

    public init(data: Data) {
        self.data = data
    }

    public static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .commaSeparatedText) { file in
            file.data
        }
        .suggestedFileName("Time Report.csv")
    }
}

#if DEBUG
/// A report of the sample data's week, or another ledger's, with what the
/// report views need around it, for previews.
struct PreviewReport {
    let report: Report
    let comparison: ReportComparison
    let ledger: Ledger
    let period: ReportPeriod

    init(
        _ ledger: Ledger = PreviewData.ledger,
        period: ReportPeriod = .week,
        grouping: ReportRequest.Grouping = .client
    ) {
        let today = PreviewData.now.local(in: "Europe/Berlin").date
        let range = period.range(containing: today, firstWeekday: 2)
        let request = ReportRequest(range: range, grouping: grouping)
        let resolved = ledger.resolvedEntries()
        report = Report(request, ledger: ledger, resolved: resolved, now: PreviewData.now)
        comparison = ReportComparison(report, period: period, today: today, firstWeekday: 2, ledger: ledger, resolved: resolved, now: PreviewData.now)
        self.ledger = ledger
        self.period = period
    }

    /// The summary, the chart and the breakdown, as a report screen shows
    /// them.
    func page(style: ReportBreakdown.Style = .inline, incomplete: Bool = false) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ReportSummary(report: report, comparison: comparison, period: period, now: PreviewData.now, incomplete: incomplete)
                ReportChart(report: report, ledger: ledger, today: PreviewData.now.local(in: "Europe/Berlin").date, firstWeekday: 2)
                    .card()
                ReportBreakdown(report: report, style: style)
                    .card()
            }
            .padding()
        }
    }
}

#Preview("Week") {
    PreviewReport().page()
        .frame(width: 900, height: 820)
}

#Preview("A Freelancer's Week") {
    PreviewReport(PreviewData.ownerLedger).page()
        .frame(width: 900, height: 760)
}

#Preview("A Freelancer's Month by Tag") {
    PreviewReport(PreviewData.ownerLedger, period: .month, grouping: .tag).page()
        .frame(width: 900, height: 1100)
}

#Preview("By Project, Incomplete") {
    PreviewReport(grouping: .project).page(incomplete: true)
        .frame(width: 900, height: 820)
}

#Preview("A Day") {
    PreviewReport(period: .day).page()
        .frame(width: 900, height: 560)
}

#Preview("Narrow") {
    PreviewReport(PreviewData.ownerLedger).page(style: .stacked)
        .frame(width: 380, height: 900)
}

#Preview("No Time") {
    PreviewReport(Ledger()).page()
        .frame(width: 900, height: 640)
}

#Preview("Summary of a Week") {
    let week = LocalDate(year: 2026, month: 9, day: 21)...LocalDate(year: 2026, month: 9, day: 27)
    let entries = PreviewData.ledger.resolvedEntries().filter { week.contains($0.entry.day) }
    return PeriodSummary(
        title: Format.days(week),
        entries: entries,
        ledger: PreviewData.ledger,
        now: PreviewData.now,
        hint: "Select an entry to edit it."
    )
    .frame(width: 300, height: 560)
}
#endif
