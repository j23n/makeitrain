#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
import TrackerCore
@testable import MacUI
@testable import TrackerKit

/// Prints where the toolbar puts the timer, the title and the other items,
/// in a few arrangements, to find the one that centers the timer between
/// the title and the items. Temporary.
@Suite(.serialized)
@MainActor
struct ToolbarLayoutProbe {
    @Test func probe() async {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        let model = PreviewData.model()
        print("PROBE macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
        show("app, entries", MainWindow(model: model, screen: .entries))
        show("app, timeline", MainWindow(model: model, screen: .timeline))
        show("principal, no padding", ProbeWindow(arrangement: .principal))
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            show("outer spacers, automatic", ProbeWindow(arrangement: .outerAutomatic))
            show("outer spacers, primary action", ProbeWindow(arrangement: .outerPrimaryAction))
            show("inner spacers, automatic", ProbeWindow(arrangement: .innerAutomatic))
            show("inner spacers, primary action", ProbeWindow(arrangement: .innerPrimaryAction))
        }
        #endif
    }

    private func show(_ name: String, _ view: some View) {
        let controller = NSHostingController(rootView: view)
        controller.sceneBridgingOptions = [.toolbars, .title]
        controller.sizingOptions = []
        let window = NSWindow(contentViewController: controller)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.toolbarStyle = .unified
        window.setContentSize(CGSize(width: 1200, height: 740))
        window.makeKeyAndOrderFront(nil)
        for _ in 0..<5 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        }
        print("PROBE == \(name), window \(Int(window.frame.width)) wide")
        if let root = window.contentView?.superview {
            if let split = Self.first(NSSplitView.self, in: root) {
                for (index, pane) in split.arrangedSubviews.enumerated() {
                    let rect = pane.convert(pane.bounds, to: nil)
                    print("PROBE   pane \(index): x \(Int(rect.minX))...\(Int(rect.maxX))")
                }
            }
            dump(root, window: window, depth: 0)
        }
        window.orderOut(nil)
        window.contentViewController = nil
    }

    private func dump(_ view: NSView, window: NSWindow, depth: Int) {
        let rect = view.convert(view.bounds, to: nil)
        let name = String(describing: type(of: view))
        let inBar = rect.minY > window.frame.height - 90 && rect.height < 70 && rect.width > 4
        let interesting = view is NSControl || name.contains("Hosting") || name.contains("Title")
            || name.contains("ToolbarItem") || name.contains("Glass")
        if inBar, interesting, rect.width < window.frame.width * 0.8 {
            var text = ""
            if let field = view as? NSTextField, !field.stringValue.isEmpty {
                text = " \"\(field.stringValue)\""
            }
            print("PROBE   \(String(repeating: ".", count: depth))\(name.prefix(70)) x \(Int(rect.minX))...\(Int(rect.maxX)) y \(Int(rect.minY)) h \(Int(rect.height))\(text)")
        }
        for subview in view.subviews where !subview.isHidden {
            dump(subview, window: window, depth: depth + 1)
        }
    }

    private static func first<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
        if let match = view as? T { return match }
        for subview in view.subviews {
            if let match = first(type, in: subview) { return match }
        }
        return nil
    }
}

/// A window like the main window, with the entries screen's toolbar items
/// and a 222-point stand-in for the timer, arranged one of several ways.
private struct ProbeWindow: View {
    enum Arrangement {
        case principal, outerAutomatic, outerPrimaryAction, innerAutomatic, innerPrimaryAction
    }

    let arrangement: Arrangement
    @State private var search = ""

    var body: some View {
        NavigationSplitView {
            List {
                Text("Timeline")
                Text("Entries")
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
        } detail: {
            detail
        }
        .navigationTitle("Entries")
    }

    private var marker: some View {
        Capsule().fill(.orange).frame(width: 222, height: 28)
    }

    @ViewBuilder
    private var detail: some View {
        let content = Color.clear
            .searchable(text: $search, placement: .toolbar)
        switch arrangement {
        case .principal:
            content
                .toolbar { items }
                .toolbar {
                    ToolbarItem(placement: .principal) { marker }
                }
        default:
            #if compiler(>=6.2)
            if #available(macOS 26.0, *) {
                spaced(content)
            }
            #else
            content
            #endif
        }
    }

    #if compiler(>=6.2)
    @available(macOS 26.0, *)
    @ViewBuilder
    private func spaced(_ content: some View) -> some View {
        switch arrangement {
        case .outerAutomatic:
            content
                .toolbar { items }
                .toolbar {
                    ToolbarSpacer(.flexible)
                    ToolbarItem { marker }.sharedBackgroundVisibility(.hidden)
                    ToolbarSpacer(.flexible)
                }
        case .outerPrimaryAction:
            content
                .toolbar { items }
                .toolbar {
                    ToolbarSpacer(.flexible, placement: .primaryAction)
                    ToolbarItem(placement: .primaryAction) { marker }.sharedBackgroundVisibility(.hidden)
                    ToolbarSpacer(.flexible, placement: .primaryAction)
                }
        case .innerAutomatic:
            content
                .toolbar {
                    ToolbarSpacer(.flexible)
                    ToolbarItem { marker }.sharedBackgroundVisibility(.hidden)
                    ToolbarSpacer(.flexible)
                    items
                }
        case .innerPrimaryAction:
            content
                .toolbar {
                    ToolbarSpacer(.flexible, placement: .primaryAction)
                    ToolbarItem(placement: .primaryAction) { marker }.sharedBackgroundVisibility(.hidden)
                    ToolbarSpacer(.flexible, placement: .primaryAction)
                    items
                }
        case .principal:
            content
        }
    }
    #endif

    @ToolbarContentBuilder
    private var items: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {} label: {
                Label("New Entry", systemImage: "plus")
            }
            Menu {
                Button("CSV File…") {}
            } label: {
                Label("Import", systemImage: "square.and.arrow.down")
            }
        }
    }
}
#endif
