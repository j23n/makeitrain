import Foundation

/// Times of day, days and durations as people type them into the command
/// line and report queries. Words are English, as the app's are.
enum TimeWords {
    /// A time of day typed as "9", "09:30", "9:30am", "21:00" or "12pm".
    struct Clock: Hashable, Sendable {
        /// Seconds after midnight. "24:00" is 86 400.
        var second: Int
        /// A plain number such as "9", which reads as a time only where one
        /// is expected, as after "from" or in "9-10".
        var bare: Bool
        /// Whether it said am or pm.
        var meridiem: Bool
    }

    /// Reads a time of day, or nil.
    static func clock(_ word: String) -> Clock? {
        var text = word.lowercased()
        var meridiem: Int?
        if text.hasSuffix("am") {
            meridiem = 0
            text.removeLast(2)
        } else if text.hasSuffix("pm") {
            meridiem = 12
            text.removeLast(2)
        }
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard !text.isEmpty, parts.count <= 2,
              parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isASCIIDigit) }),
              parts[0].count <= 2, let hour = Int(parts[0])
        else { return nil }
        var minute = 0
        if parts.count == 2 {
            guard parts[1].count == 2, let minutes = Int(parts[1]), minutes < 60 else { return nil }
            minute = minutes
        }
        if let meridiem {
            guard (1...12).contains(hour) else { return nil }
            return Clock(second: ((hour % 12 + meridiem) * 60 + minute) * 60, bare: false, meridiem: true)
        }
        if hour == 24, minute == 0 {
            return Clock(second: 86400, bare: parts.count == 1, meridiem: false)
        }
        guard hour < 24 else { return nil }
        return Clock(second: (hour * 60 + minute) * 60, bare: parts.count == 1, meridiem: false)
    }

    /// The weekday a name such as "wed" or "Wednesday" stands for, 1 for
    /// Sunday through 7 for Saturday.
    static func weekday(_ word: String) -> Int? {
        switch word.lowercased() {
        case "sun", "sunday": 1
        case "mon", "monday": 2
        case "tue", "tues", "tuesday": 3
        case "wed", "weds", "wednesday": 4
        case "thu", "thur", "thurs", "thursday": 5
        case "fri", "friday": 6
        case "sat", "saturday": 7
        default: nil
        }
    }

    /// The month a name such as "sep" or "September" stands for, 1 to 12.
    static func month(_ word: String) -> Int? {
        let names = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
        let full = ["january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november", "december"]
        let text = word.lowercased()
        if let index = names.firstIndex(of: text) ?? full.firstIndex(of: text) {
            return index + 1
        }
        return text == "sept" ? 9 : nil
    }

    /// A day written as "today", "yesterday", a weekday, which means the
    /// last one on or before today, or "2026-09-30".
    static func day(_ word: String, today: LocalDate) -> LocalDate? {
        let text = word.lowercased()
        switch text {
        case "today":
            return today
        case "yesterday":
            return today.adding(days: -1)
        default:
            break
        }
        if let weekday = weekday(text) {
            return today.adding(days: -((today.weekday - weekday + 7) % 7))
        }
        return isoDate(text)
    }

    /// A date written as "2026-09-30".
    static func isoDate(_ text: String) -> LocalDate? {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              parts.allSatisfy({ $0.allSatisfy(\.isASCIIDigit) }),
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              (1...12).contains(month), (1...LocalDate.daysIn(month: month, year: year)).contains(day)
        else { return nil }
        return LocalDate(year: year, month: month, day: day)
    }

    /// A day of a month without its year, as in "30 sep": the last one on
    /// or before today.
    static func date(day: Int, month: Int, today: LocalDate) -> LocalDate? {
        for year in [today.year, today.year - 1] {
            guard (1...LocalDate.daysIn(month: month, year: year)).contains(day) else { continue }
            let date = LocalDate(year: year, month: month, day: day)
            if date <= today {
                return date
            }
        }
        return nil
    }

    /// The day of the month in a word such as "30" or "30th".
    static func dayOfMonth(_ word: String) -> Int? {
        var text = word.lowercased()
        for suffix in ["st", "nd", "rd", "th"] where text.hasSuffix(suffix) {
            text.removeLast(2)
        }
        guard (1...2).contains(text.count), text.allSatisfy(\.isASCIIDigit), let day = Int(text), (1...31).contains(day) else {
            return nil
        }
        return day
    }

    /// The words a start time follows, as in "from 9:00".
    static let startWords: Set<String> = ["from", "since", "at", "starting"]

    /// The words an end time follows, as in "until 17:00".
    static let endWords: Set<String> = ["until", "till", "til", "to"]

    /// The dashes between two times: "-", "–" and "—".
    static let dashes: Set<Character> = ["-", "–", "—"]

    /// Whether a word is a dash between two times.
    static func isDash(_ word: String) -> Bool {
        word.count == 1 && word.allSatisfy(dashes.contains)
    }

    /// Splits a word such as "9:00-9:30" or "9–10" at its dash.
    static func splitRange(_ text: String) -> (String, String)? {
        guard let dash = text.firstIndex(where: dashes.contains), dash != text.startIndex else {
            return nil
        }
        return (String(text[..<dash]), String(text[text.index(after: dash)...]))
    }

    /// The milliseconds in a relative time written as "-15m", "−1h30" or
    /// "-1:30", meaning that long ago.
    static func ago(_ word: String) -> Int64? {
        guard let first = word.first, first == "-" || first == "−" else { return nil }
        let rest = String(word.dropFirst())
        if rest.contains(":") {
            return Durations.parse(rest).flatMap { $0 > 0 ? $0 : nil }
        }
        return Durations.parseWithUnit(rest)
    }

    /// The end of a range typed with times on either side of a dash: the
    /// end's time on the start's day, or the next day if that's not after
    /// the start. A plain hour that would end before the start, as in
    /// "11-1", reads as the afternoon one.
    static func rangeEnd(start: Clock, end: Clock) -> (second: Int, nextDay: Bool) {
        if end.second > start.second {
            return (end.second, false)
        }
        if end.bare || !end.meridiem, end.second < 43200, end.second + 43200 > start.second {
            return (end.second + 43200, false)
        }
        return (end.second, true)
    }

    /// Reads "9-11am" with the second time's am or pm applying to the first.
    static func range(_ first: String, _ second: String) -> (Clock, Clock)? {
        guard let end = clock(second) else { return nil }
        let saysMeridiem = first.lowercased().hasSuffix("m")
        if end.meridiem, !saysMeridiem {
            // "9-11am" and "11-1pm": the first time takes the second's am
            // or pm where that puts it first, and the other one otherwise.
            let same = end.second >= 43200 ? "pm" : "am"
            let other = end.second >= 43200 ? "am" : "pm"
            if let start = clock(first + same), start.second < end.second {
                return (start, end)
            }
            if let start = clock(first + other) {
                return (start, end)
            }
        }
        guard let start = clock(first) else { return nil }
        return (start, end)
    }
}
