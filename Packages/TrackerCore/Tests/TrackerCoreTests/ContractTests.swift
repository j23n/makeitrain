import Foundation
import Testing
@testable import TrackerCore

@Suite struct ContractTests {
    let project = uuid(10)
    let zone = "Europe/Berlin"

    func day(_ text: String) -> LocalDate {
        guard let day = LocalDate(fileText: text) else { fatalError("Not a day: \(text)") }
        return day
    }

    /// A finished entry of the project: `hours` hours from 9:00 on `day`.
    func entry(_ id: Int, on day: String, hours: Double, project: UUID? = nil) -> TimeEntry {
        let start = t("\(day)T09:00:00+01:00")
        return TimeEntry(
            id: uuid(id),
            projectID: project ?? self.project,
            start: start,
            end: start.adding(milliseconds: Int64(hours * 3_600_000)),
            timeZone: zone,
            updated: start
        )
    }

    func makeLedger(_ contracts: [Contract], entries: [TimeEntry] = [], archived: Bool = false) -> Ledger {
        Ledger(
            projects: [Project(id: project, name: "Mobile app", archived: archived, contracts: contracts, updated: t("2026-09-01T00:00:00Z"))],
            entries: entries
        )
    }

    // MARK: Status

    @Test func defaultAlertIsTenPercentRoundedUpToAWholeHour() {
        #expect(Contract.defaultAlertHours(for: 120) == 12)
        #expect(Contract.defaultAlertHours(for: 40) == 4)
        #expect(Contract.defaultAlertHours(for: 25) == 3)
        #expect(Contract.defaultAlertHours(for: 5) == 1)
        let contract = Contract(hours: 40, start: day("2026-10-01"), end: day("2026-11-30"))
        #expect(contract.alertTime == 4 * 3_600_000)
        var off = contract
        off.alertHours = 0
        #expect(off.alertTime == 0)
        var custom = contract
        custom.alertHours = 8
        #expect(custom.alertsAt == 8)
    }

    @Test func countsTheProjectsTimeOnTheContractsDaysOnly() {
        let contract = Contract(hours: 10, start: day("2026-11-02"), end: day("2026-11-30"))
        let ledger = makeLedger([contract], entries: [
            entry(1, on: "2026-11-01", hours: 5),
            entry(2, on: "2026-11-02", hours: 3),
            entry(3, on: "2026-11-20", hours: 2.5),
            entry(4, on: "2026-11-20", hours: 4, project: uuid(99)),
            entry(5, on: "2026-12-01", hours: 1),
        ])
        let now = t("2026-11-20T18:00:00+01:00")
        let status = ContractStatus(contract: contract, projectID: project, dayTotals: DayTotals(ledger.resolvedEntries()), today: day("2026-11-20"), now: now)
        #expect(status.used == Int64(5.5 * 3_600_000))
        #expect(status.left == Int64(4.5 * 3_600_000))
        #expect(!status.isLow)
        #expect(!status.isUsedUp)
    }

    @Test func countsTheRunningTimerAsItRuns() {
        let contract = Contract(hours: 4, start: day("2026-11-01"), end: day("2026-11-30"))
        var ledger = makeLedger([contract])
        ledger.startTimer(id: uuid(1), projectID: project, timeZone: zone, at: t("2026-11-20T09:00:00+01:00"), now: t("2026-11-20T09:00:00+01:00"))
        let resolved = ledger.resolvedEntries()
        let status = ContractStatus(contract: contract, projectID: project, dayTotals: DayTotals(resolved), today: day("2026-11-20"), now: t("2026-11-20T13:30:00+01:00"))
        #expect(status.used == Int64(4.5 * 3_600_000))
        #expect(status.isOver)
        #expect(status.isLow)
    }

    @Test func comparesWithAnEvenPace() {
        // 120 hours over 122 days; on the 81st, an even pace has used 79:40.
        let contract = Contract(hours: 120, start: day("2026-09-01"), end: day("2026-12-31"))
        let status = ContractStatus(contract: contract, projectID: project, dayTotals: DayTotals(), today: day("2026-11-20"), now: t("2026-11-20T12:00:00+01:00"))
        #expect(status.evenPace / 60000 == 79 * 60 + 40)
        #expect(status.aheadOfPace == -status.evenPace)
        #expect(status.daysLeft == 41)
        #expect(status.workdaysLeft == 29)

        let before = ContractStatus(contract: contract, projectID: project, dayTotals: DayTotals(), today: day("2026-08-20"), now: t("2026-08-20T12:00:00+01:00"))
        #expect(before.evenPace == 0)
        #expect(!before.hasStarted)
        #expect(before.daysLeft == 122)
        let after = ContractStatus(contract: contract, projectID: project, dayTotals: DayTotals(), today: day("2027-01-05"), now: t("2027-01-05T12:00:00+01:00"))
        #expect(after.evenPace == contract.budget)
        #expect(after.hasEnded)
        #expect(after.daysLeft == 0)
    }

    @Test func estimatesWhenTheHoursRunOutAtTheRecentRate() {
        // Two hours a workday over the last four weeks, and 5 hours left
        // on Friday 20 November: Monday, Tuesday, then Wednesday runs out.
        let contract = Contract(hours: 35, start: day("2026-11-01"), end: day("2026-11-30"))
        let workdays = (day("2026-11-02")...day("2026-11-20")).days.filter(\.isWorkday)
        #expect(workdays.count == 15)
        let entries = workdays.enumerated().map { entry($0.offset + 1, on: $0.element.description, hours: 2) }
        let ledger = makeLedger([contract], entries: entries)
        let status = ContractStatus(contract: contract, projectID: project, dayTotals: DayTotals(ledger.resolvedEntries()), today: day("2026-11-20"), now: t("2026-11-20T20:00:00+01:00"))
        #expect(status.left == 5 * 3_600_000)
        #expect(status.recentRate == 2 * 3_600_000)
        #expect(status.runsOut == day("2026-11-25"))

        // Enough for the rest of the contract: no date.
        let roomy = Contract(hours: 200, start: day("2026-11-01"), end: day("2026-11-30"))
        let plenty = ContractStatus(contract: roomy, projectID: project, dayTotals: DayTotals(ledger.resolvedEntries()), today: day("2026-11-20"), now: t("2026-11-20T20:00:00+01:00"))
        #expect(plenty.runsOut == nil)
    }

    @Test func picksTheContractOfTodayOrTheNextOne() {
        let earlier = Contract(id: uuid(1), hours: 100, start: day("2026-05-01"), end: day("2026-08-31"))
        let current = Contract(id: uuid(2), hours: 120, start: day("2026-09-01"), end: day("2026-12-31"))
        let next = Contract(id: uuid(3), hours: 60, start: day("2027-01-01"), end: day("2027-03-31"))
        let project = Project(name: "Web", contracts: [earlier, current, next], updated: t("2026-09-01T00:00:00Z"))
        #expect(project.contract(on: day("2026-11-20")) == current)
        #expect(project.contract(on: day("2026-04-01")) == earlier)
        #expect(project.contract(on: day("2027-05-01")) == nil)
        #expect(project.earlierContracts(before: day("2026-11-20")) == [earlier])
    }

    @Test func suggestsTheNextContract() {
        let current = Contract(hours: 120, start: day("2026-09-01"), end: day("2026-12-31"), alertHours: 8)
        let next = Contract.next(after: [current], today: day("2026-11-20"))
        #expect(next.start == day("2027-01-01"))
        #expect(next.end == day("2027-05-02"))
        #expect(next.hours == 120)
        #expect(next.alertHours == 8)
        let first = Contract.next(after: [], today: day("2026-02-10"))
        #expect(first.start == day("2026-02-01"))
        #expect(first.end == day("2026-02-28"))
    }

    // MARK: Editing

    @Test func setsChangesAndRemovesContracts() throws {
        var ledger = makeLedger([])
        let now = t("2026-11-20T10:00:00Z")
        let contract = Contract(id: uuid(1), hours: 40, start: day("2026-10-01"), end: day("2026-11-30"))
        #expect(try ledger.setContract(contract, ofProject: project, now: now).projects)
        #expect(ledger.projects[project]?.contracts == [contract])
        #expect(ledger.projects[project]?.updated == now)

        var changed = contract
        changed.hours = 50
        try ledger.setContract(changed, ofProject: project, now: now.adding(seconds: 1))
        #expect(ledger.projects[project]?.contracts == [changed])

        #expect(throws: ContractError.invalid) {
            try ledger.setContract(Contract(hours: 0, start: day("2027-01-01"), end: day("2027-01-31")), ofProject: project, now: now)
        }
        #expect(throws: ContractError.invalid) {
            try ledger.setContract(Contract(hours: 5, start: day("2027-01-31"), end: day("2027-01-01")), ofProject: project, now: now)
        }
        #expect(throws: ContractError.overlaps(changed)) {
            try ledger.setContract(Contract(hours: 5, start: day("2026-11-30"), end: day("2026-12-31")), ofProject: project, now: now)
        }
        #expect(throws: ContractError.noProject) {
            try ledger.setContract(contract, ofProject: uuid(99), now: now)
        }

        ledger.removeContract(uuid(1), fromProject: project, now: now.adding(seconds: 2))
        #expect(ledger.projects[project]?.contracts.isEmpty == true)
    }

    @Test func undoBringsTheContractsBack() throws {
        let contract = Contract(id: uuid(1), hours: 40, start: day("2026-10-01"), end: day("2026-11-30"))
        var ledger = makeLedger([contract])
        let before = ledger
        ledger.removeContract(uuid(1), fromProject: project, now: t("2026-11-20T10:00:00Z"))
        ledger.restore(ledger.diff(from: before), now: t("2026-11-20T10:01:00Z"))
        #expect(ledger.projects[project]?.contracts == [contract])
    }

    // MARK: Files

    @Test func writesContractsAsVersion3AndReadsThemBack() throws {
        let contract = Contract(id: uuid(1), hours: 120, start: day("2026-09-01"), end: day("2026-12-31"), alertHours: 12)
        let plain = Contract(id: uuid(2), hours: 20, start: day("2027-01-01"), end: day("2027-01-31"))
        let project = Project(id: uuid(10), name: "Website", contracts: [plain, contract], updated: t("2026-09-23T09:00:00Z"))
        let data = FileFormat.encode(clients: [], projects: [project])
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("""
              "contracts": [
                {
                  "alertHours": 12,
                  "end": "2026-12-31",
                  "hours": 120,
                  "id": "00000000-0000-0000-0000-000000000001",
                  "start": "2026-09-01"
                },
                {
                  "end": "2027-01-31",
                  "hours": 20,
                  "id": "00000000-0000-0000-0000-000000000002",
                  "start": "2027-01-01"
                }
              ],
        """))
        #expect(text.contains(#""version": 3"#))
        let decoded = try FileFormat.decodeProjects(from: data).projects
        #expect(decoded.first?.contracts == [contract, plain])

        // Without contracts the file stays version 2, which older copies read.
        let without = String(decoding: FileFormat.encode(clients: [], projects: [Project(name: "Web", updated: t("2026-09-23T09:00:00Z"))]), as: UTF8.self)
        #expect(without.contains(#""version": 2"#))
        #expect(!without.contains("contracts"))
    }

    @Test func refusesAContractWithABadDay() {
        let json = #"{"version": 3, "projects": [{"id": "00000000-0000-0000-0000-000000000002", "name": "Web", "updated": "2026-09-23T09:00:00Z", "contracts": [{"id": "00000000-0000-0000-0000-000000000001", "hours": 5, "start": "2026-02-30", "end": "2026-03-31"}]}]}"#
        #expect(throws: FileProblem.self) {
            try FileFormat.decodeProjects(from: Data(json.utf8))
        }
    }

    @Test func mergeIsTheSameEitherWay() {
        let stamp = t("2026-09-23T09:00:00Z")
        let a = Project(id: uuid(10), name: "Web", contracts: [Contract(id: uuid(1), hours: 10, start: day("2026-09-01"), end: day("2026-09-30"))], updated: stamp)
        let b = Project(id: uuid(10), name: "Web", contracts: [Contract(id: uuid(1), hours: 12, start: day("2026-09-01"), end: day("2026-09-30"))], updated: stamp)
        #expect(a.merged(with: b) == b.merged(with: a))
    }

    // MARK: Alerts

    @Test func alertsOnceTheTimeLeftReachesTheAlert() {
        let contract = Contract(id: uuid(1), hours: 10, start: day("2026-11-01"), end: day("2026-11-30"))
        let now = t("2026-11-20T18:00:00+01:00")
        let ledger = makeLedger([contract], entries: [entry(1, on: "2026-11-20", hours: 9.5)])
        let alerts = ledger.contractAlerts(dayTotals: DayTotals(ledger.resolvedEntries()), running: nil, today: day("2026-11-20"), now: now)
        #expect(alerts.map(\.kind) == [.low])
        #expect(alerts.first?.date == now)
        #expect(alerts.first?.left == 30 * 60000)

        // Archived projects and contracts that don't hold today don't alert.
        let archived = makeLedger([contract], entries: [entry(1, on: "2026-11-20", hours: 9.5)], archived: true)
        #expect(archived.contractAlerts(dayTotals: DayTotals(archived.resolvedEntries()), running: nil, today: day("2026-11-20"), now: now).isEmpty)
        #expect(ledger.contractAlerts(dayTotals: DayTotals(ledger.resolvedEntries()), running: nil, today: day("2026-12-01"), now: now).isEmpty)
    }

    @Test func schedulesTheRunningTimersAlertsAhead() {
        let contract = Contract(id: uuid(1), hours: 10, start: day("2026-11-01"), end: day("2026-11-30"))
        var ledger = makeLedger([contract], entries: [entry(1, on: "2026-11-19", hours: 6)])
        let start = t("2026-11-20T09:00:00+01:00")
        ledger.startTimer(id: uuid(2), projectID: project, timeZone: zone, at: start, now: start)
        let resolved = ledger.resolvedEntries()
        let now = start.adding(seconds: 1800)
        let alerts = ledger.contractAlerts(dayTotals: DayTotals(resolved), running: resolved.first { $0.isRunning }, today: day("2026-11-20"), now: now)
        // At 09:30, 6:30 used and 3:30 left: the alert, at 1 hour left,
        // at 12:00, and the end at 13:00.
        #expect(Set(alerts.map(\.kind)) == [.low, .usedUp])
        #expect(alerts.first { $0.kind == .low }?.date == start.adding(seconds: 10800))
        #expect(alerts.first { $0.kind == .usedUp }?.date == start.adding(seconds: 14400))
        #expect(alerts.allSatisfy { $0.running })
    }

    @Test func plansEachAlertOnce() {
        let contract = Contract(id: uuid(1), hours: 10, start: day("2026-11-01"), end: day("2026-11-30"))
        let now = t("2026-11-20T10:00:00Z")
        let low = ContractAlert(kind: .low, projectID: project, contract: contract, date: now, left: 3_000_000, running: false)
        let out = ContractAlert(kind: .usedUp, projectID: project, contract: contract, date: now.adding(seconds: 3000), left: 0, running: true)

        // Reached now: shown; the end of the hours, scheduled.
        let first = ContractAlertPlan(alerts: [low, out], notified: [], scheduled: [:], now: now)
        #expect(first.post == [low])
        #expect(first.schedule == [out])
        #expect(first.notified == [low.key])
        #expect(first.scheduled == [out.key: out.date])

        // A minute later, nothing new.
        let again = ContractAlertPlan(alerts: [low, out], notified: first.notified, scheduled: first.scheduled, now: now.adding(seconds: 60))
        #expect(again.post.isEmpty && again.schedule.isEmpty && again.cancel.isEmpty)

        // Once the scheduled time has come, the system showed it.
        var reached = out
        reached.date = now.adding(seconds: 3000)
        let later = now.adding(seconds: 3100)
        let shown = ContractAlertPlan(alerts: [low, reached], notified: again.notified, scheduled: again.scheduled, now: later)
        #expect(shown.post.isEmpty)
        #expect(shown.notified == [low.key, out.key])

        // The timer stopped before: the scheduled one is taken back.
        let stopped = ContractAlertPlan(alerts: [low], notified: first.notified, scheduled: first.scheduled, now: now.adding(seconds: 120))
        #expect(stopped.cancel == [out.key])
        #expect(stopped.scheduled.isEmpty)
    }

    @Test func usedUpCoversTheAlertReachedWithIt() {
        let contract = Contract(id: uuid(1), hours: 10, start: day("2026-11-01"), end: day("2026-11-30"))
        let now = t("2026-11-20T10:00:00Z")
        let low = ContractAlert(kind: .low, projectID: project, contract: contract, date: now, left: -600_000, running: false)
        let out = ContractAlert(kind: .usedUp, projectID: project, contract: contract, date: now, left: -600_000, running: false)
        let plan = ContractAlertPlan(alerts: [low, out], notified: [], scheduled: [:], now: now)
        #expect(plan.post == [out])
        #expect(plan.notified == [low.key, out.key])
    }

    @Test func aChangedContractAlertsAgain() {
        let contract = Contract(id: uuid(1), hours: 10, start: day("2026-11-01"), end: day("2026-11-30"))
        var more = contract
        more.hours = 20
        let now = t("2026-11-20T10:00:00Z")
        let low = ContractAlert(kind: .low, projectID: project, contract: contract, date: now, left: 0, running: false)
        let changed = ContractAlert(kind: .low, projectID: project, contract: more, date: now, left: 0, running: false)
        #expect(low.key != changed.key)
        let plan = ContractAlertPlan(alerts: [changed], notified: [low.key], scheduled: [:], now: now)
        #expect(plan.post == [changed])
        #expect(plan.notified == [changed.key])
    }
}
