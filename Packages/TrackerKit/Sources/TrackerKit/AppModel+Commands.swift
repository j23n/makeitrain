import Foundation
import TrackerCore

/// What running a line did.
public enum CommandOutcome: Equatable {
    /// It changed something, or, for "find", asked for a list.
    case done(Command)
    /// It can't be done, for this reason.
    case problem(CommandProblem)
    /// The line says nothing to do.
    case nothing
}

// The command line: reading a line as it's typed, previewing it, and
// running it.

extension AppModel {
    /// What reading a line needs, as of the clock's time now rather than
    /// the model's last tick, so "now" means this moment.
    public var commandContext: CommandContext {
        CommandContext(ledger: ledger, resolved: resolved, projectTags: projectTags, now: environment.now(), timeZone: environment.timeZone())
    }

    /// What a line means as of now.
    public func read(_ line: String) -> CommandReading {
        CommandReading(line, in: commandContext)
    }

    /// What a command would change, worked out on a copy.
    public func preview(_ command: Command) -> CommandPreview {
        CommandPreview(command, in: commandContext)
    }

    /// Runs a line: what Return does, or Option-Return with `alternate`. The
    /// line is read again first, so times like "now" are up to date, and
    /// remembered for Up to bring back.
    @discardableResult
    public func run(_ line: String, alternate: Bool = false, undoManager: UndoManager?) -> CommandOutcome {
        let reading = read(line)
        guard let command = alternate ? reading.alternate : reading.primary else {
            if let problem = alternate ? reading.alternateProblem ?? reading.problem : reading.problem {
                return .problem(problem)
            }
            return .nothing
        }
        preferences.remember(line)
        if case .find = command {
            return .done(command)
        }
        let zone = environment.timeZone()
        let running = self.running
        do {
            try edit(CommandText.actionName(command, running: running), undoManager: undoManager) { ledger, now in
                try ledger.perform(command, timeZone: zone, now: now)
            }
        } catch {
            return .problem(.notFound(""))
        }
        return .done(command)
    }

    /// The entries `find` lists for a query, the latest first.
    public func find(_ query: String) -> [ResolvedEntry] {
        ledger.search(query, in: resolved)
    }

    // MARK: - Entries as lines

    /// An entry written as a line the command line reads back, such as
    /// "2 oct 13:30-16:30 Bookings #153 Bug fix", for editing it as text.
    public func line(for entry: ResolvedEntry) -> String {
        let zone = entry.entry.timeZone
        let start = entry.start.local(in: zone)
        let day = start.date
        let dayText: String
        if today.daysSince1970 - day.daysSince1970 < 300 {
            dayText = "\(day.day) \(Self.monthNames[day.month - 1])"
        } else {
            dayText = day.description
        }
        let clock = { (time: LocalDateTime) in "\(time.hour):\(time.minute < 10 ? "0" : "")\(time.minute)" }
        var parts = [dayText]
        if let end = entry.end {
            parts.append("\(clock(start))-\(clock(end.local(in: zone)))")
        } else {
            parts.append("from \(clock(start))")
        }
        if let projectID = entry.entry.projectID, let project = ledger.projects[projectID] {
            parts.append(project.name)
        }
        parts += entry.entry.tags.map { tag in
            tag.hasPrefix("#") || tag.contains("#") ? tag : "#" + tag.replacingOccurrences(of: " ", with: "-")
        }
        if !entry.entry.note.isEmpty {
            parts.append(entry.entry.note)
        }
        return parts.joined(separator: " ")
    }

    /// What a line typed over an entry would make of it: its project, tags,
    /// note and times, or nil when the line doesn't describe an entry.
    public func entryChange(_ line: String, for id: UUID) -> (draft: EntryDraft, start: Timestamp, end: Timestamp?)? {
        guard let current = resolved.first(where: { $0.id == id }) else { return nil }
        // Read as if the entry weren't there, so it isn't the running timer
        // its own start has to come after.
        var context = commandContext
        context.resolved = resolved.filter { $0.id != id }
        switch CommandReading(line, in: context).primary {
        case let .log(draft, start, end)?:
            return (draft, start, end)
        case let .start(draft, start, _)?:
            return (draft, start, current.isRunning ? nil : current.end)
        default:
            return nil
        }
    }

    /// Changes an entry to what a line typed over it says. Returns false
    /// when the line doesn't describe an entry.
    @discardableResult
    public func apply(line: String, to id: UUID, undoManager: UndoManager?) -> Bool {
        guard let change = entryChange(line, for: id) else { return false }
        edit("Edit Entry", undoManager: undoManager) { ledger, now in
            ledger.updateEntry(id, now: now) { entry in
                entry.projectID = change.draft.projectID
                entry.tags = change.draft.tags
                entry.note = change.draft.note
                entry.start = change.start
                if let end = change.end {
                    entry.end = end
                }
            }
        }
        return true
    }

    static let monthNames = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
}

/// The words for commands and their problems.
public enum CommandText {
    /// The name of a command in the Undo menu.
    public static func actionName(_ command: Command, running: ResolvedEntry?) -> String {
        switch command {
        case let .start(_, _, end):
            if end != nil { return "Log Entry" }
            return running == nil ? "Start Timer" : "Switch Timer"
        case .log: return "Log Entry"
        case .stop: return "Stop Timer"
        case .moveStart: return "Change Start"
        case .addProject: return "Add Project"
        case .addClient: return "Add Client"
        case let .archive(target, archived):
            switch target {
            case .project: return archived ? "Archive Project" : "Unarchive Project"
            case .client: return archived ? "Archive Client" : "Unarchive Client"
            }
        case .setColor: return "Change Color"
        case let .merge(target, _):
            if case .client = target { return "Merge Clients" }
            return "Merge Projects"
        case let .rename(target, _):
            if case .client = target { return "Rename Client" }
            return "Rename Project"
        case .find: return "Find"
        }
    }

    /// What a command does, as the line under the command line says it,
    /// such as "Start", "Switch to" or "Switch at 11:05".
    public static func title(_ command: Command, running: ResolvedEntry?, now: Timestamp, zone: String) -> String {
        switch command {
        case let .start(_, start, end):
            if end != nil { return "Log it as done, from \(Format.time(start, zone: zone))" }
            let atNow = abs(start.distance(to: now)) < 60000
            if running == nil {
                return atNow ? "Start" : "Start from \(Format.time(start, zone: zone))"
            }
            return atNow ? "Switch to" : "Switch at \(Format.time(start, zone: zone))"
        case .log:
            return "Log"
        case let .stop(time):
            return abs(time.distance(to: now)) < 60000 ? "Stop" : "Stop at \(Format.time(time, zone: zone))"
        case let .moveStart(time):
            return "Started at \(Format.time(time, zone: zone))"
        case .addProject:
            return "Add project"
        case .addClient:
            return "Add client"
        case let .archive(_, archived):
            return archived ? "Archive" : "Unarchive"
        case .setColor:
            return "Color"
        case .merge:
            return "Merge"
        case .rename:
            return "Rename"
        case .find:
            return "Find"
        }
    }

    /// Why a line can't be run, as a sentence.
    public static func message(_ problem: CommandProblem, zone: String) -> String {
        switch problem {
        case .notRunning:
            "No timer is running."
        case let .beforeRunningStart(time):
            "That's before the running timer started, at \(Format.time(time, zone: zone))."
        case .startsInFuture:
            "That's later than now."
        case .endsInFuture:
            "That ends later than now."
        case .endsBeforeStart:
            "That ends before it starts."
        case .runningAlready:
            "That's running already."
        case .needsStart:
            "Say when it started, as in from 10:10 or -30m."
        case .needsName:
            "Type a name."
        case .needsColor:
            "Type a color, such as teal."
        case let .unknownColor(name):
            "There's no color called \(name). Try blue, red, green, purple, orange, teal, gold or gray."
        case .needsTarget:
            "Type into and what to merge it into."
        case let .notFound(name):
            name.isEmpty ? "That's gone." : "No client or project is called \(name)."
        case let .nameTaken(name):
            "There's one called \(name) already."
        case .sameTarget:
            "That's the same one."
        case .mixedTargets:
            "Merge a project into a project, or a client into a client."
        }
    }
}
