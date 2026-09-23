import Foundation
import Testing
@testable import TrackerCore

@Suite struct DayLayoutTests {
    let day = LocalDate(year: 2026, month: 9, day: 23)

    func entry(_ number: Int, _ start: String, _ end: String?, zone: String = "Europe/Berlin") -> TimeEntry {
        TimeEntry(
            id: uuid(number),
            start: t(start),
            end: end.map(t),
            timeZone: zone,
            updated: t("2026-09-23T00:00:00Z")
        )
    }

    func blocks(_ entries: [TimeEntry], now: String = "2026-09-23T23:00:00+02:00") -> [DayBlock] {
        DayLayout.blocks(on: day, entries: Ledger(entries: entries).resolvedEntries(), now: t(now))
    }

    @Test func placesEntriesAtTheirOwnWallClockTime() {
        let result = blocks([
            entry(1, "2026-09-23T09:00:00+02:00", "2026-09-23T10:30:00+02:00"),
            entry(2, "2026-09-23T09:00:00-04:00", "2026-09-23T10:00:00-04:00", zone: "America/New_York"),
        ])
        #expect(result.map(\.startSecond) == [9 * 3600, 9 * 3600])
        #expect(result.map(\.endSecond) == [10 * 3600 + 1800, 10 * 3600])
    }

    @Test func putsOverlappingEntriesSideBySide() {
        let result = blocks([
            entry(1, "2026-09-23T09:00:00+02:00", "2026-09-23T12:00:00+02:00"),
            entry(2, "2026-09-23T10:00:00+02:00", "2026-09-23T11:00:00+02:00"),
            entry(3, "2026-09-23T11:00:00+02:00", "2026-09-23T13:00:00+02:00"),
            entry(4, "2026-09-23T14:00:00+02:00", "2026-09-23T15:00:00+02:00"),
        ])
        #expect(result.map(\.column) == [0, 1, 1, 0])
        #expect(result.map(\.columns) == [2, 2, 2, 1])
    }

    @Test func cutsOffEntriesAtMidnightAndLeavesOtherDaysOut() {
        let result = blocks([
            entry(1, "2026-09-23T23:00:00+02:00", "2026-09-24T01:00:00+02:00"),
            entry(2, "2026-09-22T09:00:00+02:00", "2026-09-22T10:00:00+02:00"),
            entry(3, "2026-09-24T09:00:00+02:00", "2026-09-24T10:00:00+02:00"),
        ])
        #expect(result.map(\.id) == [uuid(1)])
        #expect(result.first?.endSecond == 86400)
    }

    @Test func aRunningTimerReachesNow() {
        let result = blocks([entry(1, "2026-09-23T09:00:00+02:00", nil)], now: "2026-09-23T11:15:00+02:00")
        #expect(result.first?.endSecond == 11 * 3600 + 900)
    }

    @Test func convertsWallClockTimesToInstants() {
        #expect(Timestamp(date: day, secondOfDay: 9 * 3600, zone: "Europe/Berlin") == t("2026-09-23T09:00:00+02:00"))
        #expect(Timestamp(date: day, secondOfDay: 9 * 3600, zone: "America/New_York") == t("2026-09-23T09:00:00-04:00"))
        #expect(Timestamp(date: day, secondOfDay: 86400, zone: "Europe/Berlin") == t("2026-09-24T00:00:00+02:00"))
        // Winter time.
        let january = LocalDate(year: 2026, month: 1, day: 15)
        #expect(Timestamp(date: january, secondOfDay: 9 * 3600 + 30 * 60, zone: "Europe/Berlin") == t("2026-01-15T09:30:00+01:00"))
    }
}
