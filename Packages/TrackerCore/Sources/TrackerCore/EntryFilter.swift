import Foundation

/// Which entries to show: those on some days, for some clients or projects,
/// or with some tags. Reports and the entries list filter the same way.
public struct EntryFilter: Hashable, Sendable {
    /// Calendar days, or every day when nil. An entry is on the day of its
    /// start, in its own time zone.
    public var range: ClosedRange<LocalDate>?
    /// Only entries for these clients, or all when nil. `nil` in the set
    /// stands for entries without a client.
    public var clients: Set<UUID?>?
    /// Only entries for these projects, or all when nil. `nil` in the set
    /// stands for unassigned entries.
    public var projects: Set<UUID?>?
    /// Only entries with at least one of these tags, ignoring case, or all
    /// when nil or empty.
    public var tags: Set<String>?

    public init(
        range: ClosedRange<LocalDate>? = nil,
        clients: Set<UUID?>? = nil,
        projects: Set<UUID?>? = nil,
        tags: Set<String>? = nil
    ) {
        self.range = range
        self.clients = clients
        self.projects = projects
        self.tags = tags
    }

    /// Whether it lets every entry through.
    public var isEmpty: Bool {
        range == nil && clients == nil && projects == nil && (tags ?? []).isEmpty
    }

    /// A test for entries, with what it needs worked out once, for going
    /// through many.
    public func matcher(in ledger: Ledger) -> (ResolvedEntry) -> Bool {
        let days = range.map(DaySpan.init)
        let wantedTags = Set((tags ?? []).map { $0.lowercased() })
        return { entry in
            if let days, !days.contains(entry.entry) {
                return false
            }
            if let projects = self.projects, !projects.contains(entry.entry.projectID) {
                return false
            }
            if let clients = self.clients, !clients.contains(ledger.client(forProject: entry.entry.projectID)?.id) {
                return false
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

extension ReportRequest {
    /// The entries the report covers.
    public var filter: EntryFilter {
        EntryFilter(range: range, clients: clients, projects: projects, tags: tags)
    }
}
