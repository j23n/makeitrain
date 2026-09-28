import Foundation

/// Why a data file can't be used. The app never overwrites such a file.
public enum FileProblem: Error, Hashable, Sendable {
    /// The file isn't JSON, or not in the expected shape.
    case unreadable(String)
    /// The file was written by a newer version of the app.
    case newerVersion(Int)
    /// iCloud hasn't downloaded the file to this device yet.
    case notDownloaded
}

extension FileProblem {
    /// `error` as a file problem: itself if it is one, otherwise the file
    /// counts as unreadable, with the error's description.
    init(_ error: any Error) {
        self = error as? FileProblem ?? .unreadable(String(describing: error))
    }
}

/// Reading and writing the data files: `projects.json` and one file per month.
///
/// Each kind of file has a version: the one this app writes and the newest
/// it reads. Decoding ignores fields it doesn't know, so adding a field needs
/// a new version. Otherwise an older copy of the app would silently drop the
/// field when it saves.
public enum FileFormat {
    /// The version of month files.
    public static let entriesVersion = 1
    /// The version of `projects.json`. Version 2 added projects'
    /// `repositories`.
    public static let projectsVersion = 2

    public static func encode(entries: [TimeEntry]) -> Data {
        JSONWriter.data(.object([
            "entries": .array(entries.sorted(by: TimeEntry.fileOrder).map(\.json)),
            "version": .number(entriesVersion),
        ]))
    }

    public static func encode(clients: [Client], projects: [Project]) -> Data {
        JSONWriter.data(.object([
            "clients": .array(clients.sorted(by: Client.fileOrder).map(\.json)),
            "projects": .array(projects.sorted(by: Project.fileOrder).map(\.json)),
            "version": .number(projectsVersion),
        ]))
    }

    /// Decodes a month file. Throws `FileProblem`.
    public static func decodeEntries(from data: Data) throws -> [TimeEntry] {
        try decode(MonthContents.self, from: data, newest: entriesVersion).entries ?? []
    }

    /// Decodes `projects.json`. Throws `FileProblem`.
    public static func decodeProjects(from data: Data) throws -> (clients: [Client], projects: [Project]) {
        let contents = try decode(ProjectsContents.self, from: data, newest: projectsVersion)
        return (contents.clients ?? [], contents.projects ?? [])
    }

    private static func decode<Contents: Decodable>(_ type: Contents.Type, from data: Data, newest: Int) throws -> Contents {
        let decoder = JSONDecoder()
        let header: VersionHeader
        do {
            header = try decoder.decode(VersionHeader.self, from: data)
        } catch {
            throw FileProblem.unreadable(describe(error))
        }
        guard header.version <= newest else {
            throw FileProblem.newerVersion(header.version)
        }
        guard header.version >= 1 else {
            throw FileProblem.unreadable("Unknown version \(header.version)")
        }
        do {
            return try decoder.decode(Contents.self, from: data)
        } catch {
            throw FileProblem.unreadable(describe(error))
        }
    }

    /// A short explanation of a decoding error, with where it happened.
    static func describe(_ error: any Error) -> String {
        guard let error = error as? DecodingError else {
            return String(describing: error)
        }
        let context: DecodingError.Context
        switch error {
        case .dataCorrupted(let found), .typeMismatch(_, let found), .valueNotFound(_, let found):
            context = found
        case .keyNotFound(let key, let found):
            return "Missing \"\(key.stringValue)\"" + location(found.codingPath)
        @unknown default:
            return String(describing: error)
        }
        return context.debugDescription + location(context.codingPath)
    }

    private static func location(_ path: [any CodingKey]) -> String {
        guard !path.isEmpty else { return "" }
        return " at " + path.map { key in key.intValue.map { "[\($0)]" } ?? key.stringValue }.joined(separator: ".")
    }
}

private struct VersionHeader: Decodable {
    var version: Int
}

private struct MonthContents: Decodable {
    var entries: [TimeEntry]?
}

private struct ProjectsContents: Decodable {
    var clients: [Client]?
    var projects: [Project]?
}

// MARK: - Records

extension TimeEntry: Decodable {
    private enum Key: String, CodingKey {
        case id, project, start, end, endUpdated, timeZone, tags, note, updated, deleted
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            projectID: try container.decodeIfPresent(UUID.self, forKey: .project),
            start: try container.time(.start),
            end: try container.timeIfPresent(.end),
            endUpdated: try container.timeIfPresent(.endUpdated),
            timeZone: try container.decode(String.self, forKey: .timeZone),
            tags: try container.decodeIfPresent([String].self, forKey: .tags) ?? [],
            note: try container.decodeIfPresent(String.self, forKey: .note) ?? "",
            updated: try container.time(.updated),
            deleted: try container.timeIfPresent(.deleted)
        )
    }

    var json: JSON {
        func time(_ time: Timestamp) -> JSON {
            .string(DateTimeFormat.format(time, zone: timeZone))
        }
        var members: [String: JSON] = [
            "id": .string(id.uuidString),
            "note": .string(note),
            "start": time(start),
            "tags": .array(tags.map(JSON.string)),
            "timeZone": .string(timeZone),
            "updated": time(updated),
        ]
        if let projectID {
            members["project"] = .string(projectID.uuidString)
        }
        if let end {
            members["end"] = time(end)
        }
        if let stamp = endUpdated ?? (end == nil ? nil : updated) {
            members["endUpdated"] = time(stamp)
        }
        if let deleted {
            members["deleted"] = time(deleted)
        }
        return .object(members)
    }

    /// The order entries are written in: by start, then id.
    static func fileOrder(_ a: TimeEntry, _ b: TimeEntry) -> Bool {
        a.start != b.start ? a.start < b.start : a.id.uuidString < b.id.uuidString
    }
}

extension Client: Decodable {
    private enum Key: String, CodingKey {
        case id, name, archived, updated, deleted
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            name: try container.decode(String.self, forKey: .name),
            archived: try container.decodeIfPresent(Bool.self, forKey: .archived) ?? false,
            updated: try container.time(.updated),
            deleted: try container.timeIfPresent(.deleted)
        )
    }

    var json: JSON {
        var members: [String: JSON] = [
            "archived": .bool(archived),
            "id": .string(id.uuidString),
            "name": .string(name),
            "updated": .string(DateTimeFormat.formatUTC(updated)),
        ]
        if let deleted {
            members["deleted"] = .string(DateTimeFormat.formatUTC(deleted))
        }
        return .object(members)
    }

    /// The order clients are written in: by name, then id.
    static func fileOrder(_ a: Client, _ b: Client) -> Bool {
        let (nameA, nameB) = (a.name.lowercased(), b.name.lowercased())
        return nameA != nameB ? nameA < nameB : a.id.uuidString < b.id.uuidString
    }
}

extension Project: Decodable {
    private enum Key: String, CodingKey {
        case id, client, name, color, archived, repositories, updated, deleted
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            clientID: try container.decodeIfPresent(UUID.self, forKey: .client),
            name: try container.decode(String.self, forKey: .name),
            color: try container.decodeIfPresent(String.self, forKey: .color) ?? "#4F7CAC",
            archived: try container.decodeIfPresent(Bool.self, forKey: .archived) ?? false,
            repositories: try container.decodeIfPresent([String].self, forKey: .repositories) ?? [],
            updated: try container.time(.updated),
            deleted: try container.timeIfPresent(.deleted)
        )
    }

    var json: JSON {
        var members: [String: JSON] = [
            "archived": .bool(archived),
            "color": .string(color),
            "id": .string(id.uuidString),
            "name": .string(name),
            "updated": .string(DateTimeFormat.formatUTC(updated)),
        ]
        if let clientID {
            members["client"] = .string(clientID.uuidString)
        }
        if !repositories.isEmpty {
            members["repositories"] = .array(repositories.map { .string($0) })
        }
        if let deleted {
            members["deleted"] = .string(DateTimeFormat.formatUTC(deleted))
        }
        return .object(members)
    }

    /// The order projects are written in: by name, then id.
    static func fileOrder(_ a: Project, _ b: Project) -> Bool {
        let (nameA, nameB) = (a.name.lowercased(), b.name.lowercased())
        return nameA != nameB ? nameA < nameB : a.id.uuidString < b.id.uuidString
    }
}

extension KeyedDecodingContainer {
    fileprivate func time(_ key: Key) throws -> Timestamp {
        let text = try decode(String.self, forKey: key)
        guard let time = DateTimeFormat.parse(text) else {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: self,
                debugDescription: "\"\(text)\" isn't an ISO 8601 date-time with an offset"
            )
        }
        return time
    }

    fileprivate func timeIfPresent(_ key: Key) throws -> Timestamp? {
        guard contains(key), try !decodeNil(forKey: key) else { return nil }
        return try time(key)
    }
}
