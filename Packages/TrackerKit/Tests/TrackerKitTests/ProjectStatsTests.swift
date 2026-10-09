import Foundation
import Testing
import TrackerCore
@testable import TrackerKit

/// The projects lists' figures, from each day's time by project and the
/// entries, as the model keeps them.
@Suite @MainActor struct ProjectStatsTests {
    let hour: Int64 = 3_600_000
    let minute: Int64 = 60000

    @Test func addsUpThisWeekThisMonthAndTheLastTwelveWeeks() async throws {
        let (harness, model) = await Harness.started()
        defer { harness.cleanUp() }
        model.firstWeekday = 2
        let website = model.addProject(named: "Website", client: nil, color: Palette.colors[0], undoManager: nil)
        // Now is Wednesday, September 23, at 9:00, in the week from Monday
        // the 21st. The twelve weeks start on Monday, July 6.
        for start in [
            "2026-09-23T07:00:00+02:00",
            "2026-09-21T09:00:00+02:00",
            // The week before, still this month.
            "2026-09-14T09:00:00+02:00",
            // Last month, four weeks before that.
            "2026-08-31T09:00:00+02:00",
            // Before the twelve weeks.
            "2026-06-01T09:00:00+02:00",
        ] {
            var logged = entry(note: "Work", at: start)
            logged.projectID = website
            model.addEntry(logged, undoManager: nil)
        }
        model.addEntry(entry(note: "Admin", at: "2026-09-22T09:00:00+02:00"), undoManager: nil)
        // Running for half an hour so far.
        model.startTimer(EntryDraft(projectID: website), undoManager: nil)
        harness.clock.advance(seconds: 1800)
        model.refreshClock()

        let row = model.projectStats[website]
        #expect(row.thisWeek == 2 * hour + 30 * minute)
        #expect(row.thisMonth == 3 * hour + 30 * minute)
        #expect(row.weeks == [0, 0, 0, 0, 0, 0, 0, 0, hour, 0, hour, 2 * hour + 30 * minute])
        #expect(row.total == 5 * hour + 30 * minute)
        #expect(row.entryCount == 6)

        let unassigned = model.projectStats[nil]
        #expect(unassigned.thisWeek == hour)
        #expect(unassigned.latest?.entry.note == "Admin")
    }

    @Test func followsTheDataTheTimeAndWhereWeeksStart() async throws {
        let (harness, model) = await Harness.started()
        defer { harness.cleanUp() }
        model.firstWeekday = 2
        let website = model.addProject(named: "Website", client: nil, color: Palette.colors[0], undoManager: nil)
        model.startTimer(EntryDraft(projectID: website), undoManager: nil)
        #expect(model.projectStats[website].thisWeek == 0)

        // The running timer's minutes.
        let ticked = watch { _ = model.projectStats }
        harness.clock.advance(seconds: 600)
        model.refreshClock()
        #expect(ticked.isSet)
        #expect(model.projectStats[website].thisWeek == 10 * minute)

        // A new entry, on Sunday the 20th, the week before.
        var sunday = entry(note: "Review", at: "2026-09-20T09:00:00+02:00")
        sunday.projectID = website
        let added = watch { _ = model.projectStats }
        model.addEntry(sunday, undoManager: nil)
        #expect(added.isSet)
        #expect(model.projectStats[website].total == hour + 10 * minute)
        #expect(model.projectStats[website].thisWeek == 10 * minute)

        // Weeks that start on Sunday.
        let moved = watch { _ = model.projectStats }
        model.firstWeekday = 1
        #expect(moved.isSet)
        #expect(model.projectStats[website].thisWeek == hour + 10 * minute)
    }
}
