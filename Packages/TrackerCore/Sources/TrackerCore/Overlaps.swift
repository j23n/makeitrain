import Foundation

/// A stretch of time, such as an entry's.
public struct TimeSpan: Hashable, Sendable {
    public var start: Timestamp
    public var end: Timestamp

    public init(start: Timestamp, end: Timestamp) {
        self.start = start
        self.end = end
    }

    /// Milliseconds from start to end. Never negative.
    public var duration: Int64 {
        max(0, start.distance(to: end))
    }
}

/// Two entries that overlap.
public struct Overlap: Hashable, Sendable {
    /// The entry that starts first.
    public var earlier: UUID
    public var later: UUID
    /// How long they overlap, in milliseconds.
    public var duration: Int64
    /// The one-click fix to offer. nil when both start at the same moment,
    /// where neither fix makes sense.
    public var fix: OverlapFix?
}

public enum OverlapFix: Hashable, Sendable {
    /// End the earlier entry when the later one starts.
    case trimEarlier(id: UUID, end: Timestamp)
    /// Cut the outer entry into the parts before and after the inner one.
    case split(outer: UUID, inner: UUID)
}

public struct OverlapAnalysis: Hashable, Sendable {
    public var overlaps: [Overlap] = []
    /// Every entry that overlaps another.
    public var flagged: Set<UUID> = []
    /// Runs of entries that overlap one another, each in start order, for
    /// laying their blocks out side by side.
    public var groups: [[UUID]] = []
}

/// Finding overlapping entries. Overlaps are worked out when displaying and
/// never stored.
public enum Overlaps {
    /// Finds the overlaps among `entries`.
    ///
    /// Entries are scanned in start order while tracking the latest end so
    /// far, and an entry overlaps if it starts before that end. That also
    /// catches an entry that overlaps an earlier, longer one when a shorter
    /// entry sits between them. A running entry counts as ending at `now`;
    /// entries with no duration can't overlap.
    public static func analyze(_ entries: [ResolvedEntry], now: Timestamp) -> OverlapAnalysis {
        let spans = entries
            .map { Span(entry: $0, end: $0.end ?? now) }
            .filter { $0.end > $0.entry.start }
            .sorted { TimeEntry.fileOrder($0.entry.entry, $1.entry.entry) }

        var result = OverlapAnalysis()
        var group: [UUID] = []
        var latest: Span?
        for span in spans {
            if let latest, span.entry.start < latest.end {
                result.overlaps.append(Overlap(
                    earlier: latest.entry.id,
                    later: span.entry.id,
                    duration: span.entry.start.distance(to: min(span.end, latest.end)),
                    fix: fix(earlier: latest, later: span)
                ))
                result.flagged.formUnion([latest.entry.id, span.entry.id])
                group.append(span.entry.id)
            } else {
                if group.count > 1 {
                    result.groups.append(group)
                }
                group = [span.entry.id]
            }
            if latest.map({ span.end > $0.end }) ?? true {
                latest = span
            }
        }
        if group.count > 1 {
            result.groups.append(group)
        }
        return result
    }

    /// Time counted more than once when durations are added up: their sum
    /// minus the length of their union. Stays correct when three spans
    /// overlap.
    public static func doubleCounted(_ spans: [TimeSpan]) -> Int64 {
        var total: Int64 = 0
        var union: Int64 = 0
        var current: TimeSpan?
        for span in spans.filter({ $0.duration > 0 }).sorted(by: { $0.start < $1.start }) {
            total += span.duration
            if let run = current, span.start <= run.end {
                current = TimeSpan(start: run.start, end: max(run.end, span.end))
            } else {
                union += current?.duration ?? 0
                current = span
            }
        }
        union += current?.duration ?? 0
        return total - union
    }

    private struct Span {
        var entry: ResolvedEntry
        var end: Timestamp
    }

    private static func fix(earlier: Span, later: Span) -> OverlapFix? {
        guard earlier.entry.start < later.entry.start else { return nil }
        if earlier.end > later.end {
            // The earlier entry contains the later one, which must have stopped to split around it.
            return later.entry.isRunning ? nil : .split(outer: earlier.entry.id, inner: later.entry.id)
        }
        return .trimEarlier(id: earlier.entry.id, end: later.entry.start)
    }
}
