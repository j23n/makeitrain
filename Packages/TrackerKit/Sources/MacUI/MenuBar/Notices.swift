#if os(macOS)
import SwiftUI
import TrackerCore
import TrackerKit

/// What's wrong with storage right now, if anything.
struct Notices: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
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
                .help(model.issues.map(\.path).joined(separator: "\n"))
            }
            if let error = model.lastError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .lineLimit(3)
            }
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.top, isEmpty ? 0 : 10)
    }

    private var isEmpty: Bool {
        model.state == .ready && model.missingFiles == 0 && model.issues.isEmpty && model.lastError == nil
    }
}

#if DEBUG
#Preview("Notices") {
    VStack(alignment: .leading, spacing: 12) {
        Notices(model: PreviewData.model(state: .loading))
        Divider()
        Notices(model: PreviewData.model(state: .waitingForICloud, missingFiles: 12))
        Divider()
        Notices(model: PreviewData.model(state: .iCloudUnavailable))
        Divider()
        Notices(model: PreviewData.model(
            issues: [FileIssue(path: "entries/2026-09.json", problem: .unreadable("Not JSON"))],
            lastError: "You don't have permission to save the file “projects.json”."
        ))
    }
    .padding(.bottom, 12)
    .frame(width: 340)
}
#endif
#endif
