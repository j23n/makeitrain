import Foundation
import Testing
@testable import TrackerCore

@Suite struct PerformTests {
    typealias F = CommandFixture
    let zone = CommandFixture.zone

    @Test func switchingAtAnEarlierTimeEndsTheRunningTimerThen() throws {
        var ledger = F.ledger(F.switchedToHarbor)
        let draft = EntryDraft(projectID: F.bookings, tags: ["#227"], note: "Export to PDF")
        try ledger.perform(.start(draft, at: F.at("11:05"), end: nil), timeZone: zone, now: F.at("12:20"), newID: uuid(200))
        #expect(ledger.entries[uuid(106)]?.end == F.at("11:05"))
        #expect(ledger.entries[uuid(200)]?.start == F.at("11:05"))
        #expect(ledger.runningEntry?.id == uuid(200))
    }

    @Test func previewsWhatAndOnlyWhatChanges() {
        let context = F.context(F.ledger(F.switchedToHarbor), now: "12:20")
        let reading = CommandReading("book #227 from 11:05", in: context)
        let preview = CommandPreview(reading.primary!, in: context)
        #expect(preview.diff.entries.count == 2)
        #expect(preview.diff.entries[0].before?.id == uuid(106))
        #expect(preview.diff.entries[0].before?.end == nil)
        #expect(preview.diff.entries[0].after?.end == F.at("11:05"))
        #expect(preview.diff.entries[1].isNew)
        #expect(preview.diff.entries[1].after?.start == F.at("11:05"))
        #expect(preview.newOverlaps.isEmpty)
        // Previewing changes nothing.
        #expect(context.ledger.entries[uuid(106)]?.end == nil)
    }

    @Test func loggingItAsDoneStopsItToo() throws {
        var ledger = F.ledger(F.switchedToHarbor)
        let draft = EntryDraft(projectID: F.bookings, note: "Review")
        try ledger.perform(.start(draft, at: F.at("11:05"), end: F.at("12:20")), timeZone: zone, now: F.at("12:20"), newID: uuid(200))
        #expect(ledger.entries[uuid(200)]?.end == F.at("12:20"))
        #expect(ledger.runningEntry == nil)
    }

    @Test func previewsTheOverlapsALogMakes() {
        let context = F.context(F.ledger(), now: "18:00")
        let command = Command.log(EntryDraft(projectID: F.harbor, note: "Review"), start: F.at("08:30"), end: F.at("09:30"))
        let preview = CommandPreview(command, in: context)
        #expect(preview.newOverlaps.count == 1)
        #expect(preview.newOverlaps.first?.earlier == uuid(105))
        #expect(preview.newOverlaps.first?.duration == Int64(30 * 60000))
    }

    @Test func previewsTheOverlapsWithATimerLeftRunning() {
        // Running since Saturday, it overlaps what's logged today.
        let forgotten = F.entry(107, F.harbor, "2026-10-03", "17:00", nil, note: "Release")
        let context = F.context(F.ledger([forgotten]), now: "18:00")
        let command = Command.log(EntryDraft(projectID: F.bookings, note: "Review"), start: F.at("16:00"), end: F.at("17:00"))
        let preview = CommandPreview(command, in: context)
        #expect(preview.newOverlaps.map(\.earlier) == [uuid(107)])
        #expect(preview.newOverlaps.first?.duration == Int64(60 * 60000))
    }

    @Test func movesTheRunningTimersStart() throws {
        var ledger = F.ledger([F.runningBookings])
        try ledger.perform(.moveStart(to: F.at("09:00")), timeZone: zone, now: F.at("10:40"))
        #expect(ledger.entries[uuid(103)]?.start == F.at("09:00"))
    }

    @Test func addsAProjectWithANewClientAndStartsATimerForIt() throws {
        var ledger = F.ledger()
        try ledger.perform(
            .addProject(name: "Phoenix", client: .new("Acme"), color: "#8064A2", startsTimer: true),
            timeZone: zone,
            now: F.at("10:40"),
            newID: uuid(300),
            newClientID: uuid(301),
            newEntryID: uuid(302)
        )
        #expect(ledger.clients[uuid(301)]?.name == "Acme")
        #expect(ledger.projects[uuid(300)]?.clientID == uuid(301))
        #expect(ledger.projects[uuid(300)]?.color == "#8064A2")
        #expect(ledger.entries[uuid(302)]?.projectID == uuid(300))
        #expect(ledger.runningEntry?.id == uuid(302))
    }

    @Test func managesProjects() throws {
        var ledger = F.ledger()
        let now = F.at("10:40")
        try ledger.perform(.archive(.project(F.harbor), archived: true), timeZone: zone, now: now)
        #expect(ledger.projects[F.harbor]?.archived == true)
        try ledger.perform(.setColor(project: F.bookings, color: "#4BACC6"), timeZone: zone, now: now)
        #expect(ledger.projects[F.bookings]?.color == "#4BACC6")
        try ledger.perform(.rename(.client(F.zenith), to: "Zenith GmbH"), timeZone: zone, now: now)
        #expect(ledger.clients[F.zenith]?.name == "Zenith GmbH")
        try ledger.perform(.merge(.project(F.harbor), into: .project(F.bookings)), timeZone: zone, now: now)
        #expect(ledger.entries[uuid(102)]?.projectID == F.bookings)
        #expect(ledger.projects[F.harbor]?.isDeleted == true)
        #expect(throws: LedgerError.notFound) {
            try ledger.perform(.merge(.project(F.harbor), into: .client(F.zenith)), timeZone: zone, now: now)
        }
    }

    @Test func findsEntriesByNoteTagProjectOrClient() {
        let ledger = F.ledger()
        let resolved = ledger.resolvedEntries()
        #expect(ledger.search("export pdf", in: resolved).map(\.id) == [uuid(101)])
        #expect(ledger.search("northbridge", in: resolved).map(\.id) == [uuid(101), uuid(104)])
        #expect(ledger.search("227", in: resolved).map(\.id) == [uuid(101)])
        #expect(ledger.search("  ", in: resolved).isEmpty)
    }
}

@Suite struct ReportQueryTests {
    typealias F = CommandFixture
    let today = LocalDate(year: 2026, month: 10, day: 5)

    func read(_ text: String) -> ReportQuery {
        ReportQuery.read(text, ledger: F.ledger(), today: today, firstWeekday: 2)
    }

    func days(_ first: String, _ last: String) -> ClosedRange<LocalDate> {
        func date(_ text: String) -> LocalDate {
            let parts = text.split(separator: "-").map { Int($0)! }
            return LocalDate(year: parts[0], month: parts[1], day: parts[2])
        }
        return date(first)...date(last)
    }

    @Test func readsClientsPeriodsAndGrouping() {
        let query = read("northbridge sep by tag")
        #expect(query.clients == [F.northbridge])
        #expect(query.range == days("2026-09-01", "2026-09-30"))
        #expect(query.period == .month)
        #expect(query.grouping == .tag)
        #expect(query.tokens.map(\.kind) == [.client(F.northbridge), .time, .keyword])
    }

    @Test func readsProjectsAndTags() {
        let query = read("book harbor last week")
        #expect(query.projects == [F.bookings, F.harbor])
        #expect(query.range == days("2026-09-28", "2026-10-04"))
        #expect(query.period == .week)
        let tagged = read("#227 this month")
        #expect(tagged.tags == ["#227"])
        #expect(tagged.range == days("2026-10-01", "2026-10-31"))
    }

    @Test func readsPeriods() {
        #expect(read("nov").range == days("2025-11-01", "2025-11-30"))
        #expect(read("sep-oct 2026").range == days("2026-09-01", "2026-10-31"))
        #expect(read("sep-oct 2026").period == .custom)
        #expect(read("dec to feb").range == days("2025-12-01", "2026-02-28"))
        #expect(read("1-15 sep").range == days("2026-09-01", "2026-09-15"))
        #expect(read("q3").range == days("2026-07-01", "2026-09-30"))
        #expect(read("q4 2025").range == days("2025-10-01", "2025-12-31"))
        #expect(read("2025").range == days("2025-01-01", "2025-12-31"))
        #expect(read("2026-09-01 to 2026-09-15").range == days("2026-09-01", "2026-09-15"))
        #expect(read("yesterday").range == days("2026-10-04", "2026-10-04"))
        #expect(read("yesterday").period == .day)
    }

    @Test func marksWordsItDoesntKnow() {
        let query = read("blah in sep")
        #expect(query.tokens.map(\.kind) == [.unknown, .keyword, .time])
        #expect(query.clients.isEmpty && query.projects.isEmpty)
    }
}
