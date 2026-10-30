import Foundation

// What the command line lists while a line is typed: the earlier entries
// that match it, to start one of them again.

extension CommandReading {
    /// Whether the line could name an earlier entry to start again: words
    /// for a project, tags or a note, without times or a command such as
    /// "stop" or "find".
    public var recallsEntries: Bool {
        guard !text.allSatisfy(\.isWhitespace) else { return false }
        return !tokens.contains { token in
            switch token.kind {
            case .keyword, .time: true
            default: false
            }
        }
    }
}

extension Ledger {
    /// Earlier entries that have every word of `query` in their note, tags,
    /// project or client, ignoring case and accents, to start again: the
    /// latest first, each project, tags and note once, leaving out the
    /// running timer's and those of archived projects.
    public func recall(_ query: String, in resolved: [ResolvedEntry], running: ResolvedEntry?, limit: Int = 5) -> [ResolvedEntry] {
        var result: [ResolvedEntry] = []
        var drafts: [EntryDraft] = running.map { [EntryDraft($0.entry)] } ?? []
        for entry in search(query, in: resolved) {
            if let projectID = entry.entry.projectID, isArchived(project: projectID) {
                continue
            }
            if drafts.contains(where: { $0.matches(entry.entry) }) {
                continue
            }
            drafts.append(EntryDraft(entry.entry))
            result.append(entry)
            if result.count == limit { break }
        }
        return result
    }

    /// An entry's project, tags and note written as a line, such as
    /// "Website redesign #12 Fix login". It doesn't always read back as
    /// them: `CommandContext.startLine(for:)` checks that it does.
    func writtenLine(for entry: TimeEntry) -> String {
        var parts: [String] = []
        if let projectID = entry.projectID, let project = projects[projectID] {
            parts.append(project.name)
        }
        parts += entry.tags.map(Tags.typed)
        if !entry.note.isEmpty {
            parts.append(entry.note)
        }
        return parts.joined(separator: " ")
    }
}

extension CommandContext {
    /// What starts an entry's project, tags and note again when typed, such
    /// as "Website redesign #12 Fix login", or nil when no line reads back
    /// as them: an unassigned note that starts with a project's name would
    /// read as that project, and tags without a note take another entry's.
    public func startLine(for entry: TimeEntry) -> String? {
        let line = ledger.writtenLine(for: entry)
        guard CommandReading(line, in: self).draft?.matches(entry) == true else { return nil }
        return line
    }
}

/// A line to try in an empty command line, and what it does.
public struct CommandExample: Hashable, Sendable {
    public var line: String
    /// What it does, such as "log finished time".
    public var meaning: String
    /// The line, read, for coloring its words.
    public var reading: CommandReading
}

extension CommandContext {
    /// Lines to try, made from the last finished entry with a project, so
    /// they name a project that's there: starting it again, stopping the
    /// timer while one runs, starting earlier, logging finished time, on
    /// another day, finding entries and adding a project. With no projects
    /// yet, adding one.
    public var examples: [CommandExample] {
        var lines: [(String, String)] = []
        let latest = resolved.last { entry in
            guard !entry.isRunning, let projectID = entry.entry.projectID else { return false }
            return !ledger.isArchived(project: projectID)
        }
        if let latest, let projectID = latest.entry.projectID, let project = ledger.projects[projectID] {
            let words = ProjectSearch.words(ProjectSearch.fold(project.name))
            let name = words.first { !CommandReader.notProjects.contains($0) } ?? project.name.lowercased()
            lines.append((startLine(for: latest.entry) ?? name, running == nil ? "start again" : "switch"))
            if running != nil {
                lines.append(("stop -10m", "stop, 10 minutes ago"))
            }
            lines.append(("\(name) -15m", running == nil ? "start, 15 minutes ago" : "switch, 15 minutes ago"))
            lines.append(("\(name) 9-10:30", "log finished time"))
            lines.append(("\(name) for 45m", "log 45 minutes ending now"))
            lines.append(("\(name) yesterday 14-16", "on another day"))
            let found = ProjectSearch.words(ProjectSearch.fold(latest.entry.note)).first { $0.count > 2 } ?? name
            lines.append(("find \(found)", "find entries"))
        } else if running != nil {
            lines.append(("stop", "stop the timer"))
        }
        lines.append(("new project Website", "add a project"))
        return lines.map { line, meaning in
            CommandExample(line: line, meaning: meaning, reading: CommandReading(line, in: self))
        }
    }
}
