import Foundation
import Testing
@testable import TrackerCore

@Suite struct TimerTests {
    let zone = "Europe/Berlin"

    func running(_ number: Int, from start: String) -> TimeEntry {
        TimeEntry(id: uuid(number), start: t(start), timeZone: zone, updated: t(start))
    }

    @Test func startingStopsTheRunningTimerAtTheSameInstant() {
        var ledger = Ledger()
        ledger.startTimer(id: uuid(1), timeZone: zone, at: t("2026-09-23T09:00:00.700+02:00"), now: t("2026-09-23T09:00:00.700+02:00"))
        ledger.startTimer(id: uuid(2), timeZone: zone, at: t("2026-09-23T10:30:00.250+02:00"), now: t("2026-09-23T10:30:00.250+02:00"))
        let first = ledger.entries[uuid(1)]!
        let second = ledger.entries[uuid(2)]!
        #expect(first.start == t("2026-09-23T09:00:00+02:00"))
        #expect(first.end == second.start)
        #expect(second.start == t("2026-09-23T10:30:00+02:00"))
        #expect(second.end == nil)
        #expect(ledger.runningEntry?.id == uuid(2))
    }

    @Test func theLaterOfTwoRunningTimersKeepsRunning() {
        // Two Macs each started a timer while one of them was offline.
        let ledger = Ledger(entries: [running(2, from: "2026-09-23T09:30:00+02:00"), running(1, from: "2026-09-23T09:00:00+02:00")])
        let resolved = ledger.resolvedEntries()
        #expect(resolved.map(\.id) == [uuid(1), uuid(2)])
        #expect(resolved[0].end == t("2026-09-23T09:30:00+02:00"))
        #expect(resolved[0].endedByLaterTimer)
        #expect(resolved[1].isRunning)
        #expect(ledger.runningEntry?.id == uuid(2))
        // Reading doesn't write anything back.
        #expect(ledger.entries[uuid(1)]?.end == nil)
    }

    @Test func runningTimersEndInAChain() {
        let ledger = Ledger(entries: [
            running(1, from: "2026-09-23T09:00:00+02:00"),
            running(2, from: "2026-09-23T09:30:00+02:00"),
            running(3, from: "2026-09-23T10:00:00+02:00"),
        ])
        let ends = ledger.resolvedEntries().map(\.end)
        #expect(ends == [t("2026-09-23T09:30:00+02:00"), t("2026-09-23T10:00:00+02:00"), nil])
    }

    @Test func deletedTimersDontCount() {
        var later = running(2, from: "2026-09-23T09:30:00+02:00")
        later.deleted = t("2026-09-23T09:40:00+02:00")
        let ledger = Ledger(entries: [running(1, from: "2026-09-23T09:00:00+02:00"), later])
        #expect(ledger.resolvedEntries().map(\.id) == [uuid(1)])
        #expect(ledger.runningEntry?.id == uuid(1))
    }

    @Test func theNextChangeGivesAnOvertakenTimerARealEnd() {
        var ledger = Ledger(entries: [running(1, from: "2026-09-23T09:00:00+02:00"), running(2, from: "2026-09-23T09:30:00+02:00")])
        let changes = ledger.stopTimer(at: t("2026-09-23T11:00:00+02:00"), now: t("2026-09-23T11:00:00+02:00"))
        #expect(ledger.entries[uuid(1)]?.end == t("2026-09-23T09:30:00+02:00"))
        #expect(ledger.entries[uuid(2)]?.end == t("2026-09-23T11:00:00+02:00"))
        #expect(changes == Changes(months: [MonthKey(year: 2026, month: 9)]))
    }

    @Test func stopsAtAnEarlierTime() {
        var ledger = Ledger()
        ledger.startTimer(id: uuid(1), timeZone: zone, at: t("2026-09-23T09:00:00+02:00"), now: t("2026-09-23T09:00:00+02:00"))
        ledger.stopTimer(at: t("2026-09-23T17:30:00+02:00"), now: t("2026-09-23T21:00:00+02:00"))
        #expect(ledger.entries[uuid(1)]?.end == t("2026-09-23T17:30:00+02:00"))
        #expect(ledger.entries[uuid(1)]?.endUpdated == t("2026-09-23T21:00:00+02:00"))
    }

    @Test func neverStopsBeforeTheStart() {
        var ledger = Ledger()
        ledger.startTimer(id: uuid(1), timeZone: zone, at: t("2026-09-23T09:00:00+02:00"), now: t("2026-09-23T09:00:00+02:00"))
        ledger.stopTimer(at: t("2026-09-23T08:00:00+02:00"), now: t("2026-09-23T09:05:00+02:00"))
        #expect(ledger.entries[uuid(1)]?.end == t("2026-09-23T09:00:00+02:00"))
    }

    @Test func aStoppedEntryDoesntRunAgain() {
        var ledger = Ledger()
        ledger.startTimer(id: uuid(1), timeZone: zone, at: t("2026-09-23T09:00:00+02:00"), now: t("2026-09-23T09:00:00+02:00"))
        ledger.stopTimer(at: t("2026-09-23T10:00:00+02:00"), now: t("2026-09-23T10:00:00+02:00"))
        ledger.updateEntry(uuid(1), now: t("2026-09-23T10:05:00+02:00")) { $0.end = nil }
        #expect(ledger.entries[uuid(1)]?.end == t("2026-09-23T10:00:00+02:00"))
        #expect(ledger.runningEntry == nil)
    }

    @Test func settingTheStartBackCanMoveTheEntryToAnotherMonth() {
        var ledger = Ledger()
        ledger.startTimer(id: uuid(1), timeZone: zone, at: t("2026-10-01T00:10:00+02:00"), now: t("2026-10-01T00:10:00+02:00"))
        let changes = ledger.updateEntry(uuid(1), now: t("2026-10-01T00:11:00+02:00")) { $0.start = t("2026-09-30T23:00:00+02:00") }
        #expect(changes.months == [MonthKey(year: 2026, month: 9), MonthKey(year: 2026, month: 10)])
        #expect(ledger.entries[uuid(1)]?.month == MonthKey(year: 2026, month: 9))
    }

    @Test func anEditBeatsTheVersionItWasMadeFromEvenWithASlowClock() {
        var macA = Ledger(entries: [running(1, from: "2026-09-23T09:00:00+02:00")])
        macA.updateEntry(uuid(1), now: t("2026-09-23T10:00:00+02:00")) { $0.note = "from A" }
        // Mac B syncs, then edits a minute later by the wall clock, but its clock is two minutes behind.
        var macB = macA
        macB.updateEntry(uuid(1), now: t("2026-09-23T09:59:00+02:00")) { $0.note = "from B" }
        #expect(macA.merging(macB).entries[uuid(1)]?.note == "from B")
    }

    @Test func editsThatChangeNothingStampNothing() {
        var ledger = Ledger(entries: [running(1, from: "2026-09-23T09:00:00+02:00")])
        let before = ledger
        let changes = ledger.updateEntry(uuid(1), now: t("2026-09-23T10:00:00+02:00")) { $0.note = "" }
        #expect(changes.isEmpty)
        #expect(ledger == before)
    }
}
