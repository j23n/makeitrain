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

    /// The order tags are listed in: ignoring case, with numbers in order,
    /// so "#9" comes before "#12".
    public static func order(_ a: String, _ b: String) -> Bool {
        a.compare(b, options: [.caseInsensitive, .numeric]) == .orderedAscending
    }

    /// A tag as a line writes it, so the command line reads it back as a
    /// tag: with a "#" in front, unless it starts with one already or
    /// refers to an issue, as "api#12" does.
    public static func typed(_ tag: String) -> String {
        tag.hasPrefix("#") || GitHub.Reference(tag: tag) != nil ? tag : "#" + tag
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
        case let .trimLater(id, start):
            changes.formUnion(edit(id, now: now) { $0.start = start })
        case let .split(outerID, innerID):
            guard let outer = entries[outerID], let inner = entries[innerID], let innerEnd = inner.end,
                  outer.start < inner.start, outer.end.map({ $0 > innerEnd }) ?? true
            else { break }
            changes.formUnion(edit(outerID, now: now) { $0.end = inner.start })
            changes.formUnion(addCopy(of: outer, id: newID, start: innerEnd, end: outer.end, now: now))
        }
        return changes
    }

    /// Moves the seam between two entries that meet or overlap: the earlier
    /// one ends and the later one starts at `time`, as one change. `time`
    /// stays inside both, at least a minute from either's other end; the
    /// later one runs until now while it runs.
    @discardableResult
    public mutating func moveSeam(earlier earlierID: UUID, later laterID: UUID, to time: Timestamp, now: Timestamp) -> Changes {
        var changes = settleOvertakenTimers(now: now)
        guard let earlier = entries[earlierID], let later = entries[laterID], !earlier.isDeleted, !later.isDeleted,
              earlier.start < later.start, let earlierEnd = earlier.end, earlierEnd >= later.start,
              later.end.map({ earlierEnd <= $0 }) ?? true
        else { return changes }
        let first = earlier.start.adding(seconds: 60)
        let last = (later.end ?? now).adding(seconds: -60)
        guard first <= last else { return changes }
        let seam = min(max(time.wholeSeconds, first), last)
        changes.formUnion(edit(earlierID, now: now) { $0.end = seam })
        changes.formUnion(edit(laterID, now: now) { $0.start = seam })
        return changes
    }

    /// Splits an entry in two at `time`, which has to fall inside it: the
    /// entry ends at `time`, and a copy with the id `newID` starts there and
    /// ends where the entry ended. Splitting the running timer stops it at
    /// `time` and keeps the copy running.
    @discardableResult
    public mutating func split(_ id: UUID, at time: Timestamp, newID: UUID = UUID(), now: Timestamp) -> Changes {
        var changes = settleOvertakenTimers(now: now)
        let at = time.wholeSeconds
        guard let entry = entries[id], !entry.isDeleted, at > entry.start, at < (entry.end ?? now) else {
            return changes
        }
        changes.formUnion(edit(id, now: now) { $0.end = at })
        changes.formUnion(addCopy(of: entry, id: newID, start: at, end: entry.end, now: now))
        return changes
    }

    /// Copies entries to right after them. `copies` maps each entry's id to
    /// its copy's. A copy keeps its entry's project, tags, note, time zone
    /// and length; all copies move by the time from the earliest start to
    /// the latest end, so copies of entries in a row follow in the same
    /// order. Running and deleted entries aren't copied.
    @discardableResult
    public mutating func duplicate(_ copies: [UUID: UUID], now: Timestamp) -> Changes {
        var changes = settleOvertakenTimers(now: now)
        let originals = copies.keys.compactMap { entries[$0] }.filter { !$0.isDeleted && $0.end != nil }
        guard let first = originals.map(\.start).min(), let last = originals.compactMap(\.end).max() else {
            return changes
        }
        let shift = first.distance(to: last)
        for original in originals {
            guard let id = copies[original.id], entries[id] == nil, let end = original.end else { continue }
            changes.formUnion(addCopy(
                of: original,
                id: id,
                start: original.start.adding(milliseconds: shift),
                end: end.adding(milliseconds: shift),
                now: now
            ))
        }
        return changes
    }

    /// Renames a tag, ignoring case, on every entry that has it. Renaming a
    /// tag to another tag's name merges the two.
    @discardableResult
    public mutating func renameTag(_ tag: String, to newName: String, now: Timestamp) -> Changes {
        renameTag(tag, to: newName, now: now) { _ in true }
    }

    /// Renames a tag on the entries of one project, or on unassigned entries
    /// for nil, leaving other projects' tags of the same name alone.
    /// Renaming to a tag the project has already merges the two; renaming to
    /// nothing removes the tag.
    @discardableResult
    public mutating func renameTag(_ tag: String, to newName: String, inProject projectID: UUID?, now: Timestamp) -> Changes {
        renameTag(tag, to: newName, now: now) { $0.projectID == projectID }
    }

    private mutating func renameTag(_ tag: String, to newName: String, now: Timestamp, where included: (TimeEntry) -> Bool) -> Changes {
        var changes = settleOvertakenTimers(now: now)
        for entry in entries.values where !entry.isDeleted && included(entry) && entry.tags.contains(where: { Tags.same($0, tag) }) {
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

    /// Adds a copy of an entry with the id `id`, from `start` to `end`. It
    /// keeps the entry's project, tags, note and time zone.
    private mutating func addCopy(of entry: TimeEntry, id: UUID, start: Timestamp, end: Timestamp?, now: Timestamp) -> Changes {
        let copy = TimeEntry(
            id: id,
            projectID: entry.projectID,
            start: start,
            end: end,
            timeZone: entry.timeZone,
            tags: entry.tags,
            note: entry.note,
            updated: now
        )
        entries[id] = copy
        return Changes(months: [copy.month])
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
