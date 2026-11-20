import Foundation

/// A number of hours agreed for a project between two days, such as 120
/// hours from 1 September to 31 December. Every entry of the project on a
/// day inside it counts in full.
public struct Contract: Identifiable, Hashable, Sendable {
    public let id: UUID
    /// The hours agreed, a whole number.
    public var hours: Int
    /// The first day that counts.
    public var start: LocalDate
    /// The last day that counts.
    public var end: LocalDate
    /// The hours left at which to alert: nil for the default, 10% of the
    /// hours, and 0 for no alert.
    public var alertHours: Int?

    public init(id: UUID = UUID(), hours: Int, start: LocalDate, end: LocalDate, alertHours: Int? = nil) {
        self.id = id
        self.hours = hours
        self.start = start
        self.end = end
        self.alertHours = alertHours
    }

    /// The alert a contract of `hours` hours gets unless it's changed: 10%
    /// of the hours, rounded up to a whole hour, so 120 hours alert at 12
    /// hours left and 25 hours at 3.
    public static func defaultAlertHours(for hours: Int) -> Int {
        max(1, (hours + 9) / 10)
    }

    /// The hours left at which the contract alerts, 0 for none.
    public var alertsAt: Int {
        max(0, alertHours ?? Self.defaultAlertHours(for: hours))
    }

    /// The hours agreed, in milliseconds.
    public var budget: Int64 {
        Int64(hours) * 3_600_000
    }

    /// The time left at which the contract alerts, in milliseconds, 0 for none.
    public var alertTime: Int64 {
        Int64(alertsAt) * 3_600_000
    }

    /// The days that count.
    public var days: ClosedRange<LocalDate> {
        start...max(start, end)
    }

    /// Whether the contract can be kept: some hours, and an end that isn't
    /// before the start.
    public var isValid: Bool {
        hours > 0 && end >= start
    }

    /// Whether the two share a day.
    public func overlaps(_ other: Contract) -> Bool {
        start <= other.end && other.start <= end
    }
}

extension Project {
    /// The contract that holds `today`, or else the next one to start.
    public func contract(on today: LocalDate) -> Contract? {
        contracts.first { $0.days.contains(today) }
            ?? contracts.filter { $0.start > today }.min { $0.start < $1.start }
    }

    /// The contracts that ended before `today`, the latest first.
    public func earlierContracts(before today: LocalDate) -> [Contract] {
        contracts.filter { $0.end < today }.sorted { $0.end > $1.end }
    }
}

/// Where a contract stands on a day: the time used and left, how that
/// compares with an even pace, and when the hours likely run out.
public struct ContractStatus: Hashable, Sendable {
    public let contract: Contract
    /// The project's time on the contract's days, the running timer up to now.
    public let used: Int64
    /// The day it's worked out for.
    public let today: LocalDate
    /// The time used if the hours were spread evenly over the contract's
    /// days, up to the end of today.
    public let evenPace: Int64
    /// The time used per workday lately: over the last four weeks of the
    /// contract up to today, Monday to Friday. Nil before there's a workday.
    public let recentRate: Int64?
    /// The workday the hours likely run out at the recent rate, when that's
    /// before the contract ends.
    public let runsOut: LocalDate?

    /// Works out the status from each day's time, as `DayTotals` keeps it.
    public init(contract: Contract, projectID: UUID, dayTotals: DayTotals, today: LocalDate, now: Timestamp) {
        self.contract = contract
        self.today = today
        let days = contract.days
        func time(on day: LocalDate) -> Int64 {
            dayTotals.projects(on: day, now: now)[projectID] ?? 0
        }
        used = days.days.reduce(0) { $0 + time(on: $1) }

        let total = days.count
        let elapsed = today < contract.start ? 0 : (today > contract.end ? total : days.lowerBound.distance(to: today) + 1)
        evenPace = total > 0 ? contract.budget * Int64(elapsed) / Int64(total) : 0

        // The last four weeks up to today, within the contract.
        if today >= contract.start {
            let last = min(today, contract.end)
            let first = max(contract.start, last.adding(days: -27))
            let workdays = (first...last).days.filter(\.isWorkday)
            recentRate = workdays.isEmpty ? nil : (first...last).days.reduce(0) { $0 + time(on: $1) } / Int64(workdays.count)
        } else {
            recentRate = nil
        }

        let left = contract.budget - used
        if let rate = recentRate, rate > 0, left > 0, today < contract.end {
            var remaining = left
            var day = today
            var found: LocalDate?
            while day < contract.end {
                day = day.adding(days: 1)
                guard day.isWorkday else { continue }
                remaining -= rate
                if remaining <= 0 {
                    found = day
                    break
                }
            }
            runsOut = found
        } else {
            runsOut = nil
        }
    }

    /// The time left, below zero once the hours are used up.
    public var left: Int64 {
        contract.budget - used
    }

    /// Whether the time left is at or under the alert.
    public var isLow: Bool {
        contract.alertTime > 0 && left <= contract.alertTime
    }

    /// Whether the hours are used up.
    public var isUsedUp: Bool {
        left <= 0
    }

    /// Whether more than the hours is used.
    public var isOver: Bool {
        left < 0
    }

    /// Whether the contract's days have begun.
    public var hasStarted: Bool {
        today >= contract.start
    }

    /// Whether the contract's days are over.
    public var hasEnded: Bool {
        today > contract.end
    }

    /// How much more is used than an even pace, below zero when less is.
    public var aheadOfPace: Int64 {
        used - evenPace
    }

    /// The days after today up to the end, or every day before the start.
    public var daysLeft: Int {
        guard !hasEnded else { return 0 }
        return hasStarted ? today.distance(to: contract.end) : contract.days.count
    }

    /// The workdays, Monday to Friday, after today up to the end, or all of
    /// them before the start.
    public var workdaysLeft: Int {
        guard !hasEnded else { return 0 }
        let first = hasStarted ? today.adding(days: 1) : contract.start
        guard first <= contract.end else { return 0 }
        return (first...contract.end).days.filter(\.isWorkday).count
    }

    /// The share of the hours used, from 0 to 1.
    public var usedShare: Double {
        contract.budget > 0 ? min(1, max(0, Double(used) / Double(contract.budget))) : 0
    }

    /// The share of the hours an even pace has used, from 0 to 1.
    public var paceShare: Double {
        contract.budget > 0 ? min(1, max(0, Double(evenPace) / Double(contract.budget))) : 0
    }

    /// The share of the hours at which it alerts, from 0 to 1, or nil for no alert.
    public var alertShare: Double? {
        guard contract.alertTime > 0, contract.budget > 0 else { return nil }
        return min(1, max(0, Double(contract.budget - contract.alertTime) / Double(contract.budget)))
    }
}

extension LocalDate {
    /// Whether the day is Monday to Friday.
    public var isWorkday: Bool {
        (2...6).contains(weekday)
    }

    /// The days from this day to `other`, negative if `other` is earlier.
    public func distance(to other: LocalDate) -> Int {
        other.daysSince1970 - daysSince1970
    }

    /// Reads a day written as in the files, such as "2026-09-23".
    public init?(fileText text: String) {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              parts.allSatisfy({ $0.allSatisfy(\.isASCIIDigit) }),
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              (1...12).contains(month), (1...LocalDate.daysIn(month: month, year: year)).contains(day)
        else { return nil }
        self.init(year: year, month: month, day: day)
    }
}

extension ClosedRange where Bound == LocalDate {
    /// How many days the range holds.
    public var count: Int {
        lowerBound.distance(to: upperBound) + 1
    }
}

// MARK: - Alerts

/// A moment a contract's time left reaches a line: its alert, or zero.
/// Each device notifies once for each, as `ContractAlertPlan` decides.
public struct ContractAlert: Hashable, Sendable {
    public enum Kind: String, Hashable, Sendable {
        /// The time left reached the contract's alert.
        case low
        /// The hours are used up.
        case usedUp
    }

    public var kind: Kind
    public var projectID: UUID
    public var contract: Contract
    /// When the time left reaches the line: now or earlier once it has,
    /// later while a running timer is on its way there.
    public var date: Timestamp
    /// The time left then.
    public var left: Int64
    /// Whether the project's timer is running.
    public var running: Bool

    /// Names the alert for one contract, its hours and its line, so a
    /// changed contract alerts again.
    public var key: String {
        switch kind {
        case .low: "contract-\(contract.id.uuidString)-low-\(contract.hours)-\(contract.alertsAt)"
        case .usedUp: "contract-\(contract.id.uuidString)-out-\(contract.hours)"
        }
    }
}

extension Ledger {
    /// The alerts of the contracts that hold `today`, of projects that
    /// aren't archived or deleted: those already reached, dated `now`,
    /// and those the running timer reaches later, dated then.
    public func contractAlerts(dayTotals: DayTotals, running: ResolvedEntry?, today: LocalDate, now: Timestamp) -> [ContractAlert] {
        var alerts: [ContractAlert] = []
        for project in projects.values where !project.isDeleted && !isArchived(project: project.id) {
            for contract in project.contracts where contract.days.contains(today) {
                let status = ContractStatus(contract: contract, projectID: project.id, dayTotals: dayTotals, today: today, now: now)
                let isRunning = running.map { $0.entry.projectID == project.id && contract.days.contains($0.entry.day) } ?? false
                func alert(_ kind: ContractAlert.Kind, line: Int64) {
                    if status.left <= line {
                        alerts.append(ContractAlert(kind: kind, projectID: project.id, contract: contract, date: now, left: status.left, running: isRunning))
                    } else if isRunning {
                        alerts.append(ContractAlert(kind: kind, projectID: project.id, contract: contract, date: now.adding(milliseconds: status.left - line), left: line, running: true))
                    }
                }
                if contract.alertTime > 0, contract.alertTime < contract.budget {
                    alert(.low, line: contract.alertTime)
                }
                alert(.usedUp, line: 0)
            }
        }
        return alerts.sorted { $0.key < $1.key }
    }
}

/// What to do about contract alerts on a device: which to show now, which
/// to schedule for a running timer, and which scheduled ones to take back.
/// The device remembers what it notified and scheduled, so each alert shows
/// once, whether it was scheduled or found when the data changed.
public struct ContractAlertPlan: Hashable, Sendable {
    /// Alerts to show now.
    public var post: [ContractAlert] = []
    /// Alerts to schedule for their date, replacing any scheduled before
    /// under the same key.
    public var schedule: [ContractAlert] = []
    /// Keys of scheduled alerts to take back.
    public var cancel: [String] = []
    /// The keys notified, to remember.
    public var notified: Set<String> = []
    /// The keys scheduled and when, to remember.
    public var scheduled: [String: Timestamp] = [:]

    /// How far a scheduled alert's date may move before it's scheduled again.
    static let slack: Int64 = 60000

    public init(alerts: [ContractAlert], notified: Set<String>, scheduled: [String: Timestamp], now: Timestamp) {
        let keys = Set(alerts.map(\.key))
        self.notified = notified.intersection(keys)
        // Used up first, which says more than the alert before it.
        let due = alerts.filter { $0.date <= now }.sorted { ($0.kind == .usedUp ? 0 : 1, $0.key) < ($1.kind == .usedUp ? 0 : 1, $1.key) }
        var postedUsedUp: Set<UUID> = []
        for alert in due where !self.notified.contains(alert.key) {
            self.notified.insert(alert.key)
            // Scheduled for a time that has come: the system showed it.
            if let date = scheduled[alert.key], date <= now.adding(milliseconds: Self.slack) {
                if alert.kind == .usedUp { postedUsedUp.insert(alert.contract.id) }
                continue
            }
            if alert.kind == .low, postedUsedUp.contains(alert.contract.id) {
                continue
            }
            if scheduled[alert.key] != nil {
                cancel.append(alert.key)
            }
            post.append(alert)
            if alert.kind == .usedUp { postedUsedUp.insert(alert.contract.id) }
        }
        for alert in alerts where alert.date > now && !self.notified.contains(alert.key) {
            if let date = scheduled[alert.key], abs(date.distance(to: alert.date)) < Self.slack {
                self.scheduled[alert.key] = date
            } else {
                schedule.append(alert)
                self.scheduled[alert.key] = alert.date
            }
        }
        for (key, date) in scheduled where self.scheduled[key] == nil && date > now && !self.notified.contains(key) {
            cancel.append(key)
        }
        cancel.sort()
    }
}

// MARK: - Editing

/// Why a contract can't be kept.
public enum ContractError: Error, Hashable, Sendable {
    /// No hours, or an end before the start.
    case invalid
    /// It shares days with another of the project's contracts.
    case overlaps(Contract)
    /// There's no such project, or it's deleted.
    case noProject
}

extension Ledger {
    /// Adds a contract to a project, or changes the one with its id. Throws
    /// `ContractError` for a contract with no hours, an end before its
    /// start, or days another of the project's contracts has.
    @discardableResult
    public mutating func setContract(_ contract: Contract, ofProject projectID: UUID, now: Timestamp) throws -> Changes {
        guard let project = projects[projectID], !project.isDeleted else { throw ContractError.noProject }
        guard contract.isValid else { throw ContractError.invalid }
        if let other = project.contracts.first(where: { $0.id != contract.id && $0.overlaps(contract) }) {
            throw ContractError.overlaps(other)
        }
        return updateProject(projectID, now: now) { project in
            project.contracts.removeAll { $0.id == contract.id }
            project.contracts.append(contract)
            project.contracts.sort(by: Contract.fileOrder)
        }
    }

    /// Takes a contract off a project.
    @discardableResult
    public mutating func removeContract(_ id: UUID, fromProject projectID: UUID, now: Timestamp) -> Changes {
        updateProject(projectID, now: now) { project in
            project.contracts.removeAll { $0.id == id }
        }
    }
}

extension Contract {
    /// A new contract to follow the project's latest: as many hours, from
    /// the day after it ends for as many days. Without one, 40 hours over
    /// the month of `today`.
    public static func next(after contracts: [Contract], today: LocalDate) -> Contract {
        guard let latest = contracts.max(by: { $0.end < $1.end }) else {
            let first = LocalDate(year: today.year, month: today.month, day: 1)
            let last = LocalDate(year: today.year, month: today.month, day: LocalDate.daysIn(month: today.month, year: today.year))
            return Contract(hours: 40, start: first, end: last)
        }
        let start = latest.end.adding(days: 1)
        return Contract(hours: latest.hours, start: start, end: start.adding(days: latest.days.count - 1), alertHours: latest.alertHours)
    }
}
