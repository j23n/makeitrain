#if os(macOS)
import SwiftUI
import TrackerCore
import TrackerKit

/// A tag with how many entries have it and their time.
struct TagRow: Identifiable, Hashable {
    var tag: String
    var count: Int
    var milliseconds: Int64

    var id: String { tag.lowercased() }

    static func rows(tags: [String], resolved: [ResolvedEntry], now: Timestamp) -> [TagRow] {
        var count: [String: Int] = [:]
        var time: [String: Int64] = [:]
        for entry in resolved {
            for tag in Set(entry.entry.tags.map { $0.lowercased() }) {
                count[tag, default: 0] += 1
                time[tag, default: 0] += entry.duration(now: now)
            }
        }
        return tags.map { tag in
            TagRow(tag: tag, count: count[tag.lowercased()] ?? 0, milliseconds: time[tag.lowercased()] ?? 0)
        }
    }
}

/// Every tag, with an inspector to rename, merge or remove it.
struct TagsView: View {
    let model: AppModel
    @State private var selection: String?
    @AppStorage("tags.inspector") private var showInspector = true

    init(model: AppModel, selection: String? = nil) {
        self.model = model
        _selection = State(initialValue: selection)
    }

    var body: some View {
        let rows = TagRow.rows(tags: model.ledger.allTags(), resolved: model.resolved, now: model.now)
        List(rows, selection: $selection) { row in
            HStack {
                Label(row.tag, systemImage: "tag")
                Spacer()
                Text(row.count == 1 ? "1 entry" : "\(row.count) entries")
                    .foregroundStyle(.secondary)
                Text(Format.duration(row.milliseconds))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 50, alignment: .trailing)
            }
        }
        .overlay {
            if rows.isEmpty {
                ContentUnavailableView("No Tags", systemImage: "tag", description: Text("Tags you add to entries show up here."))
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
                if let row = rows.first(where: { $0.id == selection }) {
                    TagEditor(model: model, row: row, allTags: rows.map(\.tag)) { renamed in
                        selection = renamed.lowercased()
                    }
                    .id(row.id)
                } else {
                    ContentUnavailableView("No Selection", systemImage: "tag", description: Text("Select a tag to rename, merge or remove it."))
                }
            }
            .inspectorColumnWidth(min: 260, ideal: 300, max: 420)
        }
    }
}

/// Renames a tag on every entry, merging it into another tag when given
/// that tag's name, or removes it from every entry.
struct TagEditor: View {
    let model: AppModel
    let row: TagRow
    let allTags: [String]
    let renamed: (String) -> Void
    @Environment(\.undoManager) private var undoManager
    @State private var mergeInto: String?
    @State private var confirmingRemove = false

    var body: some View {
        Form {
            Section {
                CommitField(title: "Name", value: row.tag) { name in
                    guard let cleaned = Tags.normalize([name]).first, cleaned != row.tag else { return }
                    if let existing = allTags.first(where: { Tags.same($0, cleaned) && !Tags.same($0, row.tag) }) {
                        mergeInto = existing
                    } else {
                        rename(to: cleaned)
                    }
                }
                LabeledContent("Entries", value: "\(row.count)")
                LabeledContent("Time Logged", value: Format.duration(row.milliseconds))
            } footer: {
                Text("Renaming a tag to the name of another tag merges the two.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Button("Remove from All Entries…", role: .destructive) {
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
            Text("Every entry tagged “\(row.tag)” is tagged “\(target)” instead.")
        }
        .confirmationDialog("Remove “\(row.tag)” from every entry?", isPresented: $confirmingRemove) {
            Button("Remove", role: .destructive) {
                model.removeTag(row.tag, undoManager: undoManager)
            }
        }
    }

    private func rename(to name: String) {
        model.renameTag(row.tag, to: name, undoManager: undoManager)
        renamed(name)
    }
}

#if DEBUG
#Preview("Tag") {
    TagsView(model: PreviewData.model(), selection: "design")
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
