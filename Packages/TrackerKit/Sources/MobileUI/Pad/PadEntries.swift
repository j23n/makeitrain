#if os(iOS)
import SwiftUI
import TrackerCore
import TrackerKit

/// Every entry on iPad, by day, newest first. The bar above narrows the
/// list to a period, clients and projects, tags or overlaps, as on the Mac,
/// and the search field to a note, project or tag. Tap an entry to edit it
/// in the inspector; touch and hold one to duplicate, split or delete it,
/// fix an overlap, or change its project and tags.
struct PadEntriesScreen: View {
    let model: AppModel
    @Environment(\.undoManager) private var undoManager
    @State private var selection: UUID?
    @State private var search = ""
    @State private var filter = EntriesFilter()
    @State private var sheet: EntriesSheet?
    @AppStorage("entries.inspector") private var showInspector = true

    struct Day: Identifiable {
        var day: LocalDate
        var entries: [ResolvedEntry]

        var id: LocalDate { day }
    }

    init(model: AppModel, selection: UUID? = nil) {
        self.model = model
        _selection = State(initialValue: selection)
    }

    var body: some View {
        let entries = self.entries
        let flagged = model.overlaps.flagged
        List(selection: $selection) {
            ForEach(Self.days(of: entries)) { day in
                Section {
                    ForEach(day.entries) { entry in
                        MobileEntryRow(model: model, entry: entry, flagged: flagged.contains(entry.id))
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
        .safeAreaInset(edge: .top, spacing: 0) {
            if !model.resolved.isEmpty || filter.isActive {
                PadEntriesFilterBar(model: model, filter: $filter, entries: entries)
            }
        }
        .overlay {
            if model.resolved.isEmpty {
                ContentUnavailableView(
                    "No Entries",
                    systemImage: "clock",
                    description: Text("Start a timer, or add an entry with the + button.")
                )
            } else if entries.isEmpty {
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
        .searchable(text: $search, prompt: "Notes, projects and tags")
        .contextMenu(forSelectionType: UUID.self) { ids in
            EntriesMenu(model: model, ids: ids, undoManager: undoManager, sheet: $sheet) { copies in
                selection = copies.first
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: addEntry) {
                    Label("New Entry", systemImage: "plus")
                }
                .help("Add an entry for the last hour")
                .disabled(model.isReadOnly)
                PadInspectorButton(shown: $showInspector)
            }
        }
        .padInspector(shown: $showInspector, hasSelection: selection != nil) {
            selection = nil
        } inspector: {
            NavigationStack {
                if let id = selection, model.resolved.contains(where: { $0.id == id }) {
                    EntryForm(model: model, id: id, select: { copy in
                        selection = copy
                    }, deleted: {
                        selection = nil
                    })
                    .id(id)
                } else {
                    PeriodSummary(
                        title: summaryTitle,
                        entries: entries,
                        ledger: model.ledger,
                        now: model.now,
                        hint: "Tap an entry to edit it."
                    )
                }
            }
        }
        .sheet(item: $sheet) { sheet in
            EntriesSheetView(model: model, sheet: sheet)
        }
        .onChange(of: selection) { _, newSelection in
            if newSelection != nil {
                showInspector = true
            }
        }
    }

    /// What the entries shown are, for the inspector's summary of them,
    /// such as "This Week" or "Sep 2 – 5, 2026, Filtered".
    private var summaryTitle: String {
        let days = filter.period == .custom ? filter.range.map(Format.days) ?? filter.period.title : filter.period.title
        let narrowed = !filter.clients.isEmpty || !filter.projects.isEmpty || !filter.tags.isEmpty || filter.overlapsOnly || !search.isEmpty
        return narrowed ? "\(days), Filtered" : days
    }

    private var noMatches: String {
        switch (filter.isActive, search.isEmpty) {
        case (true, false): "No entries match the filter and the search."
        case (true, true): "No entries match the filter."
        case (false, _): "No entries match the search."
        }
    }

    /// The entries the filter and search leave, by start, in one pass with
    /// each project's title worked out once.
    private var entries: [ResolvedEntry] {
        let flagged = model.overlaps.flagged
        let ledger = model.ledger
        let overlapsOnly = filter.overlapsOnly
        let matches = filter.entryFilter.matcher(in: ledger)
        var titles: [UUID?: String] = [:]
        var result: [ResolvedEntry] = []
        for entry in model.resolved {
            guard !overlapsOnly || flagged.contains(entry.id), matches(entry) else { continue }
            if !search.isEmpty {
                let projectID = entry.entry.projectID
                let title: String
                if let known = titles[projectID] {
                    title = known
                } else {
                    title = ledger.projectTitle(projectID)
                    titles[projectID] = title
                }
                guard entry.entry.note.localizedCaseInsensitiveContains(search)
                    || title.localizedCaseInsensitiveContains(search)
                    || entry.entry.tags.contains(where: { $0.localizedCaseInsensitiveContains(search) })
                else { continue }
            }
            result.append(entry)
        }
        return result
    }

    /// Entries by the day they start on, the newest day first, and each
    /// day's newest entry first.
    static func days(of entries: [ResolvedEntry]) -> [Day] {
        var byDay: [LocalDate: [ResolvedEntry]] = [:]
        for entry in entries {
            byDay[entry.entry.day, default: []].append(entry)
        }
        return byDay
            .map { day, entries in Day(day: day, entries: entries.reversed()) }
            .sorted { $0.day > $1.day }
    }

    private func addEntry() {
        let end = model.environment.now().wholeSeconds
        let entry = TimeEntry(start: end.adding(seconds: -3600), end: end, timeZone: model.environment.timeZone(), updated: end)
        model.addEntry(entry, undoManager: undoManager)
        selection = entry.id
    }
}

/// The bar over the iPad's entries list: the period, the clients and
/// projects, the tags and the overlaps shown, how many entries that leaves
/// and their time, and a button that clears it all.
struct PadEntriesFilterBar: View {
    let model: AppModel
    @Binding var filter: EntriesFilter
    /// The entries the filter and search leave.
    let entries: [ResolvedEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        periodMenu
                        projectsMenu
                        tagsMenu
                        overlapsToggle
                    }
                }
                PadEntriesSummary(model: model, entries: entries)
                if filter.isActive {
                    Button("Clear") {
                        filter = EntriesFilter()
                    }
                    .help("Show every entry")
                }
            }
            if filter.period == .custom, let range = filter.range {
                HStack(spacing: 8) {
                    DatePicker("From", selection: fromBinding(range), displayedComponents: .date)
                        .labelsHidden()
                    Text("to")
                        .foregroundStyle(.secondary)
                    DatePicker("To", selection: toBinding(range), displayedComponents: .date)
                        .labelsHidden()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
        .overlay(alignment: .bottom) {
            Divider()
        }
        .onChange(of: model.today) { _, today in
            filter.refresh(today: today, firstWeekday: model.firstWeekday)
        }
        .onChange(of: model.firstWeekday) { _, firstWeekday in
            filter.refresh(today: model.today, firstWeekday: firstWeekday)
        }
    }

    // MARK: Period

    private var periodMenu: some View {
        Menu {
            Section {
                periodToggle(.all)
            }
            Section {
                ForEach([EntriesPeriod.today, .thisWeek, .lastWeek, .thisMonth, .lastMonth, .thisYear], id: \.self) { period in
                    periodToggle(period)
                }
            }
            Section {
                periodToggle(.custom)
            }
        } label: {
            FilterChip(title: filter.period.title, active: filter.period != .all)
        }
        .help("Show the entries of a day, week, month or year")
    }

    private func periodToggle(_ period: EntriesPeriod) -> some View {
        Toggle(period.title, isOn: Binding(
            get: { filter.period == period },
            set: { on in
                if on {
                    filter.choose(period, today: model.today, firstWeekday: model.firstWeekday)
                }
            }
        ))
    }

    private func fromBinding(_ range: ClosedRange<LocalDate>) -> Binding<Date> {
        Binding(
            get: { range.lowerBound.pickerDate },
            set: { date in
                let from = LocalDate(pickerDate: date)
                filter.range = from...max(from, range.upperBound)
            }
        )
    }

    private func toBinding(_ range: ClosedRange<LocalDate>) -> Binding<Date> {
        Binding(
            get: { range.upperBound.pickerDate },
            set: { date in
                let to = LocalDate(pickerDate: date)
                filter.range = min(to, range.lowerBound)...to
            }
        )
    }

    // MARK: Clients and projects

    private var projectsMenu: some View {
        Menu {
            Section("Clients") {
                Toggle("No client", isOn: member(nil, of: $filter.clients))
                ForEach(model.ledger.liveClients()) { client in
                    Toggle(client.name, isOn: member(client.id, of: $filter.clients))
                }
            }
            Section("Projects") {
                Toggle("Unassigned", isOn: member(nil, of: $filter.projects))
                ForEach(projects) { project in
                    Toggle(model.ledger.projectTitle(project.id), isOn: member(project.id, of: $filter.projects))
                }
            }
        } label: {
            FilterChip(title: projectsTitle, active: !filter.clients.isEmpty || !filter.projects.isEmpty)
        }
        .help("Show only some clients' and projects' entries")
    }

    /// Projects that aren't deleted, archived ones included, since the list
    /// covers the past.
    private var projects: [Project] {
        model.ledger.projects.values
            .filter { !$0.isDeleted }
            .sorted { model.ledger.projectTitle($0.id).lowercased() < model.ledger.projectTitle($1.id).lowercased() }
    }

    private var projectsTitle: String {
        switch (filter.clients.count, filter.projects.count) {
        case (0, 0):
            return "All Projects"
        case (1, 0):
            guard let chosen = filter.clients.first, let clientID = chosen else { return "No client" }
            return model.ledger.clients[clientID]?.name ?? "Unknown client"
        case (0, 1):
            return filter.projects.first.map { model.ledger.projectTitle($0) } ?? ""
        case (let count, 0):
            return "\(count) Clients"
        case (0, let count):
            return "\(count) Projects"
        case (let clientCount, let projectCount):
            return "\(clientCount + projectCount) Clients and Projects"
        }
    }

    // MARK: Tags and overlaps

    private var tagsMenu: some View {
        Menu {
            let offered = offeredTags
            if offered.isEmpty {
                Text("No Tags")
            }
            ForEach(offered, id: \.self) { tag in
                Toggle(tag, isOn: Binding(
                    get: { filter.tags.contains(tag) },
                    set: { on in
                        if on {
                            filter.tags.insert(tag)
                        } else {
                            filter.tags.remove(tag)
                        }
                    }
                ))
            }
        } label: {
            FilterChip(title: tagsTitle, active: !filter.tags.isEmpty)
        }
        .help("Show only entries with some tags")
    }

    /// The tags of the projects chosen, or of every project, and the tags
    /// chosen already, once each, ignoring case.
    private var offeredTags: [String] {
        let byProject = model.projectTags
        let lists = filter.projects.isEmpty ? Array(byProject.values) : filter.projects.compactMap { byProject[$0] }
        var seen: Set<String> = []
        var result: [String] = []
        for tag in lists.joined() where seen.insert(tag.lowercased()).inserted {
            result.append(tag)
        }
        for tag in filter.tags where seen.insert(tag.lowercased()).inserted {
            result.append(tag)
        }
        return result.sorted(by: Tags.order)
    }

    private var tagsTitle: String {
        switch filter.tags.count {
        case 0: "All Tags"
        case 1: filter.tags.first ?? ""
        case let count: "\(count) Tags"
        }
    }

    private var overlapsToggle: some View {
        Button {
            filter.overlapsOnly.toggle()
        } label: {
            FilterChip(title: "Overlaps", systemImage: "exclamationmark.triangle", active: filter.overlapsOnly, showsMenu: false)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(filter.overlapsOnly ? .isSelected : [])
        .help("Show only entries that overlap another")
    }

    private func member(_ id: UUID?, of set: Binding<Set<UUID?>>) -> Binding<Bool> {
        Binding(
            get: { set.wrappedValue.contains(id) },
            set: { on in
                if on {
                    set.wrappedValue.insert(id)
                } else {
                    set.wrappedValue.remove(id)
                }
            }
        )
    }
}

/// One of the filters over the entries list, as a capsule: tinted while
/// it narrows the list, with a chevron when it opens a menu.
struct FilterChip: View {
    let title: String
    var systemImage: String? = nil
    let active: Bool
    var showsMenu = true

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: systemImage)
            }
            Text(title)
                .lineLimit(1)
            if showsMenu {
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
            }
        }
        .font(.subheadline.weight(.medium))
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .foregroundStyle(active ? Color.accentColor : Color.primary)
        .background(
            Capsule().fill(active ? Color.accentColor.opacity(0.15) : Color(uiColor: .tertiarySystemFill))
        )
        .contentShape(Capsule())
    }
}

/// How many entries the list shows and their time. Only a running timer's
/// time follows the clock.
struct PadEntriesSummary: View {
    let model: AppModel
    let entries: [ResolvedEntry]

    var body: some View {
        let total = entries.reduce(Int64(0)) { sum, entry in
            sum + (entry.end.map { max(0, entry.start.distance(to: $0)) } ?? model.duration(of: entry))
        }
        HStack(spacing: 6) {
            Text(entries.count == 1 ? "1 entry" : "\(entries.count.formatted()) entries")
                .foregroundStyle(.secondary)
            Text(Format.duration(total))
                .fontWeight(.semibold)
        }
        .font(.subheadline)
        .monospacedDigit()
        .lineLimit(1)
        .fixedSize()
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview("Entries") {
    NavigationStack {
        PadEntriesScreen(model: PreviewData.model(), selection: PreviewData.entry("Wireframe review, round 2"))
            .navigationTitle("Entries")
            .navigationBarTitleDisplayMode(.inline)
    }
    .defaultAppStorage(UserDefaults(suiteName: "PadEntriesPreview")!)
}

#Preview("No Entries") {
    NavigationStack {
        PadEntriesScreen(model: PreviewData.model(Ledger()))
            .navigationTitle("Entries")
            .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview("Filter Bar") {
    let model = PreviewData.model()
    return VStack(spacing: 0) {
        PadEntriesFilterBar(model: model, filter: .constant(EntriesFilter()), entries: model.resolved)
        PadEntriesFilterBar(
            model: model,
            filter: .constant(EntriesFilter(period: .custom, range: model.today.adding(days: -6)...model.today, tags: ["design"], overlapsOnly: true)),
            entries: []
        )
        Spacer()
    }
}
#endif
#endif
