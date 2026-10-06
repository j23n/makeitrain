import Foundation
import TrackerCore

/// When an entry can be split.
public enum EntrySplit {
    /// The times an entry can be split at: at least a minute after its
    /// start and before its end, or before now while it runs. Nil when it's
    /// too short to split.
    public static func range(of entry: ResolvedEntry, now: Timestamp) -> ClosedRange<Date>? {
        let first = entry.start.adding(seconds: 60)
        let last = (entry.end ?? now).adding(seconds: -60)
        guard first <= last else { return nil }
        return first.date...last.date
    }

    /// The middle of the entry, on a multiple of five minutes if there's
    /// one inside it.
    public static func suggestedTime(for entry: ResolvedEntry, now: Timestamp) -> Date {
        guard let range = range(of: entry, now: now) else { return entry.start.date }
        let middle = entry.start.adding(milliseconds: entry.start.distance(to: entry.end ?? now) / 2)
        let fiveMinutes: Int64 = 300_000
        let snapped = Timestamp(milliseconds: (middle.milliseconds + fiveMinutes / 2) / fiveMinutes * fiveMinutes)
        if range.contains(snapped.date) {
            return snapped.date
        }
        let minute = Timestamp(milliseconds: (middle.milliseconds + 30000) / 60000 * 60000)
        return min(max(minute.date, range.lowerBound), range.upperBound)
    }
}
