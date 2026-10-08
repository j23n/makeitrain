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
        self.clients = Dictionary(clients.map { ($0.id, $0) }, uniquingKeysWith: { $0.merged(with: $1) })
        self.projects = Dictionary(projects.map { ($0.id, $0) }, uniquingKeysWith: { $0.merged(with: $1) })
        self.entries = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { $0.merged(with: $1) })
    }

    /// Merges in a copy of a client.
    public mutating func merge(_ client: Client) {
        clients[client.id] = clients[client.id].map { $0.merged(with: client) } ?? client
    }

    /// Merges in a copy of a project.
    public mutating func merge(_ project: Project) {
        projects[project.id] = projects[project.id].map { $0.merged(with: project) } ?? project
    }

    /// Merges in a copy of an entry.
    public mutating func merge(_ entry: TimeEntry) {
        entries[entry.id] = entries[entry.id].map { $0.merged(with: entry) } ?? entry
    }

    /// Merges in every record of another ledger.
    public mutating func merge(_ other: Ledger) {
        clients.merge(other.clients) { $0.merged(with: $1) }
        projects.merge(other.projects) { $0.merged(with: $1) }
        entries.merge(other.entries) { $0.merged(with: $1) }
    }
}
