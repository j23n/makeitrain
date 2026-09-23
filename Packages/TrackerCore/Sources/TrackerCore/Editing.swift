import Foundation

/// What an edit touched, so the app knows which files to save.
public struct Changes: Hashable, Sendable {
    /// Month files with changed entries.
    public var months: Set<MonthKey>
    /// Whether `projects.json` changed.
    public var projects: Bool

    public init(months: Set<MonthKey> = [], projects: Bool = false) {
        self.months = months
        self.projects = projects
    }

    public var isEmpty: Bool {
        months.isEmpty && !projects
    }

    public mutating func formUnion(_ other: Changes) {
        months.formUnion(other.months)
        projects = projects || other.projects
    }

    public func union(_ other: Changes) -> Changes {
        var result = self
        result.formUnion(other)
        return result
    }
}

public enum LedgerError: Error, Hashable, Sendable {
    /// The client or project still has entries. Archive or merge it instead.
    case hasEntries
    /// There's no such record, or it's deleted.
    case notFound
}

/// Tag names as people type them.
public enum Tags {
    /// Cleans up tags: runs of spaces become one space, `;` is removed
    /// because it separates tags in the CSV, and empty tags and repeats that
    /// differ only in case are dropped.
    public static func normalize(_ tags: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for tag in tags {
            let cleaned = tag.filter { $0 != ";" }.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            guard !cleaned.isEmpty, seen.insert(cleaned.lowercased()).inserted else { continue }
            result.append(cleaned)
        }
        return result
    }

    /// Whether two tags are the same, ignoring case.
    public static func same(_ a: String, _ b: String) -> Bool {
        a.lowercased() == b.lowercased()
    }
}

// Every edit stamps what it changed, using `Timestamp.stamp(after:now:)`, and
// first gives timers overtaken by a later one a real end, so the files catch
// up with what the app shows.

// MARK: - Timers

extension Ledger {
    /// Starts a timer at `time`, stopping the running one at the same instant.
    @discardableResult
    public mutating func startTimer(
        id: UUID = UUID(),
        projectID: UUID? = nil,
        tags: [String] = [],
        note: String = "",
        timeZone: String,
        at time: Timestamp,
        now: Timestamp
    ) -> Changes {
        let start = time.wholeSeconds
        var changes = stopTimer(at: start, now: now)
        let entry = TimeEntry(
            id: id,
            projectID: projectID,
            start: start,
            timeZone: timeZone,
            tags: Tags.normalize(tags),
            note: note,
            updated: now
        )
        entries[id] = entry
        changes.months.insert(entry.month)
        return changes
    }

    /// Stops the running timer at `time`, or at its start if `time` is
    /// earlier. "Stop at…" passes a time before now.
    @discardableResult
    public mutating func stopTimer(at time: Timestamp, now: Timestamp) -> Changes {
        var changes = settleOvertakenTimers(now: now)
        guard let running = runningEntry else { return changes }
        changes.formUnion(edit(running.id, now: now) { entry in
            entry.end = max(time.wholeSeconds, entry.start)
        })
        return changes
    }

    /// Gives each timer overtaken by a later one (see `resolvedEntries()`) a
    /// real end: the moment the later one started.
    @discardableResult
    mutating func settleOvertakenTimers(now: Timestamp) -> Changes {
        var changes = Changes()
        for resolved in resolvedEntries() where resolved.endedByLaterTimer {
            changes.formUnion(edit(resolved.id, now: now) { entry in
                entry.end = resolved.end
            })
        }
        return changes
    }
}

// MARK: - Entries

extension Ledger {
    /// Adds an entry made by hand, such as one drawn on the timeline.
    @discardableResult
    public mutating func addEntry(_ entry: TimeEntry, now: Timestamp) -> Changes {
        var changes = settleOvertakenTimers(now: now)
        var new = entry
        new.start = new.start.wholeSeconds
        new.end = new.end?.wholeSeconds
        new.endUpdated = new.end == nil ? nil : now
        new.tags = Tags.normalize(new.tags)
        new.updated = now
        entries[new.id] = new
        changes.months.insert(new.month)
        return changes
    }

    /// Changes an entry and stamps what changed.
    ///
    /// Times are cut to whole seconds and tags cleaned up. A stopped entry
    /// never runs again: an edit can move its end but not remove it.
    @discardableResult
    public mutating func updateEntry(_ id: UUID, now: Timestamp, _ change: (inout TimeEntry) -> Void) -> Changes {
        var changes = settleOvertakenTimers(now: now)
        changes.formUnion(edit(id, now: now, change))
        return changes
    }

    /// Deletes an entry. Its record stays, without its note and tags, so an
    /// older copy can't bring it back. Undo by restoring the old copy with
    /// `updateEntry`.
    @discardableResult
    public mutating func deleteEntry(_ id: UUID, now: Timestamp) -> Changes {
        var changes = settleOvertakenTimers(now: now)
        guard entries[id]?.isDeleted == false else { return changes }
        changes.formUnion(edit(id, now: now) { entry in
            entry.deleted = now
            entry.note = ""
            entry.tags = []
        })
        return changes
    }

    /// Applies an overlap fix. Splitting gives the part after the inner entry
    /// the id `newID`.
    @discardableResult
    public mutating func apply(_ fix: OverlapFix, now: Timestamp, newID: UUID = UUID()) -> Changes {
        var changes = settleOvertakenTimers(now: now)
        switch fix {
        case let .trimEarlier(id, end):
            changes.formUnion(edit(id, now: now) { $0.end = end })
        case let .split(outerID, innerID):
            guard let outer = entries[outerID], let inner = entries[innerID], let innerEnd = inner.end,
                  outer.start < inner.start, outer.end.map({ $0 > innerEnd }) ?? true
            else { break }
            let after = TimeEntry(
                id: newID,
                projectID: outer.projectID,
                start: innerEnd,
                end: outer.end,
                timeZone: outer.timeZone,
                tags: outer.tags,
                note: outer.note,
                updated: now
            )
            changes.formUnion(edit(outerID, now: now) { $0.end = inner.start })
            entries[newID] = after
            changes.months.insert(after.month)
        }
        return changes
    }

    /// Renames a tag, ignoring case, on every entry that has it. Renaming a
    /// tag to another tag's name merges the two.
    @discardableResult
    public mutating func renameTag(_ tag: String, to newName: String, now: Timestamp) -> Changes {
        var changes = settleOvertakenTimers(now: now)
        for entry in entries.values where !entry.isDeleted && entry.tags.contains(where: { Tags.same($0, tag) }) {
            changes.formUnion(edit(entry.id, now: now) { entry in
                entry.tags = entry.tags.map { Tags.same($0, tag) ? newName : $0 }
            })
        }
        return changes
    }

    /// Applies a change to an entry and stamps what changed. Unlike the
    /// public methods, it doesn't settle overtaken timers first.
    private mutating func edit(_ id: UUID, now: Timestamp, _ change: (inout TimeEntry) -> Void) -> Changes {
        guard let old = entries[id] else { return Changes() }
        var new = old
        change(&new)
        precondition(new.id == id, "An edit can't change an entry's id")
        new.start = new.start.wholeSeconds
        new.end = new.end?.wholeSeconds ?? old.end
        new.tags = Tags.normalize(new.tags)
        new.updated = TimeEntry.sameExceptEnd(old, new) ? old.updated : Timestamp.stamp(after: old.updated, now: now)
        new.endUpdated = new.end == old.end ? old.endUpdated : Timestamp.stamp(after: old.endUpdated, now: now)
        guard new != old else { return Changes() }
        entries[id] = new
        return Changes(months: [old.month, new.month])
    }
}

// MARK: - Clients and projects

extension Ledger {
    @discardableResult
    public mutating func addClient(_ client: Client, now: Timestamp) -> Changes {
        var new = client
        new.updated = now
        clients[new.id] = new
        return Changes(projects: true)
    }

    /// Changes a client and stamps it if anything changed.
    @discardableResult
    public mutating func updateClient(_ id: UUID, now: Timestamp, _ change: (inout Client) -> Void) -> Changes {
        guard let old = clients[id] else { return Changes() }
        var new = old
        change(&new)
        precondition(new.id == id, "An edit can't change a client's id")
        new.updated = old.updated
        guard new != old else { return Changes() }
        new.updated = Timestamp.stamp(after: old.updated, now: now)
        clients[id] = new
        return Changes(projects: true)
    }

    /// Deletes a client and its projects. Throws `LedgerError.hasEntries` if
    /// any of its projects has entries.
    @discardableResult
    public mutating func deleteClient(_ id: UUID, now: Timestamp) throws -> Changes {
        guard clients[id]?.isDeleted == false else { throw LedgerError.notFound }
        let projectIDs = Set(projects.values.filter { $0.clientID == id }.map(\.id))
        guard !hasEntries(inProjects: projectIDs) else { throw LedgerError.hasEntries }
        var changes = updateClient(id, now: now) { $0.deleted = now }
        for projectID in projectIDs where projects[projectID]?.isDeleted == false {
            changes.formUnion(updateProject(projectID, now: now) { $0.deleted = now })
        }
        return changes
    }

    /// Moves every project of one client to another, then deletes the first client.
    @discardableResult
    public mutating func mergeClient(_ id: UUID, into targetID: UUID, now: Timestamp) throws -> Changes {
        guard id != targetID, clients[id]?.isDeleted == false, clients[targetID]?.isDeleted == false else {
            throw LedgerError.notFound
        }
        var changes = Changes()
        for project in projects.values where project.clientID == id {
            changes.formUnion(updateProject(project.id, now: now) { $0.clientID = targetID })
        }
        changes.formUnion(updateClient(id, now: now) { $0.deleted = now })
        return changes
    }

    @discardableResult
    public mutating func addProject(_ project: Project, now: Timestamp) -> Changes {
        var new = project
        new.updated = now
        projects[new.id] = new
        return Changes(projects: true)
    }

    /// Changes a project and stamps it if anything changed.
    @discardableResult
    public mutating func updateProject(_ id: UUID, now: Timestamp, _ change: (inout Project) -> Void) -> Changes {
        guard let old = projects[id] else { return Changes() }
        var new = old
        change(&new)
        precondition(new.id == id, "An edit can't change a project's id")
        new.updated = old.updated
        guard new != old else { return Changes() }
        new.updated = Timestamp.stamp(after: old.updated, now: now)
        projects[id] = new
        return Changes(projects: true)
    }

    /// Deletes a project. Throws `LedgerError.hasEntries` if it has entries.
    @discardableResult
    public mutating func deleteProject(_ id: UUID, now: Timestamp) throws -> Changes {
        guard projects[id]?.isDeleted == false else { throw LedgerError.notFound }
        guard !hasEntries(inProjects: [id]) else { throw LedgerError.hasEntries }
        return updateProject(id, now: now) { $0.deleted = now }
    }

    /// Moves every entry of one project to another, then deletes the first project.
    @discardableResult
    public mutating func mergeProject(_ id: UUID, into targetID: UUID, now: Timestamp) throws -> Changes {
        guard id != targetID, projects[id]?.isDeleted == false, projects[targetID]?.isDeleted == false else {
            throw LedgerError.notFound
        }
        var changes = settleOvertakenTimers(now: now)
        for entry in entries.values where !entry.isDeleted && entry.projectID == id {
            changes.formUnion(edit(entry.id, now: now) { $0.projectID = targetID })
        }
        changes.formUnion(updateProject(id, now: now) { $0.deleted = now })
        return changes
    }

    private func hasEntries(inProjects ids: Set<UUID>) -> Bool {
        entries.values.contains { entry in
            !entry.isDeleted && entry.projectID.map { ids.contains($0) } == true
        }
    }
}
