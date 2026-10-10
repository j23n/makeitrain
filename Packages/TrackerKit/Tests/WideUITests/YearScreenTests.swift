import Foundation
import Testing
import TrackerCore
import TrackerKit
@testable import WideUI

/// The year's keys, worked out outside the view.
@MainActor
@Suite struct YearScreenTests {
    @Test func arrowsMoveOverTheMonthsIntoTheYearBeforeOrAfter() {
        // ↑ goes up a row of four months, from February into last October.
        let up = YearScreen.moved(2, of: 2026, by: -4)
        #expect(up.month == 10)
        #expect(up.year == 2025)
        // → from December goes on to next January.
        let right = YearScreen.moved(12, of: 2026, by: 1)
        #expect(right.month == 1)
        #expect(right.year == 2027)
        let left = YearScreen.moved(1, of: 2026, by: -1)
        #expect(left.month == 12)
        #expect(left.year == 2025)
        let down = YearScreen.moved(11, of: 2026, by: 4)
        #expect(down.month == 3)
        #expect(down.year == 2027)
        // Within the year, the year stays.
        let within = YearScreen.moved(6, of: 2026, by: 4)
        #expect(within.month == 10)
        #expect(within.year == 2026)
    }

    @Test func returnOpensTodayInThisMonthAndOtherwiseTheFirst() {
        let today = LocalDate(year: 2026, month: 10, day: 14)
        #expect(YearScreen.day(opening: 10, of: 2026, today: today) == today)
        #expect(YearScreen.day(opening: 9, of: 2026, today: today) == LocalDate(year: 2026, month: 9, day: 1))
        #expect(YearScreen.day(opening: 10, of: 2025, today: today) == LocalDate(year: 2025, month: 10, day: 1))
    }
}
