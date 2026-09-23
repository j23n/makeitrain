import Foundation
import Testing
@testable import TrackerCore

@Suite struct UndoTests {
    let zone = "Europe/Berlin"

    func at(_ time: String) -> Timestamp {
        t("2026-09-23T\(time)+02:00")
    }

    @Test func undoingAStartBringsBackThePreviousTimer() {
        var ledger = Ledger()
        ledger.startTimer(id: uuid(1), timeZone: zone, at: at("09:00:00"), now: at("09:00:00"))

        let beforeStart = ledger
        ledger.startTimer(id: uuid(2), timeZone: zone, at: at("10:00:00"), now: at("10:00:00"))
        let undo = ledger.snapshot(since: beforeStart)
        #expect(undo.addedEntries == [uuid(2)])
        #expect(undo.entries.map(\.id) == [uuid(1)])

        let beforeUndo = ledger
        ledger.restore(undo, now: at("10:00:30"))
        #expect(ledger.runningEntry?.id == uuid(1))
        #expect(ledger.entries[uuid(1)]?.end == nil)
        #expect(ledger.entries[uuid(2)]?.isDeleted == true)

        // Redo: a snapshot of the undo, restored.
        let redo = ledger.snapshot(since: beforeUndo)
        ledger.restore(redo, now: at("10:01:00"))
        #expect(ledger.runningEntry?.id == uuid(2))
        #expect(ledger.entries[uuid(1)]?.end == at("10:00:00"))
        #expect(ledger.entries[uuid(2)]?.isDeleted == false)
    }

    @Test func undoingAStopResumesTheTimerEverywhere() {
        var ledger = Ledger()
        ledger.startTimer(id: uuid(1), timeZone: zone, at: at("09:00:00"), now: at("09:00:00"))
        let neverStopped = ledger

        let beforeStop = ledger
        ledger.stopTimer(at: at("12:00:00"), now: at("12:00:00"))
        let stopped = ledger
        ledger.restore(ledger.snapshot(since: beforeStop), now: at("12:01:00"))
        #expect(ledger.runningEntry?.id == uuid(1))
        #expect(ledger.entries[uuid(1)]?.endUpdated == at("12:01:00"))

        // The resume beats both the stop and a copy that never saw either.
        for other in [neverStopped, stopped] {
            #expect(ledger.merging(other).runningEntry?.id == uuid(1))
            #expect(other.merging(ledger).runningEntry?.id == uuid(1))
        }
    }

    @Test func aResumedTimerSurvivesTheFiles() throws {
        var ledger = Ledger()
        ledger.startTimer(id: uuid(1), timeZone: zone, at: at("09:00:00"), now: at("09:00:00"))
        let beforeStop = ledger
        ledger.stopTimer(at: at("12:00:00"), now: at("12:00:00"))
        ledger.restore(ledger.snapshot(since: beforeStop), now: at("12:01:00"))
        let entry = try #require(ledger.entries[uuid(1)])

        let data = FileFormat.encode(entries: [entry])
        #expect(String(decoding: data, as: UTF8.self).contains(#""endUpdated": "2026-09-23T12:01:00+02:00""#))
        #expect(try FileFormat.decodeEntries(from: data) == [entry])
    }

    @Test func undoingADeleteBringsBackTheText() {
        var ledger = Ledger()
        let entry = TimeEntry(
            id: uuid(1),
            start: at("09:00:00"),
            end: at("10:00:00"),
            timeZone: zone,
            tags: ["design"],
            note: "Wireframes",
            updated: at("10:00:00")
        )
        ledger.addEntry(entry, now: at("10:00:00"))
        let beforeDelete = ledger
        ledger.deleteEntry(uuid(1), now: at("11:00:00"))
        ledger.restore(ledger.snapshot(since: beforeDelete), now: at("11:00:01"))
        #expect(ledger.entries[uuid(1)]?.isDeleted == false)
        #expect(ledger.entries[uuid(1)]?.note == "Wireframes")
        #expect(ledger.entries[uuid(1)]?.tags == ["design"])
    }

    @Test func undoingProjectChanges() {
        var ledger = Ledger()
        let beforeAdd = ledger
        ledger.addProject(Project(id: uuid(10), name: "Website", updated: at("09:00:00")), now: at("09:00:00"))
        let added = ledger.snapshot(since: beforeAdd)
        #expect(added.addedProjects == [uuid(10)])

        let beforeArchive = ledger
        ledger.updateProject(uuid(10), now: at("09:05:00")) { $0.archived = true }
        ledger.restore(ledger.snapshot(since: beforeArchive), now: at("09:06:00"))
        #expect(ledger.projects[uuid(10)]?.archived == false)

        ledger.restore(added, now: at("09:07:00"))
        #expect(ledger.projects[uuid(10)]?.isDeleted == true)
    }

    @Test func nothingChangedMeansNothingToUndo() {
        var ledger = Ledger()
        ledger.startTimer(id: uuid(1), timeZone: zone, at: at("09:00:00"), now: at("09:00:00"))
        let before = ledger
        ledger.updateEntry(uuid(1), now: at("09:30:00")) { $0.note = "" }
        #expect(ledger.snapshot(since: before).isEmpty)
    }
}
