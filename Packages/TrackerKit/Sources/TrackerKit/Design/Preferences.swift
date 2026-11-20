import Foundation
import Observation
import TrackerCore

/// Settings that stay on this device. Clients, projects and entries are
/// in the data files, which sync; these don't.
@MainActor
@Observable
public final class Preferences {
    /// Light or dark, or following the system.
    public enum Appearance: String, CaseIterable, Identifiable, Sendable {
        case system, light, dark

        public var id: Self { self }

        public var title: String {
            switch self {
            case .system: "System"
            case .light: "Light"
            case .dark: "Dark"
            }
        }
    }

    /// A key combination that opens the command line over any app on the
    /// Mac, as Carbon's key code and modifier flags.
    public struct Shortcut: Codable, Hashable, Sendable {
        public var keyCode: UInt32
        public var modifiers: UInt32
        /// How it's shown, such as "⌥Space".
        public var title: String

        public init(keyCode: UInt32, modifiers: UInt32, title: String) {
            self.keyCode = keyCode
            self.modifiers = modifiers
            self.title = title
        }
    }

    public var appearance: Appearance {
        didSet { defaults.set(appearance.rawValue, forKey: Keys.appearance) }
    }

    /// Whether the menu bar shows the running time next to the icon.
    public var menuBarShowsTime: Bool {
        didSet { defaults.set(menuBarShowsTime, forKey: Keys.menuBarShowsTime) }
    }

    /// Whether the menu bar shows the running project's name too.
    public var menuBarShowsProject: Bool {
        didSet { defaults.set(menuBarShowsProject, forKey: Keys.menuBarShowsProject) }
    }

    /// Whether the menu bar icon is marked when something needs correcting.
    public var menuBarMarksCorrections: Bool {
        didSet { defaults.set(menuBarMarksCorrections, forKey: Keys.menuBarMarksCorrections) }
    }

    /// Whether the command line closes after Return, to get back to work.
    public var closesAfterReturn: Bool {
        didSet { defaults.set(closesAfterReturn, forKey: Keys.closesAfterReturn) }
    }

    /// The shortcut that opens the command line from anywhere. None until
    /// one is set.
    public var shortcut: Shortcut? {
        didSet {
            if let shortcut, let data = try? JSONEncoder().encode(shortcut) {
                defaults.set(data, forKey: Keys.shortcut)
            } else {
                defaults.removeObject(forKey: Keys.shortcut)
            }
        }
    }

    /// Whether the running timer shows on the Lock Screen.
    public var showsLiveActivity: Bool {
        didSet { defaults.set(showsLiveActivity, forKey: Keys.showsLiveActivity) }
    }

    /// Whether this device notifies when a contract's time left reaches its
    /// alert, and when its hours run out.
    public var contractAlerts: Bool {
        didSet { defaults.set(contractAlerts, forKey: Keys.contractAlerts) }
    }

    /// The contract alerts this device has shown, by key, so each shows once.
    public private(set) var notifiedContractAlerts: Set<String>

    /// The contract alerts this device has scheduled for a running timer,
    /// by key, and when they're due.
    public private(set) var scheduledContractAlerts: [String: Timestamp]

    /// The corrections skipped on this device, by id, the latest last.
    public private(set) var skippedCorrections: [String]

    /// Lines run on the command line, the latest last.
    public private(set) var history: [String]

    @ObservationIgnored private let defaults: UserDefaults

    private enum Keys {
        static let appearance = "appearance"
        static let menuBarShowsTime = "menuBarShowsTime"
        static let menuBarShowsProject = "menuBarShowsProject"
        static let menuBarMarksCorrections = "menuBarMarksCorrections"
        static let closesAfterReturn = "closesCommandAfterReturn"
        static let shortcut = "commandShortcut"
        static let showsLiveActivity = "showsLiveActivity"
        static let contractAlerts = "contractAlerts"
        static let notifiedContractAlerts = "notifiedContractAlerts"
        static let scheduledContractAlerts = "scheduledContractAlerts"
        static let skippedCorrections = "skippedCorrections"
        static let history = "commandHistory"
    }

    /// The most skipped corrections and lines remembered.
    static let skippedLimit = 500
    static let historyLimit = 100

    public init(defaults: UserDefaults) {
        self.defaults = defaults
        appearance = defaults.string(forKey: Keys.appearance).flatMap(Appearance.init(rawValue:)) ?? .system
        menuBarShowsTime = defaults.object(forKey: Keys.menuBarShowsTime) as? Bool ?? true
        menuBarShowsProject = defaults.object(forKey: Keys.menuBarShowsProject) as? Bool ?? false
        menuBarMarksCorrections = defaults.object(forKey: Keys.menuBarMarksCorrections) as? Bool ?? true
        closesAfterReturn = defaults.object(forKey: Keys.closesAfterReturn) as? Bool ?? true
        shortcut = defaults.data(forKey: Keys.shortcut).flatMap { try? JSONDecoder().decode(Shortcut.self, from: $0) }
        showsLiveActivity = defaults.object(forKey: Keys.showsLiveActivity) as? Bool ?? true
        contractAlerts = defaults.object(forKey: Keys.contractAlerts) as? Bool ?? true
        notifiedContractAlerts = Set(defaults.stringArray(forKey: Keys.notifiedContractAlerts) ?? [])
        scheduledContractAlerts = (defaults.dictionary(forKey: Keys.scheduledContractAlerts) ?? [:])
            .compactMapValues { ($0 as? NSNumber).map { Timestamp(milliseconds: $0.int64Value) } }
        skippedCorrections = defaults.stringArray(forKey: Keys.skippedCorrections) ?? []
        history = defaults.stringArray(forKey: Keys.history) ?? []
    }

    // MARK: - Corrections

    public func isSkipped(_ id: String) -> Bool {
        skippedCorrections.contains(id)
    }

    /// Remembers that a correction was skipped, so it isn't offered again
    /// on this device.
    public func skip(_ id: String) {
        guard !isSkipped(id) else { return }
        skippedCorrections = Array((skippedCorrections + [id]).suffix(Self.skippedLimit))
        defaults.set(skippedCorrections, forKey: Keys.skippedCorrections)
    }

    // MARK: - Contract alerts

    /// Remembers which contract alerts were shown and scheduled.
    public func rememberContractAlerts(notified: Set<String>, scheduled: [String: Timestamp]) {
        if notified != notifiedContractAlerts {
            notifiedContractAlerts = notified
            defaults.set(notified.sorted(), forKey: Keys.notifiedContractAlerts)
        }
        if scheduled != scheduledContractAlerts {
            scheduledContractAlerts = scheduled
            defaults.set(scheduled.mapValues(\.milliseconds), forKey: Keys.scheduledContractAlerts)
        }
    }

    // MARK: - History

    /// Remembers a line that was run, for Up to bring back.
    public func remember(_ line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        history = Array((history.filter { $0 != trimmed } + [trimmed]).suffix(Self.historyLimit))
        defaults.set(history, forKey: Keys.history)
    }
}
