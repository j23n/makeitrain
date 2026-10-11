import Foundation
import Testing
import TrackerCore
@testable import TrackerKit

/// A week's corrections as its screens show them, and skipping them.
@Suite @MainActor struct WeekModelTests {
    /// Monday, September 21, to Sunday, September 27.
    let days = LocalDate(year: 2026, month: 9, day: 21)...LocalDate(year: 2026, month: 9, day: 27)

    @Test func skippingACorrectionHidesIt() async throws {
        let (harness, model) = await Harness.started()
        defer { harness.cleanUp() }
        // Entries without a project, a correction each.
        let call = entry(note: "Call", at: "2026-09-21T09:00:00+02:00")
        let admin = entry(note: "Admin", at: "2026-09-22T09:00:00+02:00")
        model.addEntry(call, undoManager: nil)
        model.addEntry(admin, undoManager: nil)
        let week = WeekModel(model: model, days: days)
        #expect(week.corrections.map(\.id) == ["project \(call.id)", "project \(admin.id)"])
        #expect(week.selectedCorrection == "project \(call.id)")

        week.skip("project \(call.id)")
        #expect(week.corrections.map(\.id) == ["project \(admin.id)"])
        #expect(week.previews.map(\.number) == [1])
        #expect(week.selectedCorrection == "project \(admin.id)")
        #expect(model.preferences.isSkipped("project \(call.id)"))
    }

    @Test func anotherScreenSeesASkipWhenTheSkippedListIsFull() async throws {
        let (harness, model) = await Harness.started()
        defer { harness.cleanUp() }
        for index in 0..<Preferences.skippedLimit {
            model.preferences.skip("earlier \(index)")
        }
        let lunch = entry(note: "Lunch", at: "2026-09-22T12:00:00+02:00")
        model.addEntry(lunch, undoManager: nil)
        // Two screens show the week, as two of an iPad's windows can.
        let shown = WeekModel(model: model, days: days)
        let other = WeekModel(model: model, days: days)
        #expect(other.corrections.map(\.id) == ["project \(lunch.id)"])

        // The oldest skip makes room, so the list stays as long.
        shown.skip("project \(lunch.id)")
        #expect(model.preferences.skippedCorrections.count == Preferences.skippedLimit)
        other.refresh()
        #expect(other.corrections.isEmpty)
    }

    @Test func todayPickedFollowsTheDate() async throws {
        let (harness, model) = await Harness.started()
        defer { harness.cleanUp() }
        let wednesday = LocalDate(year: 2026, month: 9, day: 23)
        let thursday = LocalDate(year: 2026, month: 9, day: 24)
        let sunday = LocalDate(year: 2026, month: 9, day: 27)
        let nextMonday = LocalDate(year: 2026, month: 9, day: 28)
        let week = WeekModel(model: model, days: days)

        // Within the week, only the day moves.
        #expect(week.follow(wednesday, from: wednesday, to: thursday, firstWeekday: 2) == thursday)
        #expect(week.days == days)
        // Into the next week, the week moves too.
        #expect(week.follow(sunday, from: sunday, to: nextMonday, firstWeekday: 2) == nextMonday)
        #expect(week.days == nextMonday...LocalDate(year: 2026, month: 10, day: 4))
    }

    @Test func anotherDayPickedStaysWhenTheDateChanges() async throws {
        let (harness, model) = await Harness.started()
        defer { harness.cleanUp() }
        let wednesday = LocalDate(year: 2026, month: 9, day: 23)
        let sunday = LocalDate(year: 2026, month: 9, day: 27)
        let nextMonday = LocalDate(year: 2026, month: 9, day: 28)
        let week = WeekModel(model: model, days: days)

        #expect(week.follow(wednesday, from: sunday, to: nextMonday, firstWeekday: 2) == wednesday)
        #expect(week.days == days)
    }
}
