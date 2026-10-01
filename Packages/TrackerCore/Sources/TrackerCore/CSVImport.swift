import Foundation

/// Entries read from a CSV file: the app's own export, or the detailed
/// export of another time tracker.
///
/// Columns are found by their headings, ignoring case and order:
///
/// - `start` and `end`: date-times with an offset, as the app exports them,
///   such as "2026-09-23T09:00:00+02:00"; a date and time without one, such
///   as "2026-09-23 09:00"; or just a time, such as "09:00" or "9:00 PM",
///   on the day in `start date` or `date`, and in `end date`. Date-times can
///   also be written compactly, as "20260923T070000Z". Times without an
///   offset are read in the time zone given, and so are times in UTC,
///   ending in "Z", which don't say where the work was done. An end time
///   earlier than the start is on the next day, unless an end date says
///   otherwise.
/// - `duration` ("1:30", "1:30:00", or hours such as "1.5") or `hours`,
///   when there's no end. Rows with a day and a duration but no times are
///   placed one after another from 9:00.
/// - `client`, `project`, `tags` (separated by ";" or ","), and `note`,
///   `notes` or `description`.
///
/// Dates can be written "2026-09-23", "20260923", "23.09.2026",
/// "09/23/2026" or "23/09/2026"; with slashes, the day comes first if any
/// date in the file says so. Commas, semicolons and tabs all separate
/// fields, whichever the heading uses.
///
/// Clients and projects are matched by name, ignoring case, and added when
/// they're new. A row with the same start, end, project and note as an
/// entry that's already there, or as an earlier row, is skipped, so
/// importing a file twice adds its entries once.
public enum CSVImport {
    /// A row that couldn't be read.
    public struct Problem: Hashable, Sendable {
        /// The row's line in the file; the heading is line 1.
        public var line: Int
        public var message: String

        public init(line: Int, message: String) {
            self.line = line
            self.message = message
        }
    }

    /// What importing a file adds.
    public struct Plan: Sendable {
        public var entries: [TimeEntry] = []
        public var clients: [Client] = []
        public var projects: [Project] = []
        /// Rows skipped because their entry is already there.
        public var alreadyThere = 0
        /// Entries that had a day and a duration but no times, placed one
        /// after another from 9:00.
        public var placed = 0
        public var problems: [Problem] = []

        public init() {}

        /// The days the new entries are on, in their own time zones.
        public var days: ClosedRange<LocalDate>? {
            let days = entries.map(\.day)
            guard let first = days.min(), let last = days.max() else { return nil }
            return first...last
        }
    }

    /// Why a file can't be imported at all.
    public enum Failure: LocalizedError, Hashable, Sendable {
        /// The file has no rows under its heading.
        case noRows
        /// No heading says when entries start, such as "start" or "date".
        case noStartColumn

        public var message: String {
            switch self {
            case .noRows:
                "The file has no rows to import."
            case .noStartColumn:
                "The file has no column for when entries start. Its first line should name the columns, such as \"start\", \"end\" and \"project\"."
            }
        }

        public var errorDescription: String? {
            message
        }
    }

    /// The entries, clients and projects importing `data` adds to `ledger`.
    /// Times without an offset are read in `timeZone`. New projects get
    /// `color`.
    public static func plan(
        _ data: Data,
        into ledger: Ledger,
        timeZone: String,
        color: String = "#4F7CAC",
        now: Timestamp
    ) throws -> Plan {
        let text = decode(data)
        let separator = separator(in: text)
        let lines = records(text, separator: separator).filter { record in
            record.fields.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        }
        guard let heading = lines.first, lines.count > 1 else { throw Failure.noRows }
        let columns = Columns(heading.fields)
        guard columns.has(.start) || columns.has(.startDate) || columns.has(.date) else {
            throw Failure.noStartColumn
        }
        var reader = Reader(ledger: ledger, columns: columns, timeZone: timeZone, color: color, now: now)
        reader.dayFirst = lines.dropFirst().contains { record in
            [Column.start, .end, .startDate, .endDate, .date].contains { column in
                dayComesFirst(columns.value(column, in: record.fields))
            }
        }
        for record in lines.dropFirst() {
            do {
                try reader.read(record.fields)
            } catch let problem as RowProblem {
                reader.plan.problems.append(Problem(line: record.line, message: problem.message))
            }
        }
        return reader.plan
    }

    // MARK: - Columns

    enum Column: CaseIterable {
        case start, startDate, end, endDate, date, duration, hours, client, project, tags, note

        /// Headings for the column, ignoring case.
        var headings: [String] {
            switch self {
            case .start: ["start", "start time", "started", "started at", "from", "begin"]
            case .startDate: ["start date", "started on"]
            case .end: ["end", "end time", "stop", "stop time", "stopped", "ended", "to", "finish"]
            case .endDate: ["end date", "stop date"]
            case .date: ["date", "day"]
            case .duration: ["duration", "duration (h)", "length"]
            case .hours: ["hours", "duration (decimal)", "decimal hours", "hours (decimal)"]
            case .client: ["client", "customer", "client name"]
            case .project: ["project", "project name"]
            case .tags: ["tags", "tag", "labels"]
            case .note: ["note", "notes", "description", "comment", "comments", "memo"]
            }
        }
    }

    /// Where each column is in a row, from the heading.
    struct Columns {
        var index: [Column: Int] = [:]

        init(_ heading: [String]) {
            let names = heading.map { name in
                name.trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                    .split(whereSeparator: \.isWhitespace)
                    .joined(separator: " ")
            }
            for column in Column.allCases {
                index[column] = column.headings.lazy.compactMap { names.firstIndex(of: $0) }.first
            }
        }

        func has(_ column: Column) -> Bool {
            index[column] != nil
        }

        /// The column's value in a row, trimmed, or "" if there's none.
        func value(_ column: Column, in fields: [String]) -> String {
            guard let at = index[column], at < fields.count else { return "" }
            return fields[at].trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    // MARK: - Rows

    struct RowProblem: Error {
        var message: String
    }

    /// Reads rows into a plan, matching and adding clients and projects.
    struct Reader {
        let ledger: Ledger
        let columns: Columns
        let timeZone: String
        let color: String
        let now: Timestamp
        var dayFirst = false
        var plan = Plan()
        /// Client ids by lowercased name.
        var clients: [String: UUID] = [:]
        /// Project ids by client id and lowercased name.
        var projects: [ProjectKey: UUID] = [:]
        /// The entries already there and read so far, to skip repeats.
        var seen: Set<String> = []
        /// Where the next entry without times goes on each day.
        var nextPlaced: [LocalDate: Int] = [:]
        let knownTags: [String]

        struct ProjectKey: Hashable {
            var client: UUID?
            var name: String
        }

        init(ledger: Ledger, columns: Columns, timeZone: String, color: String, now: Timestamp) {
            self.ledger = ledger
            self.columns = columns
            self.timeZone = timeZone
            self.color = color
            self.now = now
            knownTags = ledger.allTags()
            for client in ledger.liveClients() where clients[client.name.lowercased()] == nil {
                clients[client.name.lowercased()] = client.id
            }
            for project in ledger.projects.values.sorted(by: { $0.id.uuidString < $1.id.uuidString }) where !project.isDeleted {
                let key = ProjectKey(client: project.clientID, name: project.name.lowercased())
                if projects[key] == nil {
                    projects[key] = project.id
                }
            }
            for resolved in ledger.resolvedEntries() {
                guard let end = resolved.end else { continue }
                let project = resolved.entry.projectID.flatMap { ledger.projects[$0] }
                let client = ledger.client(forProject: resolved.entry.projectID)
                seen.insert(Self.key(
                    start: resolved.start,
                    end: end,
                    client: client?.name ?? "",
                    project: project?.name ?? "",
                    note: resolved.entry.note
                ))
            }
        }

        static func key(start: Timestamp, end: Timestamp, client: String, project: String, note: String) -> String {
            let projectPart = project.isEmpty ? "" : "\(client.lowercased())\u{1F}\(project.lowercased())"
            return "\(start.wholeSeconds.milliseconds)\u{1F}\(end.wholeSeconds.milliseconds)\u{1F}\(projectPart)\u{1F}\(note)"
        }

        mutating func read(_ fields: [String]) throws {
            let columns = self.columns
            func value(_ column: Column) -> String {
                columns.value(column, in: fields)
            }
            let (start, end, zone, placed) = try times(value)
            guard end >= start else {
                throw RowProblem(message: "It ends before it starts.")
            }
            let projectName = value(.project)
            let clientName = projectName.isEmpty ? "" : value(.client)
            let note = value(.note)
            let key = Self.key(start: start, end: end, client: clientName, project: projectName, note: note)
            guard seen.insert(key).inserted else {
                plan.alreadyThere += 1
                return
            }
            if placed {
                plan.placed += 1
            }
            let known = knownTags
            let tags = Tags.normalize(value(.tags).split(whereSeparator: { $0 == ";" || $0 == "," }).map(String.init))
                .map { tag in known.first { Tags.same($0, tag) } ?? tag }
            let project = projectName.isEmpty ? nil : projectID(named: projectName, client: clientName)
            plan.entries.append(TimeEntry(
                projectID: project,
                start: start.wholeSeconds,
                end: end.wholeSeconds,
                timeZone: zone,
                tags: tags,
                note: note,
                updated: now
            ))
        }

        /// A row's start, end and time zone, and whether it had no times
        /// and was placed after the day's others.
        mutating func times(_ value: (Column) -> String) throws -> (Timestamp, Timestamp, String, Bool) {
            let startText = value(.start)
            let endText = value(.end)
            let dayText = columns.has(.startDate) ? value(.startDate) : value(.date)
            // Compact ISO 8601, as "20260713T152036Z", reads as the usual form.
            let startISO = CSVImport.extended(startText)
            let endISO = CSVImport.extended(endText)
            let day = CSVImport.date(CSVImport.extended(dayText), dayFirst: dayFirst)
            if !dayText.isEmpty, day == nil {
                throw RowProblem(message: "Can't read the date \u{201C}\(dayText)\u{201D}.")
            }
            let duration = try self.duration(value)

            // The start: a date-time, or a time on the row's day.
            let start: Timestamp
            let zone: String
            if let (time, offset) = DateTimeFormat.parseWithOffset(startISO) {
                start = time
                // A time in UTC doesn't say where the work was done, so it's
                // shown in this device's zone. An offset keeps the time of
                // day the entry was recorded at.
                zone = CSVImport.isUTC(startISO) ? timeZone : CSVImport.zone(forOffset: offset, at: time, preferring: timeZone)
            } else if let (date, second) = CSVImport.localDateTime(startISO, dayFirst: dayFirst) {
                start = Timestamp(date: date, secondOfDay: second, zone: timeZone)
                zone = timeZone
            } else if !startText.isEmpty {
                guard let second = CSVImport.clockTime(startText) else {
                    throw RowProblem(message: "Can't read the start \u{201C}\(startText)\u{201D}.")
                }
                guard let day else {
                    throw RowProblem(message: "The start \u{201C}\(startText)\u{201D} has no date.")
                }
                start = Timestamp(date: day, secondOfDay: second, zone: timeZone)
                zone = timeZone
            } else if let day, endText.isEmpty, let duration {
                // No times: after the day's last entry placed like this.
                let second = nextPlaced[day] ?? 9 * 3600
                nextPlaced[day] = second + Int(duration / 1000)
                let placedStart = Timestamp(date: day, secondOfDay: second, zone: timeZone)
                return (placedStart, placedStart.adding(milliseconds: duration), timeZone, true)
            } else {
                throw RowProblem(message: day == nil ? "It has no start." : "It has a date but no start, end or duration.")
            }

            // The end: a date-time, a time, or the start plus the duration.
            let end: Timestamp
            if let (time, _) = DateTimeFormat.parseWithOffset(endISO) {
                end = time
            } else if let (date, second) = CSVImport.localDateTime(endISO, dayFirst: dayFirst) {
                end = Timestamp(date: date, secondOfDay: second, zone: zone)
            } else if !endText.isEmpty {
                guard let second = CSVImport.clockTime(endText) else {
                    throw RowProblem(message: "Can't read the end \u{201C}\(endText)\u{201D}.")
                }
                let endDayText = value(.endDate)
                if let endDay = CSVImport.date(CSVImport.extended(endDayText), dayFirst: dayFirst) {
                    end = Timestamp(date: endDay, secondOfDay: second, zone: zone)
                } else if endDayText.isEmpty {
                    let startDay = start.local(in: zone).date
                    let sameDay = Timestamp(date: startDay, secondOfDay: second, zone: zone)
                    end = sameDay > start ? sameDay : Timestamp(date: startDay.adding(days: 1), secondOfDay: second, zone: zone)
                } else {
                    throw RowProblem(message: "Can't read the date \u{201C}\(endDayText)\u{201D}.")
                }
            } else if let duration {
                end = start.adding(milliseconds: duration)
            } else {
                throw RowProblem(message: "It has no end or duration.")
            }
            return (start, end, zone, false)
        }

        /// The row's duration, from its duration or hours column, if it has
        /// one.
        func duration(_ value: (Column) -> String) throws -> Int64? {
            for column in [Column.duration, .hours] {
                let text = value(column)
                guard !text.isEmpty else { continue }
                guard let duration = CSVImport.duration(text) else {
                    throw RowProblem(message: "Can't read the duration \u{201C}\(text)\u{201D}.")
                }
                return duration
            }
            return nil
        }

        /// The id of the project with this name and client, adding either
        /// when it's new.
        mutating func projectID(named name: String, client clientName: String) -> UUID {
            var clientID: UUID? = nil
            if !clientName.isEmpty {
                if let known = clients[clientName.lowercased()] {
                    clientID = known
                } else {
                    let client = Client(name: clientName, updated: now)
                    plan.clients.append(client)
                    clients[clientName.lowercased()] = client.id
                    clientID = client.id
                }
            }
            let key = ProjectKey(client: clientID, name: name.lowercased())
            if let known = projects[key] {
                return known
            }
            let project = Project(clientID: clientID, name: name, color: color, updated: now)
            plan.projects.append(project)
            projects[key] = project.id
            return project.id
        }
    }

    // MARK: - Reading the file

    /// The file's text: UTF-8, UTF-16 with a byte-order mark, or else
    /// Latin-1, without a leading byte-order mark.
    static func decode(_ data: Data) -> String {
        let text: String
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) {
            text = String(data: data, encoding: .utf16) ?? ""
        } else {
            text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
        }
        return text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
    }

    /// The separator the heading uses the most: a comma, semicolon or tab.
    static func separator(in text: String) -> Character {
        var counts: [Character: Int] = [:]
        var quoted = false
        for character in text {
            if character == "\"" {
                quoted.toggle()
            } else if !quoted, isLineBreak(character) {
                break
            } else if !quoted, character == "," || character == ";" || character == "\t" {
                counts[character, default: 0] += 1
            }
        }
        let candidates: [Character] = [",", ";", "\t"]
        return candidates.max { counts[$0, default: 0] < counts[$1, default: 0] } ?? ","
    }

    /// The file's records, each with the line it starts on. Quoted fields
    /// can hold separators, doubled quotes and line breaks.
    static func records(_ text: String, separator: Character) -> [(line: Int, fields: [String])] {
        var records: [(line: Int, fields: [String])] = []
        var fields: [String] = []
        var field = ""
        var quoted = false
        var afterQuote = false
        var line = 1
        var recordLine = 1
        for character in text {
            if quoted {
                if character == "\"" {
                    quoted = false
                    afterQuote = true
                } else {
                    if isLineBreak(character) {
                        line += 1
                    }
                    field.append(character)
                }
            } else if character == "\"" {
                if afterQuote {
                    // A doubled quote inside quotes.
                    field.append("\"")
                    quoted = true
                    afterQuote = false
                } else if field.isEmpty {
                    quoted = true
                } else {
                    field.append(character)
                }
            } else if character == separator {
                fields.append(field)
                field = ""
                afterQuote = false
            } else if isLineBreak(character) {
                fields.append(field)
                records.append((recordLine, fields))
                fields = []
                field = ""
                afterQuote = false
                line += 1
                recordLine = line
            } else {
                field.append(character)
                afterQuote = false
            }
        }
        if !field.isEmpty || !fields.isEmpty {
            fields.append(field)
            records.append((recordLine, fields))
        }
        return records
    }

    static func isLineBreak(_ character: Character) -> Bool {
        character == "\n" || character == "\r" || character == "\r\n"
    }

    // MARK: - Values

    /// A day written as "2026-09-23", "2026/09/23", "23.09.2026",
    /// "23-09-2026", or with slashes, "09/23/2026", or "23/09/2026" when
    /// `dayFirst`. Two-digit years are in this century.
    static func date(_ text: String, dayFirst: Bool) -> LocalDate? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let parts = trimmed.split(omittingEmptySubsequences: false) { $0 == "-" || $0 == "/" || $0 == "." }
        guard parts.count == 3, parts.allSatisfy({ (1...4).contains($0.count) && $0.allSatisfy(\.isASCIIDigit) }) else {
            return nil
        }
        let numbers = parts.compactMap { Int($0) }
        guard numbers.count == 3 else { return nil }
        let year: Int
        let month: Int
        let day: Int
        if parts[0].count == 4 {
            year = numbers[0]
            month = numbers[1]
            day = numbers[2]
        } else {
            year = parts[2].count == 2 ? 2000 + numbers[2] : numbers[2]
            if trimmed.contains("/"), !dayFirst {
                month = numbers[0]
                day = numbers[1]
            } else {
                day = numbers[0]
                month = numbers[1]
            }
        }
        guard year >= 1970, year < 10000, (1...12).contains(month),
              (1...LocalDate.daysIn(month: month, year: year)).contains(day)
        else { return nil }
        return LocalDate(year: year, month: month, day: day)
    }

    /// Whether a date with slashes can only be read with the day first, as
    /// "23/09/2026" can.
    static func dayComesFirst(_ text: String) -> Bool {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: "/")
        guard parts.count >= 3, parts[0].count <= 2, let first = Int(parts[0]) else { return false }
        return first > 12
    }

    /// A time of day written as "09:00", "9:00:30" or "9:00 PM", as seconds
    /// after midnight.
    static func clockTime(_ text: String) -> Int? {
        var typed = text.lowercased().filter { !$0.isWhitespace }
        var afternoon: Bool? = nil
        for (suffix, pm) in [("a.m.", false), ("p.m.", true), ("am", false), ("pm", true)] where typed.hasSuffix(suffix) {
            typed.removeLast(suffix.count)
            afternoon = pm
            break
        }
        let parts = typed.split(separator: ":", omittingEmptySubsequences: false)
        guard (2...3).contains(parts.count),
              parts.allSatisfy({ (1...2).contains($0.count) && $0.allSatisfy(\.isASCIIDigit) })
        else { return nil }
        let numbers = parts.compactMap { Int($0) }
        var hour = numbers[0]
        let minute = numbers[1]
        let second = numbers.count == 3 ? numbers[2] : 0
        guard minute < 60, second < 60 else { return nil }
        if let afternoon {
            guard (1...12).contains(hour) else { return nil }
            hour = hour % 12 + (afternoon ? 12 : 0)
        } else {
            guard hour < 24 || (hour == 24 && minute == 0 && second == 0) else { return nil }
        }
        return (hour * 60 + minute) * 60 + second
    }

    /// A date and time without an offset, such as "2026-09-23 09:00" or
    /// "09/23/2026 9:00 AM".
    static func localDateTime(_ text: String, dayFirst: Bool) -> (LocalDate, Int)? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let split = trimmed.firstIndex(where: { $0 == "T" || $0 == "t" || $0 == " " }),
              let day = date(String(trimmed[..<split]), dayFirst: dayFirst),
              let second = clockTime(String(trimmed[trimmed.index(after: split)...]))
        else { return nil }
        return (day, second)
    }

    /// A date or date-time in ISO 8601's compact form, as "20260713" or
    /// "20260713T152036Z", in the usual one the other readers take, as
    /// "2026-07-13" or "2026-07-13T15:20:36Z", and anything else as it is.
    /// The seconds can be left out and fractions of them are dropped; the
    /// zone is "Z" or an offset such as "+02", "+0200" or "+02:00".
    static func extended(_ text: String) -> String {
        let characters = Array(text.trimmingCharacters(in: .whitespaces))
        func digits(_ range: Range<Int>) -> String? {
            guard range.upperBound <= characters.count, characters[range].allSatisfy(\.isASCIIDigit) else { return nil }
            return String(characters[range])
        }
        guard let year = digits(0..<4), let month = digits(4..<6), let day = digits(6..<8) else { return text }
        let date = "\(year)-\(month)-\(day)"
        if characters.count == 8 {
            return date
        }
        guard "Tt ".contains(characters[8]), let hour = digits(9..<11), let minute = digits(11..<13) else { return text }
        var index = 13
        var second = "00"
        if let seconds = digits(13..<15) {
            second = seconds
            index = 15
        }
        if index < characters.count, characters[index] == "." || characters[index] == "," {
            let fraction = index + 1
            index = fraction
            while index < characters.count, characters[index].isASCIIDigit {
                index += 1
            }
            guard index > fraction else { return text }
        }
        let time = "\(date)T\(hour):\(minute):\(second)"
        let zone = Array(characters[index...])
        guard let sign = zone.first else { return time }
        if zone == ["Z"] || zone == ["z"] {
            return time + "Z"
        }
        guard sign == "+" || sign == "-" else { return text }
        // "+02", "+0200" or "+02:00".
        let offset = String(zone.dropFirst())
        let hours = String(offset.prefix(2))
        let minutes: String
        switch offset.count {
        case 2: minutes = "00"
        case 4: minutes = String(offset.suffix(2))
        case 5 where Array(offset)[2] == ":": minutes = String(offset.suffix(2))
        default: return text
        }
        guard (hours + minutes).allSatisfy(\.isASCIIDigit) else { return text }
        return time + "\(sign)\(hours):\(minutes)"
    }

    /// Whether a date-time is in UTC, ending in "Z".
    static func isUTC(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        return trimmed.hasSuffix("Z") || trimmed.hasSuffix("z")
    }

    /// A duration written as "1:30", "1:30:00", or hours such as "1.5" or
    /// "1,5", in milliseconds. Minutes and seconds have two digits.
    static func duration(_ text: String) -> Int64? {
        let typed = text.filter { !$0.isWhitespace }
        guard !typed.isEmpty else { return nil }
        if typed.contains(":") {
            let parts = typed.split(separator: ":", omittingEmptySubsequences: false)
            guard (2...3).contains(parts.count),
                  parts.allSatisfy({ !$0.isEmpty && $0.count <= 6 && $0.allSatisfy(\.isASCIIDigit) }),
                  parts.dropFirst().allSatisfy({ $0.count == 2 })
            else { return nil }
            let numbers = parts.compactMap { Int($0) }
            guard numbers.count == parts.count, numbers.dropFirst().allSatisfy({ $0 < 60 }) else { return nil }
            let seconds = numbers[0] * 3600 + numbers[1] * 60 + (numbers.count == 3 ? numbers[2] : 0)
            return Int64(seconds) * 1000
        }
        guard let hours = Double(typed.replacingOccurrences(of: ",", with: ".")), hours >= 0, hours < 10000 else {
            return nil
        }
        return Int64((hours * 3_600_000).rounded())
    }

    /// The zone for a time written with an offset: `zone` if its offset is
    /// the same then, or else a zone with that fixed offset, such as
    /// "GMT-0400".
    static func zone(forOffset offset: Int, at time: Timestamp, preferring zone: String) -> String {
        if Zones.offset(zone, at: time) == offset {
            return zone
        }
        if offset == 0 {
            return "UTC"
        }
        return TimeZone(secondsFromGMT: offset)?.identifier ?? "UTC"
    }
}

extension Ledger {
    /// Adds what a CSV file's import plan found: its clients, projects and
    /// entries.
    @discardableResult
    public mutating func add(_ plan: CSVImport.Plan, now: Timestamp) -> Changes {
        var changes = settleOvertakenTimers(now: now)
        for client in plan.clients {
            changes.formUnion(addClient(client, now: now))
        }
        for project in plan.projects {
            changes.formUnion(addProject(project, now: now))
        }
        for entry in plan.entries {
            changes.formUnion(addEntry(entry, now: now))
        }
        return changes
    }
}
