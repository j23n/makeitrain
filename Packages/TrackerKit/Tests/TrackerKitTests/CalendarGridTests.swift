import Foundation
import Testing
import TrackerCore
@testable import TrackerKit

@Suite struct CalendarGridTests {
    let day = LocalDate(year: 2026, month: 9, day: 23)

    /// A block for an entry on September 23 in Berlin, with times such as "09:00".
    func block(_ start: String, _ end: String) -> DayBlock {
        let startTime = DateTimeFormat.parse("2026-09-23T\(start):00+02:00")!
        let endTime = DateTimeFormat.parse("2026-09-23T\(end):00+02:00")!
        let entry = TimeEntry(start: startTime, end: endTime, timeZone: "Europe/Berlin", updated: startTime)
        return DayLayout.blocks(on: day, entries: Ledger(entries: [entry]).resolvedEntries(), now: endTime)[0]
    }

    func second(_ time: String) -> Int {
        let parts = time.split(separator: ":").map { Int($0)! }
        return parts[0] * 3600 + parts[1] * 60
    }

    @Test func movingSnapsToFiveMinutesAndKeepsTheLength() {
        let (start, end) = HourGrid.adjusted(block("09:00", "10:00"), kind: .move, by: 7 * 60)
        #expect(start == second("09:05"))
        #expect(end == second("10:05"))
    }

    @Test func movingStaysWithinTheDay() {
        let (earlyStart, earlyEnd) = HourGrid.adjusted(block("09:00", "10:00"), kind: .move, by: -10 * 3600)
        #expect(earlyStart == 0)
        #expect(earlyEnd == 3600)

        let (lateStart, lateEnd) = HourGrid.adjusted(block("23:00", "23:30"), kind: .move, by: 2 * 3600)
        #expect(lateStart == second("23:30"))
        #expect(lateEnd == 86400)
    }

    @Test func draggingTheTopEdgeMovesOnlyTheStart() {
        let (start, end) = HourGrid.adjusted(block("09:00", "10:00"), kind: .start, by: -28 * 60)
        #expect(start == second("08:30"))
        #expect(end == second("10:00"))

        // The start stops five minutes before the end.
        let (lateStart, _) = HourGrid.adjusted(block("09:00", "10:00"), kind: .start, by: 2 * 3600)
        #expect(lateStart == second("09:55"))
    }

    @Test func draggingSidewaysMovesToTheNearestDay() {
        #expect(HourGrid.dayShift(130, dayWidth: 100, from: 2, days: 7) == 1)
        #expect(HourGrid.dayShift(-160, dayWidth: 100, from: 2, days: 7) == -2)
        #expect(HourGrid.dayShift(40, dayWidth: 100, from: 2, days: 7) == 0)
        // Only to the days shown.
        #expect(HourGrid.dayShift(-500, dayWidth: 100, from: 2, days: 7) == -2)
        #expect(HourGrid.dayShift(900, dayWidth: 100, from: 2, days: 7) == 4)
        #expect(HourGrid.dayShift(300, dayWidth: 100, from: 0, days: 1) == 0)
    }

    @Test func aMonthShowsEveryWeekWithOneOfItsDays() {
        // September 2026 starts on a Tuesday and ends on a Wednesday.
        let weeks = MonthGrid.weeks(of: LocalDate(year: 2026, month: 9, day: 23), firstWeekday: 2)
        #expect(weeks.count == 5)
        #expect(weeks.first?.first == LocalDate(year: 2026, month: 8, day: 31))
        #expect(weeks.last?.last == LocalDate(year: 2026, month: 10, day: 4))
        #expect(weeks.allSatisfy { $0.count == 7 })

        // With weeks starting on Sunday, August 30 comes first.
        let sundays = MonthGrid.weeks(of: LocalDate(year: 2026, month: 9, day: 1), firstWeekday: 1)
        #expect(sundays.first?.first == LocalDate(year: 2026, month: 8, day: 30))
        #expect(sundays.last?.last == LocalDate(year: 2026, month: 10, day: 3))
    }

    @Test func draggingTheBottomEdgeMovesOnlyTheEnd() {
        let (start, end) = HourGrid.adjusted(block("09:00", "10:00"), kind: .end, by: 2 * 3600 + 100)
        #expect(start == second("09:00"))
        #expect(end == second("12:00"))

        // The end stays five minutes after the start, and within the day.
        let (_, earlyEnd) = HourGrid.adjusted(block("09:00", "10:00"), kind: .end, by: -2 * 3600)
        #expect(earlyEnd == second("09:05"))
        let (_, lateEnd) = HourGrid.adjusted(block("09:00", "10:00"), kind: .end, by: 20 * 3600)
        #expect(lateEnd == 86400)
    }
}

@Suite @MainActor struct GridDragTests {
    let monday = LocalDate(year: 2026, month: 9, day: 21)

    func time(_ text: String) -> Timestamp {
        DateTimeFormat.parse(text)!
    }

    @Test func movingABlockToAnotherDayKeepsItsLength() async {
        let (harness, model) = await Harness.started()
        defer { harness.cleanUp() }
        let review = entry(note: "Review", at: "2026-09-21T09:00:00+02:00")
        model.addEntry(review, undoManager: nil)
        let block = DayLayout.blocks(on: monday, entries: model.resolved, now: model.now)[0]

        model.applyDrag(.move, to: block, on: monday, startSecond: 14 * 3600, endSecond: 15 * 3600, dayShift: 1, undoManager: nil)
        let moved = model.resolved.first { $0.id == review.id }
        #expect(moved?.start == time("2026-09-22T14:00:00+02:00"))
        #expect(moved?.end == time("2026-09-22T15:00:00+02:00"))
    }

    @Test func draggingAnEdgeChangesOnlyThatTime() async {
        let (harness, model) = await Harness.started()
        defer { harness.cleanUp() }
        let review = entry(note: "Review", at: "2026-09-21T09:00:00+02:00")
        model.addEntry(review, undoManager: nil)
        var block = DayLayout.blocks(on: monday, entries: model.resolved, now: model.now)[0]

        model.applyDrag(.end, to: block, on: monday, startSecond: block.startSecond, endSecond: 11 * 3600, undoManager: nil)
        block = DayLayout.blocks(on: monday, entries: model.resolved, now: model.now)[0]
        model.applyDrag(.start, to: block, on: monday, startSecond: 8 * 3600 + 1800, endSecond: block.endSecond, undoManager: nil)
        let changed = model.resolved.first { $0.id == review.id }
        #expect(changed?.start == time("2026-09-21T08:30:00+02:00"))
        #expect(changed?.end == time("2026-09-21T11:00:00+02:00"))
    }

    @Test func draggingTheRunningTimersStartMovesItBack() async {
        let (harness, model) = await Harness.started()
        defer { harness.cleanUp() }
        model.startTimer(EntryDraft(note: "Running"), undoManager: nil)
        let today = model.today
        let block = DayLayout.blocks(on: today, entries: model.resolved, now: model.now)[0]

        model.applyDrag(.start, to: block, on: today, startSecond: 8 * 3600, endSecond: block.endSecond, undoManager: nil)
        #expect(model.running?.start == time("2026-09-23T08:00:00+02:00"))
        #expect(model.running?.entry.note == "Running")
    }
}
