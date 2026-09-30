#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
import TrackerCore
@testable import MacUI
@testable import TrackerKit

/// How long the entries screen, and each kind of cell in it, takes to show
/// in a window, printed to the log. For finding out why the screen is slow
/// to open with only a few dozen entries.
@Suite(.serialized)
@MainActor
struct EntriesTimings {
    /// The sample week plus the latest entries of the large sample, 30 in all.
    static var ledger: Ledger {
        let sample = PreviewData.ledger
        let extra = PreviewData.largeLedger.entries.values.sorted { $0.start > $1.start }.prefix(16)
        return Ledger(
            clients: Array(sample.clients.values),
            projects: Array(sample.projects.values),
            entries: Array(sample.entries.values) + extra
        )
    }

    @Test func timeTheEntriesScreen() async {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        let model = PreviewData.model(Self.ledger)
        let flagged = model.overlaps.flagged
        let rows = model.resolved.reversed().map { entry in
            EntryRow(entry, projectTitle: model.ledger.projectTitle(entry.entry.projectID), flagged: flagged.contains(entry.id))
        }
        let projectTags = model.projectTags
        print("TIMING \(rows.count) rows on macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")

        measure("main window, timeline", MainWindow(model: model, screen: .timeline), toolbar: true)
        measure("main window, entries", MainWindow(model: model, screen: .entries), toolbar: true)
        measure("main window, reports", MainWindow(model: model, screen: .reports), toolbar: true)
        measure("entries view alone", EntriesView(model: model), toolbar: true)
        measure("filter bar", EntriesFilterBar(model: model, filter: .constant(EntriesFilter()), rows: rows))
        measure("table, text only", Table(rows) {
            TableColumn("Start") { row in Text(Format.time(row.start, zone: row.zone)) }
            TableColumn("End") { row in Text(row.entry.end.map { Format.time($0, zone: row.zone) } ?? "Running") }
            TableColumn("Project") { row in Text(row.projectTitle) }
            TableColumn("Tags") { row in Text(row.tagsText) }
            TableColumn("Note") { row in Text(row.note) }
        })
        measure("30 start and 30 end pickers", cells(rows) { row in
            HStack {
                EntryStartCell(model: model, row: row)
                EntryEndCell(model: model, row: row)
            }
        })
        measure("30 start pickers", cells(rows) { row in EntryStartCell(model: model, row: row) })
        measure("30 plain date pickers", cells(rows) { row in
            DatePicker("Start", selection: .constant(row.start.date), displayedComponents: [.date, .hourAndMinute])
                .labelsHidden()
                .datePickerStyle(.compact)
        })
        measure("30 tag fields", cells(rows) { row in
            TagField(tags: row.entry.entry.tags, suggestions: projectTags[row.entry.entry.projectID] ?? [], placeholder: "", bordered: false) { _ in }
        })
        measure("30 note fields", cells(rows) { row in CommitField(title: "", value: row.note) { _ in } })
        measure("30 project cells", cells(rows) { row in EntryProjectCell(model: model, row: row) })
        measure("30 status icons", cells(rows) { row in EntryStatusIcon(row: row) })
    }

    private func cells<Cell: View>(_ rows: [EntryRow], @ViewBuilder cell: @escaping (EntryRow) -> Cell) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(rows) { row in
                cell(row)
            }
        }
    }

    /// Shows the view in a window twice, each time timing how long it takes
    /// to lay out and draw, and then how long what SwiftUI puts off to the
    /// next turns of the run loop takes.
    private func measure(_ name: String, _ view: some View, toolbar: Bool = false) {
        var results: [String] = []
        for _ in 0..<2 {
            let clock = ContinuousClock()
            var window: NSWindow?
            let shown = clock.measure {
                let controller = NSHostingController(rootView: view)
                if toolbar {
                    controller.sceneBridgingOptions = [.toolbars, .title]
                }
                controller.sizingOptions = []
                let newWindow = NSWindow(contentViewController: controller)
                newWindow.styleMask = [.titled, .closable, .miniaturizable, .resizable]
                newWindow.setContentSize(CGSize(width: 1200, height: 740))
                newWindow.makeKeyAndOrderFront(nil)
                newWindow.layoutIfNeeded()
                newWindow.displayIfNeeded()
                window = newWindow
            }
            let settled = clock.measure {
                for _ in 0..<20 {
                    RunLoop.main.run(mode: .default, before: Date())
                    window?.layoutIfNeeded()
                    window?.displayIfNeeded()
                }
            }
            window?.orderOut(nil)
            window?.contentViewController = nil
            results.append("\(milliseconds(shown)) + \(milliseconds(settled)) ms")
        }
        print("TIMING \(name): \(results.joined(separator: ", again "))")
    }

    private func milliseconds(_ duration: Duration) -> Int {
        let (seconds, attoseconds) = duration.components
        return Int(seconds) * 1000 + Int(attoseconds / 1_000_000_000_000_000)
    }
}
#endif
