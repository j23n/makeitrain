import Foundation
@testable import TrackerCore

/// Clients, projects and entries for command line, correction and report
/// tests, in Berlin, with today Monday 5 October 2026.
///
/// - Northbridge (1) › Bookings (11), with two GitHub repositories
/// - Zenith (2) › Harbor (12)
/// - Internal (13, `inHouse`), without a client, and Admin (14), archived
///
/// Entries: Harbor "Check-in" on Wednesday 30 September 07:30–08:50 (102);
/// Bookings "Standup" #Daily on Friday 2 October 08:45–09:00 (104) and
/// "Export to PDF" #227 09:00–12:00 (101); Internal "Planning" today
/// 08:00–09:00 (105).
struct CommandFixture {
    static let zone = "Europe/Berlin"
    static let northbridge = uuid(1)
    static let zenith = uuid(2)
    static let bookings = uuid(11)
    static let harbor = uuid(12)
    static let inHouse = uuid(13)
    static let admin = uuid(14)

    /// A time today, such as "10:40", or on another day.
    static func at(_ time: String, on day: String = "2026-10-05") -> Timestamp {
        t("\(day)T\(time):00+02:00")
    }

    static func entry(
        _ number: Int,
        _ projectID: UUID?,
        _ day: String,
        _ start: String,
        _ end: String?,
        tags: [String] = [],
        note: String = "",
        endDay: String? = nil
    ) -> TimeEntry {
        TimeEntry(
            id: uuid(number),
            projectID: projectID,
            start: at(start, on: day),
            end: end.map { at($0, on: endDay ?? day) },
            timeZone: zone,
            tags: tags,
            note: note,
            updated: t("2026-06-01T09:00:00+02:00")
        )
    }

    static var records: (clients: [Client], projects: [Project]) {
        let stamp = t("2026-06-01T09:00:00+02:00")
        return (
            [
                Client(id: northbridge, name: "Northbridge", updated: stamp),
                Client(id: zenith, name: "Zenith", updated: stamp),
            ],
            [
                Project(
                    id: bookings,
                    clientID: northbridge,
                    name: "Bookings",
                    color: "#4F7CAC",
                    repositories: ["https://github.com/northbridge/Scheduler", "https://github.com/northbridge/Libs"],
                    updated: stamp
                ),
                Project(id: harbor, clientID: zenith, name: "Harbor", color: "#9BBB59", updated: stamp),
                Project(id: inHouse, name: "Internal", color: "#7F7F7F", updated: stamp),
                Project(id: admin, name: "Admin", color: "#C0504D", archived: true, updated: stamp),
            ]
        )
    }

    static var baseEntries: [TimeEntry] {
        [
            Self.entry(102, harbor, "2026-09-30", "07:30", "08:50", note: "Check-in"),
            Self.entry(104, bookings, "2026-10-02", "08:45", "09:00", tags: ["Daily"], note: "Standup"),
            Self.entry(101, bookings, "2026-10-02", "09:00", "12:00", tags: ["#227"], note: "Export to PDF"),
            Self.entry(105, inHouse, "2026-10-05", "08:00", "09:00", note: "Planning"),
        ]
    }

    /// The fixture, with `extra` entries.
    static func ledger(_ extra: [TimeEntry] = []) -> Ledger {
        Ledger(clients: records.clients, projects: records.projects, entries: baseEntries + extra)
    }

    /// Bookings "Export to PDF" #227 running since 09:30 today (103).
    static var runningBookings: TimeEntry {
        Self.entry(103, bookings, "2026-10-05", "09:30", nil, tags: ["#227"], note: "Export to PDF")
    }

    /// Bookings "Export to PDF" #227 09:30–10:40 today (103), then Harbor
    /// "release call" running since 10:40 (106).
    static var switchedToHarbor: [TimeEntry] {
        [
            Self.entry(103, bookings, "2026-10-05", "09:30", "10:40", tags: ["#227"], note: "Export to PDF"),
            Self.entry(106, harbor, "2026-10-05", "10:40", nil, note: "release call"),
        ]
    }

    static func context(_ ledger: Ledger, now: String = "10:40", on day: String = "2026-10-05") -> CommandContext {
        CommandContext(ledger: ledger, resolved: ledger.resolvedEntries(), projectTags: ledger.tagsByProject(), now: at(now, on: day), timeZone: zone)
    }

    static func read(_ text: String, _ ledger: Ledger = ledger(), now: String = "10:40", on day: String = "2026-10-05") -> CommandReading {
        CommandReading(text, in: context(ledger, now: now, on: day))
    }
}
