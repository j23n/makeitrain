import Foundation
import Testing
@testable import TrackerCore

@Suite struct ProjectSearchTests {
    let now = t("2026-09-23T12:00:00Z")

    var ledger: Ledger {
        Ledger(
            clients: [
                Client(id: uuid(20), name: "Acme", updated: now),
                Client(id: uuid(21), name: "Globex", updated: now),
            ],
            projects: [
                Project(id: uuid(10), clientID: uuid(20), name: "Website redesign", updated: now),
                Project(id: uuid(11), clientID: uuid(20), name: "Care plan", updated: now),
                Project(id: uuid(12), clientID: uuid(21), name: "Brand refresh", updated: now),
                Project(id: uuid(13), name: "Research", updated: now),
                Project(id: uuid(14), name: "Café relaunch", updated: now),
                Project(id: uuid(15), name: "Admin", archived: true, updated: now),
            ]
        )
    }

    func titles(_ query: String, including extra: UUID? = nil) -> [String] {
        let ledger = ledger
        return ledger.pickerProjects(matching: query, including: extra).map { ledger.projectTitle($0.id) }
    }

    @Test func offersEveryLiveProjectWhenNothingIsTyped() {
        #expect(titles("") == ["Café relaunch", "Research", "Acme › Care plan", "Acme › Website redesign", "Globex › Brand refresh"])
        #expect(titles("   ") == titles(""))
    }

    @Test func matchesTheClientOrTheProjectAnywhere() {
        #expect(titles("web") == ["Acme › Website redesign"])
        #expect(titles("WEB") == ["Acme › Website redesign"])
        #expect(titles("site") == ["Acme › Website redesign"])
        #expect(titles("glob") == ["Globex › Brand refresh"])
        #expect(titles("zzz").isEmpty)
    }

    @Test func needsEveryWordTypedInAnyOrder() {
        #expect(titles("acme web") == ["Acme › Website redesign"])
        #expect(titles("web acme") == ["Acme › Website redesign"])
        #expect(titles("  acme   web ") == ["Acme › Website redesign"])
        #expect(titles("globex web").isEmpty)
    }

    @Test func ignoresAccentsAndCase() {
        #expect(titles("cafe") == ["Café relaunch"])
        #expect(titles("CAFÉ") == ["Café relaunch"])
    }

    @Test func listsTheBestMatchesFirst() {
        // "Research" starts with "re"; "relaunch", "redesign" and "refresh"
        // are words that do; "Care" only contains it.
        #expect(titles("re") == [
            "Research",
            "Café relaunch",
            "Acme › Website redesign",
            "Globex › Brand refresh",
            "Acme › Care plan",
        ])
    }

    @Test func offersAnArchivedProjectOnlyWhenItsAlreadyChosen() {
        #expect(titles("admin").isEmpty)
        #expect(titles("admin", including: uuid(15)) == ["Admin"])
        #expect(titles("", including: uuid(15)).last == "Admin")
        #expect(titles("web", including: uuid(15)) == ["Acme › Website redesign"])
        // A live project isn't listed twice.
        #expect(titles("web", including: uuid(10)) == ["Acme › Website redesign"])
    }

    @Test func offersNoProjectWhenNothingOrItIsTyped() {
        #expect(ProjectSearch.matchesNoProject(""))
        #expect(ProjectSearch.matchesNoProject("no"))
        #expect(ProjectSearch.matchesNoProject("No proj"))
        #expect(ProjectSearch.matchesNoProject("unass"))
        #expect(!ProjectSearch.matchesNoProject("web"))
        #expect(!ProjectSearch.matchesNoProject("no web"))
    }
}
