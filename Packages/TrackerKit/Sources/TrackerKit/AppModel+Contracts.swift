import Foundation
import TrackerCore

extension AppModel {
    // MARK: - Status

    /// Where the project's contract stands today: the one that holds today,
    /// or else the next to start. Nil without one.
    public func contractStatus(ofProject projectID: UUID?) -> ContractStatus? {
        guard let projectID, let project = ledger.projects[projectID], !project.isDeleted,
              let contract = project.contract(on: today) else { return nil }
        return status(of: contract, projectID: projectID)
    }

    /// Where any of the project's contracts stands today, as for an earlier one.
    public func status(of contract: Contract, projectID: UUID) -> ContractStatus {
        ContractStatus(contract: contract, projectID: projectID, dayTotals: dayTotals, today: today, now: now)
    }

    /// The project's contract while its days hold today, as the running
    /// timer shows it.
    public func activeContract(ofProject projectID: UUID?) -> ContractStatus? {
        guard let status = contractStatus(ofProject: projectID), status.hasStarted, !status.hasEnded else { return nil }
        return status
    }

    // MARK: - Editing

    /// Adds a contract to a project, or changes one. Throws `ContractError`
    /// when it can't be kept, and changes nothing then.
    public func setContract(_ contract: Contract, ofProject projectID: UUID, undoManager: UndoManager?) throws {
        let isNew = ledger.projects[projectID]?.contracts.contains { $0.id == contract.id } != true
        try edit(isNew ? "Add Contract" : "Change Contract", undoManager: undoManager) { ledger, now in
            try ledger.setContract(contract, ofProject: projectID, now: now)
        }
    }

    /// Takes a contract off a project.
    public func removeContract(_ id: UUID, fromProject projectID: UUID, undoManager: UndoManager?) {
        edit("Remove Contract", undoManager: undoManager) { ledger, now in
            ledger.removeContract(id, fromProject: projectID, now: now)
        }
    }

    // MARK: - Alerts

    /// Shows the contract alerts that are due and schedules those a running
    /// timer reaches later, each once on this device, and takes back the
    /// ones scheduled for a timer that stopped. It runs whenever the data
    /// or the time changes, and Settings runs it when they're turned off
    /// or on.
    public func updateContractAlerts() {
        guard let notifications = environment.notifications, state == .ready else { return }
        guard preferences.contractAlerts else {
            let scheduled = preferences.scheduledContractAlerts
            if !scheduled.isEmpty {
                notifications.remove(ids: Array(scheduled.keys))
                preferences.rememberContractAlerts(notified: preferences.notifiedContractAlerts, scheduled: [:])
            }
            return
        }
        let current = environment.now()
        let alerts = ledger.contractAlerts(dayTotals: dayTotals, running: running, today: current.local(in: environment.timeZone()).date, now: current)
        let plan = ContractAlertPlan(
            alerts: alerts,
            notified: preferences.notifiedContractAlerts,
            scheduled: preferences.scheduledContractAlerts,
            now: current
        )
        if !plan.cancel.isEmpty {
            notifications.remove(ids: plan.cancel)
        }
        preferences.rememberContractAlerts(notified: plan.notified, scheduled: plan.scheduled)
        let messages = plan.post.map { (alert: $0, date: Date?.none) } + plan.schedule.map { (alert: $0, date: Date?.some($0.date.date)) }
        guard !messages.isEmpty else { return }
        let texts = messages.map { message(for: $0.alert) }
        Task {
            guard await notifications.requestAuthorization() else { return }
            for (index, item) in messages.enumerated() {
                notifications.add(id: item.alert.key, title: texts[index].title, body: texts[index].body, at: item.date)
            }
        }
    }

    /// What a contract alert says, such as "Mobile app has 4:00 left" and
    /// "Acme's contract: 36 h of 40 h used, until Nov 30. The timer is
    /// running."
    func message(for alert: ContractAlert) -> (title: String, body: String) {
        let name = ledger.projects[alert.projectID]?.name ?? "A project"
        let contract = alert.contract
        let owner = ledger.client(forProject: alert.projectID).map { "\($0.name)'s contract" } ?? "The contract"
        let until = Format.monthDay(contract.end)
        switch alert.kind {
        case .low:
            let used = contract.budget - alert.left
            let running = alert.running ? " The timer is running." : ""
            return (
                "\(name) has \(Format.duration(alert.left)) left",
                "\(owner): \(Format.duration(used)) of \(Format.hours(contract.hours)) used, until \(until).\(running)"
            )
        case .usedUp:
            return (
                "\(name)'s hours are used up",
                "\(owner): all \(Format.hours(contract.hours)) are used, until \(until). Time logged from now on counts as over."
            )
        }
    }
}
