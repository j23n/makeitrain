import Foundation
import Testing
@testable import TrackerCore

@Suite struct CalendarImportTests {
    let now = t("2026-09-27T12:00:00+02:00")
    let berlin = "Europe/Berlin"
    let website = uuid(10)
    let internalWork = uuid(11)
    /// The Acme calendar goes to Website and the team calendar to Internal;
    /// the holidays calendar isn't linked.
    var projects: [String: UUID] {
        ["acme": website, "team": internalWork]
    }

    func event(
        _ number: Int,
        in calendar: String = "acme",
        _ title: String,
        from start: String,
        to end: String,
        isAllDay: Bool = false,
        isCancelled: Bool = false,
        isDeclined: Bool = false,
        isFree: Bool = false
    ) -> CalendarImport.Event {
        CalendarImport.Event(
            entryID: uuid(number),
            calendarID: calendar,
            title: title,
            start: t(start),
            end: t(end),
            isAllDay: isAllDay,
            isCancelled: isCancelled,
            isDeclined: isDeclined,
            isFree: isFree
        )
    }

    func plan(_ events: [CalendarImport.Event], into ledger: Ledger = Ledger(), includingDeleted: Bool = false) -> CalendarImport.Plan {
        CalendarImport.plan(events, projects: projects, into: ledger, timeZone: berlin, includingDeleted: includingDeleted, now: now)
    }

    @Test func turnsEventsIntoEntries() {
        let result = plan([
            event(2, in: "team", "  Planning ", from: "2026-09-24T13:00:00+02:00", to: "2026-09-24T13:45:30+02:00"),
            event(1, "Design review", from: "2026-09-23T15:00:00-04:00", to: "2026-09-23T16:00:00-04:00"),
            event(3, in: "holidays", "Not linked", from: "2026-09-25T09:00:00+02:00", to: "2026-09-25T10:00:00+02:00"),
        ])
        #expect(result.entries.map(\.id) == [uuid(1), uuid(2)])
        #expect(result.entries.compactMap(\.projectID) == [website, internalWork])
        // The title is the note, and there are no tags.
        #expect(result.entries.map(\.note) == ["Design review", "Planning"])
        #expect(result.entries.allSatisfy { $0.tags.isEmpty })
        // Entries are in the device's time zone, in whole seconds.
        #expect(result.entries.allSatisfy { $0.timeZone == berlin })
        #expect(result.entries.map(\.start) == [t("2026-09-23T21:00:00+02:00"), t("2026-09-24T13:00:00+02:00")])
        #expect(result.entries.compactMap(\.end) == [t("2026-09-23T22:00:00+02:00"), t("2026-09-24T13:45:30+02:00")])
        #expect(result.days == LocalDate(year: 2026, month: 9, day: 23)...LocalDate(year: 2026, month: 9, day: 24))
        #expect(result.skipped.isEmpty)
        #expect(result.alreadyThere == 0)
    }

    @Test func leavesOutEventsThatArentWork() {
        let result = plan([
            event(1, "Holiday", from: "2026-09-21T00:00:00+02:00", to: "2026-09-22T00:00:00+02:00", isAllDay: true),
            event(2, "Moved", from: "2026-09-21T09:00:00+02:00", to: "2026-09-21T10:00:00+02:00", isCancelled: true),
            event(3, "Not going", from: "2026-09-21T10:00:00+02:00", to: "2026-09-21T11:00:00+02:00", isDeclined: true),
            event(4, "Focus time", from: "2026-09-21T11:00:00+02:00", to: "2026-09-21T12:00:00+02:00", isFree: true),
            event(5, "Deadline", from: "2026-09-21T17:00:00+02:00", to: "2026-09-21T17:00:00+02:00"),
            event(6, "Conference", from: "2026-09-22T09:00:00+02:00", to: "2026-09-24T17:00:00+02:00"),
            event(7, "Right now", from: "2026-09-27T11:30:00+02:00", to: "2026-09-27T12:30:00+02:00"),
            event(8, "Next week", from: "2026-09-28T09:00:00+02:00", to: "2026-09-28T10:00:00+02:00"),
            event(9, "Worked", from: "2026-09-27T11:00:00+02:00", to: "2026-09-27T12:00:00+02:00"),
        ])
        let skipped: [CalendarImport.Skip: Int] = [
            .allDay: 1, .cancelled: 1, .declined: 1, .free: 1, .noTime: 1, .tooLong: 1, .notOver: 2,
        ]
        #expect(result.skipped == skipped)
        // One that ended just now counts.
        #expect(result.entries.map(\.note) == ["Worked"])
    }

    @Test func findsEntriesThatAreAlreadyThere() {
        let ledger = Ledger(entries: [
            // Imported before, then edited.
            TimeEntry(
                id: uuid(1), projectID: website, start: t("2026-09-23T09:00:00+02:00"), end: t("2026-09-23T09:50:00+02:00"),
                timeZone: berlin, note: "Kickoff, shortened", updated: now
            ),
            // Imported on another device, under another id.
            TimeEntry(
                id: uuid(40), projectID: website, start: t("2026-09-23T11:00:00+02:00"), end: t("2026-09-23T12:00:00+02:00"),
                timeZone: berlin, note: "Review", updated: now
            ),
        ])
        let result = plan([
            event(1, "Kickoff", from: "2026-09-23T09:00:00+02:00", to: "2026-09-23T10:00:00+02:00"),
            event(2, "Review", from: "2026-09-23T11:00:00+02:00", to: "2026-09-23T12:00:00+02:00"),
            // The same event twice, as when it's in two calendars.
            event(3, "Lunch talk", from: "2026-09-23T13:00:00+02:00", to: "2026-09-23T14:00:00+02:00"),
            event(3, in: "team", "Lunch talk", from: "2026-09-23T13:00:00+02:00", to: "2026-09-23T14:00:00+02:00"),
        ], into: ledger)
        #expect(result.entries.map(\.note) == ["Lunch talk"])
        #expect(result.alreadyThere == 3)
    }

    @Test func keepsDeletedEntriesDeletedUnlessAsked() {
        var ledger = Ledger(entries: [
            TimeEntry(
                id: uuid(1), projectID: website, start: t("2026-09-23T09:00:00+02:00"), end: t("2026-09-23T10:00:00+02:00"),
                timeZone: berlin, note: "Kickoff", updated: t("2026-09-24T09:00:00+02:00")
            ),
        ])
        // Deleted with a clock ahead of this device's.
        ledger.deleteEntry(uuid(1), now: t("2026-09-28T09:00:00+02:00"))
        let events = [event(1, "Kickoff", from: "2026-09-23T09:00:00+02:00", to: "2026-09-23T10:00:00+02:00")]

        let kept = plan(events, into: ledger)
        #expect(kept.entries.isEmpty)
        #expect(kept.deleted == 1)
        #expect(kept.alreadyThere == 0)

        let restoring = plan(events, into: ledger, includingDeleted: true)
        #expect(restoring.entries.map(\.id) == [uuid(1)])
        #expect(restoring.deleted == 1)
        let changes = ledger.add(restoring, now: now)
        let september: Set<MonthKey> = [MonthKey(year: 2026, month: 9)]
        #expect(changes.months == september)
        let restored = ledger.entries[uuid(1)]
        #expect(restored?.isDeleted == false)
        #expect(restored?.note == "Kickoff")
        #expect(restored?.projectID == website)
        // It beats the deletion wherever the copies meet.
        #expect((restored?.updated ?? now) > t("2026-09-28T09:00:00+02:00"))
    }

    @Test func addingLeavesEntriesTakenInTheMeantime() {
        var ledger = Ledger()
        let result = plan([event(1, "Kickoff", from: "2026-09-23T09:00:00+02:00", to: "2026-09-23T10:00:00+02:00")], into: ledger)
        // Another device imports the event and deletes the entry before this one adds it.
        ledger.merge(TimeEntry(
            id: uuid(1), projectID: website, start: t("2026-09-23T09:00:00+02:00"), end: t("2026-09-23T10:00:00+02:00"),
            timeZone: berlin, updated: now, deleted: now
        ))
        let changes = ledger.add(result, now: now)
        #expect(changes.months.isEmpty)
        #expect(ledger.entries[uuid(1)]?.isDeleted == true)

        var empty = Ledger()
        empty.add(result, now: now)
        #expect(empty.entries[uuid(1)]?.note == "Kickoff")
        #expect(empty.entries[uuid(1)]?.updated == now)
    }
}
