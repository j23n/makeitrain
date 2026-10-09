#if DEBUG
import Foundation
import TrackerCore

/// Sample data for SwiftUI previews: a week of work for a designer with two
/// clients, with a running timer, an overlap, an unassigned entry, one
/// recorded in New York, an archived project, and tags that refer to issues
/// in Acme's GitHub repositories, some written "Core/#31". There's also
/// a freelancer's three months, with hundreds of hours and dozens of issue
/// tags. "Now" is Wednesday, September 23, 2026, at 15:40 in Berlin.
public enum PreviewData {
    public static let now = time("23T15:40")

    // Fixed ids, so previews can select things.
    public static let acme = id(1)
    public static let globex = id(2)
    public static let website = id(11)
    public static let mobileApp = id(12)
    public static let brand = id(13)
    public static let internalWork = id(14)
    public static let admin = id(15)

    // The freelancer's clients and projects.
    public static let initech = id(3)
    public static let contoso = id(4)
    public static let newsletter = id(16)
    public static let billing = id(17)

    public static let ledger: Ledger = {
        let clients = [
            Client(id: acme, name: "Acme", updated: now),
            Client(id: globex, name: "Globex", updated: now),
        ]
        let projects = [
            Project(
                id: website,
                clientID: acme,
                name: "Website redesign",
                color: "#4F7CAC",
                repositories: ["https://github.com/acme/website"],
                updated: now
            ),
            Project(
                id: mobileApp,
                clientID: acme,
                name: "Mobile app",
                color: "#C0504D",
                repositories: ["https://github.com/acme/mobile", "https://github.com/acme/api", "https://github.com/acme/Core"],
                updated: now
            ),
            Project(id: brand, clientID: globex, name: "Brand refresh", color: "#9BBB59", updated: now),
            Project(id: internalWork, name: "Internal", color: "#8064A2", updated: now),
            Project(id: admin, name: "Admin", color: "#7F7F7F", archived: true, updated: now),
        ]
        var number = 100
        func make(
            _ project: UUID?,
            _ start: String,
            _ end: String?,
            _ note: String,
            _ tags: [String] = [],
            zone: String = "Europe/Berlin",
            offset: String = "+02:00"
        ) -> TimeEntry {
            number += 1
            let endTime = end.map { time($0, offset: offset) }
            return TimeEntry(
                id: id(number),
                projectID: project,
                start: time(start, offset: offset),
                end: endTime,
                timeZone: zone,
                tags: tags,
                note: note,
                updated: endTime ?? now
            )
        }
        let entries = [
            make(brand, "18T10:00", "18T12:00", "Client visit", ["client-call"], zone: "America/New_York", offset: "-04:00"),
            make(admin, "18T14:00", "18T15:00", "Expenses"),

            make(website, "21T09:00", "21T11:30", "Wireframe review, round 2", ["design", "client-call"]),
            make(internalWork, "21T11:30", "21T12:15", "Planning"),
            make(mobileApp, "21T13:00", "21T17:00", "Sync engine", ["development", "#118", "Core/#64"]),

            make(brand, "22T08:45", "22T10:00", "Moodboard", ["design"]),
            make(website, "22T10:00", "22T12:30", "Hero section", ["design", "#42"]),
            make(mobileApp, "22T13:30", "22T16:00", "Offline mode", ["development", "api#57"]),
            make(brand, "22T15:30", "22T16:30", "Call with Globex", ["client-call"]),

            make(website, "23T09:00", "23T10:30", "Kickoff with the new team", ["client-call"]),
            make(internalWork, "23T10:30", "23T12:00", "Invoices"),
            make(nil, "23T12:00", "23T12:20", "Email"),
            make(mobileApp, "23T13:00", "23T14:30", "Code review", ["development", "Core/#31"]),
            make(website, "23T14:45", nil, "Landing page copy", ["design", "#44"]),
        ]
        return Ledger(clients: clients, projects: projects, entries: entries)
    }()

    /// A freelancer's three months: Initech › Newsletter with fourteen
    /// early check-ins, 18 h 40 m, and Contoso › Billing full-time,
    /// 574 h 46 m before today's running timer, with a week off in August.
    /// Billing's tags are mostly issues in its two repositories, written
    /// like "Core/#131", with "daily" on Mondays and a few
    /// "data-exploration".
    public static let freelancerLedger: Ledger = {
        let zone = "Europe/Berlin"
        let clients = [
            Client(id: initech, name: "Initech", updated: now),
            Client(id: contoso, name: "Contoso", updated: now),
        ]
        let projects = [
            Project(id: newsletter, clientID: initech, name: "Newsletter", color: "#9BBB59", updated: now),
            Project(
                id: billing,
                clientID: contoso,
                name: "Billing",
                color: "#4F7CAC",
                repositories: ["https://github.com/contoso/Core", "https://github.com/contoso/Tools"],
                updated: now
            ),
        ]
        // The issues worked on, in turn; the busiest come up more often.
        let coreIssues = [
            131, 98, 153, 131, 151, 33, 65, 189, 131, 55, 98, 153, 104, 66, 131, 43, 68, 97, 151, 181,
            31, 64, 154, 133, 141, 189, 204, 220, 227, 114, 117, 123, 125, 127, 148, 59,
        ]
        let issues = coreIssues.map { "Core/#\($0)" } + [225, 212, 230, 233].map { "Tools/#\($0)" }
        let notes = ["Review", "Refactoring", "Bug fix", "Pairing", "Tests", "Spec"]

        var entries: [TimeEntry] = []
        func add(_ project: UUID, _ day: LocalDate, at minute: Int, for minutes: Int?, tags: [String], note: String) {
            let start = Timestamp(date: day, secondOfDay: minute * 60, zone: zone)
            let end = minutes.map { start.adding(seconds: Int64($0) * 60) }
            entries.append(TimeEntry(
                id: id(1000 + entries.count),
                projectID: project,
                start: start,
                end: end,
                timeZone: zone,
                tags: tags,
                note: note,
                updated: end ?? now
            ))
        }

        // Weekdays from June 15 to yesterday, but for the week off.
        let today = now.local(in: zone).date
        let weekOff = LocalDate(year: 2026, month: 8, day: 10)...LocalDate(year: 2026, month: 8, day: 14)
        var days: [LocalDate] = []
        var day = LocalDate(year: 2026, month: 6, day: 15)
        while day < today {
            if (2...6).contains(day.weekday), !weekOff.contains(day) {
                days.append(day)
            }
            day = day.adding(days: 1)
        }

        // Billing: 574 h 46 m over those days and this morning, more on
        // some days than on others.
        let thisMorning = 3 * 60 + 30
        let target = 574 * 60 + 46 - thisMorning
        let offsets = [40, -20, 10, -30, 0]
        var minutes = days.indices.map { index in
            target / days.count + (index < target % days.count ? 1 : 0) + offsets[index % offsets.count]
        }
        minutes[minutes.count - 1] += target - minutes.reduce(0, +)
        for (index, day) in days.enumerated() {
            let morning = 180 + index % 5 * 12
            let start = day.weekday == 2 ? 9 * 60 + 30 : 9 * 60
            if day.weekday == 2 {
                add(billing, day, at: 9 * 60, for: 30, tags: ["daily"], note: "Planning")
            }
            add(billing, day, at: start, for: morning - (start - 9 * 60), tags: [issues[index % issues.count]], note: notes[index % notes.count])
            let afternoon = index % 23 == 4 ? ["data-exploration"] : [issues[(index + 7) % issues.count]]
            add(billing, day, at: 13 * 60 + 30, for: minutes[index] - morning, tags: afternoon, note: notes[(index + 2) % notes.count])
        }
        add(billing, today, at: 9 * 60, for: thisMorning, tags: ["Core/#131"], note: "Review")
        add(billing, today, at: 14 * 60 + 20, for: nil, tags: ["Core/#227"], note: "Export to PDF")

        // Newsletter: an hour and twenty minutes before Billing, on every fifth
        // day.
        for (index, day) in days.enumerated() where index % 5 == 0 && index / 5 < 14 {
            add(newsletter, day, at: 7 * 60 + 30, for: 80, tags: index == 0 ? ["meeting"] : [], note: "Check-in")
        }
        return Ledger(clients: clients, projects: projects, entries: entries)
    }()

    /// The sample data with the timer stopped at 15:40.
    public static var stoppedLedger: Ledger {
        var stopped = PreviewData.ledger
        stopped.stopTimer(at: now, now: now)
        return stopped
    }

    /// A model showing `ledger`, the sample data unless given another. It
    /// reads no files; edits made in a live preview are saved to a
    /// temporary folder. The other values set up the notices, and the
    /// sample calendars' links to projects.
    @MainActor
    public static func model(
        _ ledger: Ledger = PreviewData.ledger,
        state: AppModel.State = .ready,
        issues: [FileIssue] = [],
        missingFiles: Int = 0,
        lastError: String? = nil,
        calendarLinks: [CalendarLink] = PreviewData.calendarLinks
    ) -> AppModel {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("TimeTrackerPreview-\(UUID().uuidString)")
        let model = AppModel(environment: AppEnvironment(
            localFolder: folder.appendingPathComponent("Data"),
            backupsFolder: folder.appendingPathComponent("Backups"),
            defaults: UserDefaults(suiteName: "TimeTrackerPreview") ?? .standard,
            now: { now },
            timeZone: { "Europe/Berlin" },
            calendars: PreviewCalendars()
        ))
        model.firstWeekday = 2
        model.showForPreview(ledger, state: state, issues: issues, missingFiles: missingFiles, lastError: lastError)
        model.calendarLinks = calendarLinks
        model.refreshCalendars()
        return model
    }

    // MARK: Calendars

    /// Acme's Exchange calendar and a Google calendar for Globex, plus two
    /// personal ones in iCloud.
    public static let calendars = [
        CalendarInfo(id: "acme", title: "Calendar", account: "jo@acme.example"),
        CalendarInfo(id: "globex", title: "Globex", account: "Google"),
        CalendarInfo(id: "home", title: "Home", account: "iCloud"),
        CalendarInfo(id: "family", title: "Family", account: "iCloud"),
    ]

    /// Acme's calendar goes to Website redesign and Globex's to Brand refresh.
    public static let calendarLinks = [
        CalendarLink(calendarID: "acme", title: "Calendar", account: "jo@acme.example", projectID: website),
        CalendarLink(calendarID: "globex", title: "Globex", account: "Google", projectID: brand),
    ]

    /// The week's events: some already logged, some left out, and a few to
    /// import.
    public static let events: [CalendarImport.Event] = {
        var number = 200
        func make(
            _ calendar: String,
            _ title: String,
            _ start: String,
            _ end: String,
            isAllDay: Bool = false,
            isDeclined: Bool = false
        ) -> CalendarImport.Event {
            number += 1
            return CalendarImport.Event(
                entryID: id(number),
                calendarID: calendar,
                title: title,
                start: time(start),
                end: time(end),
                isAllDay: isAllDay,
                isDeclined: isDeclined
            )
        }
        return [
            make("acme", "Standup", "21T09:30", "21T09:45"),
            make("acme", "Wireframe review, round 2", "21T09:00", "21T11:30"),
            make("globex", "Brand workshop", "21T14:00", "21T16:00"),
            make("acme", "Standup", "22T09:30", "22T09:45"),
            make("acme", "Sprint planning", "22T14:00", "22T15:00"),
            make("globex", "Lunch & learn", "22T12:00", "22T13:00", isDeclined: true),
            make("acme", "Standup", "23T09:30", "23T09:45"),
            make("acme", "Offsite", "22T00:00", "23T00:00", isAllDay: true),
            make("acme", "Retro", "23T16:00", "23T17:00"),
            make("home", "Dentist", "22T08:00", "22T08:45"),
        ]
    }()

    /// A time in September 2026, such as "23T15:40".
    private static func time(_ text: String, offset: String = "+02:00") -> Timestamp {
        guard let parsed = DateTimeFormat.parse("2026-09-\(text):00\(offset)") else {
            preconditionFailure("Not a sample time: \(text)")
        }
        return parsed
    }

    private static func id(_ number: Int) -> UUID {
        UUID(uuidString: "00000000-0000-0000-0000-\(String(format: "%012d", number))")!
    }
}

/// Calendars for previews: `PreviewData.calendars` with their events,
/// which the app may read.
@MainActor
public final class PreviewCalendars: CalendarProvider {
    public let access = CalendarAccess.granted
    public var onChange: (() -> Void)?

    public init() {}

    public func requestAccess() async -> CalendarAccess {
        access
    }

    public func calendars() -> [CalendarInfo] {
        PreviewData.calendars
    }

    public func events(inCalendars ids: Set<String>, from start: Timestamp, to end: Timestamp) -> [CalendarImport.Event] {
        PreviewData.events.filter { ids.contains($0.calendarID) && $0.start < end && $0.end > start }
    }
}
#endif
