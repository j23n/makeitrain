import Foundation
import Testing
import TrackerCore
@testable import TrackerKit

/// Calendars, played by lists the test fills.
@MainActor
final class FakeCalendars: CalendarProvider {
    var access = CalendarAccess.granted
    var onChange: (() -> Void)?
    var list: [CalendarInfo] = []
    var sample: [CalendarImport.Event] = []

    func requestAccess() async -> CalendarAccess { access }

    func calendars() -> [CalendarInfo] {
        access == .granted ? list : []
    }

    func events(inCalendars ids: Set<String>, from start: Timestamp, to end: Timestamp) -> [CalendarImport.Event] {
        sample.filter { ids.contains($0.calendarID) && $0.start < end && $0.end > start }
    }
}

@Suite @MainActor struct CalendarTests {
    func at(_ text: String) -> Timestamp {
        DateTimeFormat.parse(text)!
    }

    @Test func makesNameBasedUUIDs() {
        // The example in Python's documentation.
        let dns = UUID(uuidString: "6BA7B810-9DAD-11D1-80B4-00C04FD430C8")!
        let expected = UUID(uuidString: "886313E1-3B8A-5372-9B90-0C9AEE199E5D")!
        #expect(UUID(version5: dns, name: "python.org") == expected)
    }

    @Test func givesEachEventOneEntryID() {
        let kickoff = CalendarEntryID.forEvent(externalID: "kickoff@acme.example", occurrence: nil)
        #expect(kickoff == CalendarEntryID.forEvent(externalID: "kickoff@acme.example", occurrence: nil))
        // Each occurrence of a repeating event gets its own.
        let monday = CalendarEntryID.forEvent(externalID: "standup", occurrence: at("2026-09-21T09:30:00+02:00").date)
        let tuesday = CalendarEntryID.forEvent(externalID: "standup", occurrence: at("2026-09-22T09:30:00+02:00").date)
        #expect(monday != tuesday)
        #expect(monday != CalendarEntryID.forEvent(externalID: "standup", occurrence: nil))
        let version: UInt8 = monday.uuid.6 >> 4
        #expect(version == 5)
    }

    @Test func followsCalendarsWhoseIDsChanged() {
        let links = [
            CalendarLink(calendarID: "old-acme", title: "Calendar", account: "jo@acme.example", projectID: UUID()),
            CalendarLink(calendarID: "globex", title: "Globex", account: "Google", projectID: UUID()),
            CalendarLink(calendarID: "gone", title: "Old client", account: "Exchange", projectID: UUID()),
        ]
        let calendars = [
            CalendarInfo(id: "new-acme", title: "Calendar", account: "jo@acme.example", color: "#0078D4"),
            CalendarInfo(id: "globex", title: "Globex, renamed", account: "Google", color: "#33B679"),
            CalendarInfo(id: "home", title: "Home", account: "iCloud", color: "#34C759"),
        ]
        let relinked = CalendarLink.relinked(links, to: calendars)
        #expect(relinked.map(\.calendarID) == ["new-acme", "globex", "gone"])
        #expect(relinked.map(\.title) == ["Calendar", "Globex, renamed", "Old client"])
        #expect(relinked.map(\.projectID) == links.map(\.projectID))
    }

    @Test func importsEventsFromLinkedCalendarsAsOneStep() async throws {
        let harness = Harness()
        defer { harness.cleanUp() }
        let calendars = FakeCalendars()
        calendars.list = [
            CalendarInfo(id: "acme", title: "Calendar", account: "jo@acme.example", color: "#0078D4"),
            CalendarInfo(id: "home", title: "Home", account: "iCloud", color: "#34C759"),
        ]
        let kickoff = CalendarEntryID.forEvent(externalID: "kickoff", occurrence: nil)
        calendars.sample = [
            CalendarImport.Event(
                entryID: kickoff, calendarID: "acme", title: "Kickoff",
                start: at("2026-09-22T09:00:00+02:00"), end: at("2026-09-22T10:00:00+02:00")
            ),
            CalendarImport.Event(
                entryID: UUID(), calendarID: "acme", title: "Last week",
                start: at("2026-09-15T09:00:00+02:00"), end: at("2026-09-15T10:00:00+02:00")
            ),
            CalendarImport.Event(
                entryID: UUID(), calendarID: "home", title: "Dentist",
                start: at("2026-09-22T08:00:00+02:00"), end: at("2026-09-22T08:45:00+02:00")
            ),
        ]
        let model = harness.model(calendars: calendars)
        await model.start()
        model.refreshCalendars()
        #expect(model.calendars.map(\.id) == ["acme", "home"])
        #expect(!model.hasLinkedCalendars)

        let website = model.addProject(named: "Website", client: nil, color: "#4F7CAC", undoManager: nil)
        model.link(calendars.list[0], to: website)
        #expect(model.linkedProject(of: "acme") == website)
        #expect(model.hasLinkedCalendars)
        // Links are this device's settings.
        let relaunched = harness.model()
        #expect(relaunched.calendarLinks == model.calendarLinks)

        let monday = LocalDate(year: 2026, month: 9, day: 21)
        let tuesday = LocalDate(year: 2026, month: 9, day: 22)
        let plan = model.calendarImportPlan(from: monday, through: tuesday)
        #expect(plan.entries.map(\.id) == [kickoff])
        #expect(plan.entries.map(\.note) == ["Kickoff"])

        let undo = UndoManager()
        undo.groupsByEvent = false
        undo.beginUndoGrouping()
        model.importEvents(plan, undoManager: undo)
        undo.endUndoGrouping()
        #expect(undo.undoActionName == "Import Events")
        #expect(model.resolved.map(\.id) == [kickoff])
        #expect(model.calendarImportPlan(from: monday, through: tuesday).alreadyThere == 1)

        // Undoing deletes the entry, so importing it again takes a choice.
        undo.undo()
        #expect(model.resolved.isEmpty)
        let again = model.calendarImportPlan(from: monday, through: tuesday)
        #expect(again.entries.isEmpty)
        #expect(again.deleted == 1)
        model.importEvents(model.calendarImportPlan(from: monday, through: tuesday, includingDeleted: true), undoManager: nil)
        #expect(model.resolved.map(\.id) == [kickoff])

        // Unlinking the calendar leaves nothing to import.
        model.link(calendars.list[0], to: nil)
        #expect(!model.hasLinkedCalendars)
        #expect(model.calendarImportPlan(from: monday, through: tuesday).entries.isEmpty)
    }
}
