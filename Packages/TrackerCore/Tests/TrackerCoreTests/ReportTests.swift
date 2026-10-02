import Foundation
import Testing
@testable import TrackerCore

@Suite struct ReportTests {
    let now = t("2026-09-25T18:00:00+02:00")

    // Acme has Website and App; Internal has no client.
    let acme = uuid(20), beta = uuid(21)
    let website = uuid(10), app = uuid(11), inHouse = uuid(12), betaSite = uuid(13)

    var ledger: Ledger {
        Ledger(
            clients: [
                Client(id: acme, name: "Acme", updated: now),
                Client(id: beta, name: "beta corp", updated: now),
            ],
            projects: [
                Project(id: website, clientID: acme, name: "Website", color: "#111111", updated: now),
                Project(id: app, clientID: acme, name: "App", color: "#222222", updated: now),
                Project(id: inHouse, name: "Internal", color: "#333333", updated: now),
                Project(id: betaSite, clientID: beta, name: "Site", updated: now),
            ]
        )
    }

    /// An entry in Berlin, such as `entry(1, website, "23T09:00", "23T10:30")`.
    func entry(
        _ number: Int,
        _ project: UUID?,
        _ start: String,
        _ end: String?,
        tags: [String] = [],
        zone: String = "Europe/Berlin",
        offset: String = "+02:00"
    ) -> TimeEntry {
        TimeEntry(
            id: uuid(number),
            projectID: project,
            start: t("2026-09-\(start):00\(offset)"),
            end: end.map { t("2026-09-\($0):00\(offset)") },
            timeZone: zone,
            tags: tags,
            updated: now
        )
    }

    func report(_ entries: [TimeEntry], _ request: ReportRequest) -> Report {
        var ledger = ledger
        for entry in entries { ledger.merge(entry) }
        return Report(request, ledger: ledger, now: now)
    }

    func days(_ first: Int, _ last: Int) -> ClosedRange<LocalDate> {
        LocalDate(year: 2026, month: 9, day: first)...LocalDate(year: 2026, month: 9, day: last)
    }

    func date(_ year: Int, _ month: Int, _ day: Int) -> LocalDate {
        LocalDate(year: year, month: month, day: day)
    }

    let hour: Int64 = 3_600_000

    @Test func groupsByClientWithProjectsNested() {
        let result = report([
            entry(1, website, "23T09:00", "23T10:00"),
            entry(2, app, "23T10:00", "23T12:00"),
            entry(3, inHouse, "23T13:00", "23T13:30"),
            entry(4, nil, "23T14:00", "23T14:15"),
            entry(5, betaSite, "24T09:00", "24T10:00"),
            entry(6, website, "24T10:00", "24T11:00"),
        ], ReportRequest(range: days(21, 27)))

        #expect(result.total == 5 * hour + hour / 2 + hour / 4)
        #expect(result.groups.map(\.title) == ["Acme", "beta corp", "No client", "Unassigned"])
        #expect(result.groups.map(\.milliseconds) == [4 * hour, hour, hour / 2, hour / 4])
        #expect(result.groups[0].children.map(\.title) == ["App", "Website"])
        #expect(result.groups[0].children.map(\.milliseconds) == [2 * hour, 2 * hour])
        #expect(result.groups[0].children.map(\.color) == ["#222222", "#111111"])
        #expect(result.groups[2].children.map(\.title) == ["Internal"])
        #expect(result.groups[3].children.isEmpty)
    }

    @Test func groupsByProjectWithClientNames() {
        let result = report([
            entry(1, website, "23T09:00", "23T10:00"),
            entry(2, inHouse, "23T10:00", "23T12:00"),
            entry(3, nil, "23T12:00", "23T12:30"),
        ], ReportRequest(range: days(21, 27), grouping: .project))

        #expect(result.groups.map(\.title) == ["Acme › Website", "Internal", "Unassigned"])
        #expect(result.groups.map(\.milliseconds) == [hour, 2 * hour, hour / 2])
        #expect(result.groups.map(\.kind) == [.project(website), .project(inHouse), .unassigned])
    }

    @Test func groupsByTagCountingEntriesUnderEachOfTheirTags() {
        let result = report([
            entry(1, website, "23T09:00", "23T10:00", tags: ["design", "Call"]),
            entry(2, website, "23T10:00", "23T12:00", tags: ["call"]),
            entry(3, website, "23T12:00", "23T12:30"),
        ], ReportRequest(range: days(21, 27), grouping: .tag))

        // The later entry's spelling wins, as in the tag list.
        #expect(result.groups.map(\.title) == ["call", "design", "Untagged"])
        #expect(result.groups.map(\.milliseconds) == [3 * hour, hour, hour / 2])
        #expect(result.total == 3 * hour + hour / 2)
    }

    @Test func anEntryBelongsToTheDayItStartedOnInItsOwnZone() {
        let result = report([
            // 23:30 in Berlin on the 20th is the 20th, though it's past
            // midnight further east.
            entry(1, website, "20T23:30", "21T00:30"),
            // 22:00 in New York on the 21st is the 22nd in UTC, but the 21st
            // where it was recorded.
            entry(2, website, "21T22:00", "21T23:00", zone: "America/New_York", offset: "-04:00"),
            // Past midnight into the 28th in Berlin, but it started on the 27th.
            entry(3, website, "27T23:00", "28T01:00"),
            entry(4, website, "28T00:30", "28T01:00"),
        ], ReportRequest(range: days(21, 27)))

        #expect(result.entries.map(\.id) == [uuid(2), uuid(3)])
        // An entry that runs past midnight counts in full on its first day.
        #expect(result.total == 3 * hour)
        #expect(result.days.map(\.date) == (21...27).map { date(2026, 9, $0) })
        #expect(result.days.map(\.milliseconds) == [hour, 0, 0, 0, 0, 0, 2 * hour])
    }

    @Test func leavesTheRunningTimerOutOfTheTotals() {
        let result = report([
            entry(1, website, "25T09:00", "25T10:00"),
            entry(2, app, "25T16:00", nil),
        ], ReportRequest(range: days(21, 27)))

        #expect(result.total == hour)
        #expect(result.entries.map(\.id) == [uuid(1)])
        #expect(result.running?.id == uuid(2))
        #expect(result.groups.map(\.milliseconds) == [hour])
    }

    @Test func aTimerOvertakenByALaterOneCountsUntilThatOneStarted() {
        let result = report([
            entry(1, website, "25T09:00", nil),
            entry(2, app, "25T11:00", nil),
        ], ReportRequest(range: days(21, 27)))

        #expect(result.entries.map(\.id) == [uuid(1)])
        #expect(result.total == 2 * hour)
        #expect(result.running?.id == uuid(2))
    }

    @Test func saysHowMuchTimeOverlapsCountedTwice() {
        let result = report([
            entry(1, website, "23T09:00", "23T11:00"),
            entry(2, app, "23T10:00", "23T12:00"),
            entry(3, app, "23T13:00", "23T14:00"),
        ], ReportRequest(range: days(21, 27)))

        #expect(result.total == 5 * hour)
        #expect(result.doubleCounted == hour)
    }

    @Test func leavesOutDeletedEntries() {
        var deleted = entry(2, app, "23T10:00", "23T12:00")
        deleted.deleted = now
        let result = report([entry(1, website, "23T09:00", "23T10:00"), deleted], ReportRequest(range: days(21, 27)))

        #expect(result.entries.map(\.id) == [uuid(1)])
        #expect(result.total == hour)
    }

    @Test func filtersByProjectClientAndTag() {
        let entries = [
            entry(1, website, "23T09:00", "23T10:00", tags: ["Design"]),
            entry(2, app, "23T10:00", "23T12:00", tags: ["call"]),
            entry(3, inHouse, "23T13:00", "23T13:30", tags: ["design", "call"]),
            entry(4, nil, "23T14:00", "23T14:15"),
            entry(5, betaSite, "24T09:00", "24T10:00"),
        ]
        func ids(_ request: ReportRequest) -> [UUID] {
            report(entries, request).entries.map(\.id)
        }

        #expect(ids(ReportRequest(range: days(21, 27), projects: [website, nil])) == [uuid(1), uuid(4)])
        #expect(ids(ReportRequest(range: days(21, 27), clients: [acme])) == [uuid(1), uuid(2)])
        // No client covers projects without one and unassigned entries.
        #expect(ids(ReportRequest(range: days(21, 27), clients: [nil])) == [uuid(3), uuid(4)])
        #expect(ids(ReportRequest(range: days(21, 27), tags: ["DESIGN"])) == [uuid(1), uuid(3)])
        #expect(ids(ReportRequest(range: days(21, 27), tags: [])) == [uuid(1), uuid(2), uuid(3), uuid(4), uuid(5)])
        #expect(ids(ReportRequest(range: days(21, 27), clients: [acme], tags: ["call"])) == [uuid(2)])
    }

    @Test func chartsEachDayByProject() {
        let result = report([
            entry(1, website, "23T09:00", "23T10:00"),
            entry(2, website, "23T11:00", "23T12:00"),
            entry(3, nil, "23T13:00", "23T13:30"),
            entry(4, app, "25T09:00", "25T10:00"),
        ], ReportRequest(range: days(23, 25)))

        #expect(result.days.count == 3)
        #expect(result.days[0].projects == [website: 2 * hour, nil: hour / 2])
        #expect(result.days[1].projects.isEmpty)
        #expect(result.days[2].projects == [app: hour])
    }

    @Test func periodsFollowTheFirstDayOfTheWeek() {
        // Wednesday, September 23, 2026.
        let wednesday = date(2026, 9, 23)
        #expect(ReportPeriod.week.range(containing: wednesday, firstWeekday: 2) == days(21, 27))
        #expect(ReportPeriod.week.range(containing: wednesday, firstWeekday: 1) == days(20, 26))
        #expect(ReportPeriod.week.range(containing: wednesday, firstWeekday: 7) == days(19, 25))
        #expect(ReportPeriod.day.range(containing: wednesday, firstWeekday: 2) == days(23, 23))
        #expect(ReportPeriod.month.range(containing: wednesday, firstWeekday: 2) == days(1, 30))

        let sunday = date(2026, 9, 27)
        #expect(ReportPeriod.week.range(containing: sunday, firstWeekday: 2) == days(21, 27))
        #expect(ReportPeriod.week.range(containing: sunday, firstWeekday: 1) == date(2026, 9, 27)...date(2026, 10, 3))
    }

    @Test func periodsStepBackAndForward() {
        let week = days(21, 27)
        #expect(ReportPeriod.week.shift(week, by: -1, firstWeekday: 2) == days(14, 20))
        #expect(ReportPeriod.week.shift(week, by: 1, firstWeekday: 2) == date(2026, 9, 28)...date(2026, 10, 4))
        #expect(ReportPeriod.day.shift(days(23, 23), by: 1, firstWeekday: 2) == days(24, 24))
        #expect(ReportPeriod.custom.shift(days(10, 12), by: 1, firstWeekday: 2) == days(13, 15))

        let december = date(2026, 12, 1)...date(2026, 12, 31)
        let january = date(2027, 1, 1)...date(2027, 1, 31)
        let february = date(2027, 2, 1)...date(2027, 2, 28)
        #expect(ReportPeriod.month.shift(december, by: 1, firstWeekday: 2) == january)
        #expect(ReportPeriod.month.shift(january, by: -1, firstWeekday: 2) == december)
        #expect(ReportPeriod.month.shift(january, by: 1, firstWeekday: 2) == february)
    }

    // MARK: Figures

    /// How a report of `request` compares with the period before it, as of
    /// `today`.
    func comparison(_ entries: [TimeEntry], _ request: ReportRequest, _ period: ReportPeriod, today: LocalDate) -> ReportComparison {
        var ledger = ledger
        for entry in entries { ledger.merge(entry) }
        let report = Report(request, ledger: ledger, now: now)
        return ReportComparison(report, period: period, today: today, firstWeekday: 2, ledger: ledger, resolved: ledger.resolvedEntries(), now: now)
    }

    @Test func averagesTheDaysWithTimeLogged() {
        let result = report([
            entry(1, website, "21T09:00", "21T12:00"),
            entry(2, app, "21T13:00", "21T14:00"),
            entry(3, website, "23T09:00", "23T11:00"),
            // The running timer counts on no day.
            entry(4, app, "25T16:00", nil),
        ], ReportRequest(range: days(21, 27)))

        #expect(result.daysWorked == 2)
        #expect(result.averagePerDayWorked == 3 * hour)
        #expect(report([], ReportRequest(range: days(21, 27))).daysWorked == 0)
        #expect(report([], ReportRequest(range: days(21, 27))).averagePerDayWorked == 0)
    }

    @Test func comparesAPastWeekWithTheWholeWeekBefore() {
        let result = comparison([
            entry(1, website, "14T09:00", "14T13:00"),
            entry(2, website, "19T09:00", "19T13:00"),
            entry(3, website, "21T09:00", "21T15:00"),
        ], ReportRequest(range: days(21, 27)), .week, today: date(2026, 9, 30))

        #expect(result.previousRange == days(14, 20))
        #expect(result.previousTotal == 8 * hour)
        #expect(result.total == 6 * hour)
        #expect(!result.isPartial)
        #expect(result.percent == -25)
    }

    @Test func comparesAWeekUnderWayWithAsManyDaysOfTheWeekBefore() {
        // On Wednesday the 23rd: Monday to Wednesday against Monday to
        // Wednesday of the week before, leaving out its Thursday.
        let result = comparison([
            entry(1, website, "14T09:00", "14T11:00"),
            entry(2, website, "16T09:00", "16T11:00"),
            entry(3, website, "17T09:00", "17T14:00"),
            entry(4, website, "21T09:00", "21T14:00"),
            entry(5, website, "23T09:00", "23T10:00"),
        ], ReportRequest(range: days(21, 27)), .week, today: date(2026, 9, 23))

        #expect(result.previousRange == days(14, 16))
        #expect(result.previousTotal == 4 * hour)
        #expect(result.total == 6 * hour)
        #expect(result.isPartial)
        #expect(result.percent == 50)
    }

    @Test func comparesAMonthUnderWayWithTheMonthBeforeAtMost() {
        let march = date(2027, 3, 1)...date(2027, 3, 31)
        let result = comparison([], ReportRequest(range: march), .month, today: date(2027, 3, 30))

        #expect(result.previousRange == date(2027, 2, 1)...date(2027, 2, 28))
        #expect(result.isPartial)
        // Nothing logged before has no percentage.
        #expect(result.percent == nil)
    }

    @Test func comparesWithTheSameFiltersAndAsManyDaysBeforeACustomRange() {
        let result = comparison([
            entry(1, website, "07T09:00", "07T10:00"),
            entry(2, app, "08T09:00", "08T12:00"),
            entry(3, website, "10T09:00", "10T11:00"),
        ], ReportRequest(range: days(10, 12), projects: [website]), .custom, today: date(2026, 9, 30))

        #expect(result.previousRange == days(7, 9))
        #expect(result.previousTotal == hour)
        #expect(result.percent == 100)
    }
}
