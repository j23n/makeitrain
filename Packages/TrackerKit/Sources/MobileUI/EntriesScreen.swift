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

        var id: LocalDate { day }
    }

    var body: some View {
        NavigationStack(path: $path) {
            let flagged = model.overlaps.flagged
            let days = self.days
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
                        MobileDayHeader(model: model, day: day.day, entries: day.entries)
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
                } else if days.isEmpty {
                    ContentUnavailableView.search(text: search)
                }
            }
            .searchable(text: $search, prompt: "Notes, projects and tags")
            .navigationTitle("Entries")
            .navigationDestination(for: UUID.self) { id in
                EntryForm(model: model, id: id, select: { copy in
                    path = [copy]
                })
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
            .map { day, entries in Day(day: day, entries: entries.reversed()) }
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

/// A day's date and the time logged on it. It's a view of its own because
/// a running timer's time grows with the clock: only the header follows the
/// clock, not the whole list.
struct MobileDayHeader: View {
    let model: AppModel
    let day: LocalDate
    let entries: [ResolvedEntry]

    var body: some View {
        HStack {
            Text(day.year == model.today.year ? Format.day(day) : Format.longDay(day))
            Spacer()
            Text(Format.duration(entries.reduce(0) { $0 + model.duration(of: $1) }))
                .monospacedDigit()
        }
    }
}

/// An entry in the list: its project, times, duration and note, with the
/// overlap warning or the running mark the Mac's table shows. VoiceOver
/// reads it as one.
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
                    OverlapIcon()
                } else if entry.isRunning {
                    RunningIcon()
                }
                // Only the running timer's time follows the clock.
                Text(Format.duration(entry.end.map { entry.start.distance(to: $0) } ?? model.duration(of: entry)))
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
                // On as many lines as they need, rather than squeezed onto
                // one in a narrow row.
                TagList(
                    tags: entry.entry.tags,
                    links: model.ledger.issueLinks(tags: entry.entry.tags, projectID: entry.entry.projectID),
                    interactive: false,
                    wraps: true
                )
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var times: String {
        let zone = entry.entry.timeZone
        let end = entry.end.map { Format.time($0, zone: zone) } ?? "running"
        let text = "\(Format.time(entry.start, zone: zone)) – \(end)"
        return Format.zoneLabel(zone, at: entry.start).map { "\(text) \($0)" } ?? text
    }
}

/// Edits one entry, on the iPhone's Entries tab and in the iPad's
/// inspectors. Times are shown and edited in its own time zone.
struct EntryForm: View {
    let model: AppModel
    let id: UUID
    /// Shows another entry, such as the copy "Duplicate Entry" makes.
    var select: ((UUID) -> Void)? = nil
    /// What happens once the entry is deleted. Unless given, the form goes
    /// back.
    var deleted: (() -> Void)? = nil
    @Environment(\.undoManager) private var undoManager
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingDelete = false
    @State private var splitting = false

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
                CommitField(title: "Note", value: entry.entry.note, axis: .vertical) { note in
                    update("Change Note") { $0.note = note }
                }
            }

            Section {
                CommitField(title: "Tags, separated by commas", value: entry.entry.tags.joined(separator: ", ")) { text in
                    update("Change Tags") { $0.tags = text.split(separator: ",").map(String.init) }
                }
                let unused = model.ledger.tags(ofProject: entry.entry.projectID).filter { tag in
                    !entry.entry.tags.contains { Tags.same($0, tag) }
                }
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

            let links = model.ledger.issueLinks(tags: entry.entry.tags, projectID: entry.entry.projectID)
            if !links.isEmpty {
                Section("GitHub") {
                    ForEach(entry.entry.tags.filter { links[$0] != nil }, id: \.self) { tag in
                        if let url = links[tag] {
                            Link(destination: url) {
                                Label("Open \(tag)", systemImage: "arrow.up.right.square")
                            }
                        }
                    }
                }
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
                    LabeledContent("Duration") {
                        CommitField(title: "Duration", value: Format.duration(entry.start.distance(to: end))) { text in
                            guard let duration = Format.parseDuration(text) else { return }
                            update("Change Duration") { $0.end = $0.start.adding(milliseconds: duration) }
                        }
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.numbersAndPunctuation)
                    }
                } else {
                    LabeledContent("Duration", value: Format.duration(model.duration(of: entry)))
                    Button {
                        model.stopTimer(undoManager: undoManager)
                    } label: {
                        Label("Stop Timer", systemImage: "stop.fill")
                    }
                    .tint(.red)
                }
            } footer: {
                if let label = Format.zoneLabel(zone, at: entry.start) {
                    Text("Times are in \(label) (\(zone)), where the entry was recorded.")
                }
            }
            .environment(\.timeZone, Zones.zone(zone))

            overlapSection(entry)

            Section {
                if let select {
                    Button("Duplicate Entry") {
                        if let copy = model.duplicateEntries([id], undoManager: undoManager).first {
                            select(copy)
                        }
                    }
                    .disabled(entry.isRunning)
                }
                Button("Split Entry…") {
                    splitting = true
                }
                .disabled(EntrySplit.range(of: entry, now: model.now) == nil)
                Button("Delete Entry", role: .destructive) {
                    confirmingDelete = true
                }
            }
        }
        .disabled(model.isReadOnly)
        .sheet(isPresented: $splitting) {
            SplitEntrySheet(model: model, entry: entry)
        }
        .navigationTitle(entry.entry.day.year == model.today.year ? Format.day(entry.entry.day) : Format.longDay(entry.entry.day))
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Delete this entry?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete Entry", role: .destructive) {
                model.deleteEntries([id], undoManager: undoManager)
                if let deleted {
                    deleted()
                } else {
                    dismiss()
                }
            }
        }
    }

    @ViewBuilder
    private func overlapSection(_ entry: ResolvedEntry) -> some View {
        let overlaps = model.overlaps.overlaps.filter { $0.earlier == entry.id || $0.later == entry.id }
        if !overlaps.isEmpty {
            Section("Overlaps") {
                ForEach(overlaps, id: \.self) { overlap in
                    VStack(alignment: .leading, spacing: 6) {
                        Label {
                            Text(model.overlapDescription(overlap, from: entry.id))
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                        if let fix = overlap.fix {
                            Button(fix.title) {
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

#if DEBUG
#Preview("Entries") {
    EntriesScreen(model: PreviewData.model())
}

#Preview("No Entries") {
    EntriesScreen(model: PreviewData.model(Ledger()))
}

#Preview("Entry") {
    NavigationStack {
        EntryForm(model: PreviewData.model(), id: PreviewData.entry("Wireframe review, round 2"))
    }
}

#Preview("Overlapping Entry") {
    NavigationStack {
        EntryForm(model: PreviewData.model(), id: PreviewData.entry("Call with Globex"))
    }
}

#Preview("Running Timer") {
    NavigationStack {
        EntryForm(model: PreviewData.model(), id: PreviewData.entry("Landing page copy"))
    }
}
#endif
#endif
