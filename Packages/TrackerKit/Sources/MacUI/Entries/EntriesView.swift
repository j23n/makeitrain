#if os(macOS)
import SwiftUI
import TrackerCore
import TrackerKit

/// An entry as a row in the entries table, with the values it sorts by.
struct EntryRow: Identifiable {
    let entry: ResolvedEntry
    let duration: Int64
    let projectTitle: String
    let flagged: Bool

    init(_ entry: ResolvedEntry, ledger: Ledger, now: Timestamp, flagged: Bool) {
        self.entry = entry
        duration = entry.duration(now: now)
        projectTitle = ledger.projectTitle(entry.entry.projectID)
        self.flagged = flagged
    }

    var id: UUID { entry.id }
    var day: LocalDate { entry.entry.day }
    var start: Timestamp { entry.start }
    /// A running timer sorts as ending in the far future.
    var endSort: Timestamp { entry.end ?? Timestamp(milliseconds: .max) }
    var tagsText: String { entry.entry.tags.joined(separator: ", ") }
    var note: String { entry.entry.note }
    var status: Int { flagged ? 2 : entry.isRunning ? 1 : 0 }

    /// The start in the entry's own zone, labeled with the zone when it
    /// isn't the Mac's.
    var startText: String {
        let zone = entry.entry.timeZone
        let text = Format.time(entry.start, zone: zone)
        return Format.zoneLabel(zone, at: entry.start).map { "\(text) \($0)" } ?? text
    }

    /// The end, with "+1" when it's on a later day.
    var endText: String {
        guard let end = entry.end else { return "Running" }
        let zone = entry.entry.timeZone
        let text = Format.time(end, zone: zone)
        let days = end.local(in: zone).date.daysSince1970 - day.daysSince1970
        return days > 0 ? "\(text) +\(days)" : text
    }

    func matches(_ search: String) -> Bool {
        search.isEmpty
            || note.localizedCaseInsensitiveContains(search)
            || projectTitle.localizedCaseInsensitiveContains(search)
            || entry.entry.tags.contains { $0.localizedCaseInsensitiveContains(search) }
    }
}

/// Every entry in a sortable table, with an inspector to edit the selected
/// ones.
struct EntriesView: View {
    let model: AppModel
    @Environment(\.undoManager) private var undoManager
    @State private var selection: Set<UUID>
    @State private var sortOrder = [KeyPathComparator(\EntryRow.start, order: .reverse)]
    @State private var search = ""
    @State private var overlapsOnly = false
    @AppStorage("entries.inspector") private var showInspector = true

    init(model: AppModel, selection: Set<UUID> = []) {
        self.model = model
        _selection = State(initialValue: selection)
    }

    var body: some View {
        Table(rows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("", value: \EntryRow.status) { row in
                EntryStatusIcon(row: row)
            }
            .width(16)
            TableColumn("Date", value: \EntryRow.day) { row in
                Text(row.day.year == model.today.year ? Format.day(row.day) : Format.longDay(row.day))
            }
            .width(min: 80, ideal: 95)
            TableColumn("Start", value: \EntryRow.start) { row in
                Text(row.startText)
                    .monospacedDigit()
            }
            .width(min: 56, ideal: 72)
            TableColumn("End", value: \EntryRow.endSort) { row in
                Text(row.endText)
                    .monospacedDigit()
            }
            .width(min: 56, ideal: 72)
            TableColumn("Duration", value: \EntryRow.duration) { row in
                Text(Format.duration(row.duration))
                    .monospacedDigit()
            }
            .width(min: 44, ideal: 56)
            TableColumn("Project", value: \EntryRow.projectTitle) { row in
                ProjectLabel(ledger: model.ledger, projectID: row.entry.entry.projectID)
            }
            .width(min: 100, ideal: 160)
            TableColumn("Tags", value: \EntryRow.tagsText)
                .width(min: 50, ideal: 90)
            TableColumn("Note", value: \EntryRow.note)
                .width(min: 80, ideal: 160)
        }
        .contextMenu(forSelectionType: UUID.self) { ids in
            if !ids.isEmpty {
                Button(ids.count == 1 ? "Delete Entry" : "Delete \(ids.count) Entries", role: .destructive) {
                    model.deleteEntries(ids, undoManager: undoManager)
                }
                .disabled(model.isReadOnly)
            }
        } primaryAction: { ids in
            selection = ids
            showInspector = true
        }
        .onDeleteCommand {
            guard !selection.isEmpty else { return }
            model.deleteEntries(selection, undoManager: undoManager)
        }
        .overlay {
            if model.resolved.isEmpty {
                ContentUnavailableView(
                    "No Entries",
                    systemImage: "clock",
                    description: Text("Start a timer from the menu bar, or add an entry with the + button.")
                )
            }
        }
        .searchable(text: $search, placement: .toolbar, prompt: "Notes, projects and tags")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Toggle(isOn: $overlapsOnly) {
                    Label("Show Overlaps", systemImage: "exclamationmark.triangle")
                }
                .help("Show only entries that overlap another")
                Button(action: addEntry) {
                    Label("New Entry", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: .command)
                .help("Add an entry for the last hour")
                .disabled(model.isReadOnly)
                Button {
                    showInspector.toggle()
                } label: {
                    Label("Inspector", systemImage: "sidebar.right")
                }
                .help("Show or hide the inspector")
            }
        }
        .inspector(isPresented: $showInspector) {
            EntryInspector(model: model, ids: selection)
        }
    }

    private var rows: [EntryRow] {
        let flagged = model.overlaps.flagged
        return model.resolved
            .lazy
            .map { EntryRow($0, ledger: model.ledger, now: model.now, flagged: flagged.contains($0.id)) }
            .filter { !overlapsOnly || $0.flagged }
            .filter { $0.matches(search) }
            .sorted(using: sortOrder)
    }

    private func addEntry() {
        let end = model.environment.now().wholeSeconds
        let entry = TimeEntry(start: end.adding(seconds: -3600), end: end, timeZone: model.environment.timeZone(), updated: end)
        model.addEntry(entry, undoManager: undoManager)
        selection = [entry.id]
        showInspector = true
    }
}

/// A warning for an entry that overlaps another, or a dot for the running
/// timer.
struct EntryStatusIcon: View {
    let row: EntryRow

    var body: some View {
        if row.flagged {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .help("Overlaps another entry")
        } else if row.entry.isRunning {
            Image(systemName: "record.circle")
                .foregroundStyle(.red)
                .help("Running")
        }
    }
}
#endif
