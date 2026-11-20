import Foundation
import Testing
@testable import TrackerCore

@Suite struct NewEntrySpanTests {
    let day = LocalDate(year: 2026, month: 11, day: 19)
    let latest = NewEntrySpan.lastEnd

    func hm(_ hour: Int, _ minute: Int) -> Int {
        hour * 3600 + minute * 60
    }

    @Test func dragSnapsToFiveMinutesEitherWay() {
        let down = NewEntrySpan.dragged(from: hm(14, 13), to: hm(16, 31), latest: latest)
        #expect(down?.start == hm(14, 15))
        #expect(down?.end == hm(16, 30))
        let up = NewEntrySpan.dragged(from: hm(16, 31), to: hm(14, 13), latest: latest)
        #expect(up?.start == hm(14, 15))
        #expect(up?.end == hm(16, 30))
    }

    @Test func dragIsAtLeastFiveMinutes() {
        let span = NewEntrySpan.dragged(from: hm(9, 0), to: hm(9, 1), latest: latest)
        #expect(span?.start == hm(9, 0))
        #expect(span?.end == hm(9, 5))
    }

    @Test func dragStopsAtTheLatestEnd() {
        let now = hm(15, 40)
        let span = NewEntrySpan.dragged(from: hm(14, 0), to: hm(17, 0), latest: now)
        #expect(span?.end == now)
        // Started after now, it ends now and is five minutes long.
        let late = NewEntrySpan.dragged(from: hm(16, 0), to: hm(17, 0), latest: now)
        #expect(late?.start == hm(15, 35))
        #expect(late?.end == now)
        #expect(NewEntrySpan.dragged(from: 0, to: hm(1, 0), latest: 120) == nil)
    }

    @Test func latestIsNowOnTodayAndTheDaysLastEndBefore() {
        let now = t("2026-11-19T15:42:10+01:00")
        #expect(NewEntrySpan.latest(on: day, now: now, zone: "Europe/Berlin") == hm(15, 40))
        #expect(NewEntrySpan.latest(on: day.adding(days: -1), now: now, zone: "Europe/Berlin") == hm(23, 55))
        #expect(NewEntrySpan.latest(on: day.adding(days: 1), now: now, zone: "Europe/Berlin") == 0)
    }

    @Test func holdingMakesHalfAnHourUntilDraggedFurther() {
        let held = NewEntrySpan.held(at: hm(15, 2), to: hm(15, 10), latest: latest)
        #expect(held?.start == hm(15, 0))
        #expect(held?.end == hm(15, 30))
        let dragged = NewEntrySpan.held(at: hm(15, 2), to: hm(16, 28), latest: latest)
        #expect(dragged?.start == hm(15, 0))
        #expect(dragged?.end == hm(16, 30))
        let upward = NewEntrySpan.held(at: hm(15, 0), to: hm(14, 0), latest: latest)
        #expect(upward?.start == hm(14, 0))
        #expect(upward?.end == hm(15, 0))
    }

    @Test func draggingPastHalfAnHourKeepsTheHeldStart() {
        let held = NewEntrySpan.held(at: hm(15, 3), to: hm(15, 20), latest: latest)
        #expect(held?.start == hm(15, 0))
        let dragged = NewEntrySpan.held(at: hm(15, 3), to: hm(15, 40), latest: latest)
        #expect(dragged?.start == hm(15, 0))
        #expect(dragged?.end == hm(15, 40))
    }

    @Test func aHeldEntryNearNowEndsNow() {
        let span = NewEntrySpan.held(at: hm(15, 30), to: hm(15, 30), latest: hm(15, 40))
        #expect(span?.start == hm(15, 10))
        #expect(span?.end == hm(15, 40))
    }

    @Test func doubleClickMakesAnHour() {
        let span = NewEntrySpan.clicked(at: hm(10, 7), latest: latest)
        #expect(span?.start == hm(10, 5))
        #expect(span?.end == hm(11, 5))
    }

    @Test func adjustingKeepsTheOtherEndAndFiveMinutes() {
        let start = NewEntrySpan.adjusted(start: hm(15, 0), end: hm(16, 0), movingStart: true, to: hm(15, 58), latest: latest)
        #expect(start.start == hm(15, 55))
        #expect(start.end == hm(16, 0))
        let end = NewEntrySpan.adjusted(start: hm(15, 0), end: hm(16, 0), movingStart: false, to: hm(18, 0), latest: hm(17, 0))
        #expect(end.start == hm(15, 0))
        #expect(end.end == hm(17, 0))
    }

    @Test func findsWhatItOverlaps() {
        let entries = [
            TimeEntry(id: uuid(1), start: t("2026-11-19T13:00:00+01:00"), end: t("2026-11-19T14:30:00+01:00"), timeZone: "Europe/Berlin", updated: t("2026-11-19T00:00:00Z")),
            TimeEntry(id: uuid(2), start: t("2026-11-19T17:00:00+01:00"), end: t("2026-11-19T18:00:00+01:00"), timeZone: "Europe/Berlin", updated: t("2026-11-19T00:00:00Z")),
        ]
        let found = NewEntrySpan.overlapping(
            start: t("2026-11-19T14:15:00+01:00"),
            end: t("2026-11-19T16:30:00+01:00"),
            startSecond: hm(14, 15),
            entries: Ledger(entries: entries).resolvedEntries(),
            now: t("2026-11-20T12:00:00+01:00")
        )
        #expect(found.map(\.entry.id) == [uuid(1)])
        #expect(found.map(\.range) == [hm(14, 15)..<hm(14, 30)])
    }

    @Test func findsAnOverlapFromTheDayBeforeAndAnotherZone() {
        let entries = [
            TimeEntry(id: uuid(1), start: t("2026-11-18T22:00:00+01:00"), end: t("2026-11-19T01:30:00+01:00"), timeZone: "Europe/Berlin", updated: t("2026-11-19T00:00:00Z")),
            TimeEntry(id: uuid(2), start: t("2026-11-19T00:45:00+01:00"), end: t("2026-11-19T02:00:00+01:00"), timeZone: "Europe/London", updated: t("2026-11-19T00:00:00Z")),
        ]
        let found = NewEntrySpan.overlapping(
            start: t("2026-11-19T00:30:00+01:00"),
            end: t("2026-11-19T01:00:00+01:00"),
            startSecond: hm(0, 30),
            entries: Ledger(entries: entries).resolvedEntries(),
            now: t("2026-11-20T12:00:00+01:00")
        )
        #expect(found.map(\.entry.id) == [uuid(1), uuid(2)])
        #expect(found.map(\.range) == [hm(0, 30)..<hm(1, 0), hm(0, 45)..<hm(1, 0)])
        #expect(NewEntrySpan.merged(found.map(\.range)) == [hm(0, 30)..<hm(1, 0)])
    }

    @Test func mergesTouchingRanges() {
        let ranges = [hm(15, 0)..<hm(15, 30), hm(14, 0)..<hm(14, 30), hm(14, 30)..<hm(14, 45), hm(14, 40)..<hm(14, 50)]
        #expect(NewEntrySpan.merged(ranges) == [hm(14, 0)..<hm(14, 50), hm(15, 0)..<hm(15, 30)])
    }

    @Test func writesTheStartOfTheLine() {
        let line = Ledger.newEntryLine(day: day, startSecond: hm(14, 15), endSecond: hm(16, 30), today: day.adding(days: 1))
        #expect(line == "19 nov 14:15-16:30 ")
    }
}
