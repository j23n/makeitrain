import Foundation
import Testing
@testable import TrackerCore

@Suite struct SuggestionTests {
    typealias F = CommandFixture

    /// Suggestions for the word before the end of `text`, or at `cursor`.
    func suggest(_ text: String, cursor: Int? = nil, editing entryID: UUID? = nil) -> [LineSuggestion] {
        LineSuggestions.suggestions(for: text, cursor: cursor ?? text.utf16.count, in: F.context(F.ledger()), editing: entryID)
    }

    @Test func offersProjectsWhoseNameStartsWithWhatsTyped() throws {
        let first = try #require(suggest("bo").first)
        #expect(first.kind == .project(F.bookings))
        #expect(first.title == "Bookings")
        #expect(first.detail == "Northbridge")
        #expect(first.text == "Bookings ")
        #expect(first.cursor == 9)
        // A client's name finds its projects.
        #expect(suggest("north").map(\.title) == ["Bookings"])
    }

    @Test func offersProjectsOnlyWhereTheLinesProjectGoes() {
        #expect(suggest("book ha").isEmpty)
        #expect(suggest("book review fi").isEmpty)
    }

    @Test func replacesTheWordAtTheInsertionPoint() throws {
        let first = try #require(suggest("bo review", cursor: 2).first)
        #expect(first.text == "Bookings review")
        #expect(first.cursor == 9)
    }

    @Test func offersCommandsAtTheStartButNotForAnEntry() {
        let stop = suggest("st").first { $0.kind == .keyword }
        #expect(stop?.title == "stop")
        #expect(stop?.text == "stop ")
        #expect(stop?.cursor == 5)
        #expect(suggest("st", editing: uuid(105)).isEmpty)
    }

    @Test func offersTheTagsOfTheLinesProject() throws {
        let issue = try #require(suggest("book #2").first)
        #expect(issue.kind == .tag)
        #expect(issue.title == "#227")
        #expect(issue.text == "book #227 ")
        #expect(suggest("book #d").map(\.title) == ["#Daily"])
        // Harbor has no tags of its own.
        #expect(suggest("harbor #d").isEmpty)
    }

    @Test func offersEveryTagWithoutAProject() {
        let context = F.context(F.ledger([F.entry(108, F.harbor, "2026-10-01", "09:00", "10:00", tags: ["#9"], note: "Fix")]))
        #expect(LineSuggestions.suggestions(for: "#", cursor: 1, in: context).map(\.title) == ["#9", "#227", "#Daily"])
    }

    @Test func writesTagsSoTheLineReadsThemBack() throws {
        let context = F.context(F.ledger([
            F.entry(108, F.inHouse, "2026-10-01", "09:00", "10:00", tags: ["C#"], note: "Tooling"),
            F.entry(109, F.inHouse, "2026-10-02", "09:00", "10:00", tags: ["code review"], note: "Refactor"),
        ]))
        let tag = try #require(LineSuggestions.suggestions(for: "internal #c", cursor: 11, in: context).first)
        #expect(tag.title == "#C#")
        #expect(CommandReading(tag.text, in: context).draft?.tags == ["C#"])
        // A tag with spaces is written with dashes, typed so too.
        let review = try #require(LineSuggestions.suggestions(for: "internal #code-r", cursor: 16, in: context).first)
        #expect(review.title == "#code-review")
        #expect(review.text == "internal #code-review ")
        #expect(CommandReading(review.text, in: context).draft?.tags == ["code review"])
    }

    @Test func offersTheDaysStartsAndEndsWhereATimeGoes() throws {
        let end = try #require(suggest("book from 9").first)
        #expect(end.kind == .time)
        #expect(end.title == "9:00")
        #expect(end.detail == "end of Planning")
        #expect(end.text == "book from 9:00 ")
        #expect(end.cursor == 15)
        // After a start and a dash, the ends after it.
        #expect(suggest("book 8:00-").map(\.title) == ["8:00-9:00"])
        #expect(suggest("8").map(\.title) == ["8:00"])
        #expect(suggest("book till 9").map(\.title) == ["9:00"])
    }

    @Test func leavesTheEditedEntrysOwnTimesOut() {
        #expect(suggest("8", editing: uuid(105)).isEmpty)
    }

    @Test func offersWhatACommandActsOn() {
        #expect(suggest("archive ha").first?.text == "archive Harbor ")
        // Before anything's typed, the projects used last.
        #expect(suggest("archive ").map(\.title) == ["Internal", "Bookings", "Harbor"])
        #expect(suggest("merge book into ").contains { $0.kind == .project(F.harbor) })
        #expect(suggest("color book t").map(\.title) == ["teal"])
        #expect(suggest("new project Phoenix for ze").map(\.title) == ["Zenith"])
        #expect(suggest("rename book to Bo").isEmpty)
    }
}
