import SwiftUI
import TrackerCore
import TrackerKit

/// A wide window, on the Mac or an iPad: a bar with the zoom, the running
/// timer and the command line, over the day, week, month, year or
/// projects, and while the command line is used, a sidebar with what it
/// would do. The Mac's main window and the iPad's wide windows wrap it in
/// what each does on its own, such as importing.
public struct WideRoot<Trailing: View>: View {
    let model: AppModel
    /// Room at the start of the bar, as for the Mac's window buttons.
    let leadingInset: CGFloat
    /// What goes at the end of the bar, such as Settings on iPad.
    let trailing: Trailing
    @SceneStorage("zoom") private var savedZoom = Zoom.week.rawValue
    @State private var navigator: Navigator
    @State private var line: CommandLineModel
    @State private var commandFocused = false
    @State private var focusRequest = 0
    @Environment(\.undoManager) private var undoManager

    public init(model: AppModel, leadingInset: CGFloat = 0, @ViewBuilder trailing: () -> Trailing) {
        self.model = model
        self.leadingInset = leadingInset
        self.trailing = trailing()
        _navigator = State(initialValue: Navigator(.week(model.today)))
        _line = State(initialValue: CommandLineModel(model: model))
    }

    public var body: some View {
        VStack(spacing: 0) {
            TopBar(
                model: model,
                navigator: navigator,
                line: line,
                commandFocused: $commandFocused,
                focusRequest: focusRequest,
                leadingInset: leadingInset,
                trailing: trailing,
                submit: { submit(alternate: $0) },
                cancel: cancel
            )
            HStack(spacing: 0) {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .environment(\.commandSidebarShown, showsCommandSidebar)
                if showsCommandSidebar {
                    CommandSidebar(
                        line: line,
                        submit: { submit(alternate: $0) },
                        focus: { focusRequest += 1 },
                        close: cancel,
                        show: { show($0) }
                    )
                    .transition(.move(edge: .trailing))
                }
            }
            .animation(.easeOut(duration: 0.15), value: showsCommandSidebar)
        }
        .background(Theme.background)
        .foregroundStyle(Theme.text)
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
        .onAppear {
            if let zoom = Zoom(rawValue: savedZoom), zoom != navigator.screen.zoom {
                navigator.replace(zoom.screen(today: model.today))
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
    }

    /// Whether the sidebar shows the command line: while it has the
    /// keyboard, a line, today's entries or what went wrong.
    private var showsCommandSidebar: Bool {
        commandFocused || !line.text.isEmpty || line.showsToday || line.message != nil
    }

    /// Runs the line, as Return does, or Option-Return with `alternate`.
    private func submit(alternate: Bool) {
        if line.submit(alternate: alternate, undoManager: undoManager) {
            finish()
        }
    }

    /// Clears the line and leaves it, as Escape does.
    private func cancel() {
        line.clear()
        finish()
    }

    /// Shows an entry on its week, or its day when a day is shown, selected.
    private func show(_ entry: ResolvedEntry) {
        let day = entry.entry.day
        navigator.go(navigator.screen.zoom == .day ? .day(day) : .week(day))
        navigator.entryToSelect = entry.id
        cancel()
    }

    /// Leaves the command line, so keys go back to the screen.
    private func finish() {
        endTextEditing()
        commandFocused = false
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

    /// Does what another part of the app asked for, such as the projects'
    /// New. Importing and exporting are left to the window around it.
    private func handle(_ request: AppRequest?) {
        guard case let .command(text)? = request else { return }
        line.text = text
        focusRequest += 1
        model.request = nil
    }
}

extension WideRoot where Trailing == EmptyView {
    public init(model: AppModel, leadingInset: CGFloat = 0) {
        self.init(model: model, leadingInset: leadingInset) { EmptyView() }
    }
}

/// The bar along the top: Back and Forward, the zoom, and the command
/// line with the running timer.
struct TopBar<Trailing: View>: View {
    let model: AppModel
    let navigator: Navigator
    let line: CommandLineModel
    @Binding var commandFocused: Bool
    let focusRequest: Int
    let leadingInset: CGFloat
    let trailing: Trailing
    /// Runs the line, or with `alternate` what it could also mean.
    let submit: (_ alternate: Bool) -> Void
    /// Clears the line and leaves it.
    let cancel: () -> Void
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        HStack(spacing: 14) {
            if leadingInset > 0 {
                Color.clear.frame(width: leadingInset, height: 1)
            }
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
            trailing
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
                line: line,
                placeholder: model.running == nil ? "› start a timer or log time" : "› switch, stop or log time",
                fontSize: 12.5,
                focusRequest: focusRequest,
                onSubmit: submit,
                onCancel: cancel,
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
}
