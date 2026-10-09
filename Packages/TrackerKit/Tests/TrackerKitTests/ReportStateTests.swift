import Foundation
import Testing
import TrackerCore
@testable import TrackerKit

/// A report screen's figures: worked out when first read, and again only
/// after the data, the day, the filters or the days changed.
@Suite @MainActor struct ReportStateTests {
    let hour: Int64 = 3_600_000

    func day(_ month: Int, _ day: Int, _ year: Int = 2026) -> LocalDate {
        LocalDate(year: year, month: month, day: day)
    }

    @Test func worksTheFiguresOutAgainAfterTheDataOrTheReportChanged() async throws {
        let (harness, model) = await Harness.started()
        defer { harness.cleanUp() }
        let website = model.addProject(named: "Website", client: nil, color: Palette.colors[0], undoManager: nil)
        var review = entry(note: "Review", at: "2026-09-22T09:00:00+02:00")
        review.projectID = website
        model.addEntry(review, undoManager: nil)
        model.addEntry(entry(note: "Admin", at: "2026-09-21T09:00:00+02:00"), undoManager: nil)
        let state = ReportState(model: model, range: day(9, 1)...day(9, 30), period: .month)

        #expect(state.report.total == 2 * hour)
        #expect(state.dayTotals.total(on: day(9, 21)) == hour)
        // Read again with nothing changed, they're the same.
        let report = state.report
        let comparison = state.comparison
        #expect(state.report == report)
        #expect(state.comparison == comparison)

        // A new entry.
        model.addEntry(entry(note: "Call", at: "2026-09-23T07:00:00+02:00"), undoManager: nil)
        #expect(state.report.total == 3 * hour)
        #expect(state.dayTotals.total(on: day(9, 23)) == hour)

        // A typed report's filters.
        var query = ReportQuery()
        query.projects = [website]
        state.apply(query)
        #expect(state.report.total == hour)
        #expect(state.dayTotals.total(on: day(9, 21)) == 0)

        // Other days.
        state.show(day(8, 1)...day(8, 31), period: .month)
        #expect(state.report.total == 0)
        #expect(state.comparison.previousRange == day(7, 1)...day(7, 31))
    }

    @Test func comparesWithTheDaysBeforeUpToToday() async throws {
        let (harness, model) = await Harness.started()
        defer { harness.cleanUp() }
        let state = ReportState(model: model, range: day(9, 1)...day(9, 30), period: .month)
        // Wednesday, September 23, so August up to the 23rd.
        #expect(state.comparison.previousRange == day(8, 1)...day(8, 23))

        harness.clock.advance(seconds: 86400)
        model.refreshClock()
        #expect(state.comparison.previousRange == day(8, 1)...day(8, 24))
    }

    @Test func leavesTheRunningTimerOut() async throws {
        let (harness, model) = await Harness.started()
        defer { harness.cleanUp() }
        model.addEntry(entry(note: "Review", at: "2026-09-23T07:00:00+02:00"), undoManager: nil)
        model.startTimer(EntryDraft(note: "Call"), undoManager: nil)
        harness.clock.advance(seconds: 1800)
        model.refreshClock()
        let state = ReportState(model: model, range: day(9, 1)...day(9, 30), period: .month)

        #expect(state.report.running?.entry.note == "Call")
        #expect(state.report.total == hour)
        #expect(state.dayTotals.total(on: day(9, 23)) == hour)
    }

    @Test func daysOverTheYearsEndHaveTheNextJanuarysTotals() async throws {
        let (harness, model) = await Harness.started()
        defer { harness.cleanUp() }
        model.addEntry(entry(note: "Planning", at: "2027-01-20T09:00:00+01:00"), undoManager: nil)
        let state = ReportState(model: model, range: day(9, 1)...day(9, 30), period: .month)
        #expect(state.dayTotals.total(on: day(1, 20, 2027)) == 0)

        state.show(day(12, 28)...day(1, 3, 2027), period: .week)
        #expect(state.dayTotals.total(on: day(1, 20, 2027)) == hour)
    }
}
