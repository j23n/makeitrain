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

    /// What it holds, or why it can't be used, such as "Not downloaded
    /// yet."
    public var detail: String {
        guard let problem else { return contents }
        switch problem {
        case .unreadable: return "Can't be read. Left unchanged."
        case let .newerVersion(version): return "From a newer version (\(version)). Left unchanged."
        case .notDownloaded: return "Not downloaded yet."
        }
    }
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

    /// The newest backup kept on this device, if there's one.
    public var latestBackup: String? {
        try? Backups(root: backupsFolder).names().last
    }

    /// Writes a backup now, named for today, as Settings' Back Up Now does.
    public func backUpNow() async throws {
        try await writeBackup("by hand")
    }

    /// Writes a backup of all the data, named for today and `label`, such
    /// as "2026-09-23 by hand", off the main thread.
    func writeBackup(_ label: String) async throws {
        let backups = Backups(root: backupsFolder)
        let snapshot = ledger
        let name = "\(today) \(label)"
        _ = try await Task.detached { try backups.write(snapshot, named: name) }.value
    }

    /// Whether there's an entry to export: one that isn't running.
    public var hasFinishedEntries: Bool {
        resolved.contains { !$0.isRunning }
    }

    /// Every finished entry as a CSV file, with the columns of a report's
    /// export, and the file's name; nil when there's none yet.
    public func finishedEntriesCSV() -> (document: ExportDocument, fileName: String)? {
        let entries = resolved.filter { !$0.isRunning }
        guard let fileName = CSVExport.fileName(for: entries) else { return nil }
        return (document: ExportDocument(data: CSVExport.data(for: entries, ledger: ledger)), fileName: fileName)
    }
}
