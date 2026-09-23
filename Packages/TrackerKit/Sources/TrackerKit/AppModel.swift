import Foundation
import Observation
import TrackerCore

/// The app's data and actions, shared by the Mac and iOS apps.
///
/// The model keeps every record in memory. Edits change the ledger at once,
/// register undo, and schedule a save about a second later. Saving is a
/// read-merge-write of each changed file, so changes other devices made in
/// the meantime are kept.
@MainActor
@Observable
public final class AppModel {
    public enum State: Equatable, Sendable {
        /// Reading the data folder for the first time.
        case loading
        /// Waiting for iCloud's first list of files, before writing any.
        case waitingForICloud
        case ready
        /// iCloud is chosen, but this device isn't signed in. The data in
        /// memory stays visible, read-only.
        case iCloudUnavailable
    }

    /// Every record, including deleted ones.
    public private(set) var ledger = Ledger() {
        didSet { resolved = ledger.resolvedEntries() }
    }
    /// The entries that aren't deleted, sorted by start, with the two-timers
    /// rule applied.
    public private(set) var resolved: [ResolvedEntry] = []
    /// The current time, updated whenever a running timer's minutes change.
    public private(set) var now: Timestamp
    public private(set) var state: State = .loading
    public private(set) var storage: StorageKind
    /// Files that couldn't be read or saved.
    public private(set) var issues: [FileIssue] = []
    /// Files iCloud hasn't downloaded to this device yet.
    public private(set) var missingFiles = 0
    /// The last error while loading or saving, for a notice.
    public private(set) var lastError: String?

    /// The first day of the week in reports: 1 for Sunday through 7 for Saturday.
    public var firstWeekday: Int {
        didSet { environment.defaults.set(firstWeekday, forKey: Keys.firstWeekday) }
    }

    public let environment: AppEnvironment
    @ObservationIgnored private var store: FileStore
    @ObservationIgnored private var pending = Changes()
    @ObservationIgnored private var blocked = Changes()
    @ObservationIgnored private var isSaving = false
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var clockTask: Task<Void, Never>?
    @ObservationIgnored private var lastBackup: LocalDate?

    private enum Keys {
        static let storage = "storage"
        static let firstWeekday = "firstWeekday"
    }

    public init(environment: AppEnvironment) {
        self.environment = environment
        now = environment.now()
        let chosen = environment.defaults.string(forKey: Keys.storage).flatMap(StorageKind.init(rawValue:))
        storage = chosen ?? (environment.cloud?.isAvailable == true ? .iCloud : .local)
        firstWeekday = environment.defaults.object(forKey: Keys.firstWeekday) as? Int ?? Calendar.current.firstWeekday
        store = FileStore(folder: Folder(root: environment.localFolder))
        environment.cloud?.onAccountChange = { [weak self] in
            Task { await self?.accountChanged() }
        }
    }

    // MARK: - Derived data

    /// The running timer, if any.
    public var running: ResolvedEntry? {
        resolved.first { $0.isRunning }
    }

    /// Whether edits are possible. They aren't while iCloud is chosen but
    /// unavailable.
    public var isReadOnly: Bool {
        state == .iCloudUnavailable
    }

    /// The day `now` falls on in the Mac's or iPhone's current time zone.
    public var today: LocalDate {
        now.local(in: environment.timeZone()).date
    }

    /// Milliseconds an entry has run, up to now for a running one.
    public func duration(of entry: ResolvedEntry) -> Int64 {
        entry.duration(now: now)
    }

    /// Overlaps among all entries, as of now.
    public var overlaps: OverlapAnalysis {
        Overlaps.analyze(resolved, now: now)
    }

    // MARK: - Loading and saving

    /// Opens the chosen storage and starts the clock. Call once at launch.
    public func start() async {
        startClock()
        await open(storage)
    }

    /// Reads every file again and merges it in.
    public func reload() async {
        do {
            let loaded = try await store.load()
            ledger.merge(loaded.ledger)
            issues = loaded.issues
            pending.formUnion(loaded.pending)
            pending.formUnion(blocked)
            blocked = Changes()
            lastError = nil
        } catch {
            lastError = String(describing: error)
        }
        if canSave, !pending.isEmpty {
            scheduleSave()
        }
    }

    /// Saves everything pending right away, such as before quitting.
    public func flush() async {
        if let saveTask {
            saveTask.cancel()
            await saveTask.value
        }
        await saveNow()
    }

    /// Whether some changes aren't saved yet.
    public var hasUnsavedChanges: Bool {
        !pending.isEmpty || !blocked.isEmpty
    }

    private var canSave: Bool {
        state == .ready
    }

    private func open(_ kind: StorageKind) async {
        environment.cloud?.stopWatching()
        storage = kind
        switch kind {
        case .local:
            store = FileStore(folder: Folder(root: environment.localFolder))
            state = .loading
            await reload()
            state = .ready
            backUpIfDue()
            if !pending.isEmpty {
                scheduleSave()
            }
        case .iCloud:
            guard let cloud = environment.cloud, cloud.isAvailable, let documents = await cloud.documentsFolder() else {
                state = .iCloudUnavailable
                return
            }
            store = FileStore(folder: Folder(root: documents, access: cloud.fileAccess()))
            state = .waitingForICloud
            cloud.startWatching(folder: documents) { [weak self] snapshot in
                self?.cloudChanged(snapshot)
            }
        }
    }

    private func cloudChanged(_ snapshot: CloudSnapshot) {
        missingFiles = snapshot.missingFiles
        guard !snapshot.isGathering else { return }
        Task {
            for file in snapshot.conflictedFiles {
                await mergeConflicts(in: file)
            }
            await reload()
            if state == .waitingForICloud {
                state = .ready
                backUpIfDue()
                if !pending.isEmpty {
                    scheduleSave()
                }
            }
        }
    }

    /// Merges the other versions iCloud kept of a file, saves the result, and
    /// only then marks those versions resolved.
    private func mergeConflicts(in file: URL) async {
        guard let cloud = environment.cloud, let kind = DataFileKind(fileName: file.lastPathComponent) else { return }
        var versions = Ledger()
        for data in await cloud.conflictVersions(of: file) {
            switch kind {
            case .projects:
                guard let decoded = try? FileFormat.decodeProjects(from: data) else { continue }
                versions.merge(Ledger(clients: decoded.clients, projects: decoded.projects))
            case .month:
                guard let entries = try? FileFormat.decodeEntries(from: data) else { continue }
                versions.merge(Ledger(entries: entries))
            }
        }
        ledger.merge(versions)
        pending.formUnion(kind.changes)
        guard canSave else { return }
        await saveNow()
        if !blocked.months.contains(where: { kind.changes.months.contains($0) }), !(blocked.projects && kind == .projects) {
            await cloud.resolveConflicts(of: file)
        }
    }

    private func accountChanged() async {
        guard storage == .iCloud else { return }
        if environment.cloud?.isAvailable == true {
            if state == .iCloudUnavailable {
                await open(.iCloud)
            }
        } else {
            environment.cloud?.stopWatching()
            state = .iCloudUnavailable
        }
    }

    private func scheduleSave() {
        guard saveTask == nil else { return }
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self else { return }
            await self.saveNow()
            self.saveTask = nil
            if self.canSave, !self.pending.isEmpty {
                self.scheduleSave()
            }
        }
    }

    private func saveNow() async {
        guard canSave, !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        while !pending.isEmpty {
            let changes = pending
            pending = Changes()
            do {
                let result = try await store.save(ledger, changes: changes)
                ledger.merge(result.ledger)
                blocked.formUnion(result.pending)
                if !result.issues.isEmpty {
                    let known = Set(issues)
                    issues += result.issues.filter { !known.contains($0) }
                }
                lastError = nil
            } catch {
                pending.formUnion(changes)
                lastError = String(describing: error)
                return
            }
        }
    }

    // MARK: - Storage

    public enum StorageError: LocalizedError, Equatable {
        /// Some iCloud files aren't on this device yet, so a copy would miss them.
        case iCloudNotDownloaded
        case iCloudUnavailable

        public var errorDescription: String? {
            switch self {
            case .iCloudNotDownloaded:
                "Some of your data hasn't downloaded from iCloud yet. Try again once it has."
            case .iCloudUnavailable:
                "Sign in to iCloud and turn on iCloud Drive first."
            }
        }
    }

    /// Whether iCloud can be turned on.
    public var isICloudAvailable: Bool {
        environment.cloud?.isAvailable == true
    }

    /// Moves to other storage by copying: the data in memory is merged into
    /// the other folder, and the old one stays as it is. Turning iCloud off
    /// therefore leaves other devices syncing.
    public func switchStorage(to kind: StorageKind) async throws {
        guard kind != storage else { return }
        if kind == .iCloud, !isICloudAvailable {
            throw StorageError.iCloudUnavailable
        }
        if storage == .iCloud, state == .ready, missingFiles > 0 || issues.contains(where: { $0.problem == .notDownloaded }) {
            throw StorageError.iCloudNotDownloaded
        }
        await flush()
        let label = kind == .iCloud ? "before switching to iCloud" : "before switching to local storage"
        let backups = Backups(root: environment.backupsFolder)
        let snapshot = ledger
        let name = "\(today) \(label)"
        _ = try await Task.detached { try backups.write(snapshot, named: name) }.value
        environment.defaults.set(kind.rawValue, forKey: Keys.storage)
        pending.formUnion(.all(in: ledger))
        await open(kind)
    }

    /// The folder the data is in right now.
    public var dataFolder: URL {
        store.folder.root
    }

    /// Where backups go.
    public var backupsFolder: URL {
        environment.backupsFolder
    }

    // MARK: - Backups

    private func backUpIfDue() {
        let day = today
        guard lastBackup != day else { return }
        lastBackup = day
        let backups = Backups(root: environment.backupsFolder)
        let snapshot = ledger
        Task.detached(priority: .background) {
            try? backups.writeDaily(snapshot, on: day)
        }
    }

    // MARK: - Clock

    /// Updates the time now and restarts the clock, such as after the Mac wakes.
    public func refreshClock() {
        now = environment.now()
        startClock()
    }

    /// Ticks when the running timer's minutes change, or on the minute.
    private func startClock() {
        clockTask?.cancel()
        clockTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let delay = self?.millisecondsToNextTick() else { return }
                try? await Task.sleep(for: .milliseconds(delay))
                guard !Task.isCancelled, let self else { return }
                self.now = self.environment.now()
                self.backUpIfDue()
            }
        }
    }

    private func millisecondsToNextTick() -> Int64 {
        let current = environment.now()
        let anchor = running?.start ?? Timestamp(milliseconds: 0)
        let elapsed = anchor.distance(to: current)
        let intoMinute = (elapsed % 60000 + 60000) % 60000
        return 60000 - intoMinute + 50
    }

    // MARK: - Editing

    /// Runs an edit, schedules the save, and registers its undo.
    @discardableResult
    func edit(
        _ actionName: String,
        undoManager: UndoManager?,
        _ change: (inout Ledger, Timestamp) throws -> Changes
    ) rethrows -> Bool {
        guard !isReadOnly else { return false }
        let before = ledger
        let stamp = environment.now()
        now = stamp
        let changes = try change(&ledger, stamp)
        guard !changes.isEmpty else { return false }
        record(changes)
        registerUndo(ledger.snapshot(since: before), actionName: actionName, undoManager: undoManager)
        return true
    }

    private func record(_ changes: Changes) {
        pending.formUnion(changes)
        if canSave {
            scheduleSave()
        }
    }

    private func registerUndo(_ snapshot: Snapshot, actionName: String, undoManager: UndoManager?) {
        guard let undoManager, !snapshot.isEmpty else { return }
        undoManager.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated {
                model.undo(snapshot, actionName: actionName, undoManager: undoManager)
            }
        }
        undoManager.setActionName(actionName)
    }

    private func undo(_ snapshot: Snapshot, actionName: String, undoManager: UndoManager) {
        guard !isReadOnly else { return }
        let before = ledger
        let stamp = environment.now()
        now = stamp
        record(ledger.restore(snapshot, now: stamp))
        registerUndo(ledger.snapshot(since: before), actionName: actionName, undoManager: undoManager)
    }
}
