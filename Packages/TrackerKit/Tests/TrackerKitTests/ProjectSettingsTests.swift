import Foundation
import Testing
import TrackerCore
@testable import TrackerKit

@Suite @MainActor struct ProjectSettingsTests {
    @Test func addsAndOrdersRepositories() async throws {
        let harness = Harness()
        defer { harness.cleanUp() }
        let model = harness.model()
        await model.start()
        let undo = UndoManager()
        undo.groupsByEvent = false
        let project = model.addProject(named: "Website", client: nil, color: "#4F7CAC", undoManager: nil)

        #expect(model.addRepository("acme/web", toProject: project, undoManager: nil))
        #expect(model.addRepository("https://github.com/acme/api.git", toProject: project, undoManager: nil))
        // The same repository again changes nothing, and nonsense is refused.
        #expect(model.addRepository("https://github.com/ACME/web/issues", toProject: project, undoManager: nil))
        #expect(!model.addRepository("not a repository", toProject: project, undoManager: nil))
        #expect(model.ledger.projects[project]?.repositories == ["https://github.com/acme/web", "https://github.com/acme/api"])
        #expect(model.ledger.issueURL(forTag: "#7", projectID: project)?.absoluteString == "https://github.com/acme/web/issues/7")

        var tagged = entry(note: "Hero", at: "2026-09-22T09:00:00+02:00")
        tagged.projectID = project
        tagged.tags = ["#7"]
        model.addEntry(tagged, undoManager: nil)

        undo.beginUndoGrouping()
        model.makeFirstRepository("https://github.com/acme/api", ofProject: project, undoManager: undo)
        undo.endUndoGrouping()
        #expect(model.ledger.issueURL(forTag: "#7", projectID: project)?.absoluteString == "https://github.com/acme/api/issues/7")
        // The entry's "#7" meant the web repository, and still does.
        #expect(model.ledger.entries[tagged.id]?.tags == ["web#7"])
        // Undo puts back both the order and the tag.
        undo.undo()
        #expect(model.ledger.projects[project]?.repositories.first == "https://github.com/acme/web")
        #expect(model.ledger.entries[tagged.id]?.tags == ["#7"])

        model.removeRepository("https://github.com/acme/web", fromProject: project, undoManager: nil)
        #expect(model.ledger.projects[project]?.repositories == ["https://github.com/acme/api"])
    }

    @Test func linksOneCalendarToEachProject() async throws {
        let harness = Harness()
        defer { harness.cleanUp() }
        let calendars = FakeCalendars()
        calendars.list = [
            CalendarInfo(id: "acme", title: "Calendar", account: "jo@acme.example"),
            CalendarInfo(id: "globex", title: "Globex", account: "Google"),
        ]
        let model = harness.model(calendars: calendars)
        await model.start()
        model.refreshCalendars()
        let website = model.addProject(named: "Website", client: nil, color: "#4F7CAC", undoManager: nil)
        let brand = model.addProject(named: "Brand", client: nil, color: "#9BBB59", undoManager: nil)

        model.setCalendar("acme", forProject: website)
        #expect(model.linkedCalendar(ofProject: website)?.id == "acme")
        #expect(model.linkedProject(of: "acme") == website)

        // Choosing another calendar replaces the project's link.
        model.setCalendar("globex", forProject: website)
        #expect(model.linkedCalendar(ofProject: website)?.id == "globex")
        #expect(model.linkedProject(of: "acme") == nil)

        // A calendar belongs to one project: taking it moves it.
        model.setCalendar("globex", forProject: brand)
        #expect(model.linkedCalendar(ofProject: brand)?.id == "globex")
        #expect(model.linkedCalendar(ofProject: website) == nil)

        model.setCalendar(nil, forProject: brand)
        #expect(model.calendarLinks.isEmpty)
    }

    @Test func renamesATagInOneProject() async throws {
        let harness = Harness()
        defer { harness.cleanUp() }
        let model = harness.model()
        await model.start()
        let website = model.addProject(named: "Website", client: nil, color: "#4F7CAC", undoManager: nil)
        let brand = model.addProject(named: "Brand", client: nil, color: "#9BBB59", undoManager: nil)
        var first = entry(note: "Hero", at: "2026-09-22T09:00:00+02:00")
        first.projectID = website
        first.tags = ["design"]
        var second = entry(note: "Logo", at: "2026-09-22T11:00:00+02:00")
        second.projectID = brand
        second.tags = ["design"]
        model.addEntry(first, undoManager: nil)
        model.addEntry(second, undoManager: nil)

        model.renameTag("design", to: "UX", inProject: website, undoManager: nil)
        #expect(model.projectTags[website] == ["UX"])
        #expect(model.projectTags[brand] == ["design"])

        model.removeTag("design", fromProject: brand, undoManager: nil)
        #expect(model.projectTags[brand] == nil)
        #expect(model.projectTags[website] == ["UX"])

        // Renaming to another of the project's tags merges the two, in that
        // tag's spelling, and an empty name changes nothing.
        var third = entry(note: "Interviews", at: "2026-09-22T13:00:00+02:00")
        third.projectID = website
        third.tags = ["Research"]
        model.addEntry(third, undoManager: nil)
        model.renameTag("UX", to: " research", inProject: website, undoManager: nil)
        #expect(model.projectTags[website] == ["Research"])
        model.renameTag("Research", to: " ", inProject: website, undoManager: nil)
        #expect(model.projectTags[website] == ["Research"])
    }
}
