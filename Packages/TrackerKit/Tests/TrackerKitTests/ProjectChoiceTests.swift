import Foundation
import Testing
import TrackerCore
@testable import TrackerKit

@Suite struct ProjectChoiceTests {
    let now = DateTimeFormat.parse("2026-09-23T12:00:00Z")!
    let acme = UUID(), website = UUID(), app = UUID(), admin = UUID()

    var ledger: Ledger {
        Ledger(
            clients: [Client(id: acme, name: "Acme", updated: now)],
            projects: [
                Project(id: website, clientID: acme, name: "Website redesign", updated: now),
                Project(id: app, clientID: acme, name: "Mobile app", updated: now),
                Project(id: admin, name: "Admin", archived: true, updated: now),
            ]
        )
    }

    @Test func listsNoProjectFirstWhenNothingIsTyped() {
        #expect(ProjectChoice.options(in: ledger, matching: "", current: nil) == [.noProject, .project(app), .project(website)])
    }

    @Test func narrowsToWhatsTyped() {
        #expect(ProjectChoice.options(in: ledger, matching: "web", current: nil) == [.project(website)])
        #expect(ProjectChoice.options(in: ledger, matching: "acme", current: nil) == [.project(app), .project(website)])
        #expect(ProjectChoice.options(in: ledger, matching: "no", current: nil) == [.noProject])
    }

    @Test func keepsTheChosenArchivedProject() {
        #expect(ProjectChoice.options(in: ledger, matching: "", current: admin) == [.noProject, .project(app), .project(website), .project(admin)])
        #expect(ProjectChoice.options(in: ledger, matching: "adm", current: admin) == [.project(admin)])
    }

    @Test func canLeaveOutNoProjectAndOneProject() {
        #expect(ProjectChoice.options(in: ledger, matching: "", current: nil, offersNoProject: false, excluding: website) == [.project(app)])
    }

    @Test func convertsFromAnOptionalProject() {
        #expect(ProjectChoice(nil) == .noProject)
        #expect(ProjectChoice(website) == .project(website))
        #expect(ProjectChoice.project(website).projectID == website)
        #expect(ProjectChoice.noProject.projectID == nil)
    }
}
