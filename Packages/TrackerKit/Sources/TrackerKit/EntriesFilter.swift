import Foundation
import TrackerCore

/// The periods a list of entries can be narrowed to.
public enum EntriesPeriod: Hashable, Sendable {
    case all, today, thisWeek, lastWeek, thisMonth, lastMonth, thisYear, custom

    public var title: String {
        switch self {
        case .all: "All Time"
        case .today: "Today"
        case .thisWeek: "This Week"
        case .lastWeek: "Last Week"
        case .thisMonth: "This Month"
        case .lastMonth: "Last Month"
        case .thisYear: "This Year"
        case .custom: "Custom"
        }
    }

    /// The period's days as of `today`, or nil for all time. Weeks start on
    /// `firstWeekday`, 1 for Sunday through 7 for Saturday. A custom period
    /// keeps the days it has, or starts as this week.
    public func range(today: LocalDate, firstWeekday: Int, custom: ClosedRange<LocalDate>?) -> ClosedRange<LocalDate>? {
        switch self {
        case .all:
            return nil
        case .today:
            return today...today
        case .thisWeek:
            return ReportPeriod.week.range(containing: today, firstWeekday: firstWeekday)
        case .lastWeek:
            return ReportPeriod.week.range(containing: today.adding(days: -7), firstWeekday: firstWeekday)
        case .thisMonth:
            return ReportPeriod.month.range(containing: today, firstWeekday: firstWeekday)
        case .lastMonth:
            let thisMonth = ReportPeriod.month.range(containing: today, firstWeekday: firstWeekday)
            return ReportPeriod.month.shift(thisMonth, by: -1, firstWeekday: firstWeekday)
        case .thisYear:
            return LocalDate(year: today.year, month: 1, day: 1)...LocalDate(year: today.year, month: 12, day: 31)
        case .custom:
            return custom ?? ReportPeriod.week.range(containing: today, firstWeekday: firstWeekday)
        }
    }
}

/// What a list of entries is narrowed to, on the Mac's entries table and
/// the iPad's list.
public struct EntriesFilter: Equatable, Sendable {
    public var period: EntriesPeriod
    /// The period's days. They're worked out when the period is chosen and
    /// when the day changes, rather than on every redraw, so the table
    /// doesn't follow the clock.
    public var range: ClosedRange<LocalDate>?
    public var clients: Set<UUID?>
    public var projects: Set<UUID?>
    public var tags: Set<String>
    public var overlapsOnly: Bool

    public init(
        period: EntriesPeriod = .all,
        range: ClosedRange<LocalDate>? = nil,
        clients: Set<UUID?> = [],
        projects: Set<UUID?> = [],
        tags: Set<String> = [],
        overlapsOnly: Bool = false
    ) {
        self.period = period
        self.range = range
        self.clients = clients
        self.projects = projects
        self.tags = tags
        self.overlapsOnly = overlapsOnly
    }

    public var isActive: Bool {
        period != .all || !clients.isEmpty || !projects.isEmpty || !tags.isEmpty || overlapsOnly
    }

    /// The part reports share: days, clients, projects and tags.
    public var entryFilter: EntryFilter {
        EntryFilter(
            range: range,
            clients: clients.isEmpty ? nil : clients,
            projects: projects.isEmpty ? nil : projects,
            tags: tags.isEmpty ? nil : tags
        )
    }

    public mutating func choose(_ period: EntriesPeriod, today: LocalDate, firstWeekday: Int) {
        self.period = period
        range = period.range(today: today, firstWeekday: firstWeekday, custom: range)
    }

    /// Works the days out again, as when a new day starts. Custom days stay.
    public mutating func refresh(today: LocalDate, firstWeekday: Int) {
        guard period != .custom else { return }
        let current = period.range(today: today, firstWeekday: firstWeekday, custom: nil)
        if current != range {
            range = current
        }
    }
}
