import SwiftUI
import TrackerCore
import TrackerKit

/// A wide window, on the Mac or an iPad: a bar with the zoom, the running
/// timer and the command line, over the week, month, year or projects.
/// While the command line has the keyboard, what it would do shows under
/// it, as in the menu bar. The Mac's main window and the iPad's wide
/// windows wrap it in what each does on its own, such as importing.
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
            ScreenView(model: model, navigator: navigator)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .overlayPreferenceValue(CommandFieldBounds.self) { field in
            CommandDropdown(line: line, field: commandFocused ? field : nil, select: show)
        }
        .background(Theme.background)
        .foregroundStyle(Theme.text)
        .background {
            // ⌘K puts the keyboard in the command line. The View menu has
            // the zooms, Back and Forward.
            Button("Command Line") { focusRequest += 1 }
                .keyboardShortcut("k")
                .opacity(0)
                .accessibilityHidden(true)
        }
        .focusedSceneValue(\.wideNavigation, WideNavigation(
            canGoBack: navigator.canGoBack,
            canGoForward: navigator.canGoForward,
            show: { zoom in navigator.zoom(zoom, today: model.today) },
            goBack: { navigator.goBack() },
            goForward: { navigator.goForward() }
        ))
        .background(LineRefresh(model: model, line: line))
        .onAppear {
            let zoom = Zoom(saved: savedZoom)
            if zoom != navigator.screen.zoom {
                navigator.replace(zoom.screen(today: model.today))
            }
        }
        .onChange(of: navigator.screen.zoom) { _, zoom in
            savedZoom = zoom.rawValue
        }
        .onChange(of: model.request, initial: true) { _, request in
            handle(request)
        }
    }

    /// Runs the line, as Return does, or Option-Return with `alternate`,
    /// and leaves it when Settings says the command line closes after
    /// Return.
    private func submit(alternate: Bool) {
        if line.submitClosing(alternate: alternate, undoManager: undoManager) {
            finish()
        }
    }

    /// Clears the line, as Escape does, or leaves it with nothing typed.
    private func cancel() {
        if line.cancel() {
            finish()
        }
    }

    /// Shows an entry on its week, selected.
    private func show(_ entry: ResolvedEntry) {
        navigator.go(.week(entry.entry.day))
        navigator.entryToSelect = entry.id
        line.clear()
        finish()
    }

    /// Leaves the command line, so keys go back to the screen.
    private func finish() {
        endTextEditing()
        commandFocused = false
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

/// Where the top bar's command line is, for what it would do to show under
/// it.
struct CommandFieldBounds: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

/// What the main window's command line would do, under it, as the menu
/// bar's popover shows it under its line: the suggestions, what Return
/// would do, the entries found or today's, and the keys. Clicking an entry
/// shows it on its week.
private struct CommandDropdown: View {
    let line: CommandLineModel
    /// Where the field is, or nil while it doesn't have the keyboard.
    let field: Anchor<CGRect>?
    let select: (ResolvedEntry) -> Void

    /// As wide as the menu bar's popover, at least.
    private static let minimumWidth: CGFloat = 410

    var body: some View {
        if let field {
            GeometryReader { geometry in
                let bounds = geometry[field]
                let width = max(bounds.width, Self.minimumWidth)
                // Centered under the field, inside the window.
                let x = min(max(bounds.midX - width / 2, 8), max(geometry.size.width - width - 8, 8))
                CommandDetails(line: line, continuesField: false, select: select)
                    .frame(width: width)
                    .background(Theme.popover)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.strongLine))
                    .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
                    .fixedSize(horizontal: false, vertical: true)
                    .offset(x: x, y: bounds.maxY + 6)
                    .disabled(line.model.isReadOnly)
            }
        }
    }
}

/// The screen the window shows. It's a view of its own, so the window's
/// redraws, as for the command line, leave it alone instead of building
/// the screen and its model again.
private struct ScreenView: View {
    let model: AppModel
    let navigator: Navigator

    var body: some View {
        switch navigator.screen {
        case let .week(day):
            WeekScreen(model: model, navigator: navigator, anchor: day)
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
}

/// Reads the command line again when the data changes. It's a view of its
/// own, so a change doesn't redraw the whole window.
private struct LineRefresh: View {
    let model: AppModel
    let line: CommandLineModel

    var body: some View {
        Color.clear
            .onChange(of: model.revision) {
                line.refresh()
            }
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
    /// Clears the line, or leaves it with nothing typed.
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
                RunningTimerLabel(model: model, running: running)
                    .font(.system(size: 12.5))
                    .fixedSize()
                    .accessibilityElement(children: .combine)
                Rectangle().fill(Theme.strongLine).frame(width: 1, height: 16)
            }
            CommandField(
                line: line,
                placeholder: CommandText.placeholder,
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
        .anchorPreference(key: CommandFieldBounds.self, value: .bounds) { $0 }
        .disabled(model.isReadOnly)
    }
}
