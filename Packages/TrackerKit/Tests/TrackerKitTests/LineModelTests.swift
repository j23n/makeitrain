import Foundation
import Testing
import TrackerCore
@testable import TrackerKit

/// The command line's and an entry's line as the fields use them: taking
/// suggestions, going through earlier lines, and applying a line.
@Suite @MainActor struct LineModelTests {
    @Test func takesASuggestionInTheMiddleOfTheLine() async throws {
        let (harness, model) = await Harness.started()
        defer { harness.cleanUp() }
        model.addProject(named: "Website", client: nil, color: Palette.colors[0], undoManager: nil)
        let line = CommandLineModel(model: model)

        line.text = "web review"
        line.cursor = 3
        #expect(line.suggestions.items.map(\.title) == ["Website"])
        #expect(line.acceptSuggestion())
        #expect(line.text == "Website review")
        #expect(line.cursor == 8)
        #expect(line.suggestions.requestedCursor == 8)
        #expect(line.suggestions.isEmpty)
    }

    @Test func aLineBroughtBackHasNoSuggestionsUntilItsChanged() async throws {
        let (harness, model) = await Harness.started()
        defer { harness.cleanUp() }
        model.addProject(named: "Website", client: nil, color: Palette.colors[0], undoManager: nil)
        model.preferences.remember("web")
        let line = CommandLineModel(model: model)

        // So Up and Down go on through the earlier lines.
        #expect(line.previousLine())
        #expect(line.text == "web")
        #expect(line.suggestions.isEmpty)
        #expect(line.up())
        #expect(line.text == "web")

        line.text = "webs"
        #expect(line.suggestions.items.map(\.title) == ["Website"])
        line.text = "web"
        #expect(line.suggestions.items.map(\.title) == ["Website"])
    }

    @Test func tabUpAndDownGoThroughTheSuggestionsFirst() async throws {
        let (harness, model) = await Harness.started()
        defer { harness.cleanUp() }
        model.addProject(named: "Website", client: nil, color: Palette.colors[0], undoManager: nil)
        model.addProject(named: "Webinar", client: nil, color: Palette.colors[1], undoManager: nil)
        model.preferences.remember("web review")
        let line = CommandLineModel(model: model)

        line.text = "we"
        let titles = line.suggestions.items.map(\.title)
        try #require(titles.count == 2)
        #expect(line.down())
        #expect(line.suggestions.highlighted == 1)
        #expect(line.up())
        #expect(line.up())
        #expect(line.suggestions.highlighted == 1)
        #expect(line.tab())
        #expect(line.text == titles[1] + " ")
        // No suggestion is left, and no earlier entry finishes the line.
        #expect(!line.tab())

        // Without suggestions, Up and Down go through the earlier lines,
        // and Down on an empty line lists today's entries.
        line.text = ""
        #expect(line.up())
        #expect(line.text == "web review")
        #expect(line.down())
        #expect(line.text == "")
        #expect(line.down())
        #expect(line.showsToday)
    }

    @Test func listsTodaysEntriesForAnEmptyLineWithoutDown() async throws {
        let (harness, model) = await Harness.started()
        defer { harness.cleanUp() }
        let line = CommandLineModel(model: model)
        #expect(line.listedEntries(alwaysListsToday: true).isEmpty)

        let start = model.now.adding(seconds: -60)
        let today = TimeEntry(start: start, end: model.now, timeZone: "Europe/Berlin", note: "Standup", updated: start)
        model.addEntry(today, undoManager: nil)
        #expect(line.listedEntries(alwaysListsToday: true).map(\.entry.id) == [today.id])
        // Without the option, only Down lists them, as in the main window.
        #expect(line.listedEntries(alwaysListsToday: false).isEmpty)

        line.text = "web"
        #expect(line.listedEntries(alwaysListsToday: true).isEmpty)
        line.text = ""
        #expect(line.listedEntries(alwaysListsToday: true).count == 1)
    }

    @Test func offersLinesRunLatelyThenWordsToAdd() async throws {
        let (harness, model) = await Harness.started()
        defer { harness.cleanUp() }
        model.addProject(named: "Website", client: nil, color: Palette.colors[0], undoManager: nil)
        model.preferences.remember("web review")
        let line = CommandLineModel(model: model)

        #expect(line.chips.map(\.title) == ["web review"])
        line.apply(line.chips[0])
        #expect(line.text == "web review")

        line.text = "web"
        let chips = line.chips
        #expect(chips.map(\.title) == ["Website", "−15m", "#"])
        #expect(chips[0].isHighlighted)
        #expect(chips[2].isTag)
        line.apply(chips[0])
        #expect(line.text == "Website ")
        line.apply(line.chips.first { $0.title == "#" }!)
        #expect(line.text == "Website #")
    }

    @Test func readsAnEntrysLineAndAppliesIt() async throws {
        let (harness, model) = await Harness.started()
        defer { harness.cleanUp() }
        let website = model.addProject(named: "Website", client: nil, color: Palette.colors[0], undoManager: nil)
        let workshop = entry(note: "Workshop", at: "2026-09-22T09:00:00+02:00")
        model.addEntry(workshop, undoManager: nil)
        let line = EntryLineModel(model: model)

        line.show(workshop.id)
        #expect(line.text == "22 sep 9:00-10:00 Workshop")
        #expect(line.isUnchanged)
        #expect(line.parts?.draft.note == "Workshop")
        #expect(line.parts?.end == workshop.end)

        line.text = "22 sep 9:00-10:30 web Workshop"
        #expect(line.parts?.draft.projectID == website)
        #expect(line.parts?.end == workshop.start.adding(seconds: 5400))
        #expect(line.apply(undoManager: nil))
        #expect(model.resolved.first?.entry.projectID == website)
        #expect(model.resolved.first?.end == workshop.start.adding(seconds: 5400))
    }

    @Test func anEntrysLineTakesSuggestionsWithTabUpAndDown() async throws {
        let (harness, model) = await Harness.started()
        defer { harness.cleanUp() }
        model.addProject(named: "Website", client: nil, color: Palette.colors[0], undoManager: nil)
        model.addProject(named: "Webinar", client: nil, color: Palette.colors[1], undoManager: nil)
        let workshop = entry(note: "Workshop", at: "2026-09-22T09:00:00+02:00")
        model.addEntry(workshop, undoManager: nil)
        let line = EntryLineModel(model: model)
        line.show(workshop.id)

        line.text = "22 sep 9:00-10:00 we"
        let titles = line.suggestions.items.map(\.title)
        try #require(titles.count == 2)
        #expect(line.down())
        #expect(line.suggestions.highlighted == 1)
        #expect(line.up())
        #expect(line.suggestions.highlighted == 0)
        #expect(line.tab())
        #expect(line.text == "22 sep 9:00-10:00 \(titles[0]) ")
        // Without suggestions the keys are left to the field.
        #expect(!line.tab())
        #expect(!line.up())
        #expect(!line.down())
    }

    @Test func keysThatMoveNothingLeaveTheSuggestionsAlone() async throws {
        let (harness, model) = await Harness.started()
        defer { harness.cleanUp() }
        model.addProject(named: "Website", client: nil, color: Palette.colors[0], undoManager: nil)
        let workshop = entry(note: "Workshop", at: "2026-09-22T09:00:00+02:00")
        model.addEntry(workshop, undoManager: nil)
        let line = EntryLineModel(model: model)
        line.show(workshop.id)

        // With one suggestion, Up and Down are taken but move nothing, so
        // what shows the suggestions doesn't redraw.
        line.text = "22 sep 9:00-10:00 web"
        try #require(line.suggestions.items.count == 1)
        let withOne = watch { _ = line.suggestions }
        #expect(line.up())
        #expect(line.down())
        #expect(!withOne.isSet)

        // Nor does it with none, when the keys are left to the field.
        #expect(line.tab())
        try #require(line.suggestions.isEmpty)
        let withNone = watch { _ = line.suggestions }
        #expect(!line.tab())
        #expect(!line.up())
        #expect(!line.down())
        #expect(!withNone.isSet)
    }

    @Test func aLineWithoutTimesKeepsTheEntrys() async throws {
        let (harness, model) = await Harness.started()
        defer { harness.cleanUp() }
        let website = model.addProject(named: "Website", client: nil, color: Palette.colors[0], undoManager: nil)
        let workshop = entry(note: "Workshop", at: "2026-09-22T09:00:00+02:00")
        model.addEntry(workshop, undoManager: nil)
        let line = EntryLineModel(model: model)
        line.show(workshop.id)

        line.text = "web Planning"
        #expect(line.parts?.start == workshop.start)
        #expect(line.parts?.end == workshop.end)
        #expect(line.apply(undoManager: nil))
        #expect(model.resolved.first?.entry.projectID == website)
        #expect(model.resolved.first?.entry.note == "Planning")
        #expect(model.resolved.first?.start == workshop.start)
        #expect(model.resolved.first?.end == workshop.end)
    }

    @Test func refusesALineThatEndsBeforeItStarts() async throws {
        let (harness, model) = await Harness.started()
        defer { harness.cleanUp() }
        let workshop = entry(note: "Workshop", at: "2026-09-22T09:00:00+02:00")
        model.addEntry(workshop, undoManager: nil)
        let line = EntryLineModel(model: model)
        line.show(workshop.id)

        // The entry ends at 10:00 on the 22nd, before this start.
        line.text = "22 sep from 11:00 Workshop"
        #expect(line.parts == nil)
        #expect(line.problem == "That ends before it starts.")
        #expect(!line.refused)
        #expect(!line.apply(undoManager: nil))
        #expect(line.refused)
        #expect(model.resolved.first?.end == workshop.end)

        line.text = "22 sep 9:00-10:00 Workshop"
        #expect(!line.refused)
        #expect(line.problem == nil)
    }

    @Test func readsAnEntrysLineInTheZoneItWasRecordedIn() async throws {
        let (harness, model) = await Harness.started()
        defer { harness.cleanUp() }
        // 10:00 to 12:00 in New York, which was 16:00 to 18:00 in Berlin,
        // where the device is.
        let start = DateTimeFormat.parse("2026-09-22T10:00:00-04:00")!
        let visit = TimeEntry(start: start, end: start.adding(seconds: 7200), timeZone: "America/New_York", note: "Client visit", updated: start)
        let lunch = TimeEntry(start: start.adding(seconds: 9000), end: start.adding(seconds: 12600), timeZone: "America/New_York", note: "Lunch", updated: start)
        model.addEntry(visit, undoManager: nil)
        model.addEntry(lunch, undoManager: nil)
        let line = EntryLineModel(model: model)

        line.show(visit.id)
        #expect(line.text == "22 sep 10:00-12:00 Client visit")
        #expect(line.parts?.start == visit.start)
        #expect(line.parts?.end == visit.end)

        // The times offered are the day's in New York too.
        line.text = "22 sep 10:00-1"
        #expect(line.suggestions.items.map(\.title) == ["10:00-12:30", "10:00-13:30"])

        line.text = "22 sep 10:00-12:00 Client call"
        #expect(line.apply(undoManager: nil))
        let edited = model.resolved.first { $0.id == visit.id }
        #expect(edited?.entry.note == "Client call")
        #expect(edited?.start == visit.start)
        #expect(edited?.end == visit.end)
    }
}
