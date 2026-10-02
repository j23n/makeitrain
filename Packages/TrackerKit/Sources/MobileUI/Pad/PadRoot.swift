#if os(iOS)
import SwiftUI
import TrackerCore
import TrackerKit
import UniformTypeIdentifiers

/// What an iPad window shows: one of its screens, or the page of a client,
/// a project, or the entries without a project.
enum PadItem: Hashable {
    case timer, timeline, entries, reports, settings
    case client(UUID)
    case project(UUID)
    case unassigned

    /// The screens, in the sidebar's and the Go menu's order.
    static let screens: [PadItem] = [.timer, .timeline, .entries, .reports, .settings]

    /// How the window remembers it, such as "reports" or "project:" and the
    /// project's id.
    var key: String {
        switch self {
        case .timer: "timer"
        case .timeline: "timeline"
        case .entries: "entries"
        case .reports: "reports"
        case .settings: "settings"
        case .client(let id): "client:\(id.uuidString)"
        case .project(let id): "project:\(id.uuidString)"
        case .unassigned: "unassigned"
        }
    }

    /// The item a key stands for, or nil for one that's gone, such as the
    /// screens that projects' pages replaced.
    init?(key: String) {
        if let screen = Self.screens.first(where: { $0.key == key }) {
            self = screen
            return
        }
        if key == "unassigned" {
            self = .unassigned
            return
        }
        let parts = key.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, let id = UUID(uuidString: parts[1]) else { return nil }
        switch parts[0] {
        case "client": self = .client(id)
        case "project": self = .project(id)
        default: return nil
        }
    }

    /// A screen's name and symbol; nil for a page.
    var screen: (title: String, icon: String)? {
        switch self {
        case .timer: (title: "Timer", icon: "stopwatch")
        case .timeline: (title: "Timeline", icon: "calendar.day.timeline.left")
        case .entries: (title: "Entries", icon: "list.bullet.rectangle")
        case .reports: (title: "Reports", icon: "chart.bar.xaxis")
        case .settings: (title: "Settings", icon: "gear")
        case .client, .project, .unassigned: nil
        }
    }
}

/// A client or project to add, named in an alert.
enum PadNewRecord: Hashable {
    case client
    /// A project, for a client or none.
    case project(UUID?)
}

/// An iPad window: the screens, clients and projects in a sidebar, as on
/// the Mac, with the timer in each screen's toolbar, and the File menu's
/// imports and export. In a narrow window the sidebar is a list to pick
/// from.
struct PadRoot: View {
    let model: AppModel
    @SceneStorage("pad.screen") private var saved = "timeline"
    @State private var selection: PadItem?
    @Environment(\.undoManager) private var undoManager
    @State private var adding: PadNewRecord?
    @State private var newName = ""
    @State private var importing = false
    @State private var importRequest: ImportRequest?
    @State private var importError: String?
    @State private var importingEvents = false
    @State private var exportDocument: CSVDocument?
    @State private var exportName = ""
    @State private var exporting = false
    @State private var exportError: String?

    var body: some View {
        NavigationSplitView {
            PadSidebar(model: model, selection: $selection) { record in
                startAdding(record)
            }
            .navigationTitle("Time Tracker")
        } detail: {
            // The item last shown until the sidebar's selection is set, so
            // the window doesn't open empty. In a narrow window, the
            // selection alone decides whether the screen or the sidebar shows.
            let shown = selection ?? PadItem(key: saved) ?? .timeline
            NavigationStack {
                PadScreenView(model: model, item: shown, files: files) { item in
                    selection = item
                } add: { record in
                    startAdding(record)
                }
            }
            .id(shown)
            // Here rather than beside the import, so the two file dialogs
            // aren't on the same view.
            .fileExporter(
                isPresented: $exporting,
                document: exportDocument,
                contentType: .commaSeparatedText,
                defaultFilename: exportName
            ) { result in
                if case .failure(let error) = result {
                    exportError = error.localizedDescription
                }
            }
        }
        .focusedSceneValue(\.padFiles, files)
        .focusedSceneValue(\.padScreen, $selection)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.commaSeparatedText, .tabSeparatedText, .plainText]) { result in
            do {
                importRequest = try model.importRequest(forFileAt: result.get())
            } catch {
                importError = error.localizedDescription
            }
        }
        .sheet(item: $importRequest) { request in
            MobileImportSheet(model: model, request: request)
        }
        .sheet(isPresented: $importingEvents) {
            MobileCalendarImportSheet(model: model)
        }
        .alert(
            adding == .client ? "New Client" : "New Project",
            isPresented: Binding(get: { adding != nil }, set: { if !$0 { adding = nil } }),
            presenting: adding
        ) { record in
            TextField("Name", text: $newName)
            Button("Add") {
                add(record)
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Couldn't Import the File", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button("OK") { importError = nil }
        } message: {
            Text(importError ?? "")
        }
        .alert("Couldn't Export", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button("OK") { exportError = nil }
        } message: {
            Text(exportError ?? "")
        }
        .onAppear {
            if selection == nil {
                selection = PadItem(key: saved) ?? .timeline
            }
        }
        .onChange(of: selection) { _, newSelection in
            if let newSelection {
                saved = newSelection.key
            }
        }
    }

    private var files: PadFileActions {
        PadFileActions {
            importing = true
        } importEvents: {
            importingEvents = true
        } exportAll: {
            exportAll()
        }
    }

    /// Saves every finished entry, in the columns of a report's export.
    private func exportAll() {
        let entries = model.resolved.filter { !$0.isRunning }
        guard let name = CSVExport.fileName(for: entries) else { return }
        exportDocument = CSVDocument(data: CSVExport.data(for: entries, ledger: model.ledger))
        exportName = name
        exporting = true
    }

    private func startAdding(_ record: PadNewRecord) {
        newName = ""
        adding = record
    }

    /// Adds the client or project named, and shows its page.
    private func add(_ record: PadNewRecord) {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        switch record {
        case .client:
            selection = .client(model.addClient(named: name, undoManager: undoManager))
        case .project(let clientID):
            selection = .project(model.addProject(named: name, client: clientID, color: ProjectColors.next(in: model.ledger), undoManager: undoManager))
        }
    }
}

/// The iPad's sidebar: the timer, the timeline, the entries and the
/// reports; then each client with its projects under it, the projects
/// without a client and the entries without a project, each opening its
/// page; the archived clients and projects, folded away; and Settings. Its
/// toolbar's menu adds a client or a project.
struct PadSidebar: View {
    let model: AppModel
    @Binding var selection: PadItem?
    /// Asks for a new client's or project's name.
    let add: (PadNewRecord) -> Void
    @State private var showsArchived = false
    @ScaledMetric private var indent: CGFloat = 18

    var body: some View {
        let tree = ProjectTree(ledger: model.ledger)
        List(selection: $selection) {
            Section {
                ForEach(PadItem.screens.filter { $0 != .settings }, id: \.self) { item in
                    screenRow(item)
                }
            }
            Section("Projects") {
                ForEach(tree.clients) { branch in
                    clientRow(branch.client)
                    ForEach(branch.projects) { project in
                        projectRow(project, title: project.name)
                            .padding(.leading, indent)
                    }
                }
                ForEach(tree.unfiled) { project in
                    projectRow(project, title: project.name)
                }
                if model.resolved.contains(where: { $0.entry.projectID == nil }) {
                    Label {
                        Text("Unassigned")
                    } icon: {
                        ProjectDot(color: nil, size: 10)
                    }
                    .tag(PadItem.unassigned)
                }
                if tree.clients.isEmpty, tree.unfiled.isEmpty {
                    Button {
                        add(.project(nil))
                    } label: {
                        Label("New Project", systemImage: "plus")
                    }
                    .disabled(model.isReadOnly)
                }
            }
            if !tree.archivedClients.isEmpty || !tree.archivedProjects.isEmpty {
                Section {
                    DisclosureGroup(isExpanded: $showsArchived) {
                        ForEach(tree.archivedClients) { branch in
                            clientRow(branch.client)
                            ForEach(branch.projects) { project in
                                projectRow(project, title: project.name)
                                    .padding(.leading, indent)
                            }
                        }
                        ForEach(tree.archivedProjects) { project in
                            projectRow(project, title: model.ledger.projectTitle(project.id))
                        }
                    } label: {
                        Label("Archived", systemImage: "archivebox")
                    }
                }
            }
            Section {
                screenRow(.settings)
            }
            MobileNotices(model: model)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        add(.project(selectedClient))
                    } label: {
                        Label("New Project", systemImage: "folder.badge.plus")
                    }
                    Button {
                        add(.client)
                    } label: {
                        Label("New Client", systemImage: "briefcase")
                    }
                } label: {
                    Label("New", systemImage: "plus")
                }
                .disabled(model.isReadOnly)
                .help("Add a project or a client")
            }
        }
    }

    private func screenRow(_ item: PadItem) -> some View {
        Label(item.screen?.title ?? "", systemImage: item.screen?.icon ?? "")
            .tag(item)
    }

    private func clientRow(_ client: Client) -> some View {
        Label(client.name, systemImage: "briefcase")
            .tag(PadItem.client(client.id))
    }

    private func projectRow(_ project: Project, title: String) -> some View {
        Label {
            Text(title)
        } icon: {
            ProjectDot(color: Color(hex: project.color), size: 10)
        }
        .tag(PadItem.project(project.id))
    }

    /// The client a new project goes to: the one shown, or the shown
    /// project's.
    private var selectedClient: UUID? {
        switch selection {
        case .client(let id)?: id
        case .project(let id)?: model.ledger.projects[id]?.clientID
        default: nil
        }
    }
}

/// A screen or page in the iPad's detail column, with its title, and the
/// timer in its toolbar everywhere but on the Timer.
struct PadScreenView: View {
    let model: AppModel
    let item: PadItem
    let files: PadFileActions
    /// Shows another screen or page.
    let select: (PadItem) -> Void
    /// Asks for a new client's or project's name.
    let add: (PadNewRecord) -> Void
    @State private var adjusting: TimerAdjustment?

    var body: some View {
        content
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarRole(.editor)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    if item != .timer {
                        PadTimerControl(model: model, adjusting: $adjusting)
                    }
                }
            }
            .sheet(item: $adjusting) { adjustment in
                if let running = model.running {
                    AdjustTimeSheet(model: model, running: running, adjustment: adjustment)
                }
            }
    }

    /// The screen's name, or the client's or project's.
    private var title: String {
        switch item {
        case .client(let id): model.ledger.clients[id]?.name ?? "Client"
        case .project(let id): model.ledger.projects[id]?.name ?? "Project"
        case .unassigned: "Unassigned"
        default: item.screen?.title ?? ""
        }
    }

    @ViewBuilder
    private var content: some View {
        switch item {
        case .timer:
            TimerList(model: model, showsNotices: false)
        case .timeline:
            PadTimelineScreen(model: model)
        case .entries:
            PadEntriesScreen(model: model)
        case .reports:
            PadReportsScreen(model: model)
        case .settings:
            SettingsForm(model: model, showsProjects: false, exportAll: files.exportAll)
        case .client(let id):
            PadClientPage(model: model, clientID: id, select: select, add: add)
        case .project(let id):
            PadProjectPage(model: model, projectID: id, select: select)
        case .unassigned:
            PadProjectPage(model: model, projectID: nil, select: select)
        }
    }
}

// MARK: - Timer

/// The timer in an iPad screen's toolbar, as on the Mac: a button that
/// starts a timer, or the running timer and a button that stops it. Its
/// menu starts, or switches to, a recent project and tags; touch and hold
/// the start button for it.
struct PadTimerControl: View {
    let model: AppModel
    @Binding var adjusting: TimerAdjustment?
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        let recents = model.ledger.recentCombinations()
        Group {
            if let running = model.running {
                HStack(spacing: 14) {
                    Button {
                        model.stopTimer(undoManager: undoManager)
                    } label: {
                        Label("Stop Timer", systemImage: "stop.fill")
                    }
                    .tint(.red)
                    .help("Stop the timer")
                    Menu {
                        Section {
                            Button("Started Earlier…") {
                                adjusting = .start
                            }
                            Button("Stop at an Earlier Time…") {
                                adjusting = .stop
                            }
                        }
                        recentsSection(recents, title: "Switch To")
                    } label: {
                        PadRunningTimer(model: model, running: running)
                    }
                    .help("Switch to a recent project and tags, or change when the timer started")
                }
            } else {
                Menu {
                    recentsSection(recents, title: "Start")
                } label: {
                    Label("Start Timer", systemImage: "play.fill")
                        .labelStyle(.titleAndIcon)
                } primaryAction: {
                    model.startTimer(undoManager: undoManager)
                }
                .help("Start a timer without a project, or touch and hold for a recent project and tags")
            }
        }
        .disabled(model.isReadOnly)
    }

    @ViewBuilder
    private func recentsSection(_ recents: [Combination], title: String) -> some View {
        if !recents.isEmpty {
            Section(title) {
                ForEach(recents, id: \.self) { combination in
                    Button(self.title(of: combination)) {
                        model.startTimer(combination, undoManager: undoManager)
                    }
                    .disabled(model.running.map { combination.matches($0.entry) } ?? false)
                }
            }
        }
    }

    private func title(of combination: Combination) -> String {
        let project = model.ledger.projectTitle(combination.projectID)
        return combination.tags.isEmpty ? project : "\(project) · \(combination.tags.joined(separator: ", "))"
    }
}

/// The running timer's project and time so far.
private struct PadRunningTimer: View {
    let model: AppModel
    let running: ResolvedEntry

    var body: some View {
        HStack(spacing: 6) {
            ProjectDot(ledger: model.ledger, projectID: running.entry.projectID)
            Text(model.ledger.projectTitle(running.entry.projectID))
                .lineLimit(1)
                .frame(maxWidth: 220)
                .foregroundStyle(running.entry.projectID == nil ? .secondary : .primary)
            Text(Format.duration(model.duration(of: running)))
                .fontWeight(.semibold)
                .monospacedDigit()
        }
        .foregroundStyle(.primary)
    }
}

// MARK: - Inspector

/// The inspector of an iPad screen: a column beside the content, shown and
/// hidden with a toolbar button, or in a narrow window a sheet, open while
/// something is selected.
struct PadInspector<Inspector: View>: ViewModifier {
    @Binding var shown: Bool
    let hasSelection: Bool
    let clear: () -> Void
    let inspector: () -> Inspector
    @Environment(\.horizontalSizeClass) private var sizeClass

    func body(content: Content) -> some View {
        content.inspector(isPresented: presented) {
            inspector()
                .inspectorColumnWidth(min: 300, ideal: 340, max: 440)
        }
    }

    private var presented: Binding<Bool> {
        Binding(
            get: { sizeClass == .compact ? hasSelection : shown },
            set: { isShown in
                if sizeClass == .compact {
                    if !isShown {
                        clear()
                    }
                } else {
                    shown = isShown
                }
            }
        )
    }
}

extension View {
    /// Adds an iPad screen's inspector. `clear` clears the selection, when
    /// a narrow window's sheet is closed.
    func padInspector<Inspector: View>(
        shown: Binding<Bool>,
        hasSelection: Bool,
        clear: @escaping () -> Void,
        @ViewBuilder inspector: @escaping () -> Inspector
    ) -> some View {
        modifier(PadInspector(shown: shown, hasSelection: hasSelection, clear: clear, inspector: inspector))
    }
}

/// Shows or hides an iPad screen's inspector. A narrow window, where the
/// inspector is a sheet, has none.
struct PadInspectorButton: View {
    @Binding var shown: Bool
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        if sizeClass != .compact {
            Button {
                shown.toggle()
            } label: {
                Label(shown ? "Hide Inspector" : "Show Inspector", systemImage: "sidebar.right")
            }
            .help(shown ? "Hide the inspector" : "Show the inspector")
        }
    }
}

// MARK: - Commands

/// What the File menu does in the focused iPad window.
struct PadFileActions {
    /// Picks a CSV file to import.
    let importCSV: () -> Void
    /// Imports events from linked calendars.
    let importEvents: () -> Void
    /// Saves every finished entry as a CSV file.
    let exportAll: () -> Void

    init(importCSV: @escaping () -> Void, importEvents: @escaping () -> Void, exportAll: @escaping () -> Void) {
        self.importCSV = importCSV
        self.importEvents = importEvents
        self.exportAll = exportAll
    }
}

struct PadFileActionsKey: FocusedValueKey {
    typealias Value = PadFileActions
}

struct PadScreenKey: FocusedValueKey {
    typealias Value = Binding<PadItem?>
}

extension FocusedValues {
    /// The File menu's actions in the focused iPad window.
    var padFiles: PadFileActions? {
        get { self[PadFileActionsKey.self] }
        set { self[PadFileActionsKey.self] = newValue }
    }

    /// What the focused iPad window shows.
    var padScreen: Binding<PadItem?>? {
        get { self[PadScreenKey.self] }
        set { self[PadScreenKey.self] = newValue }
    }
}

/// The iPad's menu commands, in the menu bar and, with a keyboard, in the
/// list that holding Command shows: File › Import CSV…, Import Calendar
/// Events… and Export CSV…, and the screens under Go, with ⌘1 to ⌘5.
struct PadCommands: Commands {
    @FocusedValue(\.padFiles) private var files
    @FocusedBinding(\.padScreen) private var screen

    var body: some Commands {
        CommandGroup(after: .importExport) {
            Button("Import CSV…") {
                files?.importCSV()
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])
            .disabled(files == nil)
            Button("Import Calendar Events…") {
                files?.importEvents()
            }
            .disabled(files == nil)
            Button("Export CSV…") {
                files?.exportAll()
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .disabled(files == nil)
        }
        CommandMenu("Go") {
            ForEach(Array(PadItem.screens.enumerated()), id: \.element) { index, item in
                Button(item.screen?.title ?? "") {
                    screen = item
                }
                .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
            }
        }
    }
}

#if DEBUG
#Preview("iPad") {
    PadRoot(model: PreviewData.model())
}

#Preview("iPad, No Data") {
    PadRoot(model: PreviewData.model(Ledger()))
}

#Preview("iPad, a Freelancer's Data") {
    PadRoot(model: PreviewData.model(PreviewData.ownerLedger))
}

#Preview("Toolbar Timer") {
    NavigationStack {
        Text("Running")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    PadTimerControl(model: PreviewData.model(), adjusting: .constant(nil))
                }
            }
    }
}

#Preview("Toolbar Timer, Stopped") {
    NavigationStack {
        Text("Stopped")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    PadTimerControl(model: PreviewData.model(PreviewData.stoppedLedger), adjusting: .constant(nil))
                }
            }
    }
}
#endif
#endif
