import Foundation

/// Earlier copies of the records an edit changed, so the edit can be undone.
///
/// Take one with `Ledger.snapshot(since:)` after an edit, passing the ledger
/// from before it. `Ledger.restore(_:now:)` puts the copies back as a new
/// change, so the undo also wins when merged with other devices. Taking a
/// snapshot of the restore gives the redo.
public struct Snapshot: Hashable, Sendable {
    /// Entries as they were before the edit.
    public var entries: [TimeEntry] = []
    /// Entries the edit created.
    public var addedEntries: Set<UUID> = []
    public var clients: [Client] = []
    public var addedClients: Set<UUID> = []
    public var projects: [Project] = []
    public var addedProjects: Set<UUID> = []

    public init() {}

    public var isEmpty: Bool {
        entries.isEmpty && addedEntries.isEmpty && clients.isEmpty && addedClients.isEmpty
            && projects.isEmpty && addedProjects.isEmpty
    }
}

extension Ledger {
    /// The copies in `earlier` of every record that differs in this ledger.
    public func snapshot(since earlier: Ledger) -> Snapshot {
        var snapshot = Snapshot()
        for (id, entry) in entries where earlier.entries[id] != entry {
            if let old = earlier.entries[id] {
                snapshot.entries.append(old)
            } else {
                snapshot.addedEntries.insert(id)
            }
        }
        for (id, client) in clients where earlier.clients[id] != client {
            if let old = earlier.clients[id] {
                snapshot.clients.append(old)
            } else {
                snapshot.addedClients.insert(id)
            }
        }
        for (id, project) in projects where earlier.projects[id] != project {
            if let old = earlier.projects[id] {
                snapshot.projects.append(old)
            } else {
                snapshot.addedProjects.insert(id)
            }
        }
        return snapshot
    }

    /// Puts the records in `snapshot` back the way they were, stamped as new
    /// changes. Records the snapshot says were added are deleted.
    ///
    /// Unlike an ordinary edit, a restore can clear an entry's end, so
    /// undoing a stop starts the timer again.
    @discardableResult
    public mutating func restore(_ snapshot: Snapshot, now: Timestamp) -> Changes {
        var changes = Changes()
        for old in snapshot.entries {
            guard let current = entries[old.id] else {
                // Nothing to stamp against; the copy goes back as it was.
                entries[old.id] = old
                changes.months.insert(old.month)
                continue
            }
            var restored = current
            restored.projectID = old.projectID
            restored.start = old.start
            restored.end = old.end
            restored.timeZone = old.timeZone
            restored.tags = old.tags
            restored.note = old.note
            restored.deleted = old.deleted
            changes.formUnion(replace(current, with: restored, now: now))
        }
        for id in snapshot.addedEntries {
            guard let current = entries[id], !current.isDeleted else { continue }
            var deleted = current
            deleted.deleted = now
            deleted.note = ""
            deleted.tags = []
            changes.formUnion(replace(current, with: deleted, now: now))
        }
        for old in snapshot.clients {
            changes.formUnion(updateClient(old.id, now: now) { client in
                client.name = old.name
                client.archived = old.archived
                client.deleted = old.deleted
            })
        }
        for id in snapshot.addedClients where clients[id]?.isDeleted == false {
            changes.formUnion(updateClient(id, now: now) { $0.deleted = now })
        }
        for old in snapshot.projects {
            changes.formUnion(updateProject(old.id, now: now) { project in
                project.clientID = old.clientID
                project.name = old.name
                project.color = old.color
                project.archived = old.archived
                project.deleted = old.deleted
            })
        }
        for id in snapshot.addedProjects where projects[id]?.isDeleted == false {
            changes.formUnion(updateProject(id, now: now) { $0.deleted = now })
        }
        return changes
    }

    /// Stores `new` in place of `current`, stamping what changed. Unlike
    /// `updateEntry`, it can clear the end.
    private mutating func replace(_ current: TimeEntry, with new: TimeEntry, now: Timestamp) -> Changes {
        var new = new
        new.updated = TimeEntry.sameExceptEnd(current, new) ? current.updated : Timestamp.stamp(after: current.updated, now: now)
        new.endUpdated = new.end == current.end ? current.endUpdated : Timestamp.stamp(after: current.endUpdated, now: now)
        guard new != current else { return Changes() }
        entries[new.id] = new
        return Changes(months: [current.month, new.month])
    }
}
