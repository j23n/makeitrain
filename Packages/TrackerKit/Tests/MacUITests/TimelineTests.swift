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

    @Test func movingSnapsToFiveMinutesAndKeepsTheLength() {
        let (start, end) = DayTimeline.adjusted(block("09:00", "10:00"), kind: .move, by: 7 * 60)
        #expect(start == second("09:05"))
        #expect(end == second("10:05"))
    }

    @Test func movingStaysWithinTheDay() {
        let (earlyStart, earlyEnd) = DayTimeline.adjusted(block("09:00", "10:00"), kind: .move, by: -10 * 3600)
        #expect(earlyStart == 0)
        #expect(earlyEnd == 3600)

        let (lateStart, lateEnd) = DayTimeline.adjusted(block("23:00", "23:30"), kind: .move, by: 2 * 3600)
        #expect(lateStart == second("23:30"))
        #expect(lateEnd == 86400)
    }

    @Test func draggingTheTopEdgeMovesOnlyTheStart() {
        let (start, end) = DayTimeline.adjusted(block("09:00", "10:00"), kind: .start, by: -28 * 60)
        #expect(start == second("08:30"))
        #expect(end == second("10:00"))

        // The start stops five minutes before the end.
        let (lateStart, _) = DayTimeline.adjusted(block("09:00", "10:00"), kind: .start, by: 2 * 3600)
        #expect(lateStart == second("09:55"))
    }

    @Test func draggingTheBottomEdgeMovesOnlyTheEnd() {
        let (start, end) = DayTimeline.adjusted(block("09:00", "10:00"), kind: .end, by: 2 * 3600 + 100)
        #expect(start == second("09:00"))
        #expect(end == second("12:00"))

        // The end stays five minutes after the start, and within the day.
        let (_, earlyEnd) = DayTimeline.adjusted(block("09:00", "10:00"), kind: .end, by: -2 * 3600)
        #expect(earlyEnd == second("09:05"))
        let (_, lateEnd) = DayTimeline.adjusted(block("09:00", "10:00"), kind: .end, by: 20 * 3600)
        #expect(lateEnd == 86400)
    }
}
#endif
