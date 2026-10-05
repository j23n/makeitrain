import Foundation
import Testing
@testable import TrackerCore

/// The week of 28 September 2026 as the designs show it, with five things
/// to correct.
@Suite struct CorrectionTests {
    typealias F = CommandFixture
    let week = LocalDate(year: 2026, month: 9, day: 28)...LocalDate(year: 2026, month: 10, day: 4)
    let now = CommandFixture.at("10:40")
    let calendar = "northbridge-exchange"

    var ledger: Ledger {
        let q = F.bookings
        return Ledger(clients: F.records.clients, projects: F.records.projects, entries: [
            // Earlier weeks, for when the day usually ends.
            F.entry(20, q, "2026-09-21", "09:00", "18:00"),
            F.entry(21, q, "2026-09-22", "09:00", "17:30"),
            F.entry(22, q, "2026-09-23", "09:00", "18:30"),
            F.entry(8, q, "2026-09-28", "09:00", "18:00"),
            // Sprint planning came in from the calendar while the timer ran.
            F.entry(1, q, "2026-09-29", "09:00", "12:40", tags: ["#227"], note: "Export to PDF"),
            F.entry(2, q, "2026-09-29", "11:00", "12:00", note: "Sprint planning"),
            F.entry(9, q, "2026-09-29", "13:30", "18:00", note: "Bug fix"),
            // Spec runs 20 minutes into Tests.
            F.entry(3, q, "2026-09-30", "13:15", "15:00", note: "Spec"),
            F.entry(4, q, "2026-09-30", "14:40", "18:00", note: "Tests"),
            // No project, and a timer left running overnight.
            F.entry(6, nil, "2026-10-01", "12:30", "12:55", note: "Call with tax advisor"),
            F.entry(5, q, "2026-10-01", "13:30", "08:55", note: "Refactoring", endDay: "2026-10-02"),
            F.entry(7, q, "2026-10-02", "08:55", "16:30", note: "Refactoring"),
        ])
    }

    var events: [CalendarImport.Event] {
        [
            // Not logged.
            CalendarImport.Event(entryID: uuid(500), calendarID: calendar, title: "Retro", start: F.at("16:30", on: "2026-10-02"), end: F.at("17:15", on: "2026-10-02")),
            // Logged already: the timer ran through it.
            CalendarImport.Event(entryID: uuid(501), calendarID: calendar, title: "Standup", start: F.at("09:00", on: "2026-10-02"), end: F.at("09:15", on: "2026-10-02")),
        ]
    }

    func find(in ledger: Ledger) -> [Correction] {
        Corrections.find(
            on: week,
            ledger: ledger,
            resolved: ledger.resolvedEntries(),
            events: events,
            calendarProjects: [calendar: F.bookings],
            timeZone: F.zone,
            now: now
        )
    }

    @Test func findsTheWeeksFiveCorrectionsInOrder() {
        let corrections = find(in: ledger)
        #expect(corrections.count == 5)
        #expect(corrections.map(\.day) == [
            LocalDate(year: 2026, month: 9, day: 29),
            LocalDate(year: 2026, month: 9, day: 30),
            LocalDate(year: 2026, month: 10, day: 1),
            LocalDate(year: 2026, month: 10, day: 1),
            LocalDate(year: 2026, month: 10, day: 2),
        ])

        guard case let .overlap(inside) = corrections[0].kind else {
            Issue.record("Expected an overlap first")
            return
        }
        #expect(inside.earlier == uuid(1) && inside.later == uuid(2))
        #expect(corrections[0].fixes == [
            .overlap(.split(outer: uuid(1), inner: uuid(2))),
            .overlap(.trimEarlier(id: uuid(1), end: F.at("11:00", on: "2026-09-29"))),
        ])

        #expect(corrections[1].fixes == [
            .overlap(.trimEarlier(id: uuid(3), end: F.at("14:40", on: "2026-09-30"))),
            .overlap(.trimLater(id: uuid(4), start: F.at("15:00", on: "2026-09-30"))),
        ])

        #expect(corrections[2].kind == .noProject(id: uuid(6)))
        #expect(corrections[2].fixes.isEmpty)

        // The day usually ends at 18:00.
        #expect(corrections[3].kind == .ranLong(id: uuid(5), overnight: true))
        #expect(corrections[3].fixes == [
            .end(id: uuid(5), at: F.at("18:00", on: "2026-10-01")),
            .end(id: uuid(5), at: F.at("17:00", on: "2026-10-01")),
            .end(id: uuid(5), at: F.at("19:00", on: "2026-10-01")),
        ])

        guard case let .notLogged(entry) = corrections[4].kind else {
            Issue.record("Expected an event last")
            return
        }
        #expect(entry.id == uuid(500))
        #expect(entry.projectID == F.bookings)
        #expect(entry.note == "Retro")
        #expect(corrections[4].fixes == [.add(entry)])
    }

    @Test func suggestsTheProjectOfAnEntryWithTheSameNote() {
        var ledger = self.ledger
        ledger.merge(F.entry(30, F.internal, "2026-09-15", "12:00", "12:30", note: "Call with tax advisor"))
        let correction = find(in: ledger).first { $0.kind == .noProject(id: uuid(6)) }
        #expect(correction?.fixes == [.assign(id: uuid(6), projectID: F.internal)])
    }

    @Test func aTimerRunningMoreThanTwelveHoursNeedsCorrecting() {
        let running = Ledger(entries: [F.entry(40, F.bookings, "2026-10-05", "08:00", nil)])
        let today = LocalDate(year: 2026, month: 10, day: 5)
        let late = Corrections.find(on: today...today, ledger: running, resolved: running.resolvedEntries(), timeZone: F.zone, now: F.at("20:30"))
        #expect(late.map(\.kind) == [.ranLong(id: uuid(40), overnight: false)])
        // With nothing to go by, the day ends at 18:00.
        #expect(late.first?.fixes.first == .end(id: uuid(40), at: F.at("18:00")))
        let early = Corrections.find(on: today...today, ledger: running, resolved: running.resolvedEntries(), timeZone: F.zone, now: F.at("19:30"))
        #expect(early.isEmpty)
    }

    @Test func acceptingTheSuggestionsLeavesWhatTakesAChoice() {
        var ledger = self.ledger
        let ids = Set(find(in: ledger).map(\.id))
        let changes = Corrections.applySuggestions(
            ids,
            to: &ledger,
            on: week,
            events: events,
            calendarProjects: [calendar: F.bookings],
            timeZone: F.zone,
            now: now
        )
        #expect(changes.months == [MonthKey(year: 2026, month: 9), MonthKey(year: 2026, month: 10)])
        #expect(ledger.entries[uuid(1)]?.end == F.at("11:00", on: "2026-09-29"))
        #expect(ledger.entries[uuid(3)]?.end == F.at("14:40", on: "2026-09-30"))
        #expect(ledger.entries[uuid(5)]?.end == F.at("18:00", on: "2026-10-01"))
        #expect(ledger.entries[uuid(500)]?.note == "Retro")
        #expect(find(in: ledger).map(\.kind) == [.noProject(id: uuid(6))])
    }

    @Test func movesTheSeamBetweenTwoEntries() {
        var ledger = self.ledger
        ledger.moveSeam(earlier: uuid(3), later: uuid(4), to: F.at("14:50", on: "2026-09-30"), now: now)
        #expect(ledger.entries[uuid(3)]?.end == F.at("14:50", on: "2026-09-30"))
        #expect(ledger.entries[uuid(4)]?.start == F.at("14:50", on: "2026-09-30"))
        // It stays at least a minute inside both.
        ledger.moveSeam(earlier: uuid(3), later: uuid(4), to: F.at("12:00", on: "2026-09-30"), now: now)
        #expect(ledger.entries[uuid(3)]?.end == F.at("13:16", on: "2026-09-30"))
        // An entry inside another has no seam with it.
        let before = ledger
        let changes = ledger.moveSeam(earlier: uuid(1), later: uuid(2), to: F.at("11:30", on: "2026-09-29"), now: now)
        #expect(changes.isEmpty)
        #expect(ledger == before)
    }

    @Test func totalsDaysOnceForCalendarsAndCharts() {
        let ledger = F.ledger([F.runningBookings])
        let totals = DayTotals(ledger.resolvedEntries())
        let friday = LocalDate(year: 2026, month: 10, day: 2)
        let monday = LocalDate(year: 2026, month: 10, day: 5)
        #expect(totals.projects(on: friday) == [F.bookings: 195 * 60000])
        #expect(totals.total(on: monday) == 60 * 60000)
        #expect(totals.total(on: monday, now: F.at("10:40")) == 130 * 60000)
        #expect(totals.total(on: monday, now: F.at("10:40"), projects: [F.internal]) == 60 * 60000)
        #expect(totals.total(in: week) == (80 + 195) * 60000)
        #expect(totals.loggedDays.count == 3)
    }

    @Test func overlapsOfferEveryFix() {
        let ledger = Ledger(entries: [
            F.entry(1, nil, "2026-10-01", "09:00", "10:00"),
            F.entry(2, nil, "2026-10-01", "09:00", "09:30"),
        ])
        let overlap = Overlaps.analyze(ledger.resolvedEntries(), now: now).overlaps.first
        // Same start: the longer one starts when the shorter one ends.
        #expect(overlap?.fixes == [.trimLater(id: uuid(1), start: F.at("09:30", on: "2026-10-01"))])
        var fixed = ledger
        fixed.apply(OverlapFix.trimLater(id: uuid(1), start: F.at("09:30", on: "2026-10-01")), now: now)
        #expect(fixed.entries[uuid(1)]?.start == F.at("09:30", on: "2026-10-01"))
    }
}
