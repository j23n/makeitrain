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
    /// Every fix to offer, the one to suggest first: splitting the outer
    /// entry around an inner one or ending it early, or, where they only
    /// partly overlap, ending the earlier one or starting the later one
    /// later. Where both start at the same moment, the longer one can start
    /// when the shorter one ends.
    public var fixes: [OverlapFix]
}

public enum OverlapFix: Hashable, Sendable {
    /// End the earlier entry when the later one starts.
    case trimEarlier(id: UUID, end: Timestamp)
    /// Start the later entry when the earlier one ends.
    case trimLater(id: UUID, start: Timestamp)
    /// Cut the outer entry into the parts before and after the inner one.
    case split(outer: UUID, inner: UUID)
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
    public static func analyze(_ entries: [ResolvedEntry], now: Timestamp) -> [Overlap] {
        let spans = entries
            .map { Span(entry: $0, end: $0.end ?? now) }
            .filter { $0.end > $0.entry.start }
            .sorted { TimeEntry.fileOrder($0.entry.entry, $1.entry.entry) }

        var overlaps: [Overlap] = []
        var latest: Span?
        for span in spans {
            if let latest, span.entry.start < latest.end {
                overlaps.append(Overlap(
                    earlier: latest.entry.id,
                    later: span.entry.id,
                    duration: span.entry.start.distance(to: min(span.end, latest.end)),
                    fixes: fixes(earlier: latest, later: span)
                ))
            }
            if latest.map({ span.end > $0.end }) ?? true {
                latest = span
            }
        }
        return overlaps
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

    private static func fixes(earlier: Span, later: Span) -> [OverlapFix] {
        if earlier.entry.start == later.entry.start {
            // The longer one can start where the shorter one ends, unless
            // the shorter one is the running timer.
            let (short, long) = earlier.end <= later.end ? (earlier, later) : (later, earlier)
            guard short.end < long.end, !short.entry.isRunning else { return [] }
            return [.trimLater(id: long.entry.id, start: short.end)]
        }
        if earlier.end > later.end {
            // The earlier entry contains the later one, which must have
            // stopped to split around it.
            var result: [OverlapFix] = []
            if !later.entry.isRunning {
                result.append(.split(outer: earlier.entry.id, inner: later.entry.id))
            }
            result.append(.trimEarlier(id: earlier.entry.id, end: later.entry.start))
            return result
        }
        var result: [OverlapFix] = [.trimEarlier(id: earlier.entry.id, end: later.entry.start)]
        if !earlier.entry.isRunning, earlier.end < later.end {
            result.append(.trimLater(id: later.entry.id, start: earlier.end))
        }
        return result
    }
}

extension Ledger {
    /// The time an overlap's two entries both count, as `Overlap.duration`
    /// measures it: from the later one's start to the earlier of their
    /// ends, the running timer's being `now`. Nil when either entry is
    /// gone, or the earlier one has no end and isn't `running`, the running
    /// timer's id.
    public func doubleCountedSpan(_ overlap: Overlap, running: UUID?, now: Timestamp) -> TimeSpan? {
        guard let earlier = entries[overlap.earlier], let later = entries[overlap.later],
              let earlierEnd = earlier.end ?? (earlier.id == running ? now : nil)
        else { return nil }
        return TimeSpan(start: later.start, end: min(earlierEnd, later.end ?? now))
    }
}
