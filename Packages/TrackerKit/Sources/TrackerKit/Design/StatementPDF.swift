import CoreGraphics
import SwiftUI
import TrackerCore

/// A report as a PDF statement to send: who and when, the total, the time
/// by project and by tag, and every entry, on A4 pages in print colors.
public enum StatementPDF {
    static let page = CGSize(width: 595, height: 842)
    static let rowsOnFirstPage = 22
    static let rowsPerPage = 38

    /// The PDF of a report, titled for the client or projects it covers.
    @MainActor
    public static func data(for report: Report, ledger: Ledger, title: String) -> Data {
        let entries = report.entries
        var pages: [[ResolvedEntry]] = [Array(entries.prefix(rowsOnFirstPage))]
        var rest = Array(entries.dropFirst(rowsOnFirstPage))
        while !rest.isEmpty {
            pages.append(Array(rest.prefix(rowsPerPage)))
            rest = Array(rest.dropFirst(rowsPerPage))
        }
        let data = NSMutableData()
        var box = CGRect(origin: .zero, size: page)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &box, nil)
        else { return Data() }
        for (index, rows) in pages.enumerated() {
            let view = StatementPage(
                report: report,
                ledger: ledger,
                title: title,
                rows: rows,
                isFirst: index == 0,
                number: index + 1,
                count: pages.count
            )
            .frame(width: page.width, height: page.height)
            let renderer = ImageRenderer(content: view)
            context.beginPDFPage(nil)
            renderer.render { _, draw in
                draw(context)
            }
            context.endPDFPage()
        }
        context.closePDF()
        return data as Data
    }

    /// The file name for a statement, such as "Acme 2026-09-01 to
    /// 2026-09-30.pdf".
    public static func fileName(for report: Report, title: String) -> String {
        let range = report.request.range
        let days = range.lowerBound == range.upperBound ? "\(range.lowerBound)" : "\(range.lowerBound) to \(range.upperBound)"
        return "\(title) \(days).pdf"
    }
}

/// One page of a statement.
struct StatementPage: View {
    let report: Report
    let ledger: Ledger
    let title: String
    let rows: [ResolvedEntry]
    let isFirst: Bool
    let number: Int
    let count: Int

    private let ink = Color(red: 0.08, green: 0.09, blue: 0.11)
    private let gray = Color(red: 0.4, green: 0.43, blue: 0.48)
    private let rule = Color(red: 0.85, green: 0.86, blue: 0.88)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isFirst {
                header
                    .padding(.bottom, 22)
                breakdown
                    .padding(.bottom, 22)
            }
            entriesTable
            Spacer(minLength: 0)
            HStack {
                Text("\(title) · \(Format.days(report.request.range))")
                Spacer()
                Text("Page \(number) of \(count)")
            }
            .font(.system(size: 8))
            .foregroundStyle(gray)
        }
        .padding(.horizontal, 48)
        .padding(.vertical, 44)
        .frame(width: StatementPDF.page.width, height: StatementPDF.page.height, alignment: .topLeading)
        .background(Color.white)
        .foregroundStyle(ink)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 22, weight: .semibold))
            Text(Format.days(report.request.range))
                .font(.system(size: 12))
                .foregroundStyle(gray)
            HStack(alignment: .firstTextBaseline, spacing: 24) {
                figure("Total", Format.duration(report.total))
                figure("Entries", "\(report.entries.count)")
                figure("Days worked", "\(report.daysWorked)")
                figure("Average day", Format.duration(report.averagePerDayWorked))
            }
            .padding(.top, 12)
            if report.doubleCounted > 0 {
                Text("\(Format.duration(report.doubleCounted)) of the total is counted twice, where entries overlap.")
                    .font(.system(size: 9))
                    .foregroundStyle(gray)
                    .padding(.top, 4)
            }
        }
    }

    private func figure(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(gray)
            Text(value)
                .font(.system(size: 16, weight: .medium))
                .monospacedDigit()
        }
    }

    /// The time by project, or by tag when the report is grouped so.
    private var breakdown: some View {
        let groups = report.groups.flatMap { group in group.children.isEmpty ? [group] : group.children }
        return VStack(alignment: .leading, spacing: 4) {
            Text(report.request.grouping == .tag ? "By tag" : "By project")
                .font(.system(size: 10, weight: .semibold))
                .padding(.bottom, 2)
            ForEach(Array(groups.prefix(12).enumerated()), id: \.offset) { _, group in
                HStack {
                    Text(group.title)
                    Spacer()
                    Text(Format.duration(group.milliseconds))
                        .monospacedDigit()
                    Text(Format.percent(group.milliseconds, of: report.total))
                        .monospacedDigit()
                        .foregroundStyle(gray)
                        .frame(width: 36, alignment: .trailing)
                }
                .font(.system(size: 10))
                Rectangle().fill(rule).frame(height: 0.5)
            }
        }
    }

    private var entriesTable: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("Date").frame(width: 62, alignment: .leading)
                Text("Time").frame(width: 72, alignment: .leading)
                Text("Project").frame(width: 110, alignment: .leading)
                Text("Note")
                Spacer()
                Text("Hours").frame(width: 40, alignment: .trailing)
            }
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(gray)
            .padding(.bottom, 4)
            ForEach(rows) { entry in
                let zone = entry.entry.timeZone
                HStack(spacing: 8) {
                    Text(Format.monthDay(entry.entry.day)).frame(width: 62, alignment: .leading)
                    Text(Format.span(entry.start, entry.end, zone: zone))
                        .frame(width: 72, alignment: .leading)
                    Text(entry.entry.projectID.flatMap { ledger.projects[$0]?.name } ?? "Unassigned")
                        .frame(width: 110, alignment: .leading)
                    Text(([entry.entry.note] + entry.entry.tags).filter { !$0.isEmpty }.joined(separator: " · "))
                    Spacer(minLength: 4)
                    Text(String(format: "%.2f", Double(entry.length) / 3_600_000))
                        .frame(width: 40, alignment: .trailing)
                }
                .font(.system(size: 9))
                .monospacedDigit()
                .lineLimit(1)
                .padding(.vertical, 3.5)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(rule).frame(height: 0.5)
                }
            }
        }
    }
}
