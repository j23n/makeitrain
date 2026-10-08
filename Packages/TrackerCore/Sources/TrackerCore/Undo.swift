import Foundation

extension Ledger {
    /// Undoes an edit: puts the records in `diff`, taken with
    /// `diff(from:)` after the edit, back the way they were, stamped as new
    /// changes, so the undo also wins when merged with other devices.
    /// Records the edit added are deleted. The diff of the restore is the
    /// redo.
    ///
    /// Unlike an ordinary edit, a restore can clear an entry's end, so
    /// undoing a stop starts the timer again.
    @discardableResult
    public mutating func restore(_ diff: LedgerDiff, now: Timestamp) -> Changes {
        var changes = Changes()
        for change in diff.entries {
            if let old = change.before {
                guard let current = entries[old.id] else { continue }
                var restored = current
                restored.projectID = old.projectID
                restored.start = old.start
                restored.end = old.end
                restored.timeZone = old.timeZone
                restored.tags = old.tags
                restored.note = old.note
                restored.deleted = old.deleted
                changes.formUnion(replace(current, with: restored, now: now))
            } else if let added = change.after, let current = entries[added.id], !current.isDeleted {
                var deleted = current
                deleted.deleted = now
                deleted.note = ""
                deleted.tags = []
                changes.formUnion(replace(current, with: deleted, now: now))
            }
        }
        for change in diff.clients {
            if let old = change.before {
                changes.formUnion(updateClient(old.id, now: now) { client in
                    client.name = old.name
                    client.archived = old.archived
                    client.deleted = old.deleted
                })
            } else if let added = change.after, clients[added.id]?.isDeleted == false {
                changes.formUnion(updateClient(added.id, now: now) { $0.deleted = now })
            }
        }
        for change in diff.projects {
            if let old = change.before {
                changes.formUnion(updateProject(old.id, now: now) { project in
                    project.clientID = old.clientID
                    project.name = old.name
                    project.color = old.color
                    project.archived = old.archived
                    project.repositories = old.repositories
                    project.deleted = old.deleted
                })
            } else if let added = change.after, projects[added.id]?.isDeleted == false {
                changes.formUnion(updateProject(added.id, now: now) { $0.deleted = now })
            }
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
