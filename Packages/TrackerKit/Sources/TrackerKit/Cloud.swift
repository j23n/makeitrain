import Foundation
import TrackerCore

/// What the app model sees of the iCloud folder at one moment.
public struct CloudSnapshot: Equatable {
    /// True until iCloud has listed the folder for the first time.
    public var isGathering: Bool
    /// Files iCloud hasn't downloaded to this device yet.
    public var missingFiles: Int
    /// Files with versions from several devices that still need merging.
    public var conflictedFiles: [URL]

    public init(isGathering: Bool, missingFiles: Int = 0, conflictedFiles: [URL] = []) {
        self.isGathering = isGathering
        self.missingFiles = missingFiles
        self.conflictedFiles = conflictedFiles
    }
}

/// iCloud Drive as the app model uses it. `ICloudProvider` is the real one;
/// tests use a stand-in.
@MainActor
public protocol CloudProvider: AnyObject {
    /// Whether this device is signed in to iCloud with iCloud Drive on.
    var isAvailable: Bool { get }
    /// Called when the device signs in to or out of iCloud.
    var onAccountChange: (() -> Void)? { get set }
    /// The app's folder in iCloud Drive, or nil if iCloud isn't available.
    func documentsFolder() async -> URL?
    /// File access that coordinates with iCloud.
    func fileAccess() -> any FileAccess
    /// Starts reporting changes to the folder, downloading files as needed.
    func startWatching(folder: URL, onChange: @escaping (CloudSnapshot) -> Void)
    func stopWatching()
    /// The contents of the other versions iCloud kept of a file.
    func conflictVersions(of file: URL) async -> [Data]
    /// Marks those versions merged and removes them.
    func resolveConflicts(of file: URL) async
}

/// iCloud Drive, through the app's ubiquity container.
@MainActor
public final class ICloudProvider: CloudProvider {
    public let containerIdentifier: String
    public var onAccountChange: (() -> Void)?

    private var query: NSMetadataQuery?
    private var queryObservers: [NSObjectProtocol] = []
    private var accountObserver: NSObjectProtocol?

    public init(containerIdentifier: String) {
        self.containerIdentifier = containerIdentifier
        accountObserver = NotificationCenter.default.addObserver(
            forName: .NSUbiquityIdentityDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.onAccountChange?()
            }
        }
    }

    public var isAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    public func documentsFolder() async -> URL? {
        let identifier = containerIdentifier
        // Apple asks not to look up the container on the main thread: the
        // first lookup can take a while.
        return await Task.detached {
            guard let container = FileManager.default.url(forUbiquityContainerIdentifier: identifier) else {
                return nil
            }
            let documents = container.appendingPathComponent("Documents", isDirectory: true)
            try? FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
            return documents
        }.value
    }

    public func fileAccess() -> any FileAccess {
        CoordinatedFileAccess()
    }

    public func startWatching(folder: URL, onChange: @escaping (CloudSnapshot) -> Void) {
        stopWatching()
        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        query.predicate = NSPredicate(format: "%K LIKE '*.json'", NSMetadataItemFSNameKey)
        let handler: (Notification) -> Void = { [weak self, weak query] _ in
            MainActor.assumeIsolated {
                guard let self, let query else { return }
                onChange(self.snapshot(of: query))
            }
        }
        queryObservers = [
            NotificationCenter.default.addObserver(
                forName: .NSMetadataQueryDidFinishGathering, object: query, queue: .main, using: handler
            ),
            NotificationCenter.default.addObserver(
                forName: .NSMetadataQueryDidUpdate, object: query, queue: .main, using: handler
            ),
        ]
        self.query = query
        query.start()
    }

    public func stopWatching() {
        query?.stop()
        query = nil
        for observer in queryObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        queryObservers = []
    }

    public func conflictVersions(of file: URL) async -> [Data] {
        await Task.detached {
            let versions = NSFileVersion.unresolvedConflictVersionsOfItem(at: file) ?? []
            return versions.compactMap { try? Data(contentsOf: $0.url) }
        }.value
    }

    public func resolveConflicts(of file: URL) async {
        await Task.detached {
            var error: NSError?
            NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: file, options: [], error: &error) { url in
                for version in NSFileVersion.unresolvedConflictVersionsOfItem(at: url) ?? [] {
                    version.isResolved = true
                }
                try? NSFileVersion.removeOtherVersionsOfItem(at: url)
            }
        }.value
    }

    /// Reads the query's results, asking iCloud to download what's missing.
    private func snapshot(of query: NSMetadataQuery) -> CloudSnapshot {
        query.disableUpdates()
        defer { query.enableUpdates() }
        var missing = 0
        var conflicted: [URL] = []
        for case let item as NSMetadataItem in query.results {
            guard let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL else { continue }
            let status = item.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String
            if status != NSMetadataUbiquitousItemDownloadingStatusCurrent {
                missing += 1
                try? FileManager.default.startDownloadingUbiquitousItem(at: url)
            }
            if item.value(forAttribute: NSMetadataUbiquitousItemHasUnresolvedConflictsKey) as? Bool == true {
                conflicted.append(url)
            }
        }
        return CloudSnapshot(isGathering: query.isGathering, missingFiles: missing, conflictedFiles: conflicted)
    }
}

/// File access for iCloud: every read and write goes through
/// `NSFileCoordinator`, and a file that isn't downloaded yet counts as
/// `FileProblem.notDownloaded` instead of missing, so it's never overwritten.
public struct CoordinatedFileAccess: FileAccess {
    public init() {}

    public func fileNames(in folder: URL) throws -> [String] {
        guard FileManager.default.fileExists(atPath: folder.path) else { return [] }
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        // Some systems show a file iCloud hasn't downloaded as a hidden
        // ".name.icloud" placeholder.
        return Array(Set(names.map { name in
            name.hasPrefix(".") && name.hasSuffix(".icloud") ? String(name.dropFirst().dropLast(".icloud".count)) : name
        }))
    }

    public func read(_ file: URL) throws -> Data? {
        try checkDownloaded(file)
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
        // Fail fast rather than wait for a download inside the coordination.
        try checkDownloaded(file)
        return try coordinate(reading: true, files: [file], body)
    }

    public func coordinateWriting<T>(_ files: [URL], _ body: () throws -> T) throws -> T {
        try coordinate(reading: false, files: files, body)
    }

    private func checkDownloaded(_ file: URL) throws {
        let manager = FileManager.default
        let placeholder = file.deletingLastPathComponent().appendingPathComponent("." + file.lastPathComponent + ".icloud")
        var downloaded = !manager.fileExists(atPath: placeholder.path)
        if downloaded, manager.fileExists(atPath: file.path),
           let status = try? file.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]).ubiquitousItemDownloadingStatus {
            downloaded = status == .current
        }
        if !downloaded {
            try? manager.startDownloadingUbiquitousItem(at: file)
            throw FileProblem.notDownloaded
        }
    }

    /// Runs `body` inside coordinated access to every file, nesting one
    /// coordination per file on the same coordinator.
    private func coordinate<T>(reading: Bool, files: [URL], _ body: () throws -> T) throws -> T {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var result: Result<T, Error>?
        var coordinationError: NSError?
        func step(_ index: Int) {
            guard index < files.count else {
                result = Result { try body() }
                return
            }
            if reading {
                coordinator.coordinate(readingItemAt: files[index], options: [], error: &coordinationError) { _ in
                    step(index + 1)
                }
            } else {
                coordinator.coordinate(writingItemAt: files[index], options: .forMerging, error: &coordinationError) { _ in
                    step(index + 1)
                }
            }
        }
        step(0)
        if let result {
            return try result.get()
        }
        throw coordinationError ?? CocoaError(.fileReadUnknown)
    }
}
