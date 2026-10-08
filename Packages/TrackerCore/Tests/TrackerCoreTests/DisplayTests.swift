import Foundation
import Testing
@testable import TrackerCore

@Suite struct DisplayTests {
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

    func entry(_ number: Int, project: UUID?, tags: [String] = [], at time: String) -> TimeEntry {
        TimeEntry(
            id: uuid(number),
            projectID: project,
            start: t("2026-09-\(time)+02:00"),
            end: t("2026-09-\(time)+02:00").adding(seconds: 600),
            timeZone: "Europe/Berlin",
            tags: tags,
            updated: now
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
        ledger.merge(entry(1, project: nil, tags: ["design", "Call"], at: "20T09:00:00"))
        ledger.merge(entry(2, project: nil, tags: ["Design"], at: "21T09:00:00"))
        var deleted = entry(3, project: nil, tags: ["secret"], at: "22T09:00:00")
        deleted.deleted = now
        ledger.merge(deleted)
        #expect(ledger.allTags() == ["Call", "Design"])
    }

    @Test func listsEachProjectsOwnTags() {
        var ledger = ledger
        ledger.merge(entry(1, project: uuid(10), tags: ["design", "#12"], at: "20T09:00:00"))
        ledger.merge(entry(2, project: uuid(10), tags: ["#9"], at: "21T09:00:00"))
        ledger.merge(entry(3, project: uuid(11), tags: ["admin", "Design"], at: "21T10:00:00"))
        ledger.merge(entry(4, project: nil, tags: ["email"], at: "22T09:00:00"))
        ledger.merge(entry(5, project: uuid(13), at: "22T10:00:00"))
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
        #expect(combination.matches(entry(1, project: uuid(10), tags: ["#12", "Design"], at: "22T09:00:00")))
        #expect(!combination.matches(entry(2, project: uuid(10), tags: ["design"], at: "22T09:00:00")))
        #expect(!combination.matches(entry(3, project: uuid(11), tags: ["design", "#12"], at: "22T09:00:00")))
        #expect(Combination(projectID: nil, tags: []).matches(entry(4, project: nil, at: "22T09:00:00")))
    }
}
