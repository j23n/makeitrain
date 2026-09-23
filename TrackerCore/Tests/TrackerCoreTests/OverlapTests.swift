import Foundation
import Testing
@testable import TrackerCore

@Suite struct OverlapTests {
    /// An entry on Sep 23 in Berlin, with times such as "09:00", or running if `end` is nil.
    func entry(_ number: Int, _ start: String, _ end: String?) -> TimeEntry {
        TimeEntry(
            id: uuid(number),
            start: at(start),
            end: end.map(at),
            timeZone: "Europe/Berlin",
            updated: t("2026-09-23T08:00:00+02:00")
        )
    }

    func at(_ time: String) -> Timestamp {
        t("2026-09-23T\(time):00+02:00")
    }

    func analyze(_ entries: [TimeEntry], now: String = "23:00") -> OverlapAnalysis {
        Overlaps.analyze(Ledger(entries: entries).resolvedEntries(), now: at(now))
    }

    @Test func findsAnOverlapBehindAShorterEntry() {
        // B starts inside A. C starts after B ends, but still inside A.
        let result = analyze([entry(1, "09:00", "12:00"), entry(2, "10:00", "10:30"), entry(3, "11:00", "11:30")])
        #expect(result.flagged == [uuid(1), uuid(2), uuid(3)])
        #expect(result.overlaps.map(\.earlier) == [uuid(1), uuid(1)])
        #expect(result.overlaps.map(\.later) == [uuid(2), uuid(3)])
        #expect(result.overlaps.map(\.duration) == [1_800_000, 1_800_000])
        #expect(result.groups == [[uuid(1), uuid(2), uuid(3)]])
    }

    @Test func backToBackEntriesDontOverlap() {
        let result = analyze([entry(1, "09:00", "10:00"), entry(2, "10:00", "11:00"), entry(3, "11:00", "12:00")])
        #expect(result.flagged.isEmpty)
        #expect(result.groups.isEmpty)
    }

    @Test func separateOverlapsFormSeparateGroups() {
        let result = analyze([
            entry(1, "09:00", "10:00"), entry(2, "09:30", "10:30"),
            entry(3, "13:00", "14:00"), entry(4, "13:30", "13:45"),
            entry(5, "15:00", "16:00"),
        ])
        #expect(result.groups == [[uuid(1), uuid(2)], [uuid(3), uuid(4)]])
        #expect(!result.flagged.contains(uuid(5)))
    }

    @Test func aRunningTimerEndsNow() {
        let before = analyze([entry(1, "09:00", nil), entry(2, "10:00", "10:30")], now: "09:45")
        #expect(before.flagged.isEmpty)
        let after = analyze([entry(1, "09:00", nil), entry(2, "10:00", "10:30")], now: "11:00")
        #expect(after.flagged == [uuid(1), uuid(2)])
    }

    @Test func entriesWithoutDurationAndDeletedEntriesDontOverlap() {
        var deleted = entry(3, "09:30", "10:30")
        deleted.deleted = at("12:00")
        let result = analyze([entry(1, "09:00", "10:00"), entry(2, "09:30", "09:30"), deleted])
        #expect(result.flagged.isEmpty)
    }

    @Test func offersTrimOrSplit() {
        let partial = analyze([entry(1, "09:00", "10:30"), entry(2, "10:00", "11:00")])
        #expect(partial.overlaps.map(\.fix) == [.trimEarlier(id: uuid(1), end: at("10:00"))])

        let contained = analyze([entry(1, "09:00", "12:00"), entry(2, "10:00", "10:30")])
        #expect(contained.overlaps.map(\.fix) == [.split(outer: uuid(1), inner: uuid(2))])

        let meetingDuringTimer = analyze([entry(1, "09:00", nil), entry(2, "10:00", "10:30")], now: "11:00")
        #expect(meetingDuringTimer.overlaps.map(\.fix) == [.split(outer: uuid(1), inner: uuid(2))])

        let sameStart = analyze([entry(1, "09:00", "10:00"), entry(2, "09:00", "09:30")])
        #expect(sameStart.overlaps.map(\.fix) == [nil])
    }

    @Test func trimmingEndsTheEarlierEntry() {
        var ledger = Ledger(entries: [entry(1, "09:00", "10:30"), entry(2, "10:00", "11:00")])
        ledger.apply(.trimEarlier(id: uuid(1), end: at("10:00")), now: at("12:00"))
        #expect(ledger.entries[uuid(1)]?.end == at("10:00"))
        #expect(Overlaps.analyze(ledger.resolvedEntries(), now: at("12:00")).flagged.isEmpty)
    }

    @Test func splittingCutsTheOuterEntryAroundTheInnerOne() {
        var outer = entry(1, "09:00", "12:00")
        outer.projectID = uuid(9)
        outer.tags = ["design"]
        outer.note = "Wireframes"
        var ledger = Ledger(entries: [outer, entry(2, "10:00", "10:30")])
        ledger.apply(.split(outer: uuid(1), inner: uuid(2)), now: at("13:00"), newID: uuid(3))

        #expect(ledger.entries[uuid(1)]?.end == at("10:00"))
        let after = ledger.entries[uuid(3)]
        #expect(after?.start == at("10:30"))
        #expect(after?.end == at("12:00"))
        #expect(after?.projectID == uuid(9))
        #expect(after?.tags == ["design"])
        #expect(after?.note == "Wireframes")
        #expect(Overlaps.analyze(ledger.resolvedEntries(), now: at("13:00")).flagged.isEmpty)
    }

    @Test func splittingARunningTimerKeepsTheSecondPartRunning() {
        var ledger = Ledger(entries: [entry(1, "09:00", nil), entry(2, "10:00", "10:30")])
        ledger.apply(.split(outer: uuid(1), inner: uuid(2)), now: at("11:00"), newID: uuid(3))
        #expect(ledger.entries[uuid(1)]?.end == at("10:00"))
        #expect(ledger.entries[uuid(3)]?.start == at("10:30"))
        #expect(ledger.runningEntry?.id == uuid(3))
    }

    @Test func countsDoubleCountedTime() {
        let hour = TimeSpan(start: at("09:00"), end: at("10:00"))
        // The same hour three times: three hours counted, one hour of real time.
        #expect(Overlaps.doubleCounted([hour, hour, hour]) == 2 * 3_600_000)
        #expect(Overlaps.doubleCounted([hour, TimeSpan(start: at("10:00"), end: at("11:00"))]) == 0)
        #expect(Overlaps.doubleCounted([
            TimeSpan(start: at("09:00"), end: at("12:00")),
            TimeSpan(start: at("10:00"), end: at("10:30")),
            TimeSpan(start: at("11:00"), end: at("11:30")),
        ]) == 3_600_000)
        #expect(Overlaps.doubleCounted([]) == 0)
    }
}
