#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
import TrackerCore
@testable import MacUI
@testable import TrackerKit

/// Prints how much space the main window's toolbar leaves on either side of
/// the timer, between the title and the next item. Temporary.
@Suite(.serialized)
@MainActor
struct ToolbarLayoutProbe {
    @Test func probe() async {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        let model = PreviewData.model()
        print("PROBE macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
        for width in [1024.0, 1280.0] {
            for screen in [Screen.entries, .timeline, .reports] {
                show("\(screen.rawValue), \(Int(width)) wide", MainWindow(model: model, screen: screen), width: width)
            }
        }
    }

    private func show(_ name: String, _ view: some View, width: CGFloat) {
        let controller = NSHostingController(rootView: view)
        controller.sceneBridgingOptions = [.toolbars, .title]
        controller.sizingOptions = []
        let window = NSWindow(contentViewController: controller)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.toolbarStyle = .unified
        window.setContentSize(CGSize(width: width, height: 700))
        window.makeKeyAndOrderFront(nil)
        // As after each event in the app, which measures the toolbar again.
        for _ in 0..<6 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
            window.update()
        }
        guard let root = window.contentView?.superview else { return }
        let capsule = Self.all(in: root).first { String(describing: type(of: $0)).contains("GapReaderView") }
        let title = Self.all(in: root).compactMap { $0 as? NSTextField }.first { $0.stringValue == window.title }
        guard let capsule, let title else {
            print("PROBE \(name): window \(Int(window.frame.width)), capsule \(capsule != nil), title \(title != nil)")
            window.orderOut(nil)
            return
        }
        let capsuleFrame = capsule.convert(capsule.bounds, to: nil)
        let titleEnd = title.convert(title.bounds, to: nil).maxX
        let band = capsuleFrame.minY - 20...capsuleFrame.maxY + 20
        let next = Self.all(in: root)
            .filter { $0 is NSControl || String(describing: type(of: $0)).contains("HostingView") }
            .filter { !$0.isHidden && $0.window != nil }
            .map { $0.convert($0.bounds, to: nil) }
            .filter { band.contains($0.midY) && $0.minX >= capsuleFrame.maxX - 1 && $0.width >= 12 }
            .map(\.minX)
            .min()
        let nextText = next.map { "\(Int($0))" } ?? "none"
        let gaps = next.map { "left \(Int(capsuleFrame.minX - titleEnd)), right \(Int($0 - capsuleFrame.maxX))" } ?? ""
        print("PROBE \(name): window \(Int(window.frame.width)), title ends \(Int(titleEnd)), capsule \(Int(capsuleFrame.minX))...\(Int(capsuleFrame.maxX)) h \(Int(capsuleFrame.height)), next item \(nextText); \(gaps)")
        window.orderOut(nil)
        window.contentViewController = nil
    }

    private static func all(in view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap { all(in: $0) }
    }
}
#endif
