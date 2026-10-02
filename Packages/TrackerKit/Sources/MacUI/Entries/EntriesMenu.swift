#if os(macOS)
import AppKit
import SwiftUI
import TrackerCore
import TrackerKit

/// The context menu for entries, in the entries table and on the timeline:
/// duplicate, split or delete them, fix an overlap, or change their project
/// and tags.
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
                ForEach(issues, id: \.self) { issue in
                    Button("Open \(issue.tag) on GitHub") {
                        NSWorkspace.shared.open(issue.url)
                    }
                }
                Divider()
            }
            Group {
                Button(entries.count == 1 ? "Duplicate Entry" : "Duplicate \(entries.count) Entries") {
                    select(Set(model.duplicateEntries(entries.map(\.id), undoManager: undoManager)))
                }
                .disabled(entries.allSatisfy(\.isRunning))
                if entries.count == 1, let entry = entries.first {
                    Button("Split Entry…") {
                        sheet = .split(entry.id)
                    }
                    .disabled(EntrySplit.range(of: entry, now: model.now) == nil)
                    if entry.isRunning {
                        Button("Stop Timer") {
                            model.stopTimer(undoManager: undoManager)
                        }
                    }
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
                Divider()
                Button("Set Project…") {
                    sheet = .project(ids)
                }
                let projectTags = EntryMenuItems.projectTags(of: entries, in: model.projectTags)
                Menu("Add Tag") {
                    ForEach(projectTags, id: \.self) { tag in
                        Button(tag) {
                            model.updateEntries(ids, actionName: "Add Tag", undoManager: undoManager) { $0.tags.append(tag) }
                        }
                    }
                    if !projectTags.isEmpty {
                        Divider()
                    }
                    Button("New Tag…") {
                        sheet = .newTag(ids)
                    }
                }
                let tags = EntryMenuItems.tags(in: entries)
                if !tags.isEmpty {
                    Menu("Remove Tag") {
                        ForEach(tags, id: \.self) { tag in
                            Button(tag) {
                                model.updateEntries(ids, actionName: "Remove Tag", undoManager: undoManager) { entry in
                                    entry.tags.removeAll { Tags.same($0, tag) }
                                }
                            }
                        }
                    }
                }

                Divider()
                Button(entries.count == 1 ? "Delete Entry" : "Delete \(entries.count) Entries", role: .destructive) {
                    model.deleteEntries(ids, undoManager: undoManager)
                }
            }
            .disabled(model.isReadOnly)
        }
    }
}

/// A sheet the entries table shows.
enum EntriesSheet: Hashable, Identifiable {
    case split(UUID)
    case project(Set<UUID>)
    case newTag(Set<UUID>)

    var id: Self { self }
}

/// The sheet for an `EntriesSheet`. Each is given the table window's undo
/// manager, so its change undoes there.
struct EntriesSheetView: View {
    let model: AppModel
    let sheet: EntriesSheet
    let undoManager: UndoManager?

    var body: some View {
        switch sheet {
        case .split(let id):
            if let entry = model.resolved.first(where: { $0.id == id }) {
                SplitEntrySheet(model: model, entry: entry, undoManager: undoManager)
            }
        case .project(let ids):
            SetProjectSheet(model: model, ids: ids, undoManager: undoManager)
        case .newTag(let ids):
            NewTagSheet(model: model, ids: ids, undoManager: undoManager)
        }
    }
}

/// Asks where to split an entry, in the entry's own time zone, and shows
/// the two parts that makes.
struct SplitEntrySheet: View {
    let model: AppModel
    let entry: ResolvedEntry
    let undoManager: UndoManager?
    @Environment(\.dismiss) private var dismiss
    @State private var time: Date

    init(model: AppModel, entry: ResolvedEntry, undoManager: UndoManager?) {
        self.model = model
        self.entry = entry
        self.undoManager = undoManager
        _time = State(initialValue: EntrySplit.suggestedTime(for: entry, now: model.now))
    }

    var body: some View {
        let zone = entry.entry.timeZone
        let range = EntrySplit.range(of: entry, now: model.now)
        let end = entry.end ?? model.now
        let split = Timestamp(time).wholeSeconds
        let spansDays = entry.start.local(in: zone).date != end.local(in: zone).date
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Split Entry")
                    .font(.headline)
                Text("\(model.ledger.projectTitle(entry.entry.projectID)), \(times(entry.start, entry.end))")
                    .foregroundStyle(.secondary)
            }
            Form {
                DatePicker(
                    "Split at:",
                    selection: $time,
                    in: range ?? time...time,
                    displayedComponents: spansDays ? [.date, .hourAndMinute] : [.hourAndMinute]
                )
                LabeledContent("First part:") {
                    Text("\(times(entry.start, split)) (\(Format.duration(entry.start.distance(to: split))))")
                        .monospacedDigit()
                }
                LabeledContent("Second part:") {
                    Group {
                        if let end = entry.end {
                            Text("\(times(split, end)) (\(Format.duration(split.distance(to: end))))")
                        } else {
                            Text("\(Format.time(split, zone: zone)) – running")
                        }
                    }
                    .monospacedDigit()
                }
            }
            .environment(\.timeZone, Zones.zone(zone))
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("Split") {
                    model.splitEntry(entry.id, at: split, undoManager: undoManager)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(range == nil)
            }
        }
        .padding(20)
        .frame(width: 380)
    }

    /// Two times in the entry's zone, such as "09:00 – 10:30".
    private func times(_ start: Timestamp, _ end: Timestamp?) -> String {
        let zone = entry.entry.timeZone
        return "\(Format.time(start, zone: zone)) – \(end.map { Format.time($0, zone: zone) } ?? "running")"
    }
}

/// Asks for a project for the entries, with the searchable project list.
struct SetProjectSheet: View {
    let model: AppModel
    let ids: Set<UUID>
    let undoManager: UndoManager?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let projects = Set(model.resolved.filter { ids.contains($0.id) }.map(\.entry.projectID))
        VStack(spacing: 0) {
            Text(ids.count == 1 ? "Set Project" : "Set Project for \(ids.count) Entries")
                .font(.headline)
                .padding(.top, 14)
            ProjectChooser(
                ledger: model.ledger,
                current: projects.count == 1 ? projects.first.map(ProjectChoice.init) : nil
            ) { projectID in
                model.updateEntries(ids, actionName: "Change Project", undoManager: undoManager) { $0.projectID = projectID }
                dismiss()
            } cancel: {
                dismiss()
            }
            Divider()
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(12)
        }
        .frame(width: 340)
    }
}

/// Asks for tags to add to the entries, typed with commas between them.
struct NewTagSheet: View {
    let model: AppModel
    let ids: Set<UUID>
    let undoManager: UndoManager?
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    private var tags: [String] {
        Tags.normalize(text.split(separator: ",").map(String.init))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(ids.count == 1 ? "Add Tags" : "Add Tags to \(ids.count) Entries")
                .font(.headline)
            TextField("Tags", text: $text, prompt: Text("Tags, separated by commas"))
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
                .onSubmit(add)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("Add", action: add)
                    .keyboardShortcut(.defaultAction)
                    .disabled(tags.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 340)
    }

    private func add() {
        let added = tags
        guard !added.isEmpty else { return }
        // Reuse the spelling of a tag the entries' projects have.
        let known = EntryMenuItems.projectTags(of: model.resolved.filter { ids.contains($0.id) }, in: model.projectTags)
        let spelled = added.map { tag in known.first { Tags.same($0, tag) } ?? tag }
        model.updateEntries(ids, actionName: "Add Tags", undoManager: undoManager) { $0.tags += spelled }
        dismiss()
    }
}

#if DEBUG
#Preview("Context Menu") {
    // A menu button, since a preview can't right-click.
    Menu("Right-Click on “Call with Globex”") {
        EntriesMenu(
            model: PreviewData.model(),
            ids: [PreviewData.entry("Call with Globex")],
            undoManager: nil,
            sheet: .constant(nil),
            select: { _ in }
        )
    }
    .fixedSize()
    .padding(40)
}

#Preview("Context Menu, Several Entries") {
    Menu("Right-Click on Three Entries") {
        EntriesMenu(
            model: PreviewData.model(),
            ids: [PreviewData.entry("Moodboard"), PreviewData.entry("Hero section"), PreviewData.entry("Offline mode")],
            undoManager: nil,
            sheet: .constant(nil),
            select: { _ in }
        )
    }
    .fixedSize()
    .padding(40)
}

#Preview("Split Entry") {
    let model = PreviewData.model()
    let entry = model.resolved.first { $0.id == PreviewData.entry("Sync engine") }!
    return SplitEntrySheet(model: model, entry: entry, undoManager: nil)
}

#Preview("Split Running Timer") {
    let model = PreviewData.model()
    return SplitEntrySheet(model: model, entry: model.running!, undoManager: nil)
}

#Preview("Set Project") {
    SetProjectSheet(
        model: PreviewData.model(),
        ids: [PreviewData.entry("Moodboard"), PreviewData.entry("Hero section")],
        undoManager: nil
    )
}

#Preview("Add Tags") {
    NewTagSheet(model: PreviewData.model(), ids: [PreviewData.entry("Email")], undoManager: nil)
}
#endif
#endif
