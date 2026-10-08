#if os(macOS)
import AppKit
import SwiftUI
import TrackerKit

/// The command line over any app, as the shortcut opens it: a panel in the
/// middle of the screen that takes the keyboard without bringing the app's
/// windows forward, and goes away after Return or Escape.
@MainActor
final class CommandPanel: NSObject, NSWindowDelegate {
    static let shared = CommandPanel()

    private var panel: NSPanel?
    private var line: CommandLineModel?

    /// Shows the panel, or hides it if it's showing.
    func toggle() {
        if let panel, panel.isVisible {
            hide()
            return
        }
        show()
    }

    func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            let size = panel.frame.size
            panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.maxY - frame.height * 0.28 - size.height))
        }
        line?.refresh()
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() {
        line?.clear()
        panel?.orderOut(nil)
    }

    /// Hides the panel when it loses the keyboard, as a popover goes away.
    nonisolated func windowDidResignKey(_ notification: Notification) {
        MainActor.assumeIsolated {
            hide()
        }
    }

    private func makePanel() -> NSPanel {
        let line = CommandLineModel(model: AppModel.shared)
        self.line = line
        let panel = KeyPanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 200),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = NSColor(Theme.popover)
        let root = CommandBar(line: line) { [weak self] in
            self?.hide()
        }
        .frame(width: 560)
        .background(Theme.popover)
        let hosting = NSHostingController(rootView: root)
        hosting.sizingOptions = [.preferredContentSize]
        panel.contentViewController = hosting
        panel.delegate = self
        return panel
    }
}

/// A panel that can take the keyboard though it doesn't activate the app.
private final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}
#endif
