import Foundation
import TrackerCore

/// Something a window is asked to do from elsewhere in the app.
public enum AppRequest: Equatable, Sendable {
    /// The Mac's Settings asks its main window to import or export.
    case importCSV
    case importEvents
    case exportEntries
    /// Type this into the main window's command line, as the projects'
    /// New and Rename do.
    case command(String)
}

/// A data file and what's known about it, as Settings lists them.
public struct DataFileSummary: Identifiable, Hashable, Sendable {
    public var path: String
    /// Such as "54 entries" or "2 clients and 4 projects".
    public var contents: String
    /// Why it can't be used, if it can't.
    public var problem: FileProblem?

    public var id: String { path }
}

extension AppModel {
    /// The data files, newest month first after `projects.json`, with what
    /// each holds and any problem reading it.
    public var dataFiles: [DataFileSummary] {
        var counts: [MonthKey: Int] = [:]
        for entry in ledger.entries.values where !entry.isDeleted {
            counts[entry.month, default: 0] += 1
        }
        let problems = Dictionary(issues.map { ($0.path, $0.problem) }, uniquingKeysWith: { first, _ in first })
        let clients = ledger.clients.values.filter { !$0.isDeleted }.count
        let projects = ledger.projects.values.filter { !$0.isDeleted }.count
        var files = [DataFileSummary(
            path: "projects.json",
            contents: "\(clients) \(clients == 1 ? "client" : "clients") and \(projects) \(projects == 1 ? "project" : "projects")",
            problem: problems["projects.json"]
        )]
        var months = Set(counts.keys)
        for issue in issues {
            if let month = MonthKey(String(issue.path.dropFirst("entries/".count).dropLast(".json".count))) {
                months.insert(month)
            }
        }
        for month in months.sorted(by: >) {
            let path = "entries/\(month.fileName)"
            let count = counts[month] ?? 0
            files.append(DataFileSummary(path: path, contents: "\(count) \(count == 1 ? "entry" : "entries")", problem: problems[path]))
        }
        return files
    }

    /// The backups kept on this device, newest first.
    public var backupNames: [String] {
        ((try? Backups(root: backupsFolder).names()) ?? []).reversed()
    }

    /// Writes a backup now, named for today, as Settings' Back Up Now does.
    public func backUpNow() async throws {
        let backups = Backups(root: backupsFolder)
        let snapshot = ledger
        let name = "\(today) by hand"
        _ = try await Task.detached { try backups.write(snapshot, named: name) }.value
    }
}
