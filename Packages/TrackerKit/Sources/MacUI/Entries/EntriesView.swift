#if os(macOS)
import AppKit
import SwiftUI
import TrackerCore
import TrackerKit

/// An entry as a row in the entries table, with the values it sorts by.
struct EntryRow: Identifiable {
    let entry: ResolvedEntry
    let projectTitle: String
    let flagged: Bool

    init(_ entry: ResolvedEntry, projectTitle: String, flagged: Bool) {
        self.entry = entry
        self.projectTitle = projectTitle
        self.flagged = flagged
    }

    var id: UUID { entry.id }
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

    func matches(_ search: String) -> Bool {
        search.isEmpty
            || note.localizedCaseInsensitiveContains(search)
            || projectTitle.localizedCaseInsensitiveContains(search)
            || entry.entry.tags.contains { $0.localizedCaseInsensitiveContains(search) }
    }
}

/// The order of the entries table: by one of its columns, either way.
///
/// It compares the rows' values directly. Sorting with key paths, as
/// `KeyPathComparator` does, looks each value up through its key path for
/// every comparison, which adds up over thousands of entries.
struct EntryOrder: SortComparator, Hashable {
    enum Column: Hashable {
        case status, start, end, project, tags, note
    }

    var column: Column
    var order: SortOrder = .forward

    func compare(_ a: EntryRow, _ b: EntryRow) -> ComparisonResult {
        let result: ComparisonResult
        switch column {
        case .status: result = Self.ordering(a.status, b.status)
        case .start: result = Self.ordering(a.start, b.start)
        case .end: result = Self.ordering(a.endSort, b.endSort)
        case .project: result = a.projectTitle.compare(b.projectTitle, options: [.caseInsensitive, .numeric])
        case .tags: result = a.tagsText.compare(b.tagsText, options: [.caseInsensitive, .numeric])
        case .note: result = a.note.compare(b.note, options: [.caseInsensitive, .numeric])
        }
        guard order == .reverse else { return result }
        switch result {
        case .orderedAscending: return .orderedDescending
        case .orderedDescending: return .orderedAscending
        case .orderedSame: return .orderedSame
        }
    }

    private static func ordering<Value: Comparable>(_ a: Value, _ b: Value) -> ComparisonResult {
        a < b ? .orderedAscending : a > b ? .orderedDescending : .orderedSame
    }

    /// `rows`, which are in the model's order, by start, in `order`. By
    /// start, the newest first as the table opens, that's just the rows
    /// reversed, with no sorting at all.
    static func sort(_ rows: [EntryRow], by order: [EntryOrder]) -> [EntryRow] {
        guard let first = order.first else { return rows }
        if first.column == .start {
            return first.order == .forward ? rows : Array(rows.reversed())
        }
        return rows.sorted(using: order)
    }
}

/// Every entry in a sortable table, edited in place: click a value to
/// change it. The bar above narrows it to a period, clients, projects, tags
/// or overlaps. The context menu splits entries, fixes overlaps and changes
/// several entries at once.
///
/// What the table costs to show matters. Its cells show text, and become
/// date pickers, token fields and text fields when the pointer comes over
/// them, since those controls take long to make. With thousands of entries,
/// what each redraw costs matters too: the rows are built in one pass from
/// values the model keeps, and nothing here reads the clock, so the table
/// isn't rebuilt as time passes.
struct EntriesView: View {
    let model: AppModel
    @Environment(\.undoManager) private var undoManager
    @State private var selection: Set<UUID>
    @State private var sortOrder = [EntryOrder(column: .start, order: .reverse)]
    @State private var search = ""
    @State private var filter = EntriesFilter()
    @State private var sheet: EntriesSheet?
    /// Opens the CSV import.
    let imports: ImportActions?

    init(model: AppModel, selection: Set<UUID> = [], imports: ImportActions? = nil) {
        self.model = model
        self.imports = imports
        _selection = State(initialValue: selection)
    }

    var body: some View {
        let rows = self.rows
        VStack(spacing: 0) {
            if !model.resolved.isEmpty || filter.isActive {
                EntriesFilterBar(model: model, filter: $filter, rows: rows)
            }
            table(rows)
        }
        .searchable(text: $search, placement: .toolbar, prompt: "Notes, projects and tags")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: addEntry) {
                    Label("New Entry", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: .command)
                .help("Add an entry for the last hour")
                .disabled(model.isReadOnly)
                if let imports {
                    Menu {
                        Button("CSV File…", action: imports.csv)
                        Button("Calendar Events…", action: imports.calendar)
                    } label: {
                        Label("Import", systemImage: "square.and.arrow.down")
                    }
                    .help("Import entries from a CSV file or from calendars")
                    .disabled(model.isReadOnly)
                }
            }
        }
        .sheet(item: $sheet) { sheet in
            EntriesSheetView(model: model, sheet: sheet, undoManager: undoManager)
        }
    }

    private func table(_ rows: [EntryRow]) -> some View {
        let projectTags = model.projectTags
        return Table(rows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("", sortUsing: EntryOrder(column: .status)) { row in
                EntryStatusIcon(row: row)
            }
            .width(16)
            TableColumn("Start", sortUsing: EntryOrder(column: .start)) { row in
                EntryStartCell(model: model, row: row)
            }
            .width(min: 150, ideal: 170)
            TableColumn("End", sortUsing: EntryOrder(column: .end)) { row in
                EntryEndCell(model: model, row: row)
            }
            .width(min: 150, ideal: 170)
            TableColumn("Project", sortUsing: EntryOrder(column: .project)) { row in
                EntryProjectCell(model: model, row: row)
            }
            .width(min: 100, ideal: 180)
            TableColumn("Tags", sortUsing: EntryOrder(column: .tags)) { row in
                EditOnClick(enabled: !model.isReadOnly) {
                    TagList(tags: row.entry.entry.tags, interactive: false)
                } editor: { done in
                    TagField(
                        tags: row.entry.entry.tags,
                        suggestions: projectTags[row.entry.entry.projectID] ?? [],
                        placeholder: "",
                        bordered: false,
                        editsOnAppear: true,
                        endEditing: done
                    ) { tags in
                        model.updateEntries([row.id], actionName: "Change Tags", undoManager: undoManager) { $0.tags = tags }
                    }
                    .disabled(model.isReadOnly)
                }
            }
            .width(min: 60, ideal: 130)
            TableColumn("Note", sortUsing: EntryOrder(column: .note)) { row in
                EditOnHover(enabled: !model.isReadOnly) {
                    Text(row.note)
                        .lineLimit(1)
                } editor: {
                    CommitField(title: "", value: row.note) { note in
                        model.updateEntries([row.id], actionName: "Change Note", undoManager: undoManager) { $0.note = note }
                    }
                    .textFieldStyle(.plain)
                    .disabled(model.isReadOnly)
                }
            }
            .width(min: 100, ideal: 240)
        }
        .contextMenu(forSelectionType: UUID.self) { ids in
            EntriesMenu(model: model, ids: ids, undoManager: undoManager, sheet: $sheet) { copies in
                selection = copies
            }
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
            } else if rows.isEmpty {
                ContentUnavailableView {
                    Label("No Matching Entries", systemImage: "line.3.horizontal.decrease.circle")
                } description: {
                    Text(noMatches)
                } actions: {
                    Button("Show All Entries") {
                        filter = EntriesFilter()
                        search = ""
                    }
                }
            }
        }
    }

    private var noMatches: String {
        switch (filter.isActive, search.isEmpty) {
        case (true, false): "No entries match the filter and the search."
        case (true, true): "No entries match the filter."
        case (false, _): "No entries match the search."
        }
    }

    /// The rows the filter and search leave, in one pass over the entries,
    /// with each project's title worked out once.
    private var rows: [EntryRow] {
        let flagged = model.overlaps.flagged
        let ledger = model.ledger
        let overlapsOnly = filter.overlapsOnly
        let matches = filter.entryFilter.matcher(in: ledger)
        var titles: [UUID?: String] = [:]
        var rows: [EntryRow] = []
        for entry in model.resolved {
            let isFlagged = flagged.contains(entry.id)
            guard !overlapsOnly || isFlagged, matches(entry) else { continue }
            let projectID = entry.entry.projectID
            let title: String
            if let known = titles[projectID] {
                title = known
            } else {
                title = ledger.projectTitle(projectID)
                titles[projectID] = title
            }
            let row = EntryRow(entry, projectTitle: title, flagged: isFlagged)
            if row.matches(search) {
                rows.append(row)
            }
        }
        return EntryOrder.sort(rows, by: sortOrder)
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

/// The start, as a date and time in the entry's own time zone, with the
/// zone's name when it isn't the Mac's. It can't be after the end, or after
/// now for the running timer.
struct EntryStartCell: View {
    let model: AppModel
    let row: EntryRow
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        HStack(spacing: 4) {
            EditOnClick(enabled: !model.isReadOnly) {
                DateTimeText(time: row.start, zone: row.zone)
            } editor: { done in
                DateTimeField(
                    title: "Start",
                    date: row.start.date,
                    maximum: (row.entry.end ?? model.now).date,
                    timeZone: Zones.zone(row.zone),
                    editsOnAppear: true,
                    endEditing: done
                ) { date in
                    commit(Timestamp(date).wholeSeconds)
                }
                .disabled(model.isReadOnly)
            }
            .fixedSize(horizontal: true, vertical: false)
            if let label = row.zoneLabel {
                Text(label)
                    .foregroundStyle(.secondary)
                    .help("Recorded in \(row.zone)")
            }
        }
    }

    private func commit(_ start: Timestamp) {
        guard start != row.start else { return }
        if row.entry.isRunning {
            model.setRunningStart(start, undoManager: undoManager)
        } else {
            model.updateEntries([row.id], actionName: "Change Start", undoManager: undoManager) { $0.start = start }
        }
    }
}

/// The end, as a date and time in the entry's own time zone, which can't be
/// before the start. Its tooltip says how long the entry is.
struct EntryEndCell: View {
    let model: AppModel
    let row: EntryRow
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        if let end = row.entry.end {
            EditOnClick(enabled: !model.isReadOnly) {
                DateTimeText(time: end, zone: row.zone)
            } editor: { done in
                DateTimeField(
                    title: "End",
                    date: end.date,
                    minimum: row.start.date,
                    timeZone: Zones.zone(row.zone),
                    editsOnAppear: true,
                    endEditing: done
                ) { date in
                    commit(Timestamp(date).wholeSeconds, replacing: end)
                }
                .disabled(model.isReadOnly)
            }
            .help("Lasts \(Format.duration(row.start.distance(to: end)))")
        } else {
            Text("Running")
                .foregroundStyle(.secondary)
        }
    }

    private func commit(_ end: Timestamp, replacing current: Timestamp) {
        guard end != current else { return }
        model.updateEntries([row.id], actionName: "Change End", undoManager: undoManager) { $0.end = end }
    }
}

/// A date and time as the date field shows them, in a time zone, for
/// showing in its place until it's clicked.
struct DateTimeText: View {
    let time: Timestamp
    let zone: String

    var body: some View {
        Text(time.date, format: Date.FormatStyle(date: .numeric, time: .shortened, timeZone: Zones.zone(zone)))
            .lineLimit(1)
            // Where the date picker's text starts, inside its border.
            .padding(.leading, 4)
    }
}

/// The project, which opens the searchable project list.
struct EntryProjectCell: View {
    let model: AppModel
    let row: EntryRow
    @Environment(\.undoManager) private var undoManager
    @State private var choosing = false

    var body: some View {
        EditOnHover(enabled: !model.isReadOnly) {
            ProjectLabel(ledger: model.ledger, projectID: row.entry.entry.projectID)
        } editor: {
            chooser
        }
    }

    private var chooser: some View {
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

#Preview("Lots of Entries") {
    EntriesView(model: PreviewData.model(PreviewData.largeLedger))
        .frame(width: 1100, height: 700)
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
