import Charts
import SwiftUI
import TrackerCore
import UniformTypeIdentifiers

// Report views shared by the Mac and iOS screens.

/// The total, how much of it overlapping entries count twice, and the
/// running timer, which isn't included.
public struct ReportSummary: View {
    let report: Report
    let now: Timestamp
    let incomplete: Bool

    /// `incomplete` says some data files are still downloading or can't be
    /// read, so the totals may be missing entries.
    public init(report: Report, now: Timestamp, incomplete: Bool = false) {
        self.report = report
        self.now = now
        self.incomplete = incomplete
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(Format.duration(report.total))
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(detail)
                    .foregroundStyle(.secondary)
            }
            if report.doubleCounted > 0 {
                Label(
                    "Includes \(Format.duration(report.doubleCounted)) counted twice where entries overlap.",
                    systemImage: "exclamationmark.triangle"
                )
                .foregroundStyle(.orange)
            }
            if let running = report.running {
                Label(
                    "Running: \(Format.duration(running.duration(now: now))), not included",
                    systemImage: "record.circle"
                )
                .foregroundStyle(.secondary)
            }
            if incomplete {
                Label("Some data hasn't downloaded from iCloud or can't be read, so these totals may be incomplete.", systemImage: "icloud.slash")
                    .foregroundStyle(.orange)
            }
        }
    }

    private var detail: String {
        let entries = report.entries.count == 1 ? "1 entry" : "\(report.entries.count) entries"
        return "\(Format.hours(report.total)) hours in \(entries)"
    }
}

/// Hours per day, stacked by project in the projects' colors.
public struct ReportChart: View {
    let report: Report
    let ledger: Ledger

    public init(report: Report, ledger: Ledger) {
        self.report = report
        self.ledger = ledger
    }

    struct Bar: Identifiable {
        var date: Date
        var project: String
        var hours: Double

        var id: String { "\(date.timeIntervalSince1970) \(project)" }
    }

    public var body: some View {
        let data = chartData
        Chart(data.bars) { bar in
            BarMark(
                x: .value("Day", bar.date, unit: .day),
                y: .value("Hours", bar.hours)
            )
            .foregroundStyle(by: .value("Project", bar.project))
        }
        .chartForegroundStyleScale(domain: data.titles, range: data.colors)
        .chartXScale(domain: days)
        .chartYAxisLabel("Hours")
        .overlay {
            if data.bars.isEmpty {
                Text("No time logged")
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Every day in the range, including days without bars.
    private var days: ClosedRange<Date> {
        let calendar = Calendar.current
        let first = calendar.startOfDay(for: report.request.range.lowerBound.pickerDate)
        let last = calendar.startOfDay(for: report.request.range.upperBound.pickerDate)
        return first...(calendar.date(byAdding: .day, value: 1, to: last) ?? last)
    }

    /// The bars, and the projects' titles and colors, busiest first.
    private var chartData: (bars: [Bar], titles: [String], colors: [Color]) {
        var totals: [UUID?: Int64] = [:]
        for day in report.days {
            for (projectID, milliseconds) in day.projects {
                totals[projectID, default: 0] += milliseconds
            }
        }
        let order = totals.keys.sorted { a, b in
            totals[a, default: 0] != totals[b, default: 0]
                ? totals[a, default: 0] > totals[b, default: 0]
                : ledger.projectTitle(a) < ledger.projectTitle(b)
        }
        var titles: [String] = []
        var colors: [Color] = []
        for projectID in order where !titles.contains(ledger.projectTitle(projectID)) {
            titles.append(ledger.projectTitle(projectID))
            colors.append(ledger.color(ofProject: projectID))
        }
        var bars: [Bar] = []
        for day in report.days {
            for projectID in order {
                if let milliseconds = day.projects[projectID], milliseconds > 0 {
                    bars.append(Bar(
                        date: day.date.pickerDate,
                        project: ledger.projectTitle(projectID),
                        hours: Double(milliseconds) / 3_600_000
                    ))
                }
            }
        }
        return (bars, titles, colors)
    }
}

/// The report's groups, with a client's projects indented under it.
public struct ReportGroupList: View {
    let report: Report

    public init(report: Report) {
        self.report = report
    }

    public var body: some View {
        VStack(spacing: 0) {
            ForEach(report.groups) { group in
                ReportGroupRow(group: group, total: report.total, indented: false)
                ForEach(group.children) { child in
                    ReportGroupRow(group: child, total: report.total, indented: true)
                }
            }
        }
    }
}

struct ReportGroupRow: View {
    let group: ReportGroup
    let total: Int64
    let indented: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                if let color = group.color {
                    Circle()
                        .fill(Color(hex: color))
                        .frame(width: 8, height: 8)
                }
                Text(group.title)
                    .fontWeight(indented ? .regular : .medium)
                    .lineLimit(1)
                Spacer()
                Text(Format.duration(group.milliseconds))
                    .monospacedDigit()
                Text(Format.percent(group.milliseconds, of: total))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .trailing)
            }
            .padding(.leading, indented ? 22 : 0)
            .padding(.vertical, 7)
            Divider()
        }
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
#Preview("Report") {
    let week = LocalDate(year: 2026, month: 9, day: 21)...LocalDate(year: 2026, month: 9, day: 27)
    let report = Report(ReportRequest(range: week), ledger: PreviewData.ledger, now: PreviewData.now)
    return ScrollView {
        VStack(alignment: .leading, spacing: 20) {
            ReportSummary(report: report, now: PreviewData.now)
            ReportChart(report: report, ledger: PreviewData.ledger)
                .frame(height: 220)
            ReportGroupList(report: report)
        }
        .padding()
    }
    .frame(width: 640, height: 720)
}

#Preview("By Tag, Incomplete") {
    let week = LocalDate(year: 2026, month: 9, day: 21)...LocalDate(year: 2026, month: 9, day: 27)
    let report = Report(ReportRequest(range: week, grouping: .tag), ledger: PreviewData.ledger, now: PreviewData.now)
    return ScrollView {
        VStack(alignment: .leading, spacing: 20) {
            ReportSummary(report: report, now: PreviewData.now, incomplete: true)
            ReportChart(report: report, ledger: PreviewData.ledger)
                .frame(height: 220)
            ReportGroupList(report: report)
        }
        .padding()
    }
    .frame(width: 640, height: 720)
}
#endif
