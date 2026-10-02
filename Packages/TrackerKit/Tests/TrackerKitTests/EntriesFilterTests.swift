import Foundation
import Testing
import TrackerCore
import TrackerKit

@Suite struct EntriesFilterTests {
    /// A Wednesday.
    let today = LocalDate(year: 2026, month: 9, day: 23)

    func september(_ first: Int, _ last: Int) -> ClosedRange<LocalDate> {
        LocalDate(year: 2026, month: 9, day: first)...LocalDate(year: 2026, month: 9, day: last)
    }

    func range(_ period: EntriesPeriod, firstWeekday: Int = 2) -> ClosedRange<LocalDate>? {
        period.range(today: today, firstWeekday: firstWeekday, custom: nil)
    }

    @Test func periodsCoverTheirDays() {
        #expect(range(.all) == nil)
        #expect(range(.today) == september(23, 23))
        #expect(range(.thisWeek) == september(21, 27))
        #expect(range(.thisWeek, firstWeekday: 1) == september(20, 26))
        #expect(range(.lastWeek) == september(14, 20))
        #expect(range(.thisMonth) == september(1, 30))
        #expect(range(.lastMonth) == LocalDate(year: 2026, month: 8, day: 1)...LocalDate(year: 2026, month: 8, day: 31))
        #expect(range(.thisYear) == LocalDate(year: 2026, month: 1, day: 1)...LocalDate(year: 2026, month: 12, day: 31))
        #expect(range(.custom) == september(21, 27))
        #expect(EntriesPeriod.custom.range(today: today, firstWeekday: 2, custom: september(2, 5)) == september(2, 5))
    }

    @Test func lastMonthInJanuaryIsLastDecember() {
        let january = LocalDate(year: 2027, month: 1, day: 12)
        let december = LocalDate(year: 2026, month: 12, day: 1)...LocalDate(year: 2026, month: 12, day: 31)
        #expect(EntriesPeriod.lastMonth.range(today: january, firstWeekday: 2, custom: nil) == december)
    }

    @Test func periodsFollowTheDayButCustomDaysStay() {
        let october = LocalDate(year: 2026, month: 10, day: 1)
        var filter = EntriesFilter()
        #expect(!filter.isActive)

        filter.choose(.thisMonth, today: today, firstWeekday: 2)
        #expect(filter.range == september(1, 30))
        #expect(filter.isActive)

        // A custom period starts with the days shown, and keeps them.
        filter.choose(.custom, today: today, firstWeekday: 2)
        #expect(filter.range == september(1, 30))
        filter.refresh(today: october, firstWeekday: 2)
        #expect(filter.range == september(1, 30))

        filter.choose(.today, today: today, firstWeekday: 2)
        filter.refresh(today: october, firstWeekday: 2)
        #expect(filter.range == october...october)

        filter.choose(.all, today: october, firstWeekday: 2)
        #expect(filter.range == nil)
        #expect(!filter.isActive)
    }

    @Test func choicesLeftEmptyLetEverythingThrough() {
        var filter = EntriesFilter()
        #expect(filter.entryFilter.isEmpty)

        filter.overlapsOnly = true
        #expect(filter.isActive)
        #expect(filter.entryFilter.isEmpty)

        let unassigned: Set<UUID?> = [nil]
        let design: Set<String> = ["design"]
        filter.projects = unassigned
        filter.tags = design
        #expect(filter.entryFilter.projects == unassigned)
        #expect(filter.entryFilter.clients == nil)
        #expect(filter.entryFilter.tags == design)
    }
}
