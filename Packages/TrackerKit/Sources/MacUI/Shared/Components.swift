#if os(macOS)
import SwiftUI
import TrackerCore
import TrackerKit

/// A project's color and title, such as "● Acme › Website".
struct ProjectLabel: View {
    let ledger: Ledger
    let projectID: UUID?

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(ledger.color(ofProject: projectID))
                .frame(width: 8, height: 8)
            Text(ledger.projectTitle(projectID))
                .lineLimit(1)
                .foregroundStyle(projectID == nil ? .secondary : .primary)
        }
    }
}

/// Tags as small capsules.
struct TagList: View {
    let tags: [String]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(.caption)
                    .lineLimit(1)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(.quaternary))
            }
        }
    }
}

/// A menu of live projects, grouped by client, with "No Project" first. A
/// selected project that has since been archived stays visible.
struct ProjectPicker: View {
    let ledger: Ledger
    @Binding var selection: UUID?
    var title = "Project"

    var body: some View {
        Picker(title, selection: $selection) {
            Text("No Project").tag(UUID?.none)
            Divider()
            ForEach(ledger.pickerProjects()) { project in
                Text(ledger.projectTitle(project.id)).tag(UUID?.some(project.id))
            }
            if let selection, ledger.isArchived(project: selection) {
                Text(ledger.projectTitle(selection)).tag(UUID?.some(selection))
            }
        }
    }
}

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
#endif
