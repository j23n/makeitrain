import Foundation
import Observation
import TrackerCore

/// A report as the month and year screens show it: which clients, projects
/// and tags, which days, and how it's grouped, with what that adds up to.
/// It's worked out again only when one of those or the data changes.
@MainActor
@Observable
public final class ReportState {
    public let model: AppModel
    public private(set) var range: ClosedRange<LocalDate>
    /// How the range steps and compares: a day, week, month, or custom.
    public private(set) var period: ReportPeriod
    public var grouping: ReportRequest.Grouping {
        didSet { if grouping != oldValue { recompute() } }
    }
    /// Clients to include, or all when empty.
    public var clients: Set<UUID> = [] {
        didSet { if clients != oldValue { recompute() } }
    }
    /// Projects to include, or all when empty.
    public var projects: Set<UUID> = [] {
        didSet { if projects != oldValue { recompute() } }
    }
    /// Tags to include, or all when empty.
    public var tags: Set<String> = [] {
        didSet { if tags != oldValue { recompute() } }
    }

    public private(set) var report: Report
    public private(set) var comparison: ReportComparison
    /// The filtered time on each day of the range's year, the running
    /// timer left out as in reports.
    public private(set) var dayTotals: [LocalDate: Int64] = [:]
    /// Days with time counted twice.
    public private(set) var overlapDays: Set<LocalDate> = []
    /// The filtered time per project on each day of the range's year.
    public private(set) var dayProjects: [LocalDate: [UUID?: Int64]] = [:]

    @ObservationIgnored private var loadedRevision = -1

    public init(model: AppModel, range: ClosedRange<LocalDate>, period: ReportPeriod, grouping: ReportRequest.Grouping = .project) {
        self.model = model
        self.range = range
        self.period = period
        self.grouping = grouping
        let request = ReportRequest(range: range, grouping: grouping)
        let first = Report(request, ledger: model.ledger, resolved: model.resolved, now: model.now)
        report = first
        comparison = ReportComparison(
            first,
            period: period,
            today: model.today,
            ledger: model.ledger,
            resolved: model.resolved,
            now: model.now
        )
        recompute()
    }

    /// The filters and days as a report request.
    public var request: ReportRequest {
        ReportRequest(
            range: range,
            grouping: grouping,
            clients: clients.isEmpty ? nil : Set(clients.map { Optional($0) }),
            projects: projects.isEmpty ? nil : Set(projects.map { Optional($0) }),
            tags: tags.isEmpty ? nil : tags
        )
    }

    /// Shows other days.
    public func show(_ range: ClosedRange<LocalDate>, period: ReportPeriod) {
        guard range != self.range || period != self.period else { return }
        let yearChanged = range.lowerBound.year != self.range.lowerBound.year
        self.range = range
        self.period = period
        recompute(totals: yearChanged)
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
        recompute()
    }

    /// Works everything out again if the data changed.
    public func refresh() {
        guard loadedRevision != model.revision else { return }
        recompute()
    }

    /// Works out the report, and with `totals` the year's daily totals too.
    public func recompute(totals: Bool = true) {
        loadedRevision = model.revision
        report = Report(request, ledger: model.ledger, resolved: model.resolved, now: model.now)
        comparison = ReportComparison(
            report,
            period: period,
            today: model.today,
            ledger: model.ledger,
            resolved: model.resolved,
            now: model.now
        )
        guard totals else { return }
        // The year around the range, and a week either side for the month
        // grid's first and last rows.
        let year = range.lowerBound.year
        let first = LocalDate(year: year, month: 1, day: 1).adding(days: -7)
        let last = max(LocalDate(year: year, month: 12, day: 31), range.upperBound).adding(days: 7)
        var filter = request.filter
        filter.range = first...last
        let matches = filter.matcher(in: model.ledger)
        var days: [LocalDate: Int64] = [:]
        var projectsByDay: [LocalDate: [UUID?: Int64]] = [:]
        var spans: [LocalDate: [TimeSpan]] = [:]
        for entry in model.resolved where !entry.isRunning && matches(entry) {
            let day = entry.entry.day
            let duration = entry.duration(now: model.now)
            days[day, default: 0] += duration
            projectsByDay[day, default: [:]][entry.entry.projectID, default: 0] += duration
            if let end = entry.end {
                spans[day, default: []].append(TimeSpan(start: entry.start, end: end))
            }
        }
        dayTotals = days
        dayProjects = projectsByDay
        overlapDays = Set(spans.compactMap { day, spans in Overlaps.doubleCounted(spans) > 0 ? day : nil })
    }

    /// The weeks of the range's year, each with its first day and the
    /// time on its days.
    public var weeks: [(start: LocalDate, total: Int64)] {
        let year = range.lowerBound.year
        var start = LocalDate(year: year, month: 1, day: 1).startOfWeek(firstWeekday: model.firstWeekday)
        var result: [(start: LocalDate, total: Int64)] = []
        while start.year <= year {
            var total: Int64 = 0
            for offset in 0..<7 {
                total += dayTotals[start.adding(days: offset)] ?? 0
            }
            result.append((start, total))
            start = start.adding(days: 7)
        }
        return result
    }

    /// The months of the range's year, with the time in each.
    public var months: [(month: Int, total: Int64)] {
        let year = range.lowerBound.year
        return (1...12).map { month in
            let total = dayTotals.reduce(Int64(0)) { sum, item in
                item.key.year == year && item.key.month == month ? sum + item.value : sum
            }
            return (month, total)
        }
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
        var count = 0
        var day = range.lowerBound
        while day <= range.upperBound {
            if day.weekday != 1, day.weekday != 7 {
                count += 1
            }
            day = day.adding(days: 1)
        }
        return count
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
        let monthNames = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
        if period == .month {
            words.append("\(monthNames[first.month - 1]) \(first.year)")
        } else if first == last {
            words.append(first.description)
        } else {
            words.append("\(first) to \(last)")
        }
        words.append("by \(grouping.rawValue)")
        return words.joined(separator: " ")
    }
}
