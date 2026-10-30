import Foundation
import Testing
import TrackerCore
import TrackerKit
@testable import WideUI

/// The titles a screen header makes room for.
@Suite struct ScreenTitlesTests {
    @Test func makesRoomForWeeksAcrossTheNewYearMonthsAndDays() {
        // Weeks start on Monday.
        let titles = ScreenTitles.widest(in: 2026, firstWeekday: 2)
        let newYear = LocalDate(year: 2026, month: 12, day: 28)...LocalDate(year: 2027, month: 1, day: 3)
        #expect(titles.contains(Format.days(newYear)))
        let september = LocalDate(year: 2026, month: 9, day: 1)...LocalDate(year: 2026, month: 9, day: 30)
        #expect(titles.contains(Format.days(september)))
        let wednesday = LocalDate(year: 2026, month: 9, day: 23)
        #expect(titles.contains(Format.days(wednesday...wednesday)))
    }
}
