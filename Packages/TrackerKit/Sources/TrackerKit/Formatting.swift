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

    /// Reads a duration typed as "1:30", "1.5" (hours), "90m", "1h 30m" or
    /// "1h30". Nil if it can't be read.
    public static func parseDuration(_ text: String) -> Int64? {
        let typed = text.lowercased().filter { !$0.isWhitespace }
        guard !typed.isEmpty else { return nil }
        if typed.contains(":") {
            let parts = typed.split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count == 2, parts[1].count == 2,
                  let hours = parts[0].isEmpty ? 0 : Int(parts[0]), let minutes = Int(parts[1]),
                  hours >= 0, (0..<60).contains(minutes)
            else { return nil }
            return Int64(hours * 60 + minutes) * 60000
        }
        guard typed.contains("h") || typed.contains("m") else {
            guard let hours = Double(typed.replacingOccurrences(of: ",", with: ".")), hours >= 0, hours < 10000 else {
                return nil
            }
            return Int64((hours * 60).rounded()) * 60000
        }
        var minutes = 0.0
        var number = ""
        var sawHours = false
        for character in typed {
            if character.isASCII, character.isNumber || character == "." || character == "," {
                number.append(character == "," ? "." : character)
            } else if character == "h" || character == "m" {
                guard let value = Double(number) else { return nil }
                minutes += character == "h" ? value * 60 : value
                sawHours = sawHours || character == "h"
                number = ""
            } else {
                return nil
            }
        }
        if !number.isEmpty {
            // "1h30" means 1 hour 30 minutes.
            guard sawHours, let value = Double(number) else { return nil }
            minutes += value
        }
        guard minutes < 600_000 else { return nil }
        return Int64(minutes.rounded()) * 60000
    }

    /// Reads a wall-clock time typed as "9:15", "09.15", "915", "9",
    /// "9:15 PM" or "9pm", as seconds after midnight. "24:00" is the end of
    /// the day. Nil if it can't be read.
    public static func parseTime(_ text: String) -> Int? {
        var typed = text.lowercased().filter { !$0.isWhitespace }
        var afternoon: Bool? = nil
        for (suffix, pm) in [("a.m.", false), ("p.m.", true), ("am", false), ("pm", true), ("a", false), ("p", true)]
        where typed.hasSuffix(suffix) {
            typed.removeLast(suffix.count)
            afternoon = pm
            break
        }
        guard !typed.isEmpty, typed.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == ":" || $0 == ".") }) else {
            return nil
        }
        let parts = typed.split(omittingEmptySubsequences: false) { $0 == ":" || $0 == "." }.map(String.init)
        var numbers: [Int]
        if parts.count == 1 {
            // "9", "09", "915" or "0915".
            let digits = parts[0]
            switch digits.count {
            case 1, 2: numbers = [Int(digits)!, 0]
            case 3, 4: numbers = [Int(digits.dropLast(2))!, Int(digits.suffix(2))!]
            default: return nil
            }
        } else {
            guard parts.count <= 3, (1...2).contains(parts[0].count), parts.dropFirst().allSatisfy({ $0.count == 2 }) else {
                return nil
            }
            numbers = parts.map { Int($0)! }
        }
        numbers += [0]
        var hour = numbers[0]
        let minute = numbers[1], second = numbers[2]
        guard minute < 60, second < 60 else { return nil }
        if let afternoon {
            guard (1...12).contains(hour) else { return nil }
            hour = hour % 12 + (afternoon ? 12 : 0)
        } else {
            guard hour < 24 || (hour == 24 && minute == 0 && second == 0) else { return nil }
        }
        return (hour * 60 + minute) * 60 + second
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

extension ResolvedEntry {
    /// The start moved to a wall-clock time on the entry's day, in its own
    /// time zone, as when a time is typed into the Start column.
    public func startAt(secondOfDay second: Int) -> Timestamp {
        Timestamp(date: entry.day, secondOfDay: second, zone: entry.timeZone)
    }

    /// The first moment after the start at a wall-clock time in the entry's
    /// time zone, as when a time is typed into the End column: an end
    /// earlier than the start is on the next day.
    public func endAt(secondOfDay second: Int) -> Timestamp {
        let sameDay = Timestamp(date: entry.day, secondOfDay: second, zone: entry.timeZone)
        guard sameDay <= start else { return sameDay }
        return Timestamp(date: entry.day.adding(days: 1), secondOfDay: second, zone: entry.timeZone)
    }

    /// The start moved to another day at the same wall-clock time, in the
    /// entry's time zone.
    public func startOn(_ day: LocalDate) -> Timestamp {
        let local = start.local(in: entry.timeZone)
        return Timestamp(date: day, secondOfDay: local.millisecondOfDay / 1000, zone: entry.timeZone)
    }
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
