import Foundation

// How records show up in lists, pickers, reports and the CSV. Like overlaps,
// this is worked out when displaying: a project deleted on one device while
// another logged time to it shows as archived, not as missing.

extension Ledger {
    /// The client an entry's project belongs to, if any.
    public func client(forProject projectID: UUID?) -> Client? {
        projectID.flatMap { projects[$0]?.clientID }.flatMap { clients[$0] }
    }

    /// "Acme › Website redesign", or just the project's name when it has no
    /// client. "Unassigned" for no project, "Unknown project" for an id this
    /// device has no record of.
    public func projectTitle(_ projectID: UUID?) -> String {
        guard let projectID else { return "Unassigned" }
        guard let project = projects[projectID] else { return "Unknown project" }
        if let client = client(forProject: projectID) {
            return "\(client.name) › \(project.name)"
        }
        return project.name
    }

    /// What an entry is called: its note, or else its project's title.
    public func title(of entry: TimeEntry) -> String {
        entry.note.isEmpty ? projectTitle(entry.projectID) : entry.note
    }

    /// Whether a project shows as archived: it's archived or deleted, or its
    /// client is.
    public func isArchived(project projectID: UUID) -> Bool {
        guard let project = projects[projectID] else { return true }
        if project.archived || project.isDeleted { return true }
        if let client = client(forProject: projectID), client.archived || client.isDeleted { return true }
        return false
    }

    /// Projects to offer in pickers: not archived, sorted by client and then
    /// by name, with projects that have no client first.
    public func pickerProjects() -> [Project] {
        projects.values
            .filter { !isArchived(project: $0.id) }
            .sorted { a, b in
                let clientA = client(forProject: a.id)?.name.lowercased() ?? ""
                let clientB = client(forProject: b.id)?.name.lowercased() ?? ""
                return clientA != clientB ? clientA < clientB : Project.fileOrder(a, b)
            }
    }

    /// Clients that aren't deleted, sorted by name.
    public func liveClients() -> [Client] {
        clients.values.filter { !$0.isDeleted }.sorted(by: Client.fileOrder)
    }

    /// The clients a project can be moved to: those that aren't archived,
    /// and its own client if it is, sorted by name.
    public func clientChoices(forProject projectID: UUID) -> [Client] {
        let current = projects[projectID]?.clientID
        return liveClients().filter { !$0.archived || $0.id == current }
    }

    /// The projects a project can be merged into: every other one that
    /// isn't deleted, archived ones too, sorted by title.
    public func mergeTargets(forProject projectID: UUID) -> [Project] {
        projects.values
            .filter { !$0.isDeleted && $0.id != projectID }
            .sorted { projectTitle($0.id).lowercased() < projectTitle($1.id).lowercased() }
    }

    /// Whether a project has entries that aren't deleted, which keep it
    /// from being deleted.
    public func hasEntries(project projectID: UUID) -> Bool {
        entries.values.contains { !$0.isDeleted && $0.projectID == projectID }
    }

    /// Every tag on an entry that isn't deleted, once each, ignoring case,
    /// sorted. The spelling used most recently wins.
    public func allTags() -> [String] {
        Self.latestSpellings(entries.values.filter { !$0.isDeleted })
    }

    /// Every project's tags, by project id, with nil for unassigned
    /// entries: the tags on its entries that aren't deleted, as `allTags()`
    /// lists them. Projects without tags are left out.
    public func tagsByProject() -> [UUID?: [String]] {
        Dictionary(grouping: entries.values.filter { !$0.isDeleted }, by: \.projectID)
            .mapValues(Self.latestSpellings)
            .filter { !$0.value.isEmpty }
    }

    /// The tags of some entries, once each, ignoring case, sorted, each in
    /// the spelling used most recently.
    private static func latestSpellings(_ entries: [TimeEntry]) -> [String] {
        var spelling: [String: (tag: String, start: Timestamp)] = [:]
        for entry in entries {
            for tag in entry.tags {
                let key = tag.lowercased()
                if let known = spelling[key], known.start >= entry.start { continue }
                spelling[key] = (tag, entry.start)
            }
        }
        return spelling.values.map(\.tag).sorted(by: Tags.order)
    }
}
