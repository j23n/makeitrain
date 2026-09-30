#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
import TrackerCore
@testable import MacUI
@testable import TrackerKit

/// Prints where the main window's toolbar puts its items, and the font and
/// place of the window's own title in a plain window. Temporary.
@Suite(.serialized)
@MainActor
struct ToolbarLayoutProbe {
    @Test func probe() async {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        let model = PreviewData.model()
        print("PROBE macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
        for screen in [Screen.entries, .timeline, .reports] {
            show(screen.rawValue, MainWindow(model: model, screen: screen))
        }
        show("system title", PlainWindow())
    }

    private func show(_ name: String, _ view: some View) {
        let controller = NSHostingController(rootView: view)
        controller.sceneBridgingOptions = [.toolbars, .title]
        controller.sizingOptions = []
        let window = NSWindow(contentViewController: controller)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.toolbarStyle = .unified
        window.setContentSize(CGSize(width: 1200, height: 700))
        window.makeKeyAndOrderFront(nil)
        for _ in 0..<6 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
            window.update()
        }
        print("PROBE == \(name), window \(Int(window.frame.width)) wide, title \"\(window.title)\"")
        guard let root = window.contentView?.superview else { return }
        for view in Self.all(in: root) {
            if let field = view as? NSTextField, !field.stringValue.isEmpty, field.stringValue == window.title {
                let frame = field.convert(field.bounds, to: nil)
                print("PROBE   title field x \(Int(frame.minX))...\(Int(frame.maxX)), font \(field.font?.fontName ?? "?") \(field.font?.pointSize ?? 0)")
            }
        }
        let viewers = Self.all(in: root)
            .filter { String(describing: type(of: $0)).contains("ItemViewer") && !$0.isHidden }
            .sorted { $0.convert($0.bounds, to: nil).minX < $1.convert($1.bounds, to: nil).minX }
        for viewer in viewers {
            let frame = viewer.convert(viewer.bounds, to: nil)
            let content = Self.all(in: viewer)
                .filter { $0 !== viewer && ($0 is NSControl || String(describing: type(of: $0)).contains("HostingView")) && !$0.isHidden }
                .map { $0.convert($0.bounds, to: nil) }
                .filter { $0.width >= 4 }
            let left = content.map(\.minX).min()
            let right = content.map(\.maxX).max()
            let contentText = left.flatMap { l in right.map { r in "\(Int(l))...\(Int(r)) (\(Int(r - l)) wide)" } } ?? "empty"
            print("PROBE   item x \(Int(frame.minX))...\(Int(frame.maxX)): content \(contentText)")
        }
        for split in Self.all(in: window.contentView ?? root).compactMap({ $0 as? NSSplitView }).filter(\.isVertical) {
            let panes = split.arrangedSubviews.map { pane -> String in
                let frame = pane.convert(pane.bounds, to: nil)
                return "\(Int(frame.minX))...\(Int(frame.maxX))"
            }
            print("PROBE   panes \(panes.joined(separator: " | "))")
        }
        window.orderOut(nil)
        window.contentViewController = nil
    }

    private static func all(in view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap { all(in: $0) }
    }
}

/// A window like the main window with its own title in the toolbar.
private struct PlainWindow: View {
    var body: some View {
        NavigationSplitView {
            List {
                Text("Timeline")
                Text("Entries")
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
        } detail: {
            Color.clear
                .toolbar {
                    ToolbarItem {
                        Button {} label: {
                            Label("New Entry", systemImage: "plus")
                        }
                    }
                }
        }
        .navigationTitle("Entries")
    }
}
#endif
