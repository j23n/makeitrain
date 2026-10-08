import Foundation

// Carrying out a command line, and showing what it would change first.

extension Ledger {
    /// Carries out a command. A new entry, project or client gets the id
    /// `newID`; a client added with a project gets `newClientID`. Throws
    /// `LedgerError` when a merge's records are gone.
    @discardableResult
    public mutating func perform(
        _ command: Command,
        timeZone: String,
        now: Timestamp,
        newID: UUID = UUID(),
        newClientID: UUID = UUID(),
        newEntryID: UUID = UUID()
    ) throws -> Changes {
        switch command {
        case let .start(draft, start, end):
            var changes = startTimer(
                id: newID,
                projectID: draft.projectID,
                tags: draft.tags,
                note: draft.note,
                timeZone: timeZone,
                at: start,
                now: now
            )
            if let end {
                changes.formUnion(stopTimer(at: end, now: now))
            }
            return changes
        case let .log(draft, start, end):
            return addEntry(TimeEntry(
                id: newID,
                projectID: draft.projectID,
                start: start,
                end: end,
                timeZone: timeZone,
                tags: draft.tags,
                note: draft.note,
                updated: now
            ), now: now)
        case let .stop(time):
            return stopTimer(at: time, now: now)
        case let .moveStart(time):
            guard let running = runningEntry else { return Changes() }
            return updateEntry(running.id, now: now) { $0.start = min(time, now) }
        case let .addProject(name, client, color, startsTimer):
            var changes = Changes()
            var clientID: UUID?
            switch client {
            case let .existing(id)?:
                clientID = id
            case let .new(clientName)?:
                changes.formUnion(addClient(Client(id: newClientID, name: clientName, updated: now), now: now))
                clientID = newClientID
            case nil:
                clientID = nil
            }
            changes.formUnion(addProject(Project(id: newID, clientID: clientID, name: name, color: color, updated: now), now: now))
            if startsTimer {
                changes.formUnion(startTimer(id: newEntryID, projectID: newID, timeZone: timeZone, at: now, now: now))
            }
            return changes
        case let .addClient(name):
            return addClient(Client(id: newID, name: name, updated: now), now: now)
        case let .archive(target, archived):
            switch target {
            case let .project(id):
                return updateProject(id, now: now) { $0.archived = archived }
            case let .client(id):
                return updateClient(id, now: now) { $0.archived = archived }
            }
        case let .setColor(projectID, color):
            return updateProject(projectID, now: now) { $0.color = color }
        case let .merge(source, target):
            switch (source, target) {
            case let (.project(id), .project(targetID)):
                return try mergeProject(id, into: targetID, now: now)
            case let (.client(id), .client(targetID)):
                return try mergeClient(id, into: targetID, now: now)
            default:
                throw LedgerError.notFound
            }
        case let .rename(target, name):
            switch target {
            case let .project(id):
                return updateProject(id, now: now) { $0.name = name }
            case let .client(id):
                return updateClient(id, now: now) { $0.name = name }
            }
        case .find:
            return Changes()
        }
    }
}

/// Records as they were and as they are, for showing what an edit changes
/// and for undoing it.
public struct LedgerDiff: Hashable, Sendable {
    /// A record before and after. `before` is nil for a record that's new.
    public struct Change<Record: Hashable & Sendable>: Hashable, Sendable {
        public var before: Record?
        public var after: Record

        public var isNew: Bool {
            before == nil
        }
    }

    /// Changed and new entries, by start.
    public var entries: [Change<TimeEntry>] = []
    public var projects: [Change<Project>] = []
    public var clients: [Change<Client>] = []

    public var isEmpty: Bool {
        entries.isEmpty && projects.isEmpty && clients.isEmpty
    }
}

extension Ledger {
    /// What differs from `earlier`: every client, project and entry that
    /// changed or is new, as it was and as it is.
    public func diff(from earlier: Ledger) -> LedgerDiff {
        var diff = LedgerDiff()
        for (id, entry) in entries where earlier.entries[id] != entry {
            diff.entries.append(.init(before: earlier.entries[id], after: entry))
        }
        diff.entries.sort { TimeEntry.fileOrder($0.after, $1.after) }
        for (id, project) in projects where earlier.projects[id] != project {
            diff.projects.append(.init(before: earlier.projects[id], after: project))
        }
        diff.projects.sort { $0.after.name < $1.after.name }
        for (id, client) in clients where earlier.clients[id] != client {
            diff.clients.append(.init(before: earlier.clients[id], after: client))
        }
        diff.clients.sort { $0.after.name < $1.after.name }
        return diff
    }
}

/// What a command would change, worked out by carrying it out on a copy.
public struct CommandPreview: Hashable, Sendable {
    public var command: Command
    public var diff: LedgerDiff
    /// Overlaps the command would make between entries it changes or adds
    /// and others, which aren't there now.
    public var newOverlaps: [Overlap]
    /// The ledger as it would be.
    public var after: Ledger

    public init(_ command: Command, in context: CommandContext) {
        self.command = command
        var after = context.ledger
        _ = try? after.perform(command, timeZone: context.timeZone, now: context.now)
        self.after = after
        diff = after.diff(from: context.ledger)
        newOverlaps = Self.introduced(by: diff, before: context.ledger, after: after, now: context.now)
    }

    /// The overlaps in `after` that involve entries `diff` changed or added
    /// and weren't in `before`.
    private static func introduced(by diff: LedgerDiff, before: Ledger, after: Ledger, now: Timestamp) -> [Overlap] {
        let touched = Set(diff.entries.map(\.after.id))
        guard !touched.isEmpty else { return [] }
        let earlier = Set(Overlaps.analyze(before.resolvedEntries(), now: now).map { [$0.earlier, $0.later] })
        return Overlaps.analyze(after.resolvedEntries(), now: now).filter { overlap in
            (touched.contains(overlap.earlier) || touched.contains(overlap.later)) && !earlier.contains([overlap.earlier, overlap.later])
        }
    }
}

extension Ledger {
    /// Entries whose note, tags, project or client contain every word of
    /// `query`, ignoring case and accents, the latest first.
    public func search(_ query: String, in resolved: [ResolvedEntry], limit: Int = 200) -> [ResolvedEntry] {
        let terms = ProjectSearch.terms(query)
        guard !terms.isEmpty else { return [] }
        var titles: [UUID?: String] = [:]
        var result: [ResolvedEntry] = []
        for entry in resolved.reversed() {
            let projectID = entry.entry.projectID
            let title: String
            if let known = titles[projectID] {
                title = known
            } else {
                title = ProjectSearch.fold((client(forProject: projectID)?.name ?? "") + " " + (projectID.flatMap { projects[$0]?.name } ?? ""))
                titles[projectID] = title
            }
            let text = ProjectSearch.fold(entry.entry.note + " " + entry.entry.tags.joined(separator: " ")) + " " + title
            if terms.allSatisfy({ text.contains($0) }) {
                result.append(entry)
                if result.count == limit { break }
            }
        }
        return result
    }
}
