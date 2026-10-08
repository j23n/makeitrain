import Foundation

/// Entries made from calendar events. Each calendar linked to a project
/// gives that project an entry for each of its events, with the event's
/// title as the note and no tags, in the device's time zone.
///
/// Events that aren't time spent working are left out: all-day events,
/// cancelled ones, invitations that were declined, events shown as free or
/// out of office, and events that take no time or more than a day. So are
/// events that haven't ended yet.
///
/// An entry made from an event takes the event's `entryID`, which the app
/// derives from the event's id on its calendar server. Importing an event
/// again, on this device or another, therefore finds its entry instead of
/// adding a second one, and an entry that was deleted stays deleted unless
/// the import asks for deleted ones.
public enum CalendarImport {
    /// An event in a calendar, as far as importing it goes.
    public struct Event: Hashable, Sendable {
        /// The id of the entry made from the event.
        public var entryID: UUID
        /// The calendar the event is in, as this device identifies it.
        public var calendarID: String
        public var title: String
        public var start: Timestamp
        public var end: Timestamp
        public var isAllDay: Bool
        public var isCancelled: Bool
        /// Whether the invitation was declined.
        public var isDeclined: Bool
        /// Whether the event is shown as free or out of office rather than busy.
        public var isFree: Bool

        public init(
            entryID: UUID,
            calendarID: String,
            title: String,
            start: Timestamp,
            end: Timestamp,
            isAllDay: Bool = false,
            isCancelled: Bool = false,
            isDeclined: Bool = false,
            isFree: Bool = false
        ) {
            self.entryID = entryID
            self.calendarID = calendarID
            self.title = title
            self.start = start
            self.end = end
            self.isAllDay = isAllDay
            self.isCancelled = isCancelled
            self.isDeclined = isDeclined
            self.isFree = isFree
        }
    }

    /// Why an event is left out.
    public enum Skip: CaseIterable, Hashable, Sendable {
        case allDay
        case cancelled
        case declined
        /// Shown as free or out of office.
        case free
        /// It ends when it starts, or earlier.
        case noTime
        /// It lasts more than a day.
        case tooLong
        /// It hasn't ended yet.
        case notOver
    }

    /// What importing events adds.
    public struct Plan: Sendable {
        public var entries: [TimeEntry] = []
        /// Events whose entry is already there.
        public var alreadyThere = 0
        /// Events whose entry was imported before and then deleted, as by
        /// undoing the import. They're among `entries` only when
        /// `includesDeleted` is set.
        public var deleted = 0
        /// Whether `entries` brings back the deleted ones.
        public var includesDeleted = false
        /// Events left out, by why.
        public var skipped: [Skip: Int] = [:]

        public init() {}

        /// The days the new entries are on, in their own time zones.
        public var days: ClosedRange<LocalDate>? {
            LocalDate.span(of: entries.map(\.day))
        }
    }

    /// The longest event that's imported: a day.
    static let longest: Int64 = 86_400_000

    /// What importing `events` adds to `ledger`, without adding anything.
    /// `projects` has the project of each linked calendar, by calendar id;
    /// events in other calendars are ignored.
    public static func plan(
        _ events: [Event],
        projects: [String: UUID],
        into ledger: Ledger,
        timeZone: String,
        includingDeleted: Bool = false,
        now: Timestamp
    ) -> Plan {
        var plan = Plan()
        plan.includesDeleted = includingDeleted
        var existing = Set<String>()
        for entry in ledger.entries.values where !entry.isDeleted {
            if let end = entry.end {
                existing.insert(key(start: entry.start, end: end, projectID: entry.projectID, note: entry.note))
            }
        }
        var seen = Set<UUID>()
        let sorted = events.sorted { ($0.start, $0.entryID.uuidString) < ($1.start, $1.entryID.uuidString) }
        for event in sorted {
            guard let projectID = projects[event.calendarID] else { continue }
            if let reason = skip(event, now: now) {
                plan.skipped[reason, default: 0] += 1
                continue
            }
            let start = event.start.wholeSeconds
            let end = event.end.wholeSeconds
            let note = event.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let match = key(start: start, end: end, projectID: projectID, note: note)
            guard seen.insert(event.entryID).inserted else {
                plan.alreadyThere += 1
                continue
            }
            if let entry = ledger.entries[event.entryID] {
                guard entry.isDeleted else {
                    plan.alreadyThere += 1
                    continue
                }
                plan.deleted += 1
                guard includingDeleted else { continue }
                existing.insert(match)
            } else if !existing.insert(match).inserted {
                // An entry with the same times, project and note, as when
                // another device imported the event under another id.
                plan.alreadyThere += 1
                continue
            }
            plan.entries.append(TimeEntry(
                id: event.entryID,
                projectID: projectID,
                start: start,
                end: end,
                timeZone: timeZone,
                note: note,
                updated: now
            ))
        }
        return plan
    }

    /// Why an event isn't imported, or nil if it is.
    static func skip(_ event: Event, now: Timestamp) -> Skip? {
        if event.isAllDay { return .allDay }
        if event.isCancelled { return .cancelled }
        if event.isDeclined { return .declined }
        if event.isFree { return .free }
        let length = event.start.wholeSeconds.distance(to: event.end.wholeSeconds)
        if length <= 0 { return .noTime }
        if length > longest { return .tooLong }
        if event.end > now { return .notOver }
        return nil
    }

    static func key(start: Timestamp, end: Timestamp, projectID: UUID?, note: String) -> String {
        "\(start.wholeSeconds.milliseconds)\u{1F}\(end.wholeSeconds.milliseconds)\u{1F}\(projectID?.uuidString ?? "")\u{1F}\(note)"
    }
}

extension Ledger {
    /// Adds the entries a plan made from calendar events. An entry whose id
    /// is taken by now, as when another device imported the same event in
    /// the meantime, stays as it is, unless the plan brings back deleted
    /// entries and that one is deleted.
    @discardableResult
    public mutating func add(_ plan: CalendarImport.Plan, now: Timestamp) -> Changes {
        var changes = settleOvertakenTimers(now: now)
        for entry in plan.entries {
            guard let current = entries[entry.id] else {
                changes.formUnion(addEntry(entry, now: now))
                continue
            }
            guard plan.includesDeleted, current.isDeleted else { continue }
            changes.formUnion(updateEntry(entry.id, now: now) { restored in
                restored.projectID = entry.projectID
                restored.start = entry.start
                restored.end = entry.end
                restored.timeZone = entry.timeZone
                restored.tags = entry.tags
                restored.note = entry.note
                restored.deleted = nil
            })
        }
        return changes
    }
}
