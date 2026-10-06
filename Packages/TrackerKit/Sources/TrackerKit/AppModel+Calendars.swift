import Foundation
import TrackerCore

// Linking this device's calendars to projects, and importing their events
// as entries.

extension AppModel {
    /// Reads this device's calendars again, and follows linked calendars
    /// whose ids changed.
    public func refreshCalendars() {
        guard let provider = environment.calendars else { return }
        calendarAccess = provider.access
        calendars = provider.calendars()
        let relinked = CalendarLink.relinked(calendarLinks, to: calendars)
        if relinked != calendarLinks {
            calendarLinks = relinked
        }
    }

    /// Asks for access to the calendars. The system asks only the first time.
    public func requestCalendarAccess() async {
        guard let provider = environment.calendars else { return }
        calendarAccess = await provider.requestAccess()
        refreshCalendars()
    }

    /// The project a calendar's events become entries for, or nil if it
    /// isn't linked or its project was deleted.
    public func linkedProject(of calendarID: String) -> UUID? {
        guard let link = calendarLinks.first(where: { $0.calendarID == calendarID }),
              ledger.projects[link.projectID]?.isDeleted == false
        else { return nil }
        return link.projectID
    }

    /// The calendar on this device whose events become entries for a
    /// project, if there is one.
    public func linkedCalendar(ofProject projectID: UUID) -> CalendarInfo? {
        let linked = Set(calendarLinks.filter { $0.projectID == projectID }.map(\.calendarID))
        return calendars.first { linked.contains($0.id) }
    }

    /// Links a calendar on this device to a project in place of the
    /// project's other calendars, or unlinks the project's calendars.
    public func setCalendar(_ calendarID: String?, forProject projectID: UUID) {
        var links = calendarLinks.filter { $0.projectID != projectID && $0.calendarID != calendarID }
        if let calendarID, let calendar = calendars.first(where: { $0.id == calendarID }) {
            links.append(CalendarLink(calendarID: calendar.id, title: calendar.title, account: calendar.account, projectID: projectID))
        }
        calendarLinks = links
    }

    /// Whether a calendar on this device is linked to a project.
    public var hasLinkedCalendars: Bool {
        calendars.contains { linkedProject(of: $0.id) != nil }
    }

    /// What importing the events that start on the days from `first`
    /// through `last` adds, without adding anything. Only linked calendars
    /// are read.
    public func calendarImportPlan(from first: LocalDate, through last: LocalDate, includingDeleted: Bool = false) -> CalendarImport.Plan {
        guard let provider = environment.calendars else { return CalendarImport.Plan() }
        var projects: [String: UUID] = [:]
        for link in calendarLinks {
            if let projectID = linkedProject(of: link.calendarID) {
                projects[link.calendarID] = projectID
            }
        }
        guard !projects.isEmpty else { return CalendarImport.Plan() }
        let zone = environment.timeZone()
        let start = Timestamp(date: first, secondOfDay: 0, zone: zone)
        let end = Timestamp(date: last.adding(days: 1), secondOfDay: 0, zone: zone)
        // An event that started the day before belongs to that day's import.
        let events = provider.events(inCalendars: Set(projects.keys), from: start, to: end)
            .filter { $0.start >= start && $0.start < end }
        return CalendarImport.plan(
            events,
            projects: projects,
            into: ledger,
            timeZone: zone,
            includingDeleted: includingDeleted,
            now: environment.now()
        )
    }

    /// Adds what a calendar import plan found, as one step to undo.
    public func importEvents(_ plan: CalendarImport.Plan, undoManager: UndoManager?) {
        edit("Import Events", undoManager: undoManager) { ledger, now in
            ledger.add(plan, now: now)
        }
    }
}
