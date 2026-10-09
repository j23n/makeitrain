import Foundation
import Testing
import TrackerCore
@testable import TrackerKit

@Suite struct ProjectOverviewTests {
    let now = DateTimeFormat.parse("2026-09-23T15:40:00+02:00")!
    /// A Wednesday.
    let today = LocalDate(year: 2026, month: 9, day: 23)
    let hour: Int64 = 3_600_000

    // Acme has Website, with two repositories, and App.
    let acme = UUID()
    let website = UUID(), app = UUID()

    var ledger: Ledger {
        Ledger(
            clients: [Client(id: acme, name: "Acme", updated: now)],
            projects: [
                Project(
                    id: website,
                    clientID: acme,
                    name: "Website",
                    color: "#111111",
                    repositories: ["https://github.com/acme/web", "https://github.com/acme/api"],
                    updated: now
                ),
                Project(id: app, clientID: acme, name: "App", color: "#222222", updated: now),
            ]
        )
    }

    /// An entry in Berlin, such as `entry(website, "09-23T09:00", "09-23T10:30")`,
    /// or running without an end.
    func entry(_ project: UUID?, _ start: String, _ end: String?, tags: [String] = []) -> TimeEntry {
        let startTime = DateTimeFormat.parse("2026-\(start):00+02:00")!
        let endTime = end.map { DateTimeFormat.parse("2026-\($0):00+02:00")! }
        return TimeEntry(projectID: project, start: startTime, end: endTime, timeZone: "Europe/Berlin", tags: tags, updated: startTime)
    }

    func overview(_ entries: [TimeEntry], of project: UUID) -> ProjectOverview {
        var ledger = ledger
        for entry in entries { ledger.merge(entry) }
        return ProjectOverview(project: project, ledger: ledger, resolved: ledger.resolvedEntries(), today: today, firstWeekday: 2, now: now)
    }

    @Test func addsUpThisWeekThisMonthAndAllTime() {
        let result = overview([
            entry(website, "07-01T09:00", "07-01T11:00"),
            entry(website, "09-02T09:00", "09-02T10:00"),
            entry(website, "09-21T09:00", "09-21T12:00"),
            // Running for an hour so far.
            entry(website, "09-23T14:40", nil),
            entry(app, "09-22T09:00", "09-22T17:00"),
        ], of: website)

        #expect(result.thisWeek == 4 * hour)
        #expect(result.thisMonth == 5 * hour)
        #expect(result.total == 7 * hour)
        #expect(result.entryCount == 4)
        #expect(result.firstDay == LocalDate(year: 2026, month: 7, day: 1))
        #expect(result.isRunning)
        #expect(result.longTimer?.day == nil)
    }

    @Test func findsThisMonthsFirstTimerThatRanLong() {
        let result = overview([
            // Last month's, and another project's, don't count.
            entry(website, "08-31T08:00", "08-31T21:00"),
            entry(app, "09-02T08:00", "09-02T21:00"),
            entry(website, "09-10T08:00", "09-10T21:30"),
            // Past midnight into the morning.
            entry(website, "09-17T20:00", "09-18T06:00"),
        ], of: website)

        #expect(result.longTimer?.day == LocalDate(year: 2026, month: 9, day: 10))
        #expect(result.longTimer?.length == 13 * hour + hour / 2)
        #expect(result.longTimer?.overnight == false)

        let overnight = overview([entry(website, "09-17T20:00", "09-18T06:00")], of: website)
        #expect(overnight.longTimer?.day == LocalDate(year: 2026, month: 9, day: 17))
        #expect(overnight.longTimer?.length == 10 * hour)
        #expect(overnight.longTimer?.overnight == true)
    }

    @Test func groupsTheTagsThatReferToIssuesByRepository() {
        let result = overview([
            entry(website, "09-21T09:00", "09-21T11:00", tags: ["#12", "design"]),
            entry(website, "09-21T11:00", "09-21T12:00", tags: ["web#30", "#12"]),
            entry(website, "09-22T09:00", "09-22T11:00", tags: ["api#7"]),
            entry(website, "09-22T13:00", "09-22T14:00"),
            entry(website, "09-23T09:00", "09-23T09:30", tags: ["Design"]),
        ], of: website)

        // The latest spelling wins.
        #expect(result.tags.map(\.name) == ["Design"])
        #expect(result.tags.map(\.count) == [2])
        #expect(result.tags.map(\.milliseconds) == [2 * hour + hour / 2])

        #expect(result.repositories.map(\.title) == ["acme/web", "acme/api"])
        #expect(result.repositories[0].issues.map(\.name) == ["#12", "web#30"])
        #expect(result.repositories[0].issues.map(\.number) == [12, 30])
        #expect(result.repositories[0].issues.map(\.milliseconds) == [3 * hour, hour])
        // An entry with two of a repository's issues counts once for it.
        #expect(result.repositories[0].milliseconds == 3 * hour)
        #expect(result.repositories[1].issues.first?.url?.absoluteString == "https://github.com/acme/api/issues/7")
        #expect(Set(result.tagNames) == ["Design", "#12", "web#30", "api#7"])
    }
}

@Suite struct ProjectTreeTests {
    @Test func listsClientsWithTheirProjectsAndTheArchivedApart() {
        let now = DateTimeFormat.parse("2026-09-23T15:40:00+02:00")!
        let active = Client(name: "Acme", updated: now)
        let archived = Client(name: "Globex", archived: true, updated: now)
        let gone = Client(name: "Initech", updated: now, deleted: now)
        let projects = [
            Project(clientID: active.id, name: "Website", updated: now),
            Project(clientID: active.id, name: "Admin", archived: true, updated: now),
            Project(clientID: archived.id, name: "Brand", updated: now),
            Project(name: "Tools", updated: now),
            Project(name: "Old", archived: true, updated: now),
            // Its client was deleted, so it shows as archived.
            Project(clientID: gone.id, name: "Orphan", updated: now),
            Project(name: "Removed", updated: now, deleted: now),
        ]
        let tree = ProjectTree(ledger: Ledger(clients: [active, archived, gone], projects: projects))

        #expect(tree.clients.map(\.client.name) == ["Acme"])
        #expect(tree.clients.first?.projects.map(\.name) == ["Website"])
        #expect(tree.unfiled.map(\.name) == ["Tools"])
        #expect(tree.archivedClients.map(\.client.name) == ["Globex"])
        #expect(tree.archivedClients.first?.projects.map(\.name) == ["Brand"])
        // By title: "Acme › Admin", "Initech › Orphan", "Old".
        #expect(tree.archivedProjects.map(\.name) == ["Admin", "Orphan", "Old"])
    }
}
