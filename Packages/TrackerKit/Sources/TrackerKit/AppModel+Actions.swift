import Foundation
import TrackerCore

// The edits the screens can make. Each one takes the window's undo manager,
// or nil where there's none.

extension AppModel {
    // MARK: - Timer

    /// Starts a timer, stopping the running one at the same instant.
    public func startTimer(_ combination: Combination = Combination(projectID: nil, tags: []), note: String = "", undoManager: UndoManager?) {
        let zone = environment.timeZone()
        edit("Start Timer", undoManager: undoManager) { ledger, now in
            ledger.startTimer(projectID: combination.projectID, tags: combination.tags, note: note, timeZone: zone, at: now, now: now)
        }
    }

    /// Stops the running timer, now or at an earlier time.
    public func stopTimer(at time: Timestamp? = nil, undoManager: UndoManager?) {
        edit("Stop Timer", undoManager: undoManager) { ledger, now in
            ledger.stopTimer(at: time ?? now, now: now)
        }
    }

    /// Moves the running timer's start, such as back to when work began.
    public func setRunningStart(_ start: Timestamp, undoManager: UndoManager?) {
        guard let running else { return }
        edit("Change Start", undoManager: undoManager) { ledger, now in
            ledger.updateEntry(running.id, now: now) { $0.start = min(start, now) }
        }
    }

    // MARK: - Entries

    /// Adds an entry made by hand.
    public func addEntry(_ entry: TimeEntry, undoManager: UndoManager?) {
        edit("Add Entry", undoManager: undoManager) { ledger, now in
            ledger.addEntry(entry, now: now)
        }
    }

    /// Applies the same change to several entries as one undoable step.
    public func updateEntries(
        _ ids: some Collection<UUID>,
        actionName: String = "Edit Entry",
        undoManager: UndoManager?,
        _ change: (inout TimeEntry) -> Void
    ) {
        edit(actionName, undoManager: undoManager) { ledger, now in
            var changes = Changes()
            for id in ids {
                changes.formUnion(ledger.updateEntry(id, now: now, change))
            }
            return changes
        }
    }

    public func deleteEntries(_ ids: some Collection<UUID>, undoManager: UndoManager?) {
        edit(ids.count == 1 ? "Delete Entry" : "Delete Entries", undoManager: undoManager) { ledger, now in
            var changes = Changes()
            for id in ids {
                changes.formUnion(ledger.deleteEntry(id, now: now))
            }
            return changes
        }
    }

    /// Applies a one-click overlap fix.
    public func apply(_ fix: OverlapFix, undoManager: UndoManager?) {
        let name: String
        switch fix {
        case .split: name = "Split Entry"
        case .trimEarlier: name = "Trim Entry"
        }
        edit(name, undoManager: undoManager) { ledger, now in
            ledger.apply(fix, now: now)
        }
    }

    // MARK: - Clients and projects

    /// Adds a client and returns its id.
    @discardableResult
    public func addClient(named name: String, undoManager: UndoManager?) -> UUID {
        let client = Client(name: name, updated: environment.now())
        edit("Add Client", undoManager: undoManager) { ledger, now in
            ledger.addClient(client, now: now)
        }
        return client.id
    }

    public func updateClient(_ id: UUID, actionName: String = "Edit Client", undoManager: UndoManager?, _ change: (inout Client) -> Void) {
        edit(actionName, undoManager: undoManager) { ledger, now in
            ledger.updateClient(id, now: now, change)
        }
    }

    /// Deletes a client and its projects. Throws `LedgerError.hasEntries`
    /// if they have entries; archive the client instead.
    public func deleteClient(_ id: UUID, undoManager: UndoManager?) throws {
        try edit("Delete Client", undoManager: undoManager) { ledger, now in
            try ledger.deleteClient(id, now: now)
        }
    }

    public func mergeClient(_ id: UUID, into target: UUID, undoManager: UndoManager?) throws {
        try edit("Merge Clients", undoManager: undoManager) { ledger, now in
            try ledger.mergeClient(id, into: target, now: now)
        }
    }

    /// Adds a project and returns its id.
    @discardableResult
    public func addProject(named name: String, client: UUID?, color: String, undoManager: UndoManager?) -> UUID {
        let project = Project(clientID: client, name: name, color: color, updated: environment.now())
        edit("Add Project", undoManager: undoManager) { ledger, now in
            ledger.addProject(project, now: now)
        }
        return project.id
    }

    public func updateProject(_ id: UUID, actionName: String = "Edit Project", undoManager: UndoManager?, _ change: (inout Project) -> Void) {
        edit(actionName, undoManager: undoManager) { ledger, now in
            ledger.updateProject(id, now: now, change)
        }
    }

    /// Deletes a project. Throws `LedgerError.hasEntries` if it has entries;
    /// archive it instead.
    public func deleteProject(_ id: UUID, undoManager: UndoManager?) throws {
        try edit("Delete Project", undoManager: undoManager) { ledger, now in
            try ledger.deleteProject(id, now: now)
        }
    }

    public func mergeProject(_ id: UUID, into target: UUID, undoManager: UndoManager?) throws {
        try edit("Merge Projects", undoManager: undoManager) { ledger, now in
            try ledger.mergeProject(id, into: target, now: now)
        }
    }

    /// Renames a tag on every entry; renaming to an existing tag merges them.
    public func renameTag(_ tag: String, to newName: String, undoManager: UndoManager?) {
        edit("Rename Tag", undoManager: undoManager) { ledger, now in
            ledger.renameTag(tag, to: newName, now: now)
        }
    }
}
