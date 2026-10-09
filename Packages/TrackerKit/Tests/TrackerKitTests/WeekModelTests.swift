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
        // Two screens show the week, as the iPhone's Today and Week can.
        let shown = WeekModel(model: model, days: days)
        let other = WeekModel(model: model, days: days)
        #expect(other.corrections.map(\.id) == ["project \(lunch.id)"])

        // The oldest skip makes room, so the list stays as long.
        shown.skip("project \(lunch.id)")
        #expect(model.preferences.skippedCorrections.count == Preferences.skippedLimit)
        other.refresh()
        #expect(other.corrections.isEmpty)
    }
}
