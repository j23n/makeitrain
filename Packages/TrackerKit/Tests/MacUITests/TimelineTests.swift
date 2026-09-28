#if os(macOS)
import Foundation
import Testing
import TrackerCore
@testable import MacUI

@Suite struct TimelineTests {
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

    @Test func startsAtSevenUnlessAnEntryStartsEarlier() {
        #expect(TimeGrid.firstHour([]) == TimeGrid.morning)
        #expect(TimeGrid.firstHour([[block("09:00", "10:00")]]) == 7)
        #expect(TimeGrid.firstHour([[block("09:00", "10:00")], [block("06:30", "08:00")]]) == 6)
    }

    @Test func movingSnapsToFiveMinutesAndKeepsTheLength() {
        let (start, end) = TimeGrid.adjusted(block("09:00", "10:00"), kind: .move, by: 7 * 60)
        #expect(start == second("09:05"))
        #expect(end == second("10:05"))
    }

    @Test func movingStaysWithinTheDay() {
        let (earlyStart, earlyEnd) = TimeGrid.adjusted(block("09:00", "10:00"), kind: .move, by: -10 * 3600)
        #expect(earlyStart == 0)
        #expect(earlyEnd == 3600)

        let (lateStart, lateEnd) = TimeGrid.adjusted(block("23:00", "23:30"), kind: .move, by: 2 * 3600)
        #expect(lateStart == second("23:30"))
        #expect(lateEnd == 86400)
    }

    @Test func draggingTheTopEdgeMovesOnlyTheStart() {
        let (start, end) = TimeGrid.adjusted(block("09:00", "10:00"), kind: .start, by: -28 * 60)
        #expect(start == second("08:30"))
        #expect(end == second("10:00"))

        // The start stops five minutes before the end.
        let (lateStart, _) = TimeGrid.adjusted(block("09:00", "10:00"), kind: .start, by: 2 * 3600)
        #expect(lateStart == second("09:55"))
    }

    @Test func draggingSidewaysMovesToTheNearestDay() {
        #expect(TimeGrid.dayShift(130, dayWidth: 100, from: 2, days: 7) == 1)
        #expect(TimeGrid.dayShift(-160, dayWidth: 100, from: 2, days: 7) == -2)
        #expect(TimeGrid.dayShift(40, dayWidth: 100, from: 2, days: 7) == 0)
        // Only to the days shown.
        #expect(TimeGrid.dayShift(-500, dayWidth: 100, from: 2, days: 7) == -2)
        #expect(TimeGrid.dayShift(900, dayWidth: 100, from: 2, days: 7) == 4)
        #expect(TimeGrid.dayShift(300, dayWidth: 100, from: 0, days: 1) == 0)
    }

    @Test func aMonthShowsEveryWeekWithOneOfItsDays() {
        // September 2026 starts on a Tuesday and ends on a Wednesday.
        let weeks = MonthCalendar.weeks(of: LocalDate(year: 2026, month: 9, day: 23), firstWeekday: 2)
        #expect(weeks.count == 5)
        #expect(weeks.first?.first == LocalDate(year: 2026, month: 8, day: 31))
        #expect(weeks.last?.last == LocalDate(year: 2026, month: 10, day: 4))
        #expect(weeks.allSatisfy { $0.count == 7 })

        // With weeks starting on Sunday, August 30 comes first.
        let sundays = MonthCalendar.weeks(of: LocalDate(year: 2026, month: 9, day: 1), firstWeekday: 1)
        #expect(sundays.first?.first == LocalDate(year: 2026, month: 8, day: 30))
        #expect(sundays.last?.last == LocalDate(year: 2026, month: 10, day: 3))
    }

    @Test func draggingTheBottomEdgeMovesOnlyTheEnd() {
        let (start, end) = TimeGrid.adjusted(block("09:00", "10:00"), kind: .end, by: 2 * 3600 + 100)
        #expect(start == second("09:00"))
        #expect(end == second("12:00"))

        // The end stays five minutes after the start, and within the day.
        let (_, earlyEnd) = TimeGrid.adjusted(block("09:00", "10:00"), kind: .end, by: -2 * 3600)
        #expect(earlyEnd == second("09:05"))
        let (_, lateEnd) = TimeGrid.adjusted(block("09:00", "10:00"), kind: .end, by: 20 * 3600)
        #expect(lateEnd == 86400)
    }
}
#endif
