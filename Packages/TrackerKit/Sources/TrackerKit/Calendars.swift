import CryptoKit
import EventKit
import Foundation
import TrackerCore

// Importing events from the calendars on this device. EventKit shows every
// account the Mac or iPhone has, such as iCloud, Google or Exchange, and
// calendar subscriptions, so each client's calendar can be linked to one of
// their projects, whatever the client uses.

/// Whether the app may read the calendars on this device.
public enum CalendarAccess: Sendable, Equatable {
    /// The app hasn't asked yet.
    case notDetermined
    case granted
    /// Turned off in Privacy & Security, or only allowed to add events.
    case denied
    /// Not allowed on this device, as by Screen Time or a device profile.
    case restricted
}

/// A calendar on this device.
public struct CalendarInfo: Identifiable, Hashable, Sendable {
    /// How this device identifies the calendar. Other devices use other ids.
    public var id: String
    public var title: String
    /// The account it's in, such as "iCloud" or "Exchange".
    public var account: String

    public init(id: String, title: String, account: String) {
        self.id = id
        self.title = title
        self.account = account
    }
}

/// The calendars on this device, as the app model uses them.
/// `EventKitCalendars` is the real one; previews and tests use stand-ins.
@MainActor
public protocol CalendarProvider: AnyObject {
    var access: CalendarAccess { get }
    /// Called when calendars or their events change, as after a sync.
    var onChange: (() -> Void)? { get set }
    /// Asks for access the first time; later calls return what was decided.
    func requestAccess() async -> CalendarAccess
    /// The calendars that can hold events.
    func calendars() -> [CalendarInfo]
    /// The events in some calendars that overlap a stretch of time.
    func events(inCalendars ids: Set<String>, from start: Timestamp, to end: Timestamp) -> [CalendarImport.Event]
}

/// A calendar whose events become entries for a project. Links are kept on
/// each device, because each device identifies calendars differently and
/// may have other accounts.
public struct CalendarLink: Codable, Hashable, Sendable {
    public var calendarID: String
    /// The calendar's title and account, to find it again when its id
    /// changes, as after its account is removed and added back.
    public var title: String
    public var account: String
    public var projectID: UUID

    public init(calendarID: String, title: String, account: String, projectID: UUID) {
        self.calendarID = calendarID
        self.title = title
        self.account = account
        self.projectID = projectID
    }

    static let defaultsKey = "calendarLinks"

    static func load(from defaults: UserDefaults) -> [CalendarLink] {
        guard let data = defaults.data(forKey: defaultsKey) else { return [] }
        return (try? JSONDecoder().decode([CalendarLink].self, from: data)) ?? []
    }

    static func save(_ links: [CalendarLink], to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(links) else { return }
        defaults.set(data, forKey: defaultsKey)
    }

    /// `links` following calendars that are there under a new id, found by
    /// title and account when that's unambiguous, and with the current
    /// titles of the others. Links to calendars that aren't there stay, in
    /// case their account comes back.
    static func relinked(_ links: [CalendarLink], to calendars: [CalendarInfo]) -> [CalendarLink] {
        let present = Set(calendars.map(\.id))
        var taken = Set(links.map(\.calendarID)).intersection(present)
        return links.map { link in
            var updated = link
            if let calendar = calendars.first(where: { $0.id == link.calendarID }) {
                updated.title = calendar.title
                updated.account = calendar.account
            } else {
                let matches = calendars.filter { calendar in
                    calendar.title == link.title && calendar.account == link.account && !taken.contains(calendar.id)
                }
                if matches.count == 1 {
                    updated.calendarID = matches[0].id
                    taken.insert(matches[0].id)
                }
            }
            return updated
        }
    }
}

/// The ids of entries made from calendar events.
public enum CalendarEntryID {
    /// The namespace of those ids. Changing it would import every event again.
    static let namespace = UUID(uuidString: "7F1247D3-9F80-44AE-BC83-1157BB35223C")!

    /// The id of the entry made from an event: a name-based UUID of the
    /// event's id on its calendar server and, for an occurrence of a
    /// repeating event, when that occurrence was first scheduled. Every
    /// device that sees the event therefore gives its entry the same id,
    /// except for Exchange calendars, whose event ids differ between the Mac
    /// and iOS.
    public static func forEvent(externalID: String, occurrence: Date?) -> UUID {
        var name = externalID
        if let occurrence {
            name += "\n" + String(Timestamp(occurrence).wholeSeconds.milliseconds)
        }
        return UUID(version5: namespace, name: name)
    }
}

extension UUID {
    /// A name-based UUID, version 5 in RFC 9562: the same namespace and name
    /// always give the same UUID.
    init(version5 namespace: UUID, name: String) {
        var raw = namespace.uuid
        var data = withUnsafeBytes(of: &raw) { Data($0) }
        data.append(contentsOf: Array(name.utf8))
        var bytes = Array(Insecure.SHA1.hash(data: data))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        self.init(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

/// The calendars in the Calendar app, through EventKit.
@MainActor
public final class EventKitCalendars: CalendarProvider {
    public var onChange: (() -> Void)?
    private let store = EKEventStore()
    private var observer: NSObjectProtocol?

    public init() {
        observer = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: store,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.onChange?()
            }
        }
    }

    public var access: CalendarAccess {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: .granted
        case .notDetermined: .notDetermined
        case .restricted: .restricted
        case .denied, .writeOnly: .denied
        @unknown default: .denied
        }
    }

    public func requestAccess() async -> CalendarAccess {
        _ = try? await store.requestFullAccessToEvents()
        return access
    }

    public func calendars() -> [CalendarInfo] {
        guard access == .granted else { return [] }
        return store.calendars(for: .event)
            .filter { $0.type != .birthday }
            .map { calendar in
                let source: EKSource? = calendar.source
                return CalendarInfo(
                    id: calendar.calendarIdentifier,
                    title: calendar.title,
                    account: source?.title ?? ""
                )
            }
    }

    public func events(inCalendars ids: Set<String>, from start: Timestamp, to end: Timestamp) -> [CalendarImport.Event] {
        guard access == .granted else { return [] }
        let calendars = store.calendars(for: .event).filter { ids.contains($0.calendarIdentifier) }
        guard !calendars.isEmpty else { return [] }
        let predicate = store.predicateForEvents(withStart: start.date, end: end.date, calendars: calendars)
        return store.events(matching: predicate).map(Self.importEvent)
    }

    /// An event as the import sees it.
    static func importEvent(_ event: EKEvent) -> CalendarImport.Event {
        let externalID: String? = event.calendarItemExternalIdentifier
        let repeats = event.hasRecurrenceRules || event.isDetached
        let occurrence: Date? = repeats ? event.occurrenceDate : nil
        let calendar: EKCalendar? = event.calendar
        let attendance = (event.attendees ?? []).first { $0.isCurrentUser }?.participantStatus
        return CalendarImport.Event(
            entryID: CalendarEntryID.forEvent(externalID: externalID ?? event.calendarItemIdentifier, occurrence: occurrence),
            calendarID: calendar?.calendarIdentifier ?? "",
            title: event.title ?? "",
            start: Timestamp(event.startDate),
            end: Timestamp(event.endDate),
            isAllDay: event.isAllDay,
            isCancelled: event.status == .canceled,
            isDeclined: attendance == .declined,
            isFree: event.availability == .free || event.availability == .unavailable
        )
    }
}
