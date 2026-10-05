#if os(macOS)
import AppKit
import SwiftUI
import TrackerCore
import TrackerKit
import UniformTypeIdentifiers

/// The main window: a bar with the zoom, the running timer and the command
/// line, over the day, week, month, year or projects.
struct MainWindow: View {
    let model: AppModel
    @SceneStorage("zoom") private var savedZoom = Zoom.week.rawValue
    @State private var navigator: Navigator
    @State private var line: CommandLineModel
    @State private var commandFocused = false
    @State private var focusRequest = 0
    @Environment(\.undoManager) private var undoManager
    @State private var importing = false
    @State private var importRequest: ImportRequest?
    @State private var importError: String?
    @State private var importingEvents = false

    init(model: AppModel, screen: Screen? = nil) {
        self.model = model
        _navigator = State(initialValue: Navigator(screen ?? .week(model.today)))
        _line = State(initialValue: CommandLineModel(model: model))
    }

    var body: some View {
        VStack(spacing: 0) {
            TopBar(
                model: model,
                navigator: navigator,
                line: line,
                commandFocused: $commandFocused,
                focusRequest: focusRequest
            )
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .overlay(alignment: .top) {
            if commandFocused, showsDropdown {
                CommandDropdown(line: line)
                    .padding(.top, 48)
                    .transition(.opacity)
            }
        }
        .background(Theme.background)
        .foregroundStyle(Theme.text)
        .frame(minWidth: 960, minHeight: 600)
        .background(WindowConfigurator())
        .background {
            // ⌘K puts the keyboard in the command line; ⌘[ and ⌘] go back
            // and forward.
            Group {
                Button("Command Line") { focusRequest += 1 }
                    .keyboardShortcut("k")
                Button("Back") { navigator.goBack() }
                    .keyboardShortcut("[")
                Button("Forward") { navigator.goForward() }
                    .keyboardShortcut("]")
            }
            .opacity(0)
            .accessibilityHidden(true)
        }
        .exportsEntries(of: model)
        .focusedSceneValue(\.imports, imports)
        .onAppear {
            if let zoom = Zoom(rawValue: savedZoom), zoom != navigator.screen.zoom {
                navigator.replace(Self.screen(for: zoom, today: model.today))
            }
        }
        .onChange(of: navigator.screen.zoom) { _, zoom in
            savedZoom = zoom.rawValue
        }
        .onChange(of: model.revision) {
            line.refresh()
        }
        .onChange(of: model.request, initial: true) { _, request in
            handle(request)
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.commaSeparatedText, .tabSeparatedText, .plainText]) { result in
            do {
                importRequest = try model.importRequest(forFileAt: result.get())
            } catch {
                importError = error.localizedDescription
            }
        }
        .sheet(item: $importRequest) { request in
            ImportSheet(model: model, request: request, undoManager: undoManager)
        }
        .sheet(isPresented: $importingEvents) {
            CalendarImportSheet(model: model, undoManager: undoManager)
        }
        .alert(
            "Couldn't Import the File",
            isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })
        ) {
            Button("OK") { importError = nil }
        } message: {
            Text(importError ?? "")
        }
    }

    private var showsDropdown: Bool {
        !line.text.isEmpty || line.showsToday || line.message != nil
    }

    @ViewBuilder
    private var content: some View {
        switch navigator.screen {
        case let .day(day):
            WeekScreen(model: model, navigator: navigator, anchor: day, span: .day)
        case let .week(day):
            WeekScreen(model: model, navigator: navigator, anchor: day, span: .week)
        case let .month(day):
            MonthScreen(model: model, navigator: navigator, anchor: day)
        case let .year(year):
            YearScreen(model: model, navigator: navigator, year: year)
        case .projects:
            ProjectsScreen(model: model, navigator: navigator)
        case let .project(id):
            ProjectScreen(model: model, navigator: navigator, projectID: id)
                .id(id)
        }
    }

    static func screen(for zoom: Zoom, today: LocalDate) -> Screen {
        switch zoom {
        case .day: .day(today)
        case .week: .week(today)
        case .month: .month(today)
        case .year: .year(today.year)
        case .projects: .projects
        }
    }

    private var imports: ImportActions {
        ImportActions {
            importing = true
        } calendar: {
            importingEvents = true
        }
    }

    /// Does what another window asked for, such as Settings' Import CSV….
    private func handle(_ request: AppRequest?) {
        guard let request else { return }
        switch request {
        case .importCSV:
            importing = true
        case .importEvents:
            importingEvents = true
        case .exportEntries:
            // EntriesExport takes this one.
            return
        case let .showWeek(day):
            navigator.go(.week(day))
        case let .showProject(id):
            navigator.go(.project(id))
        case let .command(text):
            line.text = text
            focusRequest += 1
        }
        model.request = nil
    }
}

/// The bar along the top: Back and Forward, the zoom, and the command
/// line with the running timer.
struct TopBar: View {
    let model: AppModel
    let navigator: Navigator
    let line: CommandLineModel
    @Binding var commandFocused: Bool
    let focusRequest: Int
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        HStack(spacing: 14) {
            // The window's buttons.
            Color.clear.frame(width: 62, height: 1)
            HStack(spacing: 2) {
                navigationButton("chevron.left", "Back", enabled: navigator.canGoBack) { navigator.goBack() }
                navigationButton("chevron.right", "Forward", enabled: navigator.canGoForward) { navigator.goForward() }
            }
            SegmentPicker(
                Zoom.allCases.map { (value: $0, title: $0.title) },
                selection: Binding(get: { navigator.screen.zoom }, set: { navigator.zoom($0, today: model.today) })
            )
            Spacer(minLength: 12)
            commandCapsule
                .frame(maxWidth: 560)
            Spacer(minLength: 12)
            Color.clear.frame(width: 60, height: 1)
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(Theme.bar)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.line).frame(height: 1)
        }
    }

    private func navigationButton(_ systemImage: String, _ title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(enabled ? Theme.text2 : Theme.text3.opacity(0.5))
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(title)
        .accessibilityLabel(Text(title))
    }

    /// The running timer and the command line, in one field.
    private var commandCapsule: some View {
        HStack(spacing: 10) {
            if let running = model.running {
                HStack(spacing: 7) {
                    Circle().fill(Theme.now).frame(width: 7, height: 7)
                    Text(Format.duration(model.duration(of: running)))
                        .fontWeight(.semibold)
                        .monospacedDigit()
                    TintDot(model.ledger.tint(ofProject: running.entry.projectID), size: 7)
                    Text(running.entry.projectID.flatMap { model.ledger.projects[$0]?.name } ?? "Unassigned")
                        .lineLimit(1)
                }
                .font(.system(size: 12.5))
                .fixedSize()
                .accessibilityElement(children: .combine)
                Rectangle().fill(Theme.strongLine).frame(width: 1, height: 16)
            }
            CommandField(
                text: Binding(get: { line.text }, set: { line.text = $0 }),
                placeholder: model.running == nil ? "› start, or log time" : "› type to switch, stop or log",
                reading: line.reading,
                ledger: model.ledger,
                fontSize: 12.5,
                focusRequest: focusRequest,
                onSubmit: { alternate in
                    if line.submit(alternate: alternate, undoManager: undoManager) {
                        finish()
                    }
                },
                onTab: { line.complete() },
                onUp: { line.previousLine() },
                onDown: { line.nextLine() },
                onCancel: {
                    line.clear()
                    finish()
                },
                onFocusChange: { focused in commandFocused = focused }
            )
            .frame(height: 20)
            KeyCap("⌘K")
            if model.running != nil {
                Button {
                    model.stopTimer(undoManager: undoManager)
                } label: {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Theme.text)
                        .frame(width: 9, height: 9)
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Stop the timer")
                .accessibilityLabel(Text("Stop the timer"))
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .frame(height: 34)
        .background(RoundedRectangle(cornerRadius: 9).fill(Theme.field))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(commandFocused ? Theme.accent : Theme.strongLine, lineWidth: commandFocused ? 1.5 : 1))
        .disabled(model.isReadOnly)
    }

    /// Leaves the command line, so keys go back to the screen.
    private func finish() {
        NSApp.keyWindow?.makeFirstResponder(nil)
        commandFocused = false
    }
}

/// What the line in the top bar would do, dropping down under it.
struct CommandDropdown: View {
    let line: CommandLineModel

    var body: some View {
        VStack(spacing: 0) {
            CommandPreviewView(line: line)
            if case .find? = line.reading.primary {
                EntryList(model: line.model, entries: Array(line.found.prefix(12)))
            } else if line.showsToday {
                EntryList(model: line.model, entries: Array(line.todaysEntries.prefix(12)))
            }
            if let completion = line.reading.completion {
                Divider().overlay(Theme.line)
                HStack {
                    KeyHint("⇥", "\(completion.text), from \(Format.weekday(completion.day))")
                    Spacer()
                }
                .padding(.horizontal, 14)
                .frame(height: 30)
            }
        }
        .frame(width: 560)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.popover))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.strongLine))
        .shadow(color: .black.opacity(0.25), radius: 20, y: 10)
    }
}

/// Lets the window be dragged by its background, since the title bar is
/// hidden behind the top bar.
struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            view.window?.isMovableByWindowBackground = true
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {}
}

#if DEBUG
#Preview("Week") {
    MainWindow(model: PreviewData.model(PreviewData.ownerLedger))
        .frame(width: 1280, height: 820)
}

#Preview("No Data") {
    MainWindow(model: PreviewData.model(Ledger()))
        .frame(width: 1280, height: 820)
}
#endif
#endif
