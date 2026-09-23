import Foundation
import TrackerCore

/// Text for times, days and durations, shared by the Mac and iOS screens.
public enum Format {
    /// Hours and minutes, such as "1:05" or "12:30". Seconds are dropped.
    public static func duration(_ milliseconds: Int64) -> String {
        let minutes = max(0, milliseconds) / 60000
        let rest = minutes % 60
        return "\(minutes / 60):\(rest < 10 ? "0" : "")\(rest)"
    }

    /// Decimal hours, such as "2.42".
    public static func hours(_ milliseconds: Int64) -> String {
        String(format: "%.2f", Double(max(0, milliseconds)) / 3_600_000)
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

    /// A day with its year, such as "Sep 23, 2026".
    public static func longDay(_ day: LocalDate) -> String {
        noon(of: day).formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, timeZone: utc))
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
