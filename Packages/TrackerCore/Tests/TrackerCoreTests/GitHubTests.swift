import Foundation
import Testing
@testable import TrackerCore

@Suite struct GitHubTests {
    @Test(arguments: [
        "j23n/makeitrain",
        " j23n/makeitrain ",
        "github.com/j23n/makeitrain",
        "https://github.com/j23n/makeitrain",
        "https://github.com/j23n/makeitrain/",
        "https://github.com/j23n/makeitrain.git",
        "https://github.com/j23n/makeitrain/issues/12",
        "http://GitHub.com/j23n/makeitrain",
        "git@github.com:j23n/makeitrain.git",
    ])
    func readsRepositories(_ text: String) throws {
        let repository = try #require(GitHub.Repository(text))
        #expect(repository.address == "https://github.com/j23n/makeitrain")
        #expect(repository.title == "j23n/makeitrain")
    }

    @Test func readsEnterpriseRepositories() throws {
        let repository = try #require(GitHub.Repository("https://github.acme.example/web/site"))
        #expect(repository.address == "https://github.acme.example/web/site")
        #expect(repository.title == "github.acme.example/web/site")
        #expect(GitHub.Repository("github.acme.example/web/site")?.host == "github.acme.example")
    }

    @Test(arguments: ["", "makeitrain", "github.com/j23n", "j23n/make it rain", "https://github.com", "owner/rep\u{F6}"])
    func refusesWhatIsntARepository(_ text: String) {
        #expect(GitHub.Repository(text) == nil)
    }

    @Test func readsReferences() {
        #expect(GitHub.Reference(tag: "#123") == GitHub.Reference(tag: "#123"))
        #expect(GitHub.Reference(tag: "#123")?.number == 123)
        #expect(GitHub.Reference(tag: "#123")?.repository == nil)
        #expect(GitHub.Reference(tag: "api#7")?.repository == "api")
        #expect(GitHub.Reference(tag: "acme/api#7")?.repository == "acme/api")
        for tag in ["design", "#", "#abc", "#12a", "#0", "# 12", "#12 login", "a/b/c#1", "/api#1", "#1234567890"] {
            #expect(GitHub.Reference(tag: tag) == nil, "\(tag)")
        }
    }

    @Test func linksTagsToIssuesInTheProjectsRepositories() {
        let repositories = ["https://github.com/acme/web", "https://github.com/acme/api"]
        func url(_ tag: String, _ repositories: [String]) -> String? {
            GitHub.url(forTag: tag, repositories: repositories)?.absoluteString
        }
        // The first repository unless the tag names another.
        #expect(url("#12", repositories) == "https://github.com/acme/web/issues/12")
        #expect(url("api#3", repositories) == "https://github.com/acme/api/issues/3")
        #expect(url("API#3", repositories) == "https://github.com/acme/api/issues/3")
        #expect(url("acme/api#3", repositories) == "https://github.com/acme/api/issues/3")
        // Any repository, written with its owner.
        #expect(url("other/lib#5", repositories) == "https://github.com/other/lib/issues/5")
        // A name the project doesn't have, or a project without repositories.
        #expect(url("docs#3", repositories) == nil)
        #expect(url("#12", []) == nil)
        #expect(url("design", repositories) == nil)
        // An owner and name on the project's own server.
        #expect(url("team/tools#9", ["https://github.acme.example/web/site"]) == "https://github.acme.example/team/tools/issues/9")
    }

    @Test func tagsKeepTheirIssueWhenRepositoriesChange() {
        let now = t("2026-09-24T09:00:00Z")
        let web = "https://github.com/acme/web"
        let api = "https://github.com/acme/api"
        func entry(_ number: Int, project: UUID, tags: [String]) -> TimeEntry {
            TimeEntry(
                id: uuid(number), projectID: project,
                start: t("2026-09-23T09:00:00+02:00"), end: t("2026-09-23T10:00:00+02:00"),
                timeZone: "Europe/Berlin", tags: tags, updated: t("2026-09-23T10:00:00+02:00")
            )
        }
        var ledger = Ledger(
            projects: [
                Project(id: uuid(10), name: "Website", repositories: [web], updated: now),
                Project(id: uuid(11), name: "Other", repositories: [web], updated: now),
            ],
            entries: [
                entry(1, project: uuid(10), tags: ["#12", "design", "api#3"]),
                entry(2, project: uuid(11), tags: ["#12"]),
            ]
        )
        func tags(_ number: Int) -> [String] {
            ledger.entries[uuid(number)]?.tags ?? []
        }

        // A second repository changes nothing, and gives "api#3" its link.
        ledger.setRepositories([web, api], ofProject: uuid(10), now: now)
        #expect(tags(1) == ["#12", "design", "api#3"])
        #expect(ledger.issueURL(forTag: "api#3", projectID: uuid(10))?.absoluteString == "https://github.com/acme/api/issues/3")

        // Making another repository the first names the one "#12" meant.
        let changes = ledger.setRepositories([api, web], ofProject: uuid(10), now: now)
        #expect(tags(1) == ["web#12", "design", "api#3"])
        #expect(ledger.issueURL(forTag: "web#12", projectID: uuid(10))?.absoluteString == "https://github.com/acme/web/issues/12")
        let september: Set<MonthKey> = [MonthKey(year: 2026, month: 9)]
        #expect(changes.projects)
        #expect(changes.months == september)
        // Other projects keep their tags.
        #expect(tags(2) == ["#12"])

        // Removing a repository keeps its owner in the tags, which still open it.
        ledger.updateEntry(uuid(1), now: now) { $0.tags.append("#7") }
        ledger.setRepositories([web], ofProject: uuid(10), now: now)
        #expect(tags(1) == ["web#12", "design", "acme/api#3", "acme/api#7"])
        #expect(ledger.issueURL(forTag: "acme/api#7", projectID: uuid(10))?.absoluteString == "https://github.com/acme/api/issues/7")

        // Removing the last one leaves the tags for the next repository.
        ledger.setRepositories([], ofProject: uuid(11), now: now)
        #expect(tags(2) == ["#12"])
    }

    @Test func tagsKeepTheirRepositoryAmongNamesakes() {
        let now = t("2026-09-24T09:00:00Z")
        let ours = "https://github.com/acme/api"
        let theirs = "https://github.com/other/api"
        var ledger = Ledger(
            projects: [Project(id: uuid(10), name: "App", repositories: [ours, theirs], updated: now)],
            entries: [
                TimeEntry(
                    id: uuid(1), projectID: uuid(10),
                    start: t("2026-09-23T09:00:00+02:00"), end: t("2026-09-23T10:00:00+02:00"),
                    timeZone: "Europe/Berlin", tags: ["api#1", "#2"], updated: t("2026-09-23T10:00:00+02:00")
                ),
            ]
        )
        ledger.setRepositories([theirs, ours], ofProject: uuid(10), now: now)
        #expect(ledger.entries[uuid(1)]?.tags == ["acme/api#1", "acme/api#2"])
    }

    @Test func findsTheLinksOfAnEntrysTags() {
        let ledger = Ledger(projects: [
            Project(id: uuid(10), name: "Website", repositories: ["https://github.com/acme/web"], updated: t("2026-09-23T09:00:00Z")),
            Project(id: uuid(11), name: "Internal", updated: t("2026-09-23T09:00:00Z")),
        ])
        let links = ledger.issueLinks(tags: ["design", "#12"], projectID: uuid(10))
        #expect(links.keys.sorted() == ["#12"])
        #expect(links["#12"]?.absoluteString == "https://github.com/acme/web/issues/12")
        #expect(ledger.issueLinks(tags: ["#12"], projectID: uuid(11)).isEmpty)
        #expect(ledger.issueURL(forTag: "#12", projectID: nil) == nil)
    }
}
