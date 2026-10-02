#if os(iOS)
import SwiftUI
import TrackerCore
import TrackerKit

/// Each project's tags on iPad, under the project, with the selected one in
/// the inspector to rename, merge or remove it in its project.
struct PadTagsScreen: View {
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
                        .textCase(nil)
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
                PadInspectorButton(shown: $showInspector)
            }
        }
        .padInspector(shown: $showInspector, hasSelection: selection != nil) {
            selection = nil
        } inspector: {
            NavigationStack {
                if let group = groups.first(where: { $0.projectID == selection?.projectID }),
                   let row = group.rows.first(where: { $0.id == selection }) {
                    TagForm(model: model, row: row, projectTags: group.rows.map(\.tag)) { renamed in
                        selection = TagKey(projectID: row.projectID, tag: renamed.lowercased())
                    }
                    .id(row.id)
                } else {
                    ContentUnavailableView("No Selection", systemImage: "tag", description: Text("Tap a tag to rename, merge or remove it."))
                }
            }
        }
        .onChange(of: selection) { _, newSelection in
            if newSelection != nil {
                showInspector = true
            }
        }
    }
}

/// Renames a tag on its project's entries, merging it into another of the
/// project's tags when given that tag's name, or removes it from them.
struct TagForm: View {
    let model: AppModel
    let row: TagRow
    /// The tags of the same project.
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
                LabeledContent("Name") {
                    CommitField(title: "Name", value: row.tag) { name in
                        guard let cleaned = Tags.normalize([name]).first, cleaned != row.tag else { return }
                        if let existing = projectTags.first(where: { Tags.same($0, cleaned) && !Tags.same($0, row.tag) }) {
                            mergeInto = existing
                        } else {
                            rename(to: cleaned)
                        }
                    }
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                }
                LabeledContent("Entries", value: "\(row.count)")
                LabeledContent("Time Logged", value: Format.duration(row.milliseconds))
            } footer: {
                Text("Renaming a tag changes it on this project's entries only. Renaming it to another of the project's tags merges the two.")
            }
            if let url = model.ledger.issueURL(forTag: row.tag, projectID: row.projectID) {
                Section {
                    Link(destination: url) {
                        Label("Open \(row.tag) on GitHub", systemImage: "arrow.up.right.square")
                    }
                } footer: {
                    Text(url.absoluteString)
                        .textSelection(.enabled)
                }
            }
            Section {
                Button("Remove from the Project's Entries…", role: .destructive) {
                    confirmingRemove = true
                }
            }
        }
        .disabled(model.isReadOnly)
        .navigationTitle(row.tag)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Merge “\(row.tag)” into “\(mergeInto ?? "")”?",
            isPresented: Binding(get: { mergeInto != nil }, set: { if !$0 { mergeInto = nil } }),
            titleVisibility: .visible,
            presenting: mergeInto
        ) { target in
            Button("Merge") {
                rename(to: target)
            }
        } message: { target in
            Text("Every entry of \(project) tagged “\(row.tag)” is tagged “\(target)” instead.")
        }
        .confirmationDialog("Remove “\(row.tag)” from every entry of \(project)?", isPresented: $confirmingRemove, titleVisibility: .visible) {
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
    NavigationStack {
        PadTagsScreen(model: PreviewData.model(), selection: TagKey(projectID: PreviewData.website, tag: "design"))
            .navigationTitle("Tags")
            .navigationBarTitleDisplayMode(.inline)
    }
    .defaultAppStorage(UserDefaults(suiteName: "PadTagsPreview")!)
}

#Preview("Linked Tag") {
    NavigationStack {
        PadTagsScreen(model: PreviewData.model(), selection: TagKey(projectID: PreviewData.website, tag: "#42"))
            .navigationTitle("Tags")
            .navigationBarTitleDisplayMode(.inline)
    }
    .defaultAppStorage(UserDefaults(suiteName: "PadTagsPreview")!)
}

#Preview("No Tags") {
    NavigationStack {
        PadTagsScreen(model: PreviewData.model(Ledger()))
            .navigationTitle("Tags")
            .navigationBarTitleDisplayMode(.inline)
    }
}
#endif
#endif
