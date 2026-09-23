#if os(iOS)
import SwiftUI
import TrackerKit
import UIKit

/// The iPhone and iPad app's scene. It saves when the app goes to the
/// background and brings the clock up to date when it comes back.
public struct MobileScenes: Scene {
    @State private var model = AppModel(environment: .live())
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

/// The tabs.
struct MobileRoot: View {
    let model: AppModel

    var body: some View {
        TabView {
            TimerScreen(model: model)
                .tabItem { Label("Timer", systemImage: "stopwatch") }
            EntriesScreen(model: model)
                .tabItem { Label("Entries", systemImage: "list.bullet") }
            MobileReportsScreen(model: model)
                .tabItem { Label("Reports", systemImage: "chart.bar.xaxis") }
            MobileSettingsScreen(model: model)
                .tabItem { Label("Settings", systemImage: "gear") }
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
#endif
