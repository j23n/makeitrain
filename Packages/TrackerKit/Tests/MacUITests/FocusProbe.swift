#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
import TrackerCore
@testable import MacUI
@testable import TrackerKit

/// PROBE, temporary: where keyboard focus goes when a start time in the
/// entries table is clicked and its calendar opens, printed to the log.
@Suite(.serialized)
@MainActor
struct FocusProbe {
    @Test func clickingAStartTime() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.regular)
        NSApp.finishLaunching()
        NSApp.activate(ignoringOtherApps: true)
        print("PROBE macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")

        let model = PreviewData.model()
        let controller = NSHostingController(rootView: MainWindow(model: model, screen: .entries))
        controller.sceneBridgingOptions = [.toolbars, .title]
        controller.sizingOptions = []
        let window = NSWindow(contentViewController: controller)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(CGSize(width: 1200, height: 740))
        window.makeKeyAndOrderFront(nil)
        pump(1.5)
        log("shown", window)

        DateTimePicker.probe = { print("PROBE picker \($0)") }
        let observation = window.observe(\.firstResponder, options: [.new]) { window, _ in
            MainActor.assumeIsolated {
                print("PROBE first responder now \(Self.describe(window.firstResponder))")
                print(Thread.callStackSymbols.prefix(30).joined(separator: "\n"))
            }
        }

        let tables = Self.findAll(NSTableView.self, in: window.contentView)
        for table in tables {
            print("PROBE table \(type(of: table)) columns \(table.tableColumns.map(\.title)) rows \(table.numberOfRows)")
        }
        guard let table = tables.first(where: { $0.tableColumns.contains { $0.title == "Start" } }),
              let startColumn = table.tableColumns.firstIndex(where: { $0.title == "Start" })
        else {
            print("PROBE no entries table")
            return
        }
        let cell = table.frameOfCell(atColumn: startColumn, row: 0)
        let point = table.convert(NSPoint(x: cell.minX + 30, y: cell.midY), to: nil)
        print("PROBE clicking at \(point) in cell \(cell)")
        click(at: point, in: window)
        for (index, step) in [0.05, 0.1, 0.25, 0.5, 1.0, 2.0].enumerated() {
            pump(step)
            log("after click, step \(index) (\(step) s)", window)
        }

        print("PROBE clicking the field again")
        click(at: point, in: window)
        for (index, step) in [0.1, 0.5, 2.0].enumerated() {
            pump(step)
            log("after second click, step \(index) (\(step) s)", window)
        }

        observation.invalidate()
        DateTimePicker.probe = nil
        window.orderOut(nil)
        window.contentViewController = nil
    }

    private func click(at point: NSPoint, in window: NSWindow) {
        let time = ProcessInfo.processInfo.systemUptime
        for (type, pressure) in [(NSEvent.EventType.leftMouseDown, Float(1)), (.leftMouseUp, Float(0))] {
            if let event = NSEvent.mouseEvent(
                with: type,
                location: point,
                modifierFlags: [],
                timestamp: time,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: pressure
            ) {
                NSApp.postEvent(event, atStart: false)
            }
        }
    }

    /// Handles events and lets SwiftUI catch up, for `seconds`.
    private func pump(_ seconds: Double) {
        let end = Date(timeIntervalSinceNow: seconds)
        repeat {
            if let event = NSApp.nextEvent(matching: .any, until: Date(timeIntervalSinceNow: 0.01), inMode: .default, dequeue: true) {
                NSApp.sendEvent(event)
            }
            RunLoop.main.run(mode: .default, before: Date())
        } while Date() < end
    }

    private func log(_ label: String, _ window: NSWindow) {
        let windows = NSApp.windows.filter(\.isVisible).map { other in
            "\(type(of: other))\(other === window ? " (main)" : "")\(other.isKeyWindow ? " (key)" : "") level \(other.level.rawValue) parent \(other.parent.map { "\(type(of: $0))" } ?? "none")"
        }
        let pickers = Self.findAll(DateTimePicker.self, in: window.contentView).map { "editing \($0.isEditing)" }
        print("PROBE \(label): active \(NSApp.isActive), main key \(window.isKeyWindow), first responder \(Self.describe(window.firstResponder)), pickers \(pickers), windows \(windows)")
    }

    static func describe(_ responder: NSResponder?) -> String {
        guard let responder else { return "nil" }
        if let text = responder as? NSTextView, text.isFieldEditor {
            return "field editor of \(text.delegate.map { String(describing: type(of: $0)) } ?? "nothing")"
        }
        if let picker = responder as? DateTimePicker {
            return "DateTimePicker (editing \(picker.isEditing))"
        }
        return String(describing: type(of: responder))
    }

    static func find<T: NSView>(_ type: T.Type, in view: NSView?) -> T? {
        findAll(type, in: view).first
    }

    static func findAll<T: NSView>(_ type: T.Type, in view: NSView?) -> [T] {
        guard let view else { return [] }
        var found: [T] = []
        if let match = view as? T {
            found.append(match)
        }
        for subview in view.subviews {
            found += findAll(type, in: subview)
        }
        return found
    }
}
#endif
