#if os(macOS)
import AppKit
import SwiftUI
import TrackerCore
import TrackerKit

/// The timer in the main window's toolbar, in the middle of the space
/// between the title and the next item.
///
/// The toolbar centers its principal item in the part beside the sidebar,
/// which puts it off the middle of the free space whenever the items on one
/// side take more room than the title on the other, as the entries screen's
/// three buttons do. Padding on the far side moves it by the difference, as
/// far as that keeps it clear of both.
struct ToolbarTimer: View {
    let model: AppModel
    @State private var shift: CGFloat = 0

    var body: some View {
        TimerCapsule(model: model)
            .fixedSize()
            .background {
                ToolbarGapReader { newShift in
                    shift = newShift
                }
            }
            .padding(.leading, max(0, 2 * shift))
            .padding(.trailing, max(0, -2 * shift))
    }

    /// How far to move content `width` wide, in an item the toolbar centers
    /// on `itemCenter`, to the middle of the space from `left` to `right`.
    ///
    /// Padding on the far side moves it, which widens the item by twice as
    /// much, evenly around its center. It moves only as far as the widened
    /// item stays `margin` clear of both ends, since the toolbar would
    /// otherwise move the item itself.
    static func shift(itemCenter: CGFloat, width: CGFloat, left: CGFloat, right: CGFloat, margin: CGFloat = 8) -> CGFloat {
        let wanted = (left + right) / 2 - itemCenter
        let limit = max(0, min(itemCenter - width / 2 - left, right - itemCenter - width / 2) - margin)
        return min(max(wanted, -limit), limit).rounded()
    }
}

/// Reports how far to move the toolbar item it's in to the middle of the
/// space between the title and the next item, from the frames of the
/// toolbar's views: the window title's text field, the item's neighbors in
/// the row the title shares with the items, and the controls and SwiftUI
/// views in them. It reports no move if it can't find them.
///
/// It measures again after every event the window handles, as when the
/// sidebar or the window is resized or the search field opens, and when
/// the toolbar's items change.
private struct ToolbarGapReader: NSViewRepresentable {
    let report: (CGFloat) -> Void

    func makeNSView(context: Context) -> GapReaderView {
        let view = GapReaderView()
        view.report = report
        return view
    }

    func updateNSView(_ view: GapReaderView, context: Context) {
        view.report = report
        view.scheduleMeasuring()
    }
}

private final class GapReaderView: NSView {
    var report: ((CGFloat) -> Void)?
    private var reported: CGFloat = 0

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        let center = NotificationCenter.default
        center.removeObserver(self)
        NSObject.cancelPreviousPerformRequests(withTarget: self)
        guard let window else { return }
        center.addObserver(self, selector: #selector(scheduleMeasuring), name: NSWindow.didUpdateNotification, object: window)
        center.addObserver(self, selector: #selector(scheduleMeasuring), name: NSWindow.didResizeNotification, object: window)
        if let toolbar = window.toolbar {
            center.addObserver(self, selector: #selector(scheduleMeasuring), name: NSToolbar.willAddItemNotification, object: toolbar)
            center.addObserver(self, selector: #selector(scheduleMeasuring), name: NSToolbar.didRemoveItemNotification, object: toolbar)
        }
        scheduleMeasuring()
    }

    /// Measures once the toolbar has laid out what's changed, on the next
    /// turn of the run loop, also while the window is being resized.
    @objc func scheduleMeasuring() {
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(measure), object: nil)
        perform(#selector(measure), with: nil, afterDelay: 0, inModes: [.common])
    }

    @objc private func measure() {
        guard let window, !window.title.isEmpty, let found = place(title: window.title) else {
            send(0)
            return
        }
        let itemFrame = found.item.convert(found.item.bounds, to: nil)
        guard itemFrame.width < window.frame.width * 0.7 else {
            send(0)
            return
        }
        var left: CGFloat?
        var right: CGFloat?
        for neighbor in found.row.subviews where neighbor !== found.item && !neighbor.isHidden {
            for frame in Self.contentFrames(in: neighbor) {
                if frame.maxX <= itemFrame.minX + 1 {
                    left = max(left ?? frame.maxX, frame.maxX)
                } else if frame.minX >= itemFrame.maxX - 1 {
                    right = min(right ?? frame.minX, frame.minX)
                }
            }
        }
        guard let left else {
            send(0)
            return
        }
        let end = right ?? found.row.convert(found.row.bounds, to: nil).maxX
        let width = convert(bounds, to: nil).width
        send(ToolbarTimer.shift(itemCenter: itemFrame.midX, width: width, left: left, right: end))
    }

    private func send(_ shift: CGFloat) {
        guard abs(shift - reported) >= 1 else { return }
        reported = shift
        report?(shift)
    }

    /// The toolbar item this view is in, and the row it shares with the title.
    private struct Place {
        let item: NSView
        let row: NSView
    }

    /// The item is the ancestor beside the title.
    private func place(title: String) -> Place? {
        var view: NSView = self
        while let parent = view.superview {
            if parent.subviews.contains(where: { $0 !== view && Self.shows(title: title, in: $0) }) {
                return Place(item: view, row: parent)
            }
            view = parent
        }
        return nil
    }

    private static func shows(title: String, in view: NSView) -> Bool {
        if let field = view as? NSTextField, field.stringValue == title {
            return true
        }
        return view.subviews.contains { shows(title: title, in: $0) }
    }

    /// Where the visible controls and SwiftUI views in `view` are, in window
    /// coordinates. Spaces between items have neither.
    private static func contentFrames(in view: NSView) -> [CGRect] {
        guard !view.isHidden, view.alphaValue > 0.01 else { return [] }
        var frames: [CGRect] = []
        let name = String(describing: type(of: view))
        if view is NSControl || name.contains("HostingView") {
            let frame = view.convert(view.bounds, to: nil)
            if frame.width >= 12 {
                frames.append(frame)
            }
        }
        for subview in view.subviews {
            frames += contentFrames(in: subview)
        }
        return frames
    }
}

/// A capsule with a round button to start a timer, or with the running
/// timer and a round button to stop it, and a menu of recent projects and
/// tags to start or switch to.
struct TimerCapsule: View {
    let model: AppModel
    @Environment(\.undoManager) private var undoManager

    /// Whether toolbar items sit on glass, as on macOS 26 and later when
    /// built with its SDK.
    static var toolbarIsGlass: Bool {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            return true
        }
        #endif
        return false
    }

    /// As tall as the toolbar's other items.
    static let height: CGFloat = toolbarIsGlass ? 36 : 28
    /// Around the round button, between it and the capsule's edge.
    static let inset: CGFloat = toolbarIsGlass ? 4 : 3

    var body: some View {
        let recents = model.ledger.recentCombinations()
        HStack(spacing: 0) {
            if let running = model.running {
                Button {
                    model.stopTimer(undoManager: undoManager)
                } label: {
                    TimerGlyph(title: "Stop Timer", systemImage: "stop.fill", color: .red)
                }
                .buttonStyle(TimerButtonStyle())
                .help("Stop the timer")
                RunningTimerSummary(model: model, running: running)
                    .padding(.leading, 8)
            } else {
                Button {
                    model.startTimer(undoManager: undoManager)
                } label: {
                    HStack(spacing: 8) {
                        TimerGlyph(title: "Start Timer", systemImage: "play.fill", color: .accentColor)
                        Text("Start Timer")
                            .fontWeight(.medium)
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(TimerButtonStyle())
                .help("Start a timer without a project")
            }
            if !recents.isEmpty {
                Divider()
                    .frame(height: Self.height - 12)
                    .padding(.leading, 10)
                recentsMenu(recents)
            }
        }
        .padding(.leading, Self.inset)
        .padding(.trailing, recents.isEmpty ? Self.height / 2 - 2 : Self.inset)
        .frame(height: Self.height)
        .timerCapsule(tint: model.running.map { model.ledger.color(ofProject: $0.entry.projectID) })
        .disabled(model.isReadOnly)
    }

    private func recentsMenu(_ recents: [Combination]) -> some View {
        Menu {
            Section(model.running == nil ? "Start" : "Switch To") {
                ForEach(recents, id: \.self) { combination in
                    Button(title(of: combination)) {
                        model.startTimer(combination, undoManager: undoManager)
                    }
                    .disabled(model.running.map { combination.matches($0.entry) } ?? false)
                }
            }
        } label: {
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: Self.height - 2 * Self.inset)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(model.running == nil ? "Start a timer with a recent project and tags" : "Switch to a recent project and tags")
    }

    private func title(of combination: Combination) -> String {
        let project = model.ledger.projectTitle(combination.projectID)
        return combination.tags.isEmpty ? project : "\(project) · \(combination.tags.joined(separator: ", "))"
    }
}

/// The running timer's project, note or tags, and time so far.
private struct RunningTimerSummary: View {
    let model: AppModel
    let running: ResolvedEntry

    var body: some View {
        let entry = running.entry
        HStack(spacing: 6) {
            Circle()
                .fill(model.ledger.color(ofProject: entry.projectID))
                .frame(width: 8, height: 8)
            Text(model.ledger.projectTitle(entry.projectID))
                .fontWeight(.medium)
                .foregroundStyle(entry.projectID == nil ? .secondary : .primary)
                .lineLimit(1)
                .frame(maxWidth: 200, alignment: .leading)
            if !subtitle.isEmpty {
                Text(subtitle)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: 160, alignment: .leading)
            }
            Text(Format.duration(model.duration(of: running)))
                .fontWeight(.semibold)
                .monospacedDigit()
                .padding(.leading, 4)
        }
        .help(tooltip)
    }

    /// The note, or the tags if there's no note.
    private var subtitle: String {
        running.entry.note.isEmpty ? running.entry.tags.joined(separator: ", ") : running.entry.note
    }

    private var tooltip: String {
        var lines = ["Started \(Format.time(running.start, zone: running.entry.timeZone))"]
        if !running.entry.note.isEmpty, !running.entry.tags.isEmpty {
            lines.append(running.entry.tags.joined(separator: ", "))
        }
        return lines.joined(separator: "\n")
    }
}

/// A white symbol on a colored circle, the timer's start or stop button,
/// filling the capsule's height but for its inset.
private struct TimerGlyph: View {
    let title: String
    let systemImage: String
    let color: Color

    private static let diameter = TimerCapsule.height - 2 * TimerCapsule.inset

    var body: some View {
        Label(title, systemImage: systemImage)
            .labelStyle(.iconOnly)
            .font(.system(size: (Self.diameter * 0.4).rounded(), weight: .heavy))
            .foregroundStyle(.white)
            // The play triangle's weight sits left of its middle.
            .offset(x: systemImage == "play.fill" ? 1 : 0)
            .frame(width: Self.diameter, height: Self.diameter)
            .background(color, in: Circle())
    }
}

/// Plain, dimmed while pressed.
private struct TimerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

extension View {
    /// A capsule behind the timer: glass from macOS 26, before that a fill,
    /// tinted with the running timer's project color.
    @ViewBuilder
    func timerCapsule(tint: Color?) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            glassEffect(tint.map { Glass.regular.tint($0.opacity(0.3)) } ?? .regular, in: .capsule)
        } else {
            filledTimerCapsule(tint: tint)
        }
        #else
        filledTimerCapsule(tint: tint)
        #endif
    }

    private func filledTimerCapsule(tint: Color?) -> some View {
        let color = tint ?? .primary
        return background(color.opacity(tint == nil ? 0.06 : 0.14), in: Capsule())
            .overlay {
                Capsule().strokeBorder(color.opacity(tint == nil ? 0.12 : 0.35), lineWidth: 1)
            }
    }

    /// The timer as the toolbar's principal item. From macOS 26 the timer
    /// draws its own glass, so the toolbar's glass behind the item, which
    /// would take in the padding that centers it, is off.
    @ViewBuilder
    func timerToolbar(_ timer: some View) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            toolbar {
                ToolbarItem(placement: .principal) {
                    timer
                }
                .sharedBackgroundVisibility(.hidden)
            }
        } else {
            toolbar {
                ToolbarItem(placement: .principal) {
                    timer
                }
            }
        }
        #else
        toolbar {
            ToolbarItem(placement: .principal) {
                timer
            }
        }
        #endif
    }
}

#if DEBUG
#Preview("Timer") {
    VStack(spacing: 16) {
        TimerCapsule(model: PreviewData.model(PreviewData.stoppedLedger))
        TimerCapsule(model: PreviewData.model())
        TimerCapsule(model: PreviewData.model(Ledger()))
        TimerCapsule(model: PreviewData.model(state: .iCloudUnavailable))
    }
    .fixedSize()
    .padding(40)
}
#endif
#endif
