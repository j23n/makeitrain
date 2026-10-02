import SwiftUI
import TrackerCore

// Clients and their projects with the time logged to each, for the Clients
// & Projects screens on the Mac and the iPad.

/// A client or project in the outline, with the time logged to it.
public struct ProjectListRow: Identifiable, Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case client(UUID)
        case noClient
        case project(UUID)
    }

    public var id: Kind
    public var title: String
    public var color: String?
    public var archived: Bool
    public var milliseconds: Int64
    public var children: [ProjectListRow]?

    /// Projects without a client come first under "No client", then each
    /// client with its projects. Archived ones only when asked for.
    public static func rows(ledger: Ledger, resolved: [ResolvedEntry], now: Timestamp, showArchived: Bool) -> [ProjectListRow] {
        var time: [UUID: Int64] = [:]
        for entry in resolved {
            if let projectID = entry.entry.projectID {
                time[projectID, default: 0] += entry.duration(now: now)
            }
        }
        let clients = ledger.liveClients()
        let clientIDs = Set(clients.map(\.id))
        let projects = ledger.projects.values
            .filter { !$0.isDeleted }
            .sorted { a, b in
                let (nameA, nameB) = (a.name.lowercased(), b.name.lowercased())
                return nameA != nameB ? nameA < nameB : a.id.uuidString < b.id.uuidString
            }

        func projectRows(where belongs: (Project) -> Bool) -> [ProjectListRow] {
            projects.filter { belongs($0) && (showArchived || !$0.archived) }.map { project in
                ProjectListRow(
                    id: .project(project.id),
                    title: project.name,
                    color: project.color,
                    archived: project.archived,
                    milliseconds: time[project.id] ?? 0,
                    children: nil
                )
            }
        }
        func totalTime(where belongs: (Project) -> Bool) -> Int64 {
            projects.filter(belongs).reduce(0) { $0 + (time[$1.id] ?? 0) }
        }

        var result: [ProjectListRow] = []
        let noClient: (Project) -> Bool = { project in project.clientID.map { !clientIDs.contains($0) } ?? true }
        let unfiled = projectRows(where: noClient)
        if !unfiled.isEmpty {
            result.append(ProjectListRow(
                id: .noClient,
                title: "No client",
                color: nil,
                archived: false,
                milliseconds: totalTime(where: noClient),
                children: unfiled
            ))
        }
        for client in clients where showArchived || !client.archived {
            let children = projectRows { $0.clientID == client.id }
            result.append(ProjectListRow(
                id: .client(client.id),
                title: client.name,
                color: nil,
                archived: client.archived,
                milliseconds: totalTime { $0.clientID == client.id },
                children: children.isEmpty ? nil : children
            ))
        }
        return result
    }
}

/// A client or project with its color and the time logged to it.
public struct ProjectListRowView: View {
    let row: ProjectListRow

    public init(row: ProjectListRow) {
        self.row = row
    }

    public var body: some View {
        HStack(spacing: 8) {
            if let color = row.color {
                ProjectDot(color: Color(hex: color))
            }
            Text(row.title)
                .foregroundStyle(row.archived ? .secondary : .primary)
            if row.archived {
                Text("Archived")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(Format.duration(row.milliseconds))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
