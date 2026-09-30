#if os(macOS)
import AppKit
import SwiftUI
import TrackerCore
import TrackerKit

/// The timer in the main window's toolbar, in the middle of the space
/// between the title and the next item.
///
/// The toolbar centers its principal item in its part of the toolbar, which
/// puts it off the middle of the free space whenever the items on one side
/// take more room than the title on the other, as the entries screen's three
/// buttons do; where there isn't room to center it, the toolbar puts it
/// right after the title. Padding on one side moves it, by as much as the
/// timer sees it move.
struct ToolbarTimer: View {
    let model: AppModel
    /// Leading padding if positive, trailing if negative.
    @State private var padding: CGFloat = 0

    var body: some View {
        TimerCapsule(model: model)
            .fixedSize()
            .background {
                ToolbarGapReader { newPadding in
                    padding = newPadding
                }
            }
            .padding(.leading, max(0, padding))
            .padding(.trailing, max(0, -padding))
    }
}

/// Works out the padding that puts the timer in the middle of its space,
/// from where it sees the timer end up.
///
/// How far padding moves the timer depends on how the toolbar places it:
/// half as far when it centers the item, which the padding widens on both
/// sides, and as far when the item sits against something. It starts from
/// the first, and goes by what it sees after each change. It makes at most
/// eight changes for the same space, so the timer can't wander.
struct TimerCentering {
    /// Leading padding if positive, trailing if negative.
    private(set) var padding: CGFloat = 0
    private var gain: CGFloat = 0.5
    private var space: ClosedRange<CGFloat>?
    private var last: (padding: CGFloat, center: CGFloat)?
    private var changes = 0

    /// The new padding for a timer `width` wide whose middle is at `center`,
    /// in `space`, or nil to keep the padding. No space means there's
    /// nothing to center in, and no padding.
    mutating func update(center: CGFloat, width: CGFloat, space measured: ClosedRange<CGFloat>?) -> CGFloat? {
        guard let measured else {
            space = nil
            last = nil
            guard padding != 0 else { return nil }
            padding = 0
            return 0
        }
        let current = measured.lowerBound.rounded()...measured.upperBound.rounded()
        if current != space {
            space = current
            last = nil
            gain = 0.5
            changes = 0
        }
        if let last, abs(padding - last.padding) >= 1 {
            let seen = (center - last.center) / (padding - last.padding)
            if seen > 0.2 {
                gain = min(seen, 2)
            }
        }
        last = (padding, center)
        let error = (current.lowerBound + current.upperBound) / 2 - center
        guard abs(error) >= 1, changes < 8 else { return nil }
        let room = max(0, (current.upperBound - current.lowerBound - width) / 2)
        let next = min(max(padding + error / gain, -room), room).rounded()
        guard abs(next - padding) >= 1 else { return nil }
        changes += 1
        padding = next
        return next
    }
}

/// Reports the padding that moves the toolbar item it's in to the middle of
/// the space between the title and the next item. It finds them from the
/// frames of the toolbar's views: the window title's text field, the item's
/// neighbors in the row the title shares with the items, and the controls
/// and SwiftUI views in them. The toolbar's sections end where the window's
/// panes meet, as beside an inspector. It reports no padding if it can't
/// find the title.
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

    /// Called when the timer is drawn again, as with a new padding.
    func updateNSView(_ view: GapReaderView, context: Context) {
        view.report = report
        view.redrawn()
    }
}

private final class GapReaderView: NSView {
    var report: ((CGFloat) -> Void)?
    private var centering = TimerCentering()
    /// When it last reported, to stop if the toolbar keeps moving the timer.
    private var reports: [Date] = []
    private var paused = false
    /// What it last measured. It acts only on what holds still from one
    /// measurement to the next, since the toolbar lays the item out again
    /// a moment after the timer changes size.
    private var last: Layout?
    /// What it measured before its last change, and when it made it: until
    /// the layout shows the change, or a moment has passed, it waits.
    private var beforeChange: (layout: Layout, time: Date)?

    private struct Layout: Equatable {
        var item: CGRect
        var timer: CGRect
        var space: ClosedRange<CGFloat>?
    }

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
        center.addObserver(self, selector: #selector(windowChanged), name: NSWindow.didResizeNotification, object: window)
        if let toolbar = window.toolbar {
            center.addObserver(self, selector: #selector(windowChanged), name: NSToolbar.willAddItemNotification, object: toolbar)
            center.addObserver(self, selector: #selector(windowChanged), name: NSToolbar.didRemoveItemNotification, object: toolbar)
        }
        windowChanged()
    }

    @objc private func windowChanged() {
        paused = false
        scheduleMeasuring()
    }

    func redrawn() {
        scheduleMeasuring()
    }

    /// Measures on the next turn of the run loop, also while the window is
    /// being resized.
    @objc func scheduleMeasuring() {
        measureAgain(after: 0)
    }

    private func measureAgain(after delay: TimeInterval) {
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(measure), object: nil)
        perform(#selector(measure), with: nil, afterDelay: delay, inModes: [.common])
    }

    @objc private func measure() {
        guard !paused, let window else { return }
        let found = window.title.isEmpty ? nil : place(title: window.title)
        let item = found?.item ?? self
        let layout = Layout(
            item: item.convert(item.bounds, to: nil).integral,
            timer: convert(bounds, to: nil).integral,
            space: found.flatMap { space(in: window, around: $0) }.map { $0.lowerBound.rounded()...$0.upperBound.rounded() }
        )
        if let beforeChange, layout == beforeChange.layout, Date().timeIntervalSince(beforeChange.time) < 0.3 {
            measureAgain(after: 0.05)
            return
        }
        guard layout == last else {
            last = layout
            measureAgain(after: 0.05)
            return
        }
        beforeChange = nil
        let timer = convert(bounds, to: nil)
        guard let padding = centering.update(center: timer.midX, width: timer.width, space: layout.space) else {
            return
        }
        let now = Date()
        reports = reports.filter { now.timeIntervalSince($0) < 2 } + [now]
        if reports.count > 20 {
            // Something keeps moving it; leave it until the window changes.
            paused = true
        }
        beforeChange = (layout, now)
        last = nil
        report?(padding)
    }

    /// The space the timer has: from the title, or a pane's edge, to the
    /// next item, or a pane's edge, or the end of the row.
    private func space(in window: NSWindow, around found: Place) -> ClosedRange<CGFloat>? {
        let itemFrame = found.item.convert(found.item.bounds, to: nil)
        guard itemFrame.width < window.frame.width * 0.7 else { return nil }
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
        guard var start = left else { return nil }
        var end = right ?? found.row.convert(found.row.bounds, to: nil).maxX
        if let content = window.contentView {
            for edge in Self.paneEdges(in: content, width: window.frame.width) {
                if edge <= itemFrame.minX + 1 {
                    start = max(start, edge)
                } else if edge >= itemFrame.maxX - 1 {
                    end = min(end, edge)
                }
            }
        }
        return start < end ? start...end : nil
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

    /// Where side-by-side panes end inside the window, in window coordinates,
    /// but for the ends of the split views they're in. From macOS 26 the
    /// middle pane runs under the sidebar and the inspector, so it's their
    /// edges that count. Split views sit near the top, so it doesn't look
    /// inside scroll views.
    private static func paneEdges(in view: NSView, width: CGFloat) -> [CGFloat] {
        if view is NSScrollView {
            return []
        }
        var edges: [CGFloat] = []
        if let split = view as? NSSplitView, split.isVertical {
            let ends = split.convert(split.bounds, to: nil)
            for pane in split.arrangedSubviews where !pane.isHidden && pane.frame.width > 1 {
                let frame = pane.convert(pane.bounds, to: nil)
                for edge in [frame.minX, frame.maxX]
                where edge > 1 && edge < width - 1 && abs(edge - ends.minX) > 1 && abs(edge - ends.maxX) > 1 {
                    edges.append(edge)
                }
            }
        }
        for subview in view.subviews {
            edges += paneEdges(in: subview, width: width)
        }
        return edges
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
