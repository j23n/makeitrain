import Foundation
import Testing
import TrackerCore
@testable import TrackerKit

@Suite struct ReportDataTests {
    let now = DateTimeFormat.parse("2026-09-25T18:00:00+02:00")!
    let hour: Int64 = 3_600_000

    // Acme has Website and App, Solo has Shop, and Internal has no client.
    let acme = UUID(), solo = UUID()
    let website = UUID(), app = UUID(), shop = UUID(), inHouse = UUID()

    var ledger: Ledger {
        Ledger(
            clients: [
                Client(id: acme, name: "Acme", updated: now),
                Client(id: solo, name: "Solo", updated: now),
            ],
            projects: [
                Project(id: website, clientID: acme, name: "Website", color: "#111111", updated: now),
                Project(id: app, clientID: acme, name: "App", color: "#222222", updated: now),
                Project(id: shop, clientID: solo, name: "Shop", color: "#333333", updated: now),
                Project(id: inHouse, name: "Internal", color: "#444444", updated: now),
            ]
        )
    }

    /// An entry in Berlin, such as `entry(website, "09-23T09:00", "09-23T10:30")`.
    func entry(_ project: UUID?, _ start: String, _ end: String, tags: [String] = []) -> TimeEntry {
        let startTime = DateTimeFormat.parse("2026-\(start):00+02:00")!
        let endTime = DateTimeFormat.parse("2026-\(end):00+02:00")!
        return TimeEntry(projectID: project, start: startTime, end: endTime, timeZone: "Europe/Berlin", tags: tags, updated: startTime)
    }

    func day(_ month: Int, _ day: Int) -> LocalDate {
        LocalDate(year: 2026, month: month, day: day)
    }

    /// A report of `entries` with the sample clients and projects, and the
    /// ledger it's from.
    func report(_ entries: [TimeEntry], _ range: ClosedRange<LocalDate>, grouping: ReportRequest.Grouping = .client) -> (Report, Ledger) {
        var ledger = ledger
        for entry in entries { ledger.merge(entry) }
        return (Report(ReportRequest(range: range, grouping: grouping), ledger: ledger, now: now), ledger)
    }

    @Test func givesAClientWithOneProjectOneLine() {
        let (result, _) = report([
            entry(website, "09-21T09:00", "09-21T11:00"),
            entry(app, "09-21T11:00", "09-21T12:00"),
            entry(shop, "09-22T09:00", "09-22T12:00"),
            entry(inHouse, "09-22T13:00", "09-22T14:00"),
            entry(nil, "09-23T09:00", "09-23T09:30"),
        ], day(9, 21)...day(9, 27))
        let rows = BreakdownRow.rows(of: result)

        #expect(rows.map(\.title) == ["Acme", "App", "Website", "Solo › Shop", "Internal", "Unassigned"])
        #expect(rows.map(\.isNested) == [false, true, true, false, false, false])
        #expect(rows.map(\.milliseconds) == [3 * hour, hour, 2 * hour, 3 * hour, hour, hour / 2])
        #expect(rows[0].mark == .client)
        #expect(rows[0].bar == .parts([
            BreakdownRow.Part(color: "#222222", milliseconds: hour),
            BreakdownRow.Part(color: "#111111", milliseconds: 2 * hour),
        ]))
        #expect(rows[3].mark == .project(color: "#333333"))
        #expect(rows[3].id == .project(shop))
        // The unassigned entries have the ring of no project and a gray bar.
        #expect(rows[5].mark == .project(color: nil))
        #expect(rows[5].bar == .parts([BreakdownRow.Part(color: nil, milliseconds: hour / 2)]))
    }

    @Test func givesTagsTheAccentAndUntaggedGray() {
        let (result, _) = report([
            entry(website, "09-21T09:00", "09-21T11:00", tags: ["design", "call"]),
            entry(app, "09-21T11:00", "09-21T12:00"),
        ], day(9, 21)...day(9, 27), grouping: .tag)
        let rows = BreakdownRow.rows(of: result)

        #expect(rows.map(\.title) == ["call", "design", "Untagged"])
        #expect(rows.map(\.mark) == [.blank, .blank, .blank])
        #expect(rows.map(\.bar) == [.accent, .accent, .parts([BreakdownRow.Part(color: nil, milliseconds: hour)])])
    }

    @Test func listsProjectsByTheirTime() {
        let times: [UUID?: Int64] = [website: 2 * hour, nil: hour, app: 3 * hour, shop: 0]

        let rows = BreakdownRow.projects(times, ledger: ledger)
        #expect(rows.map(\.title) == ["Acme › App", "Acme › Website", "Unassigned"])
        #expect(rows.map(\.id) == [.project(app), .project(website), .unassigned])
        #expect(BreakdownRow.projects(times, ledger: ledger, withClients: false).map(\.title) == ["App", "Website", "Unassigned"])
    }

    @Test func chartsAWeekByDayWithTheBusiestProjectFirst() {
        let (result, ledger) = report([
            entry(website, "09-21T09:00", "09-21T10:00"),
            entry(app, "09-21T10:00", "09-21T13:00"),
            entry(app, "09-23T09:00", "09-23T10:00"),
        ], day(9, 21)...day(9, 27))
        let chart = ReportChartData(result, ledger: ledger, today: day(9, 23), firstWeekday: 2)

        #expect(chart.unit == .day)
        #expect(chart.columns.count == 7)
        #expect(chart.columns.map(\.milliseconds) == [4 * hour, 0, hour, 0, 0, 0, 0])
        #expect(chart.columns.map(\.isCurrent) == [false, false, true, false, false, false, false])
        #expect(chart.legend.map(\.id) == [app.uuidString, website.uuidString])
        // App is at the bottom of Monday's bar, being the busier.
        #expect(chart.columns[0].parts.map(\.id) == [app.uuidString, website.uuidString])
        #expect(chart.average == 2 * hour + hour / 2)
    }

    @Test func chartsLongRangesByWeekOrMonth() {
        let entries = [
            entry(website, "08-03T09:00", "08-03T10:00"),
            entry(website, "08-07T09:00", "08-07T11:00"),
            entry(app, "09-15T09:00", "09-15T12:00"),
        ]
        let (twoMonths, ledger) = report(entries, day(8, 1)...day(9, 30))
        let byWeek = ReportChartData(twoMonths, ledger: ledger, today: day(9, 23), firstWeekday: 2)
        #expect(byWeek.unit == .week)
        // August 1 is a Saturday: its week starts on July 27.
        #expect(byWeek.columns.count == 10)
        #expect(byWeek.columns[1].milliseconds == 3 * hour)
        #expect(byWeek.columns.map(\.milliseconds).reduce(0, +) == twoMonths.total)
        #expect(byWeek.average == nil)

        let (year, _) = report(entries, day(1, 1)...day(12, 31))
        let byMonth = ReportChartData(year, ledger: ledger, today: day(9, 23), firstWeekday: 2)
        #expect(byMonth.unit == .month)
        #expect(byMonth.columns.count == 12)
        #expect(Array(byMonth.columns.map(\.milliseconds)[7...8]) == [3 * hour, 3 * hour])
        #expect(byMonth.columns.map(\.isCurrent)[8])
    }
}
