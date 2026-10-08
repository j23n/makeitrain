import Foundation

// The command line: one line of text that starts, switches, stops or logs
// time, or manages clients and projects. `CommandReading(_:in:)` works out
// what a line means as it's typed, with its parts for highlighting, and
// `Ledger.perform` carries it out. Nothing changes until it's performed.

/// An entry as a line describes it: a project, tags and a note.
public struct EntryDraft: Hashable, Sendable {
    /// nil for "Unassigned".
    public var projectID: UUID?
    public var tags: [String]
    public var note: String

    public init(projectID: UUID? = nil, tags: [String] = [], note: String = "") {
        self.projectID = projectID
        self.tags = tags
        self.note = note
    }

    /// No project, tags or note.
    public var isEmpty: Bool {
        projectID == nil && tags.isEmpty && note.isEmpty
    }

    /// Whether an entry has this project, these tags in any order and case,
    /// and this note.
    public func matches(_ entry: TimeEntry) -> Bool {
        Combination(projectID: projectID, tags: tags).matches(entry) && entry.note == note
    }
}

/// A client or project a command acts on.
public enum CommandTarget: Hashable, Sendable {
    case project(UUID)
    case client(UUID)
}

/// The client a new project goes to.
public enum ClientChoice: Hashable, Sendable {
    case existing(UUID)
    /// A client that's added with the project.
    case new(String)
}

/// What a line does.
public enum Command: Hashable, Sendable {
    /// Starts a timer at `start`, stopping the running one at that moment.
    /// With an `end`, the new entry stops there at once, for "log it as
    /// done".
    case start(EntryDraft, at: Timestamp, end: Timestamp?)
    /// Adds a finished entry. The running timer keeps running.
    case log(EntryDraft, start: Timestamp, end: Timestamp)
    /// Stops the running timer.
    case stop(at: Timestamp)
    /// Moves the running timer's start, as when work began earlier.
    case moveStart(to: Timestamp)
    /// Adds a project, and its client if that's new. `startsTimer` starts a
    /// timer for it too.
    case addProject(name: String, client: ClientChoice?, color: String, startsTimer: Bool)
    case addClient(name: String)
    case archive(CommandTarget, archived: Bool)
    case setColor(project: UUID, color: String)
    case merge(CommandTarget, into: CommandTarget)
    case rename(CommandTarget, to: String)
    /// Lists the entries that match, without changing anything.
    case find(String)
}

/// Why a line can't do what it says.
public enum CommandProblem: Hashable, Sendable {
    /// "stop", or a start time with nothing to move, while no timer runs.
    case notRunning
    /// The time is before the running timer started, at this time.
    case beforeRunningStart(Timestamp)
    case startsInFuture
    case endsInFuture
    case endsBeforeStart
    /// What's typed is running already.
    case runningAlready
    /// "Log it as done" needs to know when it started.
    case needsStart
    /// A name is missing, as in "new project".
    case needsName
    /// "color" needs a color after the project.
    case needsColor
    case unknownColor(String)
    /// "merge" needs "into" and what to merge into.
    case needsTarget
    /// No client or project has this name.
    case notFound(String)
    /// A client or project with this name is there already.
    case nameTaken(String)
    /// Merging something into itself.
    case sameTarget
    /// Merging a project into a client, or the other way round.
    case mixedTargets
}

/// A part of a typed line, for highlighting it.
public struct CommandToken: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        /// A word that says what to do, such as "stop" or "new project".
        case keyword
        case project(UUID)
        case client(UUID)
        case tag
        /// A time, day or duration, such as "from 11:05" or "9:00-9:30".
        case time
        /// The name of something new, as in "new project Phoenix".
        case name
        /// A color, as hex.
        case color(String)
        case note
        /// A name that matches no client or project.
        case unknown
    }

    public var kind: Kind
    public var range: Range<String.Index>
}

/// A way to finish a line, taken from an earlier entry, offered on Tab.
public struct CommandCompletion: Hashable, Sendable {
    /// The whole line, finished.
    public var text: String
    /// The entry it's taken from.
    public var entryID: UUID
    /// That entry's day.
    public var day: LocalDate
}

/// What a typed line means.
public struct CommandReading: Hashable, Sendable {
    public var text: String
    public var tokens: [CommandToken] = []
    /// What Return does, or nil.
    public var primary: Command?
    /// What Option-Return does, or nil: "log it as done" for a timer, or
    /// "add it and start a timer" for a new project.
    public var alternate: Command?
    /// Why Return can't do what the line says.
    public var problem: CommandProblem?
    /// Why Option-Return can't.
    public var alternateProblem: CommandProblem?
    public var completion: CommandCompletion?

    public init(text: String) {
        self.text = text
    }

    /// The entry the line describes, for a line that starts or logs one.
    public var draft: EntryDraft? {
        switch primary ?? alternate {
        case let .start(draft, _, _)?, let .log(draft, _, _)?: draft
        default: nil
        }
    }
}

/// What reading a line needs to know.
public struct CommandContext: Sendable {
    public var ledger: Ledger
    /// The ledger's entries, resolved, sorted by start.
    public var resolved: [ResolvedEntry]
    /// Each project's tags, as `Ledger.tagsByProject()` lists them.
    public var projectTags: [UUID?: [String]]
    public var now: Timestamp
    /// The zone times are typed in and new entries are recorded in.
    public var timeZone: String
    /// When each project was last used, for choosing between projects that
    /// match what's typed equally well.
    var lastUsed: [UUID: Timestamp]

    public init(
        ledger: Ledger,
        resolved: [ResolvedEntry],
        projectTags: [UUID?: [String]],
        now: Timestamp,
        timeZone: String
    ) {
        self.ledger = ledger
        self.resolved = resolved
        self.projectTags = projectTags
        self.now = now
        self.timeZone = timeZone
        var lastUsed: [UUID: Timestamp] = [:]
        for entry in resolved {
            if let projectID = entry.entry.projectID {
                lastUsed[projectID] = entry.start
            }
        }
        self.lastUsed = lastUsed
    }

    public var today: LocalDate {
        now.local(in: timeZone).date
    }

    public var running: ResolvedEntry? {
        resolved.last { $0.isRunning }
    }

    /// When the last entry that ended today ended, if that's before now:
    /// the start of something logged as done without a time.
    public var lastEndToday: Timestamp? {
        let midnight = Timestamp(date: today, secondOfDay: 0, zone: timeZone)
        return resolved.compactMap(\.end).filter { $0 >= midnight && $0 < now }.max()
    }

    /// Projects whose name, or whose client's, has a word starting with
    /// each word of `phrase`, with their client's name and how well they
    /// match: the best matches first, then the ones used last. Every
    /// project matches an empty phrase.
    func projects(matching phrase: String, includingArchived: Bool) -> [(project: Project, client: String, rank: Int)] {
        let terms = ProjectSearch.terms(phrase)
        let candidates = includingArchived
            ? ledger.projects.values.filter { !$0.isDeleted }.sorted(by: Project.fileOrder)
            : ledger.pickerProjects()
        var matches: [(project: Project, client: String, rank: Int, last: Int64, index: Int)] = []
        for (index, project) in candidates.enumerated() {
            let client = ledger.client(forProject: project.id)?.name ?? ""
            guard let rank = ProjectSearch.rank(terms, project: project.name, client: client), rank <= 1 else { continue }
            matches.append((project, client, rank, lastUsed[project.id]?.milliseconds ?? .min, index))
        }
        matches.sort { a, b in
            if a.rank != b.rank { return a.rank < b.rank }
            if a.last != b.last { return a.last > b.last }
            return a.index < b.index
        }
        return matches.map { (project: $0.project, client: $0.client, rank: $0.rank) }
    }
}

extension CommandReading {
    /// What `text` means, as of `context`.
    public init(_ text: String, in context: CommandContext) {
        var reader = CommandReader(text: text, context: context)
        self = reader.read()
    }
}

extension Ledger {
    /// An entry written as a line the command line reads back, such as
    /// "2 oct 13:30-16:30 Website #12 Fix login", for editing it as text.
    /// A day 300 days or more before `today` is written with its year.
    public func line(for entry: ResolvedEntry, today: LocalDate) -> String {
        let zone = entry.entry.timeZone
        let start = entry.start.local(in: zone)
        let day = start.date
        func clock(_ time: LocalDateTime) -> String {
            TimeWords.clockText(secondOfDay: time.millisecondOfDay / 1000)
        }
        var parts = [today.daysSince1970 - day.daysSince1970 < 300 ? "\(day.day) \(TimeWords.monthNames[day.month - 1])" : day.description]
        if let end = entry.end {
            parts.append("\(clock(start))-\(clock(end.local(in: zone)))")
        } else {
            parts.append("from \(clock(start))")
        }
        if let projectID = entry.entry.projectID, let project = projects[projectID] {
            parts.append(project.name)
        }
        // A "#" added here comes with dashes for spaces, as a line splits at
        // spaces.
        parts += entry.entry.tags.map { tag in
            let typed = Tags.typed(tag)
            return typed == tag ? tag : typed.replacingOccurrences(of: " ", with: "-")
        }
        if !entry.entry.note.isEmpty {
            parts.append(entry.entry.note)
        }
        return parts.joined(separator: " ")
    }
}

/// A word of a typed line and where it is.
struct CommandWord {
    var text: String
    var lower: String
    var range: Range<String.Index>
}

/// Reads one line. See `CommandReading(_:in:)`.
struct CommandReader {
    /// Words that don't start a project's name on their own, so a note
    /// such as "a quick fix" isn't read as a project.
    static let notProjects: Set<String> = ["a", "an", "and", "at", "for", "from", "i", "in", "my", "of", "on", "or", "the", "to", "with"]

    let text: String
    let context: CommandContext
    let words: [CommandWord]
    var reading: CommandReading

    init(text: String, context: CommandContext) {
        self.text = text
        self.context = context
        words = text.split(whereSeparator: \.isWhitespace).map { word in
            CommandWord(text: String(word), lower: word.lowercased(), range: word.startIndex..<word.endIndex)
        }
        reading = CommandReading(text: text)
    }

    mutating func read() -> CommandReading {
        guard let first = words.first else { return reading }
        switch first.lower {
        case "stop":
            if readStop() { return reading }
        case "new" where words.count >= 2 && (words[1].lower == "project" || words[1].lower == "client"):
            readNew()
            return reading
        case "archive", "unarchive":
            readArchive(archived: first.lower == "archive")
            return reading
        case "color", "colour":
            readColor()
            return reading
        case "merge":
            readMerge()
            return reading
        case "rename":
            readRename()
            return reading
        case "find", "search":
            readFind()
            return reading
        default:
            break
        }
        readEntry()
        return reading
    }

    // MARK: - Times

    /// A time piece of a line, such as "from 11:05", "-15m" or "9:00-9:30".
    enum TimePiece {
        case start(TimeWords.Clock)
        /// A start this many milliseconds ago, 0 for "from now".
        case startAgo(Int64)
        case end(TimeWords.Clock)
        case endNow
        case range(TimeWords.Clock, TimeWords.Clock)
        case duration(Int64)
    }

    func word(_ index: Int) -> String? {
        index < words.count ? words[index].lower : nil
    }

    /// A time of day at `index`, with "am" or "pm" as the next word if
    /// it's there, and how many words it takes.
    func clock(at index: Int) -> (TimeWords.Clock, Int)? {
        guard let text = word(index) else { return nil }
        if let next = word(index + 1), next == "am" || next == "pm", let time = TimeWords.clock(text + next) {
            return (time, 2)
        }
        return TimeWords.clock(text).map { ($0, 1) }
    }

    /// A duration at `index`, as "45m" or "45 min", and how many words it takes.
    func duration(at index: Int) -> (Int64, Int)? {
        guard let text = word(index) else { return nil }
        if let length = Durations.parseWithUnit(text) {
            return (length, 1)
        }
        if let unit = word(index + 1), Durations.unitWords.contains(where: { $0.word == unit }),
           text.allSatisfy({ $0.isASCIIDigit || $0 == "." || $0 == "," }),
           let length = Durations.parseWithUnit(text + unit) {
            return (length, 2)
        }
        return nil
    }

    /// A range at `index`, as "9:00-9:30", "9 - 10" or "9:00 to 17:00",
    /// and how many words it takes. Two plain numbers either side of "to"
    /// read as a range only after a word such as "from".
    func range(at index: Int, plainTo: Bool = false) -> ((TimeWords.Clock, TimeWords.Clock), Int)? {
        guard let text = word(index) else { return nil }
        if case let (first, second)? = TimeWords.splitRange(text) {
            if !second.isEmpty {
                if let next = word(index + 1), next == "am" || next == "pm", let span = TimeWords.range(first, second + next) {
                    return (span, 2)
                }
                return TimeWords.range(first, second).map { ($0, 1) }
            }
            // "9:00-" and then "9:30".
            if let next = word(index + 1), let span = TimeWords.range(first, next) {
                return (span, 2)
            }
            return nil
        }
        guard case let (_, startWords)? = clock(at: index), let separator = word(index + startWords) else { return nil }
        let isTo = separator == "to"
        guard TimeWords.isDash(separator) || isTo, let endText = word(index + startWords + 1) else { return nil }
        var endWords = 1
        var end = endText
        if let next = word(index + startWords + 2), next == "am" || next == "pm" {
            end += next
            endWords = 2
        }
        let startText = startWords == 2 ? words[index].lower + words[index + 1].lower : words[index].lower
        guard let span = TimeWords.range(startText, end) else { return nil }
        // "9 to 5" in a note isn't a time; "9:00 to 17:00" is.
        if isTo, !plainTo, span.0.bare, span.1.bare { return nil }
        return (span, startWords + 1 + endWords)
    }

    /// The time piece at `index`, and how many words it takes.
    func timePiece(at index: Int) -> (TimePiece, Int)? {
        guard let text = word(index) else { return nil }
        switch text {
        case _ where TimeWords.startWords.contains(text):
            if case let (span, count)? = range(at: index + 1, plainTo: true) {
                return (TimePiece.range(span.0, span.1), count + 1)
            }
            if word(index + 1) == "now" {
                return (TimePiece.startAgo(0), 2)
            }
            if let next = word(index + 1), let ago = TimeWords.ago(next) {
                return (TimePiece.startAgo(ago), 2)
            }
            if case let (length, count)? = duration(at: index + 1), word(index + 1 + count) == "ago" {
                return (TimePiece.startAgo(length), count + 2)
            }
            if case let (time, count)? = clock(at: index + 1) {
                return (TimePiece.start(time), count + 1)
            }
            return nil
        case _ where TimeWords.endWords.contains(text):
            if word(index + 1) == "now" {
                return (TimePiece.endNow, 2)
            }
            if case let (time, count)? = clock(at: index + 1), text != "to" || !time.bare {
                return (TimePiece.end(time), count + 1)
            }
            return nil
        case "for":
            if case let (length, count)? = duration(at: index + 1) {
                return (TimePiece.duration(length), count + 1)
            }
            return nil
        default:
            if case let (span, count)? = range(at: index) {
                return (TimePiece.range(span.0, span.1), count)
            }
            if let ago = TimeWords.ago(text) {
                return (TimePiece.startAgo(ago), 1)
            }
            if case let (length, count)? = duration(at: index) {
                if word(index + count) == "ago" {
                    return (TimePiece.startAgo(length), count + 1)
                }
                return (TimePiece.duration(length), count)
            }
            if case let (time, count)? = clock(at: index), !time.bare {
                return (TimePiece.start(time), count)
            }
            return nil
        }
    }

    /// A day at `index`, as "yesterday", "wed", "2026-09-30", "30 sep" or
    /// "sep 30", and how many words it takes.
    func day(at index: Int) -> (LocalDate, Int)? {
        guard let text = word(index) else { return nil }
        let today = context.today
        if let date = TimeWords.day(text, today: today) {
            return (date, 1)
        }
        if let dayOfMonth = TimeWords.dayOfMonth(text), let next = word(index + 1), let month = TimeWords.month(next),
           let date = TimeWords.date(day: dayOfMonth, month: month, today: today) {
            return (date, 2)
        }
        if let month = TimeWords.month(text), let next = word(index + 1), let dayOfMonth = TimeWords.dayOfMonth(next),
           let date = TimeWords.date(day: dayOfMonth, month: month, today: today) {
            return (date, 2)
        }
        return nil
    }

    /// The instant a time of day, in seconds after midnight, stands for on
    /// a day in the context's zone. "24:00" is the next day's midnight.
    func instant(_ second: Int, on day: LocalDate) -> Timestamp {
        if second >= 86400 {
            return Timestamp(date: day.adding(days: 1), secondOfDay: second - 86400, zone: context.timeZone)
        }
        return Timestamp(date: day, secondOfDay: second, zone: context.timeZone)
    }

    /// The instant a time of day typed without a day stands for: today's,
    /// or yesterday's if today's hasn't come yet and yesterday's was in the
    /// last 12 hours, as when typing "from 23:30" just after midnight.
    func recent(_ second: Int, on day: LocalDate?) -> Timestamp {
        if let day {
            return instant(second, on: day)
        }
        let today = context.today
        let candidate = instant(second, on: today)
        guard candidate > context.now else { return candidate }
        let earlier = instant(second, on: today.adding(days: -1))
        return earlier.distance(to: context.now) <= 12 * 3_600_000 ? earlier : candidate
    }

    // MARK: - Projects and clients

    /// The project that best matches `phrase`, and how well: each word has
    /// to start a word of its name or its client's. Among equally good
    /// matches, the one used last wins.
    func project(matching phrase: String, includingArchived: Bool) -> (id: UUID, rank: Int)? {
        guard !ProjectSearch.terms(phrase).isEmpty,
              let best = context.projects(matching: phrase, includingArchived: includingArchived).first
        else { return nil }
        return (best.project.id, best.rank)
    }

    /// The client that best matches `phrase`, and how well.
    func client(matching phrase: String) -> (id: UUID, rank: Int)? {
        let terms = ProjectSearch.terms(phrase)
        guard !terms.isEmpty else { return nil }
        let clients = context.ledger.liveClients()
        var best: (rank: Int, archived: Bool, id: UUID)?
        for candidate in clients {
            guard let rank = ProjectSearch.rank(terms, project: candidate.name, client: ""), rank <= 1 else { continue }
            if let current = best, (current.rank, current.archived ? 1 : 0) <= (rank, candidate.archived ? 1 : 0) { continue }
            best = (rank, candidate.archived, candidate.id)
        }
        return best.map { ($0.id, $0.rank) }
    }

    /// The project or client `phrase` names: one whose name it is, or else
    /// the best match, a client winning only when it matches better.
    func target(matching phrase: String) -> CommandTarget? {
        let folded = ProjectSearch.fold(phrase.trimmingCharacters(in: .whitespaces))
        let projects = context.ledger.projects.values.filter { !$0.isDeleted }.sorted(by: Project.fileOrder)
        let clients = context.ledger.liveClients()
        if let named = projects.first(where: { ProjectSearch.fold($0.name) == folded }) {
            return .project(named.id)
        }
        if let named = clients.first(where: { ProjectSearch.fold($0.name) == folded }) {
            return .client(named.id)
        }
        switch (project(matching: phrase, includingArchived: true), client(matching: phrase)) {
        case let (projectMatch?, clientMatch?):
            return clientMatch.rank < projectMatch.rank ? .client(clientMatch.id) : .project(projectMatch.id)
        case let (projectMatch?, nil):
            return .project(projectMatch.id)
        case let (nil, clientMatch?):
            return .client(clientMatch.id)
        case (nil, nil):
            return nil
        }
    }

    func kind(of target: CommandTarget) -> CommandToken.Kind {
        switch target {
        case let .project(id): .project(id)
        case let .client(id): .client(id)
        }
    }

    /// Whether a client that isn't deleted, other than `except`, has this
    /// name, ignoring case and accents.
    func clientNameTaken(_ name: String, except: UUID? = nil) -> Bool {
        let folded = ProjectSearch.fold(name)
        return context.ledger.clients.values.contains { $0.id != except && !$0.isDeleted && ProjectSearch.fold($0.name) == folded }
    }

    /// Whether a project of `client` that isn't deleted, other than
    /// `except`, has this name, ignoring case and accents.
    func projectNameTaken(_ name: String, client: UUID?, except: UUID? = nil) -> Bool {
        let folded = ProjectSearch.fold(name)
        return context.ledger.projects.values.contains { project in
            project.id != except && !project.isDeleted && project.clientID == client && ProjectSearch.fold(project.name) == folded
        }
    }

    /// The words from `first` up to but not including `end`, as typed.
    func phrase(_ indices: Range<Int>) -> String {
        guard !indices.isEmpty else { return "" }
        return String(text[words[indices.lowerBound].range.lowerBound..<words[indices.upperBound - 1].range.upperBound])
    }

    func span(_ indices: Range<Int>) -> Range<String.Index> {
        words[indices.lowerBound].range.lowerBound..<words[indices.upperBound - 1].range.upperBound
    }

    mutating func token(_ kind: CommandToken.Kind, _ indices: Range<Int>) {
        guard !indices.isEmpty else { return }
        reading.tokens.append(CommandToken(kind: kind, range: span(indices)))
    }

    // MARK: - Entries

    mutating func readEntry() {
        let context = self.context
        var timeWords = Set<Int>()
        var pieces: [(piece: TimePiece, words: Range<Int>)] = []
        var days: [(day: LocalDate, words: Range<Int>)] = []
        var index = 0
        while index < words.count {
            if case let (piece, count)? = timePiece(at: index) {
                pieces.append((piece, index..<index + count))
                timeWords.formUnion(index..<index + count)
                index += count
            } else if case let (date, count)? = day(at: index) {
                days.append((date, index..<index + count))
                index += count
            } else {
                index += 1
            }
        }

        // A day counts only next to a time of day; otherwise "wed" or
        // "today" is part of the note.
        let saysClock = pieces.contains { piece in
            switch piece.piece {
            case .start, .end, .range: true
            default: false
            }
        }
        let chosenDay = saysClock ? days.last?.day : nil
        if saysClock {
            for typedDay in days {
                timeWords.formUnion(typedDay.words)
            }
        }

        // Times.
        var start: Timestamp?
        var end: Timestamp?
        var length: Int64?
        for (piece, _) in pieces {
            switch piece {
            case let .range(first, second):
                let from = recent(first.second, on: chosenDay)
                let fromDay = from.local(in: context.timeZone).date
                let to = TimeWords.rangeEnd(start: first, end: second)
                start = from
                end = instant(to.second, on: to.nextDay ? fromDay.adding(days: 1) : fromDay)
            case let .start(time):
                start = recent(time.second, on: chosenDay)
            case let .startAgo(milliseconds):
                start = context.now.adding(milliseconds: -milliseconds)
            case .end, .endNow, .duration:
                break
            }
        }
        for (piece, _) in pieces {
            switch piece {
            case let .end(time):
                if let start {
                    let startDay = start.local(in: context.timeZone).date
                    var candidate = instant(time.second, on: startDay)
                    if candidate <= start {
                        candidate = instant(time.second, on: startDay.adding(days: 1))
                    }
                    end = candidate
                } else {
                    end = recent(time.second, on: chosenDay)
                }
            case .endNow:
                end = context.now
            case let .duration(milliseconds):
                length = milliseconds
            default:
                break
            }
        }
        if let length {
            switch (start, end) {
            case let (from?, nil):
                end = from.adding(milliseconds: length)
            case let (nil, to?):
                start = to.adding(milliseconds: -length)
            case (nil, nil):
                end = context.now
                start = context.now.adding(milliseconds: -length)
            default:
                break
            }
        }

        // Tags and plain words.
        var tags: [String] = []
        var tagWords: [Int] = []
        var plain: [Int] = []
        for index in words.indices where !timeWords.contains(index) {
            let typed = words[index].text
            if typed.hasPrefix("#") || (typed.contains("#") && GitHub.Reference(tag: Self.trimmed(typed)) != nil) {
                tagWords.append(index)
            } else {
                plain.append(index)
            }
        }

        // The project: the first words that aren't times or tags, if they
        // name one. Up to three words, the most that match.
        var projectID: UUID?
        var projectWords = 0..<0
        if let first = plain.first {
            var run = 1
            while run < 3, plain.count > run, plain[run] == first + run {
                run += 1
            }
            for count in stride(from: run, through: 1, by: -1) {
                let candidate = phrase(first..<first + count)
                if count == 1, Self.notProjects.contains(words[first].lower) || words[first].lower.count < 2 { continue }
                if let match = project(matching: candidate, includingArchived: false) {
                    projectID = match.id
                    projectWords = first..<first + count
                    break
                }
            }
        }

        let known = context.projectTags[projectID] ?? []
        for index in tagWords {
            if let tag = Self.tag(words[index].text, known: known), !tags.contains(where: { Tags.same($0, tag) }) {
                tags.append(tag)
            }
        }
        var note = plain.filter { !projectWords.contains($0) }.map { words[$0].text }.joined(separator: " ")

        // Tags without a note take the note of the last entry with them,
        // as "#227" brings back what issue 227 was about.
        var borrowedNote = false
        if note.isEmpty, !tags.isEmpty {
            let wanted = Set(tags.map { $0.lowercased() })
            if let earlier = context.resolved.last(where: { entry in
                entry.entry.projectID == projectID && !entry.entry.note.isEmpty
                    && wanted.isSubset(of: Set(entry.entry.tags.map { $0.lowercased() }))
            }) {
                note = earlier.entry.note
                borrowedNote = true
            }
        }

        let draft = EntryDraft(projectID: projectID, tags: tags, note: note)
        decide(draft: draft, start: start, end: end)

        // Highlighting.
        for piece in pieces {
            token(.time, piece.words)
        }
        if saysClock {
            for typedDay in days {
                token(.time, typedDay.words)
            }
        }
        if let projectID {
            token(.project(projectID), projectWords)
        }
        for index in tagWords {
            token(.tag, index..<index + 1)
        }
        for index in plain where !projectWords.contains(index) {
            token(.note, index..<index + 1)
        }
        reading.tokens.sort { $0.range.lowerBound < $1.range.lowerBound }

        reading.completion = completion(
            draft: EntryDraft(projectID: projectID, tags: tags, note: borrowedNote ? "" : note),
            projectWords: projectWords,
            timeWords: pieces.map(\.words) + (saysClock ? days.map(\.words) : [])
        )
    }

    /// Works out what Return and Option-Return do for an entry line.
    mutating func decide(draft: EntryDraft, start: Timestamp?, end: Timestamp?) {
        let now = context.now
        let running = context.running
        var problem: CommandProblem?
        if let start, start > now {
            problem = .startsInFuture
        } else if let end, end > now.adding(seconds: 1) {
            problem = .endsInFuture
        } else if let start, let end, end <= start {
            problem = .endsBeforeStart
        }

        switch (start, end) {
        case let (start?, end?):
            reading.primary = problem == nil ? Command.log(draft, start: start, end: end) : nil
            reading.problem = problem
        case let (start?, nil):
            if draft.isEmpty {
                if running != nil {
                    reading.primary = problem == nil ? Command.moveStart(to: start) : nil
                    reading.problem = problem
                    return
                }
            }
            if let running, start < running.start {
                problem = problem ?? .beforeRunningStart(running.start)
            }
            reading.problem = problem
            reading.alternateProblem = problem
            if problem == nil {
                reading.primary = .start(draft, at: start, end: nil)
                reading.alternate = .start(draft, at: start, end: now)
            }
        case (nil, _?):
            reading.problem = .needsStart
        case (nil, nil):
            guard !draft.isEmpty else { return }
            if let running, draft.matches(running.entry) {
                reading.problem = .runningAlready
            } else {
                reading.primary = .start(draft, at: now, end: nil)
            }
            if running == nil, let since = context.lastEndToday {
                reading.alternate = .start(draft, at: since, end: now)
            } else {
                reading.alternateProblem = .needsStart
            }
        }
    }

    /// A tag as typed, spelled as the project has it already where it's the
    /// same but for case. A "#" in front of a word is dropped, as in
    /// "#daily", unless the project has the tag with it; references such as
    /// "#227" and "api#12" keep it.
    static func tag(_ word: String, known: [String]) -> String? {
        let typed = trimmed(word)
        let bare = typed.hasPrefix("#") ? String(typed.dropFirst()) : typed
        guard !bare.isEmpty else { return nil }
        if let spelled = known.first(where: { Tags.same($0, typed) }) {
            return spelled
        }
        if GitHub.Reference(tag: typed) != nil {
            return typed
        }
        return known.first { Tags.same($0, bare) } ?? bare
    }

    /// A word without the punctuation that ends a sentence or a list.
    static func trimmed(_ word: String) -> String {
        var result = Substring(word)
        while let last = result.last, ",.;:!?)".contains(last) {
            result = result.dropLast()
        }
        return String(result)
    }

    /// The line finished with the tags and note of the last entry that has
    /// what's typed: the same project, the tags typed, and a note that
    /// starts with the one typed.
    func completion(draft: EntryDraft, projectWords: Range<Int>, timeWords: [Range<Int>]) -> CommandCompletion? {
        guard !draft.isEmpty else { return nil }
        let typedNote = draft.note.lowercased()
        let typedTags = Set(draft.tags.map { $0.lowercased() })
        for entry in context.resolved.reversed() {
            if draft.projectID != nil, entry.entry.projectID != draft.projectID { continue }
            if draft.projectID == nil, entry.entry.projectID == nil || typedNote.isEmpty { continue }
            let tags = Set(entry.entry.tags.map { $0.lowercased() })
            guard typedTags.isSubset(of: tags), entry.entry.note.lowercased().hasPrefix(typedNote) else { continue }
            guard entry.entry.note.count > draft.note.count || tags.count > typedTags.count else { continue }
            var parts: [String] = []
            if !projectWords.isEmpty {
                parts.append(phrase(projectWords))
            } else if let projectID = entry.entry.projectID, let project = context.ledger.projects[projectID] {
                parts.append(project.name.lowercased())
            }
            parts += entry.entry.tags.map(Tags.typed)
            if !entry.entry.note.isEmpty {
                parts.append(entry.entry.note)
            }
            parts += timeWords.map { phrase($0) }
            return CommandCompletion(text: parts.joined(separator: " "), entryID: entry.id, day: entry.entry.day)
        }
        return nil
    }

    // MARK: - Stopping

    /// Reads "stop", "stop 11:05", "stop at 11:05", "stop -10m" or "stop
    /// 10m ago". Returns false when what follows "stop" isn't a time, so
    /// the line reads as an entry instead.
    mutating func readStop() -> Bool {
        let now = context.now
        var time: Timestamp?
        var used = 1
        if words.count == 1 {
            time = now
        } else {
            var index = 1
            if let text = word(index), text == "at" || text == "until" {
                index += 1
            }
            if word(index) == "now" {
                time = now
                used = index + 1
            } else if let next = word(index), let ago = TimeWords.ago(next) {
                time = now.adding(milliseconds: -ago)
                used = index + 1
            } else if case let (length, count)? = duration(at: index), word(index + count) == "ago" {
                time = now.adding(milliseconds: -length)
                used = index + count + 1
            } else if case let (typed, count)? = clock(at: index) {
                time = recent(typed.second, on: nil)
                used = index + count
            }
        }
        guard let time, used == words.count else { return false }
        token(.keyword, 0..<1)
        token(.time, 1..<used)
        guard let running = context.running else {
            reading.problem = .notRunning
            return true
        }
        if time > now.adding(seconds: 1) {
            reading.problem = .endsInFuture
        } else if time < running.start {
            reading.problem = .beforeRunningStart(running.start)
        } else {
            reading.primary = .stop(at: min(time, now))
        }
        return true
    }

    // MARK: - Clients and projects

    mutating func readNew() {
        token(.keyword, 0..<2)
        let isProject = words[1].lower == "project"
        guard isProject else {
            let name = phrase(2..<words.count)
            token(.name, 2..<words.count)
            if name.isEmpty {
                reading.problem = .needsName
            } else if clientNameTaken(name) {
                reading.problem = .nameTaken(name)
            } else {
                reading.primary = .addClient(name: name)
            }
            return
        }
        let forIndex = (2..<words.count).first { words[$0].lower == "for" || words[$0].lower == "under" } ?? words.count
        let name = phrase(2..<forIndex)
        token(.name, 2..<forIndex)
        var choice: ClientChoice?
        if forIndex < words.count {
            token(.keyword, forIndex..<forIndex + 1)
            let clientPhrase = phrase(forIndex + 1..<words.count)
            if let match = client(matching: clientPhrase) {
                choice = .existing(match.id)
                token(.client(match.id), forIndex + 1..<words.count)
            } else if !clientPhrase.isEmpty {
                choice = .new(clientPhrase)
                token(.name, forIndex + 1..<words.count)
            }
        }
        guard !name.isEmpty else {
            reading.problem = .needsName
            return
        }
        let taken = switch choice {
        case .new?: false
        case let .existing(id)?: projectNameTaken(name, client: id)
        case nil: projectNameTaken(name, client: nil)
        }
        if taken {
            reading.problem = .nameTaken(name)
            return
        }
        let color = Palette.next(in: context.ledger)
        reading.primary = .addProject(name: name, client: choice, color: color, startsTimer: false)
        reading.alternate = .addProject(name: name, client: choice, color: color, startsTimer: true)
    }

    mutating func readArchive(archived: Bool) {
        token(.keyword, 0..<1)
        let name = phrase(1..<words.count)
        guard !name.isEmpty else {
            reading.problem = .needsName
            return
        }
        guard let found = target(matching: name) else {
            token(.unknown, 1..<words.count)
            reading.problem = .notFound(name)
            return
        }
        token(kind(of: found), 1..<words.count)
        reading.primary = .archive(found, archived: archived)
    }

    mutating func readColor() {
        token(.keyword, 0..<1)
        guard words.count >= 2 else {
            reading.problem = .needsName
            return
        }
        let colorWord = words[words.count - 1]
        let color = Palette.color(named: colorWord.text)
        let nameEnd = color == nil && words.count == 2 ? 2 : words.count - 1
        let name = phrase(1..<nameEnd)
        let projectID = name.isEmpty ? nil : project(matching: name, includingArchived: true)?.id
        if let projectID {
            token(.project(projectID), 1..<nameEnd)
        } else {
            token(.unknown, 1..<nameEnd)
        }
        if let color {
            token(.color(color), words.count - 1..<words.count)
        } else if nameEnd < words.count {
            token(.unknown, words.count - 1..<words.count)
        }
        if name.isEmpty {
            reading.problem = .needsName
        } else if projectID == nil {
            reading.problem = .notFound(name)
        } else if color == nil {
            reading.problem = nameEnd == words.count ? .needsColor : .unknownColor(colorWord.text)
        } else if let projectID, let color {
            reading.primary = .setColor(project: projectID, color: color)
        }
    }

    mutating func readMerge() {
        token(.keyword, 0..<1)
        guard let into = (1..<words.count).first(where: { words[$0].lower == "into" }) else {
            let name = phrase(1..<words.count)
            if !name.isEmpty, let found = target(matching: name) {
                token(kind(of: found), 1..<words.count)
            }
            reading.problem = name.isEmpty ? .needsName : .needsTarget
            return
        }
        token(.keyword, into..<into + 1)
        let sourceName = phrase(1..<into)
        let targetName = phrase(into + 1..<words.count)
        var source = sourceName.isEmpty ? nil : target(matching: sourceName)
        var destination = targetName.isEmpty ? nil : target(matching: targetName)
        // A client and a project: try reading both as clients.
        if case .client? = source, case .project? = destination, let match = client(matching: targetName) {
            destination = .client(match.id)
        } else if case .project? = source, case .client? = destination, let match = client(matching: sourceName) {
            source = .client(match.id)
        }
        if !sourceName.isEmpty {
            token(source.map { kind(of: $0) } ?? .unknown, 1..<into)
        }
        if !targetName.isEmpty {
            token(destination.map { kind(of: $0) } ?? .unknown, into + 1..<words.count)
        }
        reading.tokens.sort { $0.range.lowerBound < $1.range.lowerBound }
        guard !sourceName.isEmpty else {
            reading.problem = .needsName
            return
        }
        guard !targetName.isEmpty else {
            reading.problem = .needsTarget
            return
        }
        guard let source else {
            reading.problem = .notFound(sourceName)
            return
        }
        guard let destination else {
            reading.problem = .notFound(targetName)
            return
        }
        switch (source, destination) {
        case (.project, .client), (.client, .project):
            reading.problem = .mixedTargets
        default:
            if source == destination {
                reading.problem = .sameTarget
            } else {
                reading.primary = .merge(source, into: destination)
            }
        }
    }

    mutating func readRename() {
        token(.keyword, 0..<1)
        let to = (1..<words.count).first { words[$0].lower == "to" } ?? words.count
        let name = phrase(1..<to)
        guard !name.isEmpty else {
            reading.problem = .needsName
            return
        }
        guard let found = target(matching: name) else {
            token(.unknown, 1..<to)
            reading.problem = .notFound(name)
            return
        }
        token(kind(of: found), 1..<to)
        if to < words.count {
            token(.keyword, to..<to + 1)
            token(.name, to + 1..<words.count)
        }
        let newName = phrase(min(to + 1, words.count)..<words.count)
        guard !newName.isEmpty else {
            reading.problem = .needsName
            return
        }
        let taken = switch found {
        case let .project(id): projectNameTaken(newName, client: context.ledger.projects[id]?.clientID, except: id)
        case let .client(id): clientNameTaken(newName, except: id)
        }
        if taken {
            reading.problem = .nameTaken(newName)
        } else {
            reading.primary = .rename(found, to: newName)
        }
    }

    mutating func readFind() {
        token(.keyword, 0..<1)
        let query = phrase(1..<words.count)
        token(.note, 1..<words.count)
        if !query.isEmpty {
            reading.primary = .find(query)
        }
    }
}
