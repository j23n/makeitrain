import Foundation
import Testing
import TrackerCore
@testable import TrackerKit

/// New entries drawn on the week, their lines, and overlaps shown whether
/// or not an entry is chosen.
@Suite @MainActor struct NewEntryTests {
    /// Monday, September 21, to Sunday, September 27. The harness's now is
    /// Wednesday the 23rd at 9:00 in Berlin.
    let days = LocalDate(year: 2026, month: 9, day: 21)...LocalDate(year: 2026, month: 9, day: 27)
    let tuesday = LocalDate(year: 2026, month: 9, day: 22)

    func hm(_ hour: Int, _ minute: Int) -> Int {
        hour * 3600 + minute * 60
    }

    @Test func aNewEntrysLineStartsWithItsTimesAndSaves() async throws {
        let (harness, model) = await Harness.started()
        defer { harness.cleanUp() }
        let website = model.addProject(named: "Website", client: nil, color: Palette.colors[0], undoManager: nil)
        let draft = model.newEntryDraft(on: tuesday, startSecond: hm(14, 15), endSecond: hm(16, 30))
        let line = EntryLineModel(model: model)

        line.showNew(draft)
        #expect(line.text == "22 sep 14:15-16:30 ")
        line.text += "web Review"
        #expect(line.parts?.draft.projectID == website)
        #expect(line.parts?.draft.note == "Review")
        #expect(line.parts?.start == draft.start)
        #expect(line.parts?.end == draft.end)
        // Nothing is saved until the line is.
        #expect(model.ledger.entries[draft.id] == nil)

        #expect(line.apply(undoManager: nil))
        let saved = try #require(model.ledger.entries[draft.id])
        #expect(saved.projectID == website)
        #expect(saved.note == "Review")
        #expect(saved.start == draft.start)
        #expect(saved.end == draft.end)
    }

    @Test func aNewEntrysLineWithoutTimesKeepsTheDrawnOnes() async throws {
        let (harness, model) = await Harness.started()
        defer { harness.cleanUp() }
        model.addProject(named: "Website", client: nil, color: Palette.colors[0], undoManager: nil)
        let draft = model.newEntryDraft(on: tuesday, startSecond: hm(10, 0), endSecond: hm(11, 0))
        let line = EntryLineModel(model: model)
        line.showNew(draft)

        line.text = "web Review"
        #expect(line.parts?.start == draft.start)
        #expect(line.parts?.end == draft.end)
    }

    @Test func draggingTheNewEntryChangesTheTimesInItsLine() async throws {
        let (harness, model) = await Harness.started()
        defer { harness.cleanUp() }
        let draft = model.newEntryDraft(on: tuesday, startSecond: hm(14, 15), endSecond: hm(16, 30))
        let line = EntryLineModel(model: model)
        line.showNew(draft)
        line.text += "Review"

        var moved = draft
        moved.startSecond = hm(15, 0)
        line.retime(moved)
        #expect(line.text == "22 sep 15:00-16:30 Review")

        // Times typed over the drawn ones stay as typed.
        line.text = "22 sep 10:00-11:00 Review"
        var again = moved
        again.endSecond = hm(17, 0)
        line.retime(again)
        #expect(line.text == "22 sep 10:00-11:00 Review")
    }

    @Test func aNewEntryEndsByNowOnToday() async throws {
        let (harness, model) = await Harness.started()
        defer { harness.cleanUp() }
        #expect(model.latestNewEntryEnd(on: LocalDate(year: 2026, month: 9, day: 23)) == hm(9, 0))
        #expect(model.latestNewEntryEnd(on: tuesday) == NewEntrySpan.lastEnd)
    }

    @Test func choosingAnEntryDropsTheNewOne() async throws {
        let (harness, model) = await Harness.started()
        defer { harness.cleanUp() }
        let workshop = entry(note: "Workshop", at: "2026-09-22T09:00:00+02:00")
        model.addEntry(workshop, undoManager: nil)
        let week = WeekModel(model: model, days: days)

        week.selectedEntry = workshop.id
        week.newEntry = model.newEntryDraft(on: tuesday, startSecond: hm(14, 0), endSecond: hm(15, 0))
        #expect(week.selectedEntry == nil)
        week.selectedEntry = workshop.id
        #expect(week.newEntry == nil)
    }

    @Test func overlapsShowWhetherOrNotAnEntryIsChosen() async throws {
        let (harness, model) = await Harness.started()
        defer { harness.cleanUp() }
        let website = model.addProject(named: "Website", client: nil, color: Palette.colors[0], undoManager: nil)
        var header = entry(note: "Header", at: "2026-09-22T09:00:00+02:00")
        var push = entry(note: "Push", at: "2026-09-22T09:30:00+02:00")
        var later = entry(note: "Later", at: "2026-09-22T14:00:00+02:00")
        header.projectID = website
        push.projectID = website
        later.projectID = website
        for item in [header, push, later] {
            model.addEntry(item, undoManager: nil)
        }
        let week = WeekModel(model: model, days: days)

        week.selectedEntry = header.id
        #expect(week.isInOverlap(header.id))
        #expect(week.isInOverlap(push.id))
        #expect(!week.isInOverlap(later.id))
        let about = week.previews(involving: header.id)
        #expect(about.count == 1)
        if case let .overlap(overlap)? = about.first?.correction.kind {
            #expect(overlap.earlier == header.id)
            #expect(overlap.later == push.id)
        } else {
            Issue.record("Expected the overlap")
        }
        #expect(week.previews(involving: later.id).isEmpty)
    }
}
