import Foundation
import TrackerCore

// What needs correcting, from the entries and this device's linked
// calendars, and fixing it.

extension AppModel {
    /// The events in this device's linked calendars that start on the days
    /// given, and each linked calendar's project, by calendar id.
    public func calendarEvents(on days: ClosedRange<LocalDate>) -> (events: [CalendarImport.Event], projects: [String: UUID]) {
        guard let provider = environment.calendars, calendarAccess == .granted else { return ([], [:]) }
        var projects: [String: UUID] = [:]
        for link in calendarLinks {
            if let projectID = linkedProject(of: link.calendarID) {
                projects[link.calendarID] = projectID
            }
        }
        guard !projects.isEmpty else { return ([], [:]) }
        let zone = environment.timeZone()
        let start = Timestamp(date: days.lowerBound, secondOfDay: 0, zone: zone)
        let end = Timestamp(date: days.upperBound.adding(days: 1), secondOfDay: 0, zone: zone)
        let events = provider.events(inCalendars: Set(projects.keys), from: start, to: end)
            .filter { $0.start >= start && $0.start < end }
        return (events, projects)
    }

    /// What needs correcting on some days, in order, leaving out what was
    /// skipped on this device.
    public func corrections(on days: ClosedRange<LocalDate>, includingSkipped: Bool = false) -> [Correction] {
        let calendar = calendarEvents(on: days)
        let found = Corrections.find(
            on: days,
            ledger: ledger,
            resolved: resolved,
            events: calendar.events,
            calendarProjects: calendar.projects,
            timeZone: environment.timeZone(),
            now: environment.now()
        )
        guard !includingSkipped else { return found }
        return found.filter { !preferences.isSkipped($0.id) }
    }

    /// Applies a correction's fix, as one step to undo.
    public func apply(_ fix: CorrectionFix, undoManager: UndoManager?) {
        edit(Self.actionName(of: fix), undoManager: undoManager) { ledger, now in
            ledger.apply(fix, now: now)
        }
    }

    /// Applies the suggested fix of each correction with one, as one step
    /// to undo.
    public func acceptSuggestions(of corrections: [Correction], on days: ClosedRange<LocalDate>, undoManager: UndoManager?) {
        let ids = Set(corrections.filter { $0.suggestion != nil }.map(\.id))
        guard !ids.isEmpty else { return }
        let calendar = calendarEvents(on: days)
        let zone = environment.timeZone()
        edit(ids.count == 1 ? "Accept Correction" : "Accept Corrections", undoManager: undoManager) { ledger, now in
            Corrections.applySuggestions(
                ids,
                to: &ledger,
                on: days,
                events: calendar.events,
                calendarProjects: calendar.projects,
                timeZone: zone,
                now: now
            )
        }
    }

    /// The ledger as it would be with the suggested fixes accepted, for
    /// showing the totals they'd make.
    public func ledgerWithSuggestions(of corrections: [Correction], on days: ClosedRange<LocalDate>) -> Ledger {
        var copy = ledger
        let calendar = calendarEvents(on: days)
        Corrections.applySuggestions(
            Set(corrections.filter { $0.suggestion != nil }.map(\.id)),
            to: &copy,
            on: days,
            events: calendar.events,
            calendarProjects: calendar.projects,
            timeZone: environment.timeZone(),
            now: environment.now()
        )
        return copy
    }

    static func actionName(of fix: CorrectionFix) -> String {
        switch fix {
        case let .overlap(overlapFix):
            switch overlapFix {
            case .split: "Split Entry"
            case .trimEarlier, .trimLater: "Trim Entry"
            }
        case .end: "End Entry"
        case .assign: "Set Project"
        case .add: "Log Event"
        }
    }

    /// Moves the seam between two entries that meet or overlap.
    public func moveSeam(earlier: UUID, later: UUID, to time: Timestamp, undoManager: UndoManager?) {
        edit("Move Seam", undoManager: undoManager) { ledger, now in
            ledger.moveSeam(earlier: earlier, later: later, to: time, now: now)
        }
    }
}
