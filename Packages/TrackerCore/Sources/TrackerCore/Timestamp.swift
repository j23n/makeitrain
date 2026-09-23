import Foundation

/// A point in time: whole milliseconds since 1970-01-01T00:00:00Z.
///
/// Times are integers rather than `Date`'s floating-point seconds, so every
/// device compares them exactly and a time survives a round trip through a
/// file unchanged.
public struct Timestamp: Hashable, Comparable, Sendable {
    public var milliseconds: Int64

    public init(milliseconds: Int64) {
        self.milliseconds = milliseconds
    }

    /// `date`, rounded to the nearest millisecond.
    public init(_ date: Date) {
        milliseconds = Int64((date.timeIntervalSince1970 * 1000).rounded())
    }

    /// The current time, to the millisecond.
    public static var now: Timestamp {
        Timestamp(Date())
    }

    public var date: Date {
        Date(timeIntervalSince1970: Double(milliseconds) / 1000)
    }

    /// This time with its milliseconds dropped.
    public var wholeSeconds: Timestamp {
        Timestamp(milliseconds: milliseconds.floorDivided(by: 1000) * 1000)
    }

    public func adding(milliseconds delta: Int64) -> Timestamp {
        Timestamp(milliseconds: milliseconds + delta)
    }

    public func adding(seconds: Int64) -> Timestamp {
        adding(milliseconds: seconds * 1000)
    }

    /// The milliseconds from this time to `other`, negative if `other` is earlier.
    public func distance(to other: Timestamp) -> Int64 {
        other.milliseconds - milliseconds
    }

    /// The stamp for a change made at `now` to something last stamped
    /// `previous`: the later of `now` and one millisecond after `previous`.
    ///
    /// The change then beats the version it was made from, even when this
    /// device's clock is behind the one that made that version.
    public static func stamp(after previous: Timestamp?, now: Timestamp) -> Timestamp {
        guard let previous else { return now }
        return max(now, previous.adding(milliseconds: 1))
    }

    public static func < (lhs: Timestamp, rhs: Timestamp) -> Bool {
        lhs.milliseconds < rhs.milliseconds
    }
}

extension Timestamp: CustomStringConvertible {
    public var description: String {
        DateTimeFormat.formatUTC(self)
    }
}

extension Int64 {
    /// Division that rounds towards negative infinity.
    func floorDivided(by divisor: Int64) -> Int64 {
        let quotient = self / divisor
        return self % divisor != 0 && (self < 0) != (divisor < 0) ? quotient - 1 : quotient
    }
}
