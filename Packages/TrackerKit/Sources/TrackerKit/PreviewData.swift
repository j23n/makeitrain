#if DEBUG
import Foundation
import TrackerCore

/// Sample data for SwiftUI previews: a week of work for a designer with two
/// clients, with a running timer, an overlap, an unassigned entry, one
/// recorded in New York and an archived project. "Now" is Wednesday,
/// September 23, 2026, at 15:40 in Berlin.
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

    public static let ledger: Ledger = {
        let clients = [
            Client(id: acme, name: "Acme", updated: now),
            Client(id: globex, name: "Globex", updated: now),
        ]
        let projects = [
            Project(id: website, clientID: acme, name: "Website redesign", color: "#4F7CAC", updated: now),
            Project(id: mobileApp, clientID: acme, name: "Mobile app", color: "#C0504D", updated: now),
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
            make(mobileApp, "21T13:00", "21T17:00", "Sync engine", ["development"]),

            make(brand, "22T08:45", "22T10:00", "Moodboard", ["design"]),
            make(website, "22T10:00", "22T12:30", "Hero section", ["design"]),
            make(mobileApp, "22T13:30", "22T16:00", "Offline mode", ["development"]),
            make(brand, "22T15:30", "22T16:30", "Call with Globex", ["client-call"]),

            make(website, "23T09:00", "23T10:30", "Kickoff with the new team", ["client-call"]),
            make(internalWork, "23T10:30", "23T12:00", "Invoices"),
            make(nil, "23T12:00", "23T12:20", "Email"),
            make(mobileApp, "23T13:00", "23T14:30", "Code review", ["development"]),
            make(website, "23T14:45", nil, "Landing page copy", ["design"]),
        ]
        return Ledger(clients: clients, projects: projects, entries: entries)
    }()

    /// The sample data with the timer stopped at 15:40.
    public static var stoppedLedger: Ledger {
        var stopped = PreviewData.ledger
        stopped.stopTimer(at: now, now: now)
        return stopped
    }

    /// The id of the sample entry with this note, such as "Call with Globex",
    /// which overlaps "Offline mode", or "Landing page copy", the running
    /// timer.
    public static func entry(_ note: String) -> UUID {
        guard let found = ledger.entries.values.first(where: { $0.note == note }) else {
            preconditionFailure("No sample entry has the note \(note)")
        }
        return found.id
    }

    /// A model showing `ledger`, the sample data unless given another. It
    /// reads no files; edits made in a live preview are saved to a
    /// temporary folder. The other values set up the notices.
    @MainActor
    public static func model(
        _ ledger: Ledger = PreviewData.ledger,
        state: AppModel.State = .ready,
        issues: [FileIssue] = [],
        missingFiles: Int = 0,
        lastError: String? = nil
    ) -> AppModel {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("TimeTrackerPreview-\(UUID().uuidString)")
        let model = AppModel(environment: AppEnvironment(
            localFolder: folder.appendingPathComponent("Data"),
            backupsFolder: folder.appendingPathComponent("Backups"),
            defaults: UserDefaults(suiteName: "TimeTrackerPreview") ?? .standard,
            now: { now },
            timeZone: { "Europe/Berlin" }
        ))
        model.firstWeekday = 2
        model.showForPreview(ledger, state: state, issues: issues, missingFiles: missingFiles, lastError: lastError)
        return model
    }

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
#endif
