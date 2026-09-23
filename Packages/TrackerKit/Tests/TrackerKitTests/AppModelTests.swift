import Foundation
import Testing
import TrackerCore
@testable import TrackerKit

/// A clock the test moves by hand.
final class TestClock {
    var now: Timestamp

    init(_ text: String) {
        now = DateTimeFormat.parse(text)!
    }

    func advance(seconds: Int64) {
        now = now.adding(seconds: seconds)
    }
}

/// iCloud, played by a local folder.
@MainActor
final class FakeCloud: CloudProvider {
    var isAvailable = true
    var onAccountChange: (() -> Void)?
    let folder: URL
    private var onChange: ((CloudSnapshot) -> Void)?

    init(folder: URL) {
        self.folder = folder
    }

    func documentsFolder() async -> URL? { isAvailable ? folder : nil }
    func fileAccess() -> any FileAccess { LocalFileAccess() }
    func startWatching(folder: URL, onChange: @escaping (CloudSnapshot) -> Void) { self.onChange = onChange }
    func stopWatching() { onChange = nil }
    func conflictVersions(of file: URL) async -> [Data] { [] }
    func resolveConflicts(of file: URL) async {}

    var isWatching: Bool { onChange != nil }

    /// Reports that iCloud has listed the folder.
    func finishGathering() {
        onChange?(CloudSnapshot(isGathering: false))
    }

    func signOut() {
        isAvailable = false
        onAccountChange?()
    }
}

/// Temporary folders and settings for one test.
@MainActor
struct Harness {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("TrackerKitTests-\(UUID().uuidString)")
    let clock = TestClock("2026-09-23T09:00:00+02:00")
    let defaults = UserDefaults(suiteName: "TrackerKitTests-\(UUID().uuidString)")!

    var localFolder: URL { root.appendingPathComponent("Data") }
    var cloudFolder: URL { root.appendingPathComponent("iCloud") }
    var backupsFolder: URL { root.appendingPathComponent("Backups") }

    func model(cloud: FakeCloud? = nil) -> AppModel {
        let clock = clock
        return AppModel(environment: AppEnvironment(
            localFolder: localFolder,
            backupsFolder: backupsFolder,
            defaults: defaults,
            now: { clock.now },
            timeZone: { "Europe/Berlin" },
            cloud: cloud
        ))
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: root)
    }
}

/// Waits for work the model does in tasks of its own.
@MainActor
func eventually(_ condition: () -> Bool) async {
    for _ in 0..<200 where !condition() {
        try? await Task.sleep(for: .milliseconds(10))
    }
}

func entry(_ id: UUID = UUID(), note: String, at time: String) -> TimeEntry {
    let start = DateTimeFormat.parse(time)!
    return TimeEntry(id: id, start: start, end: start.adding(seconds: 3600), timeZone: "Europe/Berlin", note: note, updated: start)
}

@Suite @MainActor struct AppModelTests {
    @Test func loadsTheLocalFolder() async throws {
        let harness = Harness()
        defer { harness.cleanUp() }
        let existing = Ledger(entries: [entry(note: "Earlier", at: "2026-09-22T09:00:00+02:00")])
        _ = try Folder(root: harness.localFolder).save(existing, changes: .all(in: existing))

        let model = harness.model()
        #expect(model.storage == .local)
        await model.start()
        #expect(model.state == .ready)
        #expect(model.ledger == existing)
        #expect(model.resolved.map(\.entry.note) == ["Earlier"])
    }

    @Test func savesEdits() async throws {
        let harness = Harness()
        defer { harness.cleanUp() }
        let model = harness.model()
        await model.start()

        model.startTimer(note: "Wireframes", undoManager: nil)
        #expect(model.running?.entry.note == "Wireframes")
        #expect(model.hasUnsavedChanges)
        await model.flush()
        #expect(!model.hasUnsavedChanges)

        let saved = try Folder(root: harness.localFolder).load().ledger
        #expect(saved == model.ledger)
    }

    @Test func undoesAndRedoes() async throws {
        let harness = Harness()
        defer { harness.cleanUp() }
        let model = harness.model()
        await model.start()
        let undo = UndoManager()
        undo.groupsByEvent = false

        undo.beginUndoGrouping()
        model.startTimer(note: "First", undoManager: undo)
        undo.endUndoGrouping()
        harness.clock.advance(seconds: 600)
        undo.beginUndoGrouping()
        model.startTimer(note: "Second", undoManager: undo)
        undo.endUndoGrouping()
        #expect(undo.undoActionName == "Start Timer")

        undo.undo()
        #expect(model.running?.entry.note == "First")
        undo.redo()
        #expect(model.running?.entry.note == "Second")
    }

    @Test func splitsAnEntryAndUndoesTheSplit() async throws {
        let harness = Harness()
        defer { harness.cleanUp() }
        let model = harness.model()
        await model.start()
        let undo = UndoManager()
        undo.groupsByEvent = false

        let workshop = entry(note: "Workshop", at: "2026-09-22T09:00:00+02:00")
        model.addEntry(workshop, undoManager: nil)
        undo.beginUndoGrouping()
        model.splitEntry(workshop.id, at: DateTimeFormat.parse("2026-09-22T09:20:00+02:00")!, undoManager: undo)
        undo.endUndoGrouping()
        #expect(undo.undoActionName == "Split Entry")
        #expect(model.resolved.map(\.entry.note) == ["Workshop", "Workshop"])
        let minute: Int64 = 60000
        #expect(model.resolved.map { $0.duration(now: model.now) } == [20 * minute, 40 * minute])

        undo.undo()
        #expect(model.resolved.map(\.id) == [workshop.id])
        #expect(model.resolved.first?.end == workshop.end)
    }

    @Test func firstLaunchWaitsForICloudBeforeWriting() async throws {
        let harness = Harness()
        defer { harness.cleanUp() }
        let cloud = FakeCloud(folder: harness.cloudFolder)
        let fromOtherMac = Ledger(entries: [entry(note: "From the other Mac", at: "2026-09-22T09:00:00+02:00")])
        _ = try Folder(root: harness.cloudFolder).save(fromOtherMac, changes: .all(in: fromOtherMac))

        let model = harness.model(cloud: cloud)
        #expect(model.storage == .iCloud)
        await model.start()
        #expect(model.state == .waitingForICloud)

        model.startTimer(note: "New", undoManager: nil)
        await model.flush()
        #expect(model.hasUnsavedChanges)

        cloud.finishGathering()
        await eventually { model.state == .ready }
        await model.flush()
        let saved = try Folder(root: harness.cloudFolder).load().ledger
        #expect(Set(saved.entries.values.map(\.note)) == ["From the other Mac", "New"])
    }

    @Test func turningICloudOnMergesAndKeepsTheLocalFolder() async throws {
        let harness = Harness()
        defer { harness.cleanUp() }
        harness.defaults.set("local", forKey: "storage")
        let local = Ledger(entries: [entry(note: "Local", at: "2026-09-22T09:00:00+02:00")])
        let remote = Ledger(entries: [entry(note: "Remote", at: "2026-09-21T09:00:00+02:00")])
        _ = try Folder(root: harness.localFolder).save(local, changes: .all(in: local))
        _ = try Folder(root: harness.cloudFolder).save(remote, changes: .all(in: remote))
        let cloud = FakeCloud(folder: harness.cloudFolder)

        let model = harness.model(cloud: cloud)
        await model.start()
        #expect(model.storage == .local)
        try await model.switchStorage(to: .iCloud)
        #expect(model.storage == .iCloud)
        cloud.finishGathering()
        await eventually { model.state == .ready }
        await model.flush()

        let merged = try Folder(root: harness.cloudFolder).load().ledger
        #expect(Set(merged.entries.values.map(\.note)) == ["Local", "Remote"])
        #expect(try Folder(root: harness.localFolder).load().ledger == local)
        #expect(try Backups(root: harness.backupsFolder).names().contains { $0.hasSuffix("before switching to iCloud") })
    }

    @Test func signingOutMakesTheDataReadOnlyUntilItsCopied() async throws {
        let harness = Harness()
        defer { harness.cleanUp() }
        let cloud = FakeCloud(folder: harness.cloudFolder)
        let model = harness.model(cloud: cloud)
        await model.start()
        cloud.finishGathering()
        await eventually { model.state == .ready }
        model.startTimer(note: "Before sign-out", undoManager: nil)
        await model.flush()

        cloud.signOut()
        await eventually { model.state == .iCloudUnavailable }
        #expect(model.isReadOnly)
        model.stopTimer(undoManager: nil)
        #expect(model.running != nil)

        try await model.switchStorage(to: .local)
        #expect(model.state == .ready)
        await model.flush()
        let copied = try Folder(root: harness.localFolder).load().ledger
        #expect(copied.entries.values.map(\.note) == ["Before sign-out"])
    }

    @Test func picksUpChangesFromOtherDevices() async throws {
        let harness = Harness()
        defer { harness.cleanUp() }
        let cloud = FakeCloud(folder: harness.cloudFolder)
        let model = harness.model(cloud: cloud)
        await model.start()
        cloud.finishGathering()
        await eventually { model.state == .ready }

        let other = Ledger(entries: [entry(note: "Logged on the iPhone", at: "2026-09-23T07:00:00+02:00")])
        _ = try Folder(root: harness.cloudFolder).save(other, changes: .all(in: other))
        cloud.finishGathering()
        await eventually { !model.resolved.isEmpty }
        #expect(model.resolved.map(\.entry.note) == ["Logged on the iPhone"])
    }
}
