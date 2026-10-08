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
    /// "2 oct 13:30-16:30 Website #12 Fix login", for editing it as text.
    public func line(for entry: ResolvedEntry) -> String {
        ledger.line(for: entry, today: today)
    }

    /// A line typed over an entry, read as if the entry weren't there, so
    /// it isn't the running timer its own start has to come after: the
    /// reading, what it makes of the entry part by part, or else why it
    /// can't change it. A line without times keeps the entry's.
    func readEntryLine(_ line: String, for id: UUID) -> (reading: CommandReading, parts: EntryLineParts?, problem: String?) {
        let current = resolved.first { $0.id == id }
        var context = commandContext
        context.resolved = resolved.filter { $0.id != id }
        let reading = CommandReading(line, in: context)
        let zone = context.timeZone
        if let current {
            switch reading.primary {
            case let .log(draft, start, end)?:
                return (reading, EntryLineParts(start: start, end: end, zone: zone, draft: draft), nil)
            case let .start(draft, start, _)?:
                guard reading.tokens.contains(where: { $0.kind == .time }) else {
                    return (reading, EntryLineParts(start: current.start, end: current.end, zone: zone, draft: draft), nil)
                }
                if current.end.map({ $0 > start }) ?? true {
                    return (reading, EntryLineParts(start: start, end: current.end, zone: zone, draft: draft), nil)
                }
            default:
                break
            }
        }
        if let problem = reading.problem {
            return (reading, nil, CommandText.message(problem, zone: zone))
        }
        if case .start? = reading.primary {
            // A start after the end the entry keeps.
            return (reading, nil, CommandText.message(.endsBeforeStart, zone: zone))
        }
        return (reading, nil, "Can't read this as an entry. Start with its times, then its project, tags and note.")
    }

    /// What could replace the word at `cursor`, a UTF-16 offset, in a line
    /// typed in the command line or, with `entryID`, over that entry.
    public func suggestions(for line: String, cursor: Int, editing entryID: UUID? = nil) -> [LineSuggestion] {
        LineSuggestions.suggestions(for: line, cursor: cursor, in: commandContext, editing: entryID)
    }

    /// Changes an entry to what a line typed over it says. Returns false
    /// when the line doesn't describe an entry.
    @discardableResult
    public func apply(line: String, to id: UUID, undoManager: UndoManager?) -> Bool {
        guard let change = readEntryLine(line, for: id).parts else { return false }
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
            if end != nil { return "Log as finished, from \(Format.time(start, zone: zone))" }
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
            return "Change start to \(Format.time(time, zone: zone))"
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

    /// What a command's button says, in a word or two, such as "Switch"
    /// or "Log", for the iPhone's command line.
    public static func verb(_ command: Command, running: ResolvedEntry?) -> String {
        switch command {
        case let .start(_, _, end):
            if end != nil { return "Log" }
            return running == nil ? "Start" : "Switch"
        case .log:
            return "Log"
        case .stop:
            return "Stop"
        case .moveStart:
            return "Change start"
        case .addProject, .addClient:
            return "Add"
        case let .archive(_, archived):
            return archived ? "Archive" : "Unarchive"
        case .setColor:
            return "Change color"
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
            "That's before the timer started (\(Format.time(time, zone: zone)))."
        case .startsInFuture:
            "That's in the future."
        case .endsInFuture:
            "That ends in the future."
        case .endsBeforeStart:
            "That ends before it starts."
        case .runningAlready:
            "That's already running."
        case .needsStart:
            "Add a start, such as from 10:10 or -30m."
        case .needsName:
            "Type a name."
        case .needsColor:
            "Type a color, such as teal."
        case let .unknownColor(name):
            "No color named \(name). Use blue, red, green, purple, orange, teal, gold or gray."
        case .needsTarget:
            "Type “into” and what to merge it into."
        case let .notFound(name):
            name.isEmpty ? "That was deleted." : "No client or project named \(name)."
        case let .nameTaken(name):
            "\(name) already exists."
        case .sameTarget:
            "Those are the same."
        case .mixedTargets:
            "Merge a project into a project, or a client into a client."
        }
    }
}

/// What a line typed over an entry reads as, for the guide under it.
public struct EntryLineParts: Equatable {
    public var start: Timestamp
    /// Nil while it runs.
    public var end: Timestamp?
    /// The zone its times are shown in.
    public var zone: String
    public var draft: EntryDraft
}
