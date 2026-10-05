import Foundation
import TrackerCore

/// Text for times, days and durations, shared by the Mac and iOS screens.
public enum Format {
    /// Hours and minutes. Under a day, as a stopwatch writes them, such as
    /// "1:05" or "12:30"; from a day up, with their units, such as
    /// "42 h 31 m" or "574 h", since "574:46" reads as a time of day.
    /// Seconds are dropped. The spaces don't break, so a duration stays on
    /// one line.
    public static func duration(_ milliseconds: Int64) -> String {
        durationParts(milliseconds)
            .map { part in part.unit.map { "\(part.number)\u{00A0}\($0)" } ?? part.number }
            .joined(separator: "\u{00A0}")
    }

    /// The numbers of `duration(_:)` and their units: one number without a
    /// unit under a day, such as ("1:05", nil), and from a day up the
    /// hours and any minutes, such as ("574", "h") and ("46", "m"). Views
    /// that set the units smaller than the numbers use them.
    public static func durationParts(_ milliseconds: Int64) -> [(number: String, unit: String?)] {
        let minutes = max(0, milliseconds) / 60000
        let (hours, rest) = (minutes / 60, minutes % 60)
        guard hours >= 24 else {
            return [("\(hours):\(rest < 10 ? "0" : "")\(rest)", nil)]
        }
        return rest == 0 ? [("\(hours)", "h")] : [("\(hours)", "h"), ("\(rest)", "m")]
    }

    /// Reads a duration typed as "1:30", "1.5" (hours), "90m", "1h 30m" or
    /// "1h30". Nil if it can't be read.
    public static func parseDuration(_ text: String) -> Int64? {
        Durations.parse(text)
    }

    /// The wall-clock time in a time zone, such as "09:15" or "9:15 AM",
    /// following the user's settings.
    public static func time(_ time: Timestamp, zone: String) -> String {
        time.date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: Zones.zone(zone)))
    }

    /// A day, such as "Wed, Sep 23".
    public static func day(_ day: LocalDate) -> String {
        noon(of: day).formatted(Date.FormatStyle(timeZone: utc).weekday(.abbreviated).month(.abbreviated).day())
    }

    /// A day's weekday, such as "Mon".
    public static func weekday(_ day: LocalDate) -> String {
        noon(of: day).formatted(Date.FormatStyle(timeZone: utc).weekday(.abbreviated))
    }

    /// A day without its weekday and year, such as "Sep 23".
    public static func monthDay(_ day: LocalDate) -> String {
        noon(of: day).formatted(Date.FormatStyle(timeZone: utc).month(.abbreviated).day())
    }

    /// A month's short name, such as "Sep".
    public static func shortMonth(_ day: LocalDate) -> String {
        noon(of: day).formatted(Date.FormatStyle(timeZone: utc).month(.abbreviated))
    }

    /// A month and its year, such as "September 2026".
    public static func month(_ day: LocalDate) -> String {
        noon(of: day).formatted(Date.FormatStyle(timeZone: utc).month(.wide).year())
    }

    /// A day with its year, such as "Sep 23, 2026".
    public static func longDay(_ day: LocalDate) -> String {
        noon(of: day).formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, timeZone: utc))
    }

    /// A range of days, such as "Sep 21 – 27, 2026", or one day with its
    /// weekday.
    public static func days(_ range: ClosedRange<LocalDate>) -> String {
        guard range.lowerBound != range.upperBound else {
            return noon(of: range.lowerBound).formatted(
                Date.FormatStyle(timeZone: utc).weekday(.wide).month(.abbreviated).day().year()
            )
        }
        return (noon(of: range.lowerBound)..<noon(of: range.upperBound)).formatted(
            Date.IntervalFormatStyle(date: .abbreviated, time: .omitted, timeZone: utc)
        )
    }

    /// An hour of the day for a timeline's gutter, such as "09" or "9 AM",
    /// following the user's settings.
    public static func hour(_ hour: Int) -> String {
        Date(timeIntervalSince1970: Double(hour) * 3600).formatted(Date.FormatStyle(timeZone: utc).hour())
    }

    /// A wall-clock time given as seconds after midnight, such as "09:15".
    public static func time(secondOfDay: Int) -> String {
        Date(timeIntervalSince1970: Double(secondOfDay)).formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: utc))
    }

    /// A share of a total, such as "42%".
    public static func percent(_ part: Int64, of total: Int64) -> String {
        guard total > 0 else { return "" }
        return "\(Int((Double(part) / Double(total) * 100).rounded()))%"
    }

    /// A short name for a time zone, such as "CEST", shown next to times
    /// recorded in a zone other than the current one. Nil when it's the
    /// current zone.
    public static func zoneLabel(_ zone: String, at time: Timestamp) -> String? {
        let current = TimeZone.current
        let other = Zones.zone(zone)
        guard other.secondsFromGMT(for: time.date) != current.secondsFromGMT(for: time.date) else { return nil }
        return other.abbreviation(for: time.date) ?? zone
    }

    /// A date at noon UTC, for formatting a calendar day in the UTC zone.
    static func noon(of day: LocalDate) -> Date {
        Timestamp(milliseconds: Int64(day.daysSince1970) * 86_400_000 + 43_200_000).date
    }

    private static let utc = TimeZone(identifier: "UTC")!
}

extension LocalDate {
    /// The date in the user's current calendar, at noon in the current time
    /// zone, for date pickers.
    public var pickerDate: Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        return Calendar.current.date(from: components) ?? Date()
    }

    /// The day a date picker's date falls on, in the current time zone.
    public init(pickerDate date: Date) {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        self.init(year: components.year ?? 1970, month: components.month ?? 1, day: components.day ?? 1)
    }
}
