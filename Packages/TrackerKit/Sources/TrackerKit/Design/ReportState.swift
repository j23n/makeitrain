import Foundation
import Observation
import TrackerCore

/// A report as the month and year screens show it: which clients, projects
/// and tags, which days, and how it's grouped, with what that adds up to.
/// What it adds up to is worked out when a screen first reads it, and again
/// only after one of those or the data changed.
@MainActor
@Observable
public final class ReportState {
    public let model: AppModel
    public private(set) var range: ClosedRange<LocalDate>
    /// How the range steps and compares: a day, week, month, or custom.
    public private(set) var period: ReportPeriod
    public var grouping: ReportRequest.Grouping = .project
    /// Clients to include, or all when empty.
    public var clients: Set<UUID> = []
    /// Projects to include, or all when empty.
    public var projects: Set<UUID> = []
    /// Tags to include, or all when empty.
    public var tags: Set<String> = []

    /// The report and its comparison as last worked out, and what for.
    @ObservationIgnored private var figuresCache: (key: FiguresKey, report: Report, comparison: ReportComparison)? = nil
    /// The days' totals and overlaps as last worked out, and what for.
    @ObservationIgnored private var dailyCache: (key: DailyKey, totals: DayTotals, overlapDays: Set<LocalDate>)? = nil

    /// What the report and its comparison depend on.
    private struct FiguresKey: Equatable {
        var request: ReportRequest
        var period: ReportPeriod
        var revision: Int
        var today: LocalDate
    }

    /// What the days' totals and overlaps depend on: the filters over the
    /// days they cover, and the data.
    private struct DailyKey: Equatable {
        var filter: EntryFilter
        var revision: Int
    }

    public init(model: AppModel, range: ClosedRange<LocalDate>, period: ReportPeriod) {
        self.model = model
        self.range = range
        self.period = period
    }

    /// The filters and days as a report request.
    private var request: ReportRequest {
        ReportRequest(range: range, grouping: grouping, clients: clients, projects: projects, tags: tags)
    }

    /// Shows other days.
    public func show(_ range: ClosedRange<LocalDate>, period: ReportPeriod) {
        guard range != self.range || period != self.period else { return }
        self.range = range
        self.period = period
    }

    /// The same length of time before or after.
    public func step(_ direction: Int) {
        show(period.shift(range, by: direction), period: period)
    }

    /// Takes what a typed report says: its days, if it names any, its
    /// grouping, and its clients, projects and tags in place of the ones
    /// before.
    public func apply(_ query: ReportQuery) {
        if let range = query.range {
            self.range = range
            period = query.period ?? .custom
        }
        if let grouping = query.grouping {
            self.grouping = grouping
        }
        clients = query.clients
        projects = query.projects
        tags = query.tags
    }

    /// What the days and filters add up to.
    public var report: Report {
        figures.report
    }

    /// The report's total next to the period before it.
    public var comparison: ReportComparison {
        figures.comparison
    }

    /// The filtered time on each day of the range's year, the running
    /// timer left out as in reports.
    public var dayTotals: DayTotals {
        daily.totals
    }

    /// Days with time counted twice.
    public var overlapDays: Set<LocalDate> {
        daily.overlapDays
    }

    private var figures: (report: Report, comparison: ReportComparison) {
        let key = FiguresKey(request: request, period: period, revision: model.revision, today: model.today)
        if let figuresCache, figuresCache.key == key {
            return (figuresCache.report, figuresCache.comparison)
        }
        let report = Report(key.request, ledger: model.ledger, resolved: model.resolved)
        let comparison = ReportComparison(report, period: key.period, today: key.today, ledger: model.ledger, resolved: model.resolved)
        figuresCache = (key, report, comparison)
        return (report, comparison)
    }

    private var daily: (totals: DayTotals, overlapDays: Set<LocalDate>) {
        // The year around the range, and a week either side for the month
        // grid's first and last rows.
        let year = range.lowerBound.year
        let first = LocalDate(year: year, month: 1, day: 1).adding(days: -7)
        let last = max(LocalDate(year: year, month: 12, day: 31), range.upperBound).adding(days: 7)
        let filter = EntryFilter(range: first...last, clients: clients, projects: projects, tags: tags)
        let key = DailyKey(filter: filter, revision: model.revision)
        if let dailyCache, dailyCache.key == key {
            return (dailyCache.totals, dailyCache.overlapDays)
        }
        let entries = model.resolved.filter(filter.matcher(in: model.ledger))
        var spans: [LocalDate: [TimeSpan]] = [:]
        for entry in entries {
            if let end = entry.end {
                spans[entry.entry.day, default: []].append(TimeSpan(start: entry.start, end: end))
            }
        }
        let totals = DayTotals(entries)
        let overlapDays = Set(spans.compactMap { day, spans in Overlaps.doubleCounted(spans) > 0 ? day : nil })
        dailyCache = (key, totals, overlapDays)
        return (totals, overlapDays)
    }

    /// The weeks of the range's year, each with its first day and the
    /// time on its days.
    public var weeks: [(start: LocalDate, total: Int64)] {
        let year = range.lowerBound.year
        let totals = dayTotals
        let first = LocalDate(year: year, month: 1, day: 1).startOfWeek(firstWeekday: model.firstWeekday)
        return sequence(first: first) { $0.adding(days: 7) }
            .prefix(while: { $0.year <= year })
            .map { (start: $0, total: totals.total(in: $0...$0.adding(days: 6))) }
    }

    /// What the report covers, as a title: the client, or the project, or
    /// "Everything".
    public var title: String {
        let ledger = model.ledger
        if clients.count == 1, let id = clients.first, let client = ledger.clients[id] {
            return client.name
        }
        if projects.count == 1, let id = projects.first, let project = ledger.projects[id] {
            return project.name
        }
        if !clients.isEmpty || !projects.isEmpty {
            let names = clients.compactMap { ledger.clients[$0]?.name } + projects.compactMap { ledger.projects[$0]?.name }
            return names.sorted().formatted(.list(type: .and))
        }
        if !tags.isEmpty {
            return tags.sorted(by: Tags.order).formatted(.list(type: .and))
        }
        return "Everything"
    }

    /// How many weekdays the range has, for "21 of 22 weekdays".
    public var weekdays: Int {
        range.days.filter { $0.weekday != 1 && $0.weekday != 7 }.count
    }

    /// The days in the range with time counted twice.
    public var overlapDaysInRange: [LocalDate] {
        overlapDays.filter { range.contains($0) }.sorted()
    }

    /// The report as a typed line that reads back as it, such as
    /// "acme sep 2026 by project".
    public var typed: String {
        let ledger = model.ledger
        var words: [String] = []
        words += clients.compactMap { ledger.clients[$0]?.name.lowercased() }
        words += projects.compactMap { ledger.projects[$0]?.name.lowercased() }
        words += tags.map { $0.hasPrefix("#") ? $0 : "#" + $0 }
        let first = range.lowerBound
        let last = range.upperBound
        if period == .month {
            words.append("\(TimeWords.monthNames[first.month - 1]) \(first.year)")
        } else if first == last {
            words.append(first.description)
        } else {
            words.append("\(first) to \(last)")
        }
        words.append("by \(grouping.rawValue)")
        return words.joined(separator: " ")
    }
}
