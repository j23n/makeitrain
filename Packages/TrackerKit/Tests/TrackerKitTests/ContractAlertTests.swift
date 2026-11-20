import Foundation
import Testing
import TrackerCore
@testable import TrackerKit

/// Notifications that are only written down.
@MainActor
final class FakeNotifications: NotificationProvider {
    struct Added: Equatable {
        var id: String
        var title: String
        var date: Date?
    }

    var allowed = true
    private(set) var added: [Added] = []
    private(set) var removed: [String] = []

    func requestAuthorization() async -> Bool { allowed }

    func add(id: String, title: String, body: String, at date: Date?) {
        added.append(Added(id: id, title: title, date: date))
    }

    func remove(ids: [String]) {
        removed += ids
    }
}

@Suite @MainActor struct ContractAlertTests {
    /// A started model with a project, "Website", that has `hours` logged
    /// an hour a day from September 1, and a contract of `contract` hours
    /// over September. The clock is at 09:00 on September 23.
    private func setUp(logged hours: Int, contract: Int, notifications: FakeNotifications) async -> (Harness, AppModel, UUID) {
        let harness = Harness()
        let model = harness.model(notifications: notifications)
        await model.start()
        let project = model.addProject(named: "Website", client: nil, color: "#4F7CAC", undoManager: nil)
        for day in 1...hours {
            var logged = entry(note: "Work", at: "2026-09-\(day < 10 ? "0" : "")\(day)T09:00:00+02:00")
            logged.projectID = project
            model.addEntry(logged, undoManager: nil)
        }
        try? model.setContract(
            Contract(hours: contract, start: LocalDate(year: 2026, month: 9, day: 1), end: LocalDate(year: 2026, month: 9, day: 30)),
            ofProject: project,
            undoManager: nil
        )
        return (harness, model, project)
    }

    /// Gives the model's notification tasks a moment to run.
    private func settle() async {
        try? await Task.sleep(for: .milliseconds(50))
    }

    @Test func alertsOnceWhenLowAndOnceWhenUsedUp() async throws {
        let notifications = FakeNotifications()
        let (harness, model, project) = await setUp(logged: 9, contract: 10, notifications: notifications)
        defer { harness.cleanUp() }

        // 9 of 10 hours: at the default alert of 1 hour left.
        await eventually { notifications.added.count == 1 }
        #expect(notifications.added.first?.title == "Website has 1:00 left")
        #expect(notifications.added.first?.date == nil)

        // Nothing new: no second notice.
        model.updateContractAlerts()
        await settle()
        #expect(notifications.added.count == 1)

        var last = entry(note: "Work", at: "2026-09-10T09:00:00+02:00")
        last.projectID = project
        model.addEntry(last, undoManager: nil)
        await eventually { notifications.added.count == 2 }
        #expect(notifications.added.last?.title == "Website's hours are used up")
    }

    @Test func schedulesARunningTimersAlertsAndTakesThemBack() async throws {
        let notifications = FakeNotifications()
        let (harness, model, project) = await setUp(logged: 8, contract: 10, notifications: notifications)
        defer { harness.cleanUp() }
        await settle()
        #expect(notifications.added.isEmpty)

        // 2 hours left: the alert is an hour away, and the end two.
        model.startTimer(EntryDraft(projectID: project), undoManager: nil)
        await eventually { notifications.added.count == 2 }
        let start = harness.clock.now.date
        let dates = Set(notifications.added.compactMap(\.date))
        #expect(dates == [start.addingTimeInterval(3600), start.addingTimeInterval(7200)])

        model.stopTimer(undoManager: nil)
        #expect(Set(notifications.removed) == Set(notifications.added.map(\.id)))
    }

    @Test func turningAlertsOffTakesBackScheduledOnes() async throws {
        let notifications = FakeNotifications()
        let (harness, model, project) = await setUp(logged: 8, contract: 10, notifications: notifications)
        defer { harness.cleanUp() }
        model.startTimer(EntryDraft(projectID: project), undoManager: nil)
        await eventually { notifications.added.count == 2 }

        model.preferences.contractAlerts = false
        model.updateContractAlerts()
        #expect(Set(notifications.removed) == Set(notifications.added.map(\.id)))
        #expect(model.preferences.scheduledContractAlerts.isEmpty)
    }
}
