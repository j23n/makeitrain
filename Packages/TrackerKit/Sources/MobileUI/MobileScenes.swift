#if os(iOS)
import SwiftUI
import TimerActivity
import TrackerCore
import TrackerKit
import UIKit

/// The iPhone and iPad app's scene. It saves when the app goes to the
/// background and brings the clock up to date when it comes back. An iPad
/// can open it in several windows, which share the data.
public struct MobileScenes: Scene {
    @State private var model = AppModel.shared
    @Environment(\.scenePhase) private var scenePhase

    public init() {}

    public var body: some Scene {
        WindowGroup {
            MobileRoot(model: model)
                .task { await model.start() }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                saveInBackground()
            case .active:
                model.refreshClock()
            default:
                break
            }
        }
    }

    /// Saves unsaved changes, asking iOS for time to finish.
    private func saveInBackground() {
        guard model.hasUnsavedChanges else { return }
        let application = UIApplication.shared
        var identifier = UIBackgroundTaskIdentifier.invalid
        identifier = application.beginBackgroundTask(withName: "Save") {
            application.endBackgroundTask(identifier)
            identifier = .invalid
        }
        Task {
            await model.flush()
            if identifier != .invalid {
                application.endBackgroundTask(identifier)
                identifier = .invalid
            }
        }
    }
}

/// The iPhone's tabs, or on an iPad wide enough the Mac's layout, in
/// light or dark as chosen.
struct MobileRoot: View {
    let model: AppModel

    /// The width from which an iPad window uses the Mac's layout.
    static let wideWidth: CGFloat = 960

    var body: some View {
        GeometryReader { geometry in
            if UIDevice.current.userInterfaceIdiom == .pad, geometry.size.width >= Self.wideWidth {
                PadWideRoot(model: model)
            } else {
                PhoneRoot(model: model)
            }
        }
        .onChange(of: model.preferences.appearance, initial: true) { _, appearance in
            apply(appearance)
        }
        .background(LiveActivitySync(model: model))
    }

    /// Sets every window's appearance, sheets included, which a color
    /// scheme preference doesn't reliably reach.
    private func apply(_ appearance: Preferences.Appearance) {
        let style: UIUserInterfaceStyle = switch appearance {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
        for scene in UIApplication.shared.connectedScenes {
            guard let scene = scene as? UIWindowScene else { continue }
            for window in scene.windows {
                window.overrideUserInterfaceStyle = style
            }
        }
    }
}

/// Keeps the Live Activity in step with the running timer. It's a view of
/// its own, so a change to the data doesn't redraw the root, which would
/// build the iPhone's screens again.
private struct LiveActivitySync: View {
    let model: AppModel

    var body: some View {
        Color.clear
            .onChange(of: LiveActivities.state(of: model), initial: true) { _, state in
                LiveActivities.shared.show(state)
            }
    }
}

/// What's wrong with storage right now, if anything, as a list section.
struct MobileNotices: View {
    let model: AppModel

    var body: some View {
        if model.hasStorageNotices {
            Section {
                StorageNotices(model: model)
            }
            .font(.callout)
        }
    }
}

#if DEBUG
#Preview("App") {
    MobileRoot(model: PreviewData.model())
}

#Preview("iPhone") {
    PhoneRoot(model: PreviewData.model())
}

#Preview("No Data") {
    MobileRoot(model: PreviewData.model(Ledger()))
}

#Preview("Notices") {
    List {
        MobileNotices(model: PreviewData.model(state: .waitingForICloud, missingFiles: 12))
        MobileNotices(model: PreviewData.model(state: .iCloudUnavailable))
        MobileNotices(model: PreviewData.model(
            issues: [FileIssue(path: "entries/2026-09.json", problem: .unreadable("Not JSON"))],
            lastError: "You don't have permission to save the file “projects.json”."
        ))
    }
}
#endif
#endif
