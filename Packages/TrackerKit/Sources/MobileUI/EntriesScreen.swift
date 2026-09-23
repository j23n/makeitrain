#if os(iOS)
import SwiftUI
import TrackerCore
import TrackerKit

/// Entries by day, newest first. Tap one to edit it, swipe to delete.
struct EntriesScreen: View {
    let model: AppModel
    @Environment(\.undoManager) private var undoManager
    @State private var path: [UUID] = []
    @State private var search = ""

    struct Day: Identifiable {
        var day: LocalDate
        var entries: [ResolvedEntry]
        var total: Int64

        var id: LocalDate { day }
    }

    var body: some View {
        NavigationStack(path: $path) {
            let flagged = model.overlaps.flagged
            List {
                MobileNotices(model: model)
                ForEach(days) { day in
                    Section {
                        ForEach(day.entries) { entry in
                            NavigationLink(value: entry.id) {
                                MobileEntryRow(model: model, entry: entry, flagged: flagged.contains(entry.id))
                            }
                        }
                        .onDelete { offsets in
                            model.deleteEntries(offsets.map { day.entries[$0].id }, undoManager: undoManager)
                        }
                        .deleteDisabled(model.isReadOnly)
                    } header: {
                        HStack {
                            Text(day.day.year == model.today.year ? Format.day(day.day) : Format.longDay(day.day))
                            Spacer()
                            Text(Format.duration(day.total))
                                .monospacedDigit()
                        }
                    }
                }
            }
            .overlay {
                if model.resolved.isEmpty {
                    ContentUnavailableView(
                        "No Entries",
                        systemImage: "clock",
                        description: Text("Start a timer, or add an entry with the + button.")
                    )
                }
            }
            .searchable(text: $search, prompt: "Notes, projects and tags")
            .navigationTitle("Entries")
            .navigationDestination(for: UUID.self) { id in
                EntryForm(model: model, id: id)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: addEntry) {
                        Label("New Entry", systemImage: "plus")
                    }
                    .disabled(model.isReadOnly)
                }
            }
        }
    }

    private var days: [Day] {
        var byDay: [LocalDate: [ResolvedEntry]] = [:]
        for entry in model.resolved where matches(entry) {
            byDay[entry.entry.day, default: []].append(entry)
        }
        return byDay
            .map { day, entries in
                Day(
                    day: day,
                    entries: entries.reversed(),
                    total: entries.reduce(0) { $0 + model.duration(of: $1) }
                )
            }
            .sorted { $0.day > $1.day }
    }

    private func matches(_ entry: ResolvedEntry) -> Bool {
        search.isEmpty
            || entry.entry.note.localizedCaseInsensitiveContains(search)
            || model.ledger.projectTitle(entry.entry.projectID).localizedCaseInsensitiveContains(search)
            || entry.entry.tags.contains { $0.localizedCaseInsensitiveContains(search) }
    }

    private func addEntry() {
        let end = model.environment.now().wholeSeconds
        let entry = TimeEntry(start: end.adding(seconds: -3600), end: end, timeZone: model.environment.timeZone(), updated: end)
        model.addEntry(entry, undoManager: undoManager)
        path.append(entry.id)
    }
}

/// An entry in the list: its project, times, duration and note.
struct MobileEntryRow: View {
    let model: AppModel
    let entry: ResolvedEntry
    let flagged: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                ProjectLabel(ledger: model.ledger, projectID: entry.entry.projectID)
                Spacer()
                if flagged {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .accessibilityLabel("Overlaps another entry")
                }
                Text(Format.duration(model.duration(of: entry)))
                    .monospacedDigit()
            }
            Text(times)
                .font(.caption)
                .foregroundStyle(.secondary)
            if !entry.entry.note.isEmpty {
                Text(entry.entry.note)
                    .font(.callout)
                    .lineLimit(2)
            }
            if !entry.entry.tags.isEmpty {
                TagList(tags: entry.entry.tags)
            }
        }
    }

    private var times: String {
        let zone = entry.entry.timeZone
        let end = entry.end.map { Format.time($0, zone: zone) } ?? "running"
        let text = "\(Format.time(entry.start, zone: zone)) – \(end)"
        return Format.zoneLabel(zone, at: entry.start).map { "\(text) \($0)" } ?? text
    }
}

/// Edits one entry. Times are shown and edited in its own time zone.
struct EntryForm: View {
    let model: AppModel
    let id: UUID
    @Environment(\.undoManager) private var undoManager
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingDelete = false

    var body: some View {
        if let entry = model.resolved.first(where: { $0.id == id }) {
            form(entry)
        } else {
            ContentUnavailableView("Entry Deleted", systemImage: "trash")
        }
    }

    private func form(_ entry: ResolvedEntry) -> some View {
        let zone = entry.entry.timeZone
        return Form {
            Section {
                ProjectPicker(ledger: model.ledger, selection: Binding(
                    get: { entry.entry.projectID },
                    set: { projectID in update("Change Project") { $0.projectID = projectID } }
                ))
                .pickerStyle(.navigationLink)
                CommitField(title: "Note", value: entry.entry.note, axis: .vertical) { note in
                    update("Change Note") { $0.note = note }
                }
            }

            Section {
                CommitField(title: "Tags, separated by commas", value: entry.entry.tags.joined(separator: ", ")) { text in
                    update("Change Tags") { $0.tags = text.split(separator: ",").map(String.init) }
                }
                let unused = model.ledger.allTags().filter { tag in !entry.entry.tags.contains { Tags.same($0, tag) } }
                if !unused.isEmpty {
                    Menu("Add a Tag") {
                        ForEach(unused, id: \.self) { tag in
                            Button(tag) {
                                update("Add Tag") { $0.tags.append(tag) }
                            }
                        }
                    }
                }
            } header: {
                Text("Tags")
            }

            Section {
                DatePicker(
                    "Start",
                    selection: Binding(
                        get: { entry.start.date },
                        set: { date in update("Change Start") { $0.start = Timestamp(date) } }
                    ),
                    in: ...(entry.end ?? model.now).date,
                    displayedComponents: [.date, .hourAndMinute]
                )
                if let end = entry.end {
                    DatePicker(
                        "End",
                        selection: Binding(
                            get: { end.date },
                            set: { date in update("Change End") { $0.end = Timestamp(date) } }
                        ),
                        in: entry.start.date...,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    LabeledContent("Duration", value: Format.duration(entry.start.distance(to: end)))
                } else {
                    LabeledContent("Duration", value: Format.duration(model.duration(of: entry)))
                    Button("Stop Timer") {
                        model.stopTimer(undoManager: undoManager)
                    }
                }
            } footer: {
                if let label = Format.zoneLabel(zone, at: entry.start) {
                    Text("Times are in \(label) (\(zone)), where the entry was recorded.")
                }
            }
            .environment(\.timeZone, Zones.zone(zone))

            overlapSection(entry)

            Section {
                Button("Delete Entry", role: .destructive) {
                    confirmingDelete = true
                }
            }
        }
        .disabled(model.isReadOnly)
        .navigationTitle(entry.entry.day.year == model.today.year ? Format.day(entry.entry.day) : Format.longDay(entry.entry.day))
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Delete this entry?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete Entry", role: .destructive) {
                model.deleteEntries([id], undoManager: undoManager)
                dismiss()
            }
        }
    }

    @ViewBuilder
    private func overlapSection(_ entry: ResolvedEntry) -> some View {
        let overlaps = model.overlaps.overlaps.filter { $0.earlier == entry.id || $0.later == entry.id }
        if !overlaps.isEmpty {
            Section("Overlaps") {
                ForEach(overlaps, id: \.self) { overlap in
                    let otherID = overlap.earlier == entry.id ? overlap.later : overlap.earlier
                    let other = model.resolved.first { $0.id == otherID }
                    VStack(alignment: .leading, spacing: 6) {
                        Label(
                            "\(Format.duration(overlap.duration)) with \(other.map { model.ledger.projectTitle($0.entry.projectID) } ?? "another entry")",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        if let fix = overlap.fix {
                            Button(fix.isSplit ? "Split Entry Around It" : "Trim Earlier Entry") {
                                model.apply(fix, undoManager: undoManager)
                            }
                        }
                    }
                }
            }
        }
    }

    private func update(_ actionName: String, _ change: (inout TimeEntry) -> Void) {
        model.updateEntries([id], actionName: actionName, undoManager: undoManager, change)
    }
}

extension OverlapFix {
    var isSplit: Bool {
        if case .split = self { return true }
        return false
    }
}
#endif
