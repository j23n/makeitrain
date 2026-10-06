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
                if clientA != clientB { return clientA < clientB }
                let nameA = a.name.lowercased(), nameB = b.name.lowercased()
                return nameA != nameB ? nameA < nameB : a.id.uuidString < b.id.uuidString
            }
    }

    /// Clients that aren't deleted, sorted by name.
    public func liveClients() -> [Client] {
        clients.values.filter { !$0.isDeleted }.sorted(by: Client.fileOrder)
    }

    /// Every tag on an entry that isn't deleted, once each, ignoring case,
    /// sorted. The spelling used most recently wins.
    public func allTags() -> [String] {
        tags { _ in true }
    }

    /// A project's tags: the tags on its entries that aren't deleted, or on
    /// unassigned entries for nil, once each, ignoring case, sorted. The
    /// spelling used most recently wins.
    public func tags(ofProject projectID: UUID?) -> [String] {
        tags { $0.projectID == projectID }
    }

    /// Every project's tags at once, as `tags(ofProject:)` lists them, by
    /// project id, with nil for unassigned entries. Projects without tags
    /// are left out.
    public func tagsByProject() -> [UUID?: [String]] {
        var spelling: [UUID?: [String: (tag: String, start: Timestamp)]] = [:]
        for entry in entries.values where !entry.isDeleted {
            for tag in entry.tags {
                let key = tag.lowercased()
                if let known = spelling[entry.projectID]?[key], known.start >= entry.start { continue }
                spelling[entry.projectID, default: [:]][key] = (tag, entry.start)
            }
        }
        return spelling.mapValues { $0.values.map(\.tag).sorted(by: Tags.order) }
    }

    private func tags(where included: (TimeEntry) -> Bool) -> [String] {
        var spelling: [String: (tag: String, start: Timestamp)] = [:]
        for entry in entries.values where !entry.isDeleted && included(entry) {
            for tag in entry.tags {
                let key = tag.lowercased()
                if let known = spelling[key], known.start >= entry.start { continue }
                spelling[key] = (tag, entry.start)
            }
        }
        return spelling.values.map(\.tag).sorted(by: Tags.order)
    }
}

/// A project and tags to start a timer with, such as from the "switch to" list.
public struct Combination: Hashable, Sendable {
    public var projectID: UUID?
    public var tags: [String]

    public init(projectID: UUID?, tags: [String]) {
        self.projectID = projectID
        self.tags = tags
    }

    /// Whether an entry has this project and these tags, in any order and
    /// case.
    public func matches(_ entry: TimeEntry) -> Bool {
        entry.projectID == projectID
            && Set(entry.tags.map { $0.lowercased() }) == Set(tags.map { $0.lowercased() })
    }
}
