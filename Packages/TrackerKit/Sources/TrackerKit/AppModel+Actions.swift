import Foundation
import TrackerCore

// The edits the screens can make. Each one takes the window's undo manager,
// or nil where there's none.

extension AppModel {
    // MARK: - Timer

    /// Starts a timer, stopping the running one at the same instant.
    public func startTimer(_ draft: EntryDraft = EntryDraft(), undoManager: UndoManager?) {
        let zone = environment.timeZone()
        edit("Start Timer", undoManager: undoManager) { ledger, now in
            ledger.startTimer(projectID: draft.projectID, tags: draft.tags, note: draft.note, timeZone: zone, at: now, now: now)
        }
    }

    /// Starts a timer for what an entry was for: its project, tags and note.
    public func continueEntry(_ entry: ResolvedEntry, undoManager: UndoManager?) {
        startTimer(EntryDraft(entry.entry), undoManager: undoManager)
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

    /// Changes an entry, as one step to undo with the name `actionName`.
    public func updateEntry(_ id: UUID, actionName: String, undoManager: UndoManager?, _ change: (inout TimeEntry) -> Void) {
        edit(actionName, undoManager: undoManager) { ledger, now in
            ledger.updateEntry(id, now: now, change)
        }
    }

    public func deleteEntry(_ id: UUID, undoManager: UndoManager?) {
        edit("Delete Entry", undoManager: undoManager) { ledger, now in
            ledger.deleteEntry(id, now: now)
        }
    }

    /// Copies an entry to right after it, and returns the copy's id, or nil
    /// for the running timer, which isn't copied.
    @discardableResult
    public func duplicateEntry(_ id: UUID, undoManager: UndoManager?) -> UUID? {
        let copy = UUID()
        edit("Duplicate Entry", undoManager: undoManager) { ledger, now in
            ledger.duplicate([id: copy], now: now)
        }
        return ledger.entries[copy] == nil ? nil : copy
    }

    /// Splits an entry in two at `time`, which has to fall inside it.
    public func splitEntry(_ id: UUID, at time: Timestamp, undoManager: UndoManager?) {
        edit("Split Entry", undoManager: undoManager) { ledger, now in
            ledger.split(id, at: time, now: now)
        }
    }

    /// Splits an entry in two in its middle, as `EntrySplit` finds it. An
    /// entry too short to split stays as it is.
    public func splitInMiddle(_ entry: ResolvedEntry, undoManager: UndoManager?) {
        guard let time = EntrySplit.time(for: entry, now: now) else { return }
        splitEntry(entry.id, at: time, undoManager: undoManager)
    }

    // MARK: - Import

    /// What importing a CSV file would add, without adding anything. New
    /// projects get the palette's next colors.
    public func importPlan(for data: Data) throws -> CSVImport.Plan {
        try CSVImport.plan(data, into: ledger, timeZone: environment.timeZone(), now: environment.now())
    }

    /// Reads a CSV file picked in a file importer, which may be outside the
    /// app's sandbox.
    public func importRequest(forFileAt url: URL) throws -> ImportRequest {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        let data = try Data(contentsOf: url)
        return ImportRequest(fileName: url.lastPathComponent, plan: try importPlan(for: data))
    }

    /// Adds what an import plan found, as one step to undo.
    public func importEntries(_ plan: CSVImport.Plan, undoManager: UndoManager?) {
        edit("Import Entries", undoManager: undoManager) { ledger, now in
            ledger.add(plan, now: now)
        }
    }

    // MARK: - Clients and projects

    public func updateClient(_ id: UUID, actionName: String = "Edit Client", undoManager: UndoManager?, _ change: (inout Client) -> Void) {
        edit(actionName, undoManager: undoManager) { ledger, now in
            ledger.updateClient(id, now: now, change)
        }
    }

    public func mergeClient(_ id: UUID, into target: UUID, undoManager: UndoManager?) throws {
        try edit("Merge Clients", undoManager: undoManager) { ledger, now in
            try ledger.mergeClient(id, into: target, now: now)
        }
    }

    public func updateProject(_ id: UUID, actionName: String = "Edit Project", undoManager: UndoManager?, _ change: (inout Project) -> Void) {
        edit(actionName, undoManager: undoManager) { ledger, now in
            ledger.updateProject(id, now: now, change)
        }
    }

    /// Renames a project, without the spaces and line breaks around the
    /// name. An empty name, or the one it has, changes nothing.
    public func renameProject(_ id: UUID, to name: String, undoManager: UndoManager?) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != ledger.projects[id]?.name else { return }
        updateProject(id, actionName: "Rename Project", undoManager: undoManager) { $0.name = trimmed }
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

    /// Renames a tag on a project's entries, or on unassigned entries for
    /// nil. Renaming it to another of the project's tags merges the two, in
    /// that tag's spelling. An empty name, or the one it has, changes nothing.
    public func renameTag(_ tag: String, to newName: String, inProject projectID: UUID?, undoManager: UndoManager?) {
        guard let cleaned = Tags.normalize([newName]).first, cleaned != tag else { return }
        let existing = projectTags[projectID]?.first { Tags.same($0, cleaned) && !Tags.same($0, tag) }
        edit("Rename Tag", undoManager: undoManager) { ledger, now in
            ledger.renameTag(tag, to: existing ?? cleaned, inProject: projectID, now: now)
        }
    }

    /// Takes a tag off a project's entries, or off unassigned entries for nil.
    public func removeTag(_ tag: String, fromProject projectID: UUID?, undoManager: UndoManager?) {
        edit("Remove Tag", undoManager: undoManager) { ledger, now in
            ledger.renameTag(tag, to: "", inProject: projectID, now: now)
        }
    }

    // MARK: - GitHub

    /// Adds a GitHub repository to a project, written as "owner/name" or as
    /// its address. Returns false if that isn't a repository; adding one
    /// the project has already changes nothing.
    @discardableResult
    public func addRepository(_ text: String, toProject projectID: UUID, undoManager: UndoManager?) -> Bool {
        guard let repository = GitHub.Repository(text) else { return false }
        guard let project = ledger.projects[projectID] else { return true }
        let known = project.repositories.compactMap { GitHub.Repository($0) }
        guard !known.contains(where: { $0.address.lowercased() == repository.address.lowercased() }) else { return true }
        setRepositories(project.repositories + [repository.address], ofProject: projectID, actionName: "Add Repository", undoManager: undoManager)
        return true
    }

    /// Removes a repository. If it was the first of several, the project's
    /// tags like "#123" are rewritten to keep referring to it.
    public func removeRepository(_ address: String, fromProject projectID: UUID, undoManager: UndoManager?) {
        guard let project = ledger.projects[projectID] else { return }
        setRepositories(project.repositories.filter { $0 != address }, ofProject: projectID, actionName: "Remove Repository", undoManager: undoManager)
    }

    /// Moves a repository to the front, so "#123" refers to its issues. The
    /// project's tags that referred to the previous first repository are
    /// rewritten to name it, as in "web#123", so they keep their issues.
    public func makeFirstRepository(_ address: String, ofProject projectID: UUID, undoManager: UndoManager?) {
        guard let project = ledger.projects[projectID], project.repositories.contains(address) else { return }
        let reordered = [address] + project.repositories.filter { $0 != address }
        setRepositories(reordered, ofProject: projectID, actionName: "Change First Repository", undoManager: undoManager)
    }

    /// Changes a project's repositories and the tags that follow from that,
    /// as one step to undo.
    private func setRepositories(_ repositories: [String], ofProject projectID: UUID, actionName: String, undoManager: UndoManager?) {
        edit(actionName, undoManager: undoManager) { ledger, now in
            ledger.setRepositories(repositories, ofProject: projectID, now: now)
        }
    }
}
