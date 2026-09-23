import Foundation
import Observation
import TrackerCore

/// The app's data and actions, shared by the Mac and iOS apps.
@MainActor
@Observable
public final class AppModel {
    public private(set) var ledger = Ledger()

    public init() {}
}
