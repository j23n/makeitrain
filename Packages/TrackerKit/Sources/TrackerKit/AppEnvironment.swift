import Foundation
import TrackerCore

/// What the app model needs from the outside world, so tests can swap it.
public struct AppEnvironment {
    /// The local data folder.
    public var localFolder: URL
    /// Where daily backups go.
    public var backupsFolder: URL
    /// Settings storage.
    public var defaults: UserDefaults
    /// The current time.
    public var now: () -> Timestamp
    /// The time zone new entries are recorded in, such as "Europe/Berlin".
    public var timeZone: () -> String
    /// iCloud, or nil where it isn't available, as in tests.
    public var cloud: CloudProvider?

    public init(
        localFolder: URL,
        backupsFolder: URL,
        defaults: UserDefaults,
        now: @escaping () -> Timestamp = { .now },
        timeZone: @escaping () -> String = { TimeZone.current.identifier },
        cloud: CloudProvider? = nil
    ) {
        self.localFolder = localFolder
        self.backupsFolder = backupsFolder
        self.defaults = defaults
        self.now = now
        self.timeZone = timeZone
        self.cloud = cloud
    }

    /// The real thing: folders in the app's Application Support folder, which
    /// is inside its sandbox, the standard settings, and iCloud.
    @MainActor
    public static func live(containerIdentifier: String = "iCloud.com.j23n.TimeTracker") -> AppEnvironment {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return AppEnvironment(
            localFolder: support.appendingPathComponent("Data", isDirectory: true),
            backupsFolder: support.appendingPathComponent("Backups", isDirectory: true),
            defaults: .standard,
            cloud: ICloudProvider(containerIdentifier: containerIdentifier)
        )
    }
}

/// Where the data lives.
public enum StorageKind: String, Sendable {
    case local
    case iCloud
}
