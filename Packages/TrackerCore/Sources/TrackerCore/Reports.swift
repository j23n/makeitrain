import Foundation

/// What a report covers.
public struct ReportRequest: Hashable, Sendable {
    /// The entries it covers.
    public var filter: EntryFilter
    public var grouping: Grouping

    public enum Grouping: String, CaseIterable, Hashable, Sendable {
        case client, project, tag
    }

    public init(
        range: ClosedRange<LocalDate>,
        grouping: Grouping = .client,
        clients: Set<UUID> = [],
        projects: Set<UUID> = [],
        tags: Set<String> = []
    ) {
        filter = EntryFilter(range: range, clients: clients, projects: projects, tags: tags)
        self.grouping = grouping
    }

    /// The days it covers.
    public var range: ClosedRange<LocalDate> {
        filter.range
    }
}

/// A row in a report: a client, project or tag, with its time.
public struct ReportGroup: Identifiable, Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case client(UUID)
        case noClient
        case project(UUID)
        case unassigned
        case tag(String)
        case untagged
    }

    public var kind: Kind
    public var title: String
    /// A hex color, for projects.
    public var color: String?
    public var milliseconds: Int64
    /// For a client, its projects.
    public var children: [ReportGroup]

    public var id: Kind { kind }
}

/// Totals for a range of days.
///
/// Every entry counts in full, so the total equals the sum of end minus start
/// across the CSV rows. Where entries overlap, that time counts more than
/// once; `doubleCounted` says how much. A running timer isn't in the totals;
/// it's reported separately. Grouped by tag, an entry with several tags
/// counts under each of them, so the groups can add up to more than the
/// total.
public struct Report: Hashable, Sendable {
    public var request: ReportRequest
    /// The stopped entries in range that pass the filters, by start.
    public var entries: [ResolvedEntry]
    public var total: Int64
    /// Time counted more than once because entries overlap.
    public var doubleCounted: Int64
    /// The running timer, if it's in range and passes the filters. Not part
    /// of the totals.
    public var running: ResolvedEntry?
    public var groups: [ReportGroup]
    /// How many days in the range have time logged.
    public var daysWorked: Int

    /// Builds the report from entries already resolved, as the app model
    /// keeps them.
    public init(_ request: ReportRequest, ledger: Ledger, resolved: [ResolvedEntry]) {
        self.request = request
        let matching = resolved.filter(request.filter.matcher(in: ledger))
        entries = matching.filter { !$0.isRunning }
        running = matching.first { $0.isRunning }
        total = entries.reduce(0) { $0 + $1.length }
        doubleCounted = Overlaps.doubleCounted(entries.compactMap { entry in
            entry.end.map { TimeSpan(start: entry.start, end: $0) }
        })
        groups = Report.groups(entries, request.grouping, ledger)
        daysWorked = Set(entries.filter { $0.length > 0 }.map(\.entry.day)).count
    }

    private static func groups(_ entries: [ResolvedEntry], _ grouping: ReportRequest.Grouping, _ ledger: Ledger) -> [ReportGroup] {
        switch grouping {
        case .project:
            return projectGroups(entries, ledger, titledWithClient: true)
        case .client:
            var byClient: [UUID?: [ResolvedEntry]] = [:]
            var unassigned: [ResolvedEntry] = []
            for entry in entries {
                if entry.entry.projectID == nil {
                    unassigned.append(entry)
                } else {
                    byClient[ledger.client(forProject: entry.entry.projectID)?.id, default: []].append(entry)
                }
            }
            var result = byClient.compactMap { clientID, members -> ReportGroup? in
                guard let clientID else { return nil }
                let children = projectGroups(members, ledger, titledWithClient: false)
                return ReportGroup(
                    kind: .client(clientID),
                    title: ledger.clients[clientID]?.name ?? "Unknown client",
                    color: nil,
                    milliseconds: children.reduce(0) { $0 + $1.milliseconds },
                    children: children
                )
            }
            .sorted { $0.title.lowercased() < $1.title.lowercased() }
            if let members = byClient[nil] {
                let children = projectGroups(members, ledger, titledWithClient: false)
                result.append(ReportGroup(
                    kind: .noClient,
                    title: "No client",
                    color: nil,
                    milliseconds: children.reduce(0) { $0 + $1.milliseconds },
                    children: children
                ))
            }
            if !unassigned.isEmpty {
                result.append(ReportGroup(
                    kind: .unassigned,
                    title: "Unassigned",
                    color: nil,
                    milliseconds: unassigned.reduce(0) { $0 + $1.length },
                    children: []
                ))
            }
            return result
        case .tag:
            var spelling: [String: String] = [:]
            var byTag: [String: Int64] = [:]
            var untagged: Int64 = 0
            for entry in entries {
                let duration = entry.length
                if entry.entry.tags.isEmpty {
                    untagged += duration
                }
                for tag in Set(entry.entry.tags.map { $0.lowercased() }) {
                    byTag[tag, default: 0] += duration
                }
                // Entries are in order of start, so the latest spelling wins,
                // as in the tag list.
                for tag in entry.entry.tags {
                    spelling[tag.lowercased()] = tag
                }
            }
            var result = byTag.map { key, milliseconds in
                ReportGroup(kind: .tag(key), title: spelling[key] ?? key, color: nil, milliseconds: milliseconds, children: [])
            }
            .sorted { $0.title.lowercased() < $1.title.lowercased() }
            if untagged > 0 {
                result.append(ReportGroup(kind: .untagged, title: "Untagged", color: nil, milliseconds: untagged, children: []))
            }
            return result
        }
    }

    private static func projectGroups(_ entries: [ResolvedEntry], _ ledger: Ledger, titledWithClient: Bool) -> [ReportGroup] {
        var byProject: [UUID?: Int64] = [:]
        for entry in entries {
            byProject[entry.entry.projectID, default: 0] += entry.length
        }
        var result = byProject.compactMap { projectID, milliseconds -> ReportGroup? in
            guard let projectID else { return nil }
            return ReportGroup(
                kind: .project(projectID),
                title: titledWithClient ? ledger.projectTitle(projectID) : ledger.projects[projectID]?.name ?? "Unknown project",
                color: ledger.projects[projectID]?.color,
                milliseconds: milliseconds,
                children: []
            )
        }
        .sorted { $0.title.lowercased() < $1.title.lowercased() }
        if let milliseconds = byProject[nil] {
            result.append(ReportGroup(kind: .unassigned, title: "Unassigned", color: nil, milliseconds: milliseconds, children: []))
        }
        return result
    }
}

extension ResolvedEntry {
    /// Milliseconds from start to end, or 0 while running. Reports leave
    /// the running timer out, so the time now never changes them.
    var length: Int64 {
        end.map { max(0, start.distance(to: $0)) } ?? 0
    }
}

/// The periods a report can cover.
public enum ReportPeriod: Hashable, Sendable {
    case day, week, month, custom

    /// The period containing `date`. Weeks start on `firstWeekday`, 1 for
    /// Sunday through 7 for Saturday. A custom period starts as a week.
    public func range(containing date: LocalDate, firstWeekday: Int) -> ClosedRange<LocalDate> {
        switch self {
        case .day:
            return date...date
        case .week, .custom:
            let start = date.startOfWeek(firstWeekday: firstWeekday)
            return start...start.adding(days: 6)
        case .month:
            return Self.days(ofMonth: date.month, in: date.year)
        }
    }

    /// The period before (`by: -1`) or after (`by: 1`) a range. A custom
    /// range moves by its own length.
    public func shift(_ range: ClosedRange<LocalDate>, by steps: Int) -> ClosedRange<LocalDate> {
        switch self {
        case .day, .week, .custom:
            let length = range.upperBound.daysSince1970 - range.lowerBound.daysSince1970 + 1
            return range.lowerBound.adding(days: length * steps)...range.upperBound.adding(days: length * steps)
        case .month:
            var year = range.lowerBound.year
            var month = range.lowerBound.month + steps
            while month < 1 { month += 12; year -= 1 }
            while month > 12 { month -= 12; year += 1 }
            return Self.days(ofMonth: month, in: year)
        }
    }

    /// Every day of a month.
    private static func days(ofMonth month: Int, in year: Int) -> ClosedRange<LocalDate> {
        LocalDate(year: year, month: month, day: 1)...LocalDate(year: year, month: month, day: LocalDate.daysIn(month: month, year: year))
    }
}

extension LocalDate {
    /// The first day of the week this day is in. `firstWeekday` is 1 for
    /// Sunday through 7 for Saturday.
    public func startOfWeek(firstWeekday: Int) -> LocalDate {
        adding(days: -((weekday - firstWeekday + 7) % 7))
    }
}
