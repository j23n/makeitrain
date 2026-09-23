import Foundation

/// Every client, project and entry, including deleted ones, by id.
///
/// The app keeps one ledger in memory. Copies from files and other devices
/// are merged into it record by record; edits go through the methods in
/// Editing.swift, which stamp what changed.
public struct Ledger: Hashable, Sendable {
    public internal(set) var clients: [UUID: Client]
    public internal(set) var projects: [UUID: Project]
    public internal(set) var entries: [UUID: TimeEntry]

    public init(clients: [Client] = [], projects: [Project] = [], entries: [TimeEntry] = []) {
        self.clients = [:]
        self.projects = [:]
        self.entries = [:]
        for client in clients { merge(client) }
        for project in projects { merge(project) }
        for entry in entries { merge(entry) }
    }

    /// Merges in a copy of a client. Returns whether the ledger changed.
    @discardableResult
    public mutating func merge(_ client: Client) -> Bool {
        let merged = clients[client.id].map { $0.merged(with: client) } ?? client
        guard merged != clients[client.id] else { return false }
        clients[client.id] = merged
        return true
    }

    /// Merges in a copy of a project. Returns whether the ledger changed.
    @discardableResult
    public mutating func merge(_ project: Project) -> Bool {
        let merged = projects[project.id].map { $0.merged(with: project) } ?? project
        guard merged != projects[project.id] else { return false }
        projects[project.id] = merged
        return true
    }

    /// Merges in a copy of an entry. Returns whether the ledger changed.
    @discardableResult
    public mutating func merge(_ entry: TimeEntry) -> Bool {
        let merged = entries[entry.id].map { $0.merged(with: entry) } ?? entry
        guard merged != entries[entry.id] else { return false }
        entries[entry.id] = merged
        return true
    }

    /// Merges in every record of another ledger.
    public mutating func merge(_ other: Ledger) {
        for client in other.clients.values { merge(client) }
        for project in other.projects.values { merge(project) }
        for entry in other.entries.values { merge(entry) }
    }

    public func merging(_ other: Ledger) -> Ledger {
        var result = self
        result.merge(other)
        return result
    }
}
