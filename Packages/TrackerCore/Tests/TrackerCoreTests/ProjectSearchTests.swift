import Foundation
import Testing
@testable import TrackerCore

@Suite struct ProjectSearchTests {
    /// How well what's typed matches a project, as the command line ranks
    /// projects: 0 best, nil not at all.
    func rank(_ query: String, _ project: String, client: String = "") -> Int? {
        ProjectSearch.rank(ProjectSearch.terms(query), project: project, client: client)
    }

    @Test func matchesAnythingWhenNothingIsTyped() {
        #expect(rank("", "Research") == 0)
        #expect(rank("   ", "Research") == 0)
    }

    @Test func matchesTheClientOrTheProjectAnywhere() {
        #expect(rank("web", "Website redesign", client: "Acme") != nil)
        #expect(rank("WEB", "Website redesign", client: "Acme") != nil)
        #expect(rank("site", "Website redesign", client: "Acme") != nil)
        #expect(rank("glob", "Brand refresh", client: "Globex") != nil)
        #expect(rank("zzz", "Website redesign", client: "Acme") == nil)
    }

    @Test func needsEveryWordTypedInAnyOrder() {
        #expect(rank("acme web", "Website redesign", client: "Acme") != nil)
        #expect(rank("web acme", "Website redesign", client: "Acme") != nil)
        #expect(rank("  acme   web ", "Website redesign", client: "Acme") != nil)
        #expect(rank("globex web", "Website redesign", client: "Acme") == nil)
    }

    @Test func ignoresAccentsAndCase() {
        #expect(rank("cafe", "Café relaunch") == 0)
        #expect(rank("CAFÉ", "Café relaunch") == 0)
    }

    @Test func ranksANameThatStartsWithWhatsTypedFirst() {
        // "Research" starts with "re"; "relaunch", "redesign" and "refresh"
        // are words that do; "Care" only contains it.
        #expect(rank("re", "Research") == 0)
        #expect(rank("re", "Café relaunch") == 1)
        #expect(rank("re", "Website redesign", client: "Acme") == 1)
        #expect(rank("re", "Brand refresh", client: "Globex") == 1)
        #expect(rank("re", "Care plan", client: "Acme") == 2)
    }
}
