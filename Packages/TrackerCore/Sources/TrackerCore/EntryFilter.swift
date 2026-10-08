import Foundation

/// Which entries to show: those on some days, for some clients or projects,
/// or with some tags. A report covers the entries of one.
public struct EntryFilter: Hashable, Sendable {
    /// Calendar days. An entry is on the day of its start, in its own time
    /// zone.
    public var range: ClosedRange<LocalDate>
    /// Only entries for these clients, or all when empty.
    public var clients: Set<UUID>
    /// Only entries for these projects, or all when empty.
    public var projects: Set<UUID>
    /// Only entries with at least one of these tags, ignoring case, or all
    /// when empty.
    public var tags: Set<String>

    public init(
        range: ClosedRange<LocalDate>,
        clients: Set<UUID> = [],
        projects: Set<UUID> = [],
        tags: Set<String> = []
    ) {
        self.range = range
        self.clients = clients
        self.projects = projects
        self.tags = tags
    }

    /// A test for entries, with what it needs worked out once, for going
    /// through many.
    public func matcher(in ledger: Ledger) -> (ResolvedEntry) -> Bool {
        let days = DaySpan(range)
        let wantedTags = Set(tags.map { $0.lowercased() })
        return { entry in
            if !days.contains(entry.entry) {
                return false
            }
            if !projects.isEmpty {
                guard let projectID = entry.entry.projectID, projects.contains(projectID) else { return false }
            }
            if !clients.isEmpty {
                guard let client = ledger.client(forProject: entry.entry.projectID), clients.contains(client.id) else { return false }
            }
            if !wantedTags.isEmpty, !entry.entry.tags.contains(where: { wantedTags.contains($0.lowercased()) }) {
                return false
            }
            return true
        }
    }
}

/// Days to test entries against, by their day in their own time zone.
///
/// Working out an entry's day means looking up its zone. Since no zone is
/// 16 hours or more off UTC, even in the local mean times of the 1800s, only
/// entries starting within 16 hours of either end need it; the rest are in
/// or out by their start alone.
private struct DaySpan {
    let days: ClosedRange<LocalDate>
    /// Starts before this are before the first day in every zone.
    let beforeFirst: Int64
    /// Starts from this on are on the first day or later in every zone.
    let onOrAfterFirst: Int64
    /// Starts before this are on the last day or earlier in every zone.
    let onOrBeforeLast: Int64
    /// Starts from this on are after the last day in every zone.
    let afterLast: Int64

    init(_ days: ClosedRange<LocalDate>) {
        let day: Int64 = 86_400_000
        let margin: Int64 = 16 * 3_600_000
        let first = Int64(days.lowerBound.daysSince1970) * day
        let end = Int64(days.upperBound.daysSince1970 + 1) * day
        self.days = days
        beforeFirst = first - margin
        onOrAfterFirst = first + margin
        onOrBeforeLast = end - margin
        afterLast = end + margin
    }

    func contains(_ entry: TimeEntry) -> Bool {
        let start = entry.start.milliseconds
        if start < beforeFirst || start >= afterLast {
            return false
        }
        if start >= onOrAfterFirst && start < onOrBeforeLast {
            return true
        }
        return days.contains(entry.day)
    }
}
