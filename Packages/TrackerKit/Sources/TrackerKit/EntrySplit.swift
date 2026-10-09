import Foundation
import TrackerCore

/// Where an entry is split in the middle.
public enum EntrySplit {
    /// The middle of an entry, on five minutes if that's inside it and on a
    /// minute otherwise, at least a minute after its start and before its
    /// end, or before now while it runs. Nil when it's too short to split.
    public static func time(for entry: ResolvedEntry, now: Timestamp) -> Timestamp? {
        let end = entry.end ?? now
        let first = entry.start.adding(seconds: 60)
        let last = end.adding(seconds: -60)
        guard first <= last else { return nil }
        let middle = entry.start.adding(milliseconds: entry.start.distance(to: end) / 2)
        let snapped = middle.rounded(toMinutes: 5)
        if first <= snapped, snapped <= last {
            return snapped
        }
        return min(max(middle.rounded(toMinutes: 1), first), last)
    }
}
