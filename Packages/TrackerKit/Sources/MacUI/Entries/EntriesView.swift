#if os(macOS)
import AppKit
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
    /// The zone the entry is shown and edited in.
    var zone: String { entry.entry.timeZone }

    /// The zone's short name, such as "EDT", when it isn't the Mac's.
    var zoneLabel: String? {
        Format.zoneLabel(zone, at: entry.start)
    }

    /// How many days after its start the entry ends, such as 1 for an
    /// entry past midnight.
    var endDays: Int {
        guard let end = entry.end else { return 0 }
        return end.local(in: zone).date.daysSince1970 - day.daysSince1970
    }

    func matches(_ search: String) -> Bool {
        search.isEmpty
            || note.localizedCaseInsensitiveContains(search)
            || projectTitle.localizedCaseInsensitiveContains(search)
            || entry.entry.tags.contains { $0.localizedCaseInsensitiveContains(search) }
    }
}

/// Every entry in a sortable table, edited in place: click a value to
/// change it. The context menu splits entries, fixes overlaps and changes
/// several entries at once.
struct EntriesView: View {
    let model: AppModel
    @Environment(\.undoManager) private var undoManager
    @State private var selection: Set<UUID>
    @State private var sortOrder = [KeyPathComparator(\EntryRow.start, order: .reverse)]
    @State private var search = ""
    @State private var overlapsOnly = false
    @State private var sheet: EntriesSheet?

    init(model: AppModel, selection: Set<UUID> = []) {
        self.model = model
        _selection = State(initialValue: selection)
    }

    var body: some View {
        let allTags = model.ledger.allTags()
        Table(rows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("", value: \EntryRow.status) { row in
                EntryStatusIcon(row: row)
            }
            .width(16)
            TableColumn("Date", value: \EntryRow.day) { row in
                EntryDateCell(model: model, row: row)
            }
            .width(min: 80, ideal: 100)
            TableColumn("Start", value: \EntryRow.start) { row in
                EntryStartCell(model: model, row: row)
            }
            .width(min: 60, ideal: 80)
            TableColumn("End", value: \EntryRow.endSort) { row in
                EntryEndCell(model: model, row: row)
            }
            .width(min: 60, ideal: 80)
            TableColumn("Duration", value: \EntryRow.duration) { row in
                EntryDurationCell(model: model, row: row)
            }
            .width(min: 50, ideal: 64)
            TableColumn("Project", value: \EntryRow.projectTitle) { row in
                EntryProjectCell(model: model, row: row)
            }
            .width(min: 100, ideal: 180)
            TableColumn("Tags", value: \EntryRow.tagsText) { row in
                TagField(tags: row.entry.entry.tags, suggestions: allTags, placeholder: "", bordered: false) { tags in
                    model.updateEntries([row.id], actionName: "Change Tags", undoManager: undoManager) { $0.tags = tags }
                }
                .disabled(model.isReadOnly)
            }
            .width(min: 60, ideal: 130)
            TableColumn("Note", value: \EntryRow.note) { row in
                CommitField(title: "", value: row.note) { note in
                    model.updateEntries([row.id], actionName: "Change Note", undoManager: undoManager) { $0.note = note }
                }
                .textFieldStyle(.plain)
                .disabled(model.isReadOnly)
            }
            .width(min: 100, ideal: 240)
        }
        .contextMenu(forSelectionType: UUID.self) { ids in
            EntriesMenu(model: model, ids: ids, allTags: allTags, undoManager: undoManager, sheet: $sheet)
        }
        .onDeleteCommand {
            guard !selection.isEmpty, !model.isReadOnly else { return }
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
            }
        }
        .sheet(item: $sheet) { sheet in
            EntriesSheetView(model: model, sheet: sheet, undoManager: undoManager)
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
                .help("Overlaps another entry. Right-click for a fix.")
        } else if row.entry.isRunning {
            Image(systemName: "record.circle")
                .foregroundStyle(.red)
                .help("Running")
        }
    }
}

// MARK: - Cells

/// The entry's day, which opens a calendar to move the entry to another
/// day at the same times.
struct EntryDateCell: View {
    let model: AppModel
    let row: EntryRow
    @Environment(\.undoManager) private var undoManager
    @State private var choosing = false

    var body: some View {
        Button {
            choosing = true
        } label: {
            Text(row.day.year == model.today.year ? Format.day(row.day) : Format.longDay(row.day))
        }
        .buttonStyle(.plain)
        .help("Move to another day")
        .disabled(model.isReadOnly)
        .popover(isPresented: $choosing, arrowEdge: .bottom) {
            DatePicker(
                "Date",
                selection: Binding(
                    get: { row.day.pickerDate },
                    set: { date in
                        choosing = false
                        move(to: LocalDate(pickerDate: date))
                    }
                ),
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .labelsHidden()
            .padding(8)
        }
    }

    /// Moves the entry to `day`, keeping its wall-clock start and its
    /// duration. The running timer's start can't move past now.
    private func move(to day: LocalDate) {
        let entry = row.entry
        guard day != row.day else { return }
        let start = entry.startOn(day)
        if entry.isRunning {
            model.setRunningStart(start, undoManager: undoManager)
        } else {
            let shift = entry.start.distance(to: start)
            model.updateEntries([entry.id], actionName: "Change Date", undoManager: undoManager) { changed in
                changed.start = start
                changed.end = changed.end?.adding(milliseconds: shift)
            }
        }
    }
}

/// The start, as a time to type over in the entry's own time zone. A start
/// after the end is refused.
struct EntryStartCell: View {
    let model: AppModel
    let row: EntryRow
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        HStack(spacing: 4) {
            CommitField(title: "", value: Format.time(row.start, zone: row.zone), commit: commit)
            if let label = row.zoneLabel {
                Text(label)
                    .foregroundStyle(.secondary)
                    .help("Recorded in \(row.zone)")
            }
        }
        .textFieldStyle(.plain)
        .monospacedDigit()
        .disabled(model.isReadOnly)
    }

    private func commit(_ text: String) {
        guard let second = Format.parseTime(text) else { return NSSound.beep() }
        let start = row.entry.startAt(secondOfDay: second)
        if row.entry.isRunning {
            model.setRunningStart(start, undoManager: undoManager)
        } else if let end = row.entry.end, start <= end {
            model.updateEntries([row.id], actionName: "Change Start", undoManager: undoManager) { $0.start = start }
        } else {
            NSSound.beep()
        }
    }
}

/// The end, as a time to type over in the entry's own time zone. An end
/// earlier than the start is on the next day, shown as "+1".
struct EntryEndCell: View {
    let model: AppModel
    let row: EntryRow
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        if let end = row.entry.end {
            HStack(spacing: 4) {
                CommitField(title: "", value: Format.time(end, zone: row.zone), commit: commit)
                if row.endDays > 0 {
                    Text("+\(row.endDays)")
                        .foregroundStyle(.secondary)
                        .help("Ends on a later day")
                }
            }
            .textFieldStyle(.plain)
            .monospacedDigit()
            .disabled(model.isReadOnly)
        } else {
            Text("Running")
                .foregroundStyle(.secondary)
        }
    }

    private func commit(_ text: String) {
        guard let second = Format.parseTime(text) else { return NSSound.beep() }
        let end = row.entry.endAt(secondOfDay: second)
        model.updateEntries([row.id], actionName: "Change End", undoManager: undoManager) { $0.end = end }
    }
}

/// The duration, which moves the end when typed over. The running timer's
/// just counts.
struct EntryDurationCell: View {
    let model: AppModel
    let row: EntryRow
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        if row.entry.isRunning {
            Text(Format.duration(row.duration))
                .monospacedDigit()
        } else {
            CommitField(title: "", value: Format.duration(row.duration)) { text in
                guard let duration = Format.parseDuration(text) else { return NSSound.beep() }
                model.updateEntries([row.id], actionName: "Change Duration", undoManager: undoManager) {
                    $0.end = $0.start.adding(milliseconds: duration)
                }
            }
            .textFieldStyle(.plain)
            .monospacedDigit()
            .disabled(model.isReadOnly)
        }
    }
}

/// The project, which opens the searchable project list.
struct EntryProjectCell: View {
    let model: AppModel
    let row: EntryRow
    @Environment(\.undoManager) private var undoManager
    @State private var choosing = false

    var body: some View {
        Button {
            choosing = true
        } label: {
            ProjectLabel(ledger: model.ledger, projectID: row.entry.entry.projectID)
        }
        .buttonStyle(.plain)
        .help("Choose a project; type to search clients and projects")
        .disabled(model.isReadOnly)
        .popover(isPresented: $choosing, arrowEdge: .bottom) {
            ProjectChooser(ledger: model.ledger, current: ProjectChoice(row.entry.entry.projectID)) { projectID in
                choosing = false
                model.updateEntries([row.id], actionName: "Change Project", undoManager: undoManager) { $0.projectID = projectID }
            } cancel: {
                choosing = false
            }
            .frame(width: 320)
        }
    }
}

#if DEBUG
#Preview("Entries") {
    EntriesView(model: PreviewData.model())
        .frame(width: 1100, height: 500)
}

#Preview("Overlap Selected") {
    EntriesView(model: PreviewData.model(), selection: [PreviewData.entry("Call with Globex")])
        .frame(width: 1100, height: 500)
}

#Preview("No Entries") {
    EntriesView(model: PreviewData.model(Ledger()))
        .frame(width: 1100, height: 500)
}

#Preview("Read-Only") {
    EntriesView(model: PreviewData.model(state: .iCloudUnavailable))
        .frame(width: 1100, height: 500)
}
#endif
#endif
