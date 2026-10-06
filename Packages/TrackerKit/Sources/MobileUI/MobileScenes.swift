#if os(iOS)
import SwiftUI
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
        .commands {
            PadCommands()
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

/// The iPhone's tabs, or the iPad's sidebar, in light or dark as chosen.
struct MobileRoot: View {
    let model: AppModel

    var body: some View {
        Group {
            if UIDevice.current.userInterfaceIdiom == .pad {
                PadRoot(model: model)
            } else {
                PhoneRoot(model: model)
            }
        }
        .onChange(of: model.preferences.appearance, initial: true) { _, appearance in
            apply(appearance)
        }
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

/// What's wrong with storage right now, if anything, as a list section.
struct MobileNotices: View {
    let model: AppModel

    var body: some View {
        if model.state != .ready || model.missingFiles > 0 || !model.issues.isEmpty || model.lastError != nil {
            Section {
                switch model.state {
                case .loading:
                    Label("Loading…", systemImage: "hourglass")
                case .waitingForICloud:
                    Label("Looking for your data in iCloud…", systemImage: "icloud")
                case .iCloudUnavailable:
                    Label("iCloud isn't available, so your data is read-only.", systemImage: "icloud.slash")
                    Button("Use Local Storage") {
                        Task { try? await model.switchStorage(to: .local) }
                    }
                case .ready:
                    EmptyView()
                }
                if model.missingFiles > 0 {
                    Label("Downloading \(model.missingFiles) files from iCloud…", systemImage: "icloud.and.arrow.down")
                }
                if !model.issues.isEmpty {
                    Label(
                        model.issues.count == 1 ? "A data file can't be read." : "\(model.issues.count) data files can't be read.",
                        systemImage: "exclamationmark.triangle"
                    )
                }
                if let error = model.lastError {
                    Label(error, systemImage: "exclamationmark.triangle")
                }
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
