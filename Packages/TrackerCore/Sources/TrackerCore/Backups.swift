import Foundation

/// Full copies of the data, kept outside the synced folder.
///
/// Without them, a merge bug or a damaged file could reach every device
/// within seconds, and iCloud Drive keeps no history of plain files. Each
/// backup is a folder in the data format, named so that names sort by date,
/// such as `2026-09-23` or `2026-09-23 before switching to iCloud`. Only the
/// newest `keep` are kept.
public struct Backups: Sendable {
    public let root: URL
    public let keep: Int

    public init(root: URL, keep: Int = 30) {
        self.root = root
        self.keep = keep
    }

    /// The names of the backups, oldest first.
    public func names() throws -> [String] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: root.path) else { return [] }
        return try fileManager.contentsOfDirectory(atPath: root.path)
            .filter { !$0.hasPrefix(".") }
            .sorted()
    }

    /// Writes the day's backup unless there already is one, then removes the
    /// oldest backups beyond `keep`. Returns the folder written, if any.
    @discardableResult
    public func writeDaily(_ ledger: Ledger, on day: LocalDate) throws -> URL? {
        let name = day.description
        guard try !names().contains(where: { $0 == name || $0.hasPrefix(name + " ") }) else { return nil }
        return try write(ledger, named: name)
    }

    /// Writes a backup with the given name, replacing one with the same name,
    /// then removes the oldest backups beyond `keep`.
    @discardableResult
    public func write(_ ledger: Ledger, named name: String) throws -> URL {
        let folder = root.appendingPathComponent(name, isDirectory: true)
        if FileManager.default.fileExists(atPath: folder.path) {
            try FileManager.default.removeItem(at: folder)
        }
        _ = try Folder(root: folder).save(ledger, changes: .all(in: ledger))
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try prune()
        return folder
    }

    private func prune() throws {
        let all = try names()
        for name in all.dropLast(keep) {
            try FileManager.default.removeItem(at: root.appendingPathComponent(name, isDirectory: true))
        }
    }
}

extension Changes {
    /// Every file that holds a record of `ledger`.
    public static func all(in ledger: Ledger) -> Changes {
        Changes(months: Set(ledger.entries.values.map(\.month)), projects: true)
    }
}

/// Why data couldn't be copied to another folder.
public enum CopyError: Error, Hashable, Sendable {
    /// Some files in the source couldn't be read, so their records would be
    /// left behind.
    case incomplete([FileIssue])
}

extension Folder {
    /// Merges every record in `source` into this folder, by id, and leaves
    /// `source` untouched. Records already here are kept, so this works
    /// when both folders hold data, as when turning iCloud on for a second
    /// Mac.
    ///
    /// Throws `CopyError.incomplete` without writing anything if some file in
    /// `source` can't be read.
    public func merge(from source: Folder) throws -> SaveResult {
        let loaded = try source.load()
        guard loaded.issues.isEmpty else { throw CopyError.incomplete(loaded.issues) }
        return try save(loaded.ledger, changes: .all(in: loaded.ledger))
    }
}
