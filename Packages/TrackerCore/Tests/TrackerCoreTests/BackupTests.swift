import Foundation
import Testing
@testable import TrackerCore

@Suite struct BackupTests {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("TrackerCoreBackups-\(UUID().uuidString)")
    let now = t("2026-09-23T12:00:00+02:00")

    var ledger: Ledger {
        Ledger(
            projects: [Project(id: uuid(10), name: "Website", updated: now)],
            entries: [
                TimeEntry(
                    id: uuid(1),
                    projectID: uuid(10),
                    start: t("2026-09-23T09:00:00+02:00"),
                    end: t("2026-09-23T10:00:00+02:00"),
                    timeZone: "Europe/Berlin",
                    note: "Wireframes",
                    updated: now
                ),
            ]
        )
    }

    @Test func writesOneBackupADay() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let backups = Backups(root: directory)
        let day = LocalDate(year: 2026, month: 9, day: 23)

        let written = try #require(try backups.writeDaily(ledger, on: day))
        #expect(written.lastPathComponent == "2026-09-23")
        #expect(try backups.writeDaily(ledger, on: day) == nil)
        #expect(try Folder(root: written).load().ledger == ledger)
    }

    @Test func keepsOnlyTheNewest() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let backups = Backups(root: directory, keep: 3)
        for day in 20...24 {
            try backups.writeDaily(ledger, on: LocalDate(year: 2026, month: 9, day: day))
        }
        try backups.write(ledger, named: "2026-09-24 before switching to iCloud")
        #expect(try backups.names() == ["2026-09-23", "2026-09-24", "2026-09-24 before switching to iCloud"])
    }

    @Test func writesEmptyBackups() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let folder = try Backups(root: directory).write(Ledger(), named: "empty")
        #expect(FileManager.default.fileExists(atPath: folder.path))
        #expect(try Folder(root: folder).load().ledger == Ledger())
    }
}

@Suite struct FolderMergeTests {
    let now = t("2026-09-23T12:00:00+02:00")

    func entry(_ number: Int, on day: String) -> TimeEntry {
        TimeEntry(
            id: uuid(number),
            start: t("\(day)T09:00:00+02:00"),
            end: t("\(day)T10:00:00+02:00"),
            timeZone: "Europe/Berlin",
            updated: now
        )
    }

    @Test func mergesIntoAFolderThatAlreadyHasData() throws {
        let files = MemoryFiles()
        let local = Folder(root: URL(fileURLWithPath: "/local"), access: files)
        let cloud = Folder(root: URL(fileURLWithPath: "/cloud"), access: files)
        _ = try local.save(Ledger(entries: [entry(1, on: "2026-09-21"), entry(2, on: "2026-08-01")]), changes: Changes(months: [MonthKey(year: 2026, month: 9), MonthKey(year: 2026, month: 8)]))
        _ = try cloud.save(Ledger(entries: [entry(3, on: "2026-09-22")]), changes: Changes(months: [MonthKey(year: 2026, month: 9)]))
        let localFiles = files.snapshot().filter { $0.key.hasPrefix("/local/") }

        _ = try cloud.merge(from: local)

        #expect(Set(try cloud.load().ledger.entries.keys) == [uuid(1), uuid(2), uuid(3)])
        #expect(files.snapshot().filter { $0.key.hasPrefix("/local/") } == localFiles)
    }

    @Test func refusesToLeaveRecordsBehind() throws {
        let files = MemoryFiles()
        let local = Folder(root: URL(fileURLWithPath: "/local"), access: files)
        let cloud = Folder(root: URL(fileURLWithPath: "/cloud"), access: files)
        files.put("/local/entries/2026-09.json", Data("not json".utf8))
        do {
            _ = try cloud.merge(from: local)
            Issue.record("Expected the merge to refuse")
        } catch CopyError.incomplete(let issues) {
            #expect(issues.map(\.path) == ["entries/2026-09.json"])
        }
        #expect(files.paths() == ["/local/entries/2026-09.json"])
    }
}

@Suite struct NotDownloadedTests {
    @Test func aFileNotDownloadedYetIsReportedAndNeverWritten() throws {
        let files = MemoryFiles()
        let folder = Folder(root: URL(fileURLWithPath: "/data"), access: files)
        let now = t("2026-09-23T12:00:00+02:00")
        var ledger = Ledger()
        let first = ledger.addEntry(
            TimeEntry(id: uuid(1), start: t("2026-09-23T09:00:00+02:00"), end: now, timeZone: "Europe/Berlin", updated: now),
            now: now
        )
        _ = try folder.save(ledger, changes: first)
        let saved = try #require(files.contents("/data/entries/2026-09.json"))

        files.notDownloaded = ["/data/entries/2026-09.json"]
        let loaded = try folder.load()
        #expect(loaded.issues == [FileIssue(path: "entries/2026-09.json", problem: .notDownloaded)])

        let second = ledger.addEntry(
            TimeEntry(id: uuid(2), start: t("2026-09-23T10:00:00+02:00"), end: now, timeZone: "Europe/Berlin", updated: now),
            now: now
        )
        let result = try folder.save(ledger, changes: second)
        #expect(result.pending == second)
        #expect(files.contents("/data/entries/2026-09.json") == saved)
    }
}
