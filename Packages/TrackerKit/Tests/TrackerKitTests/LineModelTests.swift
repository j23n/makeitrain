import Foundation
import Testing
import TrackerCore
@testable import TrackerKit

/// The command line's and an entry's line as the fields use them: taking
/// suggestions, going through earlier lines, and applying a line.
@Suite @MainActor struct LineModelTests {
    @Test func takesASuggestionInTheMiddleOfTheLine() async throws {
        let harness = Harness()
        defer { harness.cleanUp() }
        let model = harness.model()
        await model.start()
        model.addProject(named: "Website", client: nil, color: Palette.colors[0], undoManager: nil)
        let line = CommandLineModel(model: model)

        line.text = "web review"
        line.cursor = 3
        #expect(line.suggestions.map(\.title) == ["Website"])
        #expect(line.acceptSuggestion())
        #expect(line.text == "Website review")
        #expect(line.cursor == 8)
        #expect(line.requestedCursor == 8)
        #expect(line.suggestions.isEmpty)
    }

    @Test func aLineBroughtBackHasNoSuggestionsUntilItsChanged() async throws {
        let harness = Harness()
        defer { harness.cleanUp() }
        let model = harness.model()
        await model.start()
        model.addProject(named: "Website", client: nil, color: Palette.colors[0], undoManager: nil)
        model.preferences.remember("web")
        let line = CommandLineModel(model: model)

        // So Up and Down go on through the earlier lines.
        #expect(line.previousLine())
        #expect(line.text == "web")
        #expect(line.suggestions.isEmpty)
        #expect(!line.moveSuggestion(by: -1))

        line.text = "webs"
        #expect(line.suggestions.map(\.title) == ["Website"])
        line.text = "web"
        #expect(line.suggestions.map(\.title) == ["Website"])
    }

    @Test func readsAnEntrysLineAndAppliesIt() async throws {
        let harness = Harness()
        defer { harness.cleanUp() }
        let model = harness.model()
        await model.start()
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

    @Test func aLineWithoutTimesKeepsTheEntrys() async throws {
        let harness = Harness()
        defer { harness.cleanUp() }
        let model = harness.model()
        await model.start()
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
        let harness = Harness()
        defer { harness.cleanUp() }
        let model = harness.model()
        await model.start()
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
}
