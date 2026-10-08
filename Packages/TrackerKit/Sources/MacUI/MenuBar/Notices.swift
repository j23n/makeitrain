#if os(macOS)
import SwiftUI
import TrackerCore
import TrackerKit

/// What's wrong with storage right now, if anything.
struct Notices: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            StorageNotices(model: model)
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.top, model.hasStorageNotices ? 10 : 0)
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
