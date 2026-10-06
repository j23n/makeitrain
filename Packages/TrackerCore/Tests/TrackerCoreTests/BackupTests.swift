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
