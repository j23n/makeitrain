#if os(macOS)
import SwiftUI
import TrackerCore
import TrackerKit

/// The entries table's context menu, for the entries right-clicked: split
/// one, fix its overlaps, or change several at once.
struct EntriesMenu: View {
    let model: AppModel
    let ids: Set<UUID>
    /// Every tag in use, to add from.
    let allTags: [String]
    /// The window's, since a menu may not see it.
    let undoManager: UndoManager?
    @Binding var sheet: EntriesSheet?

    var body: some View {
        let entries = model.resolved.filter { ids.contains($0.id) }
        if !entries.isEmpty {
            Group {
                if entries.count == 1, let entry = entries.first {
                    Button("Split Entry…") {
                        sheet = .split(entry.id)
                    }
                    .disabled(SplitEntrySheet.range(of: entry, now: model.now) == nil)
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
                    Divider()
                }

                Button("Set Project…") {
                    sheet = .project(ids)
                }
                Menu("Add Tag") {
                    ForEach(allTags, id: \.self) { tag in
                        Button(tag) {
                            model.updateEntries(ids, actionName: "Add Tag", undoManager: undoManager) { $0.tags.append(tag) }
                        }
                    }
                    if !allTags.isEmpty {
                        Divider()
                    }
                    Button("New Tag…") {
                        sheet = .newTag(ids)
                    }
                }
                let tags = Self.tags(in: entries)
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

    /// The tags on any of the entries, once each, ignoring case.
    static func tags(in entries: [ResolvedEntry]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for entry in entries {
            for tag in entry.entry.tags where seen.insert(tag.lowercased()).inserted {
                result.append(tag)
            }
        }
        return result.sorted { $0.lowercased() < $1.lowercased() }
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
        _time = State(initialValue: Self.suggestedTime(for: entry, now: model.now))
    }

    /// The times an entry can be split at: at least a minute after its
    /// start and before its end, or before now while it runs. Nil when it's
    /// too short to split.
    static func range(of entry: ResolvedEntry, now: Timestamp) -> ClosedRange<Date>? {
        let first = entry.start.adding(seconds: 60)
        let last = (entry.end ?? now).adding(seconds: -60)
        guard first <= last else { return nil }
        return first.date...last.date
    }

    /// The middle of the entry, on a multiple of five minutes if there's
    /// one inside it.
    static func suggestedTime(for entry: ResolvedEntry, now: Timestamp) -> Date {
        guard let range = range(of: entry, now: now) else { return entry.start.date }
        let middle = entry.start.adding(milliseconds: entry.start.distance(to: entry.end ?? now) / 2)
        let fiveMinutes: Int64 = 300_000
        let snapped = Timestamp(milliseconds: (middle.milliseconds + fiveMinutes / 2) / fiveMinutes * fiveMinutes)
        if range.contains(snapped.date) {
            return snapped.date
        }
        let minute = Timestamp(milliseconds: (middle.milliseconds + 30000) / 60000 * 60000)
        return min(max(minute.date, range.lowerBound), range.upperBound)
    }

    var body: some View {
        let zone = entry.entry.timeZone
        let range = Self.range(of: entry, now: model.now)
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
        // Reuse an existing tag's spelling.
        let known = model.ledger.allTags()
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
            allTags: PreviewData.ledger.allTags(),
            undoManager: nil,
            sheet: .constant(nil)
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
            allTags: PreviewData.ledger.allTags(),
            undoManager: nil,
            sheet: .constant(nil)
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
