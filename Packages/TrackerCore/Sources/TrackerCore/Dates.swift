import Foundation

/// A calendar day with no time zone attached, such as the day an entry belongs to.
public struct LocalDate: Hashable, Comparable, Sendable {
    public var year: Int
    public var month: Int
    public var day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// The day `days` days after 1970-01-01.
    public init(daysSince1970 days: Int) {
        // civil_from_days from http://howardhinnant.github.io/date_algorithms.html
        let z = days + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let dayOfEra = z - era * 146_097
        let yearOfEra = (dayOfEra - dayOfEra / 1460 + dayOfEra / 36524 - dayOfEra / 146_096) / 365
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let monthFromMarch = (5 * dayOfYear + 2) / 153
        let month = monthFromMarch < 10 ? monthFromMarch + 3 : monthFromMarch - 9
        self.init(
            year: yearOfEra + era * 400 + (month <= 2 ? 1 : 0),
            month: month,
            day: dayOfYear - (153 * monthFromMarch + 2) / 5 + 1
        )
    }

    /// Days since 1970-01-01.
    public var daysSince1970: Int {
        // days_from_civil from http://howardhinnant.github.io/date_algorithms.html
        let year = month <= 2 ? self.year - 1 : self.year
        let era = (year >= 0 ? year : year - 399) / 400
        let yearOfEra = year - era * 400
        let dayOfYear = (153 * (month > 2 ? month - 3 : month + 9) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    public func adding(days: Int) -> LocalDate {
        LocalDate(daysSince1970: daysSince1970 + days)
    }

    /// 1 for Sunday through 7 for Saturday, as in `Calendar`.
    public var weekday: Int {
        // 1970-01-01 was a Thursday.
        ((daysSince1970 + 4) % 7 + 7) % 7 + 1
    }

    public var monthKey: MonthKey {
        MonthKey(year: year, month: month)
    }

    public static func < (lhs: LocalDate, rhs: LocalDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    static func daysIn(month: Int, year: Int) -> Int {
        switch month {
        case 2: year % 4 == 0 && (year % 100 != 0 || year % 400 == 0) ? 29 : 28
        case 4, 6, 9, 11: 30
        default: 31
        }
    }
}

extension LocalDate: CustomStringConvertible {
    /// Such as "2026-09-23".
    public var description: String {
        "\(padded(year, 4))-\(padded(month, 2))-\(padded(day, 2))"
    }
}

/// A calendar month. Each one names a month file, such as `2026-09.json`.
public struct MonthKey: Hashable, Comparable, Sendable {
    public var year: Int
    public var month: Int

    public init(year: Int, month: Int) {
        self.year = year
        self.month = month
    }

    /// Parses a month such as "2026-09".
    public init?(_ text: String) {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0].count == 4, parts[1].count == 2,
              parts.allSatisfy({ $0.allSatisfy(\.isASCIIDigit) }),
              let year = Int(parts[0]), let month = Int(parts[1]), (1...12).contains(month)
        else { return nil }
        self.init(year: year, month: month)
    }

    /// Such as "2026-09.json".
    public var fileName: String {
        "\(self).json"
    }

    public static func < (lhs: MonthKey, rhs: MonthKey) -> Bool {
        (lhs.year, lhs.month) < (rhs.year, rhs.month)
    }
}

extension MonthKey: CustomStringConvertible {
    /// Such as "2026-09".
    public var description: String {
        "\(padded(year, 4))-\(padded(month, 2))"
    }
}

/// A wall-clock date and time, without the zone it was read in.
public struct LocalDateTime: Hashable, Sendable {
    public var date: LocalDate
    /// Milliseconds since midnight.
    public var millisecondOfDay: Int

    public var hour: Int { millisecondOfDay / 3_600_000 }
    public var minute: Int { millisecondOfDay / 60000 % 60 }
    public var second: Int { millisecondOfDay / 1000 % 60 }
    public var millisecond: Int { millisecondOfDay % 1000 }
}

extension Timestamp {
    /// The wall-clock date and time at this instant, `offsetSeconds` east of UTC.
    public func local(offsetSeconds: Int) -> LocalDateTime {
        let local = milliseconds + Int64(offsetSeconds) * 1000
        let days = local.floorDivided(by: 86_400_000)
        return LocalDateTime(
            date: LocalDate(daysSince1970: Int(days)),
            millisecondOfDay: Int(local - days * 86_400_000)
        )
    }

    /// The wall-clock date and time at this instant in a time zone, such as "Europe/Berlin".
    public func local(in zone: String) -> LocalDateTime {
        local(offsetSeconds: Zones.offset(zone, at: self))
    }
}

/// Time zones by identifier, such as "Europe/Berlin".
public enum Zones {
    /// The zone with this identifier, or UTC if this device doesn't know it.
    public static func zone(_ identifier: String) -> TimeZone {
        TimeZone(identifier: identifier) ?? TimeZone(secondsFromGMT: 0)!
    }

    /// Seconds east of UTC in the zone at the given time.
    public static func offset(_ identifier: String, at time: Timestamp) -> Int {
        zone(identifier).secondsFromGMT(for: time.date)
    }
}

extension Character {
    var isASCIIDigit: Bool {
        ("0"..."9").contains(self)
    }
}

/// `value` with leading zeros to fill `width` digits.
func padded(_ value: Int, _ width: Int) -> String {
    let digits = String(value)
    return String(repeating: "0", count: max(0, width - digits.count)) + digits
}
