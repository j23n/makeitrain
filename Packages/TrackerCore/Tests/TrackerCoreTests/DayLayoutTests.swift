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

    @Test func showsSevenToSevenWidenedToEntriesAdditionsAndNow() {
        let none: [TimeEntry] = []
        #expect(DayLayout.hours(blocks: blocks([]), additions: none, nowHour: nil) == 7..<19)
        let early = blocks([entry(1, "2026-09-23T06:30:00+02:00", "2026-09-23T08:00:00+02:00")])
        #expect(DayLayout.hours(blocks: early, additions: none, nowHour: nil) == 6..<19)
        // An end past the hour shows that hour in full.
        let late = blocks([entry(2, "2026-09-23T18:00:00+02:00", "2026-09-23T20:10:00+02:00")])
        #expect(DayLayout.hours(blocks: late, additions: none, nowHour: nil) == 7..<21)
        let addition = entry(3, "2026-09-23T05:15:00+02:00", "2026-09-23T21:30:00+02:00")
        #expect(DayLayout.hours(blocks: blocks([]), additions: [addition], nowHour: nil) == 5..<22)
        #expect(DayLayout.hours(blocks: blocks([]), additions: none, nowHour: 22) == 7..<23)
        // An entry past midnight shows the day to its end.
        let overnight = blocks([entry(4, "2026-09-23T23:00:00+02:00", "2026-09-24T01:00:00+02:00")])
        #expect(DayLayout.hours(blocks: overnight, additions: none, nowHour: 0) == 0..<24)
    }

    @Test func aShortBlockEndsWhereItsEntryDoes() throws {
        let result = blocks([
            entry(1, "2026-09-23T09:00:00+02:00", "2026-09-23T09:10:00+02:00"),
            entry(2, "2026-09-23T09:10:00+02:00", "2026-09-23T10:00:00+02:00"),
        ])
        // Back to back, they share a column: the first mustn't reach into
        // the second.
        #expect(result.map(\.column) == [0, 0])
        let short = try #require(result.first)
        #expect(DayLayout.nextStart(after: short, in: result) == 9 * 3600 + 600)
        let hourHeight = 56.0
        let height = DayLayout.height(
            from: short.startSecond,
            to: short.endSecond,
            hourHeight: hourHeight,
            nextStart: DayLayout.nextStart(after: short, in: result)
        )
        // Ten minutes' worth of points, so the next block starts at its
        // bottom.
        #expect(abs(height - hourHeight / 6) < 0.000_001)
        let next = result[1]
        let top = Double(next.startSecond - short.startSecond) / 3600 * hourHeight
        #expect(abs(top - height) < 0.000_001)
        #expect(DayLayout.nextStart(after: next, in: result) == nil)
    }

    @Test func aVeryShortBlockIsAHairlineWhereThereIsRoom() {
        // A minute is less than a point: it's drawn as a hairline.
        #expect(DayLayout.height(from: 0, to: 60, hourHeight: 56) == DayLayout.hairline)
        // But not past the entry that starts when it ends.
        #expect(abs(DayLayout.height(from: 0, to: 60, hourHeight: 56, nextStart: 60) - 56.0 / 60) < 0.000_001)
        #expect(abs(DayLayout.height(from: 0, to: 0, hourHeight: 56, nextStart: 120) - 56.0 / 30) < 0.000_001)
        // Blocks that start before this one ends sit beside it, not below.
        let result = blocks([
            entry(1, "2026-09-23T09:00:00+02:00", "2026-09-23T09:01:00+02:00"),
            entry(2, "2026-09-23T09:00:30+02:00", "2026-09-23T09:30:00+02:00"),
            entry(3, "2026-09-23T11:00:00+02:00", "2026-09-23T12:00:00+02:00"),
        ])
        #expect(DayLayout.nextStart(after: result[0], in: result) == 11 * 3600)
    }

    @Test func aShortBlockInARunCanStillBePicked() throws {
        // As in the previews: 5 minutes, then 2, then 18, back to back.
        let result = blocks([
            entry(1, "2026-09-23T12:40:00+02:00", "2026-09-23T12:45:00+02:00"),
            entry(2, "2026-09-23T12:45:00+02:00", "2026-09-23T12:47:00+02:00"),
            entry(3, "2026-09-23T12:47:00+02:00", "2026-09-23T13:05:00+02:00"),
        ])
        let hourHeight = 56.0
        let merge = result[1]
        let top = Double(merge.startSecond) / 3600 * hourHeight
        let height = DayLayout.height(
            from: merge.startSecond,
            to: merge.endSecond,
            hourHeight: hourHeight,
            nextStart: DayLayout.nextStart(after: merge, in: result)
        )
        // Drawn two minutes tall, under 2 points, so as not to cover the
        // next entry...
        #expect(abs(height - hourHeight / 30) < 0.000_001)
        // ...but it can be clicked in 10, centered on it, over the edges of
        // the blocks before and after.
        let hit = DayLayout.hitSpan(top: top, height: height, minimum: 10)
        #expect(hit.height == 10)
        #expect(abs((hit.top + hit.height / 2) - (top + height / 2)) < 0.000_001)
        let earlierBottom = Double(result[0].endSecond) / 3600 * hourHeight
        let laterTop = Double(result[2].startSecond) / 3600 * hourHeight
        #expect(hit.top < earlierBottom)
        #expect(hit.top + hit.height > laterTop)
        // A block that's tall enough is clicked where it's drawn.
        let tall = DayLayout.hitSpan(top: 100, height: 16.8, minimum: 10)
        #expect(tall.top == 100)
        #expect(tall.height == 16.8)
    }

    @Test func placesTimesOnTheDayAndOthersAtItsEnds() {
        #expect(DayLayout.second(of: t("2026-09-23T09:30:00+02:00"), on: day, zone: "Europe/Berlin") == 9 * 3600 + 1800)
        #expect(DayLayout.second(of: t("2026-09-23T09:30:00+02:00"), on: day, zone: "America/New_York") == 3 * 3600 + 1800)
        #expect(DayLayout.second(of: t("2026-09-22T23:00:00+02:00"), on: day, zone: "Europe/Berlin") == 0)
        #expect(DayLayout.second(of: t("2026-09-24T00:30:00+02:00"), on: day, zone: "Europe/Berlin") == 86400)
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
