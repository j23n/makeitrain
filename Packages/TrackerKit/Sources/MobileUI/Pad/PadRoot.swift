#if os(iOS)
import SwiftUI
import TrackerCore
import TrackerKit
import UniformTypeIdentifiers

/// The screens in the iPad's sidebar.
enum PadScreen: String, CaseIterable, Identifiable {
    case timer, timeline, entries, reports, projects, tags, settings

    var id: Self { self }

    var title: String {
        switch self {
        case .timer: "Timer"
        case .timeline: "Timeline"
        case .entries: "Entries"
        case .reports: "Reports"
        case .projects: "Clients & Projects"
        case .tags: "Tags"
        case .settings: "Settings"
        }
    }

    var icon: String {
        switch self {
        case .timer: "stopwatch"
        case .timeline: "calendar.day.timeline.left"
        case .entries: "list.bullet.rectangle"
        case .reports: "chart.bar.xaxis"
        case .projects: "folder"
        case .tags: "tag"
        case .settings: "gear"
        }
    }
}

/// An iPad window: the screens in a sidebar, as on the Mac, with the timer
/// in each screen's toolbar, and the File menu's imports and export. In a
/// narrow window the sidebar is a list to pick a screen from.
struct PadRoot: View {
    let model: AppModel
    @SceneStorage("pad.screen") private var savedScreen = PadScreen.timeline
    @State private var screen: PadScreen?
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
            List(selection: $screen) {
                Section {
                    ForEach(PadScreen.allCases.filter { $0 != .settings }) { item in
                        Label(item.title, systemImage: item.icon)
                            .tag(item)
                    }
                }
                Section {
                    Label(PadScreen.settings.title, systemImage: PadScreen.settings.icon)
                        .tag(PadScreen.settings)
                }
                MobileNotices(model: model)
            }
            .navigationTitle("Time Tracker")
        } detail: {
            // The screen last shown until the sidebar's selection is set, so
            // the window doesn't open empty. In a narrow window, the
            // selection alone decides whether the screen or the sidebar shows.
            let shown = screen ?? savedScreen
            NavigationStack {
                PadScreenView(model: model, screen: shown, files: files)
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
        .focusedSceneValue(\.padScreen, $screen)
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
            if screen == nil {
                screen = savedScreen
            }
        }
        .onChange(of: screen) { _, newScreen in
            if let newScreen {
                savedScreen = newScreen
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
}

/// A screen in the iPad's detail column, with its title, and the timer in
/// its toolbar on every screen but the Timer's.
struct PadScreenView: View {
    let model: AppModel
    let screen: PadScreen
    let files: PadFileActions
    @State private var adjusting: TimerAdjustment?

    var body: some View {
        content
            .navigationTitle(screen.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarRole(.editor)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    if screen != .timer {
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

    @ViewBuilder
    private var content: some View {
        switch screen {
        case .timer:
            TimerList(model: model, showsNotices: false)
        case .timeline:
            PadTimelineScreen(model: model)
        case .entries:
            PadEntriesScreen(model: model)
        case .reports:
            PadReportsScreen(model: model)
        case .projects:
            PadProjectsScreen(model: model)
        case .tags:
            PadTagsScreen(model: model)
        case .settings:
            SettingsForm(model: model, showsProjects: false, exportAll: files.exportAll)
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
            Circle()
                .fill(model.ledger.color(ofProject: running.entry.projectID))
                .frame(width: 8, height: 8)
            Text(model.ledger.projectTitle(running.entry.projectID))
                .lineLimit(1)
                .frame(maxWidth: 220)
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
    typealias Value = Binding<PadScreen?>
}

extension FocusedValues {
    /// The File menu's actions in the focused iPad window.
    var padFiles: PadFileActions? {
        get { self[PadFileActionsKey.self] }
        set { self[PadFileActionsKey.self] = newValue }
    }

    /// The screen the focused iPad window shows.
    var padScreen: Binding<PadScreen?>? {
        get { self[PadScreenKey.self] }
        set { self[PadScreenKey.self] = newValue }
    }
}

/// The iPad's menu commands, in the menu bar and, with a keyboard, in the
/// list that holding Command shows: File › Import CSV…, Import Calendar
/// Events… and Export CSV…, and the screens under Go, with ⌘1 to ⌘7.
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
            ForEach(Array(PadScreen.allCases.enumerated()), id: \.element) { index, item in
                Button(item.title) {
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
