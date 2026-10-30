import Foundation
import Testing
@testable import TrackerCore

@Suite struct RecallTests {
    typealias F = CommandFixture

    @Test func recallsForAProjectTagsOrANoteOnly() {
        #expect(F.read("book").recallsEntries)
        #expect(F.read("book #227 Export").recallsEntries)
        #expect(F.read("planning").recallsEntries)
        // Times and commands say what to do already.
        #expect(!F.read("book from 10:05").recallsEntries)
        #expect(!F.read("book 9-10").recallsEntries)
        #expect(!F.read("book -15m").recallsEntries)
        #expect(!F.read("stop").recallsEntries)
        #expect(!F.read("find export").recallsEntries)
        #expect(!F.read("new project Website").recallsEntries)
        #expect(!F.read("   ").recallsEntries)
    }

    @Test func findsEntriesByProjectClientTagsAndNote() {
        let ledger = F.ledger()
        let resolved = ledger.resolvedEntries()
        func recall(_ query: String) -> [UUID] {
            ledger.recall(query, in: resolved, running: nil).map(\.id)
        }
        // The latest first.
        #expect(recall("book") == [uuid(101), uuid(104)])
        #expect(recall("north") == [uuid(101), uuid(104)])
        #expect(recall("227") == [uuid(101)])
        #expect(recall("export") == [uuid(101)])
        #expect(recall("BOOK pdf") == [uuid(101)])
        #expect(recall("plan") == [uuid(105)])
        #expect(recall("nothing like it").isEmpty)
        #expect(ledger.recall("book", in: resolved, running: nil, limit: 1).map(\.id) == [uuid(101)])
    }

    @Test func listsEachProjectTagsAndNoteOnce() {
        let earlier = F.entry(107, F.bookings, "2026-10-01", "09:00", "11:00", tags: ["#227"], note: "Export to PDF")
        let ledger = F.ledger([earlier])
        #expect(ledger.recall("book", in: ledger.resolvedEntries(), running: nil).map(\.id) == [uuid(101), uuid(104)])
    }

    @Test func leavesOutTheRunningTimersEntry() {
        let ledger = F.ledger([F.runningBookings])
        let resolved = ledger.resolvedEntries()
        let running = resolved.first { $0.isRunning }
        #expect(running?.id == uuid(103))
        // 103 runs, and 101 is the same project, tags and note.
        #expect(ledger.recall("book", in: resolved, running: running).map(\.id) == [uuid(104)])
    }

    @Test func leavesOutArchivedProjects() {
        let old = F.entry(108, F.admin, "2026-10-01", "09:00", "10:00", note: "Invoices")
        let ledger = F.ledger([old])
        #expect(ledger.recall("invoices", in: ledger.resolvedEntries(), running: nil).isEmpty)
    }

    @Test func writesAnEntryAsALineThatStartsItAgain() throws {
        let ledger = F.ledger([
            // Would read as Bookings, with the note "copy".
            F.entry(108, nil, "2026-10-01", "09:00", "10:00", note: "Bookings copy"),
            // Would take 101's note.
            F.entry(109, F.bookings, "2026-10-01", "10:00", "11:00", tags: ["#227"]),
        ])
        let context = F.context(ledger)
        for id in [uuid(101), uuid(104), uuid(105)] {
            let entry = try #require(ledger.entries[id])
            let line = try #require(context.startLine(for: entry))
            #expect(F.read(line, ledger).draft?.matches(entry) == true, "\(line)")
        }
        let export = try #require(ledger.entries[uuid(101)])
        #expect(context.startLine(for: export) == "Bookings #227 Export to PDF")
        for id in [uuid(108), uuid(109)] {
            let entry = try #require(ledger.entries[id])
            #expect(context.startLine(for: entry) == nil)
        }
    }

    @Test func examplesNameTheLastProjectAndAllRead() {
        let idle = F.context(F.ledger())
        let lines = idle.examples.map(\.line)
        #expect(lines == [
            "Internal Planning",
            "internal -15m",
            "internal 9-10:30",
            "internal for 45m",
            "internal yesterday 14-16",
            "find planning",
            "new project Website",
        ])
        for example in idle.examples {
            #expect(example.reading.primary != nil, "\(example.line)")
            if let draft = example.reading.draft {
                #expect(draft.projectID == F.inHouse, "\(example.line)")
            }
        }

        let running = F.context(F.ledger(F.switchedToHarbor), now: "12:20")
        #expect(running.examples.map(\.line).prefix(3) == ["Bookings #227 Export to PDF", "stop -10m", "bookings -15m"])
        #expect(running.examples.map(\.line).contains("find export"))
        for example in running.examples {
            #expect(example.reading.primary != nil, "\(example.line)")
        }
    }

    @Test func examplesNameTheProjectByAWordThatFindsIt() {
        let stamp = t("2026-06-01T09:00:00+02:00")
        let xray = uuid(30)
        let ledger = Ledger(
            clients: [],
            projects: [Project(id: xray, name: "X-Ray", color: "#4F7CAC", updated: stamp)],
            entries: [F.entry(130, xray, "2026-10-05", "08:00", "09:00", note: "Scan")]
        )
        // "x" alone is too short to find a project.
        let examples = F.context(ledger).examples
        #expect(examples.contains { $0.line == "ray -15m" })
        for example in examples {
            if let draft = example.reading.draft {
                #expect(draft.projectID == xray, "\(example.line)")
            }
        }
    }

    @Test func withoutProjectsTheExampleAddsOne() {
        let empty = F.context(Ledger())
        #expect(empty.examples.map(\.line) == ["new project Website"])
        #expect(empty.examples.first?.reading.primary != nil)
    }
}
