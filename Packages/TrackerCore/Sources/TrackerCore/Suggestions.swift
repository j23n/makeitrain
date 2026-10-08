import Foundation

/// Something that could take the place of the word being typed in a line,
/// with the line it makes: a project, a client, a tag, a time, a color or
/// a command's first words.
public struct LineSuggestion: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case project(UUID)
        case client(UUID)
        case tag
        case time
        /// A palette color, as hex.
        case color(String)
        case keyword
    }

    public var kind: Kind
    /// What a list shows, such as "Website" or "#design".
    public var title: String
    /// More about it, such as the client's name, or "end of Review".
    public var detail: String
    /// The whole line with the suggestion in place of the word.
    public var text: String
    /// Where the insertion point goes after it, in UTF-16 units.
    public var cursor: Int
}

/// What could be typed next in a line, for the word at the insertion
/// point: the projects whose names start with it where the line's project
/// goes, the project's tags after "#", the day's other entries' starts and
/// ends where a time goes, and a command's first words and what it acts on.
public enum LineSuggestions {
    /// The words that start a command, and what each does.
    static let keywords: [(words: String, detail: String)] = [
        ("stop", "Stop the timer"),
        ("new project", "Add a project"),
        ("new client", "Add a client"),
        ("archive", "Archive a project or client"),
        ("unarchive", "Bring one back"),
        ("rename", "Rename a project or client"),
        ("merge", "Merge one into another"),
        ("color", "Change a project's color"),
        ("find", "List entries with these words"),
    ]

    /// Words a time of day follows.
    static let timeWords: Set<String> = ["from", "since", "at", "starting", "until", "till", "til", "to"]

    /// The most suggestions offered at once.
    static let limit = 6

    /// Suggestions for the word at `cursor`, a UTF-16 offset into `text`,
    /// at most `limit`. `entryID` is the entry the line edits, if it edits
    /// one: commands aren't offered then, and the times come from the
    /// other entries of its day rather than today's.
    public static func suggestions(
        for text: String,
        cursor: Int,
        in context: CommandContext,
        editing entryID: UUID? = nil
    ) -> [LineSuggestion] {
        let word = Word(text, cursor: cursor)
        let typed = word.typed
        let lowered = typed.lowercased()
        let before = word.before
        var readingContext = context
        if let entryID {
            readingContext.resolved = context.resolved.filter { $0.id != entryID }
        }
        let reading = CommandReading(text, in: readingContext)
        var found: [LineSuggestion] = []

        // A command's first words, and what it acts on.
        if entryID == nil {
            if before.isEmpty, !typed.isEmpty, !typed.hasPrefix("#") {
                for keyword in keywords where keyword.words.hasPrefix(lowered) && keyword.words != lowered {
                    found.append(word.suggestion(.keyword, keyword.words, keyword.detail, insert: keyword.words + " "))
                }
            }
            if let command = before.first {
                switch command {
                case "archive", "unarchive", "merge":
                    found += targets(typed, word: word, in: context, clients: true)
                    return Array(found.prefix(limit))
                case "rename":
                    if !before.contains("to") {
                        found += targets(typed, word: word, in: context, clients: true)
                    }
                    return Array(found.prefix(limit))
                case "color", "colour":
                    if before.count == 1 {
                        found += targets(typed, word: word, in: context, clients: false)
                    } else {
                        for hex in Palette.colors {
                            let name = Palette.name(of: hex).lowercased()
                            if name.hasPrefix(lowered), name != lowered {
                                found.append(word.suggestion(.color(hex), name, "", insert: name))
                            }
                        }
                    }
                    return Array(found.prefix(limit))
                case "new":
                    if before.count >= 2, before[1] == "project", before.last == "for" {
                        found += clients(typed, word: word, in: context)
                    }
                    return Array(found.prefix(limit))
                case "find", "search":
                    return []
                case "stop":
                    if before.count == 1 {
                        found += times(typed, after: true, word: word, day: context.today, in: context, editing: nil)
                    }
                    return Array(found.prefix(limit))
                default:
                    break
                }
            }
        }

        // Tags, from the line's project or, without one, from every project.
        if typed.hasPrefix("#") {
            found += tags(typed, word: word, reading: reading, in: context)
            return Array(found.prefix(limit))
        }

        // Times of day, where one goes.
        let day = entryID.flatMap { id in context.resolved.first { $0.id == id } }?.start.local(in: context.timeZone).date ?? context.today
        let afterTimeWord = before.last.map(timeWords.contains) ?? false
        let clocks = times(typed, after: afterTimeWord, word: word, day: day, in: context, editing: entryID)
        if !clocks.isEmpty || typed.isEmpty {
            return Array((found + clocks).prefix(limit))
        }

        // Projects, where the line's project goes: before any note words
        // and any other project.
        let earlier = reading.tokens.filter { $0.range.upperBound <= word.start }
        let atProject = !earlier.contains { token in
            switch token.kind {
            case .project, .note: true
            default: false
            }
        }
        if atProject {
            found += projects(typed, word: word, in: context)
        }
        return Array(found.prefix(limit))
    }

    // MARK: - Kinds

    /// Live projects whose name, or whose client's, has a word starting
    /// with what's typed: the best matches first, then the ones used last.
    static func projects(_ typed: String, word: Word, in context: CommandContext) -> [LineSuggestion] {
        guard !ProjectSearch.terms(typed).isEmpty else { return [] }
        return context.projects(matching: typed, includingArchived: false)
            .filter { $0.project.name.lowercased() != typed.lowercased() }
            .map { match in
                word.suggestion(.project(match.project.id), match.project.name, match.client, insert: match.project.name)
            }
    }

    /// Live clients whose name has a word starting with what's typed.
    static func clients(_ typed: String, word: Word, in context: CommandContext) -> [LineSuggestion] {
        let terms = ProjectSearch.terms(typed)
        return context.ledger.liveClients()
            .filter { !$0.archived }
            .filter { client in
                terms.isEmpty || (ProjectSearch.rank(terms, project: client.name, client: "") ?? 2) <= 1
            }
            .filter { $0.name.lowercased() != typed.lowercased() }
            .map { client in word.suggestion(.client(client.id), client.name, "Client", insert: client.name) }
    }

    /// What a command acts on: projects, and clients when it can act on one.
    static func targets(_ typed: String, word: Word, in context: CommandContext, clients withClients: Bool) -> [LineSuggestion] {
        var found = typed.isEmpty ? recentProjects(word: word, in: context) : projects(typed, word: word, in: context)
        if withClients, !typed.isEmpty {
            found += clients(typed, word: word, in: context)
        }
        return found
    }

    /// The projects used last, for a command's target before anything's
    /// typed.
    static func recentProjects(word: Word, in context: CommandContext) -> [LineSuggestion] {
        context.projects(matching: "", includingArchived: false).map { match in
            word.suggestion(.project(match.project.id), match.project.name, match.client, insert: match.project.name)
        }
    }

    /// The tags of the line's project, or without one every tag, that
    /// start with what's typed after "#", leaving out the ones the line has.
    static func tags(_ typed: String, word: Word, reading: CommandReading, in context: CommandContext) -> [LineSuggestion] {
        let query = typed.dropFirst().lowercased()
        let projectID = reading.draft?.projectID
        let candidates = projectID.map { context.projectTags[$0] ?? [] } ?? context.ledger.allTags()
        let present = Set((reading.draft?.tags ?? []).map { $0.lowercased() })
        var found: [LineSuggestion] = []
        for tag in candidates {
            let shown = Tags.typed(tag)
            let bare = tag.hasPrefix("#") ? String(tag.dropFirst()) : tag
            guard bare.lowercased().hasPrefix(query) else { continue }
            guard shown.lowercased() != typed.lowercased(), !present.contains(tag.lowercased()) else { continue }
            found.append(word.suggestion(.tag, shown, "", insert: shown))
        }
        return found
    }

    /// Times of day for a word that's a time or starts one: the starts and
    /// ends of the day's other entries, and now. "13:30-1" offers the ends
    /// after 13:30. A bare number is taken for the start of a time only
    /// where one goes, as after "from", or when it's typed with digits.
    static func times(_ typed: String, after timeWord: Bool, word: Word, day: LocalDate, in context: CommandContext, editing entryID: UUID?) -> [LineSuggestion] {
        var head = ""
        var partial = typed
        var after: Int?
        if let dash = typed.firstIndex(of: "-"), dash != typed.startIndex {
            let start = String(typed[..<dash])
            guard let clock = TimeWords.clock(start) else { return [] }
            head = start + "-"
            partial = String(typed[typed.index(after: dash)...])
            after = clock.second
        }
        guard partial.allSatisfy({ $0.isASCIIDigit || $0 == ":" }), partial.filter({ $0 == ":" }).count <= 1 else { return [] }
        guard timeWord || after != nil || !partial.isEmpty else { return [] }
        if partial.count >= 2, partial.hasPrefix("0") {
            partial.removeFirst()
        }

        var candidates: [(second: Int, detail: String)] = []
        for entry in context.resolved where entry.id != entryID {
            let start = entry.start.local(in: context.timeZone)
            guard start.date == day else { continue }
            let title = entry.entry.note.isEmpty ? context.ledger.projectTitle(entry.entry.projectID) : entry.entry.note
            candidates.append((start.millisecondOfDay / 1000, "start of \(title)"))
            if let end = entry.end {
                let local = end.local(in: context.timeZone)
                if local.date == day {
                    candidates.append((local.millisecondOfDay / 1000, "end of \(title)"))
                }
            }
        }
        if day == context.today, after == nil {
            let now = context.now.local(in: context.timeZone).millisecondOfDay / 1000
            candidates.append((now / 300 * 300, "now"))
        }
        candidates.sort { $0.second < $1.second }

        var seen: Set<String> = []
        var found: [LineSuggestion] = []
        for candidate in candidates {
            if let after, candidate.second <= after { continue }
            let clock = "\(candidate.second / 3600):\(candidate.second / 60 % 60 < 10 ? "0" : "")\(candidate.second / 60 % 60)"
            guard clock.hasPrefix(partial), clock != partial, seen.insert(clock).inserted else { continue }
            found.append(word.suggestion(.time, head + clock, candidate.detail, insert: head + clock))
        }
        return found
    }

    // MARK: - The word being typed

    /// The word around the insertion point, and the words before it.
    struct Word {
        let text: String
        /// Where the word starts and ends.
        let start: String.Index
        let end: String.Index
        /// What's typed of it, up to the insertion point.
        let typed: String
        /// The words before it, lowercased.
        let before: [String]

        init(_ text: String, cursor: Int) {
            self.text = text
            // The insertion point, on a character's boundary.
            var index = text.startIndex
            var offset = 0
            while index < text.endIndex {
                let next = text.index(after: index)
                let width = text.utf16.distance(from: index, to: next)
                if offset + width > cursor { break }
                offset += width
                index = next
            }
            var start = index
            while start > text.startIndex, !text[text.index(before: start)].isWhitespace {
                start = text.index(before: start)
            }
            var end = index
            while end < text.endIndex, !text[end].isWhitespace {
                end = text.index(after: end)
            }
            self.start = start
            self.end = end
            typed = String(text[start..<index])
            before = text[..<start].split(whereSeparator: \.isWhitespace).map { $0.lowercased() }
        }

        /// The line with `insert` in place of the word, followed by a
        /// space, and the insertion point after that space.
        func suggestion(_ kind: LineSuggestion.Kind, _ title: String, _ detail: String, insert: String) -> LineSuggestion {
            let head = String(text[..<start]) + insert
            var rest = String(text[end...])
            if insert.hasSuffix(" ") {
                if rest.first?.isWhitespace == true {
                    rest.removeFirst()
                }
            } else if rest.first?.isWhitespace != true {
                rest = " " + rest
            }
            let cursor = head.utf16.count + (insert.hasSuffix(" ") ? 0 : 1)
            return LineSuggestion(kind: kind, title: title, detail: detail, text: head + rest, cursor: cursor)
        }
    }
}
