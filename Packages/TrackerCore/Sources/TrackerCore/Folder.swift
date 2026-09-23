import Foundation

/// The file operations the file store needs.
///
/// The local folder and tests use `LocalFileAccess`. iCloud needs a version
/// that wraps each call in `NSFileCoordinator`.
public protocol FileAccess: Sendable {
    /// The names of the files in a folder, or none if it doesn't exist.
    func fileNames(in folder: URL) throws -> [String]
    /// A file's contents, or nil if it doesn't exist.
    func read(_ file: URL) throws -> Data?
    /// Replaces a file's contents in one step, creating its folder if needed.
    func write(_ data: Data, to file: URL) throws
    /// Deletes a file if it exists.
    func remove(_ file: URL) throws
    /// Runs `body`, which reads `file`, while no one else writes it.
    func coordinateReading<T>(_ file: URL, _ body: () throws -> T) throws -> T
    /// Runs `body`, which reads and then writes `files`, while no one else
    /// reads or writes them, on this Mac or through iCloud.
    func coordinateWriting<T>(_ files: [URL], _ body: () throws -> T) throws -> T
}

/// Plain file access, for the local folder, which only this app writes.
public struct LocalFileAccess: FileAccess {
    public init() {}

    public func fileNames(in folder: URL) throws -> [String] {
        guard FileManager.default.fileExists(atPath: folder.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(atPath: folder.path)
    }

    public func read(_ file: URL) throws -> Data? {
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return try Data(contentsOf: file)
    }

    public func write(_ data: Data, to file: URL) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: file, options: .atomic)
    }

    public func remove(_ file: URL) throws {
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        try FileManager.default.removeItem(at: file)
    }

    public func coordinateReading<T>(_ file: URL, _ body: () throws -> T) throws -> T {
        try body()
    }

    public func coordinateWriting<T>(_ files: [URL], _ body: () throws -> T) throws -> T {
        try body()
    }
}

/// A problem with one file in the data folder.
public struct FileIssue: Hashable, Sendable {
    /// The file's path in the data folder, such as "entries/2026-09.json".
    public var path: String
    public var problem: FileProblem

    public init(path: String, problem: FileProblem) {
        self.path = path
        self.problem = problem
    }
}

/// What loading the data folder found.
public struct LoadResult: Sendable {
    /// Every record in every readable file, merged.
    public var ledger: Ledger
    /// Files that couldn't be read. They're left untouched.
    public var issues: [FileIssue]
    /// Files to save soon: numbered copies to fold in, and entries filed in
    /// the wrong month.
    public var pending: Changes
}

/// What saving found.
public struct SaveResult: Sendable {
    /// The ledger that was saved, merged with everything found on disk on
    /// the way.
    public var ledger: Ledger
    /// Files that couldn't be saved because they can't be read.
    public var issues: [FileIssue]
    /// What's still unsaved because of those files.
    public var pending: Changes
}

/// The data folder: `projects.json` for clients and projects, and one file
/// per month in `entries/`.
///
/// Saving never replaces a file blindly. It reads the file as it is now,
/// merges it with the ledger by id and writes the result, so changes another
/// device made in the meantime are kept. A file that can't be read is never
/// written.
public struct Folder: Sendable {
    public let root: URL
    public let access: any FileAccess

    public init(root: URL, access: any FileAccess = LocalFileAccess()) {
        self.root = root
        self.access = access
    }

    var projectsFile: URL {
        root.appendingPathComponent("projects.json")
    }

    var entriesFolder: URL {
        root.appendingPathComponent("entries", isDirectory: true)
    }

    func monthFile(_ month: MonthKey) -> URL {
        entriesFolder.appendingPathComponent(month.fileName)
    }

    // MARK: Loading

    /// Reads every data file, including iCloud's numbered copies, and merges
    /// them by id.
    public func load() throws -> LoadResult {
        var result = LoadResult(ledger: Ledger(), issues: [], pending: Changes())

        for name in try access.fileNames(in: root).sorted() {
            guard let fileName = DataFileName(name), fileName.base == "projects" else { continue }
            let url = root.appendingPathComponent(name)
            do {
                guard let data = try access.coordinateReading(url, { try access.read(url) }) else { continue }
                let contents = try FileFormat.decodeProjects(from: data)
                for client in contents.clients { result.ledger.merge(client) }
                for project in contents.projects { result.ledger.merge(project) }
                if fileName.copy != nil {
                    result.pending.projects = true
                }
            } catch {
                result.issues.append(FileIssue(path: name, problem: FileProblem(error)))
            }
        }

        var filed: [(month: MonthKey, entries: [TimeEntry])] = []
        for name in try access.fileNames(in: entriesFolder).sorted() {
            guard let fileName = DataFileName(name), let month = MonthKey(fileName.base) else { continue }
            let url = entriesFolder.appendingPathComponent(name)
            do {
                guard let data = try access.coordinateReading(url, { try access.read(url) }) else { continue }
                let entries = try FileFormat.decodeEntries(from: data)
                for entry in entries { result.ledger.merge(entry) }
                filed.append((month, entries))
                if fileName.copy != nil {
                    result.pending.months.insert(month)
                }
            } catch {
                result.issues.append(FileIssue(path: "entries/" + name, problem: FileProblem(error)))
            }
        }

        // An entry filed in the wrong month, such as the old copy of one that
        // moved, is saved into its month and then removed from the wrong one.
        for (month, entries) in filed {
            for entry in entries {
                guard let home = result.ledger.entries[entry.id]?.month, home != month else { continue }
                result.pending.months.formUnion([month, home])
            }
        }
        return result
    }

    // MARK: Saving

    /// Saves the files named in `changes` and returns the ledger merged with
    /// what they held.
    ///
    /// When an entry moves to another month, its new month is written first
    /// and the old one cleaned up afterwards. A crash in between leaves a
    /// duplicate, which merging handles, rather than a lost entry.
    public func save(_ ledger: Ledger, changes: Changes) throws -> SaveResult {
        var result = SaveResult(ledger: ledger, issues: [], pending: Changes())
        if changes.projects {
            try saveProjects(into: &result)
        }

        let names = try access.fileNames(in: entriesFolder)
        var queue = changes.months
        var saved: Set<MonthKey> = []
        var blocked: Set<MonthKey> = []
        var holdingStrays: Set<MonthKey> = []
        while let month = queue.min() {
            queue.remove(month)
            guard let strayHomes = try saveMonth(month, names: names, saved: saved, into: &result) else {
                blocked.insert(month)
                continue
            }
            saved.insert(month)
            if !strayHomes.isEmpty {
                holdingStrays.insert(month)
                queue.formUnion(strayHomes.subtracting(blocked))
            }
        }
        // Every stray's month is written now, unless its file can't be read,
        // so the strays can go.
        for month in holdingStrays.sorted() {
            _ = try saveMonth(month, names: names, saved: saved, into: &result)
        }
        return result
    }

    /// Read-merge-writes one month file and folds in its numbered copies.
    ///
    /// Entries found here that belong in a month not saved yet stay here for
    /// now; the function returns those months. Returns nil if the file can't
    /// be read.
    private func saveMonth(
        _ month: MonthKey,
        names: [String],
        saved: Set<MonthKey>,
        into result: inout SaveResult
    ) throws -> Set<MonthKey>? {
        let file = monthFile(month)
        let copies = names
            .filter { DataFileName($0).map { $0.base == month.description && $0.copy != nil } ?? false }
            .sorted()
            .map { entriesFolder.appendingPathComponent($0) }

        return try access.coordinateWriting([file] + copies) {
            var onDisk: [TimeEntry] = []
            do {
                if let data = try access.read(file) {
                    onDisk = try FileFormat.decodeEntries(from: data)
                }
            } catch {
                result.issues.append(FileIssue(path: "entries/" + month.fileName, problem: FileProblem(error)))
                result.pending.months.insert(month)
                return nil
            }
            var found = onDisk
            var folded: [URL] = []
            for copy in copies {
                do {
                    guard let data = try access.read(copy) else { continue }
                    found += try FileFormat.decodeEntries(from: data)
                    folded.append(copy)
                } catch {
                    result.issues.append(FileIssue(path: "entries/" + copy.lastPathComponent, problem: FileProblem(error)))
                }
            }
            for entry in found {
                result.ledger.merge(entry)
            }

            var records: [UUID: TimeEntry] = [:]
            for entry in result.ledger.entries.values where entry.month == month {
                records[entry.id] = entry
            }
            var strayHomes: Set<MonthKey> = []
            for entry in found {
                guard let home = result.ledger.entries[entry.id]?.month, home != month, !saved.contains(home) else { continue }
                records[entry.id] = records[entry.id].map { $0.merged(with: entry) } ?? entry
                strayHomes.insert(home)
            }

            let contents = records.values.sorted(by: TimeEntry.fileOrder)
            if contents != onDisk.sorted(by: TimeEntry.fileOrder) {
                try access.write(FileFormat.encode(entries: contents), to: file)
            }
            for copy in folded {
                try access.remove(copy)
            }
            return strayHomes
        }
    }

    /// Read-merge-writes `projects.json` and folds in its numbered copies.
    private func saveProjects(into result: inout SaveResult) throws {
        let copies = try access.fileNames(in: root)
            .filter { DataFileName($0).map { $0.base == "projects" && $0.copy != nil } ?? false }
            .sorted()
            .map { root.appendingPathComponent($0) }

        try access.coordinateWriting([projectsFile] + copies) {
            var onDisk: (clients: [Client], projects: [Project]) = ([], [])
            do {
                if let data = try access.read(projectsFile) {
                    onDisk = try FileFormat.decodeProjects(from: data)
                }
            } catch {
                result.issues.append(FileIssue(path: "projects.json", problem: FileProblem(error)))
                result.pending.projects = true
                return
            }
            var found = onDisk
            var folded: [URL] = []
            for copy in copies {
                do {
                    guard let data = try access.read(copy) else { continue }
                    let contents = try FileFormat.decodeProjects(from: data)
                    found.clients += contents.clients
                    found.projects += contents.projects
                    folded.append(copy)
                } catch {
                    result.issues.append(FileIssue(path: copy.lastPathComponent, problem: FileProblem(error)))
                }
            }
            for client in found.clients { result.ledger.merge(client) }
            for project in found.projects { result.ledger.merge(project) }

            let clients = result.ledger.clients.values.sorted(by: Client.fileOrder)
            let projects = result.ledger.projects.values.sorted(by: Project.fileOrder)
            if clients != onDisk.clients.sorted(by: Client.fileOrder)
                || projects != onDisk.projects.sorted(by: Project.fileOrder) {
                try access.write(FileFormat.encode(clients: clients, projects: projects), to: projectsFile)
            }
            for copy in folded {
                try access.remove(copy)
            }
        }
    }
}

/// What a data file holds, judging by its name, including iCloud's numbered
/// copies such as "2026-10 2.json".
public enum DataFileKind: Hashable, Sendable {
    case projects
    case month(MonthKey)

    public init?(fileName: String) {
        guard let name = DataFileName(fileName) else { return nil }
        if name.base == "projects" {
            self = .projects
        } else if let month = MonthKey(name.base) {
            self = .month(month)
        } else {
            return nil
        }
    }

    /// The file to save when a copy of this kind of file had changes.
    public var changes: Changes {
        switch self {
        case .projects: Changes(projects: true)
        case .month(let month): Changes(months: [month])
        }
    }
}

/// A data file's name split into its base and iCloud's copy number:
/// "2026-10 2.json" is "2026-10", copy 2.
struct DataFileName: Hashable {
    var base: String
    var copy: Int?

    init?(_ name: String) {
        guard name.hasSuffix(".json"), !name.hasPrefix(".") else { return nil }
        let stem = String(name.dropLast(".json".count))
        if let space = stem.lastIndex(of: " ") {
            let number = stem[stem.index(after: space)...]
            if !number.isEmpty, number.allSatisfy(\.isASCIIDigit), let copy = Int(number) {
                base = String(stem[..<space])
                self.copy = copy
                return
            }
        }
        base = stem
        copy = nil
    }
}

/// The data folder behind an actor, so file work stays off the main thread
/// and one save runs at a time.
public actor FileStore {
    nonisolated public let folder: Folder

    public init(folder: Folder) {
        self.folder = folder
    }

    public func load() throws -> LoadResult {
        try folder.load()
    }

    public func save(_ ledger: Ledger, changes: Changes) throws -> SaveResult {
        try folder.save(ledger, changes: changes)
    }
}
