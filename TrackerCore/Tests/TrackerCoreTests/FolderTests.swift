import Foundation
import Testing
@testable import TrackerCore

@Suite struct FolderTests {
    let files = MemoryFiles()
    let root = URL(fileURLWithPath: "/data")
    let september = MonthKey(year: 2026, month: 9)
    let october = MonthKey(year: 2026, month: 10)

    var folder: Folder {
        Folder(root: root, access: files)
    }

    /// An hour of work on a day in Berlin, such as "2026-09-23".
    func entry(_ number: Int, on day: String, note: String = "") -> TimeEntry {
        TimeEntry(
            id: uuid(number),
            start: t("\(day)T09:00:00+02:00"),
            end: t("\(day)T10:00:00+02:00"),
            timeZone: "Europe/Berlin",
            note: note,
            updated: t("\(day)T10:00:00+02:00")
        )
    }

    let now = t("2026-10-05T12:00:00+02:00")

    @Test func savesAndLoads() throws {
        var ledger = Ledger()
        var changes = ledger.addClient(Client(id: uuid(20), name: "Acme", updated: now), now: now)
        changes.formUnion(ledger.addProject(Project(id: uuid(10), clientID: uuid(20), name: "Website", updated: now), now: now))
        changes.formUnion(ledger.addEntry(entry(1, on: "2026-09-23"), now: now))
        changes.formUnion(ledger.addEntry(entry(2, on: "2026-10-01"), now: now))

        let saved = try folder.save(ledger, changes: changes)
        #expect(saved.issues.isEmpty)
        #expect(saved.pending.isEmpty)
        #expect(saved.ledger == ledger)
        #expect(files.paths() == ["/data/entries/2026-09.json", "/data/entries/2026-10.json", "/data/projects.json"])

        let loaded = try folder.load()
        #expect(loaded.ledger == ledger)
        #expect(loaded.issues.isEmpty)
        #expect(loaded.pending.isEmpty)
    }

    @Test func aSaveKeepsWhatAnotherDeviceWrote() throws {
        // Both Macs start from the same data.
        var macA = Ledger()
        let first = macA.addEntry(entry(1, on: "2026-09-21"), now: now)
        macA = try folder.save(macA, changes: first).ledger
        var macB = try folder.load().ledger

        // Mac B logs an entry and saves.
        let fromB = macB.addEntry(entry(2, on: "2026-09-22"), now: now)
        _ = try folder.save(macB, changes: fromB)

        // Mac A hasn't loaded Mac B's entry, logs one in the same month, and saves.
        let fromA = macA.addEntry(entry(3, on: "2026-09-23"), now: now)
        let result = try folder.save(macA, changes: fromA)

        #expect(Set(result.ledger.entries.keys) == [uuid(1), uuid(2), uuid(3)])
        #expect(Set(try folder.load().ledger.entries.keys) == [uuid(1), uuid(2), uuid(3)])
    }

    @Test func foldsNumberedCopiesIntoTheMainFiles() throws {
        let project = Project(id: uuid(10), name: "Website", updated: now)
        files.put("/data/entries/2026-10.json", FileFormat.encode(entries: [entry(1, on: "2026-10-01")]))
        files.put("/data/entries/2026-10 2.json", FileFormat.encode(entries: [entry(2, on: "2026-10-01")]))
        files.put("/data/projects 2.json", FileFormat.encode(clients: [], projects: [project]))

        let loaded = try folder.load()
        #expect(Set(loaded.ledger.entries.keys) == [uuid(1), uuid(2)])
        #expect(loaded.ledger.projects[uuid(10)] == project)
        #expect(loaded.pending == Changes(months: [october], projects: true))

        _ = try folder.save(loaded.ledger, changes: loaded.pending)
        #expect(files.paths() == ["/data/entries/2026-10.json", "/data/projects.json"])
        let reloaded = try folder.load()
        #expect(reloaded.ledger == loaded.ledger)
        #expect(reloaded.pending.isEmpty)
    }

    @Test func neverOverwritesAnUnreadableFile() throws {
        let broken = Data("{ \"version\": 1, \"entries\": [ oops".utf8)
        files.put("/data/entries/2026-09.json", broken)
        files.put("/data/entries/2026-09 2.json", FileFormat.encode(entries: [entry(2, on: "2026-09-02")]))

        let loaded = try folder.load()
        #expect(loaded.issues.map(\.path) == ["entries/2026-09.json"])

        var ledger = loaded.ledger
        let changes = ledger.addEntry(entry(1, on: "2026-09-23"), now: now)
        let result = try folder.save(ledger, changes: changes)
        #expect(files.contents("/data/entries/2026-09.json") == broken)
        #expect(files.contents("/data/entries/2026-09 2.json") != nil)
        #expect(result.issues.map(\.path) == ["entries/2026-09.json"])
        #expect(result.pending == Changes(months: [september]))
    }

    @Test func neverOverwritesAFileFromANewerVersion() throws {
        let newer = Data(#"{"version": 2, "entries": [], "shifts": []}"#.utf8)
        files.put("/data/entries/2026-09.json", newer)
        files.put("/data/projects.json", newer)

        let loaded = try folder.load()
        #expect(Set(loaded.issues.map(\.problem)) == [.newerVersion(2)])

        var ledger = loaded.ledger
        var changes = ledger.addEntry(entry(1, on: "2026-09-23"), now: now)
        changes.formUnion(ledger.addClient(Client(name: "Acme", updated: now), now: now))
        let result = try folder.save(ledger, changes: changes)
        #expect(files.contents("/data/entries/2026-09.json") == newer)
        #expect(files.contents("/data/projects.json") == newer)
        #expect(result.pending == changes)
    }

    @Test func movingAnEntryLeavesOneCopy() throws {
        var ledger = Ledger()
        let added = ledger.addEntry(entry(1, on: "2026-09-30"), now: now)
        ledger = try folder.save(ledger, changes: added).ledger

        let moved = ledger.updateEntry(uuid(1), now: now.adding(seconds: 1)) { entry in
            entry.start = entry.start.adding(seconds: 86400)
            entry.end = entry.end?.adding(seconds: 86400)
        }
        #expect(moved.months == [september, october])
        ledger = try folder.save(ledger, changes: moved).ledger

        let septemberEntries = try FileFormat.decodeEntries(from: files.contents("/data/entries/2026-09.json")!)
        let octoberEntries = try FileFormat.decodeEntries(from: files.contents("/data/entries/2026-10.json")!)
        #expect(septemberEntries.isEmpty)
        #expect(octoberEntries.map(\.id) == [uuid(1)])
        #expect(try folder.load().pending.isEmpty)
    }

    @Test(arguments: 0...2)
    func aCrashWhileMovingLosesNothing(writesBeforeCrash: Int) throws {
        var ledger = Ledger()
        let added = ledger.addEntry(entry(1, on: "2026-09-30", note: "before"), now: now)
        ledger = try folder.save(ledger, changes: added).ledger

        let moved = ledger.updateEntry(uuid(1), now: now.adding(seconds: 1)) { entry in
            entry.start = entry.start.adding(seconds: 86400)
            entry.end = entry.end?.adding(seconds: 86400)
            entry.note = "after"
        }
        files.writeBudget = writesBeforeCrash
        do {
            _ = try folder.save(ledger, changes: moved)
        } catch is MemoryFiles.Crash {
            // Expected unless the budget covered every write.
        }
        files.writeBudget = nil

        let loaded = try folder.load()
        let found = try #require(loaded.ledger.entries[uuid(1)])
        #expect(found.note == "before" || found.note == "after")

        // Saving what loading asks for finishes the move.
        let finished = try folder.save(ledger.merging(loaded.ledger), changes: moved.union(loaded.pending))
        #expect(finished.ledger.entries[uuid(1)]?.note == "after")
        let reloaded = try folder.load()
        #expect(reloaded.pending.isEmpty)
        #expect(reloaded.ledger.entries[uuid(1)]?.month == october)
    }

    @Test func skipsWritesWhenNothingChanged() throws {
        var ledger = Ledger()
        var changes = ledger.addEntry(entry(1, on: "2026-09-23"), now: now)
        changes.formUnion(ledger.addClient(Client(name: "Acme", updated: now), now: now))
        ledger = try folder.save(ledger, changes: changes).ledger
        let writes = files.writes

        _ = try folder.save(ledger, changes: changes.union(Changes(months: [october])))
        #expect(files.writes == writes)
        #expect(!files.paths().contains("/data/entries/2026-10.json"))
    }

    @Test func movesAnEntryFiledInTheWrongMonth() throws {
        files.put("/data/entries/2026-09.json", FileFormat.encode(entries: [entry(1, on: "2026-10-02")]))
        let loaded = try folder.load()
        #expect(loaded.pending == Changes(months: [september, october]))

        _ = try folder.save(loaded.ledger, changes: loaded.pending)
        #expect(try FileFormat.decodeEntries(from: files.contents("/data/entries/2026-09.json")!).isEmpty)
        #expect(try FileFormat.decodeEntries(from: files.contents("/data/entries/2026-10.json")!).map(\.id) == [uuid(1)])
    }

    @Test func ignoresOtherFiles() throws {
        files.put("/data/entries/notes.txt", Data("hello".utf8))
        files.put("/data/entries/.2026-09.json.icloud", Data())
        files.put("/data/entries/2026-09 copy.json", Data("[]".utf8))
        files.put("/data/other.json", Data("[]".utf8))
        let loaded = try folder.load()
        #expect(loaded.issues.isEmpty)
        #expect(loaded.ledger == Ledger())
    }

    @Test func worksOnDisk() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("TrackerCoreTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let folder = Folder(root: directory)

        var ledger = Ledger()
        var changes = ledger.addEntry(entry(1, on: "2026-09-23", note: "Grüße, \"quoted\"\nsecond line"), now: now)
        changes.formUnion(ledger.addProject(Project(name: "Website", updated: now), now: now))
        _ = try folder.save(ledger, changes: changes)

        // Another device's numbered copy turns up.
        try FileFormat.encode(entries: [entry(2, on: "2026-09-24")])
            .write(to: directory.appendingPathComponent("entries/2026-09 2.json"))

        let loaded = try folder.load()
        #expect(Set(loaded.ledger.entries.keys) == [uuid(1), uuid(2)])
        #expect(loaded.ledger.entries[uuid(1)]?.note == "Grüße, \"quoted\"\nsecond line")
        _ = try folder.save(loaded.ledger, changes: loaded.pending)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.appendingPathComponent("entries").path) == ["2026-09.json"])

        let store = FileStore(folder: folder)
        let reloaded = try await store.load()
        #expect(reloaded.ledger == loaded.ledger)
    }
}
