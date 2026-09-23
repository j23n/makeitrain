import Foundation

/// An entry as the app shows it, with the two-timers rule applied.
public struct ResolvedEntry: Identifiable, Hashable, Sendable {
    public var entry: TimeEntry
    /// When the entry ends: its own `end`, or, for a timer overtaken by a
    /// later one, the moment that one started. nil while running.
    public var end: Timestamp?

    public var id: UUID { entry.id }
    public var start: Timestamp { entry.start }
    public var isRunning: Bool { end == nil }

    /// Whether this timer was still running when another device started a
    /// later one. It shows as ended at that moment, but has no `end` of its
    /// own until the next change settles it.
    public var endedByLaterTimer: Bool {
        entry.end == nil && end != nil
    }

    /// Milliseconds from start to end, or to `now` while running. Never negative.
    public func duration(now: Timestamp) -> Int64 {
        max(0, start.distance(to: end ?? now))
    }
}

extension Ledger {
    /// The entries that aren't deleted, sorted by start, as the app shows them.
    ///
    /// Only one timer runs at a time. When two devices each start one while
    /// one of them is offline, the files end up with two entries without an
    /// end: the later one keeps running, and the earlier one ends at the
    /// moment the later one started. Like overlaps, the rule is applied
    /// whenever the data is read rather than written back, so every device
    /// shows the same thing. The next change gives the earlier entry a real
    /// end (see `settleOvertakenTimers(now:)`).
    public func resolvedEntries() -> [ResolvedEntry] {
        let live = entries.values.filter { !$0.isDeleted }.sorted(by: TimeEntry.fileOrder)
        let running = live.filter { $0.end == nil }
        var overtakenEnds: [UUID: Timestamp] = [:]
        for (earlier, later) in zip(running, running.dropFirst()) {
            overtakenEnds[earlier.id] = later.start
        }
        return live.map { ResolvedEntry(entry: $0, end: $0.end ?? overtakenEnds[$0.id]) }
    }

    /// The running timer, if there is one.
    public var runningEntry: ResolvedEntry? {
        entries.values
            .filter { !$0.isDeleted && $0.end == nil }
            .max(by: TimeEntry.fileOrder)
            .map { ResolvedEntry(entry: $0, end: nil) }
    }
}
