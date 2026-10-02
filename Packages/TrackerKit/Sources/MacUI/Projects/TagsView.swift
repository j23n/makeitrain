#if os(macOS)
import AppKit
import SwiftUI
import TrackerCore
import TrackerKit

/// Each project's tags, with an inspector to rename, merge or remove one
/// in its project.
struct TagsView: View {
    let model: AppModel
    @State private var selection: TagKey?
    @AppStorage("tags.inspector") private var showInspector = true

    init(model: AppModel, selection: TagKey? = nil) {
        self.model = model
        _selection = State(initialValue: selection)
    }

    var body: some View {
        let groups = TagGroup.groups(ledger: model.ledger, resolved: model.resolved, now: model.now)
        List(selection: $selection) {
            ForEach(groups) { group in
                Section {
                    ForEach(group.rows) { row in
                        TagRowView(row: row, linked: model.ledger.issueURL(forTag: row.tag, projectID: row.projectID) != nil)
                            .tag(row.id)
                    }
                } header: {
                    ProjectLabel(ledger: model.ledger, projectID: group.projectID)
                }
            }
        }
        .overlay {
            if groups.isEmpty {
                ContentUnavailableView("No Tags", systemImage: "tag", description: Text("Tags you add to a project's entries show up here, under the project."))
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showInspector.toggle()
                } label: {
                    Label("Inspector", systemImage: "sidebar.right")
                }
                .help("Show or hide the inspector")
            }
        }
        .inspector(isPresented: $showInspector) {
            Group {
                if let group = groups.first(where: { $0.projectID == selection?.projectID }),
                   let row = group.rows.first(where: { $0.id == selection }) {
                    TagEditor(model: model, row: row, projectTags: group.rows.map(\.tag)) { renamed in
                        selection = TagKey(projectID: row.projectID, tag: renamed.lowercased())
                    }
                    .id(row.id)
                } else {
                    ContentUnavailableView("No Selection", systemImage: "tag", description: Text("Select a tag to rename, merge or remove it."))
                }
            }
            .inspectorWidth()
        }
    }
}

/// Renames a tag on its project's entries, merging it into another of the
/// project's tags when given that tag's name, or removes it from them.
struct TagEditor: View {
    let model: AppModel
    let row: TagRow
    /// The other tags of the same project.
    let projectTags: [String]
    let renamed: (String) -> Void
    @Environment(\.undoManager) private var undoManager
    @State private var mergeInto: String?
    @State private var confirmingRemove = false

    var body: some View {
        let project = model.ledger.projectTitle(row.projectID)
        Form {
            Section {
                LabeledContent("Project") {
                    ProjectLabel(ledger: model.ledger, projectID: row.projectID)
                }
                CommitField(title: "Name", value: row.tag) { name in
                    guard let cleaned = Tags.normalize([name]).first, cleaned != row.tag else { return }
                    if let existing = projectTags.first(where: { Tags.same($0, cleaned) && !Tags.same($0, row.tag) }) {
                        mergeInto = existing
                    } else {
                        rename(to: cleaned)
                    }
                }
                LabeledContent("Entries", value: "\(row.count)")
                LabeledContent("Time Logged", value: Format.duration(row.milliseconds))
            } footer: {
                Text("Renaming a tag changes it on this project's entries only. Renaming it to another of the project's tags merges the two.")
                    .foregroundStyle(.secondary)
            }
            if let url = model.ledger.issueURL(forTag: row.tag, projectID: row.projectID) {
                Section {
                    Button("Open \(row.tag) on GitHub") {
                        NSWorkspace.shared.open(url)
                    }
                } footer: {
                    Text(url.absoluteString)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            Section {
                Button("Remove from the Project's Entries…", role: .destructive) {
                    confirmingRemove = true
                }
            }
        }
        .formStyle(.grouped)
        .disabled(model.isReadOnly)
        .confirmationDialog(
            "Merge “\(row.tag)” into “\(mergeInto ?? "")”?",
            isPresented: Binding(get: { mergeInto != nil }, set: { if !$0 { mergeInto = nil } }),
            presenting: mergeInto
        ) { target in
            Button("Merge") {
                rename(to: target)
            }
        } message: { target in
            Text("Every entry of \(project) tagged “\(row.tag)” is tagged “\(target)” instead.")
        }
        .confirmationDialog("Remove “\(row.tag)” from every entry of \(project)?", isPresented: $confirmingRemove) {
            Button("Remove", role: .destructive) {
                model.removeTag(row.tag, fromProject: row.projectID, undoManager: undoManager)
            }
        }
    }

    private func rename(to name: String) {
        model.renameTag(row.tag, to: name, inProject: row.projectID, undoManager: undoManager)
        renamed(name)
    }
}

#if DEBUG
#Preview("Tag") {
    TagsView(model: PreviewData.model(), selection: TagKey(projectID: PreviewData.website, tag: "design"))
        .frame(width: 800, height: 500)
}

#Preview("Linked Tag") {
    TagsView(model: PreviewData.model(), selection: TagKey(projectID: PreviewData.website, tag: "#42"))
        .frame(width: 800, height: 500)
}

#Preview("Nothing Selected") {
    TagsView(model: PreviewData.model())
        .frame(width: 800, height: 500)
}

#Preview("No Tags") {
    TagsView(model: PreviewData.model(Ledger()))
        .frame(width: 800, height: 500)
}
#endif
#endif
