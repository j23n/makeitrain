import Foundation

/// A report typed as words, such as "northbridge sep by tag": the clients,
/// projects and tags it covers, its days and how it's grouped. Words it
/// doesn't know are marked and left out.
public struct ReportQuery: Hashable, Sendable {
    /// The days, or nil when the words name no period.
    public var range: ClosedRange<LocalDate>?
    /// How the days step and compare: a day, week or month, or custom.
    public var period: ReportPeriod?
    public var grouping: ReportRequest.Grouping?
    /// Clients to include, or all when empty.
    public var clients: Set<UUID> = []
    /// Projects to include, or all when empty.
    public var projects: Set<UUID> = []
    /// Tags to include, or all when empty.
    public var tags: Set<String> = []
    public var tokens: [CommandToken] = []

    public init() {}

    /// Reads a typed report. Months without a year are the last ones up to
    /// `today`; weeks start on `firstWeekday`, 1 for Sunday.
    public static func read(_ text: String, ledger: Ledger, today: LocalDate, firstWeekday: Int) -> ReportQuery {
        let context = CommandContext(
            ledger: ledger,
            resolved: [],
            projectTags: [:],
            now: Timestamp(date: today, secondOfDay: 43200, zone: "UTC"),
            timeZone: "UTC"
        )
        var reader = CommandReader(text: text, context: context)
        return reader.readReport(today: today, firstWeekday: firstWeekday)
    }
}

extension CommandReader {
    static let fillers: Set<String> = ["in", "for", "of", "from", "during", "and", "&", ",", "on", "over", "report"]

    mutating func readReport(today: LocalDate, firstWeekday: Int) -> ReportQuery {
        var query = ReportQuery()
        var knownTags: [String]?
        var index = 0
        while index < words.count {
            let text = words[index].lower
            if text == "by", let next = word(index + 1), let grouping = Self.grouping(next) {
                query.grouping = grouping
                token(.keyword, index..<index + 2)
                index += 2
            } else if case let (span, kind, count)? = period(at: index, today: today, firstWeekday: firstWeekday) {
                query.range = span
                query.period = kind
                token(.time, index..<index + count)
                index += count
            } else if text.hasPrefix("#") {
                if knownTags == nil {
                    knownTags = context.ledger.allTags()
                }
                if let tag = Self.tag(words[index].text, known: knownTags ?? []) {
                    query.tags.insert(tag)
                }
                token(.tag, index..<index + 1)
                index += 1
            } else if Self.fillers.contains(text) {
                token(.keyword, index..<index + 1)
                index += 1
            } else {
                // The longest run of up to three plain words that names a
                // client or project.
                var run = 1
                while run < 3, index + run < words.count, !isSpecial(at: index + run, today: today, firstWeekday: firstWeekday) {
                    run += 1
                }
                var matched = false
                for count in stride(from: run, through: 1, by: -1) {
                    guard let found = target(matching: phrase(index..<index + count)) else { continue }
                    switch found {
                    case let .project(id):
                        query.projects.insert(id)
                    case let .client(id):
                        query.clients.insert(id)
                    }
                    token(kind(of: found), index..<index + count)
                    index += count
                    matched = true
                    break
                }
                if !matched {
                    token(.unknown, index..<index + 1)
                    index += 1
                }
            }
        }
        query.tokens = reading.tokens
        return query
    }

    /// Whether the word at `index` starts something other than a name.
    func isSpecial(at index: Int, today: LocalDate, firstWeekday: Int) -> Bool {
        guard let text = word(index) else { return true }
        return text == "by" || text.hasPrefix("#") || Self.fillers.contains(text)
            || period(at: index, today: today, firstWeekday: firstWeekday) != nil
    }

    static func grouping(_ word: String) -> ReportRequest.Grouping? {
        switch word {
        case "client", "clients": .client
        case "project", "projects": .project
        case "tag", "tags", "issue", "issues": .tag
        default: nil
        }
    }

    /// A year written as "2026".
    func year(at index: Int) -> Int? {
        guard let text = word(index), text.count == 4, text.allSatisfy(\.isASCIIDigit), let year = Int(text),
              (1900...2200).contains(year)
        else { return nil }
        return year
    }

    /// The days a period at `index` covers, its kind, and how many words it
    /// takes: "today", "this week", "last month", "sep", "sep 2026",
    /// "sep-oct", "1-15 sep", "q3", "2026", "2026-09-01 to 2026-09-15".
    func period(at index: Int, today: LocalDate, firstWeekday: Int) -> (ClosedRange<LocalDate>, ReportPeriod, Int)? {
        guard let text = word(index) else { return nil }
        func lastDay(_ year: Int, _ month: Int) -> LocalDate {
            LocalDate(year: year, month: month, day: LocalDate.daysIn(month: month, year: year))
        }
        /// The year of the last such month up to today.
        func recentYear(_ month: Int) -> Int {
            month <= today.month ? today.year : today.year - 1
        }
        switch text {
        case "today":
            return (today...today, .day, 1)
        case "yesterday":
            let day = today.adding(days: -1)
            return (day...day, .day, 1)
        case "ytd":
            return (LocalDate(year: today.year, month: 1, day: 1)...today, .custom, 1)
        case "this", "last", "previous":
            guard let unit = word(index + 1) else { return nil }
            let back = text == "this" ? 0 : -1
            switch unit {
            case "week":
                let range = ReportPeriod.week.range(containing: today, firstWeekday: firstWeekday)
                return (ReportPeriod.week.shift(range, by: back, firstWeekday: firstWeekday), .week, 2)
            case "month":
                let range = ReportPeriod.month.range(containing: today, firstWeekday: firstWeekday)
                return (ReportPeriod.month.shift(range, by: back, firstWeekday: firstWeekday), .month, 2)
            case "year":
                let lastYear = today.year + back
                return (LocalDate(year: lastYear, month: 1, day: 1)...LocalDate(year: lastYear, month: 12, day: 31), .custom, 2)
            default:
                return nil
            }
        default:
            break
        }

        // Months: "sep", "sep 2026", "sep to oct", "sep-oct".
        var firstMonth: Int?
        var lastMonth: Int?
        var count = 1
        if let month = TimeWords.month(text) {
            firstMonth = month
            if let separator = word(index + 1), separator == "to" || TimeWords.isDash(separator),
               let next = word(index + 2), let other = TimeWords.month(next) {
                lastMonth = other
                count = 3
            }
        } else if case let (first, second)? = TimeWords.splitRange(text), let month = TimeWords.month(first),
                  let other = TimeWords.month(second) {
            firstMonth = month
            lastMonth = other
        }
        if let firstMonth {
            var chosenYear = recentYear(lastMonth ?? firstMonth)
            if let typed = year(at: index + count) {
                chosenYear = typed
                count += 1
            }
            let last = lastMonth ?? firstMonth
            let startYear = last < firstMonth ? chosenYear - 1 : chosenYear
            let start = LocalDate(year: startYear, month: firstMonth, day: 1)
            let kind: ReportPeriod = lastMonth == nil || lastMonth == firstMonth ? .month : .custom
            return (start...lastDay(chosenYear, last), kind, count)
        }

        // Days of a month: "1-15 sep".
        if case let (first, second)? = TimeWords.splitRange(text), let from = TimeWords.dayOfMonth(first),
           let to = TimeWords.dayOfMonth(second), let next = word(index + 1), let month = TimeWords.month(next) {
            var chosenYear = recentYear(month)
            var used = 2
            if let typed = year(at: index + 2) {
                chosenYear = typed
                used = 3
            }
            let days = LocalDate.daysIn(month: month, year: chosenYear)
            guard from <= to, to <= days else { return nil }
            return (LocalDate(year: chosenYear, month: month, day: from)...LocalDate(year: chosenYear, month: month, day: to), .custom, used)
        }

        // Dates: "2026-09-30", "2026-09-01 to 2026-09-15", "2026-09-01..2026-09-15".
        if let date = TimeWords.isoDate(text) {
            if let separator = word(index + 1), separator == "to" || separator == ".." || TimeWords.isDash(separator),
               let next = word(index + 2), let other = TimeWords.isoDate(next) {
                return (min(date, other)...max(date, other), .custom, 3)
            }
            return (date...date, .day, 1)
        }
        if let dots = text.range(of: ".."), let first = TimeWords.isoDate(String(text[..<dots.lowerBound])),
           let second = TimeWords.isoDate(String(text[dots.upperBound...])) {
            return (min(first, second)...max(first, second), .custom, 1)
        }

        // A quarter, "q3" or "q3 2025", the last one up to today.
        if text.count == 2, text.first == "q", let quarter = Int(String(text.dropFirst())), (1...4).contains(quarter) {
            let firstOfQuarter = (quarter - 1) * 3 + 1
            var chosenYear = firstOfQuarter <= today.month ? today.year : today.year - 1
            var used = 1
            if let typed = year(at: index + 1) {
                chosenYear = typed
                used = 2
            }
            return (LocalDate(year: chosenYear, month: firstOfQuarter, day: 1)...lastDay(chosenYear, firstOfQuarter + 2), .custom, used)
        }

        // A year.
        if let typedYear = year(at: index) {
            return (LocalDate(year: typedYear, month: 1, day: 1)...LocalDate(year: typedYear, month: 12, day: 31), .custom, 1)
        }
        return nil
    }
}
