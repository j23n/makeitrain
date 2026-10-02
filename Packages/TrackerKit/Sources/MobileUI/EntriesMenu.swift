#if os(iOS)
import SwiftUI
import TrackerCore
import TrackerKit

/// The context menu for entries on iPad, in the entries list and on the
/// timeline: open the issues their tags refer to, duplicate, split or
/// delete them, fix an overlap, or change their project and tags.
struct EntriesMenu: View {
    let model: AppModel
    let ids: Set<UUID>
    /// The window's, since a menu may not see it.
    let undoManager: UndoManager?
    @Binding var sheet: EntriesSheet?
    /// Selects the copies "Duplicate" makes.
    let select: (Set<UUID>) -> Void

    var body: some View {
        let entries = model.resolved.filter { ids.contains($0.id) }
        if !entries.isEmpty {
            let issues = EntryMenuItems.issues(of: entries, in: model.ledger)
            if !issues.isEmpty {
                Section {
                    ForEach(issues, id: \.self) { issue in
                        Link(destination: issue.url) {
                            Label("Open \(issue.tag) on GitHub", systemImage: "arrow.up.right.square")
                        }
                    }
                }
            }
            Group {
                Section {
                    Button {
                        select(Set(model.duplicateEntries(entries.map(\.id), undoManager: undoManager)))
                    } label: {
                        Label(entries.count == 1 ? "Duplicate Entry" : "Duplicate \(entries.count) Entries", systemImage: "plus.square.on.square")
                    }
                    .disabled(entries.allSatisfy(\.isRunning))
                    if entries.count == 1, let entry = entries.first {
                        Button {
                            sheet = .split(entry.id)
                        } label: {
                            Label("Split Entry…", systemImage: "scissors")
                        }
                        .disabled(EntrySplit.range(of: entry, now: model.now) == nil)
                        if entry.isRunning {
                            Button {
                                model.stopTimer(undoManager: undoManager)
                            } label: {
                                Label("Stop Timer", systemImage: "stop.fill")
                            }
                        }
                    }
                }
                if entries.count == 1, let entry = entries.first {
                    ForEach(model.overlaps.overlaps.filter { $0.earlier == entry.id || $0.later == entry.id }, id: \.self) { overlap in
                        Section(model.overlapDescription(overlap, from: entry.id)) {
                            if let fix = overlap.fix {
                                Button(fix.title) {
                                    model.apply(fix, undoManager: undoManager)
                                }
                            }
                        }
                    }
                }
                Section {
                    Button {
                        sheet = .project(ids)
                    } label: {
                        Label("Set Project…", systemImage: "folder")
                    }
                    let projectTags = EntryMenuItems.projectTags(of: entries, in: model.projectTags)
                    Menu {
                        ForEach(projectTags, id: \.self) { tag in
                            Button(tag) {
                                model.updateEntries(ids, actionName: "Add Tag", undoManager: undoManager) { $0.tags.append(tag) }
                            }
                        }
                        Section {
                            Button("New Tag…") {
                                sheet = .newTag(ids)
                            }
                        }
                    } label: {
                        Label("Add Tag", systemImage: "tag")
                    }
                    let tags = EntryMenuItems.tags(in: entries)
                    if !tags.isEmpty {
                        Menu {
                            ForEach(tags, id: \.self) { tag in
                                Button(tag) {
                                    model.updateEntries(ids, actionName: "Remove Tag", undoManager: undoManager) { entry in
                                        entry.tags.removeAll { Tags.same($0, tag) }
                                    }
                                }
                            }
                        } label: {
                            Label("Remove Tag", systemImage: "tag.slash")
                        }
                    }
                }
                Section {
                    Button(role: .destructive) {
                        model.deleteEntries(ids, undoManager: undoManager)
                    } label: {
                        Label(entries.count == 1 ? "Delete Entry" : "Delete \(entries.count) Entries", systemImage: "trash")
                    }
                }
            }
            .disabled(model.isReadOnly)
        }
    }
}

/// A sheet the entries' context menu opens.
enum EntriesSheet: Hashable, Identifiable {
    case split(UUID)
    case project(Set<UUID>)
    case newTag(Set<UUID>)

    var id: Self { self }
}

/// The sheet for an `EntriesSheet`.
struct EntriesSheetView: View {
    let model: AppModel
    let sheet: EntriesSheet

    var body: some View {
        switch sheet {
        case .split(let id):
            if let entry = model.resolved.first(where: { $0.id == id }) {
                SplitEntrySheet(model: model, entry: entry)
            }
        case .project(let ids):
            SetProjectSheet(model: model, ids: ids)
        case .newTag(let ids):
            NewTagSheet(model: model, ids: ids)
        }
    }
}

/// Asks where to split an entry, in the entry's own time zone, and shows
/// the two parts that makes.
struct SplitEntrySheet: View {
    let model: AppModel
    let entry: ResolvedEntry
    @Environment(\.dismiss) private var dismiss
    @Environment(\.undoManager) private var undoManager
    @State private var time: Date

    init(model: AppModel, entry: ResolvedEntry) {
        self.model = model
        self.entry = entry
        _time = State(initialValue: EntrySplit.suggestedTime(for: entry, now: model.now))
    }

    var body: some View {
        let zone = entry.entry.timeZone
        let range = EntrySplit.range(of: entry, now: model.now)
        let end = entry.end ?? model.now
        let split = Timestamp(time).wholeSeconds
        let spansDays = entry.start.local(in: zone).date != end.local(in: zone).date
        NavigationStack {
            Form {
                Section {
                    DatePicker(
                        "Split At",
                        selection: $time,
                        in: range ?? time...time,
                        displayedComponents: spansDays ? [.date, .hourAndMinute] : [.hourAndMinute]
                    )
                } footer: {
                    Text("\(model.ledger.projectTitle(entry.entry.projectID)), \(times(entry.start, entry.end))")
                }
                Section {
                    LabeledContent("First Part") {
                        Text("\(times(entry.start, split)) (\(Format.duration(entry.start.distance(to: split))))")
                            .monospacedDigit()
                    }
                    LabeledContent("Second Part") {
                        Group {
                            if let end = entry.end {
                                Text("\(times(split, end)) (\(Format.duration(split.distance(to: end))))")
                            } else {
                                Text("\(Format.time(split, zone: zone)) – running")
                            }
                        }
                        .monospacedDigit()
                    }
                } footer: {
                    Text("Both parts keep the project, tags and note.")
                }
            }
            .environment(\.timeZone, Zones.zone(zone))
            .navigationTitle("Split Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Split") {
                        model.splitEntry(entry.id, at: split, undoManager: undoManager)
                        dismiss()
                    }
                    .disabled(range == nil || model.isReadOnly)
                }
            }
        }
    }

    /// Two times in the entry's zone, such as "09:00 – 10:30".
    private func times(_ start: Timestamp, _ end: Timestamp?) -> String {
        let zone = entry.entry.timeZone
        return "\(Format.time(start, zone: zone)) – \(end.map { Format.time($0, zone: zone) } ?? "running")"
    }
}

/// Chooses a project for some entries, from the searchable project list.
struct SetProjectSheet: View {
    let model: AppModel
    let ids: Set<UUID>
    @Environment(\.dismiss) private var dismiss
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        let projects = Set(model.resolved.filter { ids.contains($0.id) }.map(\.entry.projectID))
        NavigationStack {
            ProjectChooserList(
                ledger: model.ledger,
                current: projects.count == 1 ? projects.first.map { ProjectChoice($0) } : nil,
                title: ids.count == 1 ? "Set Project" : "Set Project for \(ids.count) Entries"
            ) { projectID in
                model.updateEntries(ids, actionName: "Change Project", undoManager: undoManager) { $0.projectID = projectID }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

/// Asks for tags to add to some entries, typed with commas between them.
struct NewTagSheet: View {
    let model: AppModel
    let ids: Set<UUID>
    @Environment(\.dismiss) private var dismiss
    @Environment(\.undoManager) private var undoManager
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Tags, separated by commas", text: $text)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focused)
                        .submitLabel(.done)
                        .onSubmit(add)
                } footer: {
                    Text(ids.count == 1 ? "Adds the tags to the entry." : "Adds the tags to the \(ids.count) entries.")
                }
            }
            .navigationTitle("Add Tags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add", action: add)
                        .disabled(Tags.normalize(text.split(separator: ",").map(String.init)).isEmpty)
                }
            }
            .onAppear {
                focused = true
            }
        }
    }

    private func add() {
        let entries = model.resolved.filter { ids.contains($0.id) }
        let added = EntryMenuItems.newTags(text, for: entries, in: model.projectTags)
        guard !added.isEmpty else { return }
        model.updateEntries(ids, actionName: "Add Tags", undoManager: undoManager) { $0.tags += added }
        dismiss()
    }
}

#if DEBUG
#Preview("Context Menu") {
    // A menu button, since a preview can't touch and hold.
    Menu("Touch and Hold “Call with Globex”") {
        EntriesMenu(
            model: PreviewData.model(),
            ids: [PreviewData.entry("Call with Globex")],
            undoManager: nil,
            sheet: .constant(nil),
            select: { _ in }
        )
    }
    .padding(40)
}

#Preview("Split Entry") {
    let model = PreviewData.model()
    let entry = model.resolved.first { $0.id == PreviewData.entry("Sync engine") }!
    return SplitEntrySheet(model: model, entry: entry)
}

#Preview("Set Project") {
    SetProjectSheet(model: PreviewData.model(), ids: [PreviewData.entry("Moodboard"), PreviewData.entry("Hero section")])
}

#Preview("Add Tags") {
    NewTagSheet(model: PreviewData.model(), ids: [PreviewData.entry("Email")])
}
#endif
#endif
