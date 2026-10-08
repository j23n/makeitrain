import Foundation
import Testing
@testable import TrackerCore

@Suite struct DisplayTests {
    typealias F = CommandFixture
    let now = t("2026-09-23T12:00:00Z")

    var ledger: Ledger {
        Ledger(
            clients: [
                Client(id: uuid(20), name: "Acme", updated: now),
                Client(id: uuid(21), name: "Old Client", archived: true, updated: now),
            ],
            projects: [
                Project(id: uuid(10), clientID: uuid(20), name: "Website", updated: now),
                Project(id: uuid(11), name: "Internal", updated: now),
                Project(id: uuid(12), clientID: uuid(21), name: "Legacy", updated: now),
                Project(id: uuid(13), clientID: uuid(20), name: "App", archived: true, updated: now),
                Project(id: uuid(14), clientID: uuid(20), name: "Gone", updated: now, deleted: now),
            ]
        )
    }

    @Test func titlesProjects() {
        #expect(ledger.projectTitle(uuid(10)) == "Acme › Website")
        #expect(ledger.projectTitle(uuid(11)) == "Internal")
        #expect(ledger.projectTitle(nil) == "Unassigned")
        #expect(ledger.projectTitle(uuid(99)) == "Unknown project")
        // A deleted project keeps its name.
        #expect(ledger.projectTitle(uuid(14)) == "Acme › Gone")
    }

    @Test func titlesEntriesByTheirNoteOrProject() {
        #expect(ledger.title(of: F.entry(1, uuid(10), "2026-09-22", "09:00", "10:00", note: "Wireframes")) == "Wireframes")
        #expect(ledger.title(of: F.entry(2, uuid(10), "2026-09-22", "10:00", "11:00")) == "Acme › Website")
        #expect(ledger.title(of: F.entry(3, nil, "2026-09-22", "11:00", "12:00")) == "Unassigned")
    }

    @Test func archivedIncludesDeletedProjectsAndArchivedClients() {
        #expect(!ledger.isArchived(project: uuid(10)))
        #expect(ledger.isArchived(project: uuid(12)))
        #expect(ledger.isArchived(project: uuid(13)))
        #expect(ledger.isArchived(project: uuid(14)))
        #expect(ledger.isArchived(project: uuid(99)))
    }

    @Test func pickersShowLiveProjectsByClient() {
        #expect(ledger.pickerProjects().map(\.id) == [uuid(11), uuid(10)])
        #expect(ledger.liveClients().map(\.name) == ["Acme", "Old Client"])
    }

    @Test func listsTagsOnceWithTheLatestSpelling() {
        var ledger = ledger
        ledger.merge(F.entry(1, nil, "2026-09-20", "09:00", "10:00", tags: ["design", "Call"]))
        ledger.merge(F.entry(2, nil, "2026-09-21", "09:00", "10:00", tags: ["Design"]))
        var deleted = F.entry(3, nil, "2026-09-22", "09:00", "10:00", tags: ["secret"])
        deleted.deleted = now
        ledger.merge(deleted)
        #expect(ledger.allTags() == ["Call", "Design"])
    }

    @Test func listsEachProjectsOwnTags() {
        var ledger = ledger
        ledger.merge(F.entry(1, uuid(10), "2026-09-20", "09:00", "10:00", tags: ["design", "#12"]))
        ledger.merge(F.entry(2, uuid(10), "2026-09-21", "09:00", "10:00", tags: ["#9"]))
        ledger.merge(F.entry(3, uuid(11), "2026-09-21", "10:00", "11:00", tags: ["admin", "Design"]))
        ledger.merge(F.entry(4, nil, "2026-09-22", "09:00", "10:00", tags: ["email"]))
        ledger.merge(F.entry(5, uuid(13), "2026-09-22", "10:00", "11:00"))
        let byProject = ledger.tagsByProject()
        #expect(byProject[uuid(10)] == ["#9", "#12", "design"])
        #expect(byProject[uuid(11)] == ["admin", "Design"])
        #expect(byProject[nil] == ["email"])
        // A project without tags is left out.
        #expect(byProject[uuid(13)] == nil)
        #expect(byProject.count == 3)
    }

    @Test func matchesEntriesWithTheSameProjectAndTags() {
        let combination = Combination(projectID: uuid(10), tags: ["design", "#12"])
        #expect(combination.matches(F.entry(1, uuid(10), "2026-09-22", "09:00", "10:00", tags: ["#12", "Design"])))
        #expect(!combination.matches(F.entry(2, uuid(10), "2026-09-22", "09:00", "10:00", tags: ["design"])))
        #expect(!combination.matches(F.entry(3, uuid(11), "2026-09-22", "09:00", "10:00", tags: ["design", "#12"])))
        #expect(Combination(projectID: nil, tags: []).matches(F.entry(4, nil, "2026-09-22", "09:00", "10:00")))
    }
}
