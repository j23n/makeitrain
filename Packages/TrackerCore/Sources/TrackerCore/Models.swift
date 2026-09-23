import Foundation

/// Someone you work for. Projects can belong to a client.
public struct Client: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var archived: Bool
    /// When the client last changed.
    public var updated: Timestamp
    /// Set when the client is deleted. The record stays, so an older copy
    /// can't bring it back.
    public var deleted: Timestamp?

    public init(id: UUID = UUID(), name: String, archived: Bool = false, updated: Timestamp, deleted: Timestamp? = nil) {
        self.id = id
        self.name = name
        self.archived = archived
        self.updated = updated
        self.deleted = deleted
    }

    public var isDeleted: Bool {
        deleted != nil
    }
}

public struct Project: Identifiable, Hashable, Sendable {
    public let id: UUID
    /// nil means "No client".
    public var clientID: UUID?
    public var name: String
    /// A hex color, such as "#4F7CAC".
    public var color: String
    public var archived: Bool
    /// When the project last changed.
    public var updated: Timestamp
    /// Set when the project is deleted. The record keeps its name, color and
    /// client, because entries on another device may still point at it.
    public var deleted: Timestamp?

    public init(
        id: UUID = UUID(),
        clientID: UUID? = nil,
        name: String,
        color: String = "#4F7CAC",
        archived: Bool = false,
        updated: Timestamp,
        deleted: Timestamp? = nil
    ) {
        self.id = id
        self.clientID = clientID
        self.name = name
        self.color = color
        self.archived = archived
        self.updated = updated
        self.deleted = deleted
    }

    public var isDeleted: Bool {
        deleted != nil
    }
}

/// A stretch of logged work, or the running timer.
public struct TimeEntry: Identifiable, Hashable, Sendable {
    public let id: UUID
    /// nil means "Unassigned", as after a quick start.
    public var projectID: UUID?
    /// Whole seconds.
    public var start: Timestamp
    /// Whole seconds, or nil while the timer runs.
    public var end: Timestamp?
    /// When `end` was last set. `end` merges on this stamp, separately from
    /// the other fields, so a stop survives an edit made to an out-of-date
    /// copy on another device.
    public var endUpdated: Timestamp?
    /// The zone the entry was recorded in, such as "Europe/Berlin". The entry
    /// is shown, edited and filed in this zone.
    public var timeZone: String
    public var tags: [String]
    public var note: String
    /// When anything except `end` last changed.
    public var updated: Timestamp
    /// Set when the entry is deleted. The record stays, without its note and
    /// tags, so an older copy can't bring it back.
    public var deleted: Timestamp?

    /// `end` and `endUpdated` come as a pair: without an `endUpdated`, an
    /// `end` is stamped with `updated`.
    public init(
        id: UUID = UUID(),
        projectID: UUID? = nil,
        start: Timestamp,
        end: Timestamp? = nil,
        endUpdated: Timestamp? = nil,
        timeZone: String,
        tags: [String] = [],
        note: String = "",
        updated: Timestamp,
        deleted: Timestamp? = nil
    ) {
        self.id = id
        self.projectID = projectID
        self.start = start
        self.end = end
        self.endUpdated = end == nil ? nil : endUpdated ?? updated
        self.timeZone = timeZone
        self.tags = tags
        self.note = note
        self.updated = updated
        self.deleted = deleted
    }

    public var isDeleted: Bool {
        deleted != nil
    }

    /// The day the entry belongs to: the date of its start in its own time zone.
    public var day: LocalDate {
        start.local(in: timeZone).date
    }

    /// The month file the entry belongs in: the month of its start in its own
    /// time zone, so every device files it the same way.
    public var month: MonthKey {
        day.monthKey
    }
}
