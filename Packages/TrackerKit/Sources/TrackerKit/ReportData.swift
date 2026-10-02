import SwiftUI
import TrackerCore

// What a report's chart and breakdown show, worked out from the report.

/// A report's chart: a column for each day, or for each week or month of a
/// long range, stacked by project, the busiest at the bottom; the projects
/// for its legend; and the average day worked, for a line across the days.
public struct ReportChartData {
    /// What each column covers.
    public enum Unit: Sendable {
        case day, week, month

        /// The chart's heading.
        public var title: String {
            switch self {
            case .day: "Each Day"
            case .week: "Each Week"
            case .month: "Each Month"
            }
        }
    }

    public var unit: Unit
    public var columns: [ChartColumn]
    /// The projects in the chart, the busiest first, with their time.
    public var legend: [ChartColumn.Part]
    /// The average day worked, for a chart of days with more than one.
    public var average: Int64?

    /// Columns are days up to a month, weeks up to about four months, and
    /// months beyond. Weeks start on `firstWeekday`; the column with
    /// `today` stands out.
    public init(_ report: Report, ledger: Ledger, today: LocalDate, firstWeekday: Int) {
        let days = report.days
        let unit: Unit = days.count <= 31 ? .day : days.count <= 122 ? .week : .month
        self.unit = unit

        var totals: [UUID?: Int64] = [:]
        for day in days {
            for (projectID, milliseconds) in day.projects {
                totals[projectID, default: 0] += milliseconds
            }
        }
        let order = totals.keys.sorted { a, b in
            let (timeA, timeB) = (totals[a, default: 0], totals[b, default: 0])
            return timeA != timeB ? timeA > timeB : ledger.projectTitle(a) < ledger.projectTitle(b)
        }
        func part(_ projectID: UUID?, _ milliseconds: Int64) -> ChartColumn.Part {
            ChartColumn.Part(
                id: projectID?.uuidString ?? "",
                title: ledger.projectTitle(projectID),
                color: ledger.color(ofProject: projectID),
                milliseconds: milliseconds
            )
        }
        legend = order.map { part($0, totals[$0, default: 0]) }

        // The report's days are in order, so each column's days follow one
        // another.
        var buckets: [(key: LocalDate, days: [ReportDay])] = []
        for day in days {
            let key: LocalDate
            switch unit {
            case .day: key = day.date
            case .week: key = day.date.startOfWeek(firstWeekday: firstWeekday)
            case .month: key = LocalDate(year: day.date.year, month: day.date.month, day: 1)
            }
            if let last = buckets.last, last.key == key {
                buckets[buckets.count - 1].days.append(day)
            } else {
                buckets.append((key: key, days: [day]))
            }
        }
        let dayCount = days.count
        columns = buckets.map { bucket in
            var sums: [UUID?: Int64] = [:]
            for day in bucket.days {
                for (projectID, milliseconds) in day.projects {
                    sums[projectID, default: 0] += milliseconds
                }
            }
            let first = bucket.days.first?.date ?? bucket.key
            let last = bucket.days.last?.date ?? bucket.key
            let label: String
            let title: String
            switch unit {
            case .day:
                label = dayCount <= 7 ? Format.weekday(first) : "\(first.day)"
                title = Format.day(first)
            case .week:
                label = Format.monthDay(first)
                title = Format.days(first...last)
            case .month:
                label = Format.shortMonth(first)
                title = Format.month(first)
            }
            return ChartColumn(
                id: bucket.key.description,
                label: label,
                title: title,
                parts: order.compactMap { projectID in
                    guard let milliseconds = sums[projectID], milliseconds > 0 else { return nil }
                    return part(projectID, milliseconds)
                },
                isCurrent: (first...last).contains(today)
            )
        }
        average = unit == .day && report.daysWorked > 1 ? report.averagePerDayWorked : nil
    }
}

/// A line of a breakdown of time: a client, a project or a tag with its
/// time, and the bar for its share.
public struct BreakdownRow: Identifiable, Hashable {
    /// What the line starts with.
    public enum Mark: Hashable {
        /// Nothing, as for a tag.
        case blank
        /// A client's symbol.
        case client
        /// A project's dot in its color, or the ring of no project for nil.
        case project(color: String?)
    }

    /// The color of the line's bar.
    public enum Bar: Hashable {
        /// The accent color, as for a tag.
        case accent
        /// A stretch for each part, in a project's hex color, or gray for
        /// nil, such as a client's projects.
        case parts([Part])
    }

    /// Some of a bar: a project's color and time.
    public struct Part: Hashable {
        public var color: String?
        public var milliseconds: Int64

        public init(color: String?, milliseconds: Int64) {
            self.color = color
            self.milliseconds = milliseconds
        }
    }

    public var id: ReportGroup.Kind
    public var title: String
    public var mark: Mark
    public var milliseconds: Int64
    public var bar: Bar
    /// Whether it's a project under its client's line.
    public var isNested: Bool

    public init(id: ReportGroup.Kind, title: String, mark: Mark, milliseconds: Int64, bar: Bar, isNested: Bool = false) {
        self.id = id
        self.title = title
        self.mark = mark
        self.milliseconds = milliseconds
        self.bar = bar
        self.isNested = isNested
    }

    /// A report's groups as lines. Grouped by client, a client with one
    /// project is one line, such as "Acme › Website", or just the project
    /// for no client; a client with several has a line of its own, with a
    /// bar in their colors, over a line for each.
    public static func rows(of report: Report) -> [BreakdownRow] {
        var rows: [BreakdownRow] = []
        for group in report.groups {
            switch group.kind {
            case .client, .noClient:
                if group.children.count == 1, let project = group.children.first {
                    let title = group.kind == .noClient ? project.title : "\(group.title) › \(project.title)"
                    rows.append(projectRow(project, title: title, nested: false))
                } else {
                    let parts = group.children.map { Part(color: $0.color, milliseconds: $0.milliseconds) }
                    rows.append(BreakdownRow(id: group.kind, title: group.title, mark: .client, milliseconds: group.milliseconds, bar: .parts(parts)))
                    rows += group.children.map { projectRow($0, title: $0.title, nested: true) }
                }
            case .project, .unassigned:
                rows.append(projectRow(group, title: group.title, nested: false))
            case .tag:
                rows.append(BreakdownRow(id: group.kind, title: group.title, mark: .blank, milliseconds: group.milliseconds, bar: .accent))
            case .untagged:
                let gray = [Part(color: nil, milliseconds: group.milliseconds)]
                rows.append(BreakdownRow(id: group.kind, title: group.title, mark: .blank, milliseconds: group.milliseconds, bar: .parts(gray)))
            }
        }
        return rows
    }

    /// Lines for the time of some projects, or of the unassigned entries for
    /// nil, the most first, titled with their clients unless `withClients`
    /// is false. Projects without time are left out.
    public static func projects(_ times: [UUID?: Int64], ledger: Ledger, withClients: Bool = true) -> [BreakdownRow] {
        times
            .filter { $0.value > 0 }
            .sorted { a, b in
                a.value != b.value ? a.value > b.value : ledger.projectTitle(a.key) < ledger.projectTitle(b.key)
            }
            .map { projectID, milliseconds in
                let color = projectID.flatMap { ledger.projects[$0]?.color }
                let title = withClients || projectID == nil
                    ? ledger.projectTitle(projectID)
                    : projectID.flatMap { ledger.projects[$0]?.name } ?? ledger.projectTitle(projectID)
                return BreakdownRow(
                    id: projectID.map(ReportGroup.Kind.project) ?? .unassigned,
                    title: title,
                    mark: .project(color: color),
                    milliseconds: milliseconds,
                    bar: .parts([Part(color: color, milliseconds: milliseconds)])
                )
            }
    }

    private static func projectRow(_ group: ReportGroup, title: String, nested: Bool) -> BreakdownRow {
        BreakdownRow(
            id: group.kind,
            title: title,
            mark: .project(color: group.color),
            milliseconds: group.milliseconds,
            bar: .parts([Part(color: group.color, milliseconds: group.milliseconds)]),
            isNested: nested
        )
    }
}
